--- An up/down row (swath) in the middle of the field (the area surrounded by the field boundary or the
--- innermost headland).
---@class Row : Polyline
local Row = CpObject(Polyline)

---@param vertices table[] array of tables with x, y (Vector, Vertex, State3D or just plain {x, y}
function Row:init(workingWidth, vertices)
    Polyline.init(self, vertices)
    self.workingWidth = workingWidth
    self.logger = Logger('Row ' .. tostring(self.rowNumber), Logger.level.debug)
end

function Row:setRowNumber(n)
    self.rowNumber = n
end

function Row:setBlockNumber(n)
    self.blockNumber = n
end

--- Sequence number to keep the original row sequence for debug purposes
function Row:setOriginalSequenceNumber(n)
    self.sequenceNumber = n
end

function Row:getOriginalSequenceNumber()
    return self.sequenceNumber
end

function Row:clone()
    local clone = CourseGenerator.Row(self.workingWidth)
    for _, v in ipairs(self) do
        clone:append(v:clone())
    end
    clone:calculateProperties()
    clone.preserveOrchardEndpoints = self.preserveOrchardEndpoints
    clone.blockNumber = self.blockNumber
    clone.sequenceNumber = self.sequenceNumber
    clone.startHeadlandAngle, clone.endHeadlandAngle = self.startHeadlandAngle, self.endHeadlandAngle
    clone.startsAtHeadland, clone.endsAtHeadland = self.startsAtHeadland, self.endsAtHeadland
    return clone
end

--- Create a row parallel to this one at offset distance.
---@param offset number distance of the new row. New row will be on the left side
--- (looking at increasing vertex indices) when offset > 0, right side otherwise.
function Row:createNext(offset)
    if offset >= 0 then
        return CourseGenerator.Offset.generate(self, Vector(0, 1), offset)
    else
        return CourseGenerator.Offset.generate(self, Vector(0, -1), -offset)
    end
end

--- Override Polyline:createOffset() to make sure the offset is an instance of Row
function Row:createOffset(offsetVector, minEdgeLength, preserveCorners)
    local offsetRow = CourseGenerator.Row(self.workingWidth)
    return self:_createOffset(offsetRow, offsetVector, minEdgeLength, preserveCorners)
end

--- Does the other row overlap this one?
---@param other CourseGenerator.Row
---@return boolean
function Row:overlaps(other)
    -- for simplicity, use a simple line segment instead of a polyline, rows are
    -- more or less straight anyway
    local myEndToEnd = CourseGenerator.LineSegment.fromVectors(self[1], self[#self])
    local otherEndToEnd = CourseGenerator.LineSegment.fromVectors(other[1], other[#other])
    return myEndToEnd:overlaps(otherEndToEnd)
end

--- Split a row at its intersections with the field boundary and with big islands.
--- In the trivial case of a rectangular field, this returns an array with a single row element,
--- the line between the two points where the row intersects the boundary.
---
--- In complex cases, with concave fields, the result may be more than one segments (rows)
--- so for any section of the row which is within the boundary there'll be one entry in the
--- returned array.
---
--- Big islands in the field also split a row which intersects them. We just drive around
--- smaller islands but at bigger ones it is better to end the row and turn around into the next.
---
---@param headland CourseGenerator.Headland the field boundary (or innermost headland)
---@param bigIslands CourseGenerator.Island[] islands big enough to split a row (we'll not just drive around them but turn)
---@param onlyFirstAndLastIntersections boolean|nil ignore all intersections between the first and the last. This makes
--- only sense if there are no islands.
---@param enableSmallOverlaps boolean|nil if true, and the row is almost parallel to the boundary and crosses it
--- multiple times (for instance a slightly zigzagging headland), do not split the row unless it is getting too
--- far from the boundary (it is like a smart version of onlyFirstAndLastInterSections, but significantly will slow
--- down the generation)
---@return CourseGenerator.Row[]
function Row:split(headland, bigIslands, onlyFirstAndLastIntersections, enableSmallOverlaps)
    if self.preserveOrchardEndpoints then
        local section = self:clone()
        section.preserveOrchardEndpoints = true
        section.startHeadlandAngle, section.endHeadlandAngle = math.pi / 2, math.pi / 2
        section.startsAtHeadland, section.endsAtHeadland = headland, headland
        section:setEndAttributes()
        return { section }
    end
    -- get all the intersections with the field boundary
    local intersections = self:getIntersections(headland:getPolygon(), 1,
            {
                isEnteringField = function(is)
                    -- when entering a field boundary polygon, we move on to the field
                    -- use the requested chirality of the headland as it may have loops in there which
                    -- will fool the isEntering functions
                    return self:isEntering(headland:getPolygon(), is, headland:getRequestedClockwise())
                end,
                headland = headland
            }
    )

    if #intersections < 2 then
        self.logger:trace('Row has only %d intersection with headland %d', #intersections, headland:getPassNumber())
        return {}
    end
    self.logger:trace('Row has %d intersection(s) with headland %d', #intersections, headland:getPassNumber())

    if onlyFirstAndLastIntersections then
        intersections[2] = intersections[#intersections]
        for _ = 3, #intersections do
            table.remove(intersections)
        end
    end

    -- then get all the intersections with big islands
    for _, island in ipairs(bigIslands) do
        local outermostIslandHeadland = island:getOutermostHeadland()
        local islandIntersections = self:getIntersections(outermostIslandHeadland:getPolygon(), 1,
                {
                    isEnteringField = function(is)
                        -- when entering an island headland, we move off the field
                        return not self:isEntering(outermostIslandHeadland:getPolygon(), is)
                    end,
                    headland = outermostIslandHeadland
                }
        )

        self.logger:trace('Row has %d intersections with island %d', #islandIntersections, island:getId())
        for _, is in ipairs(islandIntersections) do
            table.insert(intersections, is)
        end
        table.sort(intersections)
    end
    -- At this point, intersections contains all intersections of the row with the field boundary and any big islands,
    -- in the order the row crosses them.

    -- The assumption here is that the row always begins outside of the boundary. So whenever we cross a field boundary
    -- entering, we are on the field, whenever cross an island headland, we move off the field.

    -- This is also to properly handle the cases where the boundary intersects with
    -- itself, for instance with fields where the total width of headlands are greater than the
    -- field width (irregularly shaped fields, like ones with a peninsula)
    -- we start outside of the boundary. If we cross it entering, we'll decrement this, if we cross leaving, we'll increment it.
    local outside = 1
    -- we left the field but staying very close to the headland, so from a practical perspective it does not
    -- make sense to split the row and potentially creating a new block
    local outsideButClose = false
    local lastInsideIx
    local sections = {}
    for i = 1, #intersections do
        -- getUserData() depends on if this is a field boundary or an island
        local isEnteringField = intersections[i]:getUserData().isEnteringField(intersections[i])
        -- For the case when the row begins on a big island and the headland is bypassing that big island,
        -- meaning that there will be two intersections, at the exact same position, one with the island,
        -- and another with the headland, we'd enter the field twice (outside == -1). Don't let the inside
        -- counter go below 0 here
        outside = math.max(0, outside + (isEnteringField and -1 or 1))
        if not isEnteringField and outside == 1 then
            if not enableSmallOverlaps or (enableSmallOverlaps and
                    not self:_isSectionCloseToHeadland(intersections[i]:getUserData().headland:getPolygon(), intersections[i], intersections[i + 1])) then
                -- exiting the polygon and we were inside before (outside was 0)
                -- create a section here
                local section = self:_cutAtIntersections(intersections[lastInsideIx], intersections[i])
                -- remember the angle we met the headland so we can adjust the length of the row to have 100% coverage
                -- skip very short rows, if it is shorter than the working width then the area will
                -- be covered anyway by the headland passes
                if section:getLength() < self.workingWidth then
                    self.logger:trace('ROW TOO SHORT %.1f, %s', section:getLength(), intersections[i])
                else
                    section.startHeadlandAngle = intersections[lastInsideIx]:getAngle()
                    -- remember at what headland the row ends
                    section.startsAtHeadland = intersections[lastInsideIx]:getUserData().headland
                    section.endHeadlandAngle = intersections[i]:getAngle()
                    section.endsAtHeadland = intersections[i]:getUserData().headland
                    section:setEndAttributes()
                    table.insert(sections, section)
                end
                outsideButClose = false
            else
                outsideButClose = true
            end
        elseif isEnteringField then
            if not outsideButClose then
                lastInsideIx = i
            end
        end
    end
    return sections
end

--- Get the coordinates in the middle of the row, for instance to display the row number. Assumes
--- that the vertices are approximately evenly distributed
---@return Vector coordinates of the middle of the row
function Row:getMiddle()
    if #self % 2 == 0 then
        -- even number of vertices, return a point between the middle two
        local left = self[#self / 2]
        local right = self[#self / 2 + 1]
        return (left + right) / 2
    else
        -- odd number of vertices, return the middle one
        return self[math.floor(#self / 2)]
    end
end

--- What is on the left and right side of the row?
function Row:setAdjacentRowInfo(rowOnLeftWorked, rowOnRightWorked, leftSideBlockBoundary, rightSideBlockBoundary)
    self.rowOnLeftWorked = rowOnLeftWorked
    self.rowOnRightWorked = rowOnRightWorked
    self.leftSideBlockBoundary = leftSideBlockBoundary
    self.rightSideBlockBoundary = rightSideBlockBoundary
end

--- Update the attributes of the first and last vertex of the row based on the row's properties.
--- We use these attributes when finding an entry to a block, to see if the entry is on an island headland
--- or not. The attributes are set when the row is split at headlands but may need to be reapplied when
--- we adjust the end of the row as we may remove the first/last vertex.
function Row:setEndAttributes()
    -- A reversed row can still carry the original endpoint flags.
    self:setAttribute(1, CourseGenerator.WaypointAttributes.setRowEnd, false)
    self:setAttribute(1, CourseGenerator.WaypointAttributes.setRowStart, true)
    self:setAttribute(1, CourseGenerator.WaypointAttributes._setAtHeadland, self.startsAtHeadland)
    self:setAttribute(1, CourseGenerator.WaypointAttributes.setAtBoundaryId, self.startsAtHeadland:getBoundaryId())
    self:setAttribute(#self, CourseGenerator.WaypointAttributes.setRowEnd, true)
    self:setAttribute(#self, CourseGenerator.WaypointAttributes.setRowStart, false)
    self:setAttribute(#self, CourseGenerator.WaypointAttributes._setAtHeadland, self.endsAtHeadland)
    self:setAttribute(#self, CourseGenerator.WaypointAttributes.setAtBoundaryId, self.endsAtHeadland:getBoundaryId())
end

function Row:setAllAttributes()
    self:setEndAttributes()
    self:setAttribute(nil, CourseGenerator.WaypointAttributes.setRowNumber, self.rowNumber)
    self:setAttribute(nil, CourseGenerator.WaypointAttributes.setBlockNumber, self.blockNumber)
    self:setAttribute(nil, CourseGenerator.WaypointAttributes.setLeftSideWorked, self.rowOnLeftWorked)
    self:setAttribute(nil, CourseGenerator.WaypointAttributes.setRightSideWorked, self.rowOnRightWorked)
    self:setAttribute(nil, CourseGenerator.WaypointAttributes.setLeftSideBlockBoundary, self.leftSideBlockBoundary)
    self:setAttribute(nil, CourseGenerator.WaypointAttributes.setRightSideBlockBoundary, self.rightSideBlockBoundary)
end

function Row:reverse()
    Polyline.reverse(self)
    self.startHeadlandAngle, self.endHeadlandAngle = self.endHeadlandAngle, self.startHeadlandAngle
    self.startsAtHeadland, self.endsAtHeadland = self.endsAtHeadland, self.startsAtHeadland
    self.rowOnLeftWorked, self.rowOnRightWorked = self.rowOnRightWorked, self.rowOnLeftWorked
    self.leftSideBlockBoundary, self.rightSideBlockBoundary = self.rightSideBlockBoundary, self.leftSideBlockBoundary
end

--- Adjust the length of this row for full coverage where it meets the headland or field boundary
--- The adjustment depends on the angle the row meets the boundary/headland. In case of a headland,
--- and an angle of 90 degrees, we don't have to drive all the way up to the headland centerline, only
--- half workwidth.
--- In case of a field boundary we have to drive up all the way to the boundary.
--- The value obviously depends on the angle.
---@param context CourseGenerator.FieldworkContext The context to get the row width and the headland width to calculate
--- the length of the row. These can be different when generating courses for multiple vehicles.
function Row:adjustLength(context)
    if self.preserveOrchardEndpoints then return end
    CourseGenerator.FieldworkCourseHelper.adjustLengthAtStart(self, context, self.startHeadlandAngle)
    CourseGenerator.FieldworkCourseHelper.adjustLengthAtEnd(self, context, self.endHeadlandAngle)
end

--- Find the first two intersections with another polyline or polygon and replace the section
--- between those points with the vertices of the other polyline or polygon.
---@param context CourseGenerator.FieldworkContext
---@param other Polyline
---@param startIx number index of the vertex we want to start looking for intersections.
---@param circle boolean when true, make a full circle on the other polygon, else just go around and continue
---@return boolean, number true if there was an intersection and we actually went around, index of last vertex
--- after the bypass
function Row:bypassSmallIsland(context, other, startIx, circle)
    return CourseGenerator.FieldworkCourseHelper.bypassSmallIsland(self, context, other, startIx, circle)
end

------------------------------------------------------------------------------------------------------------------------
--- Private functions
------------------------------------------------------------------------------------------------------------------------

function Row:_cutAtIntersections(is1, is2)
    local section = CourseGenerator.Row(self.workingWidth)
    -- want a Row to be returned, not a Polyline
    return Polyline._cutAtIntersections(self, is1, is2, section)
end

--- Does the section of row between the intersections is1 and is2 with the headland remain close to the headland?
--- This is to avoid splitting a row when it crosses the headland multiple times but runs more ore less parallel
--- to the headland all the time. This can happen when the headland or the row or both are not perfectly straight.
--- Splitting a row in this case may generate multiple blocks which increase the complexity without bringing any
--- value in this case.
--- "Close" means never further away than half the working width.
---@param headland Polygon
---@param is1 CourseGenerator.Intersection
---@param is2 CourseGenerator.Intersection
function Row:_isSectionCloseToHeadland(headland, is1, is2)
    if is1 == nil or is2 == nil or headland == nil then
        return false
    end
    -- build two paths, each starting at is1 and ending at is2, one following the row, one the headland
    local rowSection = self:_cutAtIntersections(is1, is2)
    local headlandSection = headland:getShortestPathBetween(is1.ixB, is2.ixB)
    headlandSection:calculateProperties()
    headlandSection:cutStartAtIx(2)
    local sameDirection = is1:getAngle() < math.pi / 2
    if not sameDirection then
        headlandSection:reverse()
    end
    headlandSection:prepend(is1.is)
    headlandSection:append(is2.is)
    headlandSection:calculateProperties()
    -- now run along both paths and see how far we get from each other
    local rowSlider = CourseGenerator.Slider(rowSection, 1)
    local headlandSlider = CourseGenerator.Slider(headlandSection, 1)
    while rowSlider:move(1) and headlandSlider:move(1) do
        local d = (rowSlider:getBase() - headlandSlider:getBase()):length()
        if d > self.workingWidth / 2 then
            return false
        end
    end
    return true
end

---@class CourseGenerator.Row
CourseGenerator.Row = Row
