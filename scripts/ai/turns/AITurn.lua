--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2019 - 2023 Courseplay Dev Team

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

--[[

All turns have three phases:

1. Finishing Row

Keep driving until it is time to raise the implements.

2. Turn

The actual turn maneuver starts at the moment when the implements are raised. The turn maneuver can be dynamically
controlled based on the vehicle's current position or follow a calculated course. Not all turns can be run dynamically,
and this also has to be enabled by the vehicle.cp.settings.useAiTurns.

Turn courses are calculated by the code in turn.lua (which historically also did the driving) and passed on the
PPC to follow.

3. Ending Turn

In this phase we put the vehicle on a path to align with the course following the turn and initiate the lowering
of implements when needed. From this point on, control is passed back to the AIDriver.

]]

---@class AITurn
AITurn = CpObject()
AITurn.debugChannel = CpDebug.DBG_TURN

---@field ppc PurePursuitController
---@field turnContext TurnContext
function AITurn:init(vehicle, driveStrategy, ppc, proximityController, turnContext, workWidth, name)
    self:addState('INITIALIZING')
    self:addState('FINISHING_ROW')
    self:addState('TURNING')
    self:addState('ENDING_TURN')
    self:addState('REVERSING_AFTER_BLOCKED')
    self:addState('WAITING_FOR_PATHFINDER')
    self.vehicle = vehicle
    self.settings = vehicle:getCpSettings()
    self.turningRadius = AIUtil.getTurningRadius(self.vehicle)
    ---@type PurePursuitController
    self.ppc = ppc
    self.workWidth = workWidth
    ---@type AIDriveStrategyFieldWorkCourse
    self.driveStrategy = driveStrategy
    ---@type ProximityController
    self.proximityController = proximityController
    self.proximityController:registerBlockingObjectListener(self, AITurn.onBlocked)
    -- turn handles its own waypoint changes
    self.ppc:registerListeners(self, 'onWaypointPassed', 'onWaypointChange')
    ---@type TurnContext
    self.turnContext = turnContext
    self.reversingImplement, self.steeringLength = AIUtil.getSteeringParameters(self.vehicle)
    self.state = self.states.INITIALIZING
    self.name = name or 'AITurn'
    self.blocked = false
end

function AITurn:addState(state)
    if not self.states then
        self.states = {}
    end
    self.states[state] = { name = state }
end

function AITurn:debug(...)
    CpUtil.debugVehicle(self.debugChannel, self.vehicle, self.name .. ' state: ' .. self.state.name .. ' ' .. string.format(...))
end

--- Register a function to call when the turn ends. If no function is registered, calls
--- self.driveStrategy:resumeFieldworkAfterTurn() by default
---@param callbackObject table default is
---@param callbackFunction function(object: table, ix) where ix is the index of the turn end waypoint. Default is
function AITurn:registerTurnEndCallback(callbackObject, callbackFunction)
    self.callbackObject = callbackObject
    self.callbackFunction = callbackFunction
end

--- Start the actual turn maneuver after the row is finished
function AITurn:startTurn()
    -- implement in derived classes
    -- self.vehicle:raiseAIEvent("onAIFieldWorkerStartTurn", "onAIImplementStartTurn", self.turnContext:isLeftTurn(), turnStrategy)
end

--- Stuff we need to do during the turn no matter what turn type we are using
function AITurn:turn()
    return nil, nil, nil, self:getForwardSpeed()
end

function AITurn:startRecoveryTurn(...)
    -- clean up before giving back the control to the drive strategy
    -- unregister here before the AITurn object is destructed
    self.proximityController:unregisterBlockingObjectListener()
    -- restore onWaypoint* listeners before giving back control to the drive strategy, otherwise they'll be lost
    -- when the recovery turn is instantiated and registers its own listeners
    self.ppc:restorePreviouslyRegisteredListeners()
    self.driveStrategy:startRecoveryTurn(...)
end

function AITurn:onBlocked()
    self:startRecoveryTurn(1 * self.turningRadius)
end

function AITurn:onWaypointChange(ix)
    self:debug('onWaypointChange %d', ix)
    if self.driveStrategy and self.driveStrategy.isWorking and self.driveStrategy:isWorking() then
        -- make sure to set the proper X offset if applicable (for turning plows for example)
        self.driveStrategy:setOffsetX()
    end
end

function AITurn:onWaypointPassed(ix, course)
    self:debug('onWaypointPassed %d', ix)
    if ix == course:getNumberOfWaypoints() and self.state == self.states.ENDING_TURN then
        self:debug('Last waypoint reached, resuming fieldwork')
        self:resumeFieldworkAfterTurn(self.turnContext.turnEndWpIx)
    end
end

--- Is a K turn allowed.
---@param vehicle table
---@param turnContext TurnContext
---@param workWidth number
---@param turnOnField boolean is turn on field allowed
---@return boolean
function AITurn.canMakeKTurn(vehicle, turnContext, workWidth, turnOnField)
    if turnContext:isHeadlandCorner() then
        CpUtil.debugVehicle(AITurn.debugChannel, vehicle, 'Headland turn, not doing a 3 point turn.')
        return false
    end
    local turningRadius = AIUtil.getTurningRadius(vehicle)
    if math.abs(turnContext.dx) > 2 * turningRadius then
        CpUtil.debugVehicle(AITurn.debugChannel, vehicle, 'Next row is too far (%.1f, turning radius is %.1f), no 3 point turn',
                turnContext.dx, turningRadius)
        return false
    end
    if not AIVehicleUtil.getAttachedImplementsAllowTurnBackward(vehicle) then
        CpUtil.debugVehicle(AITurn.debugChannel, vehicle, 'Not all attached implements allow for reversing, use generated course turn')
        return false
    end
    if SpecializationUtil.hasSpecialization(ArticulatedAxis, vehicle.specializations) then
        CpUtil.debugVehicle(AITurn.debugChannel, vehicle, 'Has articulated axis, use generated course turn')
        return false
    end
    local reversingImplement, _ = AIUtil.getSteeringParameters(vehicle)
    if reversingImplement then
        CpUtil.debugVehicle(AITurn.debugChannel, vehicle, 'Have a towed implement, use generated course turn')
        return false
    end

    if turnOnField and
            not AITurn.canTurnOnField(turnContext, vehicle, workWidth, turningRadius) then
        CpUtil.debugVehicle(AITurn.debugChannel, vehicle, 'Turn on field is on but there is not enough room to stay on field with a 3 point turn')
        return false
    end
    CpUtil.debugVehicle(AITurn.debugChannel, vehicle, 'Can make a 3 point turn')
    return true
