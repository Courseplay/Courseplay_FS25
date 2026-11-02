--- This is the interface provided to Courseplay
-- Wraps the CourseGenerator which does not depend on the CP or Giants code.
-- all course generator related code dependent on CP/Giants functions go here
---@class CourseGeneratorInterface
CourseGeneratorInterface = CpObject()

function CourseGeneratorInterface:init()
    self.logger = Logger('CourseGeneratorInterface', Logger.level.debug, CpDebug.DBG_COURSES)
    self.generatedCourse = nil
end

--- Start generating a normal (non-vine) fieldwork course, with field boundary and island detection
---@param startPosition table {x, z}
---@param vehicle table
---@param settings CpCourseGeneratorSettings
---@param object table|nil optional object with callback
---@param onFinishedFunc function callback function to call when finished: onFinishedFunc([object,] course) where
--- course may be nil on failure
function CourseGeneratorInterface:startGenerationWithDetection(startPosition, vehicle, settings, object, onFinishedFunc)
    self.startPosition = startPosition
    self.vehicle = vehicle
    self.settings = settings
    self.object = object
    self.onFinishedFunc = onFinishedFunc
    vehicle:cpDetectFieldBoundary(startPosition.x, startPosition.z, self, self.onFieldDetectionFinished)
end

--- Start generating a normal (non-vine) fieldwork course, with field boundary and islands already detected
---@param startPosition table {x, z}
---@param vehicle table
---@param settings CpCourseGeneratorSettings
---@param object table|nil optional object with callback
---@param onFinishedFunc function callback function to call when finished: onFinishedFunc([object,] course) where
--- course may be nil on failure
---@param fieldPolygon table [{x, z}] field boundary polygon
---@param islandPolygons table [[{x, z}]] island polygons
function CourseGeneratorInterface:startGeneration(startPosition, vehicle, settings, object, onFinishedFunc,
                                                  fieldPolygon, islandPolygons)
    self.vehicle = vehicle
    self.object = object
    self.onFinishedFunc = onFinishedFunc
    local ok, course = self:generate(fieldPolygon, startPosition, vehicle, settings, islandPolygons)
    if ok then
        self:triggerCallback(course)
    else
        self:triggerCallback(nil)
    end
end

function CourseGeneratorInterface:onFieldDetectionFinished(vehicle, fieldPolygon, islandPolygons)
    if fieldPolygon == nil then
        self.logger:error(vehicle, "Field detection at x = %.1f, z = %.1f failed, can't generate",
                self.startPosition.x, self.startPosition.z)
        self:triggerCallback(nil)
        return
    end
    self.logger:info(vehicle, "Field detection finished, now start generating course")
    self:startGeneration(self.startPosition, vehicle, self.settings, self.object, self.onFinishedFunc,
            fieldPolygon, islandPolygons)
end

function CourseGeneratorInterface:triggerCallback(...)
    if self.object and self.onFinishedFunc then
        self.onFinishedFunc(self.object, ...)
    elseif self.onFinishedFunc then
        self.onFinishedFunc(...)
    end
end

