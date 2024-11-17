--[[
This file is part of Courseplay (https://github.com/Courseplay/Courseplay_FS22)
Copyright (C) 2023 Courseplay Dev Team 

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

This drive strategy implements:
 - Loading from an bunker silo or a heap on a field with a wheel loader.
 - Dumping the picked up fill level to an unload trigger oder a trailer.
 - Automatically setting the shovel/arm Positions of the wheel loader.

]]



---@class AIDriveStrategyShovelSiloLoader : AIDriveStrategyCourse
---@field shovelController ShovelController
AIDriveStrategyShovelSiloLoader = CpObject(AIDriveStrategyCourse)

----------------------------------------------------------------
--- State properties
----------------------------------------------------------------
--[[
    shovelPosition : number (1-4)
    shovelMovingSpeed : number|nil speed while the shovel/ front loader is moving
]]


----------------------------------------------------------------
--- States
----------------------------------------------------------------

AIDriveStrategyShovelSiloLoader.myStates = {
    DRIVING_ALIGNMENT_COURSE = { shovelPosition = ShovelController.POSITIONS.TRANSPORT },
    DRIVING_INTO_SILO = { shovelPosition = ShovelController.POSITIONS.LOADING, shovelMovingSpeed = 0 },
    DRIVING_OUT_OF_SILO = { shovelPosition = ShovelController.POSITIONS.TRANSPORT },
    DRIVING_TEMPORARY_OUT_OF_SILO = { shovelPosition = ShovelController.POSITIONS.TRANSPORT },
    WAITING_FOR_TRAILER = { shovelPosition = ShovelController.POSITIONS.TRANSPORT },
    DRIVING_TO_UNLOAD_POSITION = { shovelPosition = ShovelController.POSITIONS.TRANSPORT },
    DRIVING_TO_UNLOAD_TRAILER = { shovelPosition = ShovelController.POSITIONS.TRANSPORT },
    DRIVING_TO_UNLOAD = { shovelPosition = ShovelController.POSITIONS.PRE_UNLOADING, shovelMovingSpeed = 0 },
    UNLOADING = { shovelPosition = ShovelController.POSITIONS.UNLOADING, shovelMovingSpeed = 0 },
    REVERSING_AWAY_FROM_UNLOAD = { shovelPosition = ShovelController.POSITIONS.PRE_UNLOADING, shovelMovingSpeed = 0 },
}

AIDriveStrategyShovelSiloLoader.searchForTrailerDelaySec = 10
AIDriveStrategyShovelSiloLoader.distShovelTrailerPreUnload = 7
AIDriveStrategyShovelSiloLoader.distShovelUnloadStationPreUnload = 8
AIDriveStrategyShovelSiloLoader.isStuckMs = 1000 * 15

AIDriveStrategyShovelSiloLoader.maxDistanceWithoutPathfinding = 10

--- Silo area to avoid for heap
AIDriveStrategyShovelSiloLoader.siloAreaToAvoidForHeapOffsets = {
    --- The Silo area to avoid gets extended on the front and back.
    length = 3,
    --- The Silo area to avoid gets extended on the left and right.
    width = 3
}

--- Silo area to avoid for bunker silo
--- Slightly increased to avoid hitting the side walls of the silo
AIDriveStrategyShovelSiloLoader.siloAreaToAvoidForBunkerSiloOffsets = {
    --- The Silo area to avoid gets extended on the front and back.
    length = 6,
    --- The Silo area to avoid gets extended on the left and right.
    width = 4
}

function AIDriveStrategyShovelSiloLoader:init(task, job)
    AIDriveStrategyCourse.init(self, task, job)
    AIDriveStrategyCourse.initStates(self, AIDriveStrategyShovelSiloLoader.myStates)
    self.state = self.states.INITIAL
    self.debugChannel = CpDebug.DBG_SILO
    return self
end

function AIDriveStrategyShovelSiloLoader:delete()
    AIDriveStrategyCourse.delete(self)
    if self.siloController then 
        self.siloController:delete()
        self.siloController = nil
    end
    CpUtil.destroyNode(self.heapNode)
    CpUtil.destroyNode(self.unloadPositionNode)
    CpUtil.destroyNode(self.siloFrontNode)
    self.isStuckTimer:delete()
end

function AIDriveStrategyShovelSiloLoader:getGeneratedCourse(jobParameters)
    return nil
end

---@param bunkerSilo CpBunkerSilo
---@param heapSilo CpHeapBunkerSilo
function AIDriveStrategyShovelSiloLoader:setSiloAndHeap(bunkerSilo, heapSilo)
    self.bunkerSilo = bunkerSilo
    self.heapSilo = heapSilo
end

---@param unloadTrigger CpTrigger
---@param unloadStation table
function AIDriveStrategyShovelSiloLoader:setUnloadTriggerAndStation(unloadTrigger, unloadStation)
    self.unloadTrigger = unloadTrigger
    self.unloadStation = unloadStation
end

function AIDriveStrategyShovelSiloLoader:startWithoutCourse(jobParameters)

    -- to always have a valid course (for the traffic conflict detector mainly)
    self.course = Course.createStraightForwardCourse(self.vehicle, 25)
    self:startCourse(self.course, 1)

    self.jobParameters = jobParameters
    self.unloadPositionNode = CpUtil.createNode("unloadPositionNode", 0, 0, 0)

    --- Is the unload target a trailer?
    self.isUnloadingAtTrailerActive = jobParameters.unloadAt:getValue() == CpSiloLoaderJobParameters.UNLOAD_TRAILER
    if not self.isUnloadingAtTrailerActive then
        self:debug("Starting shovel silo to unload into unload trigger.")
        --- Uses the exactFillRootNode from the trigger 
        --- and the direction of the unload position marker
        --- to place the unload position node slightly in front.
        local x, y, z = getWorldTranslation(self.unloadTrigger:getFillUnitExactFillRootNode(1))
        setTranslation(self.unloadPositionNode, x, y, z)
        ---@type CpAIParameterPositionAngle
        local position = jobParameters.unloadPosition
        local dirX, dirZ = position:getDirection()
        setDirection(self.unloadPositionNode, dirX, 0, dirZ, 0, 0, 1)
        local dx, dy, dz = localToWorld(self.unloadPositionNode, 0, 0, -math.max(
                self.distShovelUnloadStationPreUnload, self.turningRadius, 1.5 * AIUtil.getLength(self.vehicle)))
        setTranslation(self.unloadPositionNode, dx, dy, dz)
    else
        self:debug("Starting shovel silo to unload into trailer.")
        ---@type CpAIParameterPositionAngle
        local position = jobParameters.unloadPosition
        local _
        _, self.trailerSearchArea = CpAIJobSiloLoader.getTrailerUnloadArea(position)

    end
    local siloAreaOffset
    if self.bunkerSilo ~= nil then
        self:debug("Bunker silo was found.")
        self.silo = self.bunkerSilo
        siloAreaOffset = self.siloAreaToAvoidForBunkerSiloOffsets
    else
        self:debug("Heap was found.")
        self.silo = self.heapSilo
        siloAreaOffset = self.siloAreaToAvoidForHeapOffsets
    end
    local cx, cz = self.silo:getFrontCenter()
    local dirX, dirZ = self.silo:getLengthDirection()
    local yRot = MathUtil.getYRotationFromDirection(dirX, dirZ)
    self.siloFrontNode = CpUtil.createNode("siloFrontNode", cx, cz, yRot)

    self.siloAreaToAvoid = PathfinderUtil.NodeArea(self.siloFrontNode, -self.silo:getWidth() / 2 - siloAreaOffset.width,
            -siloAreaOffset.length, self.silo:getWidth() + 2 * siloAreaOffset.width,
            self.silo:getLength() + 2 * siloAreaOffset.length)
    --- fill level, when the driver is started
    self.fillLevelLeftOverSinceStart = self.silo:getTotalFillLevel()

    self.siloController = CpBunkerSiloLoaderController(self.silo, self.vehicle, self)

    self.vehicle:raiseAIEvent("onAIFieldWorkerStart", "onAIImplementStart")
end

-----------------------------------------------------------------------------------------------------------------------
--- Implement handling
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyShovelSiloLoader:initializeImplementControllers(vehicle)
    self:addImplementController(vehicle, MotorController, Motorized, {}, nil)
    self:addImplementController(vehicle, WearableController, Wearable, {}, nil)
    ---@type table, ShovelController
    self.shovelImplement, self.shovelController = self:addImplementController(vehicle, ShovelController, Shovel, {}, nil)

end

--- Fuel save only allowed when no trailer is there to unload into.
function AIDriveStrategyShovelSiloLoader:isFuelSaveAllowed()
    return self.state == self.states.WAITING_FOR_TRAILER or AIDriveStrategyCourse.isFuelSaveAllowed(self)
end

-----------------------------------------------------------------------------------------------------------------------
--- Static parameters (won't change while driving)
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyShovelSiloLoader:setAllStaticParameters()
    self.reverser = AIReverseDriver(self.vehicle, self.ppc)
    self.proximityController = ProximityController(self.vehicle, self:getWorkWidth())
    self.proximityController:registerIgnoreObjectCallback(self, self.ignoreProximityObject)
    Markers.setMarkerNodes(self.vehicle)
    self.frontMarkerNode, self.backMarkerNode, self.frontMarkerDistance, self.backMarkerDistance = Markers.getMarkerNodes(self.vehicle)
    self.siloEndProximitySensor = SingleForwardLookingProximitySensorPack(self.vehicle, self.shovelController:getShovelNode(), 1, 1)
    self.heapNode = CpUtil.createNode("heapNode", 0, 0, 0, nil)
    self.lastTrailerSearch = 0
    self.isStuckTimer = Timer.new(self.isStuckMs)
    self.isStuckTimer:setFinishCallback(function()
        if self.frozen then
            return
        end
        if self.state == self.states.DRIVING_INTO_SILO then
            self:debug("Was stuck trying to drive into the bunker silo.")
            self:startDrivingOutOfSilo()
            self:setNewState(self.states.DRIVING_TEMPORARY_OUT_OF_SILO)
        end
    end)
end

-----------------------------------------------------------------------------------------------------------------------
--- Event listeners
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyShovelSiloLoader:onWaypointPassed(ix, course)
    if course:isLastWaypointIx(ix) then
        if self.state == self.states.DRIVING_ALIGNMENT_COURSE then
            local course = self:getRememberedCourseAndIx()
            self:startCourse(course, 1)
            self:setNewState(self.states.DRIVING_INTO_SILO)
        elseif self.state == self.states.DRIVING_INTO_SILO then
            self:startDrivingOutOfSilo()
        elseif self.state == self.states.DRIVING_OUT_OF_SILO then
            if self.isUnloadingAtTrailerActive then
                self:setNewState(self.states.WAITING_FOR_TRAILER)
            else
                self:startPathfindingToUnloadPosition()
            end
        elseif self.state == self.states.DRIVING_TEMPORARY_OUT_OF_SILO then
            self:startDrivingToSilo({ self.siloController:getLastTarget() })
        elseif self.state == self.states.DRIVING_TO_UNLOAD_TRAILER then
            self:approachTrailerForUnloading()
        elseif self.state == self.states.DRIVING_TO_UNLOAD_POSITION then
            self:approachUnloadStationForUnloading()
        elseif self.state == self.states.DRIVING_TO_UNLOAD then
            self:setNewState(self.states.UNLOADING)
        elseif self.state == self.states.REVERSING_AWAY_FROM_UNLOAD then
            if self.shovelController:isEmpty() then
                self:startDrivingToSilo()
            else
                self:setNewState(self.states.WAITING_FOR_TRAILER)
            end
        end
    end
end

--- this the part doing the actual work on the field after/before all
--- implements are started/lowered etc.
function AIDriveStrategyShovelSiloLoader:getDriveData(dt, vX, vY, vZ)
    self:updateLowFrequencyImplementControllers()
    self:updateLowFrequencyPathfinder()
    local moveForwards = not self.ppc:isReversing()
    local gx, gz, _
    if not moveForwards then
        local maxSpeed
        gx, gz, maxSpeed = self:getReverseDriveData()
        self:setMaxSpeed(maxSpeed)
    else
        gx, _, gz = self.ppc:getGoalPointPosition()
    end
    if self.state == self.states.INITIAL then
        if self.silo:getTotalFillLevel() <= 0 then
            self:debug("Stopping the driver, as the silo is empty.")
            self.vehicle:stopCurrentAIJob(AIMessageSuccessFinishedJob.new())
            return
        end
        if self.shovelController:isFull() then
            if self.isUnloadingAtTrailerActive then
                self:setNewState(self.states.WAITING_FOR_TRAILER)
            else
                self:startPathfindingToUnloadPosition()
            end
        else
            self:startDrivingToSilo()
        end
        self:setMaxSpeed(0)
    elseif self.state == self.states.DRIVING_ALIGNMENT_COURSE then
        self:setMaxSpeed(self.settings.fieldSpeed:getValue())
    elseif self.state == self.states.WAITING_FOR_PATHFINDER then
        self:setMaxSpeed(0)
    elseif self.state == self.states.DRIVING_INTO_SILO then
        self:setMaxSpeed(self.settings.bunkerSiloSpeed:getValue())
        if AIUtil.isStopped(self.vehicle) and not self.proximityController:isStopped() then
            --- Updates the is stuck timer
            self.isStuckTimer:startIfNotRunning()
        else 
            self.isStuckTimer:stop()
        end
        local _, _, closestObject = self.siloEndProximitySensor:getClosestObjectDistanceAndRootVehicle()
        local isEndReached, maxSpeed = self.siloController:isEndReached(self.shovelController:getShovelNode(), 2)
        self:setMaxSpeed(maxSpeed)
        if isEndReached then
            self:debug("End of the silo or heap was detected.")
            self:startDrivingOutOfSilo()
        elseif self.silo:isTheSameSilo(closestObject) and self.silo:isNodeInSilo(self.shovelController:getShovelNode()) then
            self:debug("End wall of the silo was detected.")
            self:startDrivingOutOfSilo()
        end
        if self.shovelController:isFull() then
            self:debug("Shovel is full, starting to drive out of the silo.")
            self:startDrivingOutOfSilo()
        end
    elseif self.state == self.states.DRIVING_OUT_OF_SILO then
        self:setMaxSpeed(self.settings.bunkerSiloSpeed:getValue())
    elseif self.state == self.states.DRIVING_TEMPORARY_OUT_OF_SILO then
        self:setMaxSpeed(self.settings.bunkerSiloSpeed:getValue())
    elseif self.state == self.states.DRIVING_TO_UNLOAD_POSITION then
        self:setMaxSpeed(self.settings.fieldSpeed:getValue())
    elseif self.state == self.states.DRIVING_TO_UNLOAD_TRAILER then
        self:setMaxSpeed(self.settings.fieldSpeed:getValue())
    elseif self.state == self.states.WAITING_FOR_TRAILER then
        self:setMaxSpeed(0)
        if (g_time - self.lastTrailerSearch) > self.searchForTrailerDelaySec * 1000 then
            self:searchForTrailerToUnloadInto()
            self.lastTrailerSearch = g_time
        end
    elseif self.state == self.states.DRIVING_TO_UNLOAD then
        self:setMaxSpeed(self.settings.reverseSpeed:getValue())
        local refNode
        if self.isUnloadingAtTrailerActive then
            refNode = self.targetTrailer.exactFillRootNode
        else
            refNode = self.unloadTrigger:getFillUnitExactFillRootNode(1)
        end
        if self.shovelController:isShovelOverTrailer(refNode) then
            self:setNewState(self.states.UNLOADING)
            self:setMaxSpeed(0)
        end
        if not self.isUnloadingAtTrailerActive then
            if self.shovelController:isShovelOverTrailer(refNode, 3) and self.shovelController:canDischarge(self.unloadTrigger) then
                self:setNewState(self.states.UNLOADING)
                self:setMaxSpeed(0)
            end
        end
    elseif self.state == self.states.UNLOADING then
        self:setMaxSpeed(0)
        if self:hasFinishedUnloading() then
            self:startReversingAwayFromUnloading()
        end
    elseif self.state == self.states.REVERSING_AWAY_FROM_UNLOAD then
        self:setMaxSpeed(self.settings.fieldSpeed:getValue())
    end
    if self.state.properties.shovelPosition then
        if not self.frozen and self.shovelController:moveShovelToPosition(self.state.properties.shovelPosition) then
            if self.state.properties.shovelMovingSpeed ~= nil then
                self:setMaxSpeed(self.state.properties.shovelMovingSpeed)
            end
        end
    end
    self:limitSpeed()
    self:checkProximitySensors(moveForwards)
    return gx, gz, moveForwards, self.maxSpeed, 100
end

function AIDriveStrategyShovelSiloLoader:update(dt)
    if CpDebug:isChannelActive(CpDebug.DBG_SILO, self.vehicle) then
        if self.course:isTemporary() then
            self.course:draw()
        elseif self.ppc:getCourse():isTemporary() then
            self.ppc:getCourse():draw()
        end
        if self.silo then
            self.silo:drawDebug()
            self.siloAreaToAvoid:drawDebug()
        end
        self.siloController:draw()
        if self.heapSilo then
            CpUtil.drawDebugNode(self.heapNode, false, 3)
        end
        if self.targetTrailer then
            CpUtil.drawDebugNode(self.targetTrailer.exactFillRootNode, false, 3, "ExactFillRootNode")
        end
        CpUtil.drawDebugNode(self.unloadPositionNode, false, 3)
    end
    self:updateImplementControllers(dt)
    AIDriveStrategyCourse.update(self)
end

function AIDriveStrategyShovelSiloLoader:updateCpStatus(status)
    status:setSiloLoaderStatus(self.silo:getTotalFillLevel(), self.fillLevelLeftOverSinceStart)
end

--- Ignores the bunker silo and the unload target for the proximity sensors.
function AIDriveStrategyShovelSiloLoader:ignoreProximityObject(object, vehicle)
    if self.silo:isTheSameSilo(object) then
        return true
    end
    --- This ignores the terrain.
    if object == nil then
        return true
    end
    if object == self.unloadStation then
        return true
    end
    if self.unloadTrigger and self.unloadTrigger:isTheSameObject(object) then
        return true
    end
    if self.targetTrailer then
        if object == self.targetTrailer.trailer then
            return true
        end
    end
    return false
end

function AIDriveStrategyShovelSiloLoader:getProximitySensorWidth()
    -- a bit less as size.width always has plenty of buffer
    return self.vehicle.size.width - 0.5
end

function AIDriveStrategyShovelSiloLoader:getWorkWidth()
    return self.settings.bunkerSiloWorkWidth:getValue()
end

function AIDriveStrategyShovelSiloLoader:setNewState(newState)
    self:debug("Changed State from %s to %s", self.state.name, newState.name)
    self.state = newState
end

--- Checks if a valid target was found, which means either a trailer or a manure spreader.
---@param trailer table
---@return boolean
function AIDriveStrategyShovelSiloLoader:hasTrailerValidSpecializations(trailer)
    if SpecializationUtil.hasSpecialization(Trailer, trailer.specializations) then
        --- All normal trailers
        return true
    end
    if SpecializationUtil.hasSpecialization(Sprayer, trailer.specializations) then
        --- Sprayers
        return true
    end
    if SpecializationUtil.hasSpecialization(MixerWagon, trailer.specializations) then
        --- Mixer wagon
        return true
    end
    if trailer["spec_pdlc_goeweilPack.balerStationary"] then 
        --- Goeweil 
        return true
    end

    return false
end

--- Is the trailer valid or not?
---@param trailer table
---@param trailerToIgnore table|nil
---@return boolean
---@return table|nil
function AIDriveStrategyShovelSiloLoader:isValidTrailer(trailer, trailerToIgnore)
    local function debug(...)
        self:debug("%s attached to: %s => %s", CpUtil.getName(trailer),
                trailer.rootVehicle and CpUtil.getName(trailer.rootVehicle) or "no root vehicle", string.format(...))
    end
    if not self:hasTrailerValidSpecializations(trailer) then
        debug("has not valid specializations setup")
        return false
    end
    if trailer.rootVehicle and not AIUtil.isStopped(trailer.rootVehicle) then
        debug("is not stopped!")
        return false
    end
    if trailerToIgnore and table.hasElement(trailerToIgnore, trailer) then
        debug("will be ignored!")
        return false
    end
    local canLoad, fillUnitIndex, fillType, exactFillRootNode = ImplementUtil.getCanLoadTo(trailer, self.shovelImplement,
            nil, debug)
    if not canLoad then
        debug("can't be used!")
        return false
    end
    return true, { fillUnitIndex = fillUnitIndex,
                   fillType = fillType,
                   exactFillRootNode = exactFillRootNode,
                   trailer = trailer }
end

--- Gets the closest trailer data with the distance
---@param trailerToIgnore table|nil optional trailers that will be ignored.
---@return table|nil
---@return number
function AIDriveStrategyShovelSiloLoader:getClosestTrailerAndDistance(trailerToIgnore)
    local closestDistance = math.huge
    local closestTrailerData = nil
    for i, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        local x, _, z = getWorldTranslation(vehicle.rootNode)
        if CpMathUtil.isPointInPolygon(self.trailerSearchArea, x, z) then
            local dist = calcDistanceFrom(vehicle.rootNode, self.siloFrontNode)
            if dist < closestDistance then
                local valid, trailerData = self:isValidTrailer(vehicle, trailerToIgnore)
                if valid then
                    closestDistance = dist
                    closestTrailerData = trailerData
                end
            end
        end
    end
    return closestTrailerData, closestDistance
end

--- Searches for trailer to unload into in a maximum radius relative to the silo front center.
function AIDriveStrategyShovelSiloLoader:searchForTrailerToUnloadInto()
    self:debug("Searching for an trailer nearby.")
    local trailerData, dist = self:getClosestTrailerAndDistance({})
    if not trailerData then
        self:debug("No valid trailer found anywhere!")
        self:setInfoText(InfoTextManager.WAITING_FOR_UNLOADER)
        return
    end
    local trailer = trailerData.trailer
    self:clearInfoText(InfoTextManager.WAITING_FOR_UNLOADER)
    --- Sets the unload position node in front of the closest side of the trailer.
    self:debug("Found a valid trailer %s within distance %.2f", CpUtil.getName(trailer), dist)
    self.targetTrailer = trailerData
    local _, _, distShovelDirectionNode = localToLocal(self.shovelController:getShovelNode(), self.vehicle:getAIDirectionNode(), 0, 0, 0)
    local dirX, _, dirZ = localDirectionToWorld(trailer.rootNode, 0, 0, 1)
    local yRot = MathUtil.getYRotationFromDirection(dirX, dirZ)
    local dx, _, dz = localToLocal(self.shovelController:getShovelNode(), trailer.rootNode, 0, 0, 0)
    local distRootNodeToExactFillRootNode = calcDistanceFrom(trailer.rootNode, trailerData.exactFillRootNode)
    if dx > 0 then
        local x, y, z = localToWorld(trailer.rootNode, math.abs(distShovelDirectionNode) + self.distShovelTrailerPreUnload, 0, 0)
        setTranslation(self.unloadPositionNode, x, y, z)
        setRotation(self.unloadPositionNode, 0, MathUtil.getValidLimit(yRot - math.pi / 2), 0)
    else
        local x, y, z = localToWorld(trailer.rootNode, -math.abs(distShovelDirectionNode) - self.distShovelTrailerPreUnload, 0, 0)
        setTranslation(self.unloadPositionNode, x, y, z)
        setRotation(self.unloadPositionNode, 0, MathUtil.getValidLimit(yRot + math.pi / 2), 0)
    end
    if trailer["spec_pdlc_goeweilPack.balerStationary"] or trailer.size.length < 4 then 
        --- Goeweil needs to be approached from behind
        local x, y, z = localToWorld(trailer.rootNode, 0, 0, - math.abs(distShovelDirectionNode) - distRootNodeToExactFillRootNode - self.distShovelTrailerPreUnload)
        setTranslation(self.unloadPositionNode, x, y, z)
        setRotation(self.unloadPositionNode, 0, yRot, 0)
    end
    self:startPathfindingToTrailer()
end

----------------------------------------------------------------
--- Pathfinding
----------------------------------------------------------------

--- Pathfinding has finished
---@param controller PathfinderController
---@param success boolean
---@param course Course|nil
---@param goalNodeInvalid boolean|nil
function AIDriveStrategyShovelSiloLoader:onPathfindingFinished(controller, 
    success, course, goalNodeInvalid)
    if not success then
        self:debug('Pathfinding failed, giving up!')
        self.vehicle:stopCurrentAIJob(AIMessageCpErrorNoPathFound.new())
        return
    end
    if self.state == self.states.DRIVING_ALIGNMENT_COURSE then 
        course:adjustForTowedImplements(2)
        self:startCourse(course, 1)
    elseif self.state == self.states.DRIVING_TO_UNLOAD_POSITION then 
        course:adjustForTowedImplements(2)
        self:startCourse(course, 1)
    elseif self.state == self.states.DRIVING_TO_UNLOAD_TRAILER then 
        course:adjustForTowedImplements(2)
        self:startCourse(course, 1)
    end
end

--- Pathfinding failed, but a retry attempt is leftover.
---@param controller PathfinderController
---@param lastContext PathfinderContext
---@param wasLastRetry boolean
---@param currentRetryAttempt number
function AIDriveStrategyShovelSiloLoader:onPathfindingFailed(controller,
    lastContext, wasLastRetry, currentRetryAttempt)
    --- TODO: Think of possible points of failures, that could be adjusted here.
    ---       Maybe a small reverse course might help to avoid a deadlock
    ---       after one pathfinder failure based on proximity sensor data and so on ..
    if self.state == self.states.DRIVING_ALIGNMENT_COURSE then 
        local course = self:getRememberedCourseAndIx()
        local fm = self:getFrontAndBackMarkers()
        lastContext:ignoreFruit()
        controller:findPathToWaypoint(lastContext, course, 
            1, 0, -(fm + 4), 1)
    elseif self.state == self.states.DRIVING_TO_UNLOAD_POSITION then 
        self:startPathfindingToUnloadPosition()
    elseif self.state == self.states.DRIVING_TO_UNLOAD_TRAILER then 
        self:startPathfindingToTrailer()
    end
end

--- Find an alignment path to the silo lane course.
---@param course table silo lane course
function AIDriveStrategyShovelSiloLoader:startPathfindingToStart(course)
    self:setNewState(self.states.DRIVING_ALIGNMENT_COURSE)
    self:rememberCourse(course, 1)
    local fm = self:getFrontAndBackMarkers()
    local context = PathfinderContext(self.vehicle):allowReverse(true):areaToAvoid(self.siloAreaToAvoid)
    self.pathfinderController:findPathToWaypoint(context, course, 
        1, 0, -(fm + 4), 1)
end

--- Starts Pathfinding to the position node in front of a unload trigger.
function AIDriveStrategyShovelSiloLoader:startPathfindingToUnloadPosition()
    self:setNewState(self.states.DRIVING_TO_UNLOAD_POSITION)
    local context = PathfinderContext(self.vehicle):areaToAvoid(self.siloAreaToAvoid)
        context:mustBeAccurate(false):allowReverse(true):offFieldPenalty(0)
    self.pathfinderController:findPathToNode(context, self.unloadPositionNode, 
        0, 0, 1)
end


--- Starts Pathfinding to the position node in front of the trailer side.  
function AIDriveStrategyShovelSiloLoader:startPathfindingToTrailer()
    self:setNewState(self.states.DRIVING_TO_UNLOAD_TRAILER)
    local context = PathfinderContext(self.vehicle):areaToAvoid(self.siloAreaToAvoid)
        context:mustBeAccurate(false):allowReverse(true):offFieldPenalty(0)
    self.pathfinderController:findPathToNode(context, self.unloadPositionNode, 
        0, 0, 1)
end

----------------------------------------------------------------
--- Silo work
----------------------------------------------------------------

--- Starts driving into the silo lane
function AIDriveStrategyShovelSiloLoader:startDrivingToSilo(target)
    --- Creates a straight course in the silo.
    local startPos, endPos
    if target then
        startPos, endPos = unpack(target)
    else
        startPos, endPos = self.siloController:getTarget(self:getWorkWidth())
    end
    local x, z = unpack(startPos)
    local dx, dz = unpack(endPos)
    local siloCourse = Course.createFromTwoWorldPositions(self.vehicle, x, z, dx, dz,
            0, -5, 3, 3, false)
    local vx, _, vz = getWorldTranslation(AIUtil.getDirectionNode(self.vehicle))
    local dx, _, dz = siloCourse:worldToWaypointLocal(1, vx, 0, vz)
    if dz < 0 and dz > -self.maxDistanceWithoutPathfinding and 
        math.abs(dx) <= math.abs(dz) and 
        math.abs(dx) < self.maxDistanceWithoutPathfinding * math.sqrt(2)/2 then 
        --[[
            |...|
            |...|   <- Silo
            -----
              x     <- Target waypoint
            ooooo
           ooooooo  <- Circle, where the pathfinding is skipped.
            ooooo
              o
        ]]--  
        -- TODO: Beautify the math above :) 
        self:debug("Start driving into the silo directly.")
        self:startCourse(siloCourse, 1)
        self:setNewState(self.states.DRIVING_INTO_SILO)
    else
        self:debug("Start driving to silo with pathfinder.")
        self:startPathfindingToStart(siloCourse)
    end
end

function AIDriveStrategyShovelSiloLoader:startDrivingOutOfSilo()
    --- Creates the straight reverse course.
    local startPos, endPos = self.siloController:getLastTarget()
    local x, z = unpack(endPos)
    local dx, dz = unpack(startPos)
    local reverseCourse = Course.createFromTwoWorldPositions(self.vehicle, x, z, dx, dz,
            0, 0, 6, 3, true)
    local ix = reverseCourse:getNextRevWaypointIxFromVehiclePosition(1, self.vehicle:getAIDirectionNode(), 10)
    if ix == 1 then
        ix = reverseCourse:getNumberOfWaypoints()
    end
    self:startCourse(reverseCourse, ix)
    self:setNewState(self.states.DRIVING_OUT_OF_SILO)
    self.isStuckTimer:stop()
end

--- Drives from the position node in front of the trailer to the trailer, so the unloading can begin after that.
function AIDriveStrategyShovelSiloLoader:approachTrailerForUnloading()
    local dx, _, dz = getWorldTranslation(self.targetTrailer.exactFillRootNode)
    local x, _, z = getWorldTranslation(self.vehicle:getAIDirectionNode())
    local course = Course.createFromTwoWorldPositions(self.vehicle, x, z, dx, dz,
            0, -3, 0, 3, false)
    local firstWpIx = course:getNearestWaypoints(self.vehicle:getAIDirectionNode())
    self:startCourse(course, firstWpIx)
    self:setNewState(self.states.DRIVING_TO_UNLOAD)
    if self.targetTrailer.trailer["spec_pdlc_goeweilPack.balerStationary"] then
        --- Minimal height calculation is not working for Goeweil balers
        self.shovelController:setMinimalUnloadingHeight(2.5)
    else
        self.shovelController:calculateMinimalUnloadingHeight(self.targetTrailer.exactFillRootNode)
    end
end

--- Drives from the position node in front of the trigger to the unload trigger, so the unloading can begin after that.
function AIDriveStrategyShovelSiloLoader:approachUnloadStationForUnloading()
    local dx, _, dz = getWorldTranslation(self.unloadTrigger:getFillUnitExactFillRootNode())
    local x, _, z = getWorldTranslation(self.vehicle:getAIDirectionNode())
    local course = Course.createFromTwoWorldPositions(self.vehicle, x, z, dx, dz,
            0, -3, 3, 2, false)
    local firstWpIx = course:getNearestWaypoints(self.vehicle:getAIDirectionNode())
    self:startCourse(course, firstWpIx)
    self:setNewState(self.states.DRIVING_TO_UNLOAD)
    self.shovelController:calculateMinimalUnloadingHeight(self.unloadTrigger:getFillUnitExactFillRootNode())
end

----------------------------------------------------------------
--- Unloading
----------------------------------------------------------------

--- Is the unloading finished?
---@return boolean
function AIDriveStrategyShovelSiloLoader:hasFinishedUnloading()
    if self.shovelController:isEmpty() then
        self:debug("Finished unloading, as the shovel is empty.")
        return true
    end
    if self.isUnloadingAtTrailerActive then
        if self.targetTrailer.trailer:getFillUnitFreeCapacity(self.targetTrailer.fillUnitIndex) <= 0 then
            self:debug("Trailer is full, abort unloading into trailer %s.", CpUtil.getName(self.targetTrailer.trailer))
            self.targetTrailer = nil
            return true
        end
    else
        if self.unloadTrigger:getFillUnitFreeCapacity(1, self.shovelController:getDischargeFillType(), self.vehicle:getOwnerFarmId()) <= 0 then
            self:debugSparse("Unload Trigger is full.")
        end
    end
    return false
end

--- Starts reverse straight to make some space to the trailer or unload trigger.
function AIDriveStrategyShovelSiloLoader:startReversingAwayFromUnloading()
    local _, _, spaceToTrailer = localToLocal(self.shovelController:getShovelNode(), self.vehicle:getAIDirectionNode(), 0, 0, 0)
    local course = Course.createStraightReverseCourse(self.vehicle, 1.5 * spaceToTrailer + self.turningRadius,
            0, self.vehicle:getAIDirectionNode())
    self:startCourse(course, 1)
    self:setNewState(self.states.REVERSING_AWAY_FROM_UNLOAD)
end

--- The hud trigger of an mixer wagon has the same collision flag as an vehicle,
--- so we need to explicitly ignore this trigger for the pathfinder. 
local function addMixerWagonTriggers(mixerWagon)
    local spec = mixerWagon.spec_mixerWagon
    if spec.hudTrigger then 
        PathfinderUtil.CollisionDetector.addNodeToIgnore(spec.hudTrigger)
    end
end
MixerWagon.onLoad = Utils.appendedFunction(MixerWagon.onLoad, addMixerWagonTriggers)

local function deleteMixerWagonTrigger(mixerWagon)
    local spec = mixerWagon.spec_mixerWagon
    if spec.hudTrigger then 
        PathfinderUtil.CollisionDetector.removeNodeToIgnore(spec.hudTrigger)
    end
end
MixerWagon.onDelete = Utils.prependedFunction(MixerWagon.onDelete, deleteMixerWagonTrigger)
