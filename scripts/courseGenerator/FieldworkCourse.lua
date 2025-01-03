--- A complete fieldwork course. This contains all main parts of the course in a structured form:
--- headlands, the center with blocks, each block with a set of rows.
--- The constructor FieldworkCourse() generates the course based on the parameters passed in the context.
--- FieldworkCourse:getPath() then returns a continuous Polyline covering the entire field. This is the
--- path a vehicle would follow to complete work on the field.
--- The vertices of the path contain WaypointAttributes which provide additional navigation information
--- for the vehicle.
---@class FieldworkCourse
local FieldworkCourse = CpObject()

---@param context CourseGenerator.FieldworkContext
function FieldworkCourse:init(context)
    self.logger = Logger('FieldworkCourse', nil, CpDebug.DBG_COURSES)
    self:_setContext(context)
    self.headlandPath = Polyline()
    self.circledIslands = {}
    self.headlandCache = CourseGenerator.CacheMap()

    self.logger:debug('### Generating headlands around the field perimeter ###')
    self:generateHeadlands()
    self.logger:debug('### Setting up islands ###')
    self:setupAndSortIslands()

    if self.context.bypassIslands then
        self:routeHeadlandsAroundBigIslands()
    end

    if self.context.headlandFirst then
        -- connect the headlands first as the center needs to start where the headlands finish
        self.logger:debug('### Connecting headlands (%d) from the outside towards the inside ###', #self.headlands)
        self.headlandPath = CourseGenerator.HeadlandConnector.connectHeadlandsFromOutside(self.headlands,
                context.startLocation, self:_getHeadlandWorkingWidth(), self.context.turningRadius)
        self:routeHeadlandsAroundSmallIslands(self.headlandPath)
        self.logger:debug('### Generating up/down rows ###')
        self:generateCenter()
    else
        -- here, make the center first as we want to start on the headlands where the center was finished
        self.logger:debug('### Generating up/down rows ###')
        local endOfLastRow = self:generateCenter()
        self.logger:debug('### Connecting headlands (%d) from the inside towards the outside ###', #self.headlands)
        self.headlandPath = CourseGenerator.HeadlandConnector.connectHeadlandsFromInside(self.headlands,
                endOfLastRow, self:_getHeadlandWorkingWidth(), self.context.turningRadius)
        self:routeHeadlandsAroundSmallIslands(self.headlandPath)
    end

    if self.context.bypassIslands then
        self:bypassSmallIslandsInCenter()
        self.logger:debug('### Bypassing big islands in the center: create path around them ###')
        self:circleBigIslands(self:getPath())
    end
end

--- Returns a continuous Polyline covering the entire field. This is the
--- path a vehicle would follow to complete work on the field.
--- The vertices of the path contain WaypointAttributes which provide additional navigation information
--- for the vehicle.
---@return Polyline
function FieldworkCourse:getPath()
    if not self.path then
        self.path = Polyline()
        if self.context.headlandFirst then
            self.path:appendMany(self:getHeadlandPath())
            self.path:appendMany(self:getCenterPath())
        else
            self.path:appendMany(self:getCenterPath())
            self.path:appendMany(self:getHeadlandPath())
        end
        self.path:calculateProperties()
    end
    return self.path
end

--- Iterates through the paths of all vehicles in the group. For compatibility with the FieldworkCourseMultiVehicle,
--- primarily for testing.
---@return number, number, Polyline[] index, position and path for each vehicle
function FieldworkCourse:pathIterator()
    local position = - 1
    return function()
        -- we iterate exactly over one element, the only path this course has, which belongs to position 0
        if position < 0 then
            position = position + 1
            return position, position, self:getPath()
        end
    end
end

--- Reverse the course, so the vehicle drives it in the opposite direction. The only changes made
--- during reversing is flipping the attributes where applicable, for instance, row ends become row
--- starts.
--- This is for cases where someone wants to drive the exact same course, for instance baling from
--- starting on the headland and finishing on the center, and then collecting the bales starting
--- from the center towards the headland.
--- Note that reverse() guarantees it is the exact same course just backwards, whereas generating
--- a course with starting in the center instead of the headland may result in slightly different path.
function FieldworkCourse:reverse()
    -- make sure we have the forward path
    self:getPath()
    self.path:reverse()
    for _, v in ipairs(self.path) do
        v:getAttributes():_reverse()
    end
end

---@return Polyline
function FieldworkCourse:getHeadlandPath()
    return self.headlandPath
end

---@return CourseGenerator.Headland[]
function FieldworkCourse:getHeadlands()
    return self.headlands
end

---@return number number of actually generated headlands (may be less than requested)
function FieldworkCourse:getNumberOfHeadlands()
    return self.nHeadlands
end

---@return CourseGenerator.Center
function FieldworkCourse:getCenter()
    return self.center
end

---@return Polyline
function FieldworkCourse:getCenterPath()
    return self.center and self.center:getPath() or Polyline()
end

------------------------------------------------------------------------------------------------------------------------
--- Headlands
------------------------------------------------------------------------------------------------------------------------
--- Generate the headlands based on the current context
function FieldworkCourse:generateHeadlands()
    self.headlands = {}
    self.logger:debug('generating %d headland(s) with round corners, then %d with sharp corners',
            self.nHeadlandsWithRoundCorners, self.nHeadlands - self.nHeadlandsWithRoundCorners)
    if self.nHeadlandsWithRoundCorners > 0 then
        self:generateHeadlandsFromInside()
        if self.nHeadlands > self.nHeadlandsWithRoundCorners and #self.headlands < self.nHeadlands then
            self:generateHeadlandsFromOutside(self.boundary,
                    self:_getHeadlandOffset(self.nHeadlandsWithRoundCorners + 1),
                    #self.headlands + 1)
        end
    elseif self.nHeadlands > 0 then
        self:generateHeadlandsFromOutside(self.boundary, self:_getHeadlandOffset(1), 1)
    end
end

--- Generate headlands around the field, starting with the outermost one.
---@param boundary Polygon field boundary or other headland to start the generation from
---@param firstHeadlandWidth number width of the outermost headland to generate, if the boundary is the field boundary,
--- it will usually be the half working width, if the boundary is another headland, the full working width
---@param startIx number index of the first headland to generate
function FieldworkCourse:generateHeadlandsFromOutside(boundary, firstHeadlandWidth, startIx)

    self.logger:debug('generating %d sharp headlands from the outside, first width %.1f, start at %d, min radius %.1f',
            self.nHeadlands - startIx + 1, firstHeadlandWidth, startIx, self.context.turningRadius)
    -- outermost headland is offset from the field boundary by half width
    self.headlands[startIx] = CourseGenerator.Headland(boundary, self.context.headlandClockwise, startIx, firstHeadlandWidth, false, nil)
    if not self.headlands[startIx]:isValid() then
        self:_removeHeadland(startIx)
        return
    end
    if self.context.sharpenCorners then
        self.headlands[startIx]:sharpenCorners(self.context.turningRadius)
    end
    for i = startIx + 1, self.nHeadlands do
        self.headlands[i] = CourseGenerator.Headland(self.headlands[i - 1]:getPolygon(), self.context.headlandClockwise, i,
                self:_getHeadlandWorkingWidth(i), false, self.headlands[1]:getPolygon())
        if self.headlands[i]:isValid() then
            if self.context.sharpenCorners then
                self.headlands[i]:sharpenCorners(self.context.turningRadius)
            end
        else
            self:_removeHeadland(i)
            break
        end
    end
end

--- Generate headlands around the field, starting with the innermost one. Generating from the inside
--- is needed when we needed a headland with corners rounded to the vehicle's turn radius, everything
--- outside of such a headland should be generated based on the innermost one with a rounded corner to
--- guarantee that none will have a corner sharper than the turn radius.
function FieldworkCourse:generateHeadlandsFromInside()
    self.logger:debug('generating %d headlands with round corners, min radius %.1f',
            self.nHeadlandsWithRoundCorners, self.context.turningRadius)
    -- start with the innermost headland, try until it can fit in the field (as the required number of
    -- headlands may be more than what actually fits into the field)
    while self.nHeadlandsWithRoundCorners > 0 do
        self.headlands[self.nHeadlandsWithRoundCorners] = CourseGenerator.Headland(self.boundary, self.context.headlandClockwise,
                self.nHeadlandsWithRoundCorners, self:_getHeadlandOffset(self.nHeadlandsWithRoundCorners),
                false, self.boundary)
        if self.headlands[self.nHeadlandsWithRoundCorners]:isValid() then
            self.headlands[self.nHeadlandsWithRoundCorners]:roundCorners(self.context.turningRadius)
            break
        else
            self:_removeHeadland(self.nHeadlandsWithRoundCorners)
            self.logger:warning('no room for innermost headland, reducing headlands to %d, rounded %d',
                    self.nHeadlands, self.nHeadlandsWithRoundCorners)
        end
    end
    for i = self.nHeadlandsWithRoundCorners - 1, 1, -1 do
        self.headlands[i] = CourseGenerator.Headland(self.headlands[i + 1]:getPolygon(), self.context.headlandClockwise, i,
                self:_getHeadlandWorkingWidth(i), true, self.boundary)
        self.headlands[i]:roundCorners(self.context.turningRadius)
    end
end

------------------------------------------------------------------------------------------------------------------------
--- Up/down rows
------------------------------------------------------------------------------------------------------------------------
function FieldworkCourse:generateCenter()
    -- if there are no headlands, or there are, but we start working in the middle, then use the
    -- designated start location, otherwise the point where the innermost headland ends.
    if #self.headlands == 0 then
        self.center = CourseGenerator.Center(self.context, self.boundary, nil, self.context.startLocation, self.bigIslands)
    else
        local innerMostHeadlandPolygon = self.headlands[#self.headlands]:getPolygon()
        self.center = CourseGenerator.Center(self.context, self.boundary, self.headlands[#self.headlands],
                self.context.headlandFirst and
                        innerMostHeadlandPolygon[#innerMostHeadlandPolygon] or
                        self.context.startLocation,
                self.bigIslands)
    end
    return self.center:generate()
end

------------------------------------------------------------------------------------------------------------------------
--- Islands
------------------------------------------------------------------------------------------------------------------------
function FieldworkCourse:setupAndSortIslands()
    self.bigIslands, self.smallIslands = {}, {}
    if not self.context.bypassIslands then
        return
    end
    for _, island in pairs(self.context.field:getIslands()) do
        island:generateHeadlands(self.context, (self.nHeadlands > 0 and self.headlands[1]) and
                self.headlands[1]:getPolygon() or self.boundary)
        -- for some weird cases we may not have been able to generate island headlands, so ignore those islands
        if island:getInnermostHeadland() then
            if island:isTooBigToBypass(self.context.workingWidth) then
                table.insert(self.bigIslands, island)
            else
                table.insert(self.smallIslands, island)
            end
        else
            self.logger:warning('Could not generate headlands for island %d', island:getId())
        end
    end
end

function FieldworkCourse:routeHeadlandsAroundBigIslands()

    self.logger:debug('### Bypassing big islands: headlands ###')
    for _, headland in ipairs(self.headlands) do
        headland:bypassBigIslands(self.bigIslands)
    end
end

--- We do this after we have connected the individual headlands so the links between the headlands
--- are also routed around the islands.
function FieldworkCourse:routeHeadlandsAroundSmallIslands(headlandPath)
    self.logger:debug('### Bypassing small islands on the headland ###')
    for _, island in pairs(self.smallIslands) do
        local startIx, circled = 1, false
        while startIx ~= nil do
            self.logger:debug('Bypassing island %d on the headland, at %d', island:getId(), startIx)
            --- Remember the islands we circled already, as even if multiple tracks cross it, we only want to
            --- circle once, subsequent bypasses just pick the shortest way around it.
            circled, startIx = headlandPath:goAround(
                    island:getHeadlands()[1]:getPolygon(), startIx, not self.circledIslands[island])
            self.circledIslands[island] = circled or self.circledIslands[island]
        end
    end
end

function FieldworkCourse:bypassSmallIslandsInCenter()
    self.logger:debug('### Bypassing small islands in the center ###')
    for _, island in pairs(self.smallIslands) do
        self.logger:debug('Bypassing small island %d on the center', island:getId())
        self.center:bypassSmallIsland(island:getInnermostHeadland():getPolygon(), not self.circledIslands[island])
    end
end

-- Once we have the whole course laid out, we add the headland passes around the big islands
---@param path Polyline the complete path
---@param vehicle number|nil the vehicle index, if nil, we assume there is only one vehicle
function FieldworkCourse:circleBigIslands(path, vehicle)
    for _, i in ipairs(self.context.field:getIslands()) do
        self.logger:debug('Island %d: circled %s, big %s',
                i:getId(), self.circledIslands[i], i:isTooBigToBypass(self.context.workingWidth))
    end
    -- if we are harvesting (headlandFirst = true) we want to take care of the island headlands
    -- when we first get to them. For other field works it is the opposite, we want all the up/down rows
    -- done before working on the island headlands.
    local first = self.context.headlandFirst and 1 or #path
    local step = self.context.headlandFirst and 1 or -1
    local last = self.context.headlandFirst and #path or 1
    local i = first
    local found = false
    while i ~= last and not found do
        local island = path[i]:getAttributes():_getAtIsland()
        if island and not self:isBigIslandCircled(island, vehicle) and path[i]:getAttributes():isRowEnd() then
            self.logger:debug('Found island %s at %d', island:getId(), i)
            -- we bumped upon an island which the path does not circle yet and we are at the end of a row.
            -- so now work on the island's headlands and then continue with the next row.
            local islandHeadlands = self:getIslandHeadlands(island, vehicle)
            local outermostHeadlandPolygon = islandHeadlands[#islandHeadlands]:getPolygon()
            -- find a vertex on the outermost headland to start working on the island headlands,
            -- far enough that we can generate a Dubins path to it
            local slider = CourseGenerator.Slider(outermostHeadlandPolygon,
                    outermostHeadlandPolygon:findClosestVertexToPoint(path[i]).ix, 3 * self.context.turningRadius)

            -- 'inside' since with islands, everything is backwards
            local headlandPath = CourseGenerator.HeadlandConnector.connectHeadlandsFromInside(islandHeadlands,
                    slider.ix, self:_getHeadlandWorkingWidth(), self.context.turningRadius)

            -- from the row end to the start of the headland, we instruct the driver to use
            -- the pathfinder.
            path:setAttribute(i, CourseGenerator.WaypointAttributes.setUsePathfinderToNextWaypoint)
            headlandPath:setAttribute(#headlandPath, CourseGenerator.WaypointAttributes.setUsePathfinderToNextWaypoint)
            headlandPath:setAttribute(nil, CourseGenerator.WaypointAttributes.setIslandHeadland)
            self.logger:debug('Added headland path around island %d with %d points', island:getId(), #headlandPath)
            for j = #headlandPath, 1, -1 do
                table.insert(path, i + 1, headlandPath[j])
            end

            path:calculateProperties()
            self:setBigIslandCircled(island, vehicle)
            -- if we are iterating backwards, we still want to stop at the first vertex.
            last = self.context.headlandFirst and last + #headlandPath or 1
        end
        i = i + step
    end
end

------------------------------------------------------------------------------------------------------------------------
--- Helper functions for circleBigIsland(), to override in derived classes, like in FieldworkCourseMultiVehicle
--- where the logic of getting the headlands is different.
function FieldworkCourse:getIslandHeadlands(island, vehicle)
    return island:getHeadlands()
end

--- Here we only have one vehicle, so we only need to circle an island once and ignore the vehicle.
function FieldworkCourse:isBigIslandCircled(island, vehicle)
    return self.circledIslands[island]
end

function FieldworkCourse:setBigIslandCircled(island, vehicle)
    self.circledIslands[island] = true
end
------------------------------------------------------------------------------------------------------------------------

--- Find the path to the next row on the headland.
---@param boundaryId string the boundary ID, telling if this is a boundary around the field or around an island. Will
--- only return a path when the next row can be reached while staying on the same boundary.
---@param rowEnd Vector Last waypoint of the row
---@param rowStart Vector First waypoint of the next row
---@param minDistanceFromRowEnd number|nil minimum distance of the headland (default 0)we choose for the path,
--- from the row end, this should be set so that the vehicle can make the turn from the position where it ended the
--- work on the row into the headland. In case of a headland perpendicular to the rows, this is approximately the turn
--- radius, at other angles it could be bigger or smaller, which we currently do not take into account
---@return Polyline The path on the headland to the next row. Users should consider shortening both ends of the
--- path with the turning radius to leave enough room for the vehicle to cleanly make the turn from the row end into
--- the headland path and from the headland into the next row
function FieldworkCourse:findPathToNextRow(boundaryId, rowEnd, rowStart, minDistanceFromRowEnd)
    local headlands = self:_getCachedHeadlands(boundaryId)
    local headlandWidth = #headlands * self:_getHeadlandWorkingWidth()
    local usableHeadlandWidth = headlandWidth - (minDistanceFromRowEnd or 0)
    local headlandPassNumber = CpMathUtil.clamp(math.floor(usableHeadlandWidth / self:_getHeadlandWorkingWidth()), 1, #headlands)
    local headland = headlands[headlandPassNumber]
    if headland == nil then
        return Polyline()
    end
    local vx1 = headland:findClosestVertexToPoint(rowEnd)
    local vx2 = headland:findClosestVertexToPoint(rowStart)
    --self.logger:debug('Found shortest path to next row on boundary %s, headland %d, %d->%d',
    --        boundaryId, headlandPassNumber, vx1.ix, vx2.ix)
    return headland:getShortestPathBetween(vx1.ix, vx2.ix)
end

------------------------------------------------------------------------------------------------------------------------
--- Private functions
------------------------------------------------------------------------------------------------------------------------
function FieldworkCourse:_setContext(context)
    self.context = context
    self.context:log()
    self.nHeadlands = self.context.nHeadlands
    self.nHeadlandsWithRoundCorners = self.context.nHeadlandsWithRoundCorners
    ---@type Polygon
    self.boundary = CourseGenerator.FieldworkCourseHelper.createUsableBoundary(context.field:getBoundary(), self.context.headlandClockwise)
    if self.context.fieldMargin ~= 0 then
        self.logger:debug('Applying field margin %.1f', self.context.fieldMargin)
        self.boundary = CourseGenerator.Headland(self.boundary, self.boundary:isClockwise(), 0,
                math.abs(self.context.fieldMargin), self.context.fieldMargin < 0):getPolygon()
    end
    if self.context.fieldCornerRadius > 0 then
        self.logger:debug('sharpening field boundary corners')
        self.boundary:ensureMinimumRadius(self.context.fieldCornerRadius, true)
    end
    CourseGenerator.addDebugPolyline(self.boundary, {0, 1, 1, 0.3})
end

function FieldworkCourse:_removeHeadland(n)
    -- If this is invalid, all above it (generated from this) must be invalid, remove them all so
    -- #self.headlands is not confused.
    for i = n, #self.headlands do
        self.headlands[i] = nil
    end
    self.nHeadlands = n - 1
    self.nHeadlandsWithRoundCorners = math.min(self.nHeadlands, self.nHeadlandsWithRoundCorners)
    self.logger:error('could not generate headland %d, course has %d headlands, %d rounded',
            n, self.nHeadlands, self.nHeadlandsWithRoundCorners)
end

function FieldworkCourse:_getCachedHeadlands(boundaryId)
    local headlands = self.headlandCache:get(boundaryId)
    if not headlands then
        headlands = {}
        for _, v in ipairs(self:getPath()) do
            local a = v:getAttributes()
            if a:getBoundaryId() == boundaryId and not a:isIslandBypass() and not a:isHeadlandTransition() and
                    not a:isOnConnectingPath() then
                local pass = a:getHeadlandPassNumber()
                if headlands[pass] == nil then
                    headlands[pass] = Polygon()
                end
                headlands[pass]:append(v)
            end
        end
        for i, h in ipairs(headlands) do
            self.logger:debug('cached boundary %s, headland %d with %d vertices', boundaryId, i, #h)
            h:calculateProperties()
        end
        self.headlandCache:put(boundaryId, headlands)
    end
    return headlands
end

---@param n number|nil index of the headland, 1 being the outermost one. If nil, it always returns the working width
--- corrected with the overlap.
function FieldworkCourse:_getHeadlandWorkingWidth(n)
    if n == nil or n > 1 then
        return self.context:getHeadlandWorkingWidth() * (1 - self.context:getHeadlandOverlap())
    else
        -- working width of the first headland has no overlap otherwise implements won't remain on the field
        return self.context:getHeadlandWorkingWidth()
    end
end

---@return number the offset of the nth headland from the field boundary, taking into account the overlap.
function FieldworkCourse:_getHeadlandOffset(n)
    if n == 1 then
        return self:_getHeadlandWorkingWidth(1) / 2
    else
        -- for n > 1, the headland width is with the overlap
        return self:_getHeadlandWorkingWidth(1) + (n - 1 - 0.5) * self:_getHeadlandWorkingWidth(n)
    end
end

function FieldworkCourse:__tostring()
    return string.format('%d/%d headland/center waypoints', #self:getHeadlandPath(), #self:getCenterPath())
end

---@class CourseGenerator.FieldworkCourse
CourseGenerator.FieldworkCourse = FieldworkCourse