---@param fieldPolygon table [{x, z}]
---@param startPosition table {x, z}
---@param vehicle table
---@param settings CpCourseGeneratorSettings
---@param islandPolygons|nil table [[{x, z}]] island polygons
function CourseGeneratorInterface:generate(fieldPolygon,
                                           startPosition,
                                           vehicle,
                                           settings,
                                           islandPolygons
)
    CourseGenerator.clearDebugObjects()
    local field = CourseGenerator.Field('', 0, CpMathUtil.pointsFromGame(fieldPolygon))

    local context = CourseGenerator.FieldworkContext(field, settings.workWidth:getValue(),
            settings.turningRadius:getValue(), settings.numberOfHeadlands:getValue())
    local rowPatternNumber = settings.centerMode:getValue()
    if rowPatternNumber == CourseGenerator.RowPattern.ALTERNATING and settings.rowsToSkip:getValue() == 0 then
        context:setRowPattern(CourseGenerator.RowPatternAlternating())
    elseif rowPatternNumber == CourseGenerator.RowPattern.ALTERNATING and settings.rowsToSkip:getValue() > 0 then
        context:setRowPattern(CourseGenerator.RowPatternSkip(settings.rowsToSkip:getValue(), false))
    elseif rowPatternNumber == CourseGenerator.RowPattern.SPIRAL then
        context:setRowPattern(CourseGenerator.RowPatternSpiral(settings.centerClockwise:getValue(), settings.spiralFromInside:getValue()))
    elseif rowPatternNumber == CourseGenerator.RowPattern.LANDS then
        -- TODO: auto fill clockwise from self:isPipeOnLeftSide(vehicle)?
        context:setRowPattern(CourseGenerator.RowPatternLands(settings.centerClockwise:getValue(), settings.rowsPerLand:getValue()))
    elseif rowPatternNumber == CourseGenerator.RowPattern.RACETRACK then
        context:setRowPattern(CourseGenerator.RowPatternRacetrack(settings.numberOfCircles:getValue()))
    end

    context:setStartLocation(startPosition.x, -startPosition.z)
    context:setBaselineEdge(startPosition.x, -startPosition.z)
    context:setFieldMargin(settings.fieldMargin:getValue())
    context:setUseBaselineEdge(settings.useBaseLineEdge:getValue())
    context:setFieldCornerRadius(7) --using a default, that is used during testing
    context:setHeadlandFirst(settings.startOnHeadland:getValue())
    context:setHeadlandClockwise(settings.headlandClockwise:getValue())
    context:setHeadlandOverlap(settings.headlandOverlapPercent:getValue())
    context:setSharpenCorners(settings.sharpenCorners:getValue())
    context:setHeadlandsWithRoundCorners(settings.headlandsWithRoundCorners:getValue())
    context:setAutoRowAngle(settings.autoRowAngle:getValue())
    -- the Course Generator UI uses the geographical direction angles (0 - North, 90 - East, etc), convert it to
    -- the mathematical angle (0 - x+, 90 - y+, etc)
    context:setRowAngle(math.rad(-(settings.manualRowAngleDeg:getValue() - 90)))
    context:setEvenRowDistribution(settings.evenRowWidth:getValue())
    context:setBypassIslands(settings.bypassIslands:getValue())
    context:setIslandHeadlands(settings.nIslandHeadlands:getValue())
    context:setIslandHeadlandClockwise(settings.islandHeadlandClockwise:getValue())
    if settings.bypassIslands:getValue() then
        if islandPolygons then
            -- islands were detected already, create them from the polygons and add to the field
            for i, islandPolygon in ipairs(islandPolygons) do
                context.field:addIsland(CourseGenerator.Island.createFromBoundary(i,
                        Polygon(CpMathUtil.pointsFromGame(islandPolygon))))
            end
        end
    end

    local status
    if settings.multiTools:getValue() > 1 then
        settings.narrowField:setValue(false)
        context:setNumberOfVehicles(settings.multiTools:getValue())
        context:setHeadlands(settings.multiTools:getValue() * settings.numberOfHeadlands:getValue())
        context:setIslandHeadlands(settings.multiTools:getValue() * settings.nIslandHeadlands:getValue())
        context:setUseSameTurnWidth(settings.useSameTurnWidth:getValue())
        status, self.generatedCourse = xpcall(
                function()
                    return CourseGenerator.FieldworkCourseMultiVehicle(context)
                end,
                function(err)
                    printCallstack();
                    return err
                end
        )
    elseif settings.narrowField:getValue() and settings.numberOfHeadlands:getValue() > 0 then
        -- two sided must have headlands and must start on headland
        context:setHeadlandFirst(true)
        -- and must not have multiple vehicles
        settings.multiTools:setValue(1)
        status, self.generatedCourse = xpcall(
                function()
                    return CourseGenerator.FieldworkCourseTwoSided(context)
                end,
                function(err)
                    printCallstack();
                    return err
                end
        )
    else
        status, self.generatedCourse = xpcall(
                function()
                    return CourseGenerator.FieldworkCourse(context)
                end,
                function(err)
                    printCallstack();
                    return err
                end
        )
    end

    -- return on exception or if the result is not usable
    if not status or self.generatedCourse == nil then
        return false
    end

    -- the actual number of headlands generated may be less than the requested
    local numberOfHeadlands = self.generatedCourse:getNumberOfHeadlands()

    self.logger:debug(vehicle, 'Generated course: %s', self.generatedCourse)

    local course = Course.createFromGeneratedCourse(vehicle, self.generatedCourse,
            settings.workWidth:getValue(), numberOfHeadlands, settings.multiTools:getValue(),
            settings.headlandClockwise:getValue(), settings.islandHeadlandClockwise:getValue(), not settings.useBaseLineEdge:getValue())
    self:setCourse(vehicle, course)
    return true, course
