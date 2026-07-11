--- Detects windrows (straw/hay/grass swaths lying on the ground) on a field and returns them as straight
--- lines (endpoints), so a course can be laid straight along the product for a baler to drive over.
---
--- Windrows live in the Giants densityMapHeight system (the same system that holds bunker silo heaps).
--- We sweep small parallelogram probes across the field boundary with DensityMapHeightUtil, collect the
--- cells that contain a bale-able fill type, then:
---   1. find the windrow (row) direction by sweeping angles and taking the one whose cross-axis projection
---      is the most "peaky" (parallel windrows form sharp regularly-spaced peaks perpendicular to the rows;
---      this handles rows at any angle, including diagonal),
---   2. cluster the cells into lanes (one lane per windrow) by a gap split on the cross coordinate,
---   3. fit each lane to a straight line (its two extreme points along the row axis).
---
---@class WindrowDetector
WindrowDetector = CpObject()

--- Fill types that a baler picks up from a windrow on the ground.
WindrowDetector.PRODUCT_FILL_TYPE_NAMES = { 'STRAW', 'DRYGRASS_WINDROW', 'GRASS_WINDROW', 'SILAGE' }

---@param fieldPolygon table [{x, z}] field boundary in game coordinates
---@param cellSize number|nil probe grid resolution in m (default 2)
---@param minStrawLevel number|nil minimum straw (litres) in a probe cell to count as windrow, not baled residue
function WindrowDetector:init(fieldPolygon, cellSize, minStrawLevel)
    self.logger = Logger('WindrowDetector', Logger.level.debug, CpDebug.DBG_COURSES)
    self.fieldPolygon = fieldPolygon
    self.cellSize = cellSize or 2
    self.minStrawLevel = minStrawLevel or 40
    -- resolve the bale-able fill type indices once
    self.productIndex = {}
    for _, name in ipairs(WindrowDetector.PRODUCT_FILL_TYPE_NAMES) do
        local index = g_fillTypeManager:getFillTypeIndexByName(name)
        if index then
            self.productIndex[index] = name
        end
    end
end

--- Axis-aligned bounding box of the field polygon.
function WindrowDetector:_getFieldBoundingBox()
    local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
    for _, p in ipairs(self.fieldPolygon) do
        if p.x < minX then minX = p.x end
        if p.x > maxX then maxX = p.x end
        if p.z < minZ then minZ = p.z end
        if p.z > maxZ then maxZ = p.z end
    end
    return minX, maxX, minZ, maxZ
end

--- Shortest distance from (x, z) to the field boundary (min over all boundary edges).
function WindrowDetector:_distanceToBoundary(x, z)
    local poly = self.fieldPolygon
    local n = #poly
    local best = math.huge
    for i = 1, n do
        local a, b = poly[i], poly[i % n + 1]
        local dx, dz = b.x - a.x, b.z - a.z
        local len2 = dx * dx + dz * dz
        local t = 0
        if len2 > 0 then
            t = ((x - a.x) * dx + (z - a.z) * dz) / len2
            t = math.max(0, math.min(1, t))
        end
        local cx, cz = a.x + t * dx, a.z + t * dz
        local d = math.sqrt((x - cx) ^ 2 + (z - cz) ^ 2)
        if d < best then best = d end
    end
    return best
end

--- Fill type present in the cellSize x cellSize square centred on (x, z), or nil if it isn't a product.
function WindrowDetector:_productAt(x, z)
    local h = self.cellSize / 2
    -- DensityMapHeightUtil area probe: three corners of a parallelogram (start, width-corner, height-corner)
    local fillType = DensityMapHeightUtil.getFillTypeAtArea(x - h, z - h, x + h, z - h, x - h, z + h)
    if fillType == nil or not self.productIndex[fillType] then
        return nil
    end
    local level = DensityMapHeightUtil.getFillLevelAtArea(fillType, x - h, z - h, x + h, z - h, x - h, z + h)
    if level == nil or level <= 0 then
        return nil
    end
    return fillType, level
end

