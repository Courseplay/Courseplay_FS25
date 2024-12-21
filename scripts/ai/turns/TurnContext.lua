--[[
This file is part of Courseplay (https://github.com/Courseplay/FS22_Courseplay)
Copyright (C) 2019 Peter Vaiko

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

---
--- A turn context contains all geometric information about a turn and can be used to
--- generate turn maneuvers for row end (180) or headland (corner) turns.
---
---@class TurnContext
---@field turnStartWp Waypoint
---@field beforeTurnStartWp Waypoint
---@field turnEndWp Waypoint
---@field afterTurnEndWp Waypoint
TurnContext = CpObject()

--- All data needed to create a turn
-- TODO: this uses a bit too many course internal info, should maybe moved into Course?
-- TODO: could this be done a lot easier with child nodes sitting on a single corner node?
---@param course Course
---@param turnStartIx number
---@param turnEndIx number
---@param turnNodes table to store the turn start/end waypoint nodes (which are created if nil passed in)
--- we store the nodes some global, long lived table to avoid creating new nodes every time a TurnContext object
--- is created
---@param workWidth number working width
---@param frontMarkerDistance number distance of the frontmost work area from the vehicle's root node (positive is
--- in front of the vehicle. We'll add a node (vehicleAtTurnEndNode) offset by frontMarkerDistance from the turn end
--- node so when the vehicle's root node reaches the vehicleAtTurnEndNode, the front of the work area will exactly be on the
--- turn end node. (The vehicle must be steered to the vehicleAtTurnEndNode instead of the turn end node so the implements
--- reach exactly the row end)
---@param backMarkerDistance number distance of the rearmost work area from the vehicle's root node. Will be used
--- to pass in to turn generator code and to calculate the minimum length of the row finishing course.
---@param turnEndSideOffset number offset of the turn end in meters to left (>0) or right (<0) to end the turn left or
--- right of the turn end node. Used when there's an offset to consider, for example because the implement is not
--- in the middle, like plows.
---@param turnEndForwardOffset number offset of the turn end in meters forward (>0) or back (<0), additional to the
--- frontMarkerDistance. This can be used to compensate for edge cases like sprayers where the working width is
--- much bigger than the turning diameter so the implement's tip on the turn inside is ahead of the vehicle.
function TurnContext:init(vehicle, course, turnStartIx, turnEndIx, turnNodes, workWidth,
                          frontMarkerDistance, backMarkerDistance, turnEndSideOffset, turnEndForwardOffset)
    self.debugChannel = CpDebug.DBG_TURN
    self.workWidth = workWidth
    self.vehicle = vehicle
    --- Setting up turn waypoints
    self.beforeTurnStartWp = course:getWaypoint(turnStartIx - 1)
    self.turnStartWp = course:getWaypoint(turnStartIx)
    self.turnStartWpIx = turnStartIx
    self.turnEndWp = course:getWaypoint(turnEndIx)
    self.turnEndWpIx = turnEndIx
    self.turnEndAtBoundaryId = self.turnEndWp:getAtBoundaryId()
    self.afterTurnEndWp = course:getWaypoint(math.min(course:getNumberOfWaypoints(), turnEndIx + 1))
    self.directionChangeDeg = math.deg( CpMathUtil.getDeltaAngle( math.rad(self.turnEndWp.angle), math.rad(self.beforeTurnStartWp.angle)))

    self:setupTurnStart(course, turnNodes)

    self.frontMarkerDistance = frontMarkerDistance or 0
    self.backMarkerDistance = backMarkerDistance or 0
    -- this is the node the vehicle's root node must be at so the front of the work area is exactly at the turn start
    if not turnNodes.vehicleAtTurnStartNode then
        turnNodes.vehicleAtTurnStartNode = CpUtil.createNode( 'vehicleAtTurnStart', 0, 0, 0, self.workEndNode )
    end
    setTranslation(turnNodes.vehicleAtTurnStartNode, 0, 0, - self.frontMarkerDistance)

    self.vehicleAtTurnStartNode = turnNodes.vehicleAtTurnStartNode

    self:setupTurnEnd(course, turnNodes, turnEndSideOffset)

    self.turnEndForwardOffset = - self.frontMarkerDistance + turnEndForwardOffset
    -- this is the node the vehicle's root node must be at so the front of the work area is exactly at the turn end
    if not turnNodes.vehicleAtTurnEndNode then
        turnNodes.vehicleAtTurnEndNode = CpUtil.createNode( 'vehicleAtTurnEnd', 0, 0, 0, self.turnEndWpNode.node )
    end
    setTranslation(turnNodes.vehicleAtTurnEndNode, 0, 0, self.turnEndForwardOffset)
    self.vehicleAtTurnEndNode = turnNodes.vehicleAtTurnEndNode

    self.dx, _, self.dz = localToLocal(self.turnEndWpNode.node, self.workEndNode, 0, 0, 0)
    self.leftTurn = self.dx > 0
    self.nextTurnLeft = course:isNextTurnLeft(turnEndIx)
    self:debug('start ix = %d, back marker = %.1f, front marker = %.1f',
            turnStartIx, self.backMarkerDistance, self.frontMarkerDistance)
end

--- Clean up all nodes we might have created and the caller have cached
function TurnContext.deleteNodes(turnNodes)
    if not turnNodes then 
        return        
    end
    for _, node in pairs(turnNodes) do
        -- we create WaypointNodes or just plain nodes, need to delete them differently
        local nodeToDelete = type(node) == 'number' and node or node.node
        CpUtil.destroyNode(nodeToDelete)
    end
end

--- Get overshoot for a headland corner (how far further we need to drive if the corner isn't 90 degrees
--- for full coverage
function TurnContext:getOvershootForHeadlandCorner()
    local headlandAngle = math.rad(math.abs(math.abs(self.directionChangeDeg) - 90))
    local overshoot = self.workWidth / 2 * math.tan(headlandAngle)
    self:debug('work start node headland angle = %.1f, overshoot = %.1f', math.deg(headlandAngle), overshoot)
    return overshoot
end

--- Set up the turn end node and all related nodes (relative to the turn end node)
function TurnContext:setupTurnEnd(course, turnNodes, turnEndSideOffset)
    -- making sure we have the nodes created, and created only once
    if not turnNodes.turnEndWpNode then
        turnNodes.turnEndWpNode = WaypointNode('turnEnd')
    end
    -- Turn end waypoint node, pointing to the direction after the turn
    turnNodes.turnEndWpNode:setToWaypoint(course, self.turnEndWpIx)
    self.turnEndWpNode = turnNodes.turnEndWpNode

    -- if there's an offset move the turn end node (and all others based on it)
    if turnEndSideOffset and turnEndSideOffset ~= 0 then
        self:debug('Applying %.1f side offset to turn end', turnEndSideOffset)
        local x, y, z = localToWorld(self.turnEndWpNode.node, turnEndSideOffset, 0, 0)
        setTranslation(self.turnEndWpNode.node, x, y, z)
    end

    -- Set up a node where the implement must be lowered when starting to work after the turn maneuver
    if not turnNodes.workStartNode then
        turnNodes.workStartNode = CpUtil.createNode('workStart', 0, 0, 0, turnNodes.turnEndWpNode.node)
    end
    if not turnNodes.lateWorkStartNode then
        -- this is for the headland turns where we want to cover the corner in the inbound direction (before turning)
        -- so we can start working later after the turn
        turnNodes.lateWorkStartNode = CpUtil.createNode('lateWorkStartNode', 0, 0, 0, turnNodes.workStartNode)
    end

    if self:isHeadlandCorner() then
        local overshoot = math.min(self:getOvershootForHeadlandCorner(), self.workWidth * 2)
        -- for headland turns, when we cover the corner in the outbound direction, which is half self.workWidth behind
        -- the turn end node
        setTranslation(turnNodes.workStartNode, 0, 0, - self.workWidth / 2 - overshoot)
        setTranslation(turnNodes.lateWorkStartNode, 0, 0, self.workWidth)
    else
        setTranslation(turnNodes.workStartNode, 0, 0, 0)
        setTranslation(turnNodes.lateWorkStartNode, 0, 0, 0)
    end
    self.workStartNode = turnNodes.workStartNode
    self.lateWorkStartNode = turnNodes.lateWorkStartNode
end

--- Set up the turn end node and all related nodes (relative to the turn end node)
function TurnContext:setupTurnStart(course, turnNodes)
    if not turnNodes.turnStartWpNode then
        turnNodes.turnStartWpNode = WaypointNode('turnStart')
    end
    -- Turn start waypoint node, pointing to the direction of the turn end node
    turnNodes.turnStartWpNode:setToWaypoint(course, self.turnStartWpIx)
    self.turnStartWpNode = turnNodes.turnStartWpNode

    -- Set up a node where the implement must be raised when finishing a row before the turn
    if not turnNodes.workEndNode then
        turnNodes.workEndNode = CpUtil.createNode('workEnd', 0, 0, 0)
    end
    if not turnNodes.lateWorkEndNode then
        -- this is for the headland turns where we want to cover the corner in the inbound direction (before turning)
        turnNodes.lateWorkEndNode = CpUtil.createNode('lateWorkEnd', 0, 0, 0, turnNodes.workEndNode)
    end
    if self:isHeadlandCorner() then
        -- for headland turns (about 45-135 degrees) the turn end node is on the corner but pointing to
        -- the direction after the turn. So create a node at the same location but pointing into the incoming direction
        -- to be used to find out when to raise the implements during a headland turn
        course:setNodeToWaypoint(turnNodes.workEndNode, self.turnEndWpIx)
        -- use the rotation and offset of the waypoint before the turn start to make sure that we continue straight
        -- until the implements are raised
        setRotation(turnNodes.workEndNode, 0, course:getWaypointYRotation(self.turnStartWpIx - 1), 0)
        local x, y, z = course:getOffsetPositionWithOtherWaypointDirection(self.turnEndWpIx, self.turnStartWpIx)
        setTranslation(turnNodes.workEndNode, x, y, z)
        local overshoot = math.min(self:getOvershootForHeadlandCorner(), self.workWidth * 2)
        -- for headland turns, we cover the corner in the outbound direction, so here we can end work when
        -- the implement is half self.workWidth before the turn end node
        x, y, z = localToWorld(turnNodes.workEndNode, 0, 0, - self.workWidth / 2 + overshoot)
        setTranslation(turnNodes.workEndNode, x, y, z)
        setTranslation(turnNodes.lateWorkEndNode, 0, 0, self.workWidth)
    else
        -- For 180 turns, create a node pointing in the incoming direction of the turn start waypoint. This will be used
        -- to determine relative position to the turn start. (the turn start WP can't be used as it is
        -- pointing towards the turn end waypoint which may be anything around 90 degrees)
        -- there's no need for an overshoot as it is being taken care during the course generation
        course:setNodeToWaypoint(turnNodes.workEndNode, self.turnStartWpIx)
        setRotation(turnNodes.workEndNode, 0, course:getWaypointYRotation(self.turnStartWpIx - 1), 0)
        setTranslation(turnNodes.lateWorkEndNode, 0, 0, 0)
    end

    self.workEndNode = turnNodes.workEndNode
    self.lateWorkEndNode = turnNodes.lateWorkEndNode
end

-- node's position in the turn end wp node's coordinate system
function TurnContext:getLocalPositionFromTurnEnd(node)
    return localToLocal(node, self.vehicleAtTurnEndNode, 0, 0, 0)
end

-- node's position in the turn start wp node's coordinate system
function TurnContext:getLocalPositionFromTurnStart(node)
    return localToLocal(node, self.turnStartWpNode.node, 0, 0, 0)
end

-- node's position in the work end node's coordinate system
function TurnContext:getLocalPositionFromWorkEnd(node)
    return localToLocal(node, self.workEndNode, 0, 0, 0)
end

-- turn end wp node's position in node's coordinate system
function TurnContext:getLocalPositionOfTurnEnd(node)
    return localToLocal(self.vehicleAtTurnEndNode, node, 0, 0, 0)
end

function TurnContext:isPointingToTurnEnd(node, thresholdDeg)
    local lx, _, lz = localToLocal(self.turnEndWpNode.node, node, 0, 0, 0)
    return math.abs(math.atan2(lx, lz)) < math.rad(thresholdDeg)
end

---@return number angle (radian) between the row and the headland, 90 degrees means the headland is perpendicular to the row
function TurnContext:getHeadlandAngle()
    print(self.turnEndWp.angle, self.turnStartWp.angle)
    return  math.abs(CpMathUtil.getDeltaAngle(math.rad(self.turnEndWp.angle), math.rad(self.turnStartWp.angle)))
end

function TurnContext:isNextTurnLeft()
    return self.nextTurnLeft
end

function TurnContext:isHeadlandCorner()
	-- in headland turns there's no significant direction change at the turn start waypoint, as the turn end waypoint
	-- marks the actual corner. In a non-headland turn (usually 180) there is about 90 degrees direction change at
	-- both the turn start and end waypoints
    -- a turn is a headland turn only when there is minimal direction change at the turn start and the total direction
    -- change is less than 150 degrees
    -- TODO: consider using course:isHeadlandTurnAtIx() instead as with the current generator, we know the turn type
	return math.abs(CpMathUtil.getDeltaAngle(math.rad(self.turnStartWp.angle), math.rad(self.beforeTurnStartWp.angle))) < (math.pi / 6) and
            math.abs( self.directionChangeDeg ) < 150
end

--- A simple wide turn is where there's no corner to avoid, no headland to follow, there is a straight line on the
--- field between the turn start and end
--- Currently we don't have a really good way to find this out so assume that if the turn end is reasonably close
--- to the turn start, there'll be nothing in our way.
function TurnContext:isSimpleWideTurn(turnDiameter, workWidth)
    return not self:isHeadlandCorner() and
            math.abs(self.dx) > turnDiameter and
            math.abs(self.dx) < workWidth * 2.1 and
            math.abs(self.dz) < workWidth * 2.1
end

function TurnContext:isWideTurn(turnDiameter)
    return not self:isHeadlandCorner() and math.abs(self.dx) > turnDiameter
end

function TurnContext:isPathfinderTurn(turnDiameter, workWidth)
    local d = math.sqrt(self.dx * self.dx + self.dz * self.dz)
    return not self:isSimpleWideTurn(turnDiameter, workWidth) and d > 3 * workWidth
end

function TurnContext:isLeftTurn()
    if self:isHeadlandCorner() then
        local cornerAngle = self:getCornerAngle()
        return cornerAngle > 0
    else
        return self.leftTurn
    end
end

---@return number offset of the turn end in meters forward (>0) or back (<0)
function TurnContext:getTurnEndForwardOffset()
    return self.dz
end

function TurnContext:setTargetNode(node)
    self.targetNode = node
end

--- Returns true if node is pointing approximately in the turn start direction, that is, the direction from
--- turn start waypoint to the turn end waypoint.
function TurnContext:isDirectionCloseToStartDirection(node, thresholdDeg)
    return CpMathUtil.isSameDirection(node, self.turnStartWpNode.node, thresholdDeg)
end

--- Returns true if node is pointing approximately in the turn's ending direction, that is, the direction of the turn
--- end waypoint, the direction the vehicle will continue after the turn
function TurnContext:isDirectionCloseToEndDirection(node, thresholdDeg)
    return CpMathUtil.isSameDirection(node, self.turnEndWpNode.node, thresholdDeg)
end

--- Use to find out if we can make a turn: are we farther away from the next row than our turn radius
--- @param dx number lateral distance from the next row (dx from turn end node)
--- @return boolean True if dx is bigger than r, considering the turn's direction
function TurnContext:isLateralDistanceGreater(dx, r)
    if self:isLeftTurn() then
        -- more than r meters to the left
        return dx > r
    else
        -- more than r meters to the right
        return dx < -r
    end
end

function TurnContext:isLateralDistanceLess(dx, r)
    if self:isLeftTurn() then
        -- less than r meters to the left
        return dx < r
    else
        -- less than r meters to the right
        return dx > -r
    end
end

function TurnContext:getAngleToTurnEndDirection(node)
    local lx, _, lz = localDirectionToLocal(self.turnEndWpNode.node, node, 0, 0, 1)
    -- TODO: check for nan?
    return math.atan2(lx, lz)
end

function TurnContext:isDirectionPerpendicularToTurnEndDirection(node, thresholdDeg)
    local lx, _, lz = localDirectionToLocal(self.turnEndWpNode.node, node, self:isLeftTurn() and -1 or 1, 0, 0)
    return math.abs(math.atan2(lx, lz)) < math.rad(thresholdDeg or 5)
end

function TurnContext:getAverageEndAngleDeg()
    -- use the average angle of the turn end and the next wp as there is often a bend there
    return math.deg(CpMathUtil.getAverageAngle(math.rad(self.turnEndWp.angle), math.rad(self.afterTurnEndWp.angle)))
end

--- @return number the angle to turn in this corner (if the corner is less than 90 degrees, you'll have to turn > 90 degrees)
function TurnContext:getCornerAngle()
    local endAngleDeg = self:getAverageEndAngleDeg()
    local alpha, _ = Corner.getAngles(self.turnStartWp.angle, endAngleDeg)
    return alpha
end

--- @return number the angle to turn in this corner (if the corner is less than 90 degrees, you'll have to turn > 90 degrees)
function TurnContext:getCornerAngleToTurn()
    local endAngleDeg = self:getAverageEndAngleDeg()
    return CpMathUtil.getDeltaAngle(math.rad(endAngleDeg), math.rad(self.turnStartWp.angle))
end

--- Create a corner based on the turn context's start and end waypoints
---@param vehicle table
---@param r number turning radius in m
function TurnContext:createCorner(vehicle, r)
    -- use the average angle of the turn end and the next wp as there is often a bend there
    local endAngleDeg = self:getAverageEndAngleDeg()
    CpUtil.debugVehicle(CpDebug.DBG_TURN, vehicle, 'start angle: %.1f, end angle: %.1f (from %.1f and %.1f)', self.beforeTurnStartWp.angle,
            endAngleDeg, self.turnEndWp.angle, self.afterTurnEndWp.angle)
    return Corner(vehicle, self.beforeTurnStartWp.angle, self.turnStartWp, endAngleDeg, self.turnEndWp, r,
            vehicle:getCpSettings().toolOffsetX:getValue())
end

--- Course to reverse before starting a turn to make sure the turn is completely on the field
--- @param vehicle table
--- @param reverseDistance number distance to reverse in meters
function TurnContext:createReverseWaypointsBeforeStartingTurn(vehicle, reverseDistance)
    local reverserNode = AIUtil.getReverserNode(vehicle)
    local _, _, dStart = localToLocal(reverserNode or vehicle:getAIDirectionNode(), self.workEndNode, 0, 0, 0)
    local waypoints = {}
    for d = dStart, dStart - reverseDistance - 1, -1 do
        local x, y, z = localToWorld(self.workEndNode, 0, 0, d)
        table.insert(waypoints, {x = x, y = y, z = z, rev = true})
    end
    return waypoints
end

--- Course to end a pathfinder turn, a straight line from where pathfinder ended, into to next row,
--- making sure it is long enough so the vehicle reaches the point to lower the implements on this course
---@param course Course pathfinding course to append the ending course to
---@param extraLength number add so many meters to the calculated course (for example to allow towed implements to align
--- before reversing)
---@return number length added to the course in meters
function TurnContext:appendEndingTurnCourse(course, extraLength)
    -- make sure course reaches the front marker node so end it well behind that node
    local _, _, dzFrontMarker = course:getWaypointLocalPosition(self.vehicleAtTurnEndNode, course:getNumberOfWaypoints())
    local _, _, dzWorkStart = course:getWaypointLocalPosition(self.workStartNode, course:getNumberOfWaypoints())
    local waypoints = {}
    -- A line between the front marker and the work start node, regardless of which one is first
    local startNode = dzFrontMarker < dzWorkStart and self.vehicleAtTurnEndNode or self.workStartNode
    -- make sure course is long enough that the back marker reaches the work start
    local lenToBackMarker = self.frontMarkerDistance - self.backMarkerDistance
	-- extra length at the end to allow for alignment
	extraLength = extraLength and (extraLength + lenToBackMarker) or lenToBackMarker
    -- +1 so the first waypoint of the appended line won't overlap with the last wp of course
    self:debug('appendEndingTurnCourse: dzVehicleAtTurnEnd: %.1f, dzWorkStart: %.1f, extra %.1f)',
            dzFrontMarker, dzWorkStart, extraLength)
    for d = math.min(dzFrontMarker, dzWorkStart) + 1, extraLength, 1 do
        local x, y, z = localToWorld(startNode, 0, 0, d)
        table.insert(waypoints, {x = x, y = y, z = z})
    end
    local oldLength = course:getLength()
    course:appendWaypoints(waypoints)
    return course:getLength() - oldLength
end


--- Course to finish a row before the turn, just straight ahead, ignoring the corner
---@return Course
function TurnContext:createFinishingRowCourse(vehicle)
    local waypoints = {}
    -- must be at least as long as the back marker distance so we are not reaching the end of the course before
    -- the implement reaches the field edge (a negative backMarkerDistance means the implement is behind the
    -- vehicle, this isn't a problem for a positive backMarkerDistance as the implement reaches the field edge
    -- before the vehicle (except for very wide work widths of course, so make sure we have enough course to cross
    -- the headland)
    -- (back marker is the worst case, for when the raise implement is set to 'late'. If it is set to 'early',
    -- the front marker distance would be here relevant but this is only for creating the course, where the vehicle will
    -- stop finishing the row and start the turn depends only on the raise implement setting.
    for d = 0, math.max(self.workWidth * 1.5, -self.backMarkerDistance * 1.5), 1 do
        local x, _, z = localToWorld(self.workEndNode, 0, 0, d)
        table.insert(waypoints, {x = x, z = z})
    end
    return Course(vehicle, waypoints, true)
end

--- How much space we have from node to the field edge (in the direction of the node)?
---@return number
function TurnContext:getDistanceToFieldEdge(node)
    for d = 0, 100, 1 do
        local x, _, z = localToWorld(node, 0, 0, d)
        local isField = CpFieldUtil.isOnField(x, z)
        if d == 0 and not isField then
            self:debug('Vehicle not on field, search backwards')
            for db = 0, 50, 1 do
                x, _, z = localToWorld(node, 0, 0, -db)
                isField = CpFieldUtil.isOnField(x, z)
                if isField then
                    self:debug('Field edge is at %d m (behind us)', -db)
                    return -db
                end
            end
            self:debug('Field edge not found (vehicle not on field)')
            return nil
        end
        if not isField then
            self:debug('Field edge is at %d m (in front of us)', d)
            return d
        end
    end
    -- edge not found
    self:debug('Field edge more than 100 m away')
    return math.huge
end

--- Assuming a vehicle just finished a row, provide parameters for calculating a path to the start
--- of the next row, making sure that the vehicle and the implement arrives there aligned with the row direction
---@return number, number the node where the turn ends, z offset to use with the end node
function TurnContext:getTurnEndNodeAndOffsets(steeringLength)
    local turnEndNode, goalOffset
    if self.frontMarkerDistance > 0 then
        -- implement in front of vehicle. Turn should end with the implement at the work start position, this is where
        -- the vehicle's root node is on the vehicleAtTurnEndNode
        turnEndNode = self.vehicleAtTurnEndNode
        goalOffset = 0
    else
        -- implement behind vehicle. Since we are turning, we want to be aligned with the next row with our vehicle
        -- on the work start node so by the time the implement reaches it, it is also aligned
        turnEndNode = self.workStartNode
        -- vehicle is about frontMarkerDistance before the work end when finishing the turn
        if steeringLength > 0 then
            -- giving enough time for the implement to align, the vehicle will reach the next row about the
            -- front marker distance _before_ the turn end so have the front marker distance to drive straight,
            -- during this time we expect the implement to align with the tractor
            -- TODO: this isn't exact science here, as the distance we need to straighten out the implement is rather
            -- a function of the radius, the starting angle and probably the tow bar length.
            goalOffset = - self.turnEndForwardOffset
        else
            -- no towed implement (mounted on vehicle), no need to align, place the vehicle exactly at the work start
            -- as also with 3 point mounted implements, the tractor needs some time to align with the row direction
            goalOffset = self.frontMarkerDistance + self.turnEndForwardOffset
        end
    end
    return turnEndNode, goalOffset
end

---@return string|nil id of the boundary for this turn
function TurnContext:getBoundaryId()
    return self.turnEndAtBoundaryId
end

function TurnContext:debug(...)
    CpUtil.debugVehicle(self.debugChannel, self.vehicle, 'Turn context: ' .. string.format(...))
end

function TurnContext:drawDebug()
    if CpDebug:isChannelActive(self.debugChannel) then
        local cx, cy, cz
        local nx, ny, nz
        local height = 1
        if self.workStartNode then
            cx, cy, cz = localToWorld(self.workStartNode, -self.workWidth / 2, 0, 0)
            nx, ny, nz = localToWorld(self.workStartNode, self.workWidth / 2, 0, 0)
            DebugUtil.drawDebugLine(cx, cy + height, cz, nx, ny + height, nz, 0, 1, 0)
            DebugUtil.drawDebugNode(self.workStartNode, 'work start')
        end
        if self.lateWorkStartNode then
            cx, cy, cz = localToWorld(self.lateWorkStartNode, -self.workWidth / 2, 0, 0)
            nx, ny, nz = localToWorld(self.lateWorkStartNode, self.workWidth / 2, 0, 0)
			DebugUtil.drawDebugLine(cx, cy + height, cz, nx, ny + height, nz, 0, 0.5, 0)
        end
        if self.workEndNode then
            cx, cy, cz = localToWorld(self.workEndNode, -self.workWidth / 2, 0, 0)
            nx, ny, nz = localToWorld(self.workEndNode, self.workWidth / 2, 0, 0)
			DebugUtil.drawDebugLine(cx, cy + height, cz, nx, ny + height, nz, 1, 0, 0)
            DebugUtil.drawDebugNode(self.workEndNode, 'work end')
        end
        if self.lateWorkEndNode then
            cx, cy, cz = localToWorld(self.lateWorkEndNode, -self.workWidth / 2, 0, 0)
            nx, ny, nz = localToWorld(self.lateWorkEndNode, self.workWidth / 2, 0, 0)
			DebugUtil.drawDebugLine(cx, cy + height, cz, nx, ny + height, nz, 0.5, 0, 0)
        end
        if self.vehicleAtTurnEndNode then
            cx, cy, cz = localToWorld(self.vehicleAtTurnEndNode, 0, 0, 0)
			DebugUtil.drawDebugLine(cx, cy, cz, cx, cy + 2, cz, 1, 1, 0)
            DebugUtil.drawDebugNode(self.vehicleAtTurnEndNode, 'vehicle\nat turn end')
        end
        if self.vehicleAtTurnStartNode then
            DebugUtil.drawDebugNode(self.vehicleAtTurnStartNode, 'vehicle\nat turn start')
        end
    end
end

--- A special turn context for the row start/finish turn (up/down <-> headland transition). All this does
--- is making sure the implements are raised/lowered properly when finishing or starting a row
---@class RowStartOrFinishContext : TurnContext
RowStartOrFinishContext = CpObject(TurnContext)

--- Force the 180 turn behavior so the row start/finishing course is created properly. Without this
--- it would calculate a transition to the headland or up/down rows as a headland turn as such transitions are always
--- less then 180 and then the row finishing course would be offset
function RowStartOrFinishContext:isHeadlandCorner()
    return false
end
