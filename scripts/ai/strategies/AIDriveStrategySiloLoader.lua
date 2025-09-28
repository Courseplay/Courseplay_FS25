--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2022 

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


--- Controls an stationary loader for loading of a heap or in a bunker silo.
--- The driver only drives to the silo/heap start and 
--- then start working it's way to the end of the line and finishes the job.
---@class AIDriveStrategySiloLoader : AIDriveStrategyCourse
---@field heapNode number
---@field shovelController ShovelController
---@field conveyorController ConveyorController
AIDriveStrategySiloLoader = CpObject(AIDriveStrategyCourse)

AIDriveStrategySiloLoader.myStates = {
    DRIVING_ALIGNMENT_COURSE = {},
    WAITING_FOR_PREPARING = {},
    WORKING = {},
    FINISHED_WORKING = {}
}
AIDriveStrategySiloLoader.distanceOverFieldEdgeAllowed = 25
AIDriveStrategySiloLoader.siloAreaOffsetFieldUnload = 10

AIDriveStrategySiloLoader.maxDistanceWithoutPathfinding = 10

function AIDriveStrategySiloLoader:init(task, job)
    AIDriveStrategyCourse.init(self, task, job)
    AIDriveStrategyCourse.initStates(self, AIDriveStrategySiloLoader.myStates)
    self.state = self.states.WAITING_FOR_PREPARING
    self.heapNode = CpUtil.createNode("heapNode", 0, 0, 0, nil)
end

function AIDriveStrategySiloLoader:delete()
    AIDriveStrategyCourse.delete(self)
    if self.bunkerSiloController then
        self.bunkerSiloController:delete()
        self.bunkerSiloController = nil
    end
    if self.heapNode then
        CpUtil.destroyNode(self.heapNode)
    end
end

function AIDriveStrategySiloLoader:getGeneratedCourse(jobParameters)
    return nil
end

function AIDriveStrategySiloLoader:setSiloAndHeap(bunkerSilo, heapSilo)
    self.bunkerSilo = bunkerSilo
    self.heapSilo = heapSilo
end

function AIDriveStrategySiloLoader:startWithoutCourse(jobParameters)
    -- to always have a valid course (for the traffic conflict detector mainly)
    self:startCourse(Course.createStraightForwardCourse(self.vehicle, 5, 0, nil), 1)

    self.jobParameters = jobParameters

    local x, z, dx, dz
    if self.bunkerSilo ~= nil then
        self:debug("Bunker silo was found.")
        self.silo = self.bunkerSilo
        --- Only used to calculate the correct path into the silo.
        self.bunkerSiloController = CpBunkerSiloLoaderController(self.silo, self.vehicle, self)
        local startPos, endPos = self.bunkerSiloController:getTarget(self:getWorkWidth())
        x, z = unpack(startPos)
        dx, dz = unpack(endPos)
        --- TODO: apply offset, if the silo is not filled equally to both sides.
    else
        self:debug("Heap was found.")
        self.silo = self.heapSilo
        --self:updateLoadPositionByHeapSilo()
        x, z = self.silo:getFrontCenter()
        dx, dz = self.silo:getBackCenter()
    end

    --- fill level, when the driver is started
    self.fillLevelLeftOverSinceStart = self.silo:getTotalFillLevel()

    local siloCourse = Course.createFromTwoWorldPositions(self.vehicle, x, z, dx, dz,
            0, 0, 3, 3, false)

    local vx, _, vz = getWorldTranslation(AIUtil.getDirectionNode(self.vehicle))
    local dx, _, dz = siloCourse:worldToWaypointLocal(1, vx, 0, vz)
    if dz < 5 and dz > -self.maxDistanceWithoutPathfinding and
            math.abs(dx) <= math.abs(dz) and
            math.abs(dx) < self.maxDistanceWithoutPathfinding * math.sqrt(2) / 2 then
        --[[
            |...|
            |...|   <- Silo
            --x--   <- Target waypoint
            ooooo
           ooooooo  <- Circle, where the pathfinding is skipped.
            ooooo
              o
        ]]--  
        -- TODO: Beautify the math above :) 
        self:debug("Start driving into the silo directly.")
        self:startCourse(siloCourse, 1)
        self.vehicle:raiseAIEvent("onAIFieldWorkerStart", "onAIImplementStart")
        self:lowerImplements()
    else
        self:debug("Start driving to silo with pathfinder.")
        self:startPathfindingToStart(siloCourse)
    end
