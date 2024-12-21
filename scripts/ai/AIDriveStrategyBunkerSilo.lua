--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2022 Peter Vaiko

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

--- Drive strategy for bunker silos.
---@class AIDriveStrategyBunkerSilo : AIDriveStrategyCourse
AIDriveStrategyBunkerSilo = CpObject(AIDriveStrategyCourse)

AIDriveStrategyBunkerSilo.myStates = {
    DRIVING_TO_SILO = {},
    DRIVING_TO_PARK_POSITION = {},
    WAITING_AT_PARK_POSITION = {fuelSaveAllowed = true},
    WAITING_FOR_PREPARING = {fuelSaveAllowed = true},
    DRIVING_INTO_SILO = {},
	DRIVING_OUT_OF_SILO = {},
    DRIVING_TURN = {},
    DRIVING_TEMPORARY_OUT_OF_SILO = {}
}

AIDriveStrategyBunkerSilo.siloEndProximitySensorRange = 4
AIDriveStrategyBunkerSilo.isStuckMs = 1000 * 15
AIDriveStrategyBunkerSilo.isStuckBackOffset = 12
AIDriveStrategyBunkerSilo.maxDriveIntoTheSiloAttempts = 2
AIDriveStrategyBunkerSilo.endReachedOffset = 3

function AIDriveStrategyBunkerSilo:init(task, job)
    AIDriveStrategyCourse.init(self, task, job)
    AIDriveStrategyCourse.initStates(self, AIDriveStrategyBunkerSilo.myStates)
    self.state = self.states.INITIAL

    self.debugChannel = CpDebug.DBG_SILO
	self.silo = nil
    self.siloController = nil
    self.drivingForwardsIntoSilo = true
    self.turnNode = CpUtil.createNode("turnNode", 0, 0, 0)

    self.isStuckTimer = Timer.new(self.isStuckMs)
    self.driveIntoSiloAttempts = 0
end

function AIDriveStrategyBunkerSilo:delete()
    self.silo:resetTarget(self.vehicle)
    self.isStuckTimer:delete()
    if self.parkNode then 
        CpUtil.destroyNode(self.parkNode)
        self.parkNode = nil
    end
    if self.turnNode then 
        CpUtil.destroyNode(self.turnNode)
        self.turnNode = nil
    end

    AIDriveStrategyCourse.delete(self)
end

function AIDriveStrategyBunkerSilo:startWithoutCourse(jobParameters)
    self:info('Starting bunker silo mode.')
    -- to always have a valid course (for the traffic conflict detector mainly)
    self.course = Course.createStraightForwardCourse(self.vehicle, 25)
    self:startCourse(self.course, 1)
    if self.silo == nil then 
        self:info("Bunker silo is nil!")
        self.vehicle:stopCurrentAIJob(AIMessageErrorUnknown.new())
        return
    end

    self.stopWithCompactedSilo = jobParameters.stopWithCompactedSilo:getValue()
    self.waitAtParkPosition = jobParameters.waitAtParkPosition:getValue()
    self:debug("Wait at park position: %s", tostring(jobParameters.waitAtParkPosition:getValue()))
    if self.leveler then 
        local directionNode = self.vehicle:getAIDirectionNode()
        local _, _, dz = localToLocal(self.leveler.rootNode, directionNode, 0, 0, 0)
        if dz < 0 then
            self.drivingForwardsIntoSilo = false
        end
    else 
        self:debug("Should drive forwards into the silo: %s", tostring(jobParameters.drivingForwardsIntoSilo:getValue()))
        self.drivingForwardsIntoSilo = jobParameters.drivingForwardsIntoSilo:getValue()
    end

    --- Proximity sensor to detect the silo end wall.
    if self.drivingForwardsIntoSilo then
        self.siloEndProximitySensor = SingleForwardLookingProximitySensorPack(self.vehicle, self.frontMarkerNode, 
                                                                    self.siloEndProximitySensorRange, 1)
        local x, _, z = getWorldTranslation(self.frontMarkerNode)
        local dirX, _, dirZ = localDirectionToWorld(self.frontMarkerNode, 0, 0, 1)
        local yRot = MathUtil.getYRotationFromDirection(dirX, dirZ)
        self.siloEndDetectionMarker = CpUtil.createNode("siloEndDetectionMarker", x, z, yRot)
    else
        self.siloEndProximitySensor = SingleBackwardLookingProximitySensorPack(self.vehicle, self.backMarkerNode, 
                                                                    self.siloEndProximitySensorRange, 1)
        local x, _, z = getWorldTranslation(self.backMarkerNode)
        local dirX, _, dirZ = localDirectionToWorld(self.backMarkerNode, 0, 0, -1)
        local yRot = MathUtil.getYRotationFromDirection(dirX, dirZ)
        self.siloEndDetectionMarker = CpUtil.createNode("siloEndDetectionMarker", x, z, yRot)
    end

    --- Setup the silo controller, that handles the driving conditions and coordinations.
	self.siloController = self.silo:setupLevelerTarget(self.vehicle, self, self.siloEndDetectionMarker)

