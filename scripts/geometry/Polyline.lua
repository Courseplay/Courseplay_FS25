---@class Polyline
Polyline = CpObject()

---@param vertices table[] array of tables with x, y (Vector, Vertex, State3D or just plain {x, y}
function Polyline:init(vertices)
    if vertices then
        for i, v in ipairs(vertices) do
            self[i] = Vertex(v.x, v.y, i)
        end
    end
    self.logger = Logger('Polyline', Logger.level.debug)
    self:calculateProperties()
end

--- Append a single vertex to the end of the polyline.
--- Calling calculateProperties() is the responsibility of the caller
---@param v table|Vertex table with x, y (Vector, Vertex, State3D or just plain {x, y}
--- if v is a Vertex, it will be cloned, otherwise a new vertex created
function Polyline:append(v)
    if v.is_a and v:is_a(Vertex) then
        table.insert(self, v:clone())
        self[#self].ix = #self
    else
        table.insert(self, Vertex(v.x, v.y, #self + 1))
    end
end

--- Append multiple vertices to the end of the polyline.
--- Calling calculateProperties() is the responsibility of the caller
--- if elements of p are Vertex, they will be cloned, otherwise a new vertex created for each
---@param p table|Vertex[]
function Polyline:appendMany(p)
    for _, v in ipairs(p) do
        self:append(v)
    end
end

--- Add v as the first vertex.
--- Calling calculateProperties() is the responsibility of the caller
---@param v table table with x, y (Vector, Vertex, State3D or just plain {x, y}
function Polyline:prepend(v)
    if v:is_a(Vertex) then
        table.insert(self, 1, v:clone())
    else
        table.insert(self, 1, Vertex(v.x, v.y, #self + 1))
    end
end

function Polyline:_getNewInstance()
    return Polyline()
end

function Polyline:clone()
    local clone = self:_getNewInstance()
    for _, v in ipairs(self) do
        clone:append(v:clone())
    end
    clone:calculateProperties()
    return clone
end

function Polyline:getRawIndex(n)
    return n
end

--- Returns the vertex at position n. In the derived polygon, will wrap around the ends, that is, will return
--- a valid vertex for -#self < n < 2 * #self.
function Polyline:at(n)
    return self[self:getRawIndex(n)]
end

--- Sets the vertex at position n. In the derived polygon, will wrap around the ends, that is, will return
--- a valid vertex for -#self < n < 2 * #self.
function Polyline:set(n, v)
    self[self:getRawIndex(n)] = v
end

--- Upper limit when iterating through the vertices, starting with 1 to fwdIterationLimit() (inclusive)
--- using i and i + 1 vertex in the loop. This will not wrap around the end.
function Polyline:fwdIterationLimit()
    return #self - 1
end

--- Get the center of the polyline (centroid, average of all vertices)
function Polyline:getCenter()
    local center = Vector(0, 0)
    for _, v in ipairs(self) do
        center = center + v
    end
    return center / #self
end

--- Get the bounding box
function Polyline:getBoundingBox()
    local xMin, xMax, yMin, yMax = math.huge, -math.huge, math.huge, -math.huge
    for _, v in ipairs(self) do
        xMin = math.min(xMin, v.x)
        yMin = math.min(yMin, v.y)
        xMax = math.max(xMax, v.x)
        yMax = math.max(yMax, v.y)
    end
    return xMin, yMin, xMax, yMax
end

function Polyline:getUnpackedVertices()
    local unpackedVertices = {}
    for _, v in ipairs(self) do
        table.insert(unpackedVertices, v.x)
        table.insert(unpackedVertices, v.y)
    end
    return unpackedVertices
end

--- vertex iterator
---@return number, Vertex, Vertex, Vertex the index, the vertex at index, the previous, and the next vertex.
--- previous and next may be nil
function Polyline:vertices(from, to)
    local i = from and from - 1 or 0
    local last = to or #self
    return function()
        i = i + 1
        if i > last then
            return nil, nil
        else
            return i, self[i], self[i - 1], self[i + 1]
        end
    end
end

--- edge iterator
---@param startIx number|nil start the iteration at the edge starting at the startIx vertex (or at the first)
---@param endIx number|nil the last edge to return is the one starting at endIx (or the last vertex)
---@return number, CourseGenerator.LineSegment, Vertex
function Polyline:edges(startIx, endIx)
    local i = startIx and startIx - 1 or 0
    local last = endIx or #self
    return function()
        i = i + 1
        if i >= last then
            return nil, nil, nil
        else
            return i, self[i]:getExitEdge() or CourseGenerator.LineSegment.fromVectors(self[i], self[i + 1]), self[i]
        end
    end
end

--- edge iterator backwards
---@return number, CourseGenerator.LineSegment, Vertex
function Polyline:edgesBackwards(startIx)
    local i = startIx and (startIx + 1) or (#self + 1)
    return function()
        i = i - 1
        if i < 2 then
            return nil, nil, nil
        else
            return i, self[i]:getEntryEdge() or CourseGenerator.LineSegment.fromVectors(self[i], self[i - 1]), self[i]
        end
    end
end

--- Get the length of the shortest edge (distance between vertices)
---@return number
function Polyline:getShortestEdgeLength()
    local shortest = math.huge
    for _, e in self:edges() do
        shortest = math.min(shortest, e:getLength())
    end
    return shortest
end

function Polyline:reverse()
    CourseGenerator.reverseArray(self)
    self:calculateProperties()
    return self
end

function Polyline:getLength()
    -- we cache the full length, and if it exists, return it
    if not self.length then
        -- otherwise calculate length
        local length = 0
        for _, e in self:edges() do
            length = length + e:getLength()
        end
        self.length = length
    end
    return self.length
end

function Polyline:getLengthBetween(startIx, endIx)
    local length = 0
    for _, e in self:edges(startIx, endIx) do
        length = length + e:getLength()
    end
    return length
end

---@return number index of the first vertex which is at least d distance from ix
---(can be nil if the end of line reached before d)
function Polyline:moveForward(ix, d)
    local i, dElapsed = ix, 0
    while i < #self do
        if dElapsed >= d then
            return i
        end
        dElapsed = dElapsed + self:at(i):getExitEdge():getLength()
        i = i + 1
    end
    return nil
end

---@param length number the polyline is extended forward (last vertex moved)
function Polyline:extendEnd(length)
    local newEntryEdge = self[#self]:getEntryEdge()
    newEntryEdge:extend(length)
    self[#self] = Vertex.fromVector(newEntryEdge:getEnd())
    self:calculateProperties(#self - 1)
    return self
end

---@param length number the polyline is extended backwards (first vertex moved).
function Polyline:extendStart(length)
    local newExitEdge = self[1]:getExitEdge()
    newExitEdge:extend(-length)
    self[1] = Vertex.fromVector(newExitEdge:getBase())
    self:calculateProperties(1, 2)
    return self
end

---@param length number shorten the Polyline at the last vertex
function Polyline:cutEnd(length)
    if #self == 2 then
        local theOnlyEdge = self[1]:getExitEdge()
        theOnlyEdge:setLength(theOnlyEdge:getLength() - length)
        self[2] = Vertex.fromVector(theOnlyEdge:getEnd())
        self:calculateProperties(1, 2)
    else
        local d = length
        while d > 0 and #self > 2 do
            d = d - self[#self]:getEntryEdge():getLength()
            self[#self] = nil
        end
        -- this still exists, pointing to the last vertex we just removed
        local newExitEdge = self[#self]:getExitEdge()
        newExitEdge:setLength(-d)
        self[#self] = Vertex.fromVector(newExitEdge:getEnd())
        self:calculateProperties(#self - 1)
    end
end
---
---@param length number shorten the polyline at the first vertex
function Polyline:cutStart(length)
    if #self == 2 then
        local theOnlyEdge = self[1]:getExitEdge()
        theOnlyEdge:setLength(length)
        self[1] = Vertex.fromVector(theOnlyEdge:getEnd())
    else
        local d, lastEdge = length, self[1]:getExitEdge()
        while d > 0 and #self > 2 do
            lastEdge = self[1]:getExitEdge()
            d = d - lastEdge:getLength()
            table.remove(self, 1)
        end
        lastEdge:setLength(lastEdge:getLength() - (-d))
        self[1] = Vertex.fromVector(lastEdge:getEnd())
    end
    self:calculateProperties(1, 2)
end

--- Cut all vertices from the first vertex up to but not including ix, shortening the polyline at the start
---@param ix number
function Polyline:cutStartAtIx(ix)
    if ix >= #self then
        return
    end
    ix = math.min(ix - 1, #self - 2)
    for _ = 1, ix do
        table.remove(self, 1)
    end
    self:calculateProperties(1, 2)
end

--- Cut all vertices from ix (not including) to the last vertex, shortening the polyline at the end
---@param ix number
function Polyline:cutEndAtIx(ix)
    for _ = #self, ix + 1, -1 do
        table.remove(self)
    end
    self:calculateProperties(ix - 1, ix)
end

--- Cut this polyline where it first intersects with other and keep the longer part
---@param other Polyline
function Polyline:trimAtFirstIntersection(other)
    local intersections = self:getIntersections(other)
    if #intersections == 0 then
        return
    end
    -- where is the longer part?
    local lengthFromIntersectionToEnd = self:getLengthBetween(intersections[1].ixA)
    if lengthFromIntersectionToEnd < self:getLength() / 2 then
        -- shorter part towards the end
        self:cutEndAtIx(intersections[1].ixA)
    else
        -- shorter part towards the start
        self:cutStartAtIx(intersections[1].ixA + 1)
    end
end

--- Calculate all interesting properties we may need later for more advanced functions
---@param from number index of vertex to start the calculation, default 1
---@param to number index of last vertex to use in the calculation, default #self
function Polyline:calculateProperties(from, to)
    for i, current, previous, next in self:vertices(from, to) do
        current.ix = i
        current:calculateProperties(previous, next)
    end
    -- mark dirty
    self.length = nil
end

--- If there is a sudden direction change almost 180 degrees at a vertex, remove that vertex.
function Polyline:removeGlitches()
    local i = 1
    while i < #self do
        local dA = self:at(i).dA
        if dA and math.abs(dA) > math.pi - 0.2 then
            table.remove(self, i)
        else
            i = i + 1
        end
    end
    self:calculateProperties()
end

function Polyline:_canRemoveVertex(i, maxDeltaAngle)
    if not maxDeltaAngle then
        return true
    else
        -- only remove vertices which aren't around a corner
        return math.abs(self:at(i + 1).dA) < maxDeltaAngle and math.abs(self:at(i).dA) < maxDeltaAngle
    end
end


--- If two vertices are closer than minimumLength, replace them with one between.
---@param minimumLength number After this operation, no two vertices will be closer than minimumLength
---@param maxDeltaAngle number|nil when specified, vertices where the delta angle is bigger than this are not removed,
--- thus, corners are preserved
function Polyline:ensureMinimumEdgeLength(minimumLength, maxDeltaAngle)
    local i = 1
    while i < #self do
        if (self:at(i + 1) - self:at(i)):length() < minimumLength and self:_canRemoveVertex(i, maxDeltaAngle) then
            table.remove(self, i + 1)
        else
            i = i + 1
        end
    end
    self:calculateProperties()
end

--- If two vertices are further than maximumLength apart, add a vertex between them. If the
--- delta angle at the first vertex is less than maxDeltaAngleForOffset, also offset the new vertex
--- to the left/right from the edge in an effort trying to follow a curve.
--- Use this to fix a polyline with many vertices where some edges may be slightly longer than the
--- maximum. Use splitEdges() instead if you have just a few (as little as 2) vertices and
--- need a vertex at every given distance
---@param maximumLength number|nil default CourseGenerator.cMaxEdgeLength,
---@param maxDeltaAngleForOffset number|nil default CourseGenerator.cMaxDeltaAngleForMaxEdgeLength
function Polyline:ensureMaximumEdgeLength(maximumLength, maxDeltaAngleForOffset)
    maximumLength = maximumLength or CourseGenerator.cMaxEdgeLength
    maxDeltaAngleForOffset = maxDeltaAngleForOffset or CourseGenerator.cMaxDeltaAngleForMaxEdgeLength
    local i = 1
    while i <= self:fwdIterationLimit() do
        local exitEdge = CourseGenerator.LineSegment.fromVectors(self:at(i), self:at(i + 1))
        if exitEdge:getLength() > maximumLength then
            if math.abs(self:at(i).dA) < maxDeltaAngleForOffset then
                -- for higher angles, like corners, we don't want to round them out here.
                exitEdge:setHeading(exitEdge:getHeading() - self:at(i).dA / 2)
            end
            exitEdge:setLength(exitEdge:getLength() / 2)
            local v = exitEdge:getEnd()
            table.insert(self, i + 1, Vertex(v.x, v.y, i + 1))
            self:calculateProperties(i, i + 2)
            self.logger:trace('ensureMaximumEdgeLength: added a vertex after %d', i)
            i = i + 2
        else
            i = i + 1
        end
    end
end

--- Use splitEdges() if you have just a few (as little as 2) vertices and
--- need a vertex at every given distance
---@param maximumLength number if an edge is longer than maximumLength, split it into multiple
--- edges so none of the resulting edges will be longer than maximumLength
function Polyline:splitEdges(maximumLength)
    local i = 1
    while i <= self:fwdIterationLimit() do
        local exitEdge = CourseGenerator.LineSegment.fromVectors(self:at(i), self:at(i + 1))
        local totalLength = exitEdge:getLength()
        if totalLength > maximumLength then
            local length = maximumLength
            while length < totalLength do
                exitEdge:setLength(length)
                table.insert(self, i + 1, Vertex.fromVector(exitEdge:getEnd(), i + 1))
                length = length + math.min(totalLength - length, maximumLength)
                i = i + 1
            end
        end
        i = i + 1
    end
    self:calculateProperties()
end

---@param offsetVector Vector offset to move the edges, relative to the edge's direction
---@return CourseGenerator.LineSegment[] an array of edges parallel to the existing ones, same length
--- but offset by offsetVector
function Polyline:generateOffsetEdges(offsetVector)
    local offsetEdges = {}
    for _, e in self:edges() do
        local newOffsetEdge = e:clone()
        newOffsetEdge:offset(offsetVector.x, offsetVector.y)
        table.insert(offsetEdges, newOffsetEdge)
    end
    return offsetEdges
end

function Polyline:_cleanEdges(edges, startIx, cleanEdges, previousEdge, minEdgeLength, preserveCorners)
    for i = startIx, #edges do
        local currentEdge = edges[i]
        local gapFiller = CourseGenerator.LineSegment.connect(previousEdge, currentEdge, minEdgeLength, preserveCorners)
        if gapFiller then
            table.insert(cleanEdges, gapFiller)
        end
        table.insert(cleanEdges, currentEdge)
        previousEdge = currentEdge
    end
    return cleanEdges
end

--- Make sure the edges are properly connected, their ends touch nicely without gaps and never
--- extend beyond the vertex
---@param edges CourseGenerator.LineSegment[]
function Polyline:cleanEdges(edges, minEdgeLength, preserveCorners)
    return self:_cleanEdges(edges, 2, { edges[1] }, edges[1], minEdgeLength, preserveCorners)
end

--- Generate a polyline parallel to this one, offset by the offsetVector. Note that this works only
--- with either very low offsets or simple polylines with vertices far apart when using bigger offsets.
--- Use CourseGenerator.Offset.generate() if you want to avoid creating loops on the offset polyline.
---@param offsetVector Vector offset to move the edges, relative to the edge's direction
---@param minEdgeLength number see LineSegment.connect()
---@param preserveCorners number see LineSegment.connect()
function Polyline:createOffset(offsetVector, minEdgeLength, preserveCorners)
    local offsetPolyline = Polyline()
    return self:_createOffset(offsetPolyline, offsetVector, minEdgeLength, preserveCorners)
end

--- Ensure there are no sudden direction changes in the polyline, that is, at each vertex a vehicle
--- with turning radius r would be able to follow the line with less than cMaxCrossTrackError distance
--- from the corner vertex.
--- When such a corner is found, either make it rounder according to r, or make it sharp and mark it
--- as a turn waypoint.
---@param r number turning radius
---@param makeCorners boolean if true, make corners for turn maneuvers instead of rounding them.
---@param maxCrossTrackError number|nil maximum cross track error allowed before we start adjusting corners,
---defaults to CourseGenerator.cMaxCrossTrackError
function Polyline:ensureMinimumRadius(r, makeCorners, maxCrossTrackError)

    ---@param entry CourseGenerator.Slider
    ---@param exit CourseGenerator.Slider
    local function makeArc(entry, exit)
        local from = entry:getBaseAsState3D()
        local to = exit:getBaseAsState3D()
        return CourseGenerator.AnalyticHelper.getDubinsSolutionAsVertices(from, to, r)
    end

    ---@param entry CourseGenerator.Slider
    ---@param exit CourseGenerator.Slider
    local function makeCorner(entry, exit)
        entry:extendTo(exit)
        local corner = Vertex.fromVector(entry:getEnd())
        corner.isCorner = true
        return { corner }
    end

    local wrappedAround = false
    local currentIx
    local nextIx = 1
    repeat
        local debugId = CourseGenerator.getDebugId()
        currentIx = nextIx
        nextIx = currentIx + 1
        local xte = self:at(currentIx):getXte(r)
        local radius = self:at(currentIx):getRadius()
        if xte > (maxCrossTrackError or CourseGenerator.cMaxCrossTrackError) then
            self.logger:debug('ensureMinimumRadius (%s): found a corner at %d with r: %.1f, r: %.1f, xte: %.1f',
                    debugId, currentIx, radius, r, xte)
            -- looks like we can't make this turn without deviating too much from the course,
            local entry = CourseGenerator.Slider(self, currentIx, 0)
            local exit = CourseGenerator.Slider(self, currentIx, 0)
            local rMin
            -- we can move back a lot when rounding corners, but otherwise, limit that as we may end up
            -- being outside of the field with the corner...
            local step, totalMoved, maxDistanceToMove = 0.2, 0, r * (makeCorners and 2 or 10)
            repeat
                -- from the corner, start widening the gap until we can fit an
                -- arc with r between
                entry:move(-step)
                exit:move(step)
                totalMoved = totalMoved + step
                rMin = entry:getRadiusTo(exit)
                -- use a limit a bit over r, to make sure the Dubins generated won't end
                -- up as a loop because it can't fit between entry and exit
            until rMin >= 1.01 * r or totalMoved > maxDistanceToMove
            -- entry and exit are now far enough, so use the Dubins solver to effortlessly create a nice
            -- arc between the two, or, to make it a sharp corner, find the intersection of entry and exit
            local adjustedCornerVertices
            if makeCorners then
                if totalMoved < maxDistanceToMove then
                    adjustedCornerVertices = makeCorner(entry, exit)
                else
                    -- there are cases, for instance in narrow nooks which already have turns, where
                    -- it does not make sense trying to sharpen as we'll end up a very small angle with a
                    -- corner point very far away.
                    self[currentIx].isCorner = true
                    self.logger:warning(
                            'ensureMinimumRadius (%s): will not sharpen this corner, had to move too far (%.1f) back',
                            debugId, totalMoved)
                    CourseGenerator.addDebugPoint(entry:getBase(), debugId .. ' entry')
                    CourseGenerator.addDebugPoint(exit:getBase(), debugId .. ' exit')
                    CourseGenerator.addDebugPoint(self[currentIx], debugId .. ' center')
                end
            else
                adjustedCornerVertices = makeArc(entry, exit)
            end
            if adjustedCornerVertices and #adjustedCornerVertices >= 1 then
                -- remember the size before the replacement
                local sizeBeforeReplace = #self
                -- replace the section with an arc or a corner
                nextIx, wrappedAround = self:replace(entry.ix, exit.ix + 1, adjustedCornerVertices)
                self.logger:debug('ensureMinimumRadius (%s): replaced corner vertices between %d to %d with %d waypoint(s), continue at %d (of %d), wrapped around %s',
                        debugId, entry.ix, exit.ix, #adjustedCornerVertices, nextIx, #self, wrappedAround)
                if #self < sizeBeforeReplace then
                    self:calculateProperties(entry.ix - (sizeBeforeReplace - #self), nextIx)
                else
                    self:calculateProperties(entry.ix, nextIx)
                end
            else
                self.logger:debug('ensureMinimumRadius (%s): could not calculate adjusted corner vertices', debugId)
            end
        end
    until wrappedAround or currentIx >= #self

    self:ensureMinimumEdgeLength(CourseGenerator.cMinEdgeLength)
    if makeCorners then
        self:ensureMaximumEdgeLength(CourseGenerator.cMaxEdgeLength)
    end
    self:calculateProperties()
end

--- Find the first two intersections with another polyline or polygon and replace the section
--- between those points with the vertices of the other polyline or polygon.
---@param other Polyline
---@param startIx number index of the vertex we want to start looking for intersections.
---@param circle boolean when true, make a full circle on the other polygon, else just go around and continue
---@return boolean, number true if there were two intersections and we actually went around other (circle or not),
--- then the second return value is the index of last vertex, this is the startIx of the next call to goAround() should
--- be to continue looking for more intersections with other.
--- If false, and there was one intersection (meaning either the start or end of this polyline is within other, then return
--- the index on the polyline where it intersects other.
--- after the bypass
function Polyline:goAround(other, startIx, circle)
    local intersections = self:getIntersections(other, startIx)
    local is1, is2 = intersections[1], intersections[2]
    if is1 and is2 then
        -- we cross other completely, none of our ends are within other, there may be more intersections with other though
        return self:goAroundBetweenIntersections(other, circle, is1, is2)
    else
        -- there is one intersection only, one of our ends is within other, and there are no more intersections with other
        return false
    end
end

function Polyline:goAroundBetweenIntersections(other, circle, is1, is2)
    local pathA, pathB = other:_getPathBetweenIntersections(is1.ixB, is2.ixB)
    local path
    if pathA and pathB then
        local shortPath = pathA:getLength() < pathB:getLength() and pathA or pathB
        local longPath = pathA:getLength() >= pathB:getLength() and pathA or pathB
        self.logger:debug('path A: %.1f, path B: %.1f', pathA:getLength(), pathB:getLength())
        shortPath:setAttribute(nil, CourseGenerator.WaypointAttributes.setHeadlandPassNumber,
                self:at(is1.ixA):getAttributes():getHeadlandPassNumber())
        longPath:setAttribute(nil, CourseGenerator.WaypointAttributes.setHeadlandPassNumber,
                self:at(is1.ixA):getAttributes():getHeadlandPassNumber())
        if circle then
            path = shortPath:clone()
            path:setAttribute(nil, CourseGenerator.WaypointAttributes.setIslandBypass)
            longPath:reverse()
            path:appendMany(longPath)
            -- mark this roundtrip as island bypass
            path:setAttributes(#path - #longPath, #path, CourseGenerator.WaypointAttributes.setIslandBypass)
            path:appendMany(shortPath)
            self.logger:debug('Circled around, %d waypoints', #path)
        else
            path = shortPath
            self.logger:debug('Took the shorter path, no circle')
        end
    else
        path = pathA
    end
    table.insert(path, 1, Vertex.fromVector(is1.is))
    table.insert(path, Vertex.fromVector(is2.is))
    if path then
        local lastIx = self:replace(is1.ixA, is2.ixA + 1, path)
        -- make the transitions a little smoother
        self:calculateProperties()
        -- size may change after smoothing
        local oldSize = #self
        lastIx = CourseGenerator.SplineHelper.smooth(self, 1, is1.ixA, lastIx)
        self:calculateProperties()
        return true, lastIx
    else
        self.logger:warning('No path around other polygon found')
        return false
    end
end

---@param lineSegment CourseGenerator.LineSegment
---@return Vertex, number, Vertex, number the vertex closest to lineSegment, its distance, the vertex
--- farthest from the lineSegment, its distance
function Polyline:findClosestAndFarthestVertexToLineSegment(lineSegment)
    local dMin, closestVertex = math.huge, nil
    local dMax, farthestVertex = -math.huge, nil
    for _, v in self:vertices() do
        local thisD = lineSegment:getDistanceFrom(v)
        if thisD < dMin then
            dMin = thisD
            closestVertex = v
        end
        if thisD > dMax then
            dMax = thisD
            farthestVertex = v
        end
    end
    return closestVertex, dMin, farthestVertex, dMax
end

---@param point Vector
---@param isValidFunc function optional function accepting a Vertex and returning bool to determine if this
--- vertex should be considered at all
---@return Vertex
---@return number distance of the closest vertex from point
---@return number|nil distance of the point from exit (or if it does not exist, the entry) edge of the closest vertex
function Polyline:findClosestVertexToPoint(point, isValidFunc)
    local d, closestVertex = math.huge, nil
    for _, v in self:vertices() do
        if not isValidFunc or isValidFunc(v) then
            local dFromV = (point - v):length()
            if dFromV < d then
                d = dFromV
                closestVertex = v
            end
        end
    end
    local distanceFromEdge
    if closestVertex then
        if closestVertex:getExitEdge() then
            distanceFromEdge = closestVertex:getExitEdge():getDistanceFrom(point)
        elseif closestVertex:getEntryEdge() then
            distanceFromEdge = closestVertex:getEntryEdge():getDistanceFrom(point)
        end
        return closestVertex, d, distanceFromEdge
    end
end

--- Does this line intersects the other?
---
--- This is a faster version of getIntersections() for the case where we only want to
--- know if they intersect or not.
---
---@param other Polyline
---@return boolean
function Polyline:intersects(other)
    for _, edge, _ in self:edges() do
        for _, otherEdge in other:edges() do
            local is = edge:intersects(otherEdge)
            if is then
                return true
            end
        end
    end
    return false
end

------------------------------------------------------------------------------------------------------------------------
--- Private functions
------------------------------------------------------------------------------------------------------------------------

--- Get all intersections with other, in the order we would meet them traversing self in the increasing index direction
---@param other Polyline
---@param startIx number index to start looking for intersections with other
---@param userData any user data to add to the Intersection objects (to later identify them)
---@return CourseGenerator.Intersection[] list of intersections
function Polyline:getIntersections(other, startIx, userData)
    local intersections = {}
    for i, edge, _ in self:edges(startIx) do
        for j, otherEdge in other:edges() do
            local is = edge:intersects(otherEdge)
            if is then
                -- do not add an intersection twice if it goes exactly through a vertex
                if #intersections == 0 or (intersections[#intersections].is ~= is) then
                    table.insert(intersections, CourseGenerator.Intersection(i, j, is, edge, otherEdge, userData))
                end
            end
        end
    end
    table.sort(intersections)
    return intersections
end

--- Is this polyline entering the other polygon at intersection point is?
---@param other Polygon
---@param is CourseGenerator.Intersection
---@param clockwiseOverride boolean use this clockwise setting instead of other's isClockwise() function
---@return boolean true if self is entering the other polygon, false when exiting, when moving in
--- the direction of increasing indexes
function Polyline:isEntering(other, is, clockwiseOverride)
    local otherEdge = other:at(is.ixB):getExitEdge()
    return self:at(is.ixA):getExitEdge():isEntering(clockwiseOverride or other:isClockwise(), otherEdge)
end

--- Replace all vertices between fromIx and toIx (excluding) with the entries in vertices
---@param fromIx number index of last vertex to keep
---@param toIx number index of first vertex to keep, toIx must be >= fromIx, unless wrapping around on a Polygon
---@param vertices Vector[] new vertices to put between fromIx and toIx
---@return number, boolean index of the next vertex after the replaced ones (may be more or less than toIx depending on
--- how many entries vertices had and how many elements were there originally between fromIx and toIx. The boolean
--- is true when wrapped around the end (for a polygon)
function Polyline:replace(fromIx, toIx, vertices)
    -- mark the ones we need to replace/remove. this is to make the rollover case (for polygons) easier
    for i = fromIx + 1, toIx - 1 do
        self[self:getRawIndex(i)].toBeReplaced = true
    end

    local sourceIx = 1
    local destIx = CourseGenerator.WrapAroundIndex(self, fromIx + 1)
    while self[destIx:get()] and self[destIx:get()].toBeReplaced do
        if sourceIx <= #vertices then
            local newVertex = vertices[sourceIx]:clone()
            newVertex.color = { 0, 1, 0 } -- for debug only
            self[destIx:get()] = newVertex
            self.logger:trace('Replaced %d with %s', destIx:get(), newVertex)
            destIx = destIx + 1
        else
            table.remove(self, destIx:get())
            self.logger:trace('Removed %d', destIx:get())
            -- just in case we happened to remove the last element of the table, reset destIx to the max index
            destIx:set(destIx:get())
        end
        sourceIx = sourceIx + 1
    end
    while sourceIx <= #vertices do
        -- we have some vertices left, but there is no room for them
        local newVertex = vertices[sourceIx]:clone()
        newVertex.color = { 1, 0, 0 } -- for debug only
        table.insert(self, destIx:get(), newVertex)
        self.logger:trace('Adding %s at %d', newVertex, destIx:get())
        sourceIx = sourceIx + 1
        destIx = destIx + 1
    end
    return destIx:get(), destIx:get() < fromIx
end

--- Get a reference to a contiguous segment of vertices of a polyline. Note that
--- these are references of the original vertices, not copies!
---@param fromIx number index of first vertex in the segment, not including? or is it?
---@param toIx number index of last vertex in the segment, not including? or is it?
---@return Polyline
function Polyline:_getPathBetween(fromIx, toIx)
    local segment = Polyline()
    local step = fromIx <= toIx and 1 or -1
    for i = fromIx, toIx, step do
        table.insert(segment, self:at(i))
    end
    return segment
end

--- If fromIx and toIx are the vertex indices where edges intersecting another polyline _start_,
--- get the vertices between the two intersection points.
---@param fromIx number
---@param toIx number
function Polyline:_getPathBetweenIntersections(fromIx, toIx)
    local from, to
    if fromIx <= toIx then
        -- toIx is the start of an edge, add the end of that edge too
        from, to = fromIx + 1, toIx
    else
        -- fromIx is the start of an edge, add the end of that edge too
        from, to = fromIx, toIx + 1
    end
    return self:_getPathBetween(from, to)
end

--- Set an attribute for a series of vertices
---@param first number | nil index of first vertex to set the attribute for
---@param last number | nil index of last vertex
---@param setter CourseGenerator.WaypointAttributes function to call on each vertex' attributes
---@param ... any arguments for setter
function Polyline:setAttributes(first, last, setter, ...)
    first = first or 1
    last = last or #self
    for i = first, last do
        setter(self:at(i):getAttributes(), ...)
    end
end

--- Set an attribute for a single vertex (or all)
---@param ix number|nil index of vertex to set the attribute for, if nil, the attribute is set for all vertices
---@param setter CourseGenerator.WaypointAttributes function to call on each vertex' attributes
---@param ... any arguments for setter
function Polyline:setAttribute(ix, setter, ...)
    self:setAttributes(ix, ix, setter, ...)
end

--- Remove all existing vertices
---@param ix number optional start index
function Polyline:_reset(ix)
    for i = ix or 1, #self do
        self[i] = nil
    end
    self.deltaAngle, self.area, self.length = nil, nil, nil
end

--- Private function to use derived classes, in order to instantiate a result which is an instance of
--- the derived class.
---@param result Polyline
function Polyline:_createOffset(result, offsetVector, minEdgeLength, preserveCorners)
    local offsetEdges = self:generateOffsetEdges(offsetVector)
    local cleanOffsetEdges = self:cleanEdges(offsetEdges, minEdgeLength, preserveCorners)

    for _, e in ipairs(cleanOffsetEdges) do
        result:append(e:getBase())
    end
    result:append(cleanOffsetEdges[#cleanOffsetEdges]:getEnd())
    result:calculateProperties()
    return result
end


------ Cut a polyline at is1 and is2, keeping the section between the two. is1 and is2 becomes the start and
--- end of the cut polyline.
---@param is1 CourseGenerator.Intersection
---@param is2 CourseGenerator.Intersection
---@param section Polyline|nil an optional, initialized object that will become the section
---@return Polyline
function Polyline:_cutAtIntersections(is1, is2, section)
    section = section or Polyline()
    section:append(is1.is)
    local src = is1.ixA + 1
    while src < is2.ixA do
        section:append(self[src])
        src = src + 1
    end
    section:append(is2.is)
    section:calculateProperties()
    return section
end

function Polyline:__tostring()
    local result = ''
    for i, v in ipairs(self) do
        result = result .. string.format('%d %s %s\n', i, v, v.xte)
    end
    return result
end