end

--- Moves the field unload position to the center front of the heap.
function AIDriveStrategySiloLoader:updateLoadPositionByHeapSilo()
    local sx, sz = self.silo:getStartPosition()
    local wx, wz = self.silo:getWidthPosition()
    local dirX, dirZ, siloWidth = CpMathUtil.getPointDirection({ x = sx, z = sz }, { x = wx, z = wz })
    local cx, cz = sx + dirX * siloWidth / 2, sz + dirZ * siloWidth / 2
    setTranslation(self.heapNode, cx, 0, cz)
    local dirX, dirZ = self.silo:getLengthDirection()
    local yRot = MathUtil.getYRotationFromDirection(dirX, dirZ)
    setWorldRotation(self.heapNode, 0, yRot, 0)
    --- Move the position a little bit inwards.
    local x, _, z = localToWorld(self.heapNode, 0, 0, 3)
    local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z) + 3
    setTranslation(self.heapNode, x, y, z)
end

-----------------------------------------------------------------------------------------------------------------------
--- Implement handling
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategySiloLoader:initializeImplementControllers(vehicle)
    self:addImplementController(vehicle, MotorController, Motorized, {}, nil)
    self:addImplementController(vehicle, WearableController, Wearable, {}, nil)
    self:addImplementController(vehicle, FoldableController, Foldable, {})
    local _
    _, self.conveyorController = self:addImplementController(vehicle, ConveyorController, ConveyorBelt, {}, nil)
    _, self.shovelController = self:addImplementController(vehicle, ShovelController, Shovel, {}, nil)

    self.siloEndProximitySensor = SingleForwardLookingProximitySensorPack(self.vehicle, self.shovelController:getShovelNode(), 5, 1)
end

--- Fuel save only allowed when no trailer is there to unload into.
function AIDriveStrategySiloLoader:isFuelSaveAllowed()
    return self.state == self.states.WORKING and not self.conveyorController:canDischargeToObject()
        or AIDriveStrategyCourse.isFuelSaveAllowed(self)
end

