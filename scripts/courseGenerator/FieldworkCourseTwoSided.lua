--- Not the best name for it, but this is a fieldwork course where the headland is not
--- going around the field boundary, only two, opposite sides, think about a long
--- horizontal rectangle, the headlands would be on the left and right side of the
--- field only. Here an example starting on the left side:
--  , ,-, ,-----------------------------2-----------------------------,
--  | | | | ,---------------------------------------------------, ,-, |
--  | | | | '-------------------------------------------------, | | | |
--  | |1| | ,---------------------------4---------------------' | |3| |
--  | | | | '-------------------------------------------------, | | | |
--  '-' '-' --------------------------------------------------' '-' '-'
--
-- 1: start headland block
-- 2: middle headland block
-- 3: end headland block
-- 4: center

--- For this pattern, we use a center restricted to a single block as there is no headland around it that
--- could be used to drive to the next block in all cases.
--- Also, the center rows are always generated from the side opposite of the middle headland block, using that
--- opposite side as a base edge as this is the easiest way to make sure rows remain on the field.

---@class FieldworkCourseTwoSided : CourseGenerator.FieldworkCourse
local FieldworkCourseTwoSided = CpObject(CourseGenerator.FieldworkCourse)

function FieldworkCourseTwoSided:init(context)
    self.logger = Logger('FieldworkCourseTwoSided')
    context:setRowPattern(CourseGenerator.RowPatternAlternatingFirstRowEntryOnly())
    self:_setContext(context)
    -- Add nil check for self.boundary
    if not self.boundary then
        self.context:addError(self.logger, 'Boundary is nil')
        return
    end
    -- clockwise setting really does not matter but the generated headland is expected match the boundary
    self.virtualHeadland = CourseGenerator.FieldworkCourseHelper.createVirtualHeadland(self.boundary, self.boundary:isClockwise(),
            self.context.workingWidth)
    self.headlandPath = Polyline()

    self:generateHeadlands()

    self.circledIslands = {}
    self:setupAndSortIslands()

    local centerBoundary, baselineLocation = self:_createCenterBoundary()
    if centerBoundary == nil then
        self.context:addError(self.logger, 'Can\'t create center boundary for this field with the current settings')
        return
    end
    -- this is the headland around the center part, that is, the area #4 on the drawing above
    local centerHeadland = CourseGenerator.Headland(centerBoundary, centerBoundary:isClockwise(), 0, 0, true)
    centerHeadland:sharpenCorners(2 * self.context.turningRadius)

    -- start position for the center
    local lastHeadlandRow = self.endHeadlandBlock:getLastRow()
    -- where to start generating the rows
    self.context.baselineEdge = baselineLocation
    self.center = CourseGenerator.CenterTwoSided(self.context, self.boundary, centerHeadland, lastHeadlandRow[#lastHeadlandRow], self.bigIslands)
    self.center:generate()
end

---@return number number of headlands as in the context (always the same as the actual ones)
function FieldworkCourseTwoSided:getNumberOfHeadlands()
    return self.context.nHeadlands
end

---@return Polyline
function FieldworkCourseTwoSided:getHeadlandPath()
    local headlandPath = Polyline()
    for _, r in ipairs(self.startHeadlandBlock:getRows()) do
        headlandPath:appendMany(r)
    end
    for _, r in ipairs(self.middleHeadlandBlock:getRows()) do
        headlandPath:appendMany(r)
    end
    for _, r in ipairs(self.endHeadlandBlock:getRows()) do
        headlandPath:appendMany(r)
    end
    self.logger:debug('headland path with %d vertices', #headlandPath)
    return headlandPath
end

---@return Polyline
function FieldworkCourseTwoSided:getCenterPath()
    local centerPath = self.center:getPath()
    return centerPath
end

function FieldworkCourseTwoSided:generateHeadlands()
    -- Add nil check for self.startHeadlandBlock
    if not self.startHeadlandBlock then
        self.context:addError(self.logger, 'Start headland block is nil')
        return
    end
    -- this is the side where we start working, generate here headlands parallel to the field edge
    -- block 1 on the drawing above
    self:_createStartHeadlandBlock()
    if self.startHeadlandBlock:getNumberOfRows() == 0 then
        self.context:addError(self.logger, 'Can\'t generate headlands on start side for this field with the current settings')
        return
    end
    -- now fill in the space between the headlands with rows parallel to the edge between the start and end,
    -- this is the block 3 on the drawing above (just a single row)
    local startHeadlandBlockExit = self.startHeadlandBlock:getExit(self.startHeadlandBlockEntry)
    self:_createMiddleHeadlandBlock(startHeadlandBlockExit)
    if self.middleHeadlandBlock:getNumberOfRows() == 0 then
        self.context:addError(self.logger, 'Can\'t generate headland row for this field with the current settings')
        return
    end

    -- find the opposite end of the field ...
    local fieldCenter = self.boundary:getCenter()
    local oppositeBaselineLocation = fieldCenter - (self.startHeadlandBlock:getRows()[1]:getMiddle() - fieldCenter)
    -- ... and generate headlands over there too, block 2 on the drawing above
    self:_createEndHeadlandBlock(oppositeBaselineLocation, self.middleHeadlandBlock:getRows()[1])
    if self.endHeadlandBlock:getNumberOfRows() == 0 then
        self.context:addError(self.logger, 'Can\'t generate headlands on ending side for this field with the current settings')
        return
    end

    -- now find the entry to the end block and finalize it
    local middleHeadlandBlockExit = self.middleHeadlandBlock:getExit(self.middleHeadlandBlockEntry)
    self.endHeadlandBlock:finalize(self:_getClosestEntry(self.endHeadlandBlock, middleHeadlandBlockExit))

    -- connect the start and the middle
    local lastStartHeadlandRow = self.startHeadlandBlock:getLastRow()
    local intersections = lastStartHeadlandRow:getIntersections(self.middleHeadlandBlock:getFirstRow())
    lastStartHeadlandRow:cutEndAtIx(intersections[1].ixA)
    lastStartHeadlandRow:append(intersections[1].is)
    lastStartHeadlandRow:setAttribute(#lastStartHeadlandRow, CourseGenerator.WaypointAttributes.setHeadlandTurn, true)
    self.middleHeadlandBlock:getFirstRow():cutStartAtIx(intersections[1].ixB + 1)

    -- connect the middle and the end
    local firstEndHeadlandRow = self.endHeadlandBlock:getFirstRow()
    intersections = firstEndHeadlandRow:getIntersections(self.middleHeadlandBlock:getFirstRow())
    if #intersections > 0 then
        firstEndHeadlandRow:cutStartAtIx(intersections[1].ixA + 1)
        local firstMiddleHeadlandRow = self.middleHeadlandBlock:getFirstRow()
        firstMiddleHeadlandRow:cutEndAtIx(intersections[1].ixB)
        firstMiddleHeadlandRow:append(intersections[1].is)
        firstMiddleHeadlandRow:setAttribute(#firstMiddleHeadlandRow, CourseGenerator.WaypointAttributes.setHeadlandTurn, true)
    else
        self.context:addError(self.logger, 'Can\'t connect headlands for this field with the current settings')
        return
    end
end

--- Create headland at the starting end of the field
function FieldworkCourseTwoSided:_createStartHeadlandBlock()
    -- use the boundary directly as the baseline edge and not the virtual headland to preserve corners
    local rows = CourseGenerator.CurvedPathHelper.generateCurvedUpDownRows(self.boundary, self.context.baselineEdge,
            self.context.workingWidth, self.context.turningRadius, self.context.nHeadlands, self.context.workingWidth / 2)
    self.startSideBoundary = rows[#rows]:clone()
    self.startHeadlandBlock = CourseGenerator.Block(self.context, 1)
    self.startHeadlandBlock:addRows(self:_cutAtBoundary(rows, self.virtualHeadland))
    self.startHeadlandBlockEntry = self:_getClosestEntry(self.startHeadlandBlock, self.context.startLocation)
    self.startHeadlandBlock:finalize(self.startHeadlandBlockEntry)
end

--- Create headland at the ending side of the field
function FieldworkCourseTwoSided:_createEndHeadlandBlock(oppositeBaselineLocation, middleHeadlandRow)
    local rows = CourseGenerator.CurvedPathHelper.generateCurvedUpDownRows(self.boundary, oppositeBaselineLocation,
            self.context.workingWidth, self.context.turningRadius, self.context.nHeadlands, self.context.workingWidth / 2)
    self.endSideBoundary = rows[#rows]:clone()
    self.endHeadlandBlock = CourseGenerator.Block(self.context, 3)
    rows = self:_cutAtBoundary(rows, self.virtualHeadland)
    -- on this side, we are working our way back from the field edge, so the first row is connected
    -- to the center, but all the rest must be trimmed back
    for i = 2, #rows do
        self:_trim(rows[i], middleHeadlandRow)
    end
    self.endHeadlandBlock:addRows(rows)
end

--- Create headland connecting the two above, this is a single row
function FieldworkCourseTwoSided:_createMiddleHeadlandBlock(startHeadlandBlockExit)
    local rows = CourseGenerator.CurvedPathHelper.generateCurvedUpDownRows(self.virtualHeadland:getPolygon(), startHeadlandBlockExit,
            self.context.workingWidth, self.context.turningRadius, 1)
    self.centerSideBoundary = rows[#rows]:clone()
    self.middleHeadlandBlock = CourseGenerator.Block(self.context, 2)
    self.middleHeadlandBlock:addRows(self:_cutAtBoundary(rows, self.virtualHeadland))
    self.middleHeadlandBlockEntry = self:_getClosestEntry(self.middleHeadlandBlock, startHeadlandBlockExit)
    self.middleHeadlandBlock:finalize(self.middleHeadlandBlockEntry)
end

function FieldworkCourseTwoSided:_cutAtBoundary(rows, boundary)
    local cutRows = {}
    for _, row in ipairs(rows) do
        local sections = row:split(boundary, {}, true)
        if #sections == 1 then
            table.insert(cutRows, sections[1])
        end
    end
    return cutRows
end

function FieldworkCourseTwoSided:_getClosestEntry(block, startLocation)
    local minD, closestEntry = math.huge, nil
    for _, e in pairs(block:getPossibleEntries()) do
        local d = Vector.getDistance(startLocation, e.position)
        if d < minD then
            minD, closestEntry = d, e
        end
    end
    return closestEntry
end

--- Trim a row of the ending headland at the center headland row leading to the end of the field
---@return boolean true if row was trimmed at the start
function FieldworkCourseTwoSided:_trim(row, middleHeadlandRow)
    local intersections = row:getIntersections(middleHeadlandRow)
    if #intersections == 0 then
        return
    end
    -- where is the longer part?
    local is = intersections[1]
    local lengthFromIntersectionToEnd = row:getLengthBetween(is.ixA)
    if lengthFromIntersectionToEnd < row:getLength() / 2 then
        -- shorter part towards the end
        row:cutEndAtIx(is.ixA)
        row:append(is.is)
        row:calculateProperties()
        return false
    else
        -- shorter part towards the start
        row:cutStartAtIx(is.ixA + 1)
        row:prepend(is.is)
        row:calculateProperties()
        return true
    end
    -- Block:finalize() will adjust the row length according to the headland angle
end


--- Create the boundary around the center from the headlands we generated on three sides and
--- from the field boundary
function FieldworkCourseTwoSided:_createCenterBoundary()
    local centerBoundary = Polygon()
    -- connect the start side to the center
    centerBoundary:appendMany(self.startHeadlandBlock:getLastRow())
    centerBoundary:appendMany(self.middleHeadlandBlock:getFirstRow())
        centerBoundary:calculateProperties()
    -- extend to make sure it'll intersect
    local is = centerBoundary:extendEnd(1):getIntersections(self.endSideBoundary)[1]
    if is == nil then
        self.endSideBoundary:calculateProperties()
        CourseGenerator.addDebugPolyline(centerBoundary, {0, 0, 1})
        CourseGenerator.addDebugPolyline(self.endSideBoundary, {0, 0, 1})
        self.logger:warning('Can\'t find ending part of center boundary')
        return
    end
    centerBoundary:cutEndAtIx(is.ixA)
    centerBoundary:append(is.is)
    centerBoundary:calculateProperties()
    -- connect the center to the end side
    local endingRow = self.endHeadlandBlock:getLastRow():clone()
    if self.context.nHeadlands % 2 == 0 then
        endingRow:reverse()
    end
    centerBoundary:appendMany(endingRow)

    -- This is the center point of the side opposite to the headland, this is where
    -- the center rows generation should be starting
    local baselineLocation = (centerBoundary[1] + centerBoundary[#centerBoundary]) / 2

    -- extend the start/end so they intersect the virtual headland, and then cut the fourth side
    -- out of the virtual headland
    local p = self.virtualHeadland:getPolygon()
    local startHelper = self.startHeadlandBlock:getLastRow():clone():extendStart(2 * self.context.workingWidth)
    local isStart = startHelper:getIntersections(p)[1]
    local endHelper = endingRow:extendEnd(2 * self.context.workingWidth)
    local isEnd = endHelper:getIntersections(p)[1]
    if isEnd == nil or isStart == nil then
        self.logger:warning('Can\t find closing part of center boundary')
        return
    end
    local fourthSide = p:getShortestPathBetween(isStart.ixB, isEnd.ixB):clone()
    self:_trim(fourthSide, startHelper)
    self:_trim(fourthSide, endHelper)
    fourthSide:calculateProperties()

    -- reverse the 4th side when needed to make sure its start is connected to the 3rd side of the center boundary
    local closest = fourthSide:findClosestVertexToPoint(centerBoundary[#centerBoundary])
    if closest.ix > #fourthSide / 2 then
        centerBoundary:append(isEnd.is)
        fourthSide:reverse()
        fourthSide:cutStartAtIx(2)
    else
        centerBoundary:append(isStart.is)
    end
    CourseGenerator.addDebugPolyline(fourthSide, { 0, 1, 1, 1 })
    CourseGenerator.addDebugPolyline(centerBoundary, { 0, 1, 0, 1 })

    centerBoundary:appendMany(fourthSide)
    centerBoundary:calculateProperties()
    return centerBoundary, baselineLocation
end

---@class CourseGenerator.FieldworkCourseTwoSided : CourseGenerator.FieldworkCourse
CourseGenerator.FieldworkCourseTwoSided = FieldworkCourseTwoSided
