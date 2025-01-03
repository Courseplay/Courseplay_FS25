local Headland = CpObject()

--- Headlands around the field will always have a boundary ID starting with 'F' (for field)
Headland.boundaryIdPrefix = 'F'

--- Create a headland from a base polygon. The headland is a new polygon, offset by width, that is, inside
--- of the base polygon.
---
--- This is for headlands around a field boundary. For headlands around and island, use IslandHeadland()
---
---@param basePolygon Polygon
---@param clockwise boolean the direction of the headland. We want this explicitly stated and not derived from
--- basePolygon as on fields with odd shapes (complex polygons) headlands may intersect themselves making
--- a clear definition of clockwise/counterclockwise impossible. This is the required direction for all headlands.
---@param passNumber number of the headland pass, the outermost is 1
---@param width number
---@param outward boolean if true, the generated headland will be outside of the basePolygon, inside otherwise
---@param mustNotCross|nil Polygon the headland must not cross this polygon, if it does, it is invalid. This is usually
--- the outermost headland around the field, as when anything crosses that, it'll be at least partly outside of the field.
function Headland:init(basePolygon, clockwise, passNumber, width, outward, mustNotCross)
    self.logger = Logger('Headland ' .. passNumber or '', nil, CpDebug.DBG_COURSES)
    self.clockwise = clockwise
    self.passNumber = passNumber
    self.offsetVector = CourseGenerator.FieldworkCourseHelper.getOffsetVectorForHeadland(clockwise, outward)
    if width == 0 then
        self.logger:debug('cloning base polygon as width 0, base clockwise %s, desired clockwise %s',
                basePolygon:isClockwise(), self.clockwise)
        self.polygon = basePolygon:clone()
    else
        self.logger:debug('start generating, base clockwise %s, desired clockwise %s, width %.1f, outward: %s',
                basePolygon:isClockwise(), self.clockwise, width, outward)
        self.polygon = CourseGenerator.Offset.generate(basePolygon:clone(), self.offsetVector, width)
    end
    if self.polygon then
        self.polygon:calculateProperties()
        self.polygon:ensureMaximumEdgeLength(CourseGenerator.cMaxEdgeLength)
        self.polygon:calculateProperties()
        if mustNotCross and self.polygon:intersects(mustNotCross) then
            self.polygon = nil
            self.logger:warning('would intersect outermost headland, discarding.')
        else
            -- TODO: when removing loops, we may end up not covering the entire field on complex polygons
            -- consider making the headland invalid if it has loops, instead of removing them
            self.logger:debug('polygon with %d vertices generated, area %.1f, cw %s, desired cw %s',
                    #self.polygon, self.polygon:getArea(), self.polygon:isClockwise(), clockwise)
            if #self.polygon < 3 then
                self.logger:warning('invalid headland, polygon too small (%d vertices)', #self.polygon)
                self.polygon = nil
            elseif self.polygon:isClockwise() ~= nil and self.polygon:isClockwise() ~= clockwise and clockwise ~= nil then
                self.polygon = nil
                self.logger:warning('no room left for this headland')
            end
        end
    else
        self.logger:error('could not generate headland')
    end
end

---@return boolean true if this headland is around an island (and not around the field boundary)
function Headland:isIslandHeadland()
    return false
end

---@return boolean true if this headland was requested to be created clockwise (the actual polygon
--- may be undetermined if it has loops0
function Headland:getRequestedClockwise()
    return self.clockwise
end

---@return Polyline Headland vertices with waypoint attributes
function Headland:getPath()
    -- make sure all attributes are set correctly
    self.polygon:setAttribute(nil, CourseGenerator.WaypointAttributes.setHeadlandPassNumber, self.passNumber)
    self.polygon:setAttribute(nil, CourseGenerator.WaypointAttributes.setBoundaryId, self:getBoundaryId())
    -- mark corners as headland turns
    for _, v in ipairs(self.polygon) do
        if v.isCorner then
            v:getAttributes():setHeadlandTurn(true)
        end
    end
    return self.polygon
end

---@return number which headland is it? 1 is the outermost.
function Headland:getPassNumber()
    return self.passNumber
end

--- Make sure all corners are rounded to have at least minimumRadius radius.
function Headland:roundCorners(minimumRadius)
    self.logger:debug('round corners to radius %.1f', minimumRadius)
    self.polygon:ensureMinimumRadius(minimumRadius, false)
    self.polygon:calculateProperties()
end

--- Make sure all corners are rounded to have at least minimumRadius radius.
function Headland:sharpenCorners(minimumRadius)
    self.logger:debug('sharpen corners under radius %.1f', minimumRadius)
    self.polygon:ensureMinimumRadius(minimumRadius, true)
    self.polygon:calculateProperties()
end

function Headland:isValid()
    return self.polygon ~= nil and #self.polygon > 2
end

function Headland:getPolygon()
    return self.polygon
end

--- Vertices with coordinates unpacked, to draw with love.graphics.polygon
function Headland:getUnpackedVertices()
    if not self.unpackedVertices then
        self.unpackedVertices = self.polygon:getUnpackedVertices()
    end
    return self.unpackedVertices
end

--- Bypassing big island differs from small ones as:
--- 1. no circling is needed as the big islands will have real headlands, so we always drive around them on the
---    shortest path
--- 2. if the headland starts or ends on the island, we move the headland start out of the island so we don't
---    have tricky situations when connecting headlands
function Headland:bypassBigIslands(bigIslands)
    for _, island in pairs(bigIslands) do
        self.logger:debug('Bypassing big island %d', island:getId())
        local islandHeadlandPolygon = island:getBestHeadlandToBypass():getPolygon()
        local intersections = self.polygon:getIntersections(islandHeadlandPolygon, 1)
        local is1, is2 = intersections[1], intersections[2]
        if #intersections > 0 then
            if islandHeadlandPolygon:isVectorInside(self.polygon[1]) then
                self.polygon:rebase(is1.ixA + 1)
            elseif islandHeadlandPolygon:isVectorInside(self.polygon[#self.polygon]) then
                self.polygon:rebase(is2.ixA - 1)
            end
            local startIx = 1
            while startIx ~= nil do
                _, startIx = self.polygon:goAround(islandHeadlandPolygon, startIx, false)
            end
        end
    end
end

--- Generate a path to switch from this headland to the other, starting as close as possible to the
--- given vertex on this headland and append this path to headland
---@param other CourseGenerator.Headland
---@param ix number vertex index to start the transition at
---@param workingWidth number
---@param turningRadius number
---@param headlandFirst boolean if true, work on headlands first and then transition to the middle of the field
--- for the up/down rows, if false start in the middle and work the headlands from the inside out
---@return number index of the vertex on other where the transition ends
function Headland:connectTo(other, ix, workingWidth, turningRadius, headlandFirst)
    local function ignoreIslandBypass(v)
        return not v:getAttributes():isIslandBypass()
    end
    local transitionPathTypes = self:_getTransitionPathTypes(headlandFirst)
    -- determine the theoretical minimum length of the transition (depending on the width and radius)
    local transitionLength, radius = CourseGenerator.HeadlandConnector.getTransitionLength(workingWidth, turningRadius)
    local transition = self:_continueUntilStraightSection(ix, transitionLength)
    -- index on the other polygon closest to the location where the transition will start
    local otherClosest = other:getPolygon():findClosestVertexToPoint(self.polygon:at(ix + #transition), ignoreIslandBypass)
    -- index on the other polygon where the transition will approximately end
    local transitionEndIx = other:getPolygon():moveForward(otherClosest.ix, transitionLength, ignoreIslandBypass)
    if transitionEndIx then
        -- try a few times to generate a Dubins path as depending on the orientation of the waypoints on
        -- the own headland and the next, we may need more room than the calculated, ideal transition length.
        -- In that case, the Dubins path generated will end up in a loop, so we use a target further ahead on the next headland.
        local tries = 5
        for i = 1, tries do
            CourseGenerator.addDebugPoint(self.polygon:at(ix + #transition))
            CourseGenerator.addDebugPoint(other.polygon:at(transitionEndIx))
            local connector, length = CourseGenerator.AnalyticHelper.getDubinsSolutionAsVertices(
                    self.polygon:at(ix + #transition):getExitEdge():getBaseAsState3D(),
                    other.polygon:at(transitionEndIx):getExitEdge():getBaseAsState3D(),
                    -- enable any path type on the very last try
                    radius, i < tries and transitionPathTypes or nil)
            CourseGenerator.addDebugPolyline(Polyline(connector))
            -- maximum length without loops
            local maxPlausiblePathLength = workingWidth + 4 * radius
            if length < maxPlausiblePathLength or i == tries then
                -- the whole transition is the straight section on the current headland and the actual connector between
                -- the current and the next
                transition:appendMany(connector)
                self.polygon:appendMany(transition)
                self.polygon:setAttributes(#self.polygon - #transition, #self.polygon,
                        CourseGenerator.WaypointAttributes.setHeadlandTransition)
                self.polygon:calculateProperties()
                self.logger:debug('Transition to next headland added, length %.1f, ix on next %d, try %d.',
                        length, transitionEndIx, i)
                return transitionEndIx
            else
                self.logger:warning('Generated path to next headland too long (%.1f > %.1f), try %d.',
                        length, maxPlausiblePathLength, i)
            end
            if 0.8 * radius > turningRadius then
                radius = 0.8 * radius
                self.logger:debug('Transition radius %.1f > turning radius %.1f, reducing transition radius.', radius, turningRadius)
            else
                transitionEndIx = transitionEndIx + 1
                self.logger:debug('Can\'t generate a proper transition, try a little further.')
            end
        end
        self.logger:error('Could not connect to next headland after %d tries, giving up', tries)
    else
        self.logger:warning('Could not connect to next headland, can\'t find transition end')
    end
    return nil
end

--- If there is a single headland only, so there are no transitions, make the polygon overlap itself so
--- the path does not end at the last vertex, it must continue and reach the first for full coverage
function Headland:overlap()
    self.polygon:append(self.polygon[1]:clone())
end

---@param ix number the vertex to start the search
---@param straightSectionLength number how long at the minimum the straight section should be
---@param searchRange number how far should the search for the straight section should go
---@return Polyline array of vectors (can be empty) from ix to the start of the straight section
function Headland:_continueUntilStraightSection(ix, straightSectionLength, searchRange)
    local dTotal = 0
    local count = 0
    local waypoints = Polyline()
    searchRange = searchRange or 100
    while dTotal < searchRange do
        dTotal = dTotal + self.polygon:at(ix):getExitEdge():getLength()
        local r = self.polygon:getSmallestRadiusWithinDistance(ix, straightSectionLength, 0)
        if r > self:_getHeadlandChangeMinRadius() then
            self.logger:debug('Added %d waypoint(s) to reach a straight section for the headland change after %.1f m, r = %.1f',
                    count, dTotal, r)
            return waypoints
        end
        waypoints:append((self.polygon:at(ix)):clone())
        ix = ix + 1
        count = count + 1
    end
    -- no straight section found, bail out here
    self.logger:debug('No straight section found after %.1f m for headland change to next', dTotal)
    return waypoints
end

---@param headlandFirst boolean In the context of an island, when headlandFirst is true, we want to
--- start working on the headlands around the island with the innermost headland, which is right on the
--- island boundary and work outwards
function Headland:_getTransitionPathTypes(headlandFirst)
    if (self.clockwise and headlandFirst) or (not self.clockwise and not headlandFirst) then
        -- Dubins path types to use when changing to the next headland
        self.transitionPathTypes = { DubinsSolver.PathType.LSR, DubinsSolver.PathType.LSL }
    else
        self.transitionPathTypes = { DubinsSolver.PathType.RSL, DubinsSolver.PathType.RSR }
    end
end

function Headland:_getHeadlandChangeMinRadius()
    return CourseGenerator.cHeadlandChangeMinRadius
end

--- A short ID to identify the boundary this headland is based on when serializing/deserializing. By default, this
--- is the field boundary.
function Headland:getBoundaryId()
   return Headland.boundaryIdPrefix
end

function Headland:__tostring()
    return 'Headland ' .. self.passNumber
end

---@class CourseGenerator.Headland
CourseGenerator.Headland = Headland

--- For headlands around islands, as there everything is backwards, at least the transitions
---@class IslandHeadland
local IslandHeadland = CpObject(CourseGenerator.Headland)

--- Headlands around the field will always have a boundary ID starting with 'I' (for island)
IslandHeadland.boundaryIdPrefix = 'I'

--- Create an island headland around a base polygon. The headland is a new polygon, offset by width, that is, outside
--- of the base polygon.
---
---@param basePolygon Polygon
---@param clockwise boolean This is the required direction for all headlands.
---@param passNumber number of the headland pass, the innermost (directly around the island) is 1
---@param width number
---@param mustNotCross Polygon the headland must not cross this polygon, if it does, it is invalid. This is usually
--- the outermost headland around the field, as when anything crosses that, it'll be at least partly outside of the field.
function IslandHeadland:init(island, basePolygon, clockwise, passNumber, width, mustNotCross)
    self.island = island
    CourseGenerator.Headland.init(self, basePolygon, clockwise, passNumber, width, true, mustNotCross)
end
---@return boolean true if this headland is around an island
function IslandHeadland:isIslandHeadland()
    return true
end

---@return CourseGenerator.Island the island this headland is around
function IslandHeadland:getIsland()
    return self.island
end

function IslandHeadland:_getTransitionPathTypes(headlandFirst)
    if (self.clockwise and headlandFirst) or (not self.clockwise and not headlandFirst) then
        -- Dubins path types to use when changing to the next headland
        self.transitionPathTypes = { DubinsSolver.PathType.RSL, DubinsSolver.PathType.RSR }
    else
        self.transitionPathTypes = { DubinsSolver.PathType.LSR, DubinsSolver.PathType.LSL }
    end
end

function IslandHeadland:_getHeadlandChangeMinRadius()
    -- headlands around are not very long, and as they are generated outwards, usually have no
    -- very sharp corners, and we don't have the luxury to pick a straight section for a transition
    return 0
end

--- A short ID in the form I<island ID> to identify the boundary this headland is based on when serializing/deserializing
function IslandHeadland:getBoundaryId()
    return IslandHeadland.boundaryIdPrefix .. self.island:getId()
end

function IslandHeadland:__tostring()
    return 'Island ' .. self.island:getId() .. ' headland ' .. self.passNumber
end

---@class CourseGenerator.IslandHeadland
CourseGenerator.IslandHeadland = IslandHeadland