--- Scan the field for product cells. Returns { {x, z, level, fillType}, ... }.
function WindrowDetector:_scan()
    local minX, maxX, minZ, maxZ = self:_getFieldBoundingBox()
    local cells = {}
    local z = minZ
    while z <= maxZ do
        local x = minX
        while x <= maxX do
            if CpMathUtil.isPointInPolygon(self.fieldPolygon, x, z) then
                local fillType, level = self:_productAt(x, z)
                if fillType then
                    cells[#cells + 1] = { x = x, z = z, level = level, fillType = fillType }
                end
            end
            x = x + self.cellSize
        end
        z = z + self.cellSize
    end
    return cells
end

--- Normalized variance (CV^2) of a 1D histogram of the given coordinate of the cells.
--- Parallel windrows produce sharp, regularly spaced peaks along the cross axis (high CV^2)
--- and a flat spread along the row axis (low CV^2).
function WindrowDetector:_binCV2(cells, get)
    local bins = {}
    for _, c in ipairs(cells) do
        local k = math.floor(get(c) / self.cellSize)
        bins[k] = (bins[k] or 0) + 1
    end
    local sum, sum2, n = 0, 0, 0
    for _, count in pairs(bins) do
        n = n + 1
        sum = sum + count
        sum2 = sum2 + count * count
    end
    if n == 0 then return 0 end
    local mean = sum / n
    return (sum2 / n - mean * mean) / (mean * mean + 1e-9)
end

--- How strongly the straw is periodic at `periodBins` metres when projected onto the cross axis (cx, cz):
--- the normalized autocorrelation of the level-weighted cross-density profile at lag = periodBins. Near 1
--- when the windrows line up at that spacing along this direction, near 0 otherwise. Used to lock the row
--- angle using the KNOWN spacing, which is far more reliable on contiguous straw than a generic peakiness.
function WindrowDetector:_periodicity(cells, cx, cz, periodBins)
    local umin = math.huge
    for _, c in ipairs(cells) do
        local uu = c.x * cx + c.z * cz
        if uu < umin then umin = uu end
    end
    local nb = 1
    for _, c in ipairs(cells) do
        local b = 1 + math.floor(c.x * cx + c.z * cz - umin)
        if b > nb then nb = b end
    end
    local prof = {}
    for i = 1, nb do prof[i] = 0 end
    for _, c in ipairs(cells) do
        local b = 1 + math.floor(c.x * cx + c.z * cz - umin)
        prof[b] = prof[b] + c.level
    end
    local mean = 0
    for i = 1, nb do mean = mean + prof[i] end
    mean = mean / nb
    local num, den = 0, 0
    for i = 1, nb do
        local d = prof[i] - mean
        den = den + d * d
        if i + periodBins <= nb then num = num + d * (prof[i + periodBins] - mean) end
    end
    return den > 0 and num / den or 0
end

--- Fraction of the field boundary, offset inward by `distance`, that lands on straw. ~1 for a true headland
--- ring (straw follows the whole perimeter); low for interior rows, which only cross the offset ring at
--- sparse points even when they run parallel to an edge and share a single distance-to-boundary.
function WindrowDetector:_ringCoverage(distance)
    local poly = self.fieldPolygon
    local n = #poly
    local total, hit = 0, 0
    for i = 1, n do
        local a, b = poly[i], poly[i % n + 1]
        local dx, dz = b.x - a.x, b.z - a.z
        local len = math.sqrt(dx * dx + dz * dz)
        if len > 1e-6 then
            local nx, nz = -dz / len, dx / len -- edge normal; flip so it points into the field
            local mx, mz = (a.x + b.x) / 2, (a.z + b.z) / 2
            if not CpMathUtil.isPointInPolygon(poly, mx + nx * 2, mz + nz * 2) then nx, nz = -nx, -nz end
            local steps = math.max(1, math.floor(len / 3))
            for s = 0, steps do
                local t = s / steps
                local ex, ez = a.x + dx * t + nx * distance, a.z + dz * t + nz * distance
                if CpMathUtil.isPointInPolygon(poly, ex, ez) then
                    total = total + 1
                    local ft, lvl = self:_productAt(ex, ez)
                    if ft and lvl >= self.minStrawLevel then hit = hit + 1 end
                end
            end
        end
    end
    return total > 0 and hit / total or 0
end

--- Detect the headland rings. Straw that follows the field boundary sits at fixed distances from the edge
--- and forms sharp, regularly-spaced peaks in the distance-to-boundary histogram (interior rows smear).
--- Stores distToBoundary on each cell (for classification) and returns the ring centre-distances (nearest
--- first) plus the spacing between them.
---@param cells table product cells (distToBoundary is written onto each)
---@return table ringDistances distance from the boundary of each headland ring, ascending
---@return number ringSpacing spacing between rings (0 if fewer than 2 rings)
function WindrowDetector:_detectHeadlandRings(cells)
    local binW, maxBin = 1, 60
    local hist = {}
    for i = 1, maxBin do hist[i] = 0 end
    local maxH = 0
    for _, c in ipairs(cells) do
        c.distToBoundary = self:_distanceToBoundary(c.x, c.z)
        local b = 1 + math.floor(c.distToBoundary / binW)
        if b >= 1 and b <= maxBin then
            hist[b] = hist[b] + 1
            if hist[b] > maxH then maxH = hist[b] end
        end
    end
    -- ring bins stand clearly above the interior background; group nearby above-threshold bins into one ring
    local threshold = 0.4 * maxH
    local candidates, sumWD, sumW, lastBin = {}, 0, 0, nil
    for i = 1, maxBin do
        if hist[i] >= threshold then
            if lastBin and (i - lastBin) > 4 then
                candidates[#candidates + 1] = sumWD / sumW
                sumWD, sumW = 0, 0
            end
            sumWD = sumWD + (i - 0.5) * binW * hist[i]
            sumW = sumW + hist[i]
            lastBin = i
        end
    end
    if sumW > 0 then candidates[#candidates + 1] = sumWD / sumW end
    -- Reject phantom rings: a distance-histogram spike is only a real headland ring if straw actually WRAPS
    -- the boundary at that distance. Interior rows parallel to an edge spike the histogram too, but their
    -- offset ring is mostly bare -> filtered out here, so the course goes straight down the rows.
    local rings = {}
    for _, d in ipairs(candidates) do
        local cov = self:_ringCoverage(d)
        self.logger:debug('  headland candidate %.0fm: %.0f%% boundary-wrap coverage', d, cov * 100)
        if cov >= 0.6 then rings[#rings + 1] = d end
    end
    local ringSpacing = 0
    if #rings >= 2 then
        local gaps = {}
        for i = 2, #rings do gaps[#gaps + 1] = rings[i] - rings[i - 1] end
        table.sort(gaps)
        ringSpacing = gaps[math.ceil(#gaps / 2)]
    end
    return rings, ringSpacing
end

--- Read the windrows as the density RIDGES in the straw: build a density grid, keep each windrow's crest
--- (cells that are a local maximum ACROSS the ridge, via gradient non-max suppression), then link the crest
--- cells into connected lines and order each along its own principal direction. Nothing global is imposed --
--- each windrow is found where it actually is, at its own angle and curve.
---@return table windrows list of { x1, z1, x2, z2, length, liters, fillTypeName, cells (ordered crest points) }
function WindrowDetector:_readRidges(cells)
    local cs = self.cellSize
    local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
    for _, c in ipairs(cells) do
        if c.x < minX then minX = c.x end
        if c.x > maxX then maxX = c.x end
        if c.z < minZ then minZ = c.z end
        if c.z > maxZ then maxZ = c.z end
    end
    local W = math.floor((maxX - minX) / cs) + 2
    local function key(gx, gz) return gz * W + gx end
    -- density grid (summed straw level per grid cell)
    local raw = {}
    for _, c in ipairs(cells) do
        local gx = math.floor((c.x - minX) / cs)
        local gz = math.floor((c.z - minZ) / cs)
        raw[key(gx, gz)] = (raw[key(gx, gz)] or 0) + c.level
    end
    local function R(gx, gz) return raw[key(gx, gz)] or 0 end
    -- 3x3 smooth to suppress probe noise
    local dens = {}
    for k in pairs(raw) do
        local gz = math.floor(k / W)
        local gx = k - gz * W
        local s = 0
        for dz = -1, 1 do for dx = -1, 1 do s = s + R(gx + dx, gz + dz) end end
        dens[k] = s / 9
    end
    local function Dv(gx, gz) return dens[key(gx, gz)] or 0 end
    local function bilin(px, pz)
        local x0, z0 = math.floor(px), math.floor(pz)
        local fx, fz = px - x0, pz - z0
        return Dv(x0, z0) * (1 - fx) * (1 - fz) + Dv(x0 + 1, z0) * fx * (1 - fz)
             + Dv(x0, z0 + 1) * (1 - fx) * fz + Dv(x0 + 1, z0 + 1) * fx * fz
    end
    -- ridge crests: a cell whose density is a local maximum along the gradient direction (across the ridge)
    local crest = {}
    for k, v in pairs(dens) do
        if v > 0 then
            local gz = math.floor(k / W)
            local gx = k - gz * W
            local gxv = Dv(gx + 1, gz) - Dv(gx - 1, gz)
            local gzv = Dv(gx, gz + 1) - Dv(gx, gz - 1)
            local gm = math.sqrt(gxv * gxv + gzv * gzv)
            if gm < 1e-9 then
                if v >= Dv(gx - 1, gz) and v >= Dv(gx + 1, gz) and v >= Dv(gx, gz - 1) and v >= Dv(gx, gz + 1) then
                    crest[k] = true
                end
            else
                local ux, uz = gxv / gm, gzv / gm
                if v >= bilin(gx + ux, gz + uz) and v >= bilin(gx - ux, gz - uz) then
                    crest[k] = true
                end
            end
        end
    end
    -- connected components (8-connectivity) of crest cells -> one windrow each
    local nbrs = { { -1, -1 }, { 0, -1 }, { 1, -1 }, { -1, 0 }, { 1, 0 }, { -1, 1 }, { 0, 1 }, { 1, 1 } }
    local visited = {}
    local windrows = {}
    for startKey in pairs(crest) do
        if not visited[startKey] then
            visited[startKey] = true
            local comp, stack = {}, { startKey }
            while #stack > 0 do
                local cur = stack[#stack]
                stack[#stack] = nil
                comp[#comp + 1] = cur
                local gz = math.floor(cur / W)
                local gx = cur - gz * W
                for _, nb in ipairs(nbrs) do
                    local nk = key(gx + nb[1], gz + nb[2])
                    if crest[nk] and not visited[nk] then
                        visited[nk] = true
                        stack[#stack + 1] = nk
                    end
                end
            end
            if #comp >= 3 then
                local pts, liters = {}, 0
                for _, kk in ipairs(comp) do
                    local gz = math.floor(kk / W)
                    local gx = kk - gz * W
                    pts[#pts + 1] = { x = minX + (gx + 0.5) * cs, z = minZ + (gz + 0.5) * cs }
                    liters = liters + (dens[kk] or 0)
                end
                -- order the crest points along the component's principal axis (largest covariance eigenvector)
                local mx, mz = 0, 0
                for _, p in ipairs(pts) do mx = mx + p.x; mz = mz + p.z end
                mx, mz = mx / #pts, mz / #pts
                local sxx, szz, sxz = 0, 0, 0
                for _, p in ipairs(pts) do
                    local dx, dz = p.x - mx, p.z - mz
                    sxx = sxx + dx * dx; szz = szz + dz * dz; sxz = sxz + dx * dz
                end
                local tr = sxx + szz
                local disc = math.sqrt(math.max(0, (tr * tr) / 4 - (sxx * szz - sxz * sxz)))
                local lam = tr / 2 + disc
                local ux, uz
                if math.abs(sxz) > 1e-9 then ux, uz = lam - szz, sxz
                elseif sxx >= szz then ux, uz = 1, 0
                else ux, uz = 0, 1 end
                local un = math.sqrt(ux * ux + uz * uz)
                ux, uz = ux / un, uz / un
                for _, p in ipairs(pts) do p.t = (p.x - mx) * ux + (p.z - mz) * uz end
                table.sort(pts, function(a, b) return a.t < b.t end)
                local first, last = pts[1], pts[#pts]
                local length = math.sqrt((last.x - first.x) ^ 2 + (last.z - first.z) ^ 2)
                if length >= cs then
                    windrows[#windrows + 1] = {
                        x1 = first.x, z1 = first.z, x2 = last.x, z2 = last.z,
                        length = length, liters = liters, fillTypeName = 'STRAW',
                        cells = pts, centerline = pts,
                    }
                end
            end
        end
    end
    return windrows
end

--- Order a set of points along their principal axis and return them sorted plus the two extreme points.
function WindrowDetector:_orderAlongAxis(pts)
    local mx, mz = 0, 0
    for _, p in ipairs(pts) do mx = mx + p.x; mz = mz + p.z end
    mx, mz = mx / #pts, mz / #pts
    local sxx, szz, sxz = 0, 0, 0
    for _, p in ipairs(pts) do
        local dx, dz = p.x - mx, p.z - mz
        sxx = sxx + dx * dx; szz = szz + dz * dz; sxz = sxz + dx * dz
    end
    local tr = sxx + szz
    local disc = math.sqrt(math.max(0, (tr * tr) / 4 - (sxx * szz - sxz * sxz)))
    local lam = tr / 2 + disc
    local ux, uz
    if math.abs(sxz) > 1e-9 then ux, uz = lam - szz, sxz
    elseif sxx >= szz then ux, uz = 1, 0
    else ux, uz = 0, 1 end
    local un = math.sqrt(ux * ux + uz * uz)
    ux, uz = ux / un, uz / un
    for _, p in ipairs(pts) do p.t = (p.x - mx) * ux + (p.z - mz) * uz end
    table.sort(pts, function(a, b) return a.t < b.t end)
    return pts, pts[1], pts[#pts]
end

--- Merge windrows lying on the SAME line (same direction and perpendicular offset). One physical windrow
--- split by a straw gap comes back as several crest components; driving each as its own work row makes CP
--- insert a degenerate, reversing "turn" at every gap. Joining them into one row lets the baler drive
--- straight through.
function WindrowDetector:_mergeCollinear(windrows)
    local groups = {}
    for _, w in ipairs(windrows) do
        local dx, dz = w.x2 - w.x1, w.z2 - w.z1
        local l = math.sqrt(dx * dx + dz * dz)
        if l > 1e-6 then
            dx, dz = dx / l, dz / l
            if dz < 0 or (dz == 0 and dx < 0) then dx, dz = -dx, -dz end -- canonical undirected direction
            local perp = -w.x1 * dz + w.z1 * dx -- signed distance of the line from the origin (same for a whole line)
            local key = string.format('%d_%d_%d', math.floor(dx * 20 + 0.5), math.floor(dz * 20 + 0.5),
                    math.floor(perp / 4 + 0.5))
            local g = groups[key]
            if not g then g = {}; groups[key] = g end
            for _, p in ipairs(w.cells) do g[#g + 1] = p end
        end
    end
    local out = {}
    for _, pts in pairs(groups) do
        if #pts >= 3 then
            local ordered, first, last = self:_orderAlongAxis(pts)
            out[#out + 1] = {
                x1 = first.x, z1 = first.z, x2 = last.x, z2 = last.z,
                length = math.sqrt((last.x - first.x) ^ 2 + (last.z - first.z) ^ 2),
                liters = 0, fillTypeName = 'STRAW', cells = ordered, centerline = ordered,
            }
        end
    end
    return out
end

--- Detect the windrows.
---@return table windrows list of { x1, z1, x2, z2, fillType, fillTypeName, liters, cells }
---@return table debugInfo { rowAngleDeg, headlandRingDistances, ringSpacing, productTypes, cells }
function WindrowDetector:findWindrows()
    local allCells = self:_scan()
    local debugInfo = { productTypes = {}, cells = #allCells }
    if #allCells == 0 then
        self.logger:debug('No product found in the field')
        return {}, debugInfo
    end

    -- Drop thin baled-over RESIDUE: a real windrow cell holds far more straw than the residue a baler leaves
    -- behind, so without a level cutoff a fully baled field still reads as full of windrows.
    do
        local maxL, sumL = 0, 0
        for _, c in ipairs(allCells) do
            sumL = sumL + c.level
            if c.level > maxL then maxL = c.level end
        end
        local nb, hist = 20, {}
        for i = 1, nb do hist[i] = 0 end
        for _, c in ipairs(allCells) do
            local b = math.min(nb, 1 + math.floor(c.level / math.max(1, maxL) * (nb - 1)))
            hist[b] = hist[b] + 1
        end
        local mx = 1
        for i = 1, nb do if hist[i] > mx then mx = hist[i] end end
        local bars = {}
        for i = 1, nb do bars[i] = hist[i] == 0 and '.' or tostring(math.min(9, 1 + math.floor(hist[i] / mx * 8))) end
        self.logger:debug('straw level: max %.0f, mean %.0f, cutoff %.0f, hist[0..max]: %s',
                maxL, sumL / math.max(1, #allCells), self.minStrawLevel, table.concat(bars))
    end
    local dense = {}
    for _, c in ipairs(allCells) do
        if c.level >= self.minStrawLevel then dense[#dense + 1] = c end
    end
    debugInfo.cells = #dense
    self.logger:debug('%d of %d product cells above straw cutoff %.0f', #dense, #allCells, self.minStrawLevel)
    allCells = dense
    if #allCells == 0 then
        self.logger:debug('No windrows found (only baled residue) in the field')
        return {}, debugInfo
    end

    -- Peel the headland rings so the continuous rings do not bridge the gaps between interior rows.
    local ringDistances, ringSpacing = self:_detectHeadlandRings(allCells)
    debugInfo.headlandRingDistances = ringDistances
    debugInfo.ringSpacing = ringSpacing
    local cutoff = 0
    if #ringDistances > 0 then
        cutoff = ringDistances[#ringDistances] + (ringSpacing > 0 and ringSpacing or 12) * 0.5
    end
    local cells = {}
    for _, c in ipairs(allCells) do
        if c.distToBoundary > cutoff then cells[#cells + 1] = c end
    end
    local ringStr = {}
    for _, r in ipairs(ringDistances) do ringStr[#ringStr + 1] = string.format('%.0f', r) end
    self.logger:debug('%d product cells: %d headland rings at [%s]m, spacing %.0fm -> peel <%.0fm, %d interior cells',
            #allCells, #ringDistances, table.concat(ringStr, ','), ringSpacing, cutoff, #cells)
    if #cells == 0 then
        return {}, debugInfo
    end

    -- Read the windrows directly as the density RIDGES in the interior straw -- each windrow found where it
    -- actually is, at its own angle and curve, nothing globally imposed (no fixed row angle, no comb).
    local windrows = self:_readRidges(cells)
    -- join crest pieces of the same physical windrow (split by straw gaps) so the baler drives straight
    -- through instead of CP inserting a reversing turn at every gap
    windrows = self:_mergeCollinear(windrows)
    for _, w in ipairs(windrows) do
        debugInfo.productTypes[w.fillTypeName] = (debugInfo.productTypes[w.fillTypeName] or 0) + #w.cells
    end
    self.logger:debug('read %d windrows from %d interior cells', #windrows, #cells)
    for i = 1, math.min(#windrows, 10) do
        local w = windrows[i]
        self.logger:debug('  windrow %d: (%.0f, %.0f) -> (%.0f, %.0f) %.0fm, %d crest pts',
                i, w.x1, w.z1, w.x2, w.z2, w.length, #w.cells)
    end
    return windrows, debugInfo
end
