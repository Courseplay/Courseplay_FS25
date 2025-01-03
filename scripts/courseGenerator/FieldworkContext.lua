--- A context with all parameters and constraints for a fieldwork course
--- to generate
local FieldworkContext = CpObject()

---@class CourseGenerator.FieldworkContext
CourseGenerator.FieldworkContext = FieldworkContext

---@param field CourseGenerator.Field
---@param workingWidth number working width
---@param turningRadius number minimum turning radius of the equipment
---@param nHeadlands number of headland passes
function FieldworkContext:init(field, workingWidth, turningRadius, nHeadlands)
    self.field = field
    self.startLocation = Vector(0, 0)
    self.workingWidth = workingWidth
    self.overlap = CourseGenerator.cDefaultHeadlandOverlapPercentage / 100
    self.turningRadius = turningRadius

    self.fieldMargin = 0
    self.nHeadlands = nHeadlands
    self.nHeadlandsWithRoundCorners = 0
    self.headlandClockwise = true
    self.headlandFirst = true

    self.fieldCornerRadius = 0
    self.sharpenCorners = true
    self.bypassIslands = true
    self.nIslandHeadlands = 1
    self.islandHeadlandClockwise = true

    self.rowPattern = CourseGenerator.RowPatternAlternating()
    self.autoRowAngle = true
    self.rowAngle = 0
    self.rowWaypointDistance = CourseGenerator.cRowWaypointDistance
    self.evenRowDistribution = false
    self.useBaselineEdge = false
    self.enableSmallOverlapsWithHeadland = false
    self.logger = Logger('FieldworkContext', Logger.level.debug, CpDebug.DBG_COURSES)
    self.errors = {}
    
    self.reverseCourse = false
    self.spiralFromInside = false
    -- multi vehicle support
    self.nVehicles = 1
    self.useSameTurnWidth = false
end

function FieldworkContext:log()
    self.logger:debug('working width: %.1f, turning radius: %.1f, headlands: %d, %d with round corners, clockwise %s',
            self.workingWidth, self.turningRadius, self.nHeadlands, self.nHeadlandsWithRoundCorners, self.headlandClockwise)
    self.logger:debug('field corner radius: %.1f, sharpen corners: %s, bypass islands: %s, headlands around islands %d, island headland cw %s',
            self.fieldCornerRadius, self.sharpenCorners, self.bypassIslands, self.nIslandHeadlands, self.islandHeadlandClockwise)
    self.logger:debug('row pattern: %s, row angle auto: %s, %.1fº, even row distribution: %s, use baseline edge: %s, small overlaps: %s',
            self.rowPattern, self.autoRowAngle, math.deg(self.rowAngle), self.evenRowDistribution, self.useBaselineEdge, self.enableSmallOverlapsWithHeadland)
    self.logger:debug('start location %s, baseline edge %s, vehicles %d, same turn width %s, headland overlap %.1f',
            self.startLocation, self.baselineEdge, self.nVehicles, self.useSameTurnWidth, self.overlap * 100)
end

function FieldworkContext:addError(logger, ...)
    local text = string.format(...)
    logger:error(text)
    table.insert(self.errors, text)
end

---@return string[] Errors found during the generation
function FieldworkContext:getErrors()
    return self.errors
end

function FieldworkContext:hasErrors()
    return #self.errors > 0
end

---@param nHeadlands number of headlands total.
function FieldworkContext:setHeadlands(nHeadlands)
    self.nHeadlands = math.max(0, nHeadlands)
    return self
end

---@param nHeadlandsWithRoundCorners number of headlands that should have their corners rounded to the turning radius.
function FieldworkContext:setHeadlandsWithRoundCorners(nHeadlandsWithRoundCorners)
    self.nHeadlandsWithRoundCorners = math.min(self.nHeadlands, nHeadlandsWithRoundCorners)
    return self
end

---@param nIslandHeadlands number of headlands to generate around field islands
function FieldworkContext:setIslandHeadlands(nIslandHeadlands)
    self.nIslandHeadlands = nIslandHeadlands
    return self
end