end

--- Generates a vine course, where the fieldPolygon are the start/end of the vine node.
---@param fieldPolygon table
---@param startPosition table {x, z}
---@param vehicle table
---@param workWidth number
---@param turningRadius number
---@param manualRowAngleDeg number
---@param rowsToSkip number
---@param multiTools number
function CourseGeneratorInterface:generateVineCourse(
        fieldPolygon,
        startPosition,
        vehicle,
        workWidth,
        turningRadius,
        manualRowAngleDeg,
        rowsToSkip,
        multiTools,
        lines,
        offset
)
    CourseGenerator.clearDebugObjects()
    local field = CourseGenerator.Field('', 0, CpMathUtil.pointsFromGame(fieldPolygon))

    local context = CourseGenerator.FieldworkContext(field, workWidth, turningRadius, 0)
    if rowsToSkip == 0 then
        context:setRowPattern(CourseGenerator.RowPatternAlternating())
    else
        context:setRowPattern(CourseGenerator.RowPatternSkip(rowsToSkip, true))
    end
    context:setStartLocation(startPosition.x, -startPosition.z)
    context:setAutoRowAngle(false)
    -- the Course Generator UI uses the geographical direction angles (0 - North, 90 - East, etc), convert it to
    -- the mathematical angle (0 - x+, 90 - y+, etc)
    context:setRowAngle(CpMathUtil.angleFromGame(manualRowAngleDeg))
    context:setBypassIslands(false)
    local status
    status, self.generatedCourse = xpcall(
            function()
                return CourseGenerator.FieldworkCourseVine(context,
                        CourseGenerator.FieldworkCourseVine.generateRows(workWidth, lines, offset ~= 0))
            end,
            function(err)
                printCallstack();
                return err
            end
    )
    -- return on exception or if the result is not usable
    if not status or self.generatedCourse == nil then
        return false
    end

    self.logger:debug('Generated vine course: %d center waypoints',
            #self.generatedCourse:getCenterPath())

    local course = Course.createFromGeneratedCourse(vehicle, self.generatedCourse,
            workWidth, 0, multiTools, true, true, true)
    self:setCourse(vehicle, course)
    return true, course
end

--- Waypoints of one headland straw ring: walk the field boundary and offset each point inward by `distance`,
--- emitting a waypoint every `spacing` metres. Returns the ring points in boundary order (not yet closed).
function CourseGeneratorInterface:_headlandRing(fieldPolygon, distance, spacing)
    local n = #fieldPolygon
    -- which side of an edge is inward? test the first edge's midpoint offset by one candidate normal
    local inwardSign = 1
    local a1, b1 = fieldPolygon[1], fieldPolygon[2]
    local ex, ez = b1.x - a1.x, b1.z - a1.z
    local el = math.sqrt(ex * ex + ez * ez)
    if el > 1e-6 then
        local tx, tz = ex / el, ez / el
        local mx, mz = (a1.x + b1.x) / 2, (a1.z + b1.z) / 2
        if not CpMathUtil.isPointInPolygon(fieldPolygon, mx - tz * 2, mz + tx * 2) then inwardSign = -1 end
    end
    -- MITRE each boundary vertex inward: the offset vertex sits `distance` from BOTH adjacent edges, so a
    -- corner becomes a single clean waypoint in the corner instead of two crossing offset edges.
    local corners = {}
    for i = 1, n do
        local prev = fieldPolygon[(i - 2) % n + 1]
        local cur = fieldPolygon[i]
        local nxt = fieldPolygon[i % n + 1]
        local e1x, e1z = cur.x - prev.x, cur.z - prev.z
        local e2x, e2z = nxt.x - cur.x, nxt.z - cur.z
        local l1 = math.sqrt(e1x * e1x + e1z * e1z)
        local l2 = math.sqrt(e2x * e2x + e2z * e2z)
        if l1 > 1e-6 and l2 > 1e-6 then
            local n1x, n1z = -e1z / l1 * inwardSign, e1x / l1 * inwardSign
            local n2x, n2z = -e2z / l2 * inwardSign, e2x / l2 * inwardSign
            local denom = 1 + (n1x * n2x + n1z * n2z)
            if denom < 0.1 then denom = 0.1 end -- clamp very sharp corners so the mitre can't blow up
            corners[#corners + 1] = { x = cur.x + distance * (n1x + n2x) / denom,
                                      z = cur.z + distance * (n1z + n2z) / denom }
        else
            corners[#corners + 1] = { x = cur.x, z = cur.z }
        end
    end
    -- ring = each corner waypoint, plus a waypoint every `spacing` along the straight run to the next corner
    local m = #corners
    local ring = {}
    for i = 1, m do
        local a = corners[i]
        local b = corners[i % m + 1]
        ring[#ring + 1] = { x = a.x, z = a.z }
        local dx, dz = b.x - a.x, b.z - a.z
        local len = math.sqrt(dx * dx + dz * dz)
        if len > spacing then
            local tx, tz = dx / len, dz / len
            local d = spacing
            while d < len - 0.5 do
                ring[#ring + 1] = { x = a.x + tx * d, z = a.z + tz * d }
                d = d + spacing
            end
        end
    end
    return ring
end

--- Map a course that traces the detected windrows directly: a waypoint every `spacing` metres along each
--- windrow line, with the windrows visited in nearest-endpoint order (serpentine for parallel rows). Every
--- waypoint is kept INSIDE the field boundary (no extension past the edge, nothing outside the field).
--- This does NOT use the fieldwork row/section generator -- the windrow lines ARE the course. Each windrow
--- is marked as a WORK row (rowStart/rowEnd), so CP's fieldwork driver lowers the baler along it and creates
--- the turns between rows itself; the course just ends at the last work waypoint (no return/loop).
--- (Ordering: headrows -- windrows along the inner perimeter -- should be driven first; that is a TODO for
--- when the detector separates them. For now all windrows are treated as parallel rows.)
---@param fieldPolygon table [{x, z}] field boundary (game coordinates)
---@param vehicle table
---@param windrows table detector output: [{x1, z1, x2, z2, ...}] interior windrow lines (game coordinates)
---@param headlandRings table|nil distances from the boundary of each headland straw ring (outer ring = smallest)
---@param startX number|nil start next to this position (default: the vehicle position)
---@param startZ number|nil
---@return boolean ok
---@return table|nil course
function CourseGeneratorInterface:generateWindrowCourse(fieldPolygon, vehicle, windrows, headlandRings, startX, startZ)
    local SPACING = 10
    if #windrows == 0 and (not headlandRings or #headlandRings == 0) then
        return false
    end
    if startX == nil or startZ == nil then
        local x, _, z = getWorldTranslation(vehicle.rootNode)
        startX, startZ = x, z
    end
    local function dist(ax, az, bx, bz)
        return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
    end

    local waypoints = {}
    local px, pz = startX, startZ
    local rowNumber = 0

    -- Headlands FIRST: drive each straw ring outer -> inner, as a WORK row, starting at the ring point
    -- nearest the previous exit and going all the way around. CP makes the turn to the next ring itself.
    -- Each ring is the field boundary offset inward to the ring's distance from the edge.
    if headlandRings and #headlandRings > 0 then
        local dists = {}
        for _, d in ipairs(headlandRings) do dists[#dists + 1] = d end
        table.sort(dists)
        for _, ringDist in ipairs(dists) do
            local ring = self:_headlandRing(fieldPolygon, ringDist, SPACING)
            if #ring >= 3 then
                -- rotate the ring so it starts nearest the previous exit, then walk once around (close loop)
                local startIdx, bestD = 1, math.huge
                for i, p in ipairs(ring) do
                    local d2 = (p.x - px) ^ 2 + (p.z - pz) ^ 2
                    if d2 < bestD then bestD, startIdx = d2, i end
                end
                local kept = {}
                for i = 0, #ring do
                    local p = ring[(startIdx - 1 + i) % #ring + 1]
                    if CpMathUtil.isPointInPolygon(fieldPolygon, p.x, p.z) then kept[#kept + 1] = { x = p.x, z = p.z } end
                end
                if #kept >= 2 then
                    rowNumber = rowNumber + 1
                    for i, p in ipairs(kept) do
                        local attributes = CourseGenerator.WaypointAttributes()
                        attributes:setRowNumber(rowNumber)
                        if i == 1 then attributes:setRowStart(true) end
                        if i == #kept then attributes:setRowEnd(true) end
                        p.attributes = attributes
                        waypoints[#waypoints + 1] = p
                    end
                    px, pz = kept[#kept].x, kept[#kept].z
                end
            end
        end
    end

    -- Then the interior windrows: SWEEP across the field, one side to the other (not greedy-from-the-middle,
    -- which splits the field in two). Order the windrows by cross-position (each midpoint projected onto the
    -- axis perpendicular to the rows), start from whichever side is nearer the tractor, and enter each row
    -- from the end closest to the previous exit (serpentine).
    local adx, adz = 0, 0
    for _, w in ipairs(windrows) do
        local dx, dz = w.x2 - w.x1, w.z2 - w.z1
        local l = math.sqrt(dx * dx + dz * dz)
        if l > 1e-6 then
            dx, dz = dx / l, dz / l
            if dz < 0 or (dz == 0 and dx < 0) then dx, dz = -dx, -dz end
            adx, adz = adx + dx, adz + dz
        end
    end
    local al = math.sqrt(adx * adx + adz * adz)
    if al > 1e-6 then adx, adz = adx / al, adz / al else adx, adz = 0, 1 end
    local crossX, crossZ = -adz, adx -- axis perpendicular to the rows
    local ordered = {}
    for _, w in ipairs(windrows) do
        w._cross = ((w.x1 + w.x2) / 2) * crossX + ((w.z1 + w.z2) / 2) * crossZ
        ordered[#ordered + 1] = w
    end
    table.sort(ordered, function(a, b) return a._cross < b._cross end)
    if #ordered >= 2 then
        -- start from whichever end of the sweep is nearer the tractor
        local f, lst = ordered[1], ordered[#ordered]
        local df = math.min(dist(px, pz, f.x1, f.z1), dist(px, pz, f.x2, f.z2))
        local dl = math.min(dist(px, pz, lst.x1, lst.z1), dist(px, pz, lst.x2, lst.z2))
        if dl < df then
            local rev = {}
            for i = #ordered, 1, -1 do rev[#rev + 1] = ordered[i] end
            ordered = rev
        end
    end

    for _, w in ipairs(ordered) do
        local fx, fz, tx, tz
        if dist(px, pz, w.x1, w.z1) <= dist(px, pz, w.x2, w.z2) then
            fx, fz, tx, tz = w.x1, w.z1, w.x2, w.z2
        else
            fx, fz, tx, tz = w.x2, w.z2, w.x1, w.z1
        end
        local dx, dz = tx - fx, tz - fz
        local length = math.sqrt(dx * dx + dz * dz)
        local steps = math.max(1, math.floor(length / SPACING + 0.5))
        -- Sample the line, splitting into contiguous IN-FIELD segments: a point outside the field ends the
        -- current segment. This keeps waypoints inside the field AND, on a concave field where a windrow
        -- leaves and re-enters, produces two separate rows instead of one lowered pass across the gap.
        local segments, segment = {}, {}
        for k = 0, steps do
            local t = k / steps
            local x, z = fx + dx * t, fz + dz * t
            if CpMathUtil.isPointInPolygon(fieldPolygon, x, z) then
                segment[#segment + 1] = { x = x, z = z }
            elseif #segment > 0 then
                segments[#segments + 1] = segment
                segment = {}
            end
        end
        if #segment > 0 then segments[#segments + 1] = segment end
        -- each in-field segment (>= 2 waypoints) is its own WORK row. CP raises the baler at the rowEnd
        -- waypoint and lowers at rowStart, so if those sit on the windrow ends the last/first stretch of straw
        -- is left (the detected crest is also a bit shorter than the real straw). So extend the row a short
        -- OVERRUN past each end -- but only while still inside the field -- and put the rowStart/rowEnd markers
        -- on that overrun. The true windrow endpoints stay WORK waypoints and the baler stays lowered across
        -- the whole windrow; the lift/drop happens on bare ground just past the product.
        local OVERRUN = 4
        for _, segmentPoints in ipairs(segments) do
            if #segmentPoints >= 2 then
                local a, b = segmentPoints[1], segmentPoints[#segmentPoints]
                local sdx, sdz = b.x - a.x, b.z - a.z
                local sl = math.sqrt(sdx * sdx + sdz * sdz)
                if sl > 1e-6 then
                    sdx, sdz = sdx / sl, sdz / sl
                    local pre = { x = a.x - sdx * OVERRUN, z = a.z - sdz * OVERRUN }
                    local post = { x = b.x + sdx * OVERRUN, z = b.z + sdz * OVERRUN }
                    if CpMathUtil.isPointInPolygon(fieldPolygon, pre.x, pre.z) then
                        table.insert(segmentPoints, 1, pre)
                    end
                    if CpMathUtil.isPointInPolygon(fieldPolygon, post.x, post.z) then
                        segmentPoints[#segmentPoints + 1] = post
                    end
                end
                rowNumber = rowNumber + 1
                for i, p in ipairs(segmentPoints) do
                    local attributes = CourseGenerator.WaypointAttributes()
                    attributes:setRowNumber(rowNumber)
                    if i == 1 then attributes:setRowStart(true) end
                    if i == #segmentPoints then attributes:setRowEnd(true) end
                    p.attributes = attributes
                    waypoints[#waypoints + 1] = p
                end
            end
        end
        px, pz = tx, tz
    end

    if #waypoints < 2 then
        self.logger:debug(vehicle, 'Windrow course: only %d waypoints inside the field, not enough', #waypoints)
        return false
    end
    self.logger:debug(vehicle, '%d waypoints over %d windrows', #waypoints, #windrows)
    -- protect course construction: if it errors, return false so the caller can show the error dialog
    -- and clear its pending flag, instead of the exception wedging the Generate button for the session.
    local ok, course = xpcall(function() return Course(vehicle, waypoints) end,
            function(err) printCallstack(); return err end)
    if not ok then
        self.logger:error(vehicle, 'Windrow course construction failed: %s', tostring(course))
        return false
    end
    vehicle:setFieldWorkCourse(course)
    return true, course
end

--- Load the course into the vehicle
function CourseGeneratorInterface:setCourse(vehicle, course)
    if course and course:getMultiTools() > 1 then
        course:setPosition(vehicle:getCpLaneOffsetSetting():getValue())
    end
    vehicle:setFieldWorkCourse(course)
end

--- Generate a course for the vehicle, with start position at the vehicle's position
function CourseGeneratorInterface:generateDefaultCourse(vehicle)
    local settings = vehicle:getCourseGeneratorSettings()
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    self.logger:info(vehicle, 'Generating course at x = %.1f, z = %.1f', x, z)
    self:startGenerationWithDetection({x = x, z = z}, vehicle, settings, nil, function()
        self.logger:info(vehicle, 'Course generation finished')
    end)
end