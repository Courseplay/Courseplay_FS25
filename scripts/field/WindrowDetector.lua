--- Detects windrows (straw/hay/grass swaths lying on the ground) on a field and returns them as
--- lines that can be used as course generator rows, so a baler can be driven exactly over the product.
---
--- Windrows live in the Giants densityMapHeight system (the same system that holds bunker silo heaps).
--- We sweep small parallelogram probes across the field boundary with DensityMapHeightUtil, collect the
--- cells that contain a bale-able fill type, then:
---   1. pick the cross-row axis from the point cloud (parallel windrows form sharp, regularly spaced peaks
---      along the cross axis and a flat spread along the row axis -- a 1D histogram peakiness test; a PCA
---      fails here because a ~rectangular field region has ambiguous global spread),
---   2. cluster the cells into lanes (one lane per windrow) by a gap split on the cross coordinate,
---   3. fit each lane to a straight line (its two extreme points along the row axis).
---
---@class WindrowDetector
WindrowDetector = CpObject()

--- Fill types that a baler picks up from a windrow on the ground.
WindrowDetector.PRODUCT_FILL_TYPE_NAMES = { 'STRAW', 'DRYGRASS_WINDROW', 'GRASS_WINDROW', 'SILAGE' }

---@param fieldPolygon table [{x, z}] field boundary in game coordinates
---@param cellSize number|nil probe grid resolution in m (default 2)
---@param laneGap number|nil cross-row gap (m) that separates two windrows (default 6, < row spacing, > row width)
function WindrowDetector:init(fieldPolygon, cellSize, laneGap)
    self.logger = Logger('WindrowDetector', Logger.level.debug, CpDebug.DBG_COURSES)
    self.fieldPolygon = fieldPolygon
    self.cellSize = cellSize or 2
    self.laneGap = laneGap or 6
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

--- Detect the windrows.
---@return table windrows list of { x1, z1, x2, z2, fillType, fillTypeName, liters, cells }
---@return table debugInfo { crossAxis = 'x'|'z', productTypes = { name = cellCount }, cells = totalCells }
function WindrowDetector:findWindrows()
    local cells = self:_scan()
    local debugInfo = { productTypes = {}, cells = #cells }
    if #cells == 0 then
        self.logger:debug('No windrows found in the field')
        return {}, debugInfo
    end

    -- 1. choose the cross-row axis by histogram peakiness (axis-aligned; rotated windrows map to the
    -- nearest axis, which is fine for GIANTS fields where each harvester/windrower pass is near axis-aligned)
    local crossIsX = self:_binCV2(cells, function(c) return c.x end) >= self:_binCV2(cells, function(c) return c.z end)
    debugInfo.crossAxis = crossIsX and 'x' or 'z'
    -- u = cross-row coordinate (lane key), v = along-row coordinate (position within a windrow)
    local u = function(c) return crossIsX and c.x or c.z end
    local v = function(c) return crossIsX and c.z or c.x end

    -- 2. cluster into lanes: sort by cross coordinate, split where the gap exceeds laneGap
    table.sort(cells, function(a, b) return u(a) < u(b) end)
    local lanes, lane = {}, { cells[1] }
    for i = 2, #cells do
        if (u(cells[i]) - u(cells[i - 1])) > self.laneGap then
            lanes[#lanes + 1] = lane
            lane = {}
        end
        lane[#lane + 1] = cells[i]
        debugInfo.productTypes[self.productIndex[cells[i].fillType]] =
            (debugInfo.productTypes[self.productIndex[cells[i].fillType]] or 0) + 1
    end
    lanes[#lanes + 1] = lane

    -- 3. fit each lane to a straight line: the two extreme cells along the row axis
    local windrows = {}
    for _, laneCells in ipairs(lanes) do
        if #laneCells >= 3 then
            table.sort(laneCells, function(a, b) return v(a) < v(b) end)
            local first, last = laneCells[1], laneCells[#laneCells]
            local liters = 0
            for _, c in ipairs(laneCells) do liters = liters + c.level end
            windrows[#windrows + 1] = {
                x1 = first.x, z1 = first.z, x2 = last.x, z2 = last.z,
                fillType = first.fillType,
                fillTypeName = self.productIndex[first.fillType],
                liters = liters,
                cells = laneCells,
            }
        end
    end
    self.logger:debug('Found %d windrows from %d product cells (cross axis: %s)',
            #windrows, #cells, debugInfo.crossAxis)
    return windrows, debugInfo
end