---@param fieldCornerRadius number if a field has a corner under this radius, we'll sharpen it
function FieldworkContext:setFieldCornerRadius(fieldCornerRadius)
    self.fieldCornerRadius = fieldCornerRadius
    return self
end

---@param bypass boolean if true, the course will go around islands
function FieldworkContext:setBypassIslands(bypass)
    self.bypassIslands = bypass
    return self
end

---@param clockwise boolean generate the headlands around the islands int the clockwise direction if true, counterclockwise if false
function FieldworkContext:setHeadlandClockwise(clockwise)
    self.headlandClockwise = clockwise
    return self
end

---@param sharpen boolean if true, sharpen the corners of the headlands which are not rounded. Will make
--- a sharp turn whenever the headland's curvature is less than the turning radius.
function FieldworkContext:setSharpenCorners(sharpen)
    self.sharpenCorners = sharpen
    return self
end

---@param overlapPercentage number Headland overlap percentage. We make headland passes slightly narrower than the working width, so they overlap
--- a bit to make sure there are no unworked gaps remaining when maneuvering. This is the overlap in percentage of
--- the working width.
function FieldworkContext:setHeadlandOverlap(overlapPercentage)
    self.overlap = overlapPercentage / 100
    return self
end

---@param clockwise boolean generate headlands around islands in the clockwise direction if true, counterclockwise if false
function FieldworkContext:setIslandHeadlandClockwise(clockwise)
    self.islandHeadlandClockwise = clockwise
    return self
end


---@param headlandFirst boolean start working on the headland first and switch to the center when done (harvesting),
--- If false, start on the up/down rows in the middle and do the headlands last (for instance sowing)
function FieldworkContext:setHeadlandFirst(headlandFirst)
    self.headlandFirst = headlandFirst
    return self
end

--- The (approximate) location where we want to start working on the headland when progressing inwards.
function FieldworkContext:setStartLocation(x, y)
    ---@type Vector
    self.startLocation = Vector(x, y)
    return self
end

--- Should the angle of rows determined automatically?
function FieldworkContext:setAutoRowAngle(auto)
    self.autoRowAngle = auto
    return self
end

--- Angle of the up/down rows when not automatically selected
---@param rowAngle number row angle in radians, x axis is 0, increasing counterclockwise
function FieldworkContext:setRowAngle(rowAngle)
    self.rowAngle = rowAngle
    return self
end

--- Distance between waypoints on rows
---@param d number distance between waypoints, default is CourseGenerator.cRowWaypointDistance
function FieldworkContext:setRowWaypointDistance(d)
    self.rowWaypointDistance = d
    return self
end

--- Distribute rows evenly, so the distance between them may be less than the working width,
--- or should the last row absorb all the difference, so only the last row is narrower than
--- the working width
function FieldworkContext:setEvenRowDistribution(evenRowDistribution)
    self.evenRowDistribution = evenRowDistribution
    return self
end

--- Select the edge of the field boundary which we will use as a baseline for up/down rows,
--- instead of a straight line at some angle.
--- The idea is that field boundaries which are only slightly deviate from straight line
--- cause straight up/down rows to meet the headland in a very flat angle, resulting in
--- very long turns.
--- Making the up/down rows parallel with such an edge may yield better results.
function FieldworkContext:setBaselineEdge(x, y)
    self.baselineEdge = Vector(x, y)
    return self
end

--- Instead of generating straight up/down rows, use a baseline (set by setBaselineEdge()) and make
--- all rows follow that baseline.
function FieldworkContext:setUseBaselineEdge(use)
    self.useBaselineEdge = use
    return self
end

--- What pattern to use to determine in which order the rows within a block are worked on.
---@param rowPattern CourseGenerator.RowPattern
function FieldworkContext:setRowPattern(rowPattern)
    self.rowPattern = rowPattern
    return self
end