-----------------------------------------------------------------------------------------------------------------------
--- Static parameters (won't change while driving)
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategySiloLoader:setAllStaticParameters()
    AIDriveStrategyCourse.setAllStaticParameters(self)
    self.reverser = AIReverseDriver(self.vehicle, self.ppc)
    self.proximityController = ProximityController(self.vehicle, self:getWorkWidth())

    self:setFrontAndBackMarkers()

    -- distance to keep to the right (>0) or left (<0) when pulling back to make room for the tractor
    self.pullBackRightSideOffset = math.abs(self.conveyorController:getPipeOffsetX()) - self:getWorkWidth() / 2 + 5
    self.pullBackRightSideOffset = self:isPipeOnLeft() and self.pullBackRightSideOffset or -self.pullBackRightSideOffset
    -- should be at pullBackRightSideOffset to the right or left at pullBackDistanceStart
    self.pullBackDistanceStart = 2 * AIUtil.getTurningRadius(self.vehicle)
    -- and back up another bit
    self.pullBackDistanceEnd = self.pullBackDistanceStart + 5
    -- when making a pocket, how far to back up before changing to forward
    self.pocketReverseDistance = 20

    --- My unloader. This expires in a few seconds, so unloaders have to renew their registration periodically
    ---@type CpTemporaryObject
    self.unloader = CpTemporaryObject(nil)
    -- periodically check if we need to call an unloader
    self.timeToCallUnloader = CpTemporaryObject(true)
    -- hold the harvester temporarily
    self.temporaryHold = CpTemporaryObject(false)
    --- if this is not nil, we have a pending rendezvous with our unloader
    ---@type CpTemporaryObject
    self.unloaderToRendezvous = CpTemporaryObject(nil)

    self.waitingForUnloaderAtEndOfRow = CpTemporaryObject()
end

-----------------------------------------------------------------------------------------------------------------------
--- Event listeners
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategySiloLoader:onWaypointPassed(ix, course)
    if course:isLastWaypointIx(ix) then
        if self.state == self.states.DRIVING_ALIGNMENT_COURSE then
            local course = self:getRememberedCourseAndIx()
            self:startCourse(course, 1)
            self.state = self.states.WAITING_FOR_PREPARING
            self.vehicle:raiseAIEvent("onAIFieldWorkerStart", "onAIImplementStart")
            self:lowerImplements()
        elseif self.state == self.states.WORKING then
            self.state = self.states.FINISHED_WORKING
        end
    end
end

--- this the part doing the actual work on the field after/before all
--- implements are started/lowered etc.
function AIDriveStrategySiloLoader:getDriveData(dt, vX, vY, vZ)
    self:updateLowFrequencyImplementControllers()
    self:updateLowFrequencyPathfinder()
    local moveForwards = not self.ppc:isReversing()
    local gx, gz

    ----------------------------------------------------------------
    if not moveForwards then
        local maxSpeed
        gx, gz, maxSpeed = self:getReverseDriveData()
        self:setMaxSpeed(maxSpeed)
    else
        gx, _, gz = self.ppc:getGoalPointPosition()
    end

    if self.state == self.states.DRIVING_ALIGNMENT_COURSE then
        self:setMaxSpeed(self.settings.fieldSpeed:getValue())
    elseif self.state == self.states.WAITING_FOR_PREPARING then
        self:setMaxSpeed(0)
        self:prepareForStart()
    elseif self.state == self.states.WAITING_FOR_PATHFINDER then
        self:setMaxSpeed(0)
    elseif self.state == self.states.WORKING then

        self:setMaxSpeed(self.settings.reverseSpeed:getValue() * (1 - self.shovelController:getFillLevelPercentage() / 100))
        if not self.conveyorController:isDischarging() and self.shovelController:isFull() then
            self:setMaxSpeed(0)
        end

        self:callUnloaderWhenNeeded()
        if self.bunkerSiloController then
            local _, _, closestObject = self.siloEndProximitySensor:getClosestObjectDistanceAndRootVehicle()
            local isEndReached, maxSpeed = self.bunkerSiloController:isEndReached(self.shovelController:getShovelNode(), 0)
            if self.silo:isTheSameSilo(closestObject) or isEndReached then
                self:debug("End wall detected or bunker silo end is reached.")
                self.state = self.states.FINISHED_WORKING
            end
        end

    elseif self.state == self.states.FINISHED_WORKING then
        self:setMaxSpeed(0)
        self:debugSparse("Waiting until the conveyor is empty.")
        if self.shovelController:isEmpty() then
            self.conveyorController:disableDischarge()
            self.vehicle:stopCurrentAIJob(AIMessageSuccessFinishedJob.new())
        end
    end
    self:limitSpeed()
    return gx, gz, moveForwards, self.maxSpeed, 100
end

--- Pathfinding has finished
---@param controller PathfinderController
---@param success boolean
---@param course Course|nil
---@param goalNodeInvalid boolean|nil
function AIDriveStrategySiloLoader:onPathfindingFinished(controller,
                                                         success, course, goalNodeInvalid)
    if not success then
        self:debug('Pathfinding failed, giving up!')
        self.vehicle:stopCurrentAIJob(AIMessageCpErrorNoPathFound.new())
        return
    end
    if self.state == self.states.DRIVING_ALIGNMENT_COURSE then
        self:startCourse(course, 1)
    end
end

--- Pathfinding failed, but a retry attempt is leftover.
---@param controller PathfinderController
---@param lastContext PathfinderContext
---@param wasLastRetry boolean
---@param currentRetryAttempt number
function AIDriveStrategySiloLoader:onPathfindingFailed(controller,
                                                       lastContext, wasLastRetry, currentRetryAttempt)
    --- TODO: Think of possible points of failures, that could be adjusted here.
    ---       Maybe a small reverse course might help to avoid a deadlock
    ---       after one pathfinder failure based on proximity sensor data and so on ..
    if self.state == self.states.DRIVING_ALIGNMENT_COURSE then
        local course = self:getRememberedCourseAndIx()
        local fm = self:getFrontAndBackMarkers()
        controller:findPathToWaypoint(lastContext, course,
                1, 0, -1.5 * (fm + 4), 1)
    end
end

--- Find an alignment path to the silo/heap course.
---@param course Course silo/heap course
function AIDriveStrategySiloLoader:startPathfindingToStart(course)
    self.state = self.states.DRIVING_ALIGNMENT_COURSE
    self:rememberCourse(course, 1)
    local fm = self:getFrontAndBackMarkers()
    local context = PathfinderContext(self.vehicle):allowReverse(true):ignoreFruit(true)
    self.pathfinderController:findPathToWaypoint(context, course,
            1, 0, -1.5 * (fm + 4), 1)
end

function AIDriveStrategySiloLoader:prepareForStart()
    if not self.conveyorController:isPipeMoving() then
        self.state = self.states.WORKING
        self.conveyorController:enableDischargeToObject()
    end
end

function AIDriveStrategySiloLoader:update(dt)
    AIDriveStrategyCourse.update(self)
    self:updateImplementControllers(dt)
    if CpDebug:isChannelActive(CpDebug.DBG_SILO, self.vehicle) then
        if self.course:isTemporary() then
            self.course:draw()
        elseif self.ppc:getCourse():isTemporary() then
            self.ppc:getCourse():draw()
        end
        if self.silo then
            self.silo:drawDebug()
        end
        if self.bunkerSiloController then
            self.bunkerSiloController:draw()
        end
    end
end

function AIDriveStrategySiloLoader:updateCpStatus(status)
    status:setSiloLoaderStatus(self.silo:getTotalFillLevel(), self.fillLevelLeftOverSinceStart)
end

---------------------------------------------
--- Combine unloader interface functions
---------------------------------------------

function AIDriveStrategySiloLoader:getFillType()
    return self.shovelController:getDischargeFillType()
end

function AIDriveStrategySiloLoader:isPipeOnLeft()
    return self.conveyorController:isPipeOnTheLeftSide()
end

function AIDriveStrategySiloLoader:hasAutoAimPipe()
    return false
end

function AIDriveStrategySiloLoader:alwaysNeedsUnloader()
    return false
end

--- Let unloaders register for events. This is different from the CombineUnloadManager registration, these
--- events are for the low level coordination between the combine and its unloader(s). CombineUnloadManager
--- takes care about coordinating the work between multiple combines.
function AIDriveStrategySiloLoader:clearAllUnloaderInformation()
    self:cancelRendezvous()
    self.unloader:reset()
end

--- Register a combine unload AI driver for notification about combine events
--- Unloaders can renew their registration as often as they want to make sure they remain registered.
---@param driver AIDriveStrategyUnloadCombine
function AIDriveStrategySiloLoader:registerUnloader(driver)
    self.unloader:set(driver, 1000)
end

--- Deregister a combine unload AI driver from notifications
---@param driver CombineUnloadAIDriver
function AIDriveStrategySiloLoader:deregisterUnloader(driver, noEventSend)
    self:cancelRendezvous()
    self.unloader:reset()
end

function AIDriveStrategySiloLoader:getMeasuredBackDistance()
    return math.abs(self.conveyorController:getPipeOffsetZ())
end

--- Hold the harvester for a period of periodMs milliseconds
function AIDriveStrategySiloLoader:hold(periodMs)
    if not self.temporaryHold:get() then
        self:debug('Temporary hold request for %d milliseconds', periodMs)
    end
    self.temporaryHold:set(true, math.min(math.max(0, periodMs), 30000))
end

function AIDriveStrategySiloLoader:callUnloaderWhenNeeded()
    if not self.timeToCallUnloader:get() then
        return
    end
    -- check back again in a few seconds
    self.timeToCallUnloader:set(false, 3000)

    if self.unloader:get() then
        self:debug('callUnloaderWhenNeeded: already has an unloader assigned (%s)', CpUtil.getName(self.unloader:get()))
        return
    end

    local bestUnloader, bestEte
    if self:isWaitingForUnload() then
        bestUnloader, _ = self:findUnloader()
        self:debug('callUnloaderWhenNeeded: stopped, need unloader here')
        if bestUnloader then
            bestUnloader:getCpDriveStrategy():call(self.vehicle, nil)
        end
    end
end

function AIDriveStrategySiloLoader:findUnloader()
    local bestScore = -math.huge
    local bestUnloader, bestEte
    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if AIDriveStrategyUnloadCombine.isActiveCpSiloLoader(vehicle) then
            local x, _, z = getWorldTranslation(self.vehicle.rootNode)
            ---@type AIDriveStrategyUnloadCombine
            local driveStrategy = vehicle:getCpDriveStrategy()
            if driveStrategy:isServingPosition(x, z, self.distanceOverFieldEdgeAllowed) then
                local unloaderFillLevelPercentage = driveStrategy:getFillLevelPercentage()
                if driveStrategy:isIdle() and unloaderFillLevelPercentage < 99 then
                    local unloaderDistance, unloaderEte = driveStrategy:getDistanceAndEteToVehicle(self.vehicle)

                    local score = unloaderFillLevelPercentage - 0.1 * unloaderDistance
                    self:debug('findUnloader: %s idle on my field, fill level %.1f, distance %.1f, ETE %.1f, score %.1f)',
                            CpUtil.getName(vehicle), unloaderFillLevelPercentage, unloaderDistance, unloaderEte, score)
                    if score > bestScore then
                        bestUnloader = vehicle
                        bestScore = score
                        bestEte = unloaderEte
                    end
                else
                    self:debug('findUnloader: %s serving my field but already busy', CpUtil.getName(vehicle))
                end
            else
                self:debug('findUnloader: %s is not serving my field', CpUtil.getName(vehicle))
            end
        end
    end
    if bestUnloader then
        self:debug('findUnloader: best unloader is %s (score %.1f, ETE %.1f)',
                CpUtil.getName(bestUnloader), bestScore, bestEte)
        return bestUnloader, bestEte
    else
        self:debug('findUnloader: no idle unloader found')
    end
end

function AIDriveStrategySiloLoader:isPipeMoving()
    return false
end

function AIDriveStrategySiloLoader:isDischarging()
    return self.conveyorController:isDischarging()
end

function AIDriveStrategySiloLoader:canLoadTrailer(trailer)
    local dischargeNode = self.conveyorController:getDischargeNode()
    local fillType = self.conveyorController:getDischargeFillType()
    if not trailer:getFillUnitSupportsFillType(dischargeNode.dischargeFillUnitIndex, fillType) then
        return false
    end

    local allowFillType = trailer:getFillUnitAllowsFillType(dischargeNode.dischargeFillUnitIndex, fillType)

    if not allowFillType then
        return false
    end

    if trailer.getFillUnitFreeCapacity ~= nil and trailer:getFillUnitFreeCapacity(dischargeNode.dischargeFillUnitIndex, fillType, self.vehicle:getActiveFarm()) <= 0 then
        return false
    end

    if trailer.getIsFillAllowedFromFarm ~= nil and not trailer:getIsFillAllowedFromFarm(self.vehicle:getActiveFarm()) then
        return false
    end

    return true
end

function AIDriveStrategySiloLoader:isTurning()
    return false
end

function AIDriveStrategySiloLoader:isReadyToUnload()
    return true
end

function AIDriveStrategySiloLoader:willWaitForUnloadToFinish()
    return true
end

function AIDriveStrategySiloLoader:getFieldworkCourse()
    return self.course
end

function AIDriveStrategySiloLoader:getClosestFieldworkWaypointIx()
    return self.ppc:getRelevantWaypointIx()
end

function AIDriveStrategySiloLoader:getWorkWidth()
    return self.settings.bunkerSiloWorkWidth:getValue()
end

function AIDriveStrategySiloLoader:getCombine()
    return self.vehicle
end

function AIDriveStrategySiloLoader:isAttachedHarvester()
    return false
end

function AIDriveStrategySiloLoader:getPipeOffsetReferenceNode()
    return self.vehicle:getAIDirectionNode()
end

function AIDriveStrategySiloLoader:isWaitingForUnloadAfterPulledBack()
    return true
end

function AIDriveStrategySiloLoader:isOnHeadland()
    return false
end

function AIDriveStrategySiloLoader:getAreaToAvoid()
    return nil
end

function AIDriveStrategySiloLoader:isReversing()
    return false
end

function AIDriveStrategySiloLoader:isAboutToTurn()
    return false
end

function AIDriveStrategySiloLoader:isAboutToReturnFromPocket()
    return false
end

function AIDriveStrategySiloLoader:isManeuvering()
    return false
end

function AIDriveStrategySiloLoader:isWaitingForUnload()
    return true
end

function AIDriveStrategySiloLoader:hasRendezvousWith(vehicle)
    return false
end

function AIDriveStrategySiloLoader:cancelRendezvous()

end

--- The unloader may call this repeatedly to confirm that the rendezvous still stands, making sure the
--- combine won't give up and keeps waiting
function AIDriveStrategySiloLoader:reconfirmRendezvous()
    if self.waitingForUnloaderAtEndOfRow:get() then
        -- ok, we'll wait another 30 seconds
        self.waitingForUnloaderAtEndOfRow:set(true, 30000)
    end
end

function AIDriveStrategySiloLoader:isUnloadFinished()
    return false
end

function AIDriveStrategySiloLoader:isWaitingForUnloadAfterCourseEnded()
    return false
end

function AIDriveStrategySiloLoader:getFillLevelPercentage()
    return 99
end

function AIDriveStrategySiloLoader:isWaitingInPocket()
    return false
end

--- Offset of the pipe from the combine implement's root node
---@param additionalOffsetX number add this to the offsetX if you don't want to be directly under the pipe. If
--- greater than 0 -> to the left, less than zero -> to the right
---@param additionalOffsetZ number forward (>0)/backward (<0) offset from the pipe
function AIDriveStrategySiloLoader:getPipeOffset(additionalOffsetX, additionalOffsetZ)
    local pipeOffsetX, pipeOffsetZ = self.conveyorController:getPipeOffsetX(), self.conveyorController:getPipeOffsetZ()
    return pipeOffsetX + (additionalOffsetX or 0), pipeOffsetZ + (additionalOffsetZ or 0)
end

--- Pipe side offset relative to course. This is to help the unloader
--- to find the pipe when we are waiting in a pocket
function AIDriveStrategySiloLoader:getPipeOffsetFromCourse()
    return self.conveyorController:getPipeOffsetX(), self.conveyorController:getPipeOffsetZ()
end