end

function AIDriveStrategyBunkerSilo:getGeneratedCourse()
    return nil    
end

-----------------------------------------------------------------------------------------------------------------------
--- Implement handling
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyBunkerSilo:initializeImplementControllers(vehicle)
    self.leveler = self:addImplementController(vehicle, LevelerController, Leveler, {})
    self:addImplementController(vehicle, BunkerSiloCompacterController, BunkerSiloCompacter, {})
    self:addImplementController(vehicle, MotorController, Motorized, {})
    self:addImplementController(vehicle, WearableController, Wearable, {})
    self:addImplementController(vehicle, FoldableController, Foldable, {})
end

function AIDriveStrategyBunkerSilo:isFuelSaveAllowed()
    return self.state.properties.fuelSaveAllowed or AIDriveStrategyCourse.isFuelSaveAllowed(self)
end

-----------------------------------------------------------------------------------------------------------------------
--- Static parameters (won't change while driving)
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyBunkerSilo:setAllStaticParameters()
    AIDriveStrategyCourse.setAllStaticParameters(self)
    Markers.setMarkerNodes(self.vehicle)

    self.frontMarkerNode, self.backMarkerNode, self.frontMarkerDistance, self.backMarkerDistance = 
        Markers.getMarkerNodes(self.vehicle)

    self.proximityController:registerIgnoreObjectCallback(self, self.ignoreProximityObject)


    self.isStuckTimer:setFinishCallback(function ()
            if self.frozen then 
                return
            end
            self:debug("is stuck, trying to drive out of the silo.")
            if self:isTemporaryOutOfSiloDrivingAllowed() then 
                if self.driveIntoSiloAttempts >= self.maxDriveIntoTheSiloAttempts then
                    self:debug("Max attempts reached, trying a new approach.")
                    self:startDrivingOutOfSilo()
                else
                    self:startDrivingTemporaryOutOfSilo()
                end
            elseif self.state == self.states.DRIVING_INTO_SILO and self.siloController:hasNearbyUnloader() and self:isDrivingToParkPositionAllowed() then
                self:debug("Found an unloader nearby and is stuck, so immediately leave the silo.")
                self:startDrivingOutOfSilo()
            end
        end)

end

function AIDriveStrategyBunkerSilo:setSilo(silo)
    ---@type CpBunkerSilo
	self.silo = silo	
end

function AIDriveStrategyBunkerSilo:setAIVehicle(vehicle, jobParameters)
    AIDriveStrategyCourse.setAIVehicle(self, vehicle, jobParameters)
    local parkPosition = jobParameters.startPosition
    if parkPosition ~= nil and parkPosition.x ~= nil and parkPosition.z ~= nil and parkPosition.angle ~= nil then
        self.parkNode = CpUtil.createNode("parkNode", parkPosition.x, parkPosition.z, parkPosition.angle)
        self:debug("Valid park position set.")
    end
end

-----------------------------------------------------------------------------------------------------------------------
--- Event listeners
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyBunkerSilo:onWaypointPassed(ix, course)
    if course:isLastWaypointIx(ix) then
        if self.state == self.states.DRIVING_INTO_SILO then 
            self:startDrivingOutOfSilo()
        elseif self.state == self.states.DRIVING_OUT_OF_SILO then 
            if self:isDrivingToParkPositionAllowed() and self.siloController:hasNearbyUnloader() then
                --- Only allow driving to park position here for now, as the silo interferes with the pathfinder.
                self:startPathfindingToParkPosition()
            else 
                self:startTransitionToNextLane()
            end
        elseif self.state == self.states.DRIVING_TURN then 
            self.ppc:setNormalLookaheadDistance()
            local course = self:getRememberedCourseAndIx()
            self:startDrivingIntoSilo(course)
        elseif self.state == self.states.DRIVING_TO_SILO then
            local course = self:getRememberedCourseAndIx()
            self:startDrivingIntoSilo(course)
            self.vehicle:raiseAIEvent("onAIFieldWorkerStart", "onAIImplementStart")
        elseif self.state == self.states.DRIVING_TO_PARK_POSITION then
            self.state = self.states.WAITING_AT_PARK_POSITION
        elseif self.state == self.states.DRIVING_TEMPORARY_OUT_OF_SILO then
            local course = self:getRememberedCourseAndIx()
            self:startDrivingIntoSilo(course)
        end
    end
end

function AIDriveStrategyBunkerSilo:getDriveData(dt, vX, vY, vZ)
    local moveForwards = not self.ppc:isReversing()
    local gx, gz, maxSpeed

    if not moveForwards then
        gx, gz, maxSpeed = self:getReverseDriveData()
       -- self:setMaxSpeed(maxSpeed)
    else
        gx, _, gz = self.ppc:getGoalPointPosition()
    end

    local moveForwards = not self.ppc:isReversing()
    self:updateLowFrequencyImplementControllers()
    self:drive(dt)
    AIDriveStrategyFieldWorkCourse.setAITarget(self)

	self:setMaxSpeed(self.settings.bunkerSiloSpeed:getValue())

    self:checkProximitySensors(moveForwards)

    if self:isTemporaryOutOfSiloDrivingAllowed() then
        self.isStuckTimer:startIfNotRunning()
    end

    if self.siloController:hasNearbyUnloader() then 
        if not self:isDrivingToParkPositionAllowed() then 
            self:setMaxSpeed(0) -- Waiting for unloader
            self:setInfoText(InfoTextManager.WAITING_FOR_UNLOADER)
        end
    elseif not self:isDrivingToParkPositionAllowed() then
        self:clearInfoText(InfoTextManager.WAITING_FOR_UNLOADER)
    end
    
    if self.vehicle:getIsAIPreparingToDrive() then 
        self:setMaxSpeed(0) --- Unfolding/folding
    end

    if self.stopWithCompactedSilo and self.silo:getCompactionPercentage() >= 99 then 
        self:debug("Stopping, as the silo is compacted.")
        self.vehicle:stopCurrentAIJob(AIMessageSuccessFinishedJob.new())
    end

    if not self.silo:canBeFilled() then 
        self:debug("Stopping, as the silo state is no longer filling.")
        self.vehicle:stopCurrentAIJob(AIMessageSuccessFinishedJob.new())
    end

    return gx, gz, moveForwards, self.maxSpeed, 100
end

function AIDriveStrategyBunkerSilo:isTemporaryOutOfSiloDrivingAllowed()
    return (self.state == self.states.DRIVING_INTO_SILO or self.state == self.states.DRIVING_TURN) and 
            AIUtil.isStopped(self.vehicle) 
            and not self.siloController:hasNearbyUnloader()
            and not self.proximityController:isStopped()
end

function AIDriveStrategyBunkerSilo:checkProximitySensors(moveForwards)
    AIDriveStrategyCourse.checkProximitySensors(self, moveForwards)
  
end

function AIDriveStrategyBunkerSilo:update(dt)
    AIDriveStrategyCourse.update(self, dt)
    self:updateImplementControllers(dt)
    if CpDebug:isChannelActive(self.debugChannel, self.vehicle) then

        self.pathfinderController:drawNodes()
        if self.ppc:getCourse() then
            self.ppc:getCourse():draw()
        end
        if self.siloEndDetectionMarker ~= nil then
            DebugUtil.drawDebugNode(self.siloEndDetectionMarker, "siloEndDetectionMarker", false, 1)
        end

        DebugUtil.drawDebugNode(self.frontMarkerNode, "FrontMarker", false, 1)
        DebugUtil.drawDebugNode(self.backMarkerNode, "BackMarker", false, 1)
        if self.parkNode then 
            DebugUtil.drawDebugNode(self.parkNode, "ParkNode", true, 3)
        end
        if self.leveler then 
            DebugUtil.drawDebugNode(ImplementUtil.getLevelerNode(self.leveler).node, "LevelerNode", true, 3)
        end
    end
end

-----------------------------------------------------------------------------------------------------------------------
--- Bunker silo interactions
-----------------------------------------------------------------------------------------------------------------------

function AIDriveStrategyBunkerSilo:drive(dt)
    if self.state == self.states.INITIAL then
        self:setMaxSpeed(0)
        if self.silo:isVehicleInSilo(self.vehicle) then 
            self:startDrivingIntoSilo()
        else 
            local course, _ = self:getDriveIntoSiloCourse()
            self:startPathfindingToSiloCourse( course, 1, self:isDriveDirectionReverse())
        end
    elseif self.state == self.states.DRIVING_INTO_SILO then

        local _, _, closestObject = self.siloEndProximitySensor:getClosestObjectDistanceAndRootVehicle()
        if self.silo:isTheSameSilo(closestObject) then
            self:debug("End wall detected.")
            self:startDrivingOutOfSilo()
        end

        local isEndReached, maxSpeed = self.siloController:isEndReached(self:getEndMarker(), self:getEndMarkerOffset())
        if isEndReached then
            self:debug("Bunker silo end is reached.")
            self:startDrivingOutOfSilo()
        end

        self:setMaxSpeed(maxSpeed)

        if self:isDrivingToParkPositionAllowed() then
            if self.siloController:hasNearbyUnloader() then 
           --     self:startDrivingToParkPositionWithPathfinding()
            end
        end

    elseif self.state == self.states.DRIVING_OUT_OF_SILO then
        if self:isDrivingToParkPositionAllowed() then
            if self.siloController:hasNearbyUnloader() then 
              --  self:startDrivingToParkPositionWithPathfinding()
            end
        end
    elseif self.state == self.states.WAITING_FOR_PATHFINDER then
        self:setMaxSpeed(0)
    elseif self.state == self.states.WAITING_AT_PARK_POSITION then
        self:setMaxSpeed(0)
        self:setInfoText(InfoTextManager.WAITING_FOR_UNLOADER)
        if not self.siloController:hasNearbyUnloader() then
            local course, _ = self:getDriveIntoSiloCourse()
            self:startPathfindingToSiloCourse( course, 1, self:isDriveDirectionReverse())
            self:clearInfoText(InfoTextManager.WAITING_FOR_UNLOADER)
        end
    elseif self.state == self.states.DRIVING_TURN then 
        self:setMaxSpeed(self.settings.turnSpeed:getValue())
    end
end

function AIDriveStrategyBunkerSilo:isWaitingAtParkPosition()
    return self.state == self.states.WAITING_AT_PARK_POSITION
end

function AIDriveStrategyBunkerSilo:isWaitingForUnloaders()
    return self.state == self.states.WAITING_AT_PARK_POSITION or not self:isDrivingToParkPositionAllowed() and self.siloController:hasNearbyUnloader()
end

function AIDriveStrategyBunkerSilo:isDrivingToParkPositionAllowed()
    return self.waitAtParkPosition and self.parkNode ~= nil
end

--- Is the drive direction to drive into the silo reverse?
function AIDriveStrategyBunkerSilo:isDriveDirectionReverse()
    return not self.drivingForwardsIntoSilo
end

--- Starts the straight silo lane earlier. (Driving into the silo)
function AIDriveStrategyBunkerSilo:getStartOffset()
    return -4 * self:getEndOffset()
end

--- Makes sure the straight silo lane stops later. (Driving out of the silo)
function AIDriveStrategyBunkerSilo:getEndOffset()
    local offset = self:isDriveDirectionReverse() and - self.backMarkerDistance or self.frontMarkerDistance
    return offset
end

function AIDriveStrategyBunkerSilo:getTemporaryBackCourseLength()
    return self.isStuckBackOffset + math.abs(self.frontMarkerDistance) + math.abs(self.backMarkerDistance)
end

function AIDriveStrategyBunkerSilo:getEndMarker()
  
    return self.siloEndDetectionMarker
end

function AIDriveStrategyBunkerSilo:getEndMarkerOffset()
    return self.endReachedOffset
end

--- Gets the work width.
function AIDriveStrategyBunkerSilo:getWorkWidth()
    return self.settings.bunkerSiloWorkWidth:getValue()
end

function AIDriveStrategyBunkerSilo:startTransitionToNextLane()
    self.state = self.states.DRIVING_TURN
    local course, ix = self:getDriveIntoSiloCourse()
    self:rememberCourse(course, ix)
    self.ppc:setShortLookaheadDistance()

    local x, y, z = course:getWaypointPosition(1)
    local yRot = course:getWaypointYRotation(1)
    setTranslation(self.turnNode, x, y, z)
    setRotation(self.turnNode, 0, yRot, 0)
    if self:isDriveDirectionReverse() then
        --- Enables reverse path finding.
        setRotation(self.turnNode, 0, yRot + math.pi, 0)
    end

    local path = PathfinderUtil.findAnalyticPath(ReedsSheppSolver(), self.vehicle:getAIDirectionNode(), 
        0, 0, self.turnNode, 0, 0, self.turningRadius)
    if not path or #path == 0 then
        self:debug("No valid turn was found!")
        self.vehicle:stopCurrentAIJob(AIMessageCpErrorNoPathFound.new())
    else 
        local turnCourse =  Course.createFromAnalyticPath(self.vehicle, path, true)
        self:startCourse(turnCourse, 1)
        self.state = self.states.DRIVING_TURN
        self:debug("Started driving turn to next lane.")
    end
end

--- Starts driving into the silo.
function AIDriveStrategyBunkerSilo:startDrivingIntoSilo(oldCourse)
    local firstWpIx, course
    if not oldCourse then 
        course, firstWpIx = self:getDriveIntoSiloCourse()
    else 
        course = oldCourse
        firstWpIx = self:getNearestWaypoints(oldCourse, self:isDriveDirectionReverse())
    end
    self:startCourse(course, firstWpIx)
    self.state = self.states.DRIVING_INTO_SILO
    self:lowerImplements()
    self:debug("Started driving into the silo.")
end

--- Start driving out of silo.
function AIDriveStrategyBunkerSilo:startDrivingOutOfSilo()
    local course, firstWpIx = self:getDriveOutOfSiloCourse(self.course)
    self:startCourse(course, firstWpIx)
    self.state = self.states.DRIVING_OUT_OF_SILO
    self:raiseImplements()
    self:debug("Started driving out of the silo.")
    self.driveIntoSiloAttempts = 0
end

function AIDriveStrategyBunkerSilo:startDrivingTemporaryOutOfSilo()
    self:rememberCourse(self.course, 1)
    local driveDirection = self:isDriveDirectionReverse()
    local course 
    if driveDirection then
		course = Course.createStraightForwardCourse(self.vehicle, self:getTemporaryBackCourseLength(), 0, self.vehicle:getAIDirectionNode())
	else 
        course = Course.createStraightReverseCourse(self.vehicle, self:getTemporaryBackCourseLength(), 0, self.vehicle:getAIDirectionNode())
	end
    self:startCourse(course, 1)
    self.state = self.states.DRIVING_TEMPORARY_OUT_OF_SILO
    self:raiseImplements()
    self.driveIntoSiloAttempts = self.driveIntoSiloAttempts + 1
    self:debug("Started driving temporary out of the silo. Attempts until now: %d", self.driveIntoSiloAttempts)
end

--- Create a straight course into the silo.
---@return Course generated course 
---@return number first waypoint of the course relative to the vehicle position.
function AIDriveStrategyBunkerSilo:getDriveIntoSiloCourse()
	local driveDirection = self:isDriveDirectionReverse()
	
    local startPos, endPos = self.siloController:getTarget(self:getWorkWidth())
    local x, z = unpack(startPos)
    local dx, dz = unpack(endPos)

    local course = Course.createFromTwoWorldPositions(self.vehicle, x, z, dx, dz, 0, 
                                                self:getStartOffset(), 0, 3, driveDirection)

	local firstWpIx = self:getNearestWaypoints(course, driveDirection)
	return course, firstWpIx
end

--- Create a straight course out of the silo.
---@param driveInCourse Course drive into the course, which will be inverted.
---@return Course generated course 
---@return number first waypoint of the course relative to the vehicle position.
function AIDriveStrategyBunkerSilo:getDriveOutOfSiloCourse(driveInCourse)
	local driveDirection = self:isDriveDirectionReverse()
    local x, _, z, dx, dz
    local startPos, endPos = self.siloController:getLastTarget()
    if driveInCourse then
        x, _, z = driveInCourse:getWaypointPosition(driveInCourse:getNumberOfWaypoints())
        dx, _, dz = driveInCourse:getWaypointPosition(1)
        local dirX, dirZ, _ = CpMathUtil.getPointDirection({x = x, z = z}, {x = dx, z = dz}) 
        local sx, sz = unpack(startPos)
        local ex, ez = unpack(endPos)
        local length = MathUtil.vector2Length(sx - ex, sz - ez)
        dx, dz = x + length * dirX, z + length * dirZ
    else 
        x, z = unpack(endPos)
        dx, dz = unpack(startPos)
    end

	local course = Course.createFromTwoWorldPositions(self.vehicle, x, z, dx, dz, 0, 0, 
    self:getEndOffset(), 3, not driveDirection)
	local firstWpIx = self:getNearestWaypoints(course, not driveDirection)
	return course, firstWpIx
end

function AIDriveStrategyBunkerSilo:getNearestWaypoints(course, reverse)
    if reverse then 
        local ix = course:getNextRevWaypointIxFromVehiclePosition(1, self.vehicle:getAIDirectionNode(), 10)
        return ix
    end
    local firstWpIx = course:getNearestWaypoints(self.vehicle:getAIDirectionNode())
    return firstWpIx
end

--- Stops the driver, as the silo was deleted.
function AIDriveStrategyBunkerSilo:stopSiloWasDeleted()
    self.vehicle:stopCurrentAIJob(AIMessageErrorUnknown.new())
end

-----------------------------------------------------------------------------------------------------------------------
--- Leveler interactions
-----------------------------------------------------------------------------------------------------------------------

function AIDriveStrategyBunkerSilo:isLevelerLoweringAllowed()
    return self.state == self.states.DRIVING_INTO_SILO
end

--- Ignores the bunker silo for the proximity sensors.
function AIDriveStrategyBunkerSilo:ignoreProximityObject(object, vehicle)
    if self.silo:isTheSameSilo(object) then
        return true 
    end
    --- This ignores the terrain.
    if object == nil then
        return true
    end
end

------------------------------------------------------------------------------------------------------------------------
--- Pathfinding
---------------------------------------------------------------------------------------------------------------------------

--- Pathfinding has finished
---@param controller PathfinderController
---@param success boolean
---@param course Course|nil
---@param goalNodeInvalid boolean|nil
function AIDriveStrategyBunkerSilo:onPathfindingFinished(controller, 
    success, course, goalNodeInvalid)
    if not success then
        self:debug('Pathfinding failed, giving up!')
        self.vehicle:stopCurrentAIJob(AIMessageCpErrorNoPathFound.new())
        return
    end
    if self.state == self.states.DRIVING_TO_SILO then 
        self:startCourse(course, 1)
    elseif self.state == self.states.DRIVING_TO_PARK_POSITION then
        self:startCourse(course, 1)
    end
end

--- Pathfinding failed, but a retry attempt is leftover.
---@param controller PathfinderController
---@param lastContext PathfinderContext
---@param wasLastRetry boolean
---@param currentRetryAttempt number
function AIDriveStrategyBunkerSilo:onPathfindingFailed(controller,
    lastContext, wasLastRetry, currentRetryAttempt)
    --- TODO: Think of possible points of failures, that could be adjusted here.
    ---       Maybe a small reverse course might help to avoid a deadlock
    ---       after one pathfinder failure based on proximity sensor data and so on ..
    if self.state == self.states.DRIVING_TO_SILO then 
        local course = self:getRememberedCourseAndIx()
        controller:findPathToWaypoint(lastContext, course, 
            1, 0, 0, 1)
    elseif self.state == self.states.DRIVING_TO_PARK_POSITION then
        self.pathfinderController:findPathToNode(lastContext, self.parkNode, 
            0, 0, 1)
    end
end

--- Find an alignment path to the silo/heap course.
---@param course Course silo/heap course  
---@param ix number
---@param isReverse boolean
function AIDriveStrategyBunkerSilo:startPathfindingToSiloCourse(course, ix, isReverse)
    self.state = self.states.DRIVING_TO_SILO
    self:rememberCourse(course, ix)
    local context = PathfinderContext(self.vehicle):allowReverse(true):offFieldPenalty(0)
    self.pathfinderController:findPathToWaypoint(context, course, 
        ix, 0, 0, 1)
end

function AIDriveStrategyBunkerSilo:startPathfindingToParkPosition()
    if not self:isDrivingToParkPositionAllowed() then 
        self:debug("Driving to park position is not allowed!")
        return 
    end
    self.state = self.states.DRIVING_TO_PARK_POSITION
    self.vehicle:prepareForAIDriving()
    local context = PathfinderContext(self.vehicle):allowReverse(true):offFieldPenalty(0)
    self.pathfinderController:findPathToNode(context, self.parkNode, 
        0, 0, 1)
end

---@param status CpStatus
function AIDriveStrategyBunkerSilo:updateCpStatus(status)
    status:setLevelSiloStatus(self.silo:getCompactionPercentage())
end