---@param enableSmallOverlaps boolean|nil if true, and the row is almost parallel to the boundary and crosses it
--- multiple times (for instance a slightly zigzagging headland), do not split the row unless it is getting too
--- far from the boundary (it is like a smart version of onlyFirstAndLastInterSections, but significantly will slow
--- down the generation)
function FieldworkContext:setEnableSmallOverlapsWithHeadland(enableSmallOverlaps)
    self.enableSmallOverlapsWithHeadland = enableSmallOverlaps
    return self
end

---@param reverseCourse boolean reverse the complete course, not sure how to do it when copy a course and reverse it afterwards.
function FieldworkContext:setReverseCourse(reverseCourse)
    self.reverseCourse = reverseCourse
    return self
end

---@param spiralFromInside boolean will create a course with headlands on just two sides or also called "narrow field"
function FieldworkContext:setSpiralFromInside(spiralFromInside)
    self.spiralFromInside = spiralFromInside
    return self
end

---@param margin number reduce or increase the size of the field. Positive values will make the field smaller, moving
---the field boundary inside by margin meters, negative values will make it larger, moving the boundary outside.
function FieldworkContext:setFieldMargin(margin)
    self.fieldMargin = margin
    return self
end

--- Override the working width for headland passes (if not the same as the working width)
---@param w number
function FieldworkContext:setHeadlandWorkingWidth(w)
    self.headlandWorkingWidth = w
    return self
end

---@return number width of a headland pass in meters
function FieldworkContext:getHeadlandWorkingWidth()
    return self.headlandWorkingWidth or self.workingWidth
end

---@return number headland overlap
function FieldworkContext:getHeadlandOverlap()
    return self.overlap
end

--- Disable sequencing of blocks, just generate them, with the rows and then stop.
--- Block sequencing uses a genetic algorithm to find the best order of blocks to work on.
--- When we perform an island detection only, we just want a grid across the field, but that may result in many blocks,
--- no need for a CPU intensive, very long running block sequencing.
function FieldworkContext:_setGenerateBlocksOnly()
    self.generateBlocksOnly = true
    return self
end

function FieldworkContext:_generateBlocksOnly()
    return self.generateBlocksOnly
end

------------------------------------------------------------------------------------------------------------------------
--- Multi vehicle support
------------------------------------------------------------------------------------------------------------------------

---@param nVehicles number number of vehicles that'll work on the course at the same time
function FieldworkContext:setNumberOfVehicles(nVehicles)
    self.nVehicles = nVehicles
    return self
end

--- @param useSameTurnWidth boolean row end turns are always the same width: 'symmetric lane change' enabled, meaning
--- after each turn we reverse the offset
function FieldworkContext:setUseSameTurnWidth(useSameTurnWidth)
    self.useSameTurnWidth = useSameTurnWidth
    return self
end

--- Distance between the rows in the field center
--- In the center there is one row for multiple vehicles, and the rows for the individual vehicles
--- are created from this single row by offsetting it. In that case, we consider the row as wide as the number
--- of vehicles times the working width of a single vehicle, this way, the offset rows (without individually adjusting
----- their lengths) will still yield full coverage. However, the headlands are single vehicle wide, so we need to
----- use different widths for them.
---@param w number
function FieldworkContext:setCenterRowSpacing(w)
    self.centerRowSpacing = w
    return self
end

---@return number distance between two adjacent up/down rows.
function FieldworkContext:getCenterRowSpacing()
    return self.centerRowSpacing or self.workingWidth
end

---@see Row.adjustLength()
function FieldworkContext:setCenterRowWidthForAdjustment(width)
    self.centerRowWidthForAdjustment = width
    return self
end

--- Width of the row to use when adjusting a row length for full coverage where it meets the headland at an angle
---@return number
function FieldworkContext:getCenterRowWidthForAdjustment()
    return self.centerRowWidthForAdjustment or self.workingWidth
end

---@see Row.adjustLength()
function FieldworkContext:setHeadlandWidthForAdjustment(width)
    self.headlandWidthForAdjustment = width
    return self
end

--- Width of the headland to use when adjusting a row length for full coverage where it meets the headland at an angle
---@return number
function FieldworkContext:getHeadlandWidthForAdjustment()
    return self.headlandWidthForAdjustment or self.workingWidth
end