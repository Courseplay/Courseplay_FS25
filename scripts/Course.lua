--[[
This file is part of Courseplay (https://github.com/Courseplay/Courseplay_FS25)
Copyright (C) 2018-2022 Peter Va9ko

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

---@class Course
Course = CpObject()

--- Course constructor
---@param waypoints Waypoint[] table of waypoints of the course
---@param temporary boolean|nil optional, default false is this a temporary course?
---@param first number|nil optional, index of first waypoint to use
---@param last number|nil optional, index of last waypoint to use to construct of the course
function Course:init(vehicle, waypoints, temporary, first, last)
    -- add waypoints from current vehicle course
    ---@type Waypoint[]
    self.waypoints = Course.initWaypoints()
    for i = first or 1, last or #waypoints do
        table.insert(self.waypoints, Waypoint(waypoints[i]))
    end
    -- offset to apply to every position
    self.offsetX, self.offsetZ = 0, 0
    self.temporaryOffsetX, self.temporaryOffsetZ = CpSlowChangingObject(0, 0), CpSlowChangingObject(0, 0)
    self.numberOfHeadlands = 0
    self.workWidth = 0
    self.name = ''
    self.editedByCourseEditor = false
    self.nVehicles = 1
    -- only for logging purposes
    self.vehicle = vehicle
    self.temporary = temporary or false
    self.currentWaypoint = 1
    self.length = 0
    self.totalTurns = 0
    self:enrichWaypointData()
end

function Course:getDebugTable()
    return {
        { name = "numWp", value = self:getNumberOfWaypoints() },
        { name = "workWidth", value = self.workWidth },
        { name = "curWpIx", value = self:getCurrentWaypointIx() },
        { name = "length", value = self.length },
        { name = "numTurns", value = self.totalTurns },
        { name = "offsetX", value = self.offsetX },
        { name = "offsetZ", value = self.offsetZ },
        { name = "nVehicles", value = self.nVehicles },
        { name = "numHeadlands", value = self.numberOfHeadlands },
        { name = "totalTurns", value = self.totalTurns },
    }

end

function Course:setName(name)
    self.name = name
end

function Course:setVehicle(vehicle)
    self.vehicle = vehicle
end

function Course:getVehicle()
    return self.vehicle
end

function Course:getName()
    return self.name
end

function Course:setEditedByCourseEditor()
    self.editedByCourseEditor = true
end

function Course:wasEditedByCourseEditor()
    return self.editedByCourseEditor
end

function Course:getAllWaypoints()
    return self.waypoints
end

--- Function to create the waypoints table in the Course object. This makes sure, that
--- the index is always within the bounds of the table, and avoids crashes, but may result
--- in other errors.
---@return table
function Course.initWaypoints()
    return setmetatable({}, {
        -- add a function to clamp the index between 1 and #self.waypoints
        __index = function(tbl, key)
            local result = rawget(tbl, key)
            if not result and type(key) == "number" then
                result = rawget(tbl, math.min(math.max(1, key), #tbl))
            end
            return result
        end
    })
end

--- Current offset to apply. getWaypointPosition() will always return the position adjusted by the
-- offset. The x and z offset are in the waypoint's coordinate system, waypoints are directed towards
-- the next waypoint, so a z = 1 offset will move the waypoint 1m forward, x = 1 1 m to the right (when
-- looking in the drive direction)
--- IMPORTANT: the offset for multitool (laneOffset) must not be part of this as it is already part of the
--- course,
--- @see Course#calculateOffsetCourse
function Course:setOffset(x, z)
    self.offsetX, self.offsetZ = x, z
end

function Course:getOffset()
    return self.offsetX, self.offsetZ
end

--- Temporary offset to apply. This is to use an offset temporarily without overwriting the normal offset of the course
function Course:setTemporaryOffset(x, z, t)
    self.temporaryOffsetX:set(x, t)
    self.temporaryOffsetZ:set(z, t)
end

function Course:changeTemporaryOffsetX(dx, t)
    self.temporaryOffsetX:set(self.temporaryOffsetX:get() + dx, t)
end

function Course:setWorkWidth(w)
    self.workWidth = w
end

function Course:getWorkWidth()
    return self.workWidth
end

function Course:getNumberOfHeadlands()
    return self.numberOfHeadlands
end

--- get number of waypoints in course
function Course:getNumberOfWaypoints()
    return #self.waypoints
end

---@return Waypoint
function Course:getWaypoint(ix)
    return self.waypoints[ix]
end

function Course:getMultiTools()
    return self.nVehicles or 1
end

--- Is this a temporary course? Can be used to differentiate between recorded and dynamically generated courses
-- The Course() object does not use this attribute for anything
function Course:isTemporary()
    return self.temporary
end

-- add missing angles and world directions from one waypoint to the other
-- PPC relies on waypoint angles, the world direction is needed to calculate offsets
function Course:enrichWaypointData(startIx)
    if #self.waypoints < 2 then
        return
    end
    if not startIx then
        -- initialize only if recalculating the whole course, otherwise keep (and update) the old values)
        self.length = 0
    end
    for i = startIx or 1, #self.waypoints - 1 do
        self.waypoints[i].dToHere = self.length
        local cx, _, cz = self.waypoints[i]:getPosition()
        local nx, _, nz = self.waypoints[i + 1]:getPosition()
        local dToNext = MathUtil.getPointPointDistance(cx, cz, nx, nz)
        self.waypoints[i].dToNext = dToNext
        self.length = self.length + dToNext
        if self:isTurnStartAtIx(i) then
            self.totalTurns = self.totalTurns + 1
        end
        if self:isTurnEndAtIx(i) then
            self.dFromLastTurn = 0
        elseif self.dFromLastTurn then
            self.dFromLastTurn = self.dFromLastTurn + dToNext
        end
        self.waypoints[i].turnsToHere = self.totalTurns
        -- TODO: looks like we may end up with the first two waypoint of a course being the same. This takes care
        -- of setting dx/dz to 0 (instead of NaN) but should investigate as it does not make sense
        if MathUtil.vector2Length(nx - cx, nz - cz) > 0 then
            local dx, dz = MathUtil.vector2Normalize(nx - cx, nz - cz)
            self.waypoints[i].dx, self.waypoints[i].dz = dx, dz
            self.waypoints[i].yRot = MathUtil.getYRotationFromDirection(dx, dz)
        else
            self.waypoints[i].dx, self.waypoints[i].dz = 0, 0
            -- NaN or both 0, use the direction of the previous waypoint
            self.waypoints[i].yRot = self.waypoints[i - 1].yRot or 0
        end
        self.waypoints[i].angle = math.deg(self.waypoints[i].yRot)
        self.waypoints[i].calculatedRadius = i == 1 and math.huge or self:calculateRadius(i)
        self.waypoints[i].curvature = i == 1 and 0 or 1 / self:calculateSignedRadius(i)
        if (self:isReverseAt(i) and not self:switchingToForwardAt(i)) or self:switchingToReverseAt(i) then
            -- X offset must be reversed at waypoints where we are driving in reverse
            self.waypoints[i]:setReverseOffset(true)
        end
    end
    -- make the last waypoint point to the same direction as the previous so we don't
    -- turn towards the first when ending the course. (the course generator points the last
    -- one to the first, should probably be changed there)
    self.waypoints[#self.waypoints].angle = self.waypoints[#self.waypoints - 1].angle
    self.waypoints[#self.waypoints].yRot = self.waypoints[#self.waypoints - 1].yRot
    self.waypoints[#self.waypoints].dx = self.waypoints[#self.waypoints - 1].dx
    self.waypoints[#self.waypoints].dz = self.waypoints[#self.waypoints - 1].dz
    self.waypoints[#self.waypoints].dToNext = 0
    self.waypoints[#self.waypoints].dToHere = self.length
    self.waypoints[#self.waypoints].turnsToHere = self.totalTurns
    self.waypoints[#self.waypoints].calculatedRadius = math.huge
    self.waypoints[#self.waypoints].curvature = 0
    self.waypoints[#self.waypoints]:setReverseOffset(self:isReverseAt(#self.waypoints))
    -- now add some metadata for the combines
    local dToNextTurn, lNextRow, nextRowStartIx = 0, 0, 0
    local dToNextDirectionChange, nextDirectionChangeIx = 0, 0
    local turnFound = false
    local directionChangeFound = false
    for i = #self.waypoints - 1, 1, -1 do
        if turnFound then
            dToNextTurn = dToNextTurn + self.waypoints[i].dToNext
            self.waypoints[i].dToNextTurn = dToNextTurn
            self.waypoints[i].lNextRow = lNextRow
            self.waypoints[i].nextRowStartIx = nextRowStartIx
        end
        if self:isTurnStartAtIx(i) then
            lNextRow = dToNextTurn
            nextRowStartIx = i + 1
            dToNextTurn = 0
            turnFound = true
        end
        if directionChangeFound then
            dToNextDirectionChange = dToNextDirectionChange + self.waypoints[i].dToNext
            self.waypoints[i].dToNextDirectionChange = dToNextDirectionChange
            self.waypoints[i].nextDirectionChangeIx = nextDirectionChangeIx
        end
        if self:switchingDirectionAt(i) then
            dToNextDirectionChange = 0
            nextDirectionChangeIx = i
            directionChangeFound = true
        end
    end
    CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle or CpUtil.getCurrentVehicle(),
            'Course with %d waypoints created/updated, %.1f meters, %d turns', #self.waypoints, self.length, self.totalTurns)
end

function Course:getDeltaAngle(ix)
    return CpMathUtil.getDeltaAngle(self.waypoints[ix].yRot, self.waypoints[ix - 1].yRot)
end

function Course:calculateSignedRadius(ix)
    return CpMathUtil.divide(self:getDistanceToNextWaypoint(ix), (2 * math.sin(self:getDeltaAngle(ix) / 2)))
end

function Course:calculateRadius(ix)
    return math.abs(self:calculateSignedRadius(ix))
end

--- Is this the same course as otherCourse?
-- TODO: is there a hash we could use instead?
function Course:equals(other)
    if #self.waypoints ~= #other.waypoints then
        return false
    end
    -- for now just check the coordinates of the first waypoint
    if self.waypoints[1].x - other.waypoints[1].x > 0.01 then
        return false
    end
    if self.waypoints[1].z - other.waypoints[1].z > 0.01 then
        return false
    end
    -- same number of waypoints, first waypoint same coordinates, equals!
    return true
end

--- A super simple hash to identify and compare courses (see convoy)
function Course:getHash()
    local hash = ''
    for i = 1, math.min(20, #self.waypoints) do
        hash = hash .. string.format('%d%d', self.waypoints[i].x, self.waypoints[i].z)
    end
    return hash
end

function Course:setCurrentWaypointIx(ix)
    self.currentWaypoint = ix
end

function Course:getCurrentWaypointIx()
    return self.currentWaypoint
end

function Course:setLastPassedWaypointIx(ix)
    self.lastPassedWaypoint = ix
end

function Course:getLastPassedWaypointIx()
    return self.lastPassedWaypoint
end

function Course:isReverseAt(ix)
    return self.waypoints[math.min(math.max(1, ix), #self.waypoints)].rev
end

function Course:getLastReverseAt(ix)
    for i = ix, #self.waypoints do
        if not self.waypoints[i].rev then
            return i - 1
        end
    end
end

function Course:isForwardOnly()
    for _, wp in ipairs(self.waypoints) do
        if wp.rev then
            return false
        end
    end
    return true
end

function Course:isTurnStartAtIx(ix)
    -- Don't start turns at the last waypoint
    -- TODO: do a row finish maneuver instead
    return ix < #self.waypoints and
            -- don't start any turns just before a connecting path as there the pathfinder should take over
            (self.waypoints[ix]:isRowEnd() and
                    not self:isOnConnectingPath(ix + 1) and
                    not self:shouldUsePathfinderToNextWaypoint(ix)) or
            (self.waypoints[ix + 1] and self.waypoints[ix + 1]:isHeadlandTurn() and
                    self.waypoints[ix + 2] and not self:isOnConnectingPath(ix + 2))
end

function Course:isHeadlandTurnAtIx(ix)
    return ix <= #self.waypoints and self.waypoints[ix]:isHeadlandTurn()
end

function Course:isTurnEndAtIx(ix)
    return (self.waypoints[ix]:isRowStart() and not self:shouldUsePathfinderToThisWaypoint(ix)) or
            self.waypoints[ix]:isHeadlandTurn()
end

function Course:shouldUsePathfinderToNextWaypoint(ix)
    return self.waypoints[ix]:shouldUsePathfinderToNextWaypoint() or
            (ix < #self.waypoints and self.waypoints[ix + 1]:shouldUsePathfinderToThisWaypoint())
end

function Course:shouldUsePathfinderToThisWaypoint(ix)
    return self.waypoints[ix]:shouldUsePathfinderToThisWaypoint() or
            (ix > 1 and self.waypoints[ix - 1]:shouldUsePathfinderToNextWaypoint())
end

function Course:skipOverTurnStart(ix)
    if self:isTurnStartAtIx(ix) then
        return ix + 1
    else
        return ix
    end
end

--- Is this waypoint on a connecting track, that is, a transfer path between
-- a headland and the up/down rows where there's no fieldwork to do.
function Course:isOnConnectingPath(ix)
    return ix <= #self.waypoints and self.waypoints[ix]:isOnConnectingPath()
end

function Course:switchingDirectionAt(ix)
    return self:switchingToForwardAt(ix) or self:switchingToReverseAt(ix)
end

function Course:getNextDirectionChangeFromIx(ix)
    for i = ix, #self.waypoints do
        if self:switchingDirectionAt(i) then
            return i
        end
    end
end

function Course:switchingToReverseAt(ix)
    return not self:isReverseAt(ix) and self:isReverseAt(ix + 1)
end

function Course:switchingToForwardAt(ix)
    return self:isReverseAt(ix) and not self:isReverseAt(ix + 1)
end

function Course:getHeadlandNumber(ix)
    return self.waypoints[ix].attributes:getHeadlandPassNumber()
end

---@param ix number
---@param n number|nil headland pass number
---@param boundaryId string|nil boundary id of the headland
function Course:isOnHeadland(ix, n, boundaryId)
    ix = ix or self.currentWaypoint
    if n then
        if boundaryId == nil then
            return self.waypoints[ix].attributes:getHeadlandPassNumber() == n
        else
            return self.waypoints[ix].attributes:getHeadlandPassNumber() == n and
                    self.waypoints[ix]:getBoundaryId() == boundaryId
        end
    else
        return self.waypoints[ix].attributes:getHeadlandPassNumber() ~= nil
    end
end

---@param ix number
---@return boolean|nil true if ix is on a clockwise headland (around the field, or around an island). False if
--- it is on a counterclockwise headland, and nil, if is is not on a headland.
function Course:isOnClockwiseHeadland(ix)
    local boundaryId = self.waypoints[ix].attributes:getBoundaryId()
    if boundaryId == nil then
        return nil
    end
    if CourseGenerator.isHeadland(boundaryId) then
        return self.headlandClockwise
    elseif CourseGenerator.isIslandHeadland(boundaryId) then
        return self.islandHeadlandClockwise
    end
    return nil
end

function Course:isHeadlandTransition(ix)
    return self.waypoints[ix]:isHeadlandTransition()
end

function Course:isOnOutermostHeadland(ix)
    return self.waypoints[ix].attributes:getHeadlandPassNumber() == 1
end

function Course:startsWithHeadland()
    return self:isOnHeadland(1)
end

---@param n number number of headland to get, 1 -> number of headlands, 1 is the outermost
---@param boundaryId string|nil id of the boundary to return only the points that are on the same field boundary
--- or island headland
---@return Polygon headland as a polygon (x, y)
function Course:getHeadland(n, boundaryId)
    local headland = Polygon()
    local first, last, step
    if self:startsWithHeadland() then
        first, last, step = 1, self:getNumberOfWaypoints(), 1
    else
        -- if the course ends with the headland, start at the end to avoid headlands around the
        -- islands in the center of the field
        first, last, step = self:getNumberOfWaypoints(), 1, -1
    end
    for i = first, last, step do
        -- do not want to include the transition and the connecting path parts as those are overlap with the first part
        -- of the headland confusing the shortest path finding
        if self:isOnHeadland(i, n, boundaryId) and not self:isHeadlandTransition(i) and not self:isOnConnectingPath(i) then
            local x, _, z = self:getWaypointPosition(i)
            headland:append({ x = x, y = -z })
        end
        if #headland > 0 and not self:isOnHeadland(i, n) then
            -- stop after we leave the headland around the field boundary or when we already found our headland
            -- and now on a different one
            -- as we don't want to include headlands around islands.
            break
        end
    end
    return headland
end

function Course:getTurnControls(ix)
    return self.waypoints[ix].turnControls
end

function Course:setUseTightTurnOffset(ix)
    return self.waypoints[ix]:setUseTightTurnOffset()
end

function Course:getUseTightTurnOffset(ix)
    return self.waypoints[ix]:getUseTightTurnOffset()
end

--- Returns the position of the waypoint at ix with the current offset applied.
---@param ix number waypoint index
---@return number, number, number x, y, z
function Course:getWaypointPosition(ix)
    if self:isTurnStartAtIx(ix) and not self:isHeadlandTurnAtIx(ix) then
        -- turn start waypoints point to the turn end wp, for example at the row end they point 90 degrees to the side
        -- from the row direction. This is a problem when there's an offset so use the direction of the previous wp
        -- when calculating the offset for a turn start wp, except for headlands turns where we actually drive the
        -- section between turn start and turn end.
        return self:getOffsetPositionWithOtherWaypointDirection(ix, ix - 1)
    else
        return self.waypoints[ix]:getOffsetPosition(self.offsetX + self.temporaryOffsetX:get(), self.offsetZ + self.temporaryOffsetZ:get())
    end
end

---Return the offset coordinates of waypoint ix as if it was pointing to the same direction as waypoint ixDir
function Course:getOffsetPositionWithOtherWaypointDirection(ix, ixDir)
    return self.waypoints[ix]:getOffsetPosition(self.offsetX + self.temporaryOffsetX:get(), self.offsetZ + self.temporaryOffsetZ:get(),
            self.waypoints[ixDir].dx, self.waypoints[ixDir].dz)
end

-- distance between (px,pz) and the ix waypoint
function Course:getDistanceBetweenPointAndWaypoint(px, pz, ix)
    return self.waypoints[ix]:getDistanceFromPoint(px, pz)
end

function Course:getDistanceBetweenVehicleAndWaypoint(vehicle, ix)
    return self.waypoints[ix]:getDistanceFromVehicle(vehicle)
end

--- get waypoint position in the node's local coordinates
function Course:getWaypointLocalPosition(node, ix)
    local x, y, z = self:getWaypointPosition(ix)
    local dx, dy, dz = worldToLocal(node, x, y, z)
    return dx, dy, dz
end

function Course:getWaypointAngleDeg(ix)
    return self.waypoints[math.min(#self.waypoints, ix)].angle
end

--- Gets the world directions of the waypoint.
---@param ix number
---@return number x world direction
---@return number z world direction
function Course:getWaypointWorldDirections(ix)
    local wp = self.waypoints[math.min(#self.waypoints, ix)]
    return wp.dx, wp.dz
end

--- Get the driving direction at the waypoint. y rotation points in the direction
--- of the next waypoint, but at the last wp before a direction change this is the opposite of the driving
--- direction, since we want to reach that last waypoint
function Course:getYRotationCorrectedForDirectionChanges(ix)
    if ix == #self.waypoints or self:switchingDirectionAt(ix) and ix > 1 then
        -- last waypoint before changing direction, use the yRot from the previous waypoint
        return self.waypoints[ix - 1].yRot
    else
        return self.waypoints[ix].yRot
    end
end

-- This is the radius calculated when the course is created.
function Course:getCalculatedRadiusAtIx(ix)
    local r = self.waypoints[ix].calculatedRadius
    if r ~= r then
        -- radius can be nan
        return nil
    else
        return r
    end
end

--- Get the minimum radius within d distance from waypoint ix
---@param ix number waypoint index to start
---@param d number distance in meters to look forward
---@return number the  minimum radius within d distance from waypoint ix
function Course:getMinRadiusWithinDistance(ix, d)
    local ixAtD = self:getNextWaypointIxWithinDistance(ix, d) or ix
    local minR, count = math.huge, 0
    for i = ix, ixAtD do
        if self:isTurnStartAtIx(i) or self:isTurnEndAtIx(i) then
            -- the turn maneuver code will take care of speed
            return nil
        end
        local r = self:getCalculatedRadiusAtIx(i)
        if r and r < minR then
            count = count + 1
            minR = r
        end
    end
    return count > 0 and minR or nil
end

--- Get the Y rotation of a waypoint (pointing into the direction of the next)
function Course:getWaypointYRotation(ix)
    local i = ix
    -- at the last waypoint use the incoming direction
    if ix >= #self.waypoints then
        i = #self.waypoints - 1
    elseif ix < 1 then
        i = 1
    end
    local cx, _, cz = self:getWaypointPosition(i)
    local nx, _, nz = self:getWaypointPosition(i + 1)
    -- if current and next are at the same position, to avoid division by zero
    if MathUtil.vector2Length(nx - cx, nz - cz) < 0.00001 then
        -- use the direction of the previous waypoint if exists, otherwise the next. This is to make sure that
        -- the WaypointNode used by the PPC has a valid direction
        if i > 1 then
            return self.waypoints[i - 1].yRot
        else
            return self.waypoints[i + 1].yRot
        end
        return 0
    end
    local dx, dz = MathUtil.vector2Normalize(nx - cx, nz - cz)
    return MathUtil.getYRotationFromDirection(dx, dz)
end

---@return number RidgeMarkerController.RIDGE_MARKER_NONE, RidgeMarkerController.RIDGE_MARKER_LEFT, RidgeMarkerController.RIDGE_MARKER_RIGHT
function Course:getRidgeMarkerState(ix)
    -- set ridge marker only if we are absolutely sure that a side is not worked
    if self.waypoints[ix].attributes:isLeftSideNotWorked() then
        return RidgeMarkerController.RIDGE_MARKER_LEFT
    elseif self.waypoints[ix].attributes:isRightSideNotWorked() then
        return RidgeMarkerController.RIDGE_MARKER_RIGHT
    else
        return RidgeMarkerController.RIDGE_MARKER_NONE
    end
end

function Course:isLeftSideWorked(ix)
    return self.waypoints[ix].attributes:isLeftSideWorked()
end

---@return boolean true if the next 180 turn is to the left, false if to the right, nil if we don't know
function Course:isNextTurnLeft(ix)
    if self.waypoints[ix].nextRowStartIx == nil then
        return nil
    else
        local turnStartWaypointIx = self.waypoints[ix].nextRowStartIx - 1
        return CpMathUtil.getDeltaAngle(self.waypoints[turnStartWaypointIx].yRot, self.waypoints[turnStartWaypointIx - 1].yRot) < 0
    end
end

function Course:getIxRollover(ix)
    if ix > #self.waypoints then
        return ix - #self.waypoints
    elseif ix < 1 then
        return #self.waypoints - ix
    end
    return ix
end

function Course:isLastWaypointIx(ix)
    return #self.waypoints == ix
end

function Course:print()
    for i = 1, #self.waypoints do
        local p = self.waypoints[i]
        print(string.format('%d: x=%.1f z=%.1f a=%.1f yRot=%.1f re=%s rs=%s r=%s d=%.1f t=%d l=%s p=%s tt=%s dx=%.1f dz=%.1f',
                i, p.x, p.z, p.angle or -1, math.deg(p.yRot or 0),
                tostring(p:isRowEnd()), tostring(p:isRowStart()), tostring(p.rev), p.dToHere or -1, p.turnsToHere or -1,
                tostring(p.attributes:getHeadlandPassNumber()), tostring(p.pipeInFruit), tostring(p.useTightTurnOffset), p.dx, p.dz))
    end
end

function Course:getDistanceToNextWaypoint(ix)
    return self.waypoints[math.min(#self.waypoints, ix)].dToNext
end

function Course:getDistanceBetweenWaypoints(a, b)
    return math.abs(self.waypoints[a].dToHere - self.waypoints[b].dToHere)
end

function Course:getDistanceFromFirstWaypoint(ix)
    return self.waypoints[ix].dToHere
end

function Course:getDistanceToLastWaypoint(ix)
    return self.length - self.waypoints[ix].dToHere
end

--- How far are we from the waypoint marked as the beginning of the up/down rows?
---@param ix number start searching from this index. Will stop searching after 100 m
---@return number, number of meters or math.huge if no start up/down row waypoint found within 100 meters and the
--- index of the first up/down waypoint
function Course:getDistanceToFirstUpDownRowWaypoint(ix)
    local d = 0
    local isConnectingPath = false
    for i = ix, #self.waypoints - 1 do
        isConnectingPath = isConnectingPath or self.waypoints[i].attributes:isOnConnectingPath()
        d = d + self.waypoints[i].dToNext
        if self.waypoints[i].attributes:getHeadlandPassNumber() and not self.waypoints[i + 1].attributes:getHeadlandPassNumber() and isConnectingPath then
            return d, i + 1
        end
        if d > 1000 then
            return math.huge, nil
        end
    end
    return math.huge, nil
end

function Course:hasWaypointWithPropertyAround(ix, forward, backward, hasProperty)
    for i = math.max(ix - backward + 1, 1), math.min(ix + forward - 1, #self.waypoints) do
        if hasProperty(self.waypoints[i]) then
            -- one of the waypoints around ix has this property
            return true, i
        end
    end
    return false
end

--- Is there an turn (start or end) around ix?
---@param ix number waypoint index to look around
---@param distance number distance in meters to look around the waypoint
---@return boolean true if any of the waypoints are turn start/end point
function Course:hasTurnWithinDistance(ix, distance)
    return self:hasWaypointWithPropertyWithinDistance(ix, distance, function(p)
        return p:isRowEnd() or p:isRowStart()
    end)
end

function Course:hasWaypointWithPropertyWithinDistance(ix, distance, hasProperty)
    -- search backwards first
    local d = 0
    for i = math.max(1, ix - 1), 1, -1 do
        if hasProperty(self.waypoints[i]) then
            return true, i
        end
        d = d + self.waypoints[i].dToNext
        if d > distance then
            break
        end
    end
    -- search forward
    d = 0
    for i = ix, #self.waypoints - 1 do
        if hasProperty(self.waypoints[i]) then
            return true, i
        end
        d = d + self.waypoints[i].dToNext
        if d > distance then
            break
        end
    end
    return false
end

--- Get the index of the first waypoint from ix which is at least distance meters away
---@param backward boolean search backward if true
---@return number, number index and exact distance
function Course:getNextWaypointIxWithinDistance(ix, distance, backward)
    local d = 0
    local from, to, step = ix, #self.waypoints - 1, 1
    if backward then
        from, to, step = ix - 1, 1, -1
    end
    for i = from, to, step do
        d = d + self.waypoints[i].dToNext
        if d > distance then
            return i + 1, d
        end
    end
    -- at the end/start of course return last/first wp
    return to + 1, d
end

--- Get the index of the first waypoint from ix which is at least distance meters away (search backwards)
function Course:getPreviousWaypointIxWithinDistance(ix, distance)
    local d = 0
    for i = math.max(1, ix - 1), 1, -1 do
        d = d + self.waypoints[i].dToNext
        if d > distance then
            return i
        end
    end
    return nil
end

--- Get the index of the first waypoint from ix which is at least distance meters away (search backwards)
--- or the index of the last turn end waypoint, whichever comes first
function Course:getPreviousWaypointIxWithinDistanceOrToTurnEnd(ix, distance)
    local d = 0
    if self:isTurnEndAtIx(ix) then
        return ix
    end
    for i = math.max(1, ix - 1), 1, -1 do
        d = d + self.waypoints[i].dToNext
        if self:isTurnEndAtIx(i) or d > distance then
            return i
        end
    end
    return nil
end

function Course:getLength()
    return self.length
end

--- Is there a turn between the two waypoints?
function Course:isTurnBetween(ix1, ix2)
    return self.waypoints[ix1].turnsToHere ~= self.waypoints[ix2].turnsToHere
end

function Course:getRemainingDistanceAndTurnsFrom(ix)
    local distance = self.length - self.waypoints[ix].dToHere
    local numTurns = self.totalTurns - self.waypoints[ix].turnsToHere
    return distance, numTurns
end

function Course:getNextFwdWaypointIx(ix)
    for i = ix, #self.waypoints do
        if not self:isReverseAt(i) then
            return i
        end
    end
    CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, 'Course: could not find next forward waypoint after %d', ix)
    return ix
end

---@param ix number waypoint index to start the search at
---@param vehicleNode number node representing the vehicle position
---@param maxDx number maximum lateral deviation of the found waypoint
---@param lookAhead number number of waypoints in front of ix to search for, default 10
---@return number index of next waypoint in front of us, or ix when not found
---@return boolean true if we found the next waypoint
function Course:getNextFwdWaypointIxFromVehiclePosition(ix, vehicleNode, maxDx, lookAhead)
    -- only look at the next few waypoints, we don't want to find anything far away, really, it should be in front of us
    for i = ix, math.min(ix + (lookAhead or 10), #self.waypoints) do
        if not self:isReverseAt(i) then
            local uX, uY, uZ = self:getWaypointPosition(i)
            local dx, _, dz = worldToLocal(vehicleNode, uX, uY, uZ);
            if dz > 0 and math.abs(dx) < maxDx then
                return i, true
            end
        end
    end
    CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, 'Course: could not find next forward waypoint from vehicle position after %d', ix)
    return ix, false
end

function Course:getNextRevWaypointIxFromVehiclePosition(ix, vehicleNode, lookAheadDistance)
    for i = ix, #self.waypoints do
        if self:isReverseAt(i) then
            local uX, uY, uZ = self:getWaypointPosition(i)
            local _, _, z = worldToLocal(vehicleNode, uX, uY, uZ);
            if z < -lookAheadDistance then
                return i
            end
        end
    end
    CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, 'Course: could not find next reverse waypoint from vehicle position after %d', ix)
    return ix
end

--- Cut waypoints from the end of the course until we shortened it by at least d
-- @param d length in meters to shorten course
-- @return true if shortened
-- TODO: this must be protected from courses with a few waypoints only
function Course:shorten(d)
    local dCut = 0
    local from = #self.waypoints - 1
    for i = from, 1, -1 do
        dCut = dCut + self.waypoints[i].dToNext
        if dCut > d then
            self:enrichWaypointData()
            return true
        end
        table.remove(self.waypoints)
    end
    self:enrichWaypointData()
    return false
end

--- Append waypoints to the course
---@param waypoints Waypoint[]
function Course:appendWaypoints(waypoints)
    for i = 1, #waypoints do
        table.insert(self.waypoints, Waypoint(waypoints[i]))
    end
    self:enrichWaypointData()
end

--- Append another course to the course
---@param other Course
function Course:append(other)
    self:appendWaypoints(other.waypoints)
end

--- Return a copy of the course
function Course:copy(vehicle, first, last)
    local newCourse = Course(vehicle or self.vehicle, self.waypoints, self:isTemporary(), first, last)
    newCourse:setName(self:getName())
    newCourse.nVehicles = self.nVehicles
    newCourse.workWidth = self.workWidth
    newCourse.numberOfHeadlands = self.numberOfHeadlands
    if self.nVehicles > 1 then
        newCourse.multiVehicleData = self.multiVehicleData:copy()
    end
    return newCourse
end

--- Append a single waypoint to the course
---@param waypoint Waypoint
function Course:appendWaypoint(waypoint)
    table.insert(self.waypoints, Waypoint(waypoint))
end

--- Extend a course with a straight segment (same direction as last WP)
---@param length number the length to extend the course with
---@param dx number    direction to extend
---@param dz number direction to extend
function Course:extend(length, dx, dz)
    -- remember the number of waypoints when we started
    local nWaypoints = #self.waypoints
    local lastWp = self.waypoints[#self.waypoints]
    dx, dz = dx or lastWp.dx, dz or lastWp.dz
    local step = 5
    local first = math.min(length, step)
    local last = length
    for i = first, last, step do
        local x = lastWp.x + dx * i
        local z = lastWp.z + dz * i
        self:appendWaypoint({ x = x, z = z })
    end
    if length % step > 0 then
        -- add the remainder to make sure we extend all the way up to length
        local x = lastWp.x + dx * length
        local z = lastWp.z + dz * length
        self:appendWaypoint({ x = x, z = z })
    end
    -- enrich the waypoints we added
    self:enrichWaypointData(nWaypoints)
end

--- Reverse a course, that is, the last waypoint becomes the first and the first the last.
--- Row start/end and other attributes are flipped accordingly.
--- @see CourseGenerator.FieldworkCourse:reverse() and
--- @see CourseGenerator.WaypointAttributes:reverse()
function Course:reverse()
    CourseGenerator.reverseArray(self.waypoints)
    for _, p in ipairs(self.waypoints) do
        p.attributes:_reverse()
    end
    self:enrichWaypointData()
    CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, 'Course reversed')
end

--- Create a new (straight) temporary course based on a node
---@param vehicle table
---@param referenceNode number
---@param xOffset number side offset of the new course (relative to node), left positive
---@param from number start at this many meters z offset from node
---@param to number end at this many meters z offset from node
---@param step number step (waypoint distance), must be negative if to < from
---@param reverse boolean is this a reverse course?
function Course.createFromNode(vehicle, referenceNode, xOffset, from, to, step, reverse)
    local waypoints = {}
    -- never go under 0.5 m length, also protect from division by zero when from == to
    local distance = math.max(math.abs(from - to), 0.5)
    -- if the distance < step, reduce step to the distance, so we have at least two waypoints.
    local nPoints = math.floor(distance / math.min(distance, math.abs(step))) + 1
    local dBetweenPoints = (to - from) / (nPoints - 1)
    local dz = from
    for i = 0, nPoints - 1 do
        local x, _, z = localToWorld(referenceNode, xOffset, 0, dz + i * dBetweenPoints)
        table.insert(waypoints, { x = x, z = z, rev = reverse })
    end
    return Course(vehicle, waypoints, true)
end

--- Create a straight, forward course for the vehicle.
---@param vehicle table the course will start at the root node of the vehicle
---@param length number|nil optional length of the course in meters, default is 100 meters
---@param xOffset number|nil optional side offset for the course
---@param directionNode number|nil optional force direction node
function Course.createStraightForwardCourse(vehicle, length, xOffset, directionNode)
    local l = length or 100
    return Course.createFromNode(vehicle, directionNode or vehicle.rootNode, xOffset or 0, 0, l, 5, false)
end

--- Create a straight, reverse course for the vehicle.
---@param vehicle table the course will start at the root node of the last implement attached to the vehicle, or
--- at the vehicle's root node if there are not implements attached.
---@param length number|nil optional length of the course in meters, default is 100 meters
---@param xOffset number|nil optional side offset for the course
---@param lastNode number|nil optional force last node
function Course.createStraightReverseCourse(vehicle, length, xOffset, lastNode)
    local lastTrailer = AIUtil.getLastAttachedImplement(vehicle)
    local l = length or 100
    return Course.createFromNode(vehicle, lastNode or lastTrailer.rootNode or vehicle.rootNode, xOffset or 0, 0, -l, -5, true)
end

--- The Reeds-Shepp algorithm we have does not take into account any towed implement or trailer, it calculates
--- the path for a single vehicle. Therefore, we need to extend the path at the cusps (direction changes) to
--- allow the towed implement to also reach the cusp, or, when reversing, reverse enough that the tractor reaches
--- the cusp.
function Course:adjustForTowedImplements(extensionLength)
    self:extendCusps(extensionLength, function(i)
        return self:switchingDirectionAt(i)
    end)
end

--- Same here, for vehicles which have a reverser node. When driving in reverse, we use the reverser node
--- for the PPC. The reverser node reaches the waypoint where the direction changes to forward earlier
--- than the direction node we used to calculate the path because it is usually further back than the
--- direction node. This makes the vehicle change to forward too early and aligning with the forward
--- leg difficult.
--- Therefore, we extend the reversing leg a bit so the direction node can reach the calculate direction
--- change waypoint.
function Course:adjustForReversing(extensionLength)
    self:extendCusps(extensionLength, function(i)
        return self:switchingToForwardAt(i)
    end)
end

function Course:extendCusps(extensionLength, selectionFunc)
    local waypoints = Course.initWaypoints()
    for i = 1, #self.waypoints do
        if selectionFunc(i) then
            local wp = self.waypoints[i]
            local newWp = Waypoint(wp)
            newWp.x = wp.x - wp.dx * extensionLength
            newWp.z = wp.z - wp.dz * extensionLength
            table.insert(waypoints, newWp)
        else
            table.insert(waypoints, self.waypoints[i])
        end
    end
    self.waypoints = waypoints
    self:enrichWaypointData()
end

--- Create a new temporary course between two nodes.
---@param vehicle table
---@param startNode number
---@param endNode number
---@param xOffset number side offset of the new course (relative to node), left positive
---@param zStartOffset number start at this many meters z offset from node
---@param zEndOffset number end at this many meters z offset from node
---@param step number step (waypoint distance), must be positive
---@param reverse boolean is this a reverse course?
function Course.createFromNodeToNode(vehicle, startNode, endNode, xOffset, zStartOffset, zEndOffset, step, reverse)
    local waypoints = {}

    local dist = calcDistanceFrom(startNode, endNode)

    local node = createTransformGroup("temp")

    local x, y, z = getWorldTranslation(startNode)
    local dx, _, dz = getWorldTranslation(endNode)
    local nx, nz = MathUtil.vector2Normalize(dx - x, dz - z)

    local yRot = 0
    if nx == nx or nz == nz then
        yRot = MathUtil.getYRotationFromDirection(nx, nz)
    end

    setTranslation(node, x, 0, z)
    setRotation(node, 0, yRot, 0)

    for d = zStartOffset, dist + zEndOffset, step do
        local ax, _, az = localToWorld(node, xOffset, 0, d)
        table.insert(waypoints, { x = ax, z = az, rev = reverse })
    end
    ---Make sure that at the end is a waypoint.
    local ax, _, az = localToWorld(node, xOffset, 0, dist + zEndOffset)
    table.insert(waypoints, { x = ax, z = az, rev = reverse })

    CpUtil.destroyNode(node)
    local course = Course(vehicle, waypoints, true)
    course:enrichWaypointData()
    return course
end

--- Create a new (straight) temporary course based on a world coordinates
---@param vehicle table
---@param sx number x at start position
---@param sz number z at start position
---@param ex number x at end position
---@param ez number z at end position
---@param xOffset number side offset of the new course (relative to node), left positive
---@param zStartOffset number start at this many meters z offset from node
---@param zEndOffset number end at this many meters z offset from node
---@param step number step (waypoint distance), must be positive
---@param reverse boolean is this a reverse course?
function Course.createFromTwoWorldPositions(vehicle, sx, sz, ex, ez, xOffset, zStartOffset, zEndOffset, step, reverse)
    local waypoints = {}

    local yRot
    local nx, nz = MathUtil.vector2Normalize(ex - sx, ez - sz)
    if nx ~= nx or nz ~= nz then
        yRot = 0
    else
        yRot = MathUtil.getYRotationFromDirection(nx, nz)
    end

    local node = createTransformGroup("temp")

    setTranslation(node, sx, 0, sz)
    setRotation(node, 0, yRot, 0)

    local dist = MathUtil.getPointPointDistance(sx, sz, ex, ez)

    for d = zStartOffset, dist + zEndOffset, step do
        local ax, _, az = localToWorld(node, xOffset, 0, d)
        if MathUtil.getPointPointDistance(ex, ez, ax, az) > 0.1 * step then
            -- only add this point if not too close to the end point (as the end point will always be added)
            table.insert(waypoints, { x = ax, z = az, rev = reverse })
        end
    end
    ---Make sure that at the end is a waypoint.
    local ax, _, az = localToWorld(node, xOffset, 0, dist + zEndOffset)
    table.insert(waypoints, { x = ax, z = az, rev = reverse })

    CpUtil.destroyNode(node)
    local course = Course(vehicle, waypoints, true)
    course:enrichWaypointData()
    return course
end

function Course:getDirectionToWPInDistance(ix, vehicle, distance)
    local lx, lz = 0, 1
    for i = ix, #self.waypoints do
        if self:getDistanceBetweenVehicleAndWaypoint(vehicle, i) > distance then
            local x, y, z = self:getWaypointPosition(i)
            lx, lz = AIVehicleUtil.getDriveDirection(vehicle.cp.directionNode, x, y, z)
            break
        end
    end
    return lx, lz
end

function Course:getDistanceToNextTurn(ix)
    return self.waypoints[ix].dToNextTurn
end

function Course:getDistanceFromLastTurn(ix)
    return self.waypoints[ix].dFromLastTurn
end

function Course:getDistanceToNextDirectionChange(ix)
    return self.waypoints[ix].dToNextDirectionChange
end

--- Are we closer than distance to the next turn?
---@param distance number
---@return boolean true when we are closer than distance to the next turn, false otherwise, even
--- if we can't determine the distance to the next turn.
function Course:isCloseToNextTurn(distance)
    local ix = self.currentWaypoint
    if ix then
        local dToNextTurn = self:getDistanceToNextTurn(ix)
        if dToNextTurn and dToNextTurn < distance then
            return true
        elseif self:isTurnEndAtIx(ix) or self:isTurnStartAtIx(ix) then
            return true
        else
            return false
        end
    end
    return false
end

--- Is the current waypoint within distance of a property, where getDistanceFunc() is a function which
--- determines this distance
---@param distance number
---@param getDistanceFunc function(ix)
function Course:isCloseToProperty(distance, getDistanceFunc)
    local ix = self.currentWaypoint
    if ix then
        local d = getDistanceFunc(self, ix)
        if d and d < distance then
            return true
        else
            return false
        end
    end
    return false
end

--- Are we closer than distance from the last turn?
---@param distance number
---@return boolean true when we are closer than distance to the last turn, false otherwise, even
--- if we can't determine the distance to the last turn.
function Course:isCloseToLastTurn(distance)
    return self:isCloseToProperty(distance, Course.getDistanceFromLastTurn)
end

--- Are we closer than distance to the next direction change?
---@param distance number
---@return boolean true when we are closer than distance to the next direction change, false otherwise, or when
--- the distance is not known
function Course:isCloseToNextDirectionChange(distance)
    return self:isCloseToProperty(distance, Course.getDistanceToNextDirectionChange)
end

function Course:isCloseToLastWaypoint(distance)
    return self:isCloseToProperty(distance, Course.getDistanceToLastWaypoint)
end

--- Get the length of the up/down row where waypoint ix is located
--- @param ix number waypoint index in the row
--- @return number length of the current row
--- @return number index of the first waypoint of the row or ix, if no turn was found for some reason.
function Course:getRowLength(ix)
    for i = ix, 1, -1 do
        if self:isTurnEndAtIx(i) then
            return self:getDistanceToNextTurn(i), i
        end
    end
    return 0, ix
end

function Course:getNextRowLength(ix)
    return self.waypoints[ix].lNextRow
end

function Course:getNextRowStartIx(ix)
    return self.waypoints[ix].nextRowStartIx
end

function Course:draw()
    for i = 1, self:getNumberOfWaypoints() do
        local x, y, z = self:getWaypointPosition(i)
        local color = self:isReverseAt(i) and {0.8, 0.3, 0.3} or {0.3, 0.3, 0.8}
        Utils.renderTextAtWorldPosition(x, y + 3.2, z, tostring(i), getCorrectTextSize(0.012), 0, color)
        if i < self:getNumberOfWaypoints() then
            local nx, ny, nz = self:getWaypointPosition(i + 1)
            -- cyan, darker blue with tight turn offset
            color = self:getUseTightTurnOffset(i) and {0, 0, 0.5} or {0, 0.5, 0.5}
            DebugUtil.drawDebugLine(x, y + 3, z, nx, ny + 3, nz, table.unpack(color))
        end
    end
end

function Course:worldToWaypointLocal(ix, x, y, z)
    local tempNode = WaypointNode('worldToWaypointLocal')
    tempNode:setToWaypoint(self, ix)
    setRotation(tempNode.node, 0, self:getWaypointYRotation(ix), 0);
    local dx, dy, dz = worldToLocal(tempNode.node, x, y, z)
    tempNode:destroy()
    return dx, dy, dz
end

function Course:waypointLocalToWorld(ix, x, y, z)
    local tempNode = WaypointNode('waypointLocalToWorld')
    tempNode:setToWaypoint(self, ix)
    setRotation(tempNode.node, 0, self:getWaypointYRotation(ix), 0);
    local dx, dy, dz = localToWorld(tempNode.node, x, y, z)
    tempNode:destroy()
    return dx, dy, dz
end

function Course:setNodeToWaypoint(node, ix)
    local x, y, z = self:getWaypointPosition(ix)
    setTranslation(node, x, y, z)
    setRotation(node, 0, self:getWaypointYRotation(ix), 0)
end

--- Run a function for all waypoints of the course within the last d meters
---@param d number
---@param lambda function (waypoint)
---@param stopAtDirectionChange boolean if we reach a direction change, stop there, the last waypoint the function
--- is called for is the one before the direction change
function Course:executeFunctionForLastWaypoints(d, lambda, stopAtDirectionChange)
    local i = self:getNumberOfWaypoints()
    while i > 1 and self:getDistanceToLastWaypoint(i) < d and
            ((stopAtDirectionChange and not self:switchingDirectionAt(i)) or not stopAtDirectionChange) do
        lambda(self.waypoints[i])
        i = i - 1
    end
end

function Course:setUseTightTurnOffsetForLastWaypoints(d)
    self:executeFunctionForLastWaypoints(d, function(wp)
        wp:setUseTightTurnOffset()
    end)
end

--- Return the waypoints between startIx and endIx as a new course
---@param startIx number
---@param endIx number
---@param reverse boolean when true, set waypoints to reverse (unless allAttributes true)
---@param allAttributes boolean copy all attributes of the waypoint when true, otherwise
--- just x, z coordinates
function Course:getSectionAsNewCourse(startIx, endIx, reverse, allAttributes)
    local section = Course(self.vehicle, {})
    for i = startIx, endIx, startIx < endIx and 1 or -1 do
        local wp = self.waypoints[i]
        if wp then
            if allAttributes then
                section:appendWaypoint(wp)
            else
                section:appendWaypoint({ x = wp.x, z = wp.z, rev = reverse })
            end
        end
    end
    section:enrichWaypointData()
    return section, self:getNumberOfWaypoints()
end

--- @param node number the node around we are looking for waypoints
--- @param startIx number|nil start looking for waypoints at this index
--- @return number, number, number, number the waypoint closest to node, its distance, the waypoint closest to the node
--- pointing approximately (+-45) in the same direction as the node and its distance
function Course:getNearestWaypoints(node, startIx)
    local nx, _, nz = getWorldTranslation(node)
    local lx, _, lz = localDirectionToWorld(node, 0, 0, 1)
    local nodeAngle = math.atan2(lx, lz)
    local maxDeltaAngle = math.pi / 2
    local dClosest, dClosestRightDirection = math.huge, math.huge
    local ixClosest, ixClosestRightDirection = 1, 1

    for i = startIx or 1, #self.waypoints do
        local p = self.waypoints[i]
        local x, _, z = self:getWaypointPosition(i)
        local d = MathUtil.getPointPointDistance(x, z, nx, nz)
        if d < dClosest then
            dClosest = d
            ixClosest = i
        end
        local deltaAngle = math.abs(CpMathUtil.getDeltaAngle(math.rad(p.angle), nodeAngle))
        if d < dClosestRightDirection and deltaAngle < maxDeltaAngle then
            dClosestRightDirection = d
            ixClosestRightDirection = i
        end
    end

    return ixClosest, dClosest, ixClosestRightDirection, dClosestRightDirection
end

--- Check if our course intersects otherCourse
---@param otherCourse Course
---@param lookahead number distance in meters we want to traverse on our course to check for an intersection
---@param startAtCurrentWaypoint boolean if true, start checking at the current waypoint on both courses,
--- otherwise at the first waypoint
---@return number, number distance on my course to the intersection point (or nil when there is no intersection),
--- distance on the other course until the intersection point.
function Course:intersects(otherCourse, lookahead, startAtCurrentWaypoint)
    local myDistance = 0
    for i = startAtCurrentWaypoint and self:getCurrentWaypointIx() or 1, #self.waypoints - 1 do
        local m1, m2 = self.waypoints[i], self.waypoints[i + 1]
        myDistance = myDistance + m2.dToHere - m1.dToHere
        local otherDistance = 0
        for j = startAtCurrentWaypoint and otherCourse:getCurrentWaypointIx() or 1, #otherCourse.waypoints - 1 do
            local o1, o2 = otherCourse.waypoints[j], otherCourse.waypoints[j + 1]
            otherDistance = otherDistance + o2.dToHere - o1.dToHere
            if CpMathUtil.getIntersectionPoint(m1.x, m1.z, m2.x, m2.z, o1.x, o1.z, o2.x, o2.z) then
                -- these sections intersect
                return myDistance, otherDistance
            end
        end
        if myDistance > lookahead then
            break
        end
    end
    return nil
end

function Course:isPipeInFruitAt(ix)
    return self.waypoints[ix].pipeInFruit
end

--- For each non-headland waypoint of the course determine if the pipe will be
--- in the fruit at that waypoint, assuming that the course is driven continuously from the
--- start to the end waypoint
-- TODO: with the new course generator, we should know if the left/right side of the row is worked or not, so
-- this whole thing may be obsolete
---@return number, number the total number of non-headland waypoints, the total number waypoint where
--- the pipe will be in the fruit
function Course:setPipeInFruitMap(pipeOffsetX, workWidth)
    local pipeInFruitMapHelperWpNode = WaypointNode('pipeInFruitMapHelperWpNode')
    ---@param rowStartIx number index of the first waypoint of the row
    local function createRowRectangle(rowStartIx)
        -- find the end of the row
        local rowEndIx = #self.waypoints
        for i = rowStartIx, #self.waypoints do
            if self:isTurnStartAtIx(i) then
                rowEndIx = i
                break
            end
        end
        pipeInFruitMapHelperWpNode:setToWaypoint(self, rowStartIx, true)
        local x, y, z = self:getWaypointPosition(rowEndIx)
        local _, _, rowLength = worldToLocal(pipeInFruitMapHelperWpNode.node, x, y, z)
        local row = {
            startIx = rowStartIx,
            length = rowLength
        }
        return row
    end

    local function setPipeInFruit(ix, pipeOffsetX, rows)
        local halfWorkWidth = workWidth / 2
        pipeInFruitMapHelperWpNode:setToWaypoint(self, ix, true)
        local x, y, z = localToWorld(pipeInFruitMapHelperWpNode.node, pipeOffsetX, 0, 0)
        for _, row in ipairs(rows) do
            pipeInFruitMapHelperWpNode:setToWaypoint(self, row.startIx)
            -- pipe's local position in the row start wp's system
            local lx, _, lz = worldToLocal(pipeInFruitMapHelperWpNode.node, x, y, z)
            -- add 20 m buffer to account for non-perpendicular headlands where technically the pipe
            -- would not be in the fruit around the end of the row
            if math.abs(lx) <= halfWorkWidth and lz >= -20 and lz <= row.length + 20 then
                -- pipe is in the fruit at ix
                return true
            end
        end
        return false
    end

    -- The idea here is that we walk backwards on the course, remembering each row and adding them
    -- to the list of unworked rows. This way, at any waypoint we have a list of rows the vehicle
    -- wouldn't have finished if it was driving the course the right way (start to end).
    -- Now check if the pipe would be in any of these unworked rows
    local rowsNotDone = {}
    local totalNonHeadlandWps = 0
    local pipeInFruitWps = 0
    -- start at the end of the course
    local i = #self.waypoints
    while i > 1 do
        -- skip over the headland, we assume the headland is worked first and will always be harvested before
        -- we get to the middle of the field. If not, your problem...
        if not self:isOnHeadland(i) then
            totalNonHeadlandWps = totalNonHeadlandWps + 1
            -- check if the pipe is in an unworked row
            self.waypoints[i].pipeInFruit = setPipeInFruit(i, pipeOffsetX, rowsNotDone)
            -- turn start waypoints point towards the turn end waypoint so setPipeInFruit magic won't work,
            -- offset position is not towards to previous row, so here, just use the same setting as the
            -- waypoint before the turn
            if self.waypoints[i].pipeInFruit and i < #self.waypoints and self:isTurnStartAtIx(i + 1) then
                self.waypoints[i + 1].pipeInFruit = true
            end
            pipeInFruitWps = pipeInFruitWps + (self.waypoints[i].pipeInFruit and 1 or 0)
            if self:isTurnEndAtIx(i) then
                -- we are at the start of a row (where the turn ends)
                table.insert(rowsNotDone, createRowRectangle(i))
            end
        end
        i = i - 1
    end
    pipeInFruitMapHelperWpNode:destroy()
    return totalNonHeadlandWps, pipeInFruitWps
end

---@param ix number waypoint where we want to get the progress, when nil, uses the current waypoint
---@return number, number, boolean 0-1 progress, waypoint where the progress is calculated, true if last waypoint
function Course:getProgress(ix)
    ix = ix or self:getCurrentWaypointIx()
    return self.waypoints[ix].dToHere / self.length, ix, ix == #self.waypoints
end

--- Calculate the y rotation of the waypoint. This is to avoid having to call enrichWaypointData() for each multitool
--- course, as this is the only thing we need to figure out if a row is straight or not.
local function calculateYRot(waypoints, i)
    local x1, z1 = waypoints[i].x, waypoints[i].z
    local x2, z2 = waypoints[i + 1].x, waypoints[i + 1].z
    if (x1 - x2) == 0 and (z1 - z2) == 0 then 
        -- Divide by zero fix ..
        return 0
    end
    local nx, nz = MathUtil.vector2Normalize(x2 - x1, z2 - z1)
    -- check for NaN
    if nx == nx and nz == nz then
        return MathUtil.getYRotationFromDirection(nx, nz)
    else
        return 0
    end
end
--- When compaction is enabled we only save the start and end of a row, except when it isn't straight, for instance
--- because it is bypassing an island. For those rows, we save all waypoints.
--- Baseline edge courses (with rows following a curved field edge) have the compaction disabled anyway.
---@return number, number index of next unsaved waypoint, index of next waypoint entry in the XML file
local function saveRowToXml(waypoints, xmlFile, key, compact, rowStartIx, xmlIx)
    local row = {}
    local i, straight, rowAngle = rowStartIx, true, calculateYRot(waypoints, rowStartIx)
    while i < #waypoints and not waypoints[i]:isRowEnd() do
        table.insert(row, waypoints[i])
        if math.abs(calculateYRot(waypoints, i) - rowAngle) > 0.01 then
            straight = false
        end
        i = i + 1
    end
    -- i points to the row end, add it to the row
    local rowEndIx = i
    table.insert(row, waypoints[i])
    if straight and compact then
        -- only save the row start and end
        waypoints[rowStartIx]:setXmlValue(xmlFile, key, xmlIx)
        waypoints[rowEndIx]:setXmlValue(xmlFile, key, xmlIx + 1)
        return rowEndIx + 1, xmlIx + 2
    else
        i = xmlIx
        -- save all waypoints
        for _, wp in ipairs(row) do
            wp:setXmlValue(xmlFile, key, i)
            i = i + 1
        end
        return rowEndIx + 1, i
    end
end

---@param compact boolean skip waypoints between row start and end (as for straight rows, these can be regenerated
--- easily after the course is loaded)
local function saveWaypointsToXml(waypoints, xmlFile, key, compact)
    local wpIx, xmlIx = 1, 1
    while wpIx <= #waypoints do
        local wp = waypoints[wpIx]
        if wp:isRowStart() then
            wpIx, xmlIx = saveRowToXml(waypoints, xmlFile, key, compact, wpIx, xmlIx)
        else
            wp:setXmlValue(xmlFile, key, xmlIx)
            wpIx = wpIx + 1
            xmlIx = xmlIx + 1
        end
    end
end

-- The idea is not to store the waypoints of a fieldwork row (as it is just a straight line, unless we use the baseline
-- edge feature of the generator), only the start and the end
-- of the row (turn end and turn start waypoints). We still need those intermediate
-- waypoints though when working so the PPC does not put the targets kilometers away, so after loading a course, these
-- points can be generated by this function
local function addIntermediateWaypoints(d, waypoints, rowStart, rowEnd)
    local dx, dz = (rowEnd.x - rowStart.x) / d, (rowEnd.z - rowStart.z) / d
    for n = 1, math.floor((d -1) / CourseGenerator.cRowWaypointDistance) do
        local newWp = Waypoint({})
        newWp.x = rowStart.x + n * CourseGenerator.cRowWaypointDistance * dx
        newWp.z = rowStart.z + n * CourseGenerator.cRowWaypointDistance * dz
        newWp:copyRowData(rowStart)
        table.insert(waypoints, newWp)
    end
end

--- From XML -----------------------------------------------------------------------------------------------------------
local function createWaypointsFromXml(xmlFile, key)
    local waypoints = Course.initWaypoints()
    -- these are only saved for the row start waypoint, here we add them to all waypoints of the row
    local rowStart
    xmlFile:iterate(key .. Waypoint.xmlKey, function(ix, wpKey)
        local wp = Waypoint.createFromXmlFile(xmlFile, wpKey)
        if wp:isRowStart() then
            rowStart = wp
        elseif wp:isRowEnd() then
            local d = wp:getDistanceFromOther(waypoints[#waypoints])
            if waypoints[#waypoints]:isRowStart() and d > CourseGenerator.cRowWaypointDistance + 0.1 then
                -- there is now intermediate waypoints between the row start and row end and they are further
                -- apart than the row waypoint distance, add intermediate waypoints
                addIntermediateWaypoints(d, waypoints, waypoints[#waypoints], wp)
            end
            rowStart = nil
        elseif rowStart then
            -- normal row waypoint, copy the row data from the row start waypoint
            wp:copyRowData(rowStart)
        end
        table.insert(waypoints, wp)
    end)
    return waypoints
end

function Course:saveToXml(courseXml, courseKey)
    courseXml:setValue(courseKey .. '#name', self.name)
    courseXml:setValue(courseKey .. '#workWidth', self.workWidth or 0)
    courseXml:setValue(courseKey .. '#numHeadlands', self.numberOfHeadlands or 0)
    courseXml:setValue(courseKey .. '#nVehicles', self.nVehicles or 1)
    CpUtil.setXmlValue(courseXml, courseKey .. '#headlandClockwise', self.headlandClockwise)
    CpUtil.setXmlValue(courseXml, courseKey .. '#islandHeadlandClockwise', self.islandHeadlandClockwise)
    courseXml:setValue(courseKey .. '#wasEdited', self.editedByCourseEditor)
    CpUtil.setXmlValue(courseXml, courseKey .. '#compacted', self.compacted)
    if self.nVehicles > 1 then
        self.multiVehicleData:setXmlValue(courseXml, courseKey, self.compacted)
    else
        -- only write the current waypoints if we are not a multi-vehicle course
        saveWaypointsToXml(self.waypoints, courseXml, courseKey, self.compacted)
    end
end

---@param vehicle  table|nil
---@param courseXml table
---@param courseKey string key to the course in the XML
function Course.createFromXml(vehicle, courseXml, courseKey)
    local course = Course(vehicle, {})
    course.name = courseXml:getValue(courseKey .. '#name')
    course.workWidth = courseXml:getValue(courseKey .. '#workWidth')
    course.numberOfHeadlands = courseXml:getValue(courseKey .. '#numHeadlands')
    course.nVehicles = courseXml:getValue(courseKey .. '#nVehicles', 1)
    course.headlandClockwise = courseXml:getValue(courseKey .. '#headlandClockwise')
    course.islandHeadlandClockwise = courseXml:getValue(courseKey .. '#islandHeadlandClockwise')
    course.editedByCourseEditor = courseXml:getValue(courseKey .. '#compacted', false)
    course.compacted = courseXml:getValue(courseKey .. '#compacted', false)
    if course.nVehicles == 1 then
        -- for multi-vehicle courses, we load the multi-vehicle data and restore the current course
        -- from there, so we don't need to write the same course twice in the savegame
        course.waypoints = createWaypointsFromXml(courseXml, courseKey)
    else
        course.multiVehicleData = Course.MultiVehicleData.createFromXmlFile(courseXml, courseKey)
        course:setPosition(course.multiVehicleData:getPosition())
        if vehicle then
            vehicle:getCpLaneOffsetSetting():setValue(course.multiVehicleData:getPosition())
        end
    end
    course:enrichWaypointData()
    CpUtil.debugVehicle(CpDebug.DBG_COURSES, vehicle, 'Course with %d waypoints loaded.', #course.waypoints)
    return course
end

--- From stream --------------------------------------------------------------------------------------------------------
function Course:writeStream(vehicle, streamId, connection)
    streamWriteString(streamId, self.name or "")
    streamWriteFloat32(streamId, self.workWidth or 0)
    streamWriteInt32(streamId, self.numberOfHeadlands or 0)
    streamWriteInt32(streamId, self.nVehicles or 1)
    CpUtil.streamWriteBool(streamId, self.headlandClockwise)
    CpUtil.streamWriteBool(streamId, self.islandHeadlandClockwise)
    streamWriteInt32(streamId, #self.waypoints or 0)
    streamWriteBool(streamId, self.editedByCourseEditor)
    for i, p in ipairs(self.waypoints) do
        p:writeStream(streamId)
    end
    if self.nVehicles > 1 then
        self.multiVehicleData:writeStream(streamId)
    end
end

function Course.createFromStream(vehicle, streamId, connection)
    local course = Course(vehicle, {})
    course.name = streamReadString(streamId)
    course.workWidth = streamReadFloat32(streamId)
    course.numberOfHeadlands = streamReadInt32(streamId)
    course.nVehicles = streamReadInt32(streamId)
    course.headlandClockwise = CpUtil.streamReadBool(streamId)
    course.islandHeadlandClockwise = CpUtil.streamReadBool(streamId)
    local numWaypoints = streamReadInt32(streamId)
    course.editedByCourseEditor = streamReadBool(streamId)
    for ix = 1, numWaypoints do
        table.insert(course.waypoints, Waypoint.createFromStream(streamId, ix))
    end
    if course.nVehicles > 1 then
        course.multiVehicleData = Course.MultiVehicleData.createFromStream(streamId, course.nVehicles)
        vehicle:getCpLaneOffsetSetting():setValue(course.multiVehicleData:getPosition())
    end
    course:enrichWaypointData()
    CpUtil.debugVehicle(CpDebug.DBG_MULTIPLAYER, vehicle, 'Course with %d waypoints, %d vehicles loaded.',
            #course.waypoints, course.nVehicles)
    return course
end

--- From generator ------------------------------------------------------------------------------------------------------
local function createWaypointsFromGeneratedPath(path)
    local waypoints = Course.initWaypoints()
    for i, wp in ipairs(path) do
        table.insert(waypoints, Waypoint.initFromGeneratedWp(wp, i))
    end
    return waypoints
end

---@param straightRows boolean rows are straight, so are fully defined by the row start and end waypoints, therefore
--- waypoints between them don't have to be saved (for better performance) as they can be restored when loading
function Course.createFromGeneratedCourse(vehicle, generatedCourse, workWidth, numberOfHeadlands, nVehicles,
                                          headlandClockwise, islandHeadlandClockwise, straightRows)
    local waypoints = createWaypointsFromGeneratedPath(generatedCourse:getPath())
    local course = Course(vehicle or CpUtil.getCurrentVehicle(), waypoints)
    course.workWidth = workWidth
    course.numberOfHeadlands = numberOfHeadlands
    course.nVehicles = nVehicles
    course.compacted = straightRows
    course.headlandClockwise = headlandClockwise
    course.islandHeadlandClockwise = islandHeadlandClockwise
    if course.nVehicles > 1 then
        course.multiVehicleData = Course.MultiVehicleData.createFromGeneratedCourse(vehicle, generatedCourse)
    end
    return course
end

--- When creating a course from an analytic path, we want to have the direction of the last waypoint correct
function Course.createFromAnalyticPath(vehicle, path, isTemporary)
    local course = Course(vehicle, CpMathUtil.pointsToGameInPlace(path), isTemporary)
    -- enrichWaypointData rotated the last waypoint in the direction of the second to last,
    -- correct that according to the analytic path's last waypoint
    local yRot = CpMathUtil.angleToGame(path[#path].t or 0)
    course.waypoints[#course.waypoints].yRot = yRot
    course.waypoints[#course.waypoints].angle = math.deg(yRot)
    course.waypoints[#course.waypoints].dx, course.waypoints[#course.waypoints].dz = MathUtil.getDirectionFromYRotation(yRot)
    CpUtil.debugVehicle(CpDebug.DBG_COURSES, vehicle,
            'Last waypoint of the course created from analytical path: angle set to %.1f°', math.deg(yRot))
    return course
end

------------------------------------------------------------------------------------------------------------------------
--- Courses for multiple vehicles working together on the same field as a group (multitool/convoy)
---
--- Course.waypoints is always the active course of the vehicle. For multi-vehicle courses, MultiVehicleData
--- stores the course for each vehicle (position) of the group. When a new position is selected for a vehicle,
--- we make Course.waypoints to point to the waypoint array of the selected position in MultiVehicleData.
------------------------------------------------------------------------------------------------------------------------
--- Set the position of the vehicle in the group and activate the course for that position.
--- @param position number an integer defining the position of this vehicle within the group, negative numbers are to
--- the left, positives to the right. For example, a -2 means that this is the second vehicle to the left (and thus,
--- there are at least 4 vehicles in the group), a 0 means the vehicle in the middle
function Course:setPosition(position)
    if self.multiVehicleData then
        if not self.multiVehicleData.waypoints[position] then
            CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, 'Course position %d does not exist, setting default',
                    position, #self.waypoints)
            -- set to leftmost vehicle
            position = -math.floor(self.nVehicles / 2)
        end
        self.waypoints = self.multiVehicleData.waypoints[position]
        self.multiVehicleData.position = position
        self:enrichWaypointData()
        CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, 'Course position set to %d (%d waypoints)', position, #self.waypoints)
    else
        CpUtil.errorVehicle(self.vehicle, 'Course:setPosition called on a single vehicle course')
    end
end

---@class Course.MultiVehicleData
Course.MultiVehicleData = CpObject()
Course.MultiVehicleData.key = '.multiVehicleData'
function Course.MultiVehicleData:init(position)
    self.position = position or 0
    -- two dimensional array, first index is the position in the group, second index is the waypoint index
    self.waypoints = {}
end

---@return number the active position of the vehicle in the group
function Course.MultiVehicleData:getPosition()
    return self.position
end

function Course.MultiVehicleData.createFromGeneratedCourse(vehicle, generatedCourse)
    local mvd = Course.MultiVehicleData(0)
    for _, position, path in generatedCourse:pathIterator() do
        mvd.waypoints[position] = createWaypointsFromGeneratedPath(path)
        CpUtil.debugVehicle(CpDebug.DBG_COURSES, vehicle, 'Adding %d waypoints for position %d',
                #mvd.waypoints[position], position)
    end
    return mvd
end

function Course.MultiVehicleData:copy()
    local copy = Course.MultiVehicleData(self.position)
    for position, waypoints in pairs(self.waypoints) do
        copy.waypoints[position] = Course.initWaypoints()
        for i, wp in ipairs(waypoints) do
            table.insert(copy.waypoints[position], Waypoint(wp))
        end
    end
    return copy
end

--- XML ----------------------------------------------------------------------------------------------------------------
function Course.MultiVehicleData.registerXmlSchema(schema, baseKey)
    local key = baseKey .. Course.MultiVehicleData.key
    schema:register(XMLValueType.INT, key .. "#selectedPosition", "Selected position")
    key = key .. '.waypoints(?)'
    schema:register(XMLValueType.INT, key .. "#position", "Position of this course")
    Waypoint.registerXmlSchema(schema, key)
end

function Course.MultiVehicleData:setXmlValue(xmlFile, baseKey, compacted)
    local mvdKey = baseKey .. Course.MultiVehicleData.key
    xmlFile:setValue(mvdKey .. '#selectedPosition', self.position)
    local i = 0
    -- save the course for each position in the group
    for position, waypoints in pairs(self.waypoints) do
        local posKey = string.format("%s%s(%d)", mvdKey, '.waypoints', i)
        xmlFile:setValue(posKey .. '#position', position)
        saveWaypointsToXml(waypoints, xmlFile, posKey, compacted)
        i = i + 1
    end
end

function Course.MultiVehicleData.createFromXmlFile(xmlFile, baseKey)
    local mvdKey = baseKey .. Course.MultiVehicleData.key
    local selectedPosition = xmlFile:getValue(mvdKey .. '#selectedPosition')
    local mvd = Course.MultiVehicleData(selectedPosition)
    -- load the course for each position in the group
    xmlFile:iterate(mvdKey .. '.waypoints', function(ix, posKey)
        local position = xmlFile:getValue(posKey .. '#position')
        mvd.waypoints[position] = createWaypointsFromXml(xmlFile, posKey)
    end)
    return mvd
end

--- Stream -------------------------------------------------------------------------------------------------------------
function Course.MultiVehicleData:writeStream(stream)
    streamWriteInt32(stream, self.position)
    for position, waypoints in pairs(self.waypoints) do
        streamWriteInt32(stream, position)
        streamWriteInt32(stream, #waypoints)
        for i, wp in ipairs(waypoints) do
            wp:writeStream(stream)
        end
    end
end

function Course.MultiVehicleData.createFromStream(stream, nVehicles)
    local selectedPosition = streamReadInt32(stream)
    local mvd = Course.MultiVehicleData(selectedPosition)
    for i = 1, nVehicles do
        local position = streamReadInt32(stream)
        local nWaypoints = streamReadInt32(stream)
        mvd.waypoints[position] = Course.initWaypoints()
        for ix = 1, nWaypoints do
            table.insert(mvd.waypoints[position], Waypoint.createFromStream(stream, ix))
        end
    end
    return mvd
end

function Course.MultiVehicleData.getAllowedPositions(nMultiToolVehicles)
    if nMultiToolVehicles == 2 then 
        return {-1,1}
    elseif nMultiToolVehicles == 3 then 
        return {-1,0,1}
    elseif nMultiToolVehicles == 4 then 
        return {-2,-1,1,2}
    elseif nMultiToolVehicles == 5 then 
        return {-2,-1,0,1,2}
    end
    return {0}
end