end

---@param turnContext TurnContext
---@return boolean, number True if there's enough space to make a forward turn on the field. Also return the
---distance to reverse in order to be able to just make the turn on the field
function AITurn.canTurnOnField(turnContext, vehicle, workWidth, turningRadius)
    local spaceNeededOnFieldForTurn = turningRadius + workWidth / 2
    local distanceToFieldEdge = turnContext:getDistanceToFieldEdge(turnContext.vehicleAtTurnStartNode)
    CpUtil.debugVehicle(AITurn.debugChannel, vehicle, 'Space needed to turn on field %.1f m', spaceNeededOnFieldForTurn)
    if distanceToFieldEdge then
        return (distanceToFieldEdge > spaceNeededOnFieldForTurn), spaceNeededOnFieldForTurn - distanceToFieldEdge
    else
        return false, 0
    end
end

function AITurn:getForwardSpeed()
    return self.settings.turnSpeed:getValue()
end

function AITurn:getReverseSpeed()
    return self.settings.reverseSpeed:getValue()
end

function AITurn:isForwardOnly()
    return false
end

function AITurn:isFinishingRow()
    return self.state == self.states.FINISHING_ROW
end

function AITurn:isEndingTurn()
    -- include the direction too because some turns go to the ENDING_TURN state very early, while still driving
    -- perpendicular to the row. This way this returns true really only when we are about to end the turn
    return self.state == self.states.ENDING_TURN and self.turnContext:isDirectionCloseToEndDirection(self.vehicle:getAIDirectionNode(), 15)
end

-- get a virtual goal point position for a turn performed with full steering angle to the left or right (or straight)
---@param moveForwards boolean move forward when true, backwards otherwise
---@param isLeftTurn boolean turn to the right or left, or straight when nil
function AITurn:getGoalPointForTurn(moveForwards, isLeftTurn)
    local dx, dz
    if isLeftTurn == nil then
        dx = 0
        dz = moveForwards and self.ppc:getLookaheadDistance() or -self.ppc:getLookaheadDistance()
    else
        dx = isLeftTurn and self.ppc:getLookaheadDistance() or -self.ppc:getLookaheadDistance()
        dz = moveForwards and 1 or -1
    end
    local gx, _, gz = localToWorld(self.vehicle:getAIDirectionNode(), dx, 0, dz)
    return gx, gz
end

function AITurn:getDriveData(dt)
    local maxSpeed = self:getForwardSpeed()
    local gx, gz, moveForwards
    if self.state == self.states.INITIALIZING then
        local rowFinishingCourse = self.turnContext:createFinishingRowCourse(self.vehicle)
        self.ppc:setCourse(rowFinishingCourse)
        self.ppc:initialize(1)
        self.state = self.states.FINISHING_ROW
        -- Finishing the current row
    elseif self.state == self.states.FINISHING_ROW then
        self:finishRow(dt)
    elseif self.state == self.states.ENDING_TURN then
        -- Ending the turn (starting next row)
        local allowedToDrive = self:endTurn(dt)
        if not allowedToDrive then
            maxSpeed = 0
        end
    elseif self.state == self.states.WAITING_FOR_PATHFINDER then
        maxSpeed = 0
    else
        -- Performing the actual turn
        gx, gz, moveForwards, maxSpeed = self:turn(dt)
    end
    return gx, gz, moveForwards, maxSpeed
end

-- default for 180 turns: we need to raise the implement (when finishing a row) when we reach the
-- workEndNode.
function AITurn:getRaiseImplementNode()
    return self.turnContext.workEndNode
end

function AITurn:finishRow(dt)
    -- keep driving straight until we need to raise our implements
    if self.driveStrategy:shouldRaiseImplements(self:getRaiseImplementNode()) then
        self.driveStrategy:raiseImplements()
        self.driveStrategy:raiseControllerEvent(AIDriveStrategyCourse.onFinishRowEvent, self.turnContext:isHeadlandCorner())
        self:debug('Row finished, starting turn.')
        self:startTurn()
    end
end

---@return boolean true if it is ok the continue driving, false when the vehicle should stop
function AITurn:endTurn(dt)
    -- keep driving on the turn ending temporary course until we need to lower our implements
    -- check implements only if we are more or less in the right direction (next row's direction)
    if self.turnContext:isDirectionCloseToEndDirection(self.vehicle:getAIDirectionNode(), 30) and
            self.driveStrategy:shouldLowerImplements(self.turnContext.turnEndWpNode.node, false) then
        self:debug('Turn ended, resume fieldwork')
        self:resumeFieldworkAfterTurn(self.turnContext.turnEndWpIx)
    end
    return true
end

--- Give back control the the drive strategy
function AITurn:resumeFieldworkAfterTurn(ix)
    -- just in case, raise this event so plows are rotated to the working position. Should really never end up
    -- here though, as the course should be long enough for the normal turn end processing to be triggered.
    self.driveStrategy:raiseControllerEvent(AIDriveStrategyCourse.onTurnEndProgressEvent,
            self.turnContext.workStartNode, self.ppc:isReversing(), true, self.turnContext:isLeftTurn())

    if self.proximityController then
        self.proximityController:unregisterBlockingObjectListener()
    end
    -- restore the strategies' listeners
    self.ppc:restorePreviouslyRegisteredListeners()
    if self.callbackFunction and self.callbackObject then
        self:debug('Triggering turn end callback function')
        self.callbackFunction(self.callbackObject, ix)
    else
        self.driveStrategy:resumeFieldworkAfterTurn(ix)
    end
end

function AITurn:drawDebug()
end

--[[
A K (3 point) turn to make a 180 to continue on the next row. This is a hybrid maneuver, starting with
the forward (and reverse if there's not enough room) leg, then using a course leading into the next row
in the turn end phase.
]]

---@class KTurn : AITurn
KTurn = CpObject(AITurn)

function KTurn:init(vehicle, strategy, ppc, proximityController, turnContext, workWidth)
    AITurn.init(self, vehicle, strategy, ppc, proximityController, turnContext, workWidth, 'KTurn')
    self:addState('FORWARD')
    self:addState('REVERSE')
    self:addState('FORWARD_ARC')
end

function KTurn:onWaypointChange(ix)
    -- ending part of the K turn is driving on the course end, so revert to the default
    if self.state == self.states.ENDING_TURN then
        AITurn.onWaypointChange(self, ix)
    end
end

function KTurn:onWaypointPassed(ix, course)
    -- ending part of the K turn is driving on the course end, so revert to the default
    if self.state == self.states.ENDING_TURN then
        AITurn.onWaypointPassed(self, ix, course)
    end
end

function KTurn:startTurn()
    AITurn.startTurn(self)
    self.state = self.states.FORWARD
end

function KTurn:turn(dt)
    -- we end the K turn with a temporary course leading straight into the next row. During this turn the
    -- AI driver's state remains TURNING and thus calls AITurn:drive() which wil take care of raising the implements
    local endTurn = function(course)
        self.state = self.states.ENDING_TURN
        self.ppc:setCourse(course)
        self.ppc:initialize(1)
    end

    local gx, gz, maxSpeed, moveForwards
    if self.state == self.states.FORWARD then
        local dx, _, dz = self.turnContext:getLocalPositionFromTurnEnd(self.vehicle:getAIDirectionNode())
        maxSpeed = self:getForwardSpeed()
        moveForwards = true
        if dz > -math.max(0, math.max(2, self.turnContext.frontMarkerDistance)) then
            -- drive straight until we are beyond the turn end (or, if the implement is mounted on the front,
            -- make sure we end up at least 2 meters before the row start to have time to straighten out, so there
            -- is no fruit missed)
            gx, gz = self:getGoalPointForTurn(moveForwards, nil)
        elseif not self.turnContext:isDirectionPerpendicularToTurnEndDirection(self.vehicle:getAIDirectionNode()) then
            -- full turn towards the turn end waypoint
            gx, gz = self:getGoalPointForTurn(moveForwards, self.turnContext:isLeftTurn())
        else
            -- drive straight ahead until we cross turn end line
            gx, gz = self:getGoalPointForTurn(moveForwards, nil)
            if self.turnContext:isLateralDistanceGreater(dx, self.turningRadius * 1.05) then
                -- no need to reverse from here, we can make the turn
                self.endingTurnCourse = TurnEndingManeuver(self.vehicle, self.turnContext,
                        self.vehicle:getAIDirectionNode(), self.turningRadius, self.workWidth, 0):getCourse()
                self:debug('K Turn: dx = %.1f, r = %.1f, no need to reverse.', dx, self.turningRadius)
                endTurn(self.endingTurnCourse)
            else
                -- reverse until we can make turn to the turn end point
                self.vehicle:raiseAIEvent("onAIFieldWorkerTurnProgress", "onAIImplementTurnProgress", 0.5, self.turnContext:isLeftTurn())
                self:debug('Turn progress 50')
                self.state = self.states.REVERSE
                self.endingTurnCourse = TurnEndingManeuver(self.vehicle, self.turnContext,
                        self.vehicle:getAIDirectionNode(), self.turningRadius, self.workWidth, 0):getCourse()
                self:debug('K Turn: dx = %.1f, r = %.1f, reversing now.', dx, self.turningRadius)
            end
        end
    elseif self.state == self.states.REVERSE then
        -- reversing parallel to the direction between the turn start and turn end waypoints
        moveForwards = false
        maxSpeed = self:getReverseSpeed()
        gx, gz = self:getGoalPointForTurn(moveForwards, nil)
        local _, _, dz = self.endingTurnCourse:getWaypointLocalPosition(self.vehicle:getAIDirectionNode(), 1)
        if dz > 0 then
            -- we can make the turn from here
            self:debug('K Turn ending turn')
            endTurn(self.endingTurnCourse)
        end
    end
    return gx, gz, moveForwards, maxSpeed
end

--[[
  Headland turn for combines:
  1. drive forward to the field edge or the headland path edge
  2. start turning forward
  3. reverse straight and then align with the direction after the
     corner while reversing
  4. forward to the turn start to continue on headland
]]
---@class CombineHeadlandTurn : AITurn
CombineHeadlandTurn = CpObject(AITurn)

---@param driveStrategy AIDriveStrategyFieldWorkCourse
---@param turnContext TurnContext
function CombineHeadlandTurn:init(vehicle, driveStrategy, ppc, proximityController, turnContext)
    AITurn.init(self, vehicle, driveStrategy, ppc, proximityController, turnContext, 'CombineHeadlandTurn')
    self:addState('FORWARD')
    self:addState('REVERSE_STRAIGHT')
    self:addState('REVERSE_ARC')
    self.turningRadius = AIUtil.getTurningRadius(self.vehicle)
    self.cornerAngleToTurn = turnContext:getCornerAngleToTurn()
    -- half the turn angle but not less than 45
    self.angleToTurnInReverse = math.max(math.pi / 4, math.abs(self.cornerAngleToTurn / 2))
    self.dxToStartReverseTurn = self.turningRadius - math.abs(self.turningRadius - self.turningRadius * math.cos(self.cornerAngleToTurn))
end

function CombineHeadlandTurn:startTurn()
    self.state = self.states.FORWARD
    self:debug('Starting combine headland turn')
end

function CombineHeadlandTurn:onWaypointChange(ix, course)
    -- nothing to do
end

function CombineHeadlandTurn:onWaypointPassed(ix, course)
    -- nothing to do, especially because the row finishing course is still active in the PPC and we may
    -- pass the last waypoint which causes the turn to end and return to field work
end

-- in a combine headland turn we want to raise the header after it reached the field edge (or headland edge on an inner
-- headland.
function CombineHeadlandTurn:getRaiseImplementNode()
    return self.turnContext.lateWorkEndNode
end

function CombineHeadlandTurn:turn(dt)
    local gx, gz, moveForwards, maxSpeed = AITurn.turn(self)
    local dx, _, dz = self.turnContext:getLocalPositionFromTurnEnd(self.vehicle:getAIDirectionNode())
    local angleToTurnEnd = math.abs(self.turnContext:getAngleToTurnEndDirection(self.vehicle:getAIDirectionNode()))
    if self.state == self.states.FORWARD then
        maxSpeed = self:getForwardSpeed()
        moveForwards = true
        if angleToTurnEnd > self.angleToTurnInReverse then
            --and not self.turnContext:isLateralDistanceLess(dx, self.dxToStartReverseTurn) then
            -- full turn towards the turn end direction
            gx, gz = self:getGoalPointForTurn(moveForwards, self.turnContext:isLeftTurn())
        else
            -- reverse until we can make turn to the turn end point
            self.state = self.states.REVERSE_STRAIGHT
            self:debug('Combine headland turn start reversing straight')
        end

    elseif self.state == self.states.REVERSE_STRAIGHT then
        maxSpeed = self:getReverseSpeed()
        moveForwards = false
        gx, gz = self:getGoalPointForTurn(moveForwards, nil)
        if dx < 0.2 then
            self.state = self.states.REVERSE_ARC
            self:debug('Combine headland turn start reversing arc')
        end

    elseif self.state == self.states.REVERSE_ARC then
        maxSpeed = self:getReverseSpeed()
        moveForwards = false
        gx, gz = self:getGoalPointForTurn(moveForwards, not self.turnContext:isLeftTurn())
        if angleToTurnEnd < math.rad(20) then
            self.state = self.states.ENDING_TURN
            self:debug('Combine headland turn forwarding again')
            -- lower implements here unconditionally (regardless of the direction, self:endTurn() would wait until we
            -- are pointing to the turn target direction)
            self.driveStrategy:lowerImplements()
            self:resumeFieldworkAfterTurn(self.turnContext.turnEndWpIx)
        end
    end
    return gx, gz, moveForwards, maxSpeed
end

--[[
A turn maneuver following a course (waypoints created by turn.lua)
]]

---@class CourseTurn : AITurn
CourseTurn = CpObject(AITurn)
---@param fieldWorkCourse Course needed only when generating a pathfinder turn, this is where it gets the headland
function CourseTurn:init(vehicle, driveStrategy, ppc, proximityController, turnContext, fieldWorkCourse, workWidth, name)
    AITurn.init(self, vehicle, driveStrategy, ppc, proximityController, turnContext, workWidth, name or 'CourseTurn')

    self.forceTightTurnOffset = false
    self.enableTightTurnOffset = false
    self.fieldWorkCourse = fieldWorkCourse
end

function CourseTurn:getForwardSpeed()
    if self.turnCourse then
        local currentWpIx = self.turnCourse:getCurrentWaypointIx()
        if self.turnCourse:getDistanceFromFirstWaypoint(currentWpIx) > 10 and
                -- TODO: Instead of a fixed value for DistanceToLastWaypoint, consider the radius of the waypoints to calculate the maximum speed.
                self.turnCourse:getDistanceToLastWaypoint(currentWpIx) > 20 then
            -- in the middle of a long turn maneuver we can drive faster...
            return self.settings.fieldSpeed:getValue()
        else
            return AITurn.getForwardSpeed(self)
        end
    end
    return AITurn.getForwardSpeed(self)
end

-- this turn starts when the vehicle reached the point where the implements are raised.
-- Types of Turns
--
-- 1. 3 point (K) turn (forward)
--    This turn does not use a course, instead it drives by steering only, first forward (left or right),
--    then straight backwards, and then forward again (left or right)
--
-- 2. Calculated turn
--    This is using a precalculated curve to get from the turn start to the turn end. Calculation is based on
--    the geometry only, it does not take obstacles or fruit in account. We use two different algorithms to
--    calculate the path: Dubins (forward only) and Reeds-Shepp (forward or reverse).
--
-- 3. Pathfinder turn
--    We use the hybrid A* pathfinding algorithm to generate the path between the turn start and turn end. This
--    algorithm can avoid collisions and fruit. There are two variations:
--    a) free pathfinding from turn start to end, where the path is determined only by obstacles and fruit on the field
--    b) drive as much as possible on the outermost headland between turn start and end
--
-- Which 180° turn we use when (headland turns are different):
--
-- * First, we check if we can make a 3 point turn (canMakeKTurn()):
--   - the lateral distance to the next row is less than the turn diameter
--   - can reverse with the attached implements (nothing towed allowed here)
--   - not an articulated axis vehicle (we can't yet reverse correctly with those)
--   - there's enough room on the field to make the turn, that is, turning radius + half work width
--
-- * If there is no 3 point turn possible, then:
--   - if the turn end is very far and there are headlands, we always use the pathfinder to find a way
--     to the turn end through the outermost headland
--   - if there's enough room to turn on the field:
--      = if pathfinder turns are enabled in the settings, use the pathfinder to generate the turn path
--      = otherwise, use a calculated turn
--   - if there's not enough room to turn on the field (no or not enough headlands):
--      = if turn on field setting is on, always use calculated turns
--      = if turn on field setting is off, use pathfinder turns if enabled in settings, calculated turns otherwise
--
function CourseTurn:startTurn()
    AITurn.startTurn(self)
    local canTurnOnField = AITurn.canTurnOnField(self.turnContext, self.vehicle, self.workWidth, self.turningRadius)
    if self.turnContext:isHeadlandCorner() then
        self:debug('Starting a headland corner turn')
        self:generateCalculatedTurn()
        self.state = self.states.TURNING
    elseif self.turnContext:isPathfinderTurn(2 * self.turningRadius, self.workWidth) then
        self:debug('Starting a pathfinder turn on headland')
        self:generatePathfinderTurn(true)
    elseif canTurnOnField then
        if self.settings.allowPathfinderTurns:getValue() then
            self:debug('Starting a pathfinder turn: plenty of room on field to turn and pathfinder turns are enabled')
            self:generatePathfinderTurn(false)
        else
            self:debug('Starting a calculated turn: plenty of room on field to turn and pathfinder turns are disabled')
            self:generateCalculatedTurn()
            self.state = self.states.TURNING
        end
    else
        if self.driveStrategy:isTurnOnFieldActive() then
            self:debug('Starting a calculated turn: not enough room on field to turn but turn on field is on, can not use pathfinder turn, even if it is enabled')
            self:generateCalculatedTurn()
            self.state = self.states.TURNING
        elseif not self.settings.allowPathfinderTurns:getValue() then
            self:debug('Starting a calculated turn: not enough room on field to turn but turn on field is off and pathfinder turns are disabled')
            self:generateCalculatedTurn()
            self.state = self.states.TURNING
        else
            self:debug('Starting a pathfinder turn: not enough room on field to turn, turn on field is off, and pathfinder turns are enabled')
            self:generatePathfinderTurn(false)
        end
    end
    if self.state == self.states.TURNING then
        self.ppc:setCourse(self.turnCourse)
        self.ppc:initialize(1)
    end
end

function CourseTurn:isForwardOnly()
    return self.turnCourse and self.turnCourse:isForwardOnly()
end

function CourseTurn:getCourse()
    return self.turnCourse
end

function CourseTurn:turn()

    local gx, gz, moveForwards, maxSpeed = AITurn.turn(self)

    self:changeDirectionWhenAligned()
    self:changeToFwdWhenWaypointReached()

    if TurnManeuver.hasTurnControl(self.turnCourse, self.turnCourse:getCurrentWaypointIx(),
            TurnManeuver.LOWER_IMPLEMENT_AT_TURN_END) then
        self.state = self.states.ENDING_TURN
        self:debug('About to end turn')
    end
    return gx, gz, moveForwards, maxSpeed
end

---@return boolean true if it is ok the continue driving, false when the vehicle should stop
function CourseTurn:endTurn(dt)
    -- keep driving on the turn course until we need to lower our implements
    local shouldLower, dz = self.driveStrategy:shouldLowerImplements(self.turnContext.workStartNode, self.ppc:isReversing())
    self.driveStrategy:raiseControllerEvent(AIDriveStrategyCourse.onTurnEndProgressEvent,
            self.turnContext.workStartNode, self.ppc:isReversing(), shouldLower, self.turnContext:isLeftTurn())
    if shouldLower then
        if not self.implementsLowered then
            -- have not started lowering implements yet
            self:debug('Turn ending, lowering implements')
            self.driveStrategy:lowerImplements()
            self.implementsLowered = true
            if self.ppc:isReversing() then
                -- when ending a turn in reverse, don't drive the rest of the course, switch right back to fieldwork
                self:resumeFieldworkAfterTurn(self.turnContext.turnEndWpIx)
            end
        else
            -- implements already lowering, making sure we check if they are lowered, the faster we go, the earlier,
            -- for those people who set insanely high turn speeds...
            local implementCheckDistance = math.max(1, 0.1 * self.vehicle:getLastSpeed())
            if dz and dz > -implementCheckDistance then
                if self.driveStrategy:getCanContinueWork() then
                    self:debug("implements lowered, resume fieldwork")
                    self:resumeFieldworkAfterTurn(self.turnContext.turnEndWpIx)
                else
                    self:debug('waiting for lower at dz=%.1f', dz)
                    -- we are almost at the start of the row but still not lowered everything,
                    -- hold.
                    return false
                end
            end
        end
    end
    return true
end

function CourseTurn:onWaypointChange(ix)
    AITurn.onWaypointChange(self, ix)
    if self.turnCourse then
        if self.forceTightTurnOffset or (self.enableTightTurnOffset and self.turnCourse:useTightTurnOffset(ix)) then
            -- adjust the course a bit to the outside in a curve to keep a towed implement on the course
            self.tightTurnOffset = AIUtil.calculateTightTurnOffsetForTurnManeuver(self.vehicle, self.steeringLength,
                    self.turnCourse, self.turnCourse:getCurrentWaypointIx(), self.tightTurnOffset)
            self.turnCourse:setOffset(self.tightTurnOffset, 0)
        else
            -- reset offset to 0 if tight turn offset is not on
            self.tightTurnOffset = 0
            self.turnCourse:setOffset(0, 0)
        end
    end
end

--- When switching direction during a turn, especially when switching to reverse we want to make sure
--- that a towed implement is aligned with the reverse direction (already straight behind the tractor when
--- starting to reverse). Turn courses are generated with a very long alignment section to allow for this with
--- the changeDirectionWhenAligned property set, indicating that we don't have to travel along the path, we can
--- change direction as soon as the implement is aligned.
--- So check that here and force a direction change when possible.
function CourseTurn:changeDirectionWhenAligned()
    if self.ppc:getLastPassedWaypointIx() and
            TurnManeuver.hasTurnControl(self.turnCourse, self.ppc:getLastPassedWaypointIx(),
                    TurnManeuver.CHANGE_DIRECTION_WHEN_ALIGNED) then
        local aligned = self.driveStrategy:areAllImplementsAligned(self.turnContext.turnEndWpNode.node)
        self:debug('aligned: %s', tostring(aligned))
        if aligned then
            -- find the next direction switch and continue course from there
            local nextDirectionChangeIx = self.turnCourse:getNextDirectionChangeFromIx(self.turnCourse:getCurrentWaypointIx())
            if nextDirectionChangeIx then
                self:debug('skipping to next direction change at %d', nextDirectionChangeIx + 1)
                if self.turnCourse:isReverseAt(nextDirectionChangeIx + 1) then
                    self.ppc:initializeForReversing(nextDirectionChangeIx + 1)
                else
                    self.ppc:initialize(nextDirectionChangeIx + 1)
                end
            end
        end
    end
end

--- Check if we reached a waypoint where we should change to forward. This is useful when backing up to reach a point
--- where we can start driving on an arc, for example in a headland corner of when backing up from the field edge
--- before we make a U turn
function CourseTurn:changeToFwdWhenWaypointReached()
    local changeWpIx = TurnManeuver.hasTurnControl(self.turnCourse, self.turnCourse:getCurrentWaypointIx(), TurnManeuver.CHANGE_TO_FWD_WHEN_REACHED)
    if changeWpIx and self.ppc:isReversing() then
        local _, _, dz = self.turnCourse:getWaypointLocalPosition(self.vehicle:getAIDirectionNode(), changeWpIx)
        -- is the change waypoint now in front of us?
        if dz > 0 then
            -- find the next direction switch and continue course from there
            local getNextFwdWaypointIx = self.turnCourse:getNextFwdWaypointIx(self.turnCourse:getCurrentWaypointIx())
            if getNextFwdWaypointIx then
                self:debug('skipping to next forward waypoint at %d (dz: %.1f)', getNextFwdWaypointIx, dz)
                self.ppc:initialize(getNextFwdWaypointIx)
            end
        end
    end
end

function CourseTurn:generateCalculatedTurn()
    local turnManeuver
    if self.turnContext:isHeadlandCorner() then
        -- TODO_22
        self:debug('This is a headland turn')
        turnManeuver = HeadlandCornerTurnManeuver(self.vehicle, self.turnContext, self.vehicle:getAIDirectionNode(),
                self.turningRadius, self.workWidth, self.reversingImplement, self.steeringLength)
        -- adjust turn course for tight turns only for headland corners by default
        self.forceTightTurnOffset = self.steeringLength > 0
    else
        local distanceToFieldEdge = self.turnContext:getDistanceToFieldEdge(self.vehicle:getAIDirectionNode())
        local turnOnField = self.driveStrategy:isTurnOnFieldActive()
        -- if don't have to turn on field then pretend we have a lot of space
        distanceToFieldEdge = turnOnField and distanceToFieldEdge or math.huge
        self:debug('This is NOT a headland turn, turnOnField=%s distanceToFieldEdge=%.1f', turnOnField, distanceToFieldEdge)
        if distanceToFieldEdge > self.workWidth or self.steeringLength > 0 then
            -- if there's plenty of space or it is a towed implement, stick with Dubins, that's easier
            -- TODO: the generated Dubins turn may not fit on the field and we we'll move it back, forcing the
            -- vehicle to reverse at the start and at the end of the turn. This will be very slow, and if the
            -- vehicle is able to reverse, a Reeds-Shepp would be lot faster
            if self.steeringLength > 0 then
                turnManeuver = TowedDubinsTurnManeuver(self.vehicle, self.turnContext, self.vehicle:getAIDirectionNode(),
                        self.turningRadius, self.workWidth, self.steeringLength, distanceToFieldEdge)
            else
                turnManeuver = DubinsTurnManeuver(self.vehicle, self.turnContext, self.vehicle:getAIDirectionNode(),
                        self.turningRadius, self.workWidth, self.steeringLength, distanceToFieldEdge)
            end
        else
            turnManeuver = ReedsSheppTurnManeuver(self.vehicle, self.turnContext, self.vehicle:getAIDirectionNode(),
                    self.turningRadius, self.workWidth, self.steeringLength, distanceToFieldEdge)
        end
        -- only use tight turn offset if we are towing something and not an articulated axis or track vehicle
        -- as those usually have a very small turn radius anyway, causing jackknifing
        if self.steeringLength > 0 and not AIUtil.hasArticulatedAxis(self.vehicle) then
            self:debug('Enabling tight turn offset')
            self.enableTightTurnOffset = true
        end
    end
    self.turnCourse = turnManeuver:getCourse()
end

function CourseTurn:generatePathfinderTurn(useHeadland)
    self.pathfindingStartedAt = g_currentMission.time
    local result
    local turnEndNode, goalOffset = self.turnContext:getTurnEndNodeAndOffsets(self.steeringLength)
    local _, backMarkerDistance = self.driveStrategy:getFrontAndBackMarkers()
    self:debug('Pathfinder turn (useHeadland: %s): generate turn with hybrid A*, goal offset %.1f', useHeadland, goalOffset)
    self.driveStrategy.pathfinder, result = PathfinderUtil.findPathForTurn(self.vehicle, 0, turnEndNode, goalOffset,
            self.turningRadius, self.driveStrategy:getAllowReversePathfinding(),
            useHeadland and self.fieldWorkCourse or nil,
            self.driveStrategy:getWorkWidth(), backMarkerDistance,
            self.driveStrategy:isTurnOnFieldActive(), self.turnContext:getBoundaryId())
    if result.done then
        return self:onPathfindingDone(result.path)
    else
        self.state = self.states.WAITING_FOR_PATHFINDER
        self.driveStrategy:setPathfindingDoneCallback(self, self.onPathfindingDone)
    end
end

function CourseTurn:onPathfindingDone(path)
    if path and #path > 2 then
        self:debug('Pathfinding finished with %d waypoints (%d ms)', #path, g_currentMission.time - (self.pathfindingStartedAt or 0))
        self.turnCourse = Course(self.vehicle, CpMathUtil.pointsToGameInPlace(path), true)
        -- make sure we use tight turn offset towards the end of the course so a towed implement is aligned with the new row
        self.turnCourse:setUseTightTurnOffsetForLastWaypoints(15)
        local endingTurnLength = self.turnContext:appendEndingTurnCourse(self.turnCourse, nil, true)
        local x = AIUtil.getDirectionNodeToReverserNodeOffset(self.vehicle)
        self:debug('Extending course at direction switch for reversing to %.1f m (or at least 1m)', -x)
        self.turnCourse:adjustForReversing(math.max(1, -x))
        TurnManeuver.setLowerImplements(self.turnCourse, endingTurnLength, true)
    else
        self:debug('No path found in %d ms, falling back to normal turn course generator', g_currentMission.time - (self.pathfindingStartedAt or 0))
        self:generateCalculatedTurn()
    end
    self.ppc:setCourse(self.turnCourse)
    self.ppc:initialize(1)
    self.state = self.states.TURNING
end

function CourseTurn:drawDebug()
    if self.turnCourse and self.turnCourse:isTemporary() and CpDebug:isChannelActive(CpDebug.DBG_TURN, self.vehicle) then
        self.turnCourse:draw()
    end
end

--- A turn maneuver to recover when the vehicle is blocked by an object (tree, fence, etc) during the turn
--- This should only be initiated when the state is TURNING, so after the row is finished and before starting
--- the new row.
--- The recovery turn will back up the vehicle a bit and then attempt to find a path to the work start node
--- of the turn context, just as a pathfinder turn would do.
---@class RecoveryTurn : CourseTurn
RecoveryTurn = CpObject(CourseTurn)
---@param reverseDistance number|nil distance to back up before retrying pathfinding, default 10 m
---@param retryCount number|nil this attempt's retry count, that is how many times so far have this turn tried to
--- recover? First call should be 0 (default)
function RecoveryTurn:init(vehicle, driveStrategy, ppc, proximityController, turnContext, fieldWorkCourse, workWidth,
                           reverseDistance, retryCount, name)
    CourseTurn.init(self, vehicle, driveStrategy, ppc, proximityController, turnContext, fieldWorkCourse, workWidth, name or 'RecoveryTurn')
    -- we could also just unregister, but this way we'll have a log entry in case the recovery is
    -- blocked too, indicating that we give up.
    self.proximityController:registerBlockingObjectListener(self, RecoveryTurn.onBlocked)
    self.retryCount = retryCount or 0
    if self.driveStrategy:getAllowReversePathfinding() then
        self:debug('Starting a pathfinder turn to recover after being blocked without reversing first')
        self:generatePathfinderTurn(false)
    else
        reverseDistance = reverseDistance or 10
        self:debug('reverse pathfinding not allowed, reversing before pathfinding, retry count %d, reverse distance %.1f',
                self.retryCount, reverseDistance)
        self.state = self.states.REVERSING_AFTER_BLOCKED
        self.turnCourse = Course.createStraightReverseCourse(self.vehicle, reverseDistance)
        self.ppc:setCourse(self.turnCourse)
        self.ppc:initialize(1)
    end
end

function RecoveryTurn:turn()
    if self.state == self.states.REVERSING_AFTER_BLOCKED then
        return AITurn.turn(self)
    else
        return CourseTurn.turn(self)
    end
end

function RecoveryTurn:onWaypointPassed(ix, course)
    AITurn.onWaypointPassed(self, ix, course)
    if self.turnCourse and self.turnCourse:isLastWaypointIx(ix) then
        if self.state == self.states.REVERSING_AFTER_BLOCKED then
            self:debug('Starting a pathfinder turn to recover after being blocked')
            self:generatePathfinderTurn(false)
        end
    end
end

function RecoveryTurn:onBlocked()
    if self.retryCount < 1 then
        self:debug('Recovering from blocked turn unsuccessful after %d tries, trying again.', self.retryCount + 1)
        -- back up a bit more and see if that works
        self:startRecoveryTurn(0.5 * self.turningRadius, self.retryCount + 1)
    else
        self:debug('Recovering from blocked turn unsuccessful, giving up after %d tries.', self.retryCount + 1)
        self:resumeFieldworkAfterTurn(self.turnContext.turnEndWpIx)
    end
end

--- Combines (in general, when harvesting) in headland corners we want to work the corner first, then back up and then
--- turn so we harvest any area before we drive over it
---@class CombineCourseTurn : CourseTurn
CombineCourseTurn = CpObject(CourseTurn)

---@param turnContext TurnContext
function CombineCourseTurn:init(vehicle, driveStrategy, ppc, proximityController, turnContext, fieldWorkCourse, workWidth, name)
    CourseTurn.init(self, vehicle, driveStrategy, ppc, proximityController, turnContext, fieldWorkCourse, workWidth, name or 'CombineCourseTurn')
end

-- in a combine headland turn we want to raise the header after it reached the field edge (or headland edge on an inner
-- headland.
function CombineCourseTurn:getRaiseImplementNode()
    return self.turnContext.lateWorkEndNode
end

--[[
  Headland turn for combines on the outermost headland:
  1. drive forward to the field edge or the headland path edge
  2. start turning forward
  3. reverse straight and then align with the direction after the
     corner while reversing
  4. forward to the turn start to continue on headland
]]
---@class CombinePocketHeadlandTurn : CombineCourseTurn
CombinePocketHeadlandTurn = CpObject(CombineCourseTurn)

---@param driveStrategy AIDriveStrategyCombineCourse
---@param turnContext TurnContext
function CombinePocketHeadlandTurn:init(vehicle, driveStrategy, ppc, proximityController, turnContext, fieldWorkCourse, workWidth)
    CombineCourseTurn.init(self, vehicle, driveStrategy, ppc, proximityController, turnContext, fieldWorkCourse,
            workWidth, 'CombinePocketHeadlandTurn')
end

--- Create a pocket in the next row at the corner to stay on the field during the turn maneuver.
---@param turnContext TurnContext
function CombinePocketHeadlandTurn:generatePocketHeadlandTurn(turnContext)
    local cornerWaypoints = {}
    -- this is how far we have to cut into the next headland (the position where the header will be after the turn)
    local offset = math.min(self.turningRadius + turnContext.frontMarkerDistance, self.workWidth)
    local corner = turnContext:createCorner(self.vehicle, self.turningRadius)
    local d = -self.workWidth / 2 + turnContext.frontMarkerDistance
    local reverseDistance = 2 * offset
    local wp
    if reverseDistance / 2 > d + 2 then
        -- drive forward only if we aren't there yet
        wp = corner:getPointAtDistanceFromCornerStart(d + 2)
        table.insert(cornerWaypoints, wp)
        -- drive forward up to the field edge
        wp = corner:getPointAtDistanceFromCornerStart(d)
        table.insert(cornerWaypoints, wp)
    end
    -- drive back to prepare for making a pocket
    wp = corner:getPointAtDistanceFromCornerStart(reverseDistance / 2)
    wp.rev = true
    table.insert(cornerWaypoints, wp)
    wp = corner:getPointAtDistanceFromCornerStart(reverseDistance)
    wp.rev = true
    table.insert(cornerWaypoints, wp)
    -- now make a pocket in the inner headland to make room to turn
    wp = corner:getPointAtDistanceFromCornerStart(reverseDistance * 0.75, -offset * 0.6)
    table.insert(cornerWaypoints, wp)
    wp = corner:getPointAtDistanceFromCornerStart(reverseDistance * 0.5, -offset * 0.7)
    if not CpFieldUtil.isOnField(wp.x, wp.z) then
        self:debug('No field where the pocket would be, this seems to be a 270 corner')
        corner:delete()
        return nil
    end
    table.insert(cornerWaypoints, wp)
    -- drive forward to the field edge on the inner headland
    wp = corner:getPointAtDistanceFromCornerStart(d, -offset * 0.7)
    table.insert(cornerWaypoints, wp)
    wp = corner:getPointAtDistanceFromCornerStart(reverseDistance / 1.5)
    wp.rev = true
    table.insert(cornerWaypoints, wp)
    wp = corner:getPointAtDistanceFromCornerEnd(self.turningRadius / 3, self.turningRadius / 2)
    table.insert(cornerWaypoints, wp)
    wp = corner:getPointAtDistanceFromCornerEnd(self.turningRadius, self.turningRadius / 4)
    table.insert(cornerWaypoints, wp)
    corner:delete()
    return Course(self.vehicle, cornerWaypoints, true), turnContext.turnEndWpIx
end

function CombinePocketHeadlandTurn:startTurn()
    self.turnCourse = self:generatePocketHeadlandTurn(self.turnContext)
    if not self.turnCourse then
        self:debug('Could not create pocket course, falling back to normal headland corner')
        self:generateCalculatedTurn()
    end
    self.ppc:setCourse(self.turnCourse)
    self.ppc:initialize(1)
    self.state = self.states.TURNING
end

--- When making a pocket we need to lower the header whenever driving forward
function CombinePocketHeadlandTurn:turn(dt)
    local gx, gy, moveForwards, maxSpeed = AITurn.turn(self)
    if self.ppc:isReversing() then
        self.driveStrategy:raiseImplements()
        self.implementsLowered = nil
    elseif not self.implementsLowered then
        self.driveStrategy:lowerImplements()
        self.implementsLowered = true
    end
    return gx, gy, moveForwards, maxSpeed
end

--- No turn ending phase here, we just have one course for the entire turn and when it ends, we are done
function CombinePocketHeadlandTurn:onWaypointPassed(ix, course)
    if ix == course:getNumberOfWaypoints() then
        self:debug('onWaypointPassed %d', ix)
        self:debug('Last waypoint reached, resuming fieldwork')
        self:resumeFieldworkAfterTurn(self.turnContext.turnEndWpIx)
    end
end

--- A turn type which isn't really a turn, we only use this to finish a row (drive straight until the implement
--- reaches the end of the row, don't drive towards the next waypoint until then) and then call the
--- user supplied callback.
---@class FinishRowOnly : AITurn
FinishRowOnly = CpObject(AITurn)

function FinishRowOnly:init(vehicle, driveStrategy, ppc, proximityController, turnContext)
    AITurn.init(self, vehicle, driveStrategy, ppc, proximityController, turnContext, 0, 'FinishRow')
end

-- don't perform the actual turn, just give back control to the strategy
function FinishRowOnly:startTurn()
    self:debug('Row finished, ending turn')
    self:resumeFieldworkAfterTurn(self.turnContext.turnEndWpIx)
end

--- A turn which really isn't a turn just a course to start a field work row using the supplied course and
--- making sure we start working at the start point defined by the turn context with all implements lowered in time.
--- This does not actually drive the course like the other AITurn derivates to keep full control in the strategy
--- (like not registering its own onWaypoint* callbacks). It only provides a getDriveData() for limiting
--- the speed, and probably should not even be a turn.
---@class StartRowOnly: CourseTurn
StartRowOnly = CpObject(CourseTurn)
---@param turnContext RowStartOrFinishContext a turn context holding all data about the work start location and
--- the implement configuration
---@param startRowCourse Course course leading to the first waypoint of the row to start
function StartRowOnly:init(vehicle, driveStrategy, ppc, turnContext, startRowCourse)
    -- not yet reached a TurnManeuver.LOWER_IMPLEMENT_AT_TURN_END marker
    self:addState('DRIVING_TO_ROW')
    -- close to the work start point, ready to lower at the right moment
    self:addState('APPROACHING_ROW')
    -- implements are now lowering, maneuver ends when they are completely lowered
    self:addState('IMPLEMENTS_LOWERING')
    self.vehicle = vehicle
    self.settings = vehicle:getCpSettings()
    self.turningRadius = AIUtil.getTurningRadius(self.vehicle)
    ---@type AIDriveStrategyFieldWorkCourse
    self.driveStrategy = driveStrategy
    ---@type PurePursuitController
    self.ppc = ppc
    ---@type TurnContext
    self.turnContext = turnContext
    self.name = 'StartRowOnly'

    self.turnCourse = startRowCourse

    self.forceTightTurnOffset = false
    local _, steeringLength = AIUtil.getSteeringParameters(self.vehicle)
    self.enableTightTurnOffset = steeringLength > 0 and not AIUtil.hasArticulatedAxis(self.vehicle)

    -- TODO: do we need tight turn offset here?
    self.turnCourse:setUseTightTurnOffsetForLastWaypoints(15)
    -- add a turn ending section into the row to make sure the implements are lowered correctly
    local endingTurnLength = self.turnContext:appendEndingTurnCourse(self.turnCourse, 3, true)
    TurnManeuver.setLowerImplements(self.turnCourse, endingTurnLength, true)
    self.turnCourse:adjustForReversing(2)
    self.state = self.states.DRIVING_TO_ROW
end

function StartRowOnly:getCourse()
    return self.turnCourse
end

--- Implements the usual getDriveData() interface, only ever sets the maximum speed though
function StartRowOnly:getDriveData()
    if self.state == self.states.DRIVING_TO_ROW then
        if TurnManeuver.hasTurnControl(self.turnCourse, self.turnCourse:getCurrentWaypointIx(),
                TurnManeuver.LOWER_IMPLEMENT_AT_TURN_END) then
            self.state = self.states.APPROACHING_ROW
            self:debug('Approaching row')
            self.driveStrategy:raiseControllerEvent(AIDriveStrategyCourse.onTurnEndProgressEvent,
                    self.turnContext.workStartNode, self.ppc:isReversing(), true, not self.turnContext:isNextTurnLeft())
        end
    elseif self.state == self.states.APPROACHING_ROW then
        local shouldLower, _ = self.driveStrategy:shouldLowerImplements(self.turnContext.workStartNode,
                self.ppc:isReversing())
        if shouldLower then
            -- have not started lowering implements yet
            self:debug('Lowering implements')
            self.driveStrategy:lowerImplements()
            self.state = self.states.IMPLEMENTS_LOWERING
            if self.ppc:isReversing() then
                -- when ending a turn in reverse, don't drive the rest of the course, switch right back to fieldwork
                self:resumeFieldworkAfterTurn(self.turnContext.turnEndWpIx)
            end
        end
        return nil, nil, nil, self:getForwardSpeed()
    elseif self.state == self.states.IMPLEMENTS_LOWERING then
        local _, dz = self.driveStrategy:shouldLowerImplements(self.turnContext.workStartNode, self.ppc:isReversing())
        -- implements already lowering, making sure we check if they are lowered, the faster we go, the earlier,
        -- for those people who set insanely high turn speeds...
        local implementCheckDistance = math.max(1, 0.1 * self.vehicle:getLastSpeed())
        if dz and dz > -implementCheckDistance then
            if self.driveStrategy:getCanContinueWork() then
                self:debug("implements lowered, resume fieldwork")
                self:resumeFieldworkAfterTurn(self.turnContext.turnEndWpIx)
            else
                self:debug('waiting for lower at dz=%.1f', dz)
                -- we are almost at the start of the row but still not lowered everything, hold.
                return nil, nil, nil, 0
            end
        end
        return nil, nil, nil, self:getForwardSpeed()
    end
    return nil, nil, nil, nil
end

function StartRowOnly:onLastWaypoint()
    self:debug('Last waypoint reached before all implements are lowered, resuming fieldwork')
    self:resumeFieldworkAfterTurn(self.turnContext.turnEndWpIx)
end

--- A turn for working between vine rows.
---@class VineTurn : CourseTurn
VineTurn = CpObject(CourseTurn)
function VineTurn:init(vehicle, driveStrategy, ppc, proximityController, turnContext, fieldWorkCourse, workWidth)
    CourseTurn.init(self, vehicle, driveStrategy, ppc, proximityController, turnContext, fieldWorkCourse, workWidth, 'VineTurn')
end

function VineTurn:startTurn()
    local turnManeuver = VineTurnManeuver(self.vehicle, self.turnContext, self.vehicle:getAIDirectionNode(),
            self.turningRadius, self.workWidth)
    self.turnCourse = turnManeuver:getCourse()
    self.ppc:setCourse(self.turnCourse)
    self.ppc:initialize(1)
    self.state = self.states.TURNING
end
