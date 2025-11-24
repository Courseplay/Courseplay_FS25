--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2019-2021 Peter Vaiko

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

---@class AIDriveStrategyCombineCourse : AIDriveStrategyFieldWorkCourse
AIDriveStrategyCombineCourse = CpObject(AIDriveStrategyFieldWorkCourse)

-- fill level when we start making a pocket to unload if we are on the outermost headland
AIDriveStrategyCombineCourse.pocketFillLevelFullPercentage = 95
AIDriveStrategyCombineCourse.safeUnloadDistanceBeforeEndOfRow = 30
-- when fill level is above this threshold, don't start the next row if the pipe would be
-- in the fruit
AIDriveStrategyCombineCourse.waitForUnloadAtEndOfRowFillLevelThreshold = 95

-- When to initiate a self unload before turning to the next row?
-- if the fill level is above this threshold when about to begin a turn and there is a trailer
-- close by, and ...
AIDriveStrategyCombineCourse.selfUnloadBeforeNextRowFillLevelThreshold = 60
-- if the best trailer is less then this (meters) to the left or right
AIDriveStrategyCombineCourse.selfUnloadBeforeNextRowMaxDistance = 50
--- Percentage delta leftover until full, when the combine slows down.
AIDriveStrategyCombineCourse.startingSlowdownFillLevelThreshold = 1.5
--- Minimum working speed, for slowdown.
AIDriveStrategyCombineCourse.normalMinimalWorkingSpeed = 5

AIDriveStrategyCombineCourse.myStates = {
    -- main states
    UNLOADING_ON_FIELD = {},
    -- unload sub-states
    STOPPING_FOR_UNLOAD = {},
    WAITING_FOR_UNLOAD_ON_FIELD = {},
    PULLING_BACK_FOR_UNLOAD = {},
    WAITING_FOR_UNLOAD_AFTER_PULLED_BACK = {},
    RETURNING_FROM_PULL_BACK = {},
    REVERSING_TO_MAKE_A_POCKET = {},
    MAKING_POCKET = {},
    WAITING_FOR_UNLOAD_IN_POCKET = {},
    WAITING_FOR_UNLOAD_BEFORE_STARTING_NEXT_ROW = {},
    UNLOADING_BEFORE_STARTING_NEXT_ROW = {},
    WAITING_FOR_UNLOAD_AFTER_FIELDWORK_ENDED = {},
    WAITING_FOR_UNLOADER_TO_LEAVE = {},
    RETURNING_FROM_POCKET = {},
    DRIVING_TO_SELF_UNLOAD = {},
    DRIVING_TO_SELF_UNLOAD_BEFORE_NEXT_ROW = {}, -- before turning into the next row, we unload into a nearby trailer
    SELF_UNLOADING = {},
    SELF_UNLOADING_WAITING_FOR_DISCHARGE = {},
    DRIVING_TO_SELF_UNLOAD_AFTER_FIELDWORK_ENDED = {},
    SELF_UNLOADING_AFTER_FIELDWORK_ENDED = {},
    SELF_UNLOADING_AFTER_FIELDWORK_ENDED_WAITING_FOR_DISCHARGE = {},
    RETURNING_FROM_SELF_UNLOAD = {},
}

-- stop limit we use for self unload to approach the trailer
AIDriveStrategyCombineCourse.proximityStopThresholdSelfUnload = 0.1

-- Developer hack: to check the class of an object one should use the is_a() defined in CpObject.lua.
-- However, when we reload classes on the fly during the development, the is_a() calls in other modules still
-- have the old class definition (for example CombineUnloadManager.lua) of this class and thus, is_a() fails.
-- Therefore, use this instead, this is safe after a reload.
AIDriveStrategyCombineCourse.isAAIDriveStrategyCombineCourse = true

function AIDriveStrategyCombineCourse:init(task, job)
    AIDriveStrategyFieldWorkCourse.init(self, task, job)
    AIDriveStrategyCourse.initStates(self, AIDriveStrategyCombineCourse.myStates)
    self.fruitLeft, self.fruitRight = 0, 0
    self.litersPerMeter = 0
    self.litersPerSecond = 0
    self.fillLevelAtLastWaypoint = 0
    self.beaconLightsActive = false
    self.stopDisabledAfterEmpty = CpTemporaryObject(false)
    self.stopDisabledAfterEmpty:set(false, 1)
    self:initUnloadStates()
    self.chopperCanDischarge = CpTemporaryObject(false)
    -- hold the harvester temporarily
    self.temporaryHold = CpTemporaryObject(false)
    -- periodically check if we need to call an unloader
    self.timeToCallUnloader = CpTemporaryObject(true)
    self.unloaderRequestedToIgnoreProximity = CpTemporaryObject()
    -- we want to keep to pipe open, even if there is no trailer under it
    self.forcePipeOpen = CpTemporaryObject()
    -- and sometimes, we want to keep it close, even if there is a trailer under it
    self.forcePipeClose = CpTemporaryObject()
    self.pocketHelperNode = HelperTerrainNode('pocketHelperNode')
    --- Register info texts
    self:registerInfoTextForStates(self:getFillLevelInfoText(), {
        states = {
            [self.states.UNLOADING_ON_FIELD] = true
        },
        unloadStates = {
            [self.states.WAITING_FOR_UNLOAD_ON_FIELD] = true,
            [self.states.WAITING_FOR_UNLOAD_AFTER_FIELDWORK_ENDED] = true,
            [self.states.WAITING_FOR_UNLOAD_AFTER_PULLED_BACK] = true,
            [self.states.WAITING_FOR_UNLOAD_IN_POCKET] = true
        }
    })
end

function AIDriveStrategyCombineCourse:delete()
    self.pocketHelperNode:destroy()
    AIDriveStrategyFieldWorkCourse.delete(self)
end

function AIDriveStrategyCombineCourse:getStateAsString()
    local s = self.state.name
    if self.state == self.states.UNLOADING_ON_FIELD then
        s = s .. '/' .. self.unloadState.name
    end
    return s
end

-----------------------------------------------------------------------------------------------------------------------
--- Initialization
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyCombineCourse:setAllStaticParameters()
    AIDriveStrategyFieldWorkCourse.setAllStaticParameters(self)
    self:debug('AIDriveStrategyCombineCourse set')

    if self:isChopper() then
        self:debug('This is a chopper.')
    end

    self:checkMarkers()
    self:measureBackDistance()
    Markers.setMarkerNodes(self.vehicle, self.measuredBackDistance)

    self.proximityController:registerBlockingVehicleListener(self, AIDriveStrategyCombineCourse.onBlockingVehicle)
    self.proximityController:registerIgnoreObjectCallback(self, AIDriveStrategyCombineCourse.ignoreProximityObject)

    -- distance to keep to the right (>0) or left (<0) when pulling back to make room for the tractor
    self.pullBackRightSideOffset = math.abs(self.pipeController:getPipeOffsetX()) - self:getWorkWidth() / 2 + 5
    self.pullBackRightSideOffset = self:isPipeOnLeft() and self.pullBackRightSideOffset or -self.pullBackRightSideOffset
    -- should be at pullBackRightSideOffset to the right or left at pullBackDistanceStart
    self.pullBackDistanceStart = 2 * AIUtil.getTurningRadius(self.vehicle)
    -- and back up another bit
    self.pullBackDistanceEnd = self.pullBackDistanceStart + 5
    -- when making a pocket, how far to back up before changing to forward
    -- for very long vehicles, like potato/sugar beet harvesters the 20 meters may not be enough
    self.pocketReverseDistance = AIUtil.getVehicleAndImplementsTotalLength(self.vehicle) * 2.2
    -- register ourselves at our boss
    -- TODO_22 g_combineUnloadManager:addCombineToList(self.vehicle, self)
    self.waitingForUnloaderAtEndOfRow = CpTemporaryObject()
    --- My unloader. This expires in a few seconds, so unloaders have to renew their registration periodically
    ---@type CpTemporaryObject
    self.unloader = CpTemporaryObject(nil)
    --- if this is not nil, we have a pending rendezvous with our unloader
    ---@type CpTemporaryObject
    self.unloaderToRendezvous = CpTemporaryObject(nil)
    -- local total, pipeInFruit = self.vehicle:getFieldWorkCourse():setPipeInFruitMap(self.pipeController:getPipeOffsetX(), self:getWorkWidth())
    -- self:debug('Pipe in fruit map created, there are %d non-headland waypoints, of which at %d the pipe will be in the fruit',
            -- total, pipeInFruit)
    self.pipeInFruitMapIndex = 0
    self.pipeInFruitMapCountPerUpdate = 80
    self.pipeInFruitMapFinished = false
    self.fillLevelFullPercentage = self.normalFillLevelFullPercentage
end

function AIDriveStrategyCombineCourse:initializeImplementControllers(vehicle)
    AIDriveStrategyFieldWorkCourse.initializeImplementControllers(self, vehicle)
    local _
    self.implementWithPipe, self.pipeController = self:addImplementController(vehicle,
            PipeController, Pipe, {}, nil)
    self.combineController, self.combine = self:getFirstRegisteredImplementControllerByClass(CombineController)
end

function AIDriveStrategyCombineCourse:getProximitySensorWidth()
    -- proximity sensor width across the entire working width
    return self:getWorkWidth()
end

-- This part of an ugly workaround to make the chopper pickups work
function AIDriveStrategyCombineCourse:checkMarkers()
    for _, implement in pairs(AIUtil.getAllAIImplements(self.vehicle)) do
        local aiLeftMarker, aiRightMarker, aiBackMarker = implement.object:getAIMarkers()
        if not aiLeftMarker or not aiRightMarker or not aiBackMarker then
            self.notAllImplementsHaveAiMarkers = true
            return
        end
    end
end

function AIDriveStrategyCombineCourse:getAllowReversePathfinding()
    if self:isTurning() and self:hasAutoAimPipe() and self.unloader:get() ~= nil then
        -- chopper with CP unloader turning, disable reverse for pathfinder turns
        -- to make following the chopper through the turn easier
        return false
    else
        return AIDriveStrategyFieldWorkCourse.getAllowReversePathfinding(self)
    end
end

--- Get the combine object, this can be different from the vehicle in case of tools towed or mounted on a tractor
function AIDriveStrategyCombineCourse:getCombine()
    return self.combine
end

function AIDriveStrategyCombineCourse:isAttachedHarvester()
    return self.vehicle ~= self.combine
end

function AIDriveStrategyCombineCourse:getPipeOffsetReferenceNode()
    if self:isAttachedHarvester() then
        -- for attached harvesters this gets the root node of the harvester as that is our reference point to the
        -- pipe offsets
        return self:getCombine().rootNode
    else
        return self.vehicle:getAIDirectionNode()
    end
end

function AIDriveStrategyCombineCourse:update(dt)
    AIDriveStrategyFieldWorkCourse.update(self, dt)
    self:updateChopperFillType()
    self:onDraw()

    if not self.pipeInFruitMapFinished and self.course then
        if self.pipeController and self.pipeController.getPipeOffsetX and self.pipeController:getPipeOffsetX() then
            if self.getWorkWidth and self:getWorkWidth() then
                if self.pipeInFruitMapIndex < self.course:getNumberOfWaypoints() + self.pipeInFruitMapCountPerUpdate then
                    self.vehicle:getFieldWorkCourse():setPipeInFruitMapSegment(self.pipeController:getPipeOffsetX(), self:getWorkWidth(), self.pipeInFruitMapIndex, self.pipeInFruitMapCountPerUpdate)
                    self.pipeInFruitMapIndex = self.pipeInFruitMapIndex + self.pipeInFruitMapCountPerUpdate
                else
                    self.pipeInFruitMapFinished = true
                end
            end
        end
    end
end

--- Hold the harvester for a period of periodMs milliseconds
function AIDriveStrategyCombineCourse:hold(periodMs)
    if not self.temporaryHold:get() then
        self:debug('Temporary hold request for %d milliseconds', periodMs)
    end
    self.temporaryHold:set(true, math.min(math.max(0, periodMs), 30000))
end

function AIDriveStrategyCombineCourse:getDriveData(dt, vX, vY, vZ)
    self:handlePipe(dt)
    self:measureBackDistance()
    Markers.refreshMarkerNodes(self.vehicle, self.measuredBackDistance)
    if self.temporaryHold:get() then
        self:setMaxSpeed(0)
    end

    --- Combine may need the field polygon for the self-unload to work, so if by now we don't have one
    --- and the field boundary detection is not running, start it. This can happen if the combine wasn't started
    --- directly, such as as it was driving to the field and then switched strategy
    if not self.vehicle:cpIsFieldBoundaryDetectionRunning() and self.vehicle:cpGetFieldPolygon() == nil then
        self:startFieldBoundaryDetection()
    end

    if self.vehicle:cpIsFieldBoundaryDetectionRunning() then
        if self.settings.selfUnload:getValue() then
            -- don't have the field boundary yet, and self unload is selected, don't move
            self:setMaxSpeed(0)
        end
        if self:waitForFieldBoundary() then
            self:debug('Have field boundary now.')
        end
    elseif self.state == self.states.WORKING then
        -- Harvesting
        self:checkRendezvous()
        self:checkBlockingUnloader()

        if self:isFull() then
            self:changeToUnloadOnField()
        elseif self:alwaysNeedsUnloader() then
            if not self.pipeController:isFillableTrailerUnderPipe() then
                self:debug('Need an unloader to work but have no fillable trailer under the pipe')
                self:changeToUnloadOnField()
            end
        elseif self:shouldWaitAtEndOfRow() then
            self:startWaitingForUnloadBeforeNextRow()
        end

        if not self.pipeController:isInAllowedState() then
            self:debugSparse('Pipe is not in allowed state, stop')
            self:setMaxSpeed(0)
        end

        if self:shouldStopForUnloading() then
            -- player does not want us to move while discharging
            self:setMaxSpeed(0)
        else
            -- Slowdown the combine near the last few percent, so no crops are leftover,
            -- as the combine needs to stop in time, before it's full.
            local leftoverPercentage = self.fillLevelFullPercentage - self.combineController:getFillLevelPercentage()
            if (leftoverPercentage > 0 and leftoverPercentage < self.startingSlowdownFillLevelThreshold) then
                local speed = leftoverPercentage * (self.vehicle:getSpeedLimit(true) / self.startingSlowdownFillLevelThreshold) + self.normalMinimalWorkingSpeed
                self:setMaxSpeed(speed)
            end
        end


    elseif self.state == self.states.TURNING then
        self:checkBlockingUnloader()
    elseif self.state == self.states.WAITING_FOR_LOWER then
        if self:isFull() then
            self:debug('Waiting for lower but full...')
            self:changeToUnloadOnField()
        end
    elseif self.state == self.states.UNLOADING_ON_FIELD then
        -- Unloading
        self:driveUnloadOnField()
        if self:isWaitingForUnload() then
            self:callUnloaderWhenNeeded()
        end
    end
    if self:isTurning() and not self:isFinishingRow() then
        if self:shouldHoldInTurnManeuver() then
            self:setMaxSpeed(0)
        end
    end
    return AIDriveStrategyFieldWorkCourse.getDriveData(self, dt, vX, vY, vZ)
end

function AIDriveStrategyCombineCourse:updateFieldworkOffset(course)
    if self.state == self.states.UNLOADING_ON_FIELD and self:isUnloadStateOneOf(self.selfUnloadStates) then
        -- do not apply fieldwork offset when not doing fieldwork
        course:setOffset((self.aiOffsetX or 0) + (self.tightTurnOffset or 0), (self.aiOffsetZ or 0))
    else
        course:setOffset(self.settings.toolOffsetX:getValue() + (self.aiOffsetX or 0) + (self.tightTurnOffset or 0),
                (self.aiOffsetZ or 0))
    end
end

function AIDriveStrategyCombineCourse:checkDistanceToOtherFieldWorkers()
    -- do not slow down/stop for convoy while unloading
    if self.state ~= self.states.UNLOADING_ON_FIELD then
        self:setMaxSpeed(self.fieldWorkerProximityController:getMaxSpeed(self.settings.convoyDistance:getValue(), self.maxSpeed))
    end
end

--- Take care of unloading on the field. This could be stopping and waiting for an unloader or
--- self unloading.
--- The output of this function is:
---  * set self.maxSpeed
---  * change the course to run, for example pulling back/making pocket or self unload
---  * this does not supply drive target point
function AIDriveStrategyCombineCourse:driveUnloadOnField()
    if self.unloadState == self.states.STOPPING_FOR_UNLOAD then
        self:setMaxSpeed(0)
        -- wait until we stopped before raising the implements
        if AIUtil.isStopped(self.vehicle) then
            if self.raiseHeaderAfterStopped then
                self:debug('Stopped, now raise implements and switch to next unload state')
                self:raiseImplements()
            end
            self.unloadState = self.newUnloadStateAfterStopped
        end
    elseif self.unloadState == self.states.PULLING_BACK_FOR_UNLOAD then
        self:setMaxSpeed(self.settings.reverseSpeed:getValue())
    elseif self.unloadState == self.states.REVERSING_TO_MAKE_A_POCKET then
        self:setMaxSpeed(self.settings.reverseSpeed:getValue())
    elseif self.unloadState == self.states.MAKING_POCKET then
        self:setMaxSpeed(self.settings.fieldWorkSpeed:getValue())
        local _, _, dz = self.pocketHelperNode:localToLocal(self.vehicle:getAIDirectionNode(), 0, 0,
                self.pipeController:getPipeOffsetZ())
        if dz > -18 then
            -- we are close enough to the reference waypoint, so stop making the pocket and wait for unload.
            self:debug('Waiting for unload in the pocket')
            self.unloadState = self.states.WAITING_FOR_UNLOAD_IN_POCKET
        end
    elseif self.unloadState == self.states.RETURNING_FROM_PULL_BACK then
        self:setMaxSpeed(self.settings.turnSpeed:getValue())
    elseif self.unloadState == self.states.WAITING_FOR_UNLOAD_IN_POCKET or
            self.unloadState == self.states.WAITING_FOR_UNLOAD_AFTER_PULLED_BACK or
            self.unloadState == self.states.UNLOADING_BEFORE_STARTING_NEXT_ROW then
        if self:isUnloadFinished() then
            -- reset offset to return to the original up/down row after we unloaded in the pocket
            self.aiOffsetX = 0

            -- wait a bit after the unload finished to give a chance to the unloader to move away
            self.stateBeforeWaitingForUnloaderToLeave = self.unloadState
            self.unloadState = self.states.WAITING_FOR_UNLOADER_TO_LEAVE
            self.waitingForUnloaderSince = g_currentMission.time
            self:debug('Unloading finished, wait for the unloader to leave...')
        else
            self:setMaxSpeed(0)
        end
    elseif self.unloadState == self.states.WAITING_FOR_UNLOAD_ON_FIELD then
        if g_updateLoopIndex % 5 == 0 then
            --small delay, to make sure no more fillLevel change is happening
            if not self:isFull() and not self:shouldStopForUnloading() and not self:alwaysNeedsUnloader() then
                self:debug('not full anymore, can continue working')
                self:changeToFieldWork()
            elseif self:alwaysNeedsUnloader() and self:isFillableTrailerUnderPipe() then
                self:debug('Need an unloader to work, now have a trailer under the pipe, can continue working')
                self:changeToFieldWork()
            end
        end
        self:setMaxSpeed(0)
    elseif self.unloadState == self.states.WAITING_FOR_UNLOAD_BEFORE_STARTING_NEXT_ROW then
        self:setMaxSpeed(0)
        if self:isDischarging() then
            self:cancelRendezvous()
            self.unloadState = self.states.UNLOADING_BEFORE_STARTING_NEXT_ROW
            self:debug('Unloading started at end of row')
        end
        if not self.waitingForUnloaderAtEndOfRow:get() then
            local unloaderWhoDidNotShowUp = self.unloaderToRendezvous:get()
            self:cancelRendezvous()
            if unloaderWhoDidNotShowUp then
                unloaderWhoDidNotShowUp:getCpDriveStrategy():onMissedRendezvous(self)
            end
            self:debug('Waited for unloader at the end of the row but it did not show up, try to continue')
            self:changeToFieldWork()
        end
    elseif self.unloadState == self.states.WAITING_FOR_UNLOAD_AFTER_FIELDWORK_ENDED then
        local fillLevel = self.combineController:getFillLevel()
        if fillLevel < 0.01 then
            self:debug('Unloading finished after fieldwork ended, end course')
            AIDriveStrategyFieldWorkCourse.finishFieldWork(self)
        else
            self:setMaxSpeed(0)
        end
    elseif self.unloadState == self.states.WAITING_FOR_UNLOADER_TO_LEAVE then
        self:setMaxSpeed(0)
        -- TODO: instead of just wait a few seconds we could check if the unloader has actually left
        if self.waitingForUnloaderSince + 5000 < g_currentMission.time then
            if self.stateBeforeWaitingForUnloaderToLeave == self.states.WAITING_FOR_UNLOAD_AFTER_PULLED_BACK then
                local pullBackReturnCourse = self.pathfinderController:findAnalyticPathFromVehicleToGoal(
                        self.positionToContinueAfterPullback, self:getAllowReversePathfinding())
                if pullBackReturnCourse then
                    self.unloadState = self.states.RETURNING_FROM_PULL_BACK
                    self:debug('Unloading finished, returning to fieldwork on return course')
                    self.ppc:setShortLookaheadDistance()
                    self:startCourse(pullBackReturnCourse, 1)
                    self:rememberCourse(self.courseAfterPullBack, self.ixAfterPullBack)
                else
                    self:debug('Unloading finished, returning to fieldwork directly')
                    self:startCourse(self.courseAfterPullBack, self.ixAfterPullBack)
                    self.ppc:setNormalLookaheadDistance()
                    self:changeToFieldWork()
                end
            elseif self.stateBeforeWaitingForUnloaderToLeave == self.states.WAITING_FOR_UNLOAD_IN_POCKET then
                self:debug('Unloading in pocket finished, returning to fieldwork')
                self.fillLevelFullPercentage = self.normalFillLevelFullPercentage
                self:changeToFieldWork()
            elseif self.stateBeforeWaitingForUnloaderToLeave == self.states.UNLOADING_BEFORE_STARTING_NEXT_ROW then
                self:debug('Unloading before next row finished, returning to fieldwork')
                self:changeToFieldWork()
            elseif self.stateBeforeWaitingForUnloaderToLeave == self.states.WAITING_FOR_UNLOAD_ON_FIELD then
                self:debug('Unloading on field finished, returning to fieldwork')
                self:changeToFieldWork()
            else
                self:debug('Unloading finished, previous state not known, returning to fieldwork')
                self:changeToFieldWork()
            end
        end
    elseif self:isUnloadStateOneOf(self.drivingToSelfUnloadStates) then
        if self:isCloseToCourseEnd(25) then
            -- slow down towards the end of the course, near the trailer
            self:setMaxSpeed(math.min(10, 0.5 * self.settings.fieldSpeed:getValue()))
            -- we'll be very close to the tractor/trailer, don't stop too soon
            self.proximityController:setTemporaryStopThreshold(self.proximityStopThresholdSelfUnload, 3000)
            if g_vehicleConfigurations:getRecursively(self.vehicle, 'openPipeEarly') then
                if not self.pipeController:isPipeOpen() then
                    self:debug('Opening pipe early to not crash it into the trailer')
                    self.pipeController:openPipe()
                end
                self.forcePipeOpen:set(true, 1000)
            end
        else
            self:setMaxSpeed(self.settings.fieldSpeed:getValue())
        end
    elseif self.unloadState == self.states.SELF_UNLOADING_WAITING_FOR_DISCHARGE then
        self:setMaxSpeed(0)
        self:debugSparse('Waiting for the self unloading to start')
        if self:isDischarging() then
            self.unloadState = self.states.SELF_UNLOADING
        end
    elseif self.unloadState == self.states.SELF_UNLOADING then
        self:setMaxSpeed(0)
        if self:isUnloadFinished() then
            if not self:continueSelfUnloadToNextTrailer() then
                self:debug('Self unloading finished, returning to fieldwork')
                self:returnToFieldworkAfterSelfUnload()
            end
        end
    elseif self.unloadState == self.states.SELF_UNLOADING_AFTER_FIELDWORK_ENDED_WAITING_FOR_DISCHARGE then
        self:setMaxSpeed(0)
        self:debugSparse('Fieldwork ended, waiting for the self unloading to start')
        if self:isDischarging() then
            self.unloadState = self.states.SELF_UNLOADING_AFTER_FIELDWORK_ENDED
        end
    elseif self.unloadState == self.states.SELF_UNLOADING_AFTER_FIELDWORK_ENDED then
        self:setMaxSpeed(0)
        if self:isUnloadFinished() then
            if not self:continueSelfUnloadToNextTrailer() then
                self:debug('Self unloading finished after fieldwork ended, finishing fieldwork')
                AIDriveStrategyFieldWorkCourse.finishFieldWork(self)
            end
        end
    elseif self.unloadState == self.states.RETURNING_FROM_SELF_UNLOAD then
        if self:isCloseToCourseStart(25) then
            self:setMaxSpeed(0.5 * self.settings.fieldSpeed:getValue())
            -- we'll be very close to the tractor/trailer, don't stop too soon
            self.proximityController:setTemporaryStopThreshold(self.proximityStopThresholdSelfUnload, 3000)
        else
            self:setMaxSpeed(self.settings.fieldSpeed:getValue())
        end
        -- apply the work starter's speed limit (when approaching the work start)
        local _, _, _, maxSpeed = self.workStarter:getDriveData()
        if maxSpeed ~= nil then
            self:setMaxSpeed(maxSpeed)
        end
    end
end

-----------------------------------------------------------------------------------------------------------------------
--- Event listeners
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyCombineCourse:onWaypointPassed(ix, course)
    if self.state == self.states.UNLOADING_ON_FIELD and
            (self.unloadState == self.states.DRIVING_TO_SELF_UNLOAD or
                    self.unloadState == self.states.DRIVING_TO_SELF_UNLOAD_BEFORE_NEXT_ROW or
                    self.unloadState == self.states.DRIVING_TO_SELF_UNLOAD_AFTER_FIELDWORK_ENDED or
                    self.unloadState == self.states.RETURNING_FROM_SELF_UNLOAD) then
        -- nothing to do while driving to unload and back
        return AIDriveStrategyFieldWorkCourse.onWaypointPassed(self, ix, course)
    end

    self:checkFruit()

    -- make sure we start making a pocket while we still have some fill capacity left as we'll be
    -- harvesting fruit while making the pocket unless we have self unload turned on
    if self:shouldMakePocket() and not self.settings.selfUnload:getValue() then
        self.fillLevelFullPercentage = self.pocketFillLevelFullPercentage
    end

    local isOnHeadland = self.course:isOnHeadland(ix)
    self.combineController:updateStrawSwath(isOnHeadland)

    if self.state == self.states.WORKING then
        if not self:alwaysNeedsUnloader() then
            self:estimateDistanceUntilFull(ix)
            self:callUnloaderWhenNeeded()
        end
    end

    if self.returnedFromPocketIx and self.returnedFromPocketIx == ix then
        -- back to normal look ahead distance for PPC, no tight turns are needed anymore
        self:debug('Reset PPC to normal lookahead distance')
        self.ppc:setNormalLookaheadDistance()
    end
    AIDriveStrategyFieldWorkCourse.onWaypointPassed(self, ix, course)
end

--- Called when the last waypoint of a course is passed
function AIDriveStrategyCombineCourse:onLastWaypointPassed()
    local fillLevel = self.combineController:getFillLevel()
    if self.state == self.states.UNLOADING_ON_FIELD then
        if self.unloadState == self.states.RETURNING_FROM_PULL_BACK then
            self:debug('Pull back finished, returning to fieldwork')
            self.ppc:setNormalLookaheadDistance()
            self:startRememberedCourse()
            self:changeToFieldWork()
        elseif self.unloadState == self.states.RETURNING_FROM_SELF_UNLOAD then
            self:debug('Back from self unload, returning to fieldwork')
            self.workStarter:onLastWaypoint()
        elseif self.unloadState == self.states.REVERSING_TO_MAKE_A_POCKET then
            self:debug('Reversed, now start making a pocket')
            self:lowerImplements()
            self.state = self.states.UNLOADING_ON_FIELD
            self.unloadState = self.states.MAKING_POCKET
            -- offset the main fieldwork course and start on it
            self.aiOffsetX = math.min(self.pullBackRightSideOffset, self:getWorkWidth())
            self:startRememberedCourse()
        elseif self.unloadState == self.states.PULLING_BACK_FOR_UNLOAD then
            -- pulled back, now wait for unload
            self.unloadState = self.states.WAITING_FOR_UNLOAD_AFTER_PULLED_BACK
            self:debug('Pulled back, now wait for unload')
        elseif self.unloadState == self.states.DRIVING_TO_SELF_UNLOAD or
                self.unloadState == self.states.DRIVING_TO_SELF_UNLOAD_BEFORE_NEXT_ROW then
            self:debug('Self unloading point reached, fill level %.1f, waiting for unload to start.', fillLevel)
            self.unloadState = self.states.SELF_UNLOADING_WAITING_FOR_DISCHARGE
        elseif self.unloadState == self.states.DRIVING_TO_SELF_UNLOAD_AFTER_FIELDWORK_ENDED then
            self:debug('Self unloading point reached after fieldwork ended, fill level %.1f, waiting for unload to start.', fillLevel)
            self.unloadState = self.states.SELF_UNLOADING_AFTER_FIELDWORK_ENDED_WAITING_FOR_DISCHARGE
        end
    elseif self.state == self.states.WORKING and fillLevel > 0 then
        -- reset offset we used for the course ending to not miss anything
        self.aiOffsetZ = 0
        if self.settings.selfUnload:getValue() and
                self:startSelfUnload(self.states.DRIVING_TO_SELF_UNLOAD_AFTER_FIELDWORK_ENDED) then
            self:debug('Start self unload after fieldwork ended')
        else
            -- let AutoDrive know we are done and can unload
            self:debug('Fieldwork done, fill level is %.1f, now waiting to be unloaded.', fillLevel)
            self.state = self.states.UNLOADING_ON_FIELD
            self.unloadState = self.states.WAITING_FOR_UNLOAD_AFTER_FIELDWORK_ENDED
        end
    else
        AIDriveStrategyFieldWorkCourse.onLastWaypointPassed(self)
    end
end

-----------------------------------------------------------------------------------------------------------------------
--- State changes
-----------------------------------------------------------------------------------------------------------------------

--- Some of our turns need a short look ahead distance, make sure we restore the normal after the turn
function AIDriveStrategyCombineCourse:resumeFieldworkAfterTurn(ix)
    self.ppc:setNormalLookaheadDistance()
    AIDriveStrategyFieldWorkCourse.resumeFieldworkAfterTurn(self, ix)
end

--- Stop, raise the header (if needed) and then, and only then change to the new states. This is to avoid leaving
--- unharvested spots due to the header being lifted while the vehicle is still in motion.
function AIDriveStrategyCombineCourse:stopForUnload(newUnloadStateAfterStopped, raiseHeaderAfterStopped)
    self.state = self.states.UNLOADING_ON_FIELD
    self.unloadState = self.states.STOPPING_FOR_UNLOAD
    self.newUnloadStateAfterStopped = newUnloadStateAfterStopped
    self.raiseHeaderAfterStopped = raiseHeaderAfterStopped
end

--- Start waiting for the implements to lower
-- getCanAIVehicleContinueWork() seems to return false when the implement being lowered/raised (moving) but
-- true otherwise. Due to some timing issues it may return true just after we started lowering it
-- so the harvester misses some fruit when restarting after unloading ended
function AIDriveStrategyCombineCourse:startWaitingForLower()
    -- force delayed lower
    self.state = self.states.WAITING_FOR_LOWER_DELAYED
    self:debug('waiting for lower delayed')
end

function AIDriveStrategyCombineCourse:changeToUnloadOnField()
    self:checkFruit()
    -- TODO: check around turn maneuvers we may not want to pull back before a turn
    self:rememberCourse(self.fieldWorkCourse, self:getBestWaypointToContinueFieldWork())
    if self.settings.selfUnload:getValue() and self:startSelfUnload(self.states.DRIVING_TO_SELF_UNLOAD) then
        self:debug('Start self unload')
    elseif self.settings.avoidFruit:getValue() and self:shouldMakePocket() then
        -- I'm on the edge of the field or fruit is on both sides, make a pocket on the right side and wait there for the unload
        local pocketCourse, nextIx = self:createPocketCourse()
        if pocketCourse then
            self:debug('No room to the left, making a pocket for unload')
            self.state = self.states.UNLOADING_ON_FIELD
            self.unloadState = self.states.REVERSING_TO_MAKE_A_POCKET
            -- place a marker at the current pipe position, we'll use this to find out where to stop
            -- making the pocket
            self.pocketHelperNode:placeAtNode(Markers.getFrontMarkerNode(self.vehicle), 1, 0, 0, 0)
            self:rememberCourse(self.course, nextIx)
            -- raise header for reversing
            self:raiseImplements()
            self:startCourse(pocketCourse, 1)
            -- tighter turns
            self.ppc:setShortLookaheadDistance()
        else
            self:startWaitingForUnloadWhenFull()
        end
    elseif self.settings.avoidFruit:getValue() and self:shouldPullBack() then
        -- is our pipe in the fruit? (assuming pipe is on the left side)
        local pullBackCourse = self:createPullBackCourse()
        if pullBackCourse then
            self:debug('Pipe in fruit, pulling back to make room for unloading')
            self:stopForUnload(self.states.PULLING_BACK_FOR_UNLOAD, true)
            self.courseAfterPullBack = self.course
            self.ixAfterPullBack = self.ppc:getLastPassedWaypointIx() or self.ppc:getCurrentWaypointIx()
            -- remember where to start after the pull back, a bit further back just in case.
            self.positionToContinueAfterPullback = PathfinderUtil.getVehiclePositionAsState3D(self.vehicle, 0, -2)
            -- tighter turns
            self.ppc:setShortLookaheadDistance()
            self:startCourse(pullBackCourse, 1)
        else
            self:startWaitingForUnloadWhenFull()
        end
    else
        self:startWaitingForUnloadWhenFull()
    end
end

function AIDriveStrategyCombineCourse:startWaitingForUnloadWhenFull()
    self:stopForUnload(self.states.WAITING_FOR_UNLOAD_ON_FIELD, true)
    self:debug('Waiting for the unloader on the field')
    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("ai_messageErrorGrainTankIsFull"), self.vehicle:getCurrentHelper().name))
end

function AIDriveStrategyCombineCourse:startWaitingForUnloadBeforeNextRow()
    self:debug('Waiting for unload before starting the next row')
    self.waitingForUnloaderAtEndOfRow:set(true, 30000)
    self:stopForUnload(self.states.WAITING_FOR_UNLOAD_BEFORE_STARTING_NEXT_ROW, true)
end

--- The unloader may call this repeatedly to confirm that the rendezvous still stands, making sure the
--- combine won't give up and keeps waiting
function AIDriveStrategyCombineCourse:reconfirmRendezvous()
    if self.waitingForUnloaderAtEndOfRow:get() then
        -- ok, we'll wait another 30 seconds
        self.waitingForUnloaderAtEndOfRow:set(true, 30000)
    end
end

function AIDriveStrategyCombineCourse:isUnloadFinished()
    local fillLevel = self.combineController:getFillLevel()
    -- unload is done when fill levels are ok (not full) and not discharging anymore (either because we
    -- are empty or the trailer is full)
    return (not self:isFull() and self.pipeController:justStoppedDischarging()) or fillLevel < 0.1
end

function AIDriveStrategyCombineCourse:isFull(fillLevelFullPercentage)
    local fillLevelPercentage = self.combineController:getFillLevelPercentage()
    if fillLevelPercentage >= 100 or fillLevelPercentage > (fillLevelFullPercentage or self.fillLevelFullPercentage) then
        self:debugSparse('Full or refillUntilPct reached: %.2f', fillLevelPercentage)
        return true
    end
    if fillLevelPercentage < 0.1 then
        self.stopDisabledAfterEmpty:set(true, 2000)
    end
    return false
end

function AIDriveStrategyCombineCourse:shouldMakePocket()
    if self:alwaysNeedsUnloader() then
        self:debug('Always need unloader so not making a pocket')
        return false
    end
    -- fruitLeft/fruitRight are percentage of fruit covered area. Also, sugarbeet and some other fruits
    -- return 50% even after harvested, so check for 75% to be on the safe side
    if self.fruitLeft > 75 and self.fruitRight > 75 then
        -- fruit both sides
        return true
    elseif self:isPipeOnLeft() then
        -- on the outermost headland clockwise (field edge)
        return not self.fieldOnLeft
    else
        -- on the outermost headland counterclockwise (field edge)
        return not self.fieldOnRight
    end
end

function AIDriveStrategyCombineCourse:shouldPullBack()
    if self:alwaysNeedsUnloader() then
        self:debug('Always need unloader so not making a pocket')
        return false
    else
        return self:isPipeInFruit()
    end
end

function AIDriveStrategyCombineCourse:isPipeOnLeft()
    return self.pipeController:isPipeOnTheLeftSide()
end

function AIDriveStrategyCombineCourse:isPipeInFruit()
    -- is our pipe in the fruit?
    if self:isPipeOnLeft() then
        return self.fruitLeft > self.fruitRight
    else
        return self.fruitLeft < self.fruitRight
    end
end

---@return number, number the amount of fruit on left/right side of the combine. 0 is no fruit, and it is probably
--- a number up to 100, indicating how much fruit is there.
function AIDriveStrategyCombineCourse:getFruitAtSides()
    return self.fruitLeft, self.fruitRight
end

--- Check both sides of the combine/chopper to see if we are at the edge of the field and if there is fruit there.
--- This is to direct the unloader to the side where there is no fruit.
function AIDriveStrategyCombineCourse:checkFruit()
    local workWidth = self:getWorkWidth()

    local x, _, z = localToWorld(self.vehicle:getAIDirectionNode(), workWidth, 0, 0)
    self.fieldOnLeft = CpFieldUtil.isOnField(x, z)
    _, self.fruitLeft = PathfinderUtil.hasFruit(x, z, 1, 1)
    self.fruitLeft = self.fruitLeft or 0

    x, _, z = localToWorld(self.vehicle:getAIDirectionNode(), -workWidth, 0, 0)
    self.fieldOnRight = CpFieldUtil.isOnField(x, z)
    _, self.fruitRight = PathfinderUtil.hasFruit(x, z, 1, 1)
    self.fruitRight = self.fruitRight or 0

    self:debug('Fruit left: %.2f right %.2f, field on left %s, right %s',
            self.fruitLeft, self.fruitRight, tostring(self.fieldOnLeft), tostring(self.fieldOnRight))
end

--- Estimate the waypoint where the combine will be full/reach the fill level where it should start unloading
--- (waypointIxWhenFull/waypointIxWhenCallUnloader), based on the current harvest rate
function AIDriveStrategyCombineCourse:estimateDistanceUntilFull(ix)
    -- calculate fill rate so the combine driver knows if it can make the next row without unloading
    local fillLevel = self.combineController:getFillLevel()
    local capacity = self.combineController:getCapacity()
    if ix > 1 then
        local dToNext = self.course:getDistanceToNextWaypoint(ix - 1)
        if self.fillLevelAtLastWaypoint and self.fillLevelAtLastWaypoint > 0 and self.fillLevelAtLastWaypoint <= fillLevel then
            local litersPerMeter
            if dToNext > 0.1 then
                litersPerMeter = (fillLevel - self.fillLevelAtLastWaypoint) / dToNext
            else
                -- use the last known liters per meter if the distance is too short
                litersPerMeter = self.litersPerMeter
            end
            local litersPerSecond = 0
            if self.fillLevelLastCheckedTime and (self.fillLevelLastCheckedTime < g_currentMission.time) then
                litersPerSecond = (fillLevel - self.fillLevelAtLastWaypoint) /
                        ((g_currentMission.time - self.fillLevelLastCheckedTime) / 1000)
            end
            -- smooth everything a bit, also ignore 0
            self.litersPerMeter = litersPerMeter > 0 and ((self.litersPerMeter + litersPerMeter) / 2) or self.litersPerMeter
            self.litersPerSecond = litersPerSecond > 0 and ((self.litersPerSecond + litersPerSecond) / 2) or self.litersPerSecond
        else
            -- no history yet, so make sure we don't end up with some unrealistic numbers
            self.waypointIxWhenFull = nil
            self.litersPerMeter = 0
            self.litersPerSecond = 0
        end
        self:debug('Fill rate is %.1f l/m, %.1f l/s (fill level %.1f of %.1f, last %.1f, dToNext = %.1f)',
                self.litersPerMeter, self.litersPerSecond, fillLevel, capacity, self.fillLevelAtLastWaypoint, dToNext)
        self.fillLevelLastCheckedTime = g_currentMission.time
        self.fillLevelAtLastWaypoint = fillLevel
    end
    local litersUntilFull = capacity - fillLevel
    local dUntilFull = CpMathUtil.divide(litersUntilFull, self.litersPerMeter)
    local litersUntilCallUnloader = capacity * self.settings.callUnloaderPercent:getValue() / 100 - fillLevel
    local dUntilCallUnloader = CpMathUtil.divide(litersUntilCallUnloader, self.litersPerMeter)
    self.waypointIxWhenFull = self.course:getNextWaypointIxWithinDistance(ix, dUntilFull) or self.course:getNumberOfWaypoints()
    local wpDistance
    self.waypointIxWhenCallUnloader, wpDistance = self.course:getNextWaypointIxWithinDistance(ix, dUntilCallUnloader)
    self:debug('Will be full at waypoint %d, fill level %d at waypoint %d (current waypoint %d), %.1f m and %.1f l until call (currently %.1f l), wp distance %.1f',
            self.waypointIxWhenFull or -1, self.settings.callUnloaderPercent:getValue(), self.waypointIxWhenCallUnloader or -1,
            self.course:getCurrentWaypointIx(), dUntilCallUnloader, litersUntilCallUnloader, fillLevel, wpDistance)
end

function AIDriveStrategyCombineCourse:shouldWaitAtEndOfRow()
    if self.settings.selfUnload:getValue() then
        -- don't wait for anyone when self unloading
        return false
    end
    local nextRowStartIx = self.course:getNextRowStartIx(self.ppc:getRelevantWaypointIx())
    local lastPassedWaypointIx = self.ppc:getLastPassedWaypointIx() or self.ppc:getRelevantWaypointIx()
    local distanceToNextTurn = self.course:getDistanceToNextTurn(lastPassedWaypointIx) or math.huge
    local closeToTurn = distanceToNextTurn < AIDriveStrategyCombineCourse.safeUnloadDistanceBeforeEndOfRow
    -- If close to the end of the row and the pipe would be in the fruit after the turn, and our fill level is high,
    -- we always wait here for an unloader, regardless of having a rendezvous or not (unless we have our pipe in fruit here)
    if nextRowStartIx and closeToTurn and
            self:isPipeInFruitAt(nextRowStartIx) and
            self:isFull(AIDriveStrategyCombineCourse.waitForUnloadAtEndOfRowFillLevelThreshold) then
        self:checkFruit()
        if not self:isPipeInFruit() then
            self:debug('shouldWaitAtEndOfRow: Closer than %.1f m to a turn, pipe would be in fruit after turn at %d, fill level over %.1f',
                    AIDriveStrategyCombineCourse.safeUnloadDistanceBeforeEndOfRow, nextRowStartIx,
                    AIDriveStrategyCombineCourse.waitForUnloadAtEndOfRowFillLevelThreshold)
            return true
        end
    end
    -- Or, if we are close to the turn and have a rendezvous waypoint before the turn
    if nextRowStartIx and closeToTurn and
            self.unloaderRendezvousWaypointIx and
            nextRowStartIx > self.unloaderRendezvousWaypointIx then
        self:debug('shouldWaitAtEndOfRow: Closer than %.1f m to a turn and rendezvous waypoint %d is before the turn, waiting for the unloader here',
                AIDriveStrategyCombineCourse.safeUnloadDistanceBeforeEndOfRow, self.unloaderRendezvousWaypointIx)
        return true
    end
end

------------------------------------------------------------------------------------------------------------------------
--- Unloader handling
---
--- We need to answer the following questions:
--- 1. When to call the unloader?
--- 2. Where to meet the unloader?
--- 3. Which unloader to call?
---
--- To question #3, we check the distance between the unloader and the target (combine and a rendezvous point) and based
--- on the unloader's distance to the target and its fill level, we calculate a score and call the unloader with
--- the best score.
---
--- To questions #1 and #2, we have to cases:
---
--- The easy case
---
--- If the combine is stopped for unloading (either 100% full, or made a pocket or finished the course, etc.),
--- the unloader must drive to the combine immediately.
---
--- The difficult case
---
--- The combine is still harvesting, and periodically calculates the waypoint/distance where it will reach the fill
--- level threshold configured. This is the fill level when we want the unload process to start, so the unloader
--- is supposed to meet the combine at that (rendezvous) spot. This answers #2, where to meet the unloader.
--- But when to call the unloader? When it will reach the rendezvous point about the same time (or a little earlier)
--- as the combine reaches it. So we ask around all unloaders to figure out what their estimated time en-route (ETE)
--- to the rendezvous waypoint would be. Then pick the one with the shortest ETE, and if its ETE (plus some reserve)
--- is more than the combine's ETE, call it.
---
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyCombineCourse:callUnloaderWhenNeeded()
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
        self:debug('callUnloaderWhenNeeded: stopped, need unloader here')
        bestUnloader, _ = self:findUnloader(self.vehicle, nil)
        if bestUnloader then
            bestUnloader:getCpDriveStrategy():call(self.vehicle, nil)
        end
    else
        if not self.waypointIxWhenCallUnloader then
            self:debug('callUnloaderWhenNeeded: don\'t know yet where to meet the unloader')
            return
        end
        -- Find a good waypoint to unload, as the calculated one may have issues, like pipe would be in the fruit,
        -- or in a turn, etc.
        -- TODO: isPipeInFruitAllowed
        local tentativeRendezvousWaypointIx = self:findBestWaypointToUnload(self.waypointIxWhenCallUnloader, false)
        if not tentativeRendezvousWaypointIx then
            self:debug('callUnloaderWhenNeeded: can\'t find a good waypoint to meet the unloader')
            return
        end
        bestUnloader, bestEte = self:findUnloader(nil, self.course:getWaypoint(tentativeRendezvousWaypointIx))
        -- getSpeedLimit() may return math.huge (inf), when turning for example, not sure why, and that throws off
        -- our ETE calculation
        if bestUnloader and self.vehicle:getSpeedLimit(true) < 100 then
            local dToUnloadWaypoint = self.course:getDistanceBetweenWaypoints(tentativeRendezvousWaypointIx,
                    self.course:getCurrentWaypointIx())
            local myEte = dToUnloadWaypoint / (self.vehicle:getSpeedLimit(true) / 3.6)
            self:debug('callUnloaderWhenNeeded: best unloader ETE at waypoint %d %.1fs, my ETE %.1fs',
                    tentativeRendezvousWaypointIx, bestEte, myEte)
            if bestEte - 5 > myEte then
                -- I'll be at the rendezvous a lot earlier than the unloader which will almost certainly result in the
                -- cancellation of the rendezvous.
                -- So, set something up further away, with better chances,
                -- using the unloader's ETE, knowing that 1) that ETE is for the current rendezvous point, 2) there
                -- may be another unloader selected for that waypoint
                local dToTentativeRendezvousWaypoint = bestEte * (self.vehicle:getSpeedLimit(true) / 3.6)
                self:debug('callUnloaderWhenNeeded: too close to rendezvous waypoint, trying move it %.1fm',
                        dToTentativeRendezvousWaypoint)
                tentativeRendezvousWaypointIx = self.course:getNextWaypointIxWithinDistance(
                        self.course:getCurrentWaypointIx(), dToTentativeRendezvousWaypoint)
                if tentativeRendezvousWaypointIx then
                    bestUnloader, bestEte = self:findUnloader(nil, self.course:getWaypoint(tentativeRendezvousWaypointIx))
                    if bestUnloader then
                        self:callUnloader(bestUnloader, tentativeRendezvousWaypointIx, bestEte)
                    end
                else
                    self:debug('callUnloaderWhenNeeded: still can\'t find a good waypoint to meet the unloader')
                end
            elseif bestEte + 5 > myEte then
                -- do not call too early (like minutes before we get there), only when it needs at least as
                -- much time to get there as the combine (-5 seconds)
                self:callUnloader(bestUnloader, tentativeRendezvousWaypointIx, bestEte)
            end
        end
    end
end

function AIDriveStrategyCombineCourse:callUnloader(bestUnloader, tentativeRendezvousWaypointIx, bestEte)
    if bestUnloader:getCpDriveStrategy():call(self.vehicle,
            self.course:getWaypoint(tentativeRendezvousWaypointIx)) then
        self.unloaderToRendezvous:set(bestUnloader, 1000 * (bestEte + 30))
        self.unloaderRendezvousWaypointIx = tentativeRendezvousWaypointIx
        self:debug('callUnloaderWhenNeeded: harvesting, unloader accepted rendezvous at waypoint %d', self.unloaderRendezvousWaypointIx)
    else
        self:debug('callUnloaderWhenNeeded: harvesting, unloader rejected rendezvous at waypoint %d', tentativeRendezvousWaypointIx)
    end
end

---@param vehicle table
---@return boolean true if vehicle is an active Courseplay controlled combine/harvester
function AIDriveStrategyCombineCourse.isActiveCpCombine(vehicle)
    if not (vehicle.getIsCpActive and vehicle:getIsCpActive()) then
        -- not driven by CP
        return false
    end
    local driveStrategy = vehicle.getCpDriveStrategy and vehicle:getCpDriveStrategy()
    return driveStrategy and driveStrategy.callUnloader ~= nil
end

--- Find an unloader to drive to the target, which may either be the combine itself (when stopped and waiting for unload)
--- or a waypoint which the combine will reach in the future. Combine and waypoint parameters are mutually exclusive.
---@param combine table the combine vehicle if we need the unloader come to the combine, otherwise nil
---@param waypoint Waypoint the waypoint where the unloader should meet the combine, otherwise nil.
---@return table, number the best fitting unloader or nil, the estimated time en-route for the unloader to reach the
--- target (combine or waypoint)
function AIDriveStrategyCombineCourse:findUnloader(combine, waypoint)
    local bestScore = -math.huge
    local bestUnloader, bestEte
    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if AIDriveStrategyUnloadCombine.isActiveCpCombineUnloader(vehicle) then
            local x, _, z = getWorldTranslation(self.vehicle.rootNode)
            ---@type AIDriveStrategyUnloadCombine
            local driveStrategy = vehicle:getCpDriveStrategy()
            -- look a bit outside of the field as the harvester's root node may be just off the field (like in a turn,
            -- or when starting.
            if driveStrategy:isServingPosition(x, z, 10) then
                local unloaderFillLevelPercentage = driveStrategy:getFillLevelPercentage()
                if driveStrategy:isAllowedToBeCalled() and unloaderFillLevelPercentage < 99 then
                    local unloaderDistance, unloaderEte
                    if combine then
                        -- if already stopped, we want the unloader to come to us
                        unloaderDistance, unloaderEte = driveStrategy:getDistanceAndEteToVehicle(combine)
                    elseif self.waypointIxWhenCallUnloader then
                        -- if still going, we want the unloader to meet us at the waypoint
                        unloaderDistance, unloaderEte = driveStrategy:getDistanceAndEteToWaypoint(waypoint)
                    end
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

function AIDriveStrategyCombineCourse:checkRendezvous()
    if self.unloaderToRendezvous:get() then
        local lastPassedWaypointIx = self.ppc:getLastPassedWaypointIx() or self.ppc:getRelevantWaypointIx()
        local d = self.course:getDistanceBetweenWaypoints(lastPassedWaypointIx, self.unloaderRendezvousWaypointIx)
        if d < 10 then
            self:debugSparse('Slow down around the unloader rendezvous waypoint %d to let the unloader catch up',
                    self.unloaderRendezvousWaypointIx)
            self:setMaxSpeed(self.settings.fieldWorkSpeed:getValue() / 2)
        elseif lastPassedWaypointIx > self.unloaderRendezvousWaypointIx then
            -- past the rendezvous waypoint
            self:debug('Unloader missed the rendezvous at %d', self.unloaderRendezvousWaypointIx)
            local unloaderWhoDidNotShowUp = self.unloaderToRendezvous:get()
            -- need to call this before onMissedRendezvous as the unloader will call back to set up a new rendezvous
            -- and we don't want to cancel that right away
            self:cancelRendezvous()
            unloaderWhoDidNotShowUp:getCpDriveStrategy():onMissedRendezvous(self.vehicle)
        end
        if self:isDischarging() then
            self:debug('Discharging, cancelling unloader rendezvous')
            self:cancelRendezvous()
        end
    end
end

function AIDriveStrategyCombineCourse:hasRendezvousWith(unloader)
    return self.unloaderToRendezvous:get() == unloader
end

function AIDriveStrategyCombineCourse:cancelRendezvous()
    local unloader = self.unloaderToRendezvous:get()
    self:debug('Rendezvous with %s at waypoint %d cancelled',
            unloader and CpUtil.getName(self.unloaderToRendezvous:get() or 'N/A'),
            self.unloaderRendezvousWaypointIx or -1)
    self.unloaderRendezvousWaypointIx = nil
    self.unloaderToRendezvous:reset()
end

--- Before the unloader asks for a rendezvous (which may result in a lengthy pathfinding to figure out
--- the distance), it should check if the combine is willing to rendezvous.
function AIDriveStrategyCombineCourse:isWillingToRendezvous()
    if self.state ~= self.states.WORKING then
        self:debug('not harvesting, will not rendezvous')
        return nil
    elseif not self.settings.unloadOnFirstHeadland:getValue() and
            self.course:isOnHeadland(self.course:getCurrentWaypointIx(), 1) then
        self:debug('on first headland and unload not allowed on first headland, will not rendezvous')
        return nil
    end
    return true
end

--- An area where the combine is expected to perform a turn between now and the rendezvous waypoint
---@return Waypoint a waypoint, the center of the maneuvering area
---@return number radius around the waypoint, defining a circular area
function AIDriveStrategyCombineCourse:getTurnArea()
    if self.unloaderRendezvousWaypointIx then
        for ix = self.course:getCurrentWaypointIx(), self.unloaderRendezvousWaypointIx do
            if self.course:isTurnEndAtIx(ix) then
                return self.course:getWaypoint(ix), self.turningRadius * 3
            end
        end
    end
end

function AIDriveStrategyCombineCourse:canUnloadWhileMovingAtWaypoint(ix)
    if self:isPipeInFruitAt(ix) then
        self:debug('pipe would be in fruit at the planned rendezvous waypoint %d', ix)
        return false
    end
    if not self.settings.unloadOnFirstHeadland:getValue() and self.course:isOnHeadland(ix, 1) then
        self:debug('planned rendezvous waypoint %d is on first headland, no unloading of moving combine there', ix)
        return false
    end
    return true
end

function AIDriveStrategyCombineCourse:checkFruitAtNode(node, offsetX, offsetZ)
    local x, _, z = localToWorld(node, offsetX, 0, offsetZ or 0)
    local hasFruit, fruitValue = PathfinderUtil.hasFruit(x, z, 1, 1)
    return hasFruit, fruitValue
end

--- Is pipe in fruit according to the current field harvest state at waypoint?
function AIDriveStrategyCombineCourse:isPipeInFruitAtWaypointNow(course, ix)
    if not self.storage.fruitCheckHelperWpNode then
        self.storage.fruitCheckHelperWpNode = WaypointNode(CpUtil.getName(self.vehicle) .. 'fruitCheckHelperWpNode')
    end
    self.storage.fruitCheckHelperWpNode:setToWaypoint(course, ix)
    local hasFruit, fruitValue = self:checkFruitAtNode(self.storage.fruitCheckHelperWpNode.node, self.pipeController:getPipeOffsetX())
    self:debug('at waypoint %d pipe in fruit %s (fruitValue %.1f)', ix, tostring(hasFruit), fruitValue or 0)
    return hasFruit, fruitValue
end

function AIDriveStrategyCombineCourse:isPipeInFruitAt(ix)
    if self.course:getMultiTools() > 1 then
        -- we don't have a reliable pipe in fruit map for multitools, so just check
        -- if there is fruit at the waypoint now, to be on the safe side
        return self:isPipeInFruitAtWaypointNow(self.course, ix)
    else
        return self.course:isPipeInFruitAt(ix)
    end
end

--- Find the best waypoint to unload.
---@param ix number waypoint index we want to start unloading, either because that's about where
--- we'll rendezvous the unloader or we'll be full there.
---@return number best waypoint to unload, ix may be adjusted to make sure it isn't in a turn or
--- the fruit is not in the pipe.
function AIDriveStrategyCombineCourse:findBestWaypointToUnload(ix, isPipeInFruitAllowed)
    if self.course:isOnHeadland(ix) then
        return self:findBestWaypointToUnloadOnHeadland(ix)
    else
        return self:findBestWaypointToUnloadOnUpDownRows(ix, isPipeInFruitAllowed)
    end
end

function AIDriveStrategyCombineCourse:findBestWaypointToUnloadOnHeadland(ix)
    if not self.settings.unloadOnFirstHeadland:getValue() and
            self.course:isOnHeadland(ix, 1) then
        self:debug('planned rendezvous waypoint %d is on first headland, no unloading of moving combine there', ix)
        return nil
    end
    if self.course:isTurnStartAtIx(ix) then
        -- on the headland, use the wp after the turn, the one before may be very far, especially on a
        -- transition from headland to up/down rows.
        return ix + 1
    else
        return ix
    end
end

--- We calculated a waypoint to meet the unloader (either because it asked for it or we think we'll need
--- to unload. Now make sure that this location is not around a turn or the pipe isn't in the fruit by
--- trying to move it up or down a bit. If that's not possible, just leave it and see what happens :)
function AIDriveStrategyCombineCourse:findBestWaypointToUnloadOnUpDownRows(ix, isPipeInFruitAllowed)
    local dToNextTurn = self.course:getDistanceToNextTurn(ix) or math.huge
    local lRow, ixAtRowStart = self.course:getRowLength(ix)
    local pipeInFruit = self:isPipeInFruitAt(ix)
    local currentIx = self.course:getCurrentWaypointIx()
    local newWpIx = ix
    self:debug('Looking for a waypoint to unload around %d on up/down row, pipe in fruit %s, dToNextTurn: %d m, lRow = %d m',
            ix, tostring(pipeInFruit), dToNextTurn, lRow or 0)
    if pipeInFruit and not isPipeInFruitAllowed then
        --if the pipe is in fruit AND the user selects 'avoid fruit'
        if ixAtRowStart then
            if self.course:getMultiTools() > 1 then
                self:debug('Pipe may be in fruit at waypoint %d, we have no reliable information as multitool active, rejecting rendezvous', ix)
                newWpIx = nil
            elseif ixAtRowStart > currentIx then
                -- have not started the previous row yet
                self:debug('Pipe would be in fruit at waypoint %d. Check previous row', ix)
                pipeInFruit, _ = self:isPipeInFruitAt(ixAtRowStart - 2) -- wp before the turn start
                if not pipeInFruit then
                    local lPreviousRow, ixAtPreviousRowStart = self.course:getRowLength(ixAtRowStart - 1)
                    self:debug('pipe not in fruit in the previous row (%d m, ending at wp %d), rendezvous at %d',
                            lPreviousRow, ixAtRowStart - 1, newWpIx)
                    newWpIx = math.max(ixAtRowStart - 3, ixAtPreviousRowStart, currentIx)
                else
                    self:debug('Pipe in fruit in previous row too, rejecting rendezvous')
                    newWpIx = nil
                end
            else
                -- previous row already started. Could check next row but that means the rendezvous would be after
                -- the combine turns, and we'd be in the way during the turn, so rather not worry about the next row
                -- until the combine gets there.
                self:debug('Pipe would be in fruit at waypoint %d. Previous row is already started, no rendezvous', ix)
                newWpIx = nil
            end
        else
            self:debug('Could not determine row length, rejecting rendezvous')
            newWpIx = nil
        end
    else
        if (pipeInFruit) then
            self:debug('pipe would be in fruit at waypoint %d, acceptable for user', ix)
        else
            self:debug('pipe is not in fruit at %d. If it is towards the end of the row, bring it up a bit', ix)
        end
        -- so we'll have some distance for unloading
        if ixAtRowStart and dToNextTurn < AIDriveStrategyCombineCourse.safeUnloadDistanceBeforeEndOfRow then
            local safeIx = self.course:getPreviousWaypointIxWithinDistance(ix,
                    AIDriveStrategyCombineCourse.safeUnloadDistanceBeforeEndOfRow)
            newWpIx = math.max(ixAtRowStart + 1, safeIx or -1, ix - 4, currentIx)
        end
    end
    -- no better idea, just use the original estimated, making sure we avoid turn start waypoints
    if newWpIx and self.course:isTurnStartAtIx(newWpIx) then
        self:debug('Calculated rendezvous waypoint is at turn start, moving it up')
        -- make sure it is not on the turn start waypoint
        return math.max(newWpIx - 1, currentIx)
    else
        return newWpIx
    end
end

--- Create a temporary course to pull back to the right when the pipe is in the fruit so the tractor does not have
-- to drive in the fruit to get under the pipe
function AIDriveStrategyCombineCourse:createPullBackCourse()
    -- all we need is a waypoint on our right side towards the back
    self.returnPoint = {}
    self.returnPoint.x, _, self.returnPoint.z = getWorldTranslation(self.vehicle.rootNode)

    local dx, _, dz = localDirectionToWorld(self.vehicle:getAIDirectionNode(), 0, 0, 1)
    self.returnPoint.rotation = MathUtil.getYRotationFromDirection(dx, dz)
    dx, _, dz = localDirectionToWorld(self.vehicle:getAIDirectionNode(), 0, 0, -1)

    local x1, _, z1 = localToWorld(self.vehicle:getAIDirectionNode(), -self.pullBackRightSideOffset, 0, -self.pullBackDistanceStart)
    local x2, _, z2 = localToWorld(self.vehicle:getAIDirectionNode(), -self.pullBackRightSideOffset, 0, -self.pullBackDistanceEnd)
    -- both points must be on the field
    if CpFieldUtil.isOnField(x1, z1) and CpFieldUtil.isOnField(x2, z2) then

        local referenceNode, debugText = AIUtil.getReverserNode(self.vehicle)
        if referenceNode then
            self:debug('Using %s to start pull back course', debugText)
        else
            referenceNode = AIUtil.getDirectionNode(self.vehicle)
            self:debug('Using the direction node to start pull back course')
        end
        -- don't make this too complicated, just create a straight line on the left/right side (depending on
        -- where the pipe is and rely on the PPC, no need for generating fancy curves
        return Course.createFromNode(self.vehicle, referenceNode,
                -self.pullBackRightSideOffset, 0, -self.pullBackDistanceEnd, -2, true)
    else
        self:debug("Pull back course would be outside of the field")
        return nil
    end
end

--- Get the area the unloader should avoid when approaching the combine.
--- Main (and for now, only) use case is to prevent the unloader to cross in front of the combine after the
--- combine pulled back full with pipe in the fruit, making room for the unloader on its left side.
--- @return table, number, number, number, number node, xOffset, zOffset, width, length : the area to avoid is
--- a length x width m rectangle, the rectangle's bottom right corner (when looking from node) is at xOffset/zOffset
--- from node.
function AIDriveStrategyCombineCourse:getAreaToAvoid()
    if self:isWaitingForUnloadAfterPulledBack() then
        local xOffset = self:getWorkWidth() / 2
        local zOffset = 0
        local length = self.pullBackDistanceEnd
        local width = self.pullBackRightSideOffset
        return PathfinderUtil.NodeArea(AIUtil.getDirectionNode(self.vehicle), xOffset, zOffset, width, length)
    end
end

--- Create a temporary course to make a pocket in the fruit on the right (or left), so we can move into that pocket and
--- wait for the unload there. This way the unload tractor does not have to leave the field.
--- We create a temporary course to reverse back far enough. After that, we return to the main course but
--- set an offset to the right (or left)
function AIDriveStrategyCombineCourse:createPocketCourse()
    local startIx = self.ppc:getLastPassedWaypointIx() or self.ppc:getCurrentWaypointIx()
    -- find the waypoint we want to back up to
    local backIx = self.course:getPreviousWaypointIxWithinDistance(startIx, self.pocketReverseDistance)
    if not backIx then
        return nil
    end
    -- this where we are back on track after returning from the pocket
    self.returnedFromPocketIx = self.ppc:getCurrentWaypointIx()
    self:debug('Backing up %.1f meters from waypoint %d to %d to make a pocket', self.pocketReverseDistance, startIx, backIx)
    if startIx - backIx > 2 then
        local pocketReverseWaypoints = {}
        for i = startIx, backIx, -1 do
            if self.course:isTurnStartAtIx(i) then
                self:debug('There is a turn behind me at waypoint %d, no pocket', i)
                return nil
            end
            local x, _, z = self.course:getWaypointPosition(i)
            table.insert(pocketReverseWaypoints, { x = x, z = z, rev = true })
        end
        return Course(self.vehicle, pocketReverseWaypoints, true), backIx + 1
    else
        self:debug('Not enough waypoints behind me, no pocket')
        return nil
    end
end

--- Only allow fuel save, if no trailer is under the pipe and we are waiting for unloading.
function AIDriveStrategyCombineCourse:isFuelSaveAllowed()
    if self.pipeController:isFillableTrailerInRange() then
        -- Disables Fuel save, when a trailer is under the pipe.
        return false
    end
    --- Enables fuel save, while waiting for the rain to stop.
    if self.combine:getIsThreshingDuringRain() then
        return true
    end
    return self:isWaitingForUnload() or self:isChopperWaitingForUnloader()
            or AIDriveStrategyCourse.isFuelSaveAllowed(self)
end

--- Check if the vehicle should stop during a turn for example while it
--- is held for unloading or waiting for the straw swath to stop
function AIDriveStrategyCombineCourse:shouldHoldInTurnManeuver()
    --- Hold during discharge
    local discharging = self:isDischarging() and not self:alwaysNeedsUnloader()
    local stillProcessingFruit = self:alwaysNeedsUnloader() and self:isProcessingFruit()
    local isFinishingRow = self.aiTurn and self.aiTurn:isFinishingRow()
    local waitForStraw = self.combineController:isDroppingStrawSwath() and not isFinishingRow and not self:isOnHeadland()

    self:debugSparse('Turn maneuver=> Autoaim: %s, discharging: %s, wait for straw: %s, straw swath active: %s, processing: %s, finishing row: %s',
            tostring(self:hasAutoAimPipe()), tostring(discharging), tostring(waitForStraw),
            tostring(self.combineController:isDroppingStrawSwath()), tostring(stillProcessingFruit), tostring(isFinishingRow))
    -- choppers don't hold, they need to keep moving through turns and actively harvesting
    return (discharging or waitForStraw or stillProcessingFruit) and not self:hasAutoAimPipe()
end

--- Should we return to the first point of the course after we are done?
function AIDriveStrategyCombineCourse:shouldReturnToFirstPoint()
    -- Combines stay where they are after finishing work
    -- TODO: call unload driver
    return false
end

--- Interface for the unloader and AutoDrive
---@return boolean true when the combine is waiting to be unloaded (and won't move until the unloader gets there)
function AIDriveStrategyCombineCourse:isWaitingForUnload()
    return self.state == self.states.UNLOADING_ON_FIELD and
            (self.unloadState == self.states.WAITING_FOR_UNLOAD_ON_FIELD or
                    self.unloadState == self.states.WAITING_FOR_UNLOAD_IN_POCKET or
                    self.unloadState == self.states.WAITING_FOR_UNLOAD_AFTER_PULLED_BACK or
                    self.unloadState == self.states.WAITING_FOR_UNLOAD_AFTER_FIELDWORK_ENDED or
                    self.unloadState == self.states.WAITING_FOR_UNLOAD_BEFORE_STARTING_NEXT_ROW)
end

--- Interface for AutoDrive
---@return boolean true when the combine is waiting to be unloaded after it ended the course
function AIDriveStrategyCombineCourse:isWaitingForUnloadAfterCourseEnded()
    return self.state == self.states.UNLOADING_ON_FIELD and
            self.unloadState == self.states.WAITING_FOR_UNLOAD_AFTER_FIELDWORK_ENDED
end

function AIDriveStrategyCombineCourse:isWaitingInPocket()
    return self.state == self.states.UNLOADING_ON_FIELD and
            self.unloadState == self.states.WAITING_FOR_UNLOAD_IN_POCKET
end

--- Interface for Mode 2
---@return boolean true when the combine is waiting to after it pulled back.
function AIDriveStrategyCombineCourse:isWaitingForUnloadAfterPulledBack()
    return self.state == self.states.UNLOADING_ON_FIELD and
            self.unloadState == self.states.WAITING_FOR_UNLOAD_AFTER_PULLED_BACK
end

---@return boolean the combine is about to turn
function AIDriveStrategyCombineCourse:isAboutToTurn()
    if self.state == self.states.WORKING and self.course then
        return self.course:isCloseToNextTurn(10)
    else
        return false
    end
end

--- Can the cutter be turned off ?
function AIDriveStrategyCombineCourse:getCanCutterBeTurnedOff()
    return self:isWaitingForUnload() or
            (self.state == self.states.UNLOADING_ON_FIELD and self:isUnloadStateOneOf(self.selfUnloadStates) and
                    -- we want that cutter to be turned on when returning to fieldwork after self unload
                    self.unloadState ~= self.states.RETURNING_FROM_SELF_UNLOAD)
end

-----------------------------------------------------------------------------------------------------------------------
--- Turns
-----------------------------------------------------------------------------------------------------------------------

--- Will we be driving forward only (not reversing) during a turn
function AIDriveStrategyCombineCourse:isTurnForwardOnly()
    return self:isTurning() and self.aiTurn and self.aiTurn:isForwardOnly()
end

function AIDriveStrategyCombineCourse:getTurnCourse()
    return self.aiTurn and self.aiTurn:getCourse()
end

function AIDriveStrategyCombineCourse:startTurn(ix)
    self:debug('    Starting a combine turn.')

    self.turnContext = TurnContext(self.vehicle, self.course, ix, ix + 1, self.turnNodes, self:getWorkWidth(),
            self.frontMarkerDistance, self.backMarkerDistance,
            self:getTurnEndSideOffset(self.course:isHeadlandTurnAtIx(ix + 1)), self:getTurnEndForwardOffset())

    -- Combines drive special headland corner maneuvers, except potato and sugarbeet harvesters
    if self.turnContext:isHeadlandCorner() then
        if self.combineController:isTowed() then
            self:debug('Headland turn but this is a towed harvester using normal turn maneuvers.')
            AIDriveStrategyFieldWorkCourse.startTurn(self, ix)
        elseif self.course:isOnConnectingPath(ix) then
            self:debug('Headland turn but this a connecting track, use normal turn maneuvers.')
            AIDriveStrategyFieldWorkCourse.startTurn(self, ix)
        elseif self.course:isOnOutermostHeadland(ix) and self:isTurnOnFieldActive() and
                not self.combineController:isRootVegetableHarvester() and
                not g_vehicleConfigurations:getRecursively(self.vehicle, 'disablePocket') then
            self:debug('Creating a pocket in the corner so the combine stays on the field during the turn')
            self.aiTurn = CombinePocketHeadlandTurn(self.vehicle, self, self.ppc, self.proximityController, self.turnContext,
                    self.course, self:getWorkWidth())
            self.state = self.states.TURNING
            self.ppc:setShortLookaheadDistance()
        else
            self:debug('Use combine headland turn.')
            self.aiTurn = CombineHeadlandTurn(self.vehicle, self, self.ppc, self.proximityController, self.turnContext)
            self.state = self.states.TURNING
        end
    else
        self:debug('Non headland turn.')
        if self.settings.selfUnload:getValue() and self:shouldSelfUnloadBeforeNextRow() then
            self:debug('Fill level over %.0f, attempt to self unload before continue with next row',
                    AIDriveStrategyCombineCourse.selfUnloadBeforeNextRowFillLevelThreshold)
            -- will continue at the turn end waypoint after the unload is finished
            self:rememberCourse(self.fieldWorkCourse, ix + 1)
            self.aiTurn = FinishRowOnly(self.vehicle, self, self.ppc, self.proximityController, self.turnContext)
            self.aiTurn:registerTurnEndCallback(self, AIDriveStrategyCombineCourse.startSelfUnloadBeforeNextRow)
            self.state = self.states.TURNING
            -- continue at the turn end waypoint on failed pathfinding
            self.waypointIxToContinueOnFailedSelfUnload = ix + 1
        else
            AIDriveStrategyFieldWorkCourse.startTurn(self, ix)
        end
    end
end

function AIDriveStrategyCombineCourse:isTurning()
    return self.state == self.states.TURNING
end

-- Turning except in the ending turn phase which isn't really a turn, it is rather 'starting row'
function AIDriveStrategyCombineCourse:isTurningButNotEndingTurn()
    return self:isTurning() and self.aiTurn and not self.aiTurn:isEndingTurn()
end

function AIDriveStrategyCombineCourse:isFinishingRow()
    return self:isTurning() and self.aiTurn and self.aiTurn:isFinishingRow()
end

function AIDriveStrategyCombineCourse:getTurnStartWpIx()
    return self.turnContext and self.turnContext.turnStartWpIx or nil
end

function AIDriveStrategyCombineCourse:isTurningOnHeadland()
    return self.state == self.states.TURNING and self.turnContext and self.turnContext:isHeadlandCorner()
end

function AIDriveStrategyCombineCourse:isTurningLeft()
    return self.state == self.states.TURNING and self.turnContext and self.turnContext:isLeftTurn()
end

function AIDriveStrategyCombineCourse:getFieldworkCourse()
    return self.course
end

function AIDriveStrategyCombineCourse:alwaysNeedsUnloader()
    return self.combineController:alwaysNeedsUnloader()
end

function AIDriveStrategyCombineCourse:isProcessingFruit()
    return self.combineController:isProcessingFruit()
end

function AIDriveStrategyCombineCourse:isFillableTrailerUnderPipe()
    return self.pipeController:isFillableTrailerUnderPipe()
end

function AIDriveStrategyCombineCourse:hasAutoAimPipe()
    return self.pipeController:isAutoAimPipe()
end

function AIDriveStrategyCombineCourse:isChopper()
    return self.combineController:isChopper()
end

-----------------------------------------------------------------------------------------------------------------------
--- Pipe handling
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyCombineCourse:handlePipe(dt)
    if self:isChopper() then
        self.pipeController:handleChopperPipe()
    else
        self:handleCombinePipe(dt)
    end
end

function AIDriveStrategyCombineCourse:handleCombinePipe(dt)
    -- don't open the pipe while turning or driving to self unload
    -- open it when there's a trailer in range or when AutoDrive wants us to open it
    if self:isPipeOpenEnabled() and (self:isAGoodTrailerInRange() or self:isAutoDriveWaitingForPipe()) then
        if not self.forcePipeClose:get() then
            -- just closed it after unloading, don't open it again right away, wait a bit, as we should now be moving
            -- away from the trailer
            self.pipeController:openPipe()
        end
    else
        if not self.forcePipeOpen:get() then
            -- when driving to self unload, we may open the pipe well before reaching the trailer to avoid
            -- banging it into the trailer. This is configurable, and needed for harvester opening their pipe
            -- upwards
            self.pipeController:closePipe(true)
        end
    end
    -- Close the pipe if configured to do so after unloading
    if self.pipeController:isPipeOpen() and self.pipeController:justStoppedDischarging() then
        if g_vehicleConfigurations:get(self.vehicle, 'closePipeAfterUnload') then
            self:debug('Closing pipe after unloading done.')
            self.pipeController:closePipe()
            -- TODO: now with the canWorkWhenOpen() check we may not need this anymore
            self.forcePipeClose:set(true, 2000)
        end
    end
    -- This is to avoid reopening the pipe, if it is configured to close after unloading.
    -- After unloading finished, check for anything in range, ignore trailer fill state, as all we want
    -- is to wait until the trailer is out of range.
    if self.forcePipeClose:get() and self.pipeController:isSomethingInRange() then
        self.forcePipeClose:setAndProlong(true, 2000)
        self:debugSparse('Pipe open disabled, trailer still in range after unloading...')
    end
end

--- we don't want random triggers to open the pipe while turning or driving to another trailer
function AIDriveStrategyCombineCourse:isPipeOpenEnabled()
    if self:isTurning() then
        return false
    elseif self.state == self.states.UNLOADING_ON_FIELD and
            self:isUnloadStateOneOf(self.drivingToSelfUnloadStates) and not self:isCloseToCourseEnd(10) then
        return false
    else
        return true
    end
end

function AIDriveStrategyCombineCourse:isAGoodTrailerInRange()
    local _, trailer = self.pipeController:isFillableTrailerInRange()
    local unloaderVehicle = trailer and trailer:getRootVehicle()

    if unloaderVehicle == nil then
        return false
    end

    if AIDriveStrategyUnloadCombine.isActiveCpCombineUnloader(unloaderVehicle) then
        return unloaderVehicle:getCpDriveStrategy():getCombineToUnload() == self.vehicle
    else
        return true
    end
end

--- Not exactly sure what this does, but without this the chopper just won't move.
--- Copied from AIDriveStrategyCombine:update()
function AIDriveStrategyCombineCourse:updateChopperFillType()
    if self:isChopper() then
        self.combineController:updateChopperFillType()
    end
end

function AIDriveStrategyCombineCourse:isChopperWaitingForUnloader()
    return self.waitingForTrailer
end

function AIDriveStrategyCombineCourse:isAnyWorkAreaProcessing()
    for _, implement in pairs(self.vehicle:getChildVehicles()) do
        if implement.spec_workArea ~= nil then
            for i, workArea in pairs(implement.spec_workArea.workAreas) do
                if implement:getIsWorkAreaProcessing(workArea) then
                    return true
                end
            end
        end
    end
    return false
end

function AIDriveStrategyCombineCourse:isPipeMoving()
    return self.pipeController:isPipeMoving()
end

function AIDriveStrategyCombineCourse:canLoadTrailer(trailer)
    local fillType = self:getFillType()
    return FillLevelUtil.canLoadTrailer(trailer, fillType)
end

function AIDriveStrategyCombineCourse:getCurrentDischargeNode()
    return self.pipeController:getDischargeNode()
end

function AIDriveStrategyCombineCourse:getFillLevelPercentage()
    return self.combineController:getFillLevelPercentage()
end

--- Support for AutoDrive mod: they'll only find us if we open the pipe
function AIDriveStrategyCombineCourse:isAutoDriveWaitingForPipe()
    if self.vehicle.spec_autodrive then
        -- AutoDrive mod active on harvester
        if self:isWaitingForUnload() and self.vehicle.adHasHarvesterAvailableUnloader then
            -- AutoDrive has an unloader available for this harvester, and we are waiting for unload stopped,
            -- so open the pipe to let AutoDrive know we are ready and that it can get the exact pipe position
            -- and other properties from the harvester
            return self.vehicle:adHasHarvesterAvailableUnloader()
        elseif self.vehicle.spec_autodrive.combineIsCallingDriver then
            -- AutoDrive legacy interface for compatibility
            -- TODO: remove when most users have updated AutoDrive
            return self.vehicle.spec_autodrive:combineIsCallingDriver(self.vehicle)
        end
    end
    return false
end

function AIDriveStrategyCombineCourse:shouldStopForUnloading()
    if self.settings.stopForUnload:getValue() then
        if self:isDischarging() and not self.stopDisabledAfterEmpty:get() then
            -- stop only if the pipe is discharging AND we have been emptied a while ago.
            -- this makes sure the combine will start driving after it is emptied but the trailer
            -- is still under the pipe
            return true
        end
    end
    return false
end

function AIDriveStrategyCombineCourse:getFillType()
    return self.pipeController:getFillType()
end

-- even if there is a trailer in range, we should not start moving until the pipe is turned towards the
-- trailer and can start discharging. This returning true does not mean there's a trailer under the pipe,
-- this seems more like for choppers to check if there's a potential target around
function AIDriveStrategyCombineCourse:canDischarge()
    return self.pipeController:getDischargeObject()
end

function AIDriveStrategyCombineCourse:isDischarging()
    return self.pipeController:isDischarging()
end


-----------------------------------------------------------------------------------------------------------------------
--- Self unload
--- When self unload is enabled, instead of calling an unloader when full, the combine will find
--- a suitable trailer on or around the field, drive to the trailer and empty the grain tank into the trailer.
--- See SelfUnloadHelper.lua on how exactly a trailer is picked.
---
--- There are two events which can trigger a self unload:
--- 1. grain tank full
--- 2. grain tank at more than 60% when the combine just finished a row and there is a
---    trailer nearby.

-----------------------------------------------------------------------------------------------------------------------
--- Find a path to the best trailer to unload
function AIDriveStrategyCombineCourse:startSelfUnload(unloadStateAfterPathfindingDoneForSelfUnload,
                                                      bestTrailer, fillRootNode)

    if not self.pathfinder or not self.pathfinder:isActive() then
        self.pathfindingStartedAt = g_currentMission.time
        self.courseAfterPathfinding = nil
        self.waypointIxAfterPathfinding = nil

        local targetNode, alignLength, offsetX, trailer = SelfUnloadHelper:getTargetParameters(
                self.vehicle:cpGetFieldPolygon(),
                self.vehicle,
                self.implementWithPipe,
                self.pipeController,
                bestTrailer,
                fillRootNode)

        if not targetNode then
            return false
        end

        -- little straight section parallel to the trailer to align better
        self.selfUnloadAlignCourse = Course.createFromNode(self.vehicle, targetNode,
                offsetX, -alignLength + 1, -self.pipeController:getPipeOffsetZ() - 1, 1, false)

        self.unloadStateAfterPathfindingDoneForSelfUnload = unloadStateAfterPathfindingDoneForSelfUnload

        local fieldNum = CpFieldUtil.getFieldNumUnderVehicle(self.vehicle)
        local context = PathfinderContext(self.vehicle):mustBeAccurate(true)
        context:allowReverse(self:getAllowReversePathfinding()):useFieldNum(fieldNum)
        -- use no field penalty around the trailer to encourage the pathfinder to bridge that gap between the field
        -- and the trailer
        context:areaToIgnoreOffFieldPenalty(
                PathfinderUtil.NodeArea.createVehicleArea(trailer, 1.5 * SelfUnloadHelper.maxDistanceFromField))
        local result
        -- require full accuracy from pathfinder as we must exactly line up with the trailer
        self.pathfinder, result = PathfinderUtil.startPathfindingFromVehicleToNode(
                targetNode, offsetX, -alignLength, context)
        if result.done then
            return self:onPathfindingDoneBeforeSelfUnload(result.path)
        else
            self.state = self.states.WAITING_FOR_PATHFINDER
            self:setPathfindingDoneCallback(self, self.onPathfindingDoneBeforeSelfUnload)
        end
    else
        self:debug('Pathfinder already active')
    end
    return true
end

function AIDriveStrategyCombineCourse:onPathfindingDoneBeforeSelfUnload(path)
    if path and #path > 2 then
        self:debug('Pathfinding to self unload finished with %d waypoints (%d ms)',
                #path, g_currentMission.time - (self.pathfindingStartedAt or 0))
        local selfUnloadCourse = Course(self.vehicle, CpMathUtil.pointsToGameInPlace(path), true)
        if self.selfUnloadAlignCourse then
            selfUnloadCourse:append(self.selfUnloadAlignCourse)
            self.selfUnloadAlignCourse = nil
        end
        self:raiseImplements()
        self.state = self.states.UNLOADING_ON_FIELD
        self.unloadState = self.unloadStateAfterPathfindingDoneForSelfUnload
        self.ppc:setShortLookaheadDistance()
        self:startCourse(selfUnloadCourse, 1)
        return true
    else
        self:debug('No path found to self unload in %d ms',
                g_currentMission.time - (self.pathfindingStartedAt or 0))
        if self.unloadStateAfterPathfindingDoneForSelfUnload == self.states.DRIVING_TO_SELF_UNLOAD then
            self.unloadState = self.states.WAITING_FOR_UNLOAD_ON_FIELD
        elseif self.unloadStateAfterPathfindingDoneForSelfUnload == self.states.DRIVING_TO_SELF_UNLOAD_BEFORE_NEXT_ROW then
            -- continue turn as if nothing happened
            self:startCourse(self.fieldWorkCourse, self.waypointIxToContinueOnFailedSelfUnload)
            AIDriveStrategyFieldWorkCourse.startTurn(self, self.waypointIxToContinueOnFailedSelfUnload)
        elseif self.unloadStateAfterPathfindingDoneForSelfUnload == self.states.DRIVING_TO_SELF_UNLOAD_AFTER_FIELDWORK_ENDED then
            self.unloadState = self.states.WAITING_FOR_UNLOAD_AFTER_FIELDWORK_ENDED
        end
        return false
    end
end

--- Back to fieldwork after self unloading
function AIDriveStrategyCombineCourse:returnToFieldworkAfterSelfUnload()
    if not self.pathfinder or not self.pathfinder:isActive() then
        self.pathfindingStartedAt = g_currentMission.time
        local fieldWorkCourse, ix = self:getRememberedCourseAndIx()
        self:debug('Return to fieldwork after self unload at waypoint %d', ix)
        local context = PathfinderContext(self.vehicle):allowReverse(self:getAllowReversePathfinding())
        local result
        self.pathfinder, result = PathfinderUtil.startPathfindingFromVehicleToWaypoint(
                fieldWorkCourse, ix, self.settings.toolOffsetX:getValue(), 0, context)
        if result.done then
            return self:onPathfindingDoneAfterSelfUnload(result.path)
        else
            self.state = self.states.WAITING_FOR_PATHFINDER
            self:setPathfindingDoneCallback(self, self.onPathfindingDoneAfterSelfUnload)
        end
    else
        self:debug('Pathfinder already active')
    end
    return true
end

function AIDriveStrategyCombineCourse:onPathfindingDoneAfterSelfUnload(path)
    -- TODO: for some reason, the combine lowers the header while unloading, that should be fixed, for now, raise it here
    self:raiseImplements()
    local course, ix = self:getRememberedCourseAndIx()
    local fm, bm = self:getFrontAndBackMarkers()
    self.turnContext = RowStartOrFinishContext(self.vehicle, course, ix, ix, self.turnNodes, self:getWorkWidth(),
            fm, bm, 0, 0)
    if path and #path > 2 then
        self.state = self.states.UNLOADING_ON_FIELD
        self.unloadState = self.states.RETURNING_FROM_SELF_UNLOAD
        self.ppc:setShortLookaheadDistance()
        self:debug('Pathfinding to return to fieldwork after self unload finished with %d waypoints (%d ms)',
                #path, g_currentMission.time - (self.pathfindingStartedAt or 0))
        local returnCourse = Course(self.vehicle, CpMathUtil.pointsToGameInPlace(path), true)
        returnCourse:adjustForTowedImplements(2)
        self.workStarter = StartRowOnly(self.vehicle, self, self.ppc, self.turnContext, returnCourse)
        self:startCourse(self.workStarter:getCourse(), 1)
        return true
    else
        self:debug('No path found to return to fieldwork after self unload (%d ms)',
                g_currentMission.time - (self.pathfindingStartedAt or 0))
        local returnCourse = AlignmentCourse(self.vehicle, self.vehicle:getAIDirectionNode(),
                self.turningRadius, course, ix, 0):getCourse()
        if returnCourse then
            self.state = self.states.UNLOADING_ON_FIELD
            self.unloadState = self.states.RETURNING_FROM_SELF_UNLOAD
            self.ppc:setShortLookaheadDistance()
            self:debug('Start an alignment course to fieldwork waypoint %d', ix)
            self.workStarter = StartRowOnly(self.vehicle, self, self.ppc, self.turnContext, returnCourse)
            self:startCourse(self.workStarter:getCourse(), 1)
        else
            self.state = self.states.WORKING
            self:debug('Could not generate alignment course to fieldwork waypoint %d, starting course directly', ix)
            self:startRememberedCourse()
        end
        return false
    end
end

function AIDriveStrategyCombineCourse:continueSelfUnloadToNextTrailer()
    local fillLevel = self.combineController:getFillLevel()
    if fillLevel > 20 then
        self:debug('Self unloading finished, but fill level is %.1f, is there another trailer around we can unload to?', fillLevel)
        if self:startSelfUnload(self.states.DRIVING_TO_SELF_UNLOAD) then
            return true
        end
    end
    return false
end

function AIDriveStrategyCombineCourse:shouldSelfUnloadBeforeNextRow()
    if self:isFull(AIDriveStrategyCombineCourse.selfUnloadBeforeNextRowFillLevelThreshold) then
        local distance
        self.selfUnloadBestTrailer, self.selfUnloadFillRootNode, distance = SelfUnloadHelper:findBestTrailer(
                self.vehicle:cpGetFieldPolygon(),
                self.vehicle,
                self.implementWithPipe,
                self.pipeController.pipeOffsetX)
        if not self.selfUnloadBestTrailer then
            return false
        end
        local dx, _, dz = localToLocal(AIUtil.getDirectionNode(self.vehicle),
                AIUtil.getDirectionNode(self.selfUnloadBestTrailer), 0, 0, 0)
        self:debug('Best trailer dx: %.1f, dz: %.1f', dx, dz)
        -- the best trailer is sort of in front of us and not too far to the left or right
        if dz > -10 and math.abs(dx) < AIDriveStrategyCombineCourse.selfUnloadBeforeNextRowMaxDistance then
            self:debug('Best trailer for self unload is less than %.0f m, start self unload before continuing with next row',
                    AIDriveStrategyCombineCourse.selfUnloadBeforeNextRowMaxDistance)
            return true
        end
    end
    return false
end

-- This is a callback from the "finish row only" turn initiated at the end of the row when there is a
-- trailer nearby for self unloading. At this point, the row is done and we are ready to drive to the
-- trailer before starting the next row
function AIDriveStrategyCombineCourse:startSelfUnloadBeforeNextRow(ix)
    -- giving back control to the strategy, re-register these listeners
    if self:startSelfUnload(self.states.DRIVING_TO_SELF_UNLOAD_BEFORE_NEXT_ROW,
            self.selfUnloadBestTrailer, self.selfUnloadFillRootNode) then
        self:debug('Start self unload before continuing with next row')
    else
        -- giving up self unload, attempt to re-initialize the turn
        self:startCourse(self.fieldWorkCourse, self.waypointIxToContinueOnFailedSelfUnload)
        AIDriveStrategyFieldWorkCourse.startTurn(self, self.waypointIxToContinueOnFailedSelfUnload)
    end
end

--- Let unloaders register for events. This is different from the CombineUnloadManager registration, these
--- events are for the low level coordination between the combine and its unloader(s). CombineUnloadManager
--- takes care about coordinating the work between multiple combines.
function AIDriveStrategyCombineCourse:clearAllUnloaderInformation()
    self:cancelRendezvous()
    self.unloader:reset()
end

--- Register a combine unload AI driver for notification about combine events
--- Unloaders can renew their registration as often as they want to make sure they remain registered.
---@param driver AIDriveStrategyUnloadCombine
function AIDriveStrategyCombineCourse:registerUnloader(driver)
    self.unloader:set(driver, 1000)
end

--- Deregister a combine unload AI driver from notifications
---@param driver AIDriveStrategyUnloadCombine
function AIDriveStrategyCombineCourse:deregisterUnloader(driver, noEventSend)
    self:cancelRendezvous()
    self.unloader:reset()
end

--- Make life easier for unloaders, increases reach of the pipe
--- Old code ??
function AIDriveStrategyCombineCourse:fixMaxRotationLimit()
    if self.pipe then
        local lastPipeNode = self.pipe.nodes and self.pipe.nodes[#self.pipe.nodes]
        if self:isChopper() and lastPipeNode and lastPipeNode.maxRotationLimits then
            self.oldLastPipeNodeMaxRotationLimit = lastPipeNode.maxRotationLimits
            self:debug('Chopper fix maxRotationLimits, old Values: x=%s, y= %s, z =%s', tostring(lastPipeNode.maxRotationLimits[1]), tostring(lastPipeNode.maxRotationLimits[2]), tostring(lastPipeNode.maxRotationLimits[3]))
            lastPipeNode.maxRotationLimits = nil
        end
    end
end

--- Old code ??
function AIDriveStrategyCombineCourse:resetFixMaxRotationLimit()
    if self.pipe then
        local lastPipeNode = self.pipe.nodes and self.pipe.nodes[#self.pipe.nodes]
        if lastPipeNode and self.oldLastPipeNodeMaxRotationLimit then
            lastPipeNode.maxRotationLimits = self.oldLastPipeNodeMaxRotationLimit
            self:debug('Chopper: reset maxRotationLimits is x=%s, y= %s, z =%s', tostring(lastPipeNode.maxRotationLimits[1]), tostring(lastPipeNode.maxRotationLimits[3]), tostring(lastPipeNode.maxRotationLimits[3]))
            self.oldLastPipeNodeMaxRotationLimit = nil
        end
    end
end

--- Offset of the pipe from the combine implement's root node
---@param additionalOffsetX number add this to the offsetX if you don't want to be directly under the pipe. If
--- greater than 0 -> to the left, less than zero -> to the right
---@param additionalOffsetZ number forward (>0)/backward (<0) offset from the pipe
---@return number, number, boolean X and Z offset of pipe, true the pipe is auto aiming, that is, can discharge either side
function AIDriveStrategyCombineCourse:getPipeOffset(additionalOffsetX, additionalOffsetZ)
    local pipeOffsetX, pipeOffsetZ = self.pipeController:getPipeOffset()
    return pipeOffsetX + (additionalOffsetX or 0), pipeOffsetZ + (additionalOffsetZ or 0), self:hasAutoAimPipe()
end

--- Pipe side offset relative to course. This is to help the unloader
--- to find the pipe when we are waiting in a pocket
function AIDriveStrategyCombineCourse:getPipeOffsetFromCourse()
    return self.pipeController:getPipeOffset()
end

function AIDriveStrategyCombineCourse:initUnloadStates()
    self.safeUnloadFieldworkStates = {
        self.states.WORKING,
        self.states.WAITING_FOR_LOWER,
        self.states.WAITING_FOR_LOWER_DELAYED,
        self.states.WAITING_FOR_STOP,
    }

    self.safeFieldworkUnloadOrRefillStates = {
        self.states.WAITING_FOR_UNLOAD_AFTER_FIELDWORK_ENDED,
        self.states.WAITING_FOR_UNLOAD_ON_FIELD,
        self.states.WAITING_FOR_UNLOAD_AFTER_PULLED_BACK,
        self.states.WAITING_FOR_UNLOAD_IN_POCKET,
        self.states.WAITING_FOR_UNLOAD_BEFORE_STARTING_NEXT_ROW
    }

    self.willWaitForUnloadToFinishFieldworkStates = {
        self.states.WAITING_FOR_UNLOAD_AFTER_PULLED_BACK,
        self.states.WAITING_FOR_UNLOAD_IN_POCKET,
        self.states.WAITING_FOR_UNLOAD_AFTER_FIELDWORK_ENDED,
        self.states.WAITING_FOR_UNLOAD_BEFORE_STARTING_NEXT_ROW
    }
    --- All self unload states.
    self.selfUnloadStates = {
        self.states.DRIVING_TO_SELF_UNLOAD,
        self.states.SELF_UNLOADING,
        self.states.SELF_UNLOADING_WAITING_FOR_DISCHARGE,
        self.states.DRIVING_TO_SELF_UNLOAD_AFTER_FIELDWORK_ENDED,
        self.states.DRIVING_TO_SELF_UNLOAD_BEFORE_NEXT_ROW,
        self.states.SELF_UNLOADING_AFTER_FIELDWORK_ENDED,
        self.states.SELF_UNLOADING_AFTER_FIELDWORK_ENDED_WAITING_FOR_DISCHARGE,
        self.states.RETURNING_FROM_SELF_UNLOAD
    }
    self.drivingToSelfUnloadStates = {
        self.states.DRIVING_TO_SELF_UNLOAD,
        self.states.DRIVING_TO_SELF_UNLOAD_AFTER_FIELDWORK_ENDED,
        self.states.DRIVING_TO_SELF_UNLOAD_BEFORE_NEXT_ROW,
    }
end

function AIDriveStrategyCombineCourse:isStateOneOf(myState, states)
    return CpUtil.isStateOneOf(myState, states)
end

function AIDriveStrategyCombineCourse:isUnloadStateOneOf(states)
    return self:isStateOneOf(self.unloadState, states)
end

-- TODO: this whole logic is more relevant to the unloader maybe move it there?
function AIDriveStrategyCombineCourse:getClosestFieldworkWaypointIx()
    if self:isTurning() then
        if self.turnContext then
            -- send turn start wp, unloader will decide if it needs to move it to the turn end or not
            return self.turnContext.turnStartWpIx
        else
            -- if for whatever reason we don't have a turn context, current waypoint is ok
            return self.course:getCurrentWaypointIx()
        end
    elseif self.course:isTemporary() then
        return self.course:getLastPassedWaypointIx()
    else
        -- if currently on the fieldwork course, this is the best estimate
        return self.ppc:getRelevantWaypointIx()
    end
end

--- Maneuvering means turning or working on a pocket or pulling back due to the pipe in fruit
--- We don't want to get too close to a maneuvering combine until it is done
function AIDriveStrategyCombineCourse:isManeuvering()
    return self:isTurning() or
            (
                    self.state == self.states.UNLOADING_ON_FIELD and
                            not self:isUnloadStateOneOf(self.safeFieldworkUnloadOrRefillStates)
            )
end

function AIDriveStrategyCombineCourse:isOnHeadland(n)
    return self.course:isOnHeadland(self.course:getCurrentWaypointIx(), n)
end

--- Are we ready for an unloader?
--- @param noUnloadWithPipeInFruit boolean pipe must not be in fruit for unload
function AIDriveStrategyCombineCourse:isReadyToUnload(noUnloadWithPipeInFruit)
    -- no unloading when not in a safe state (like turning)
    -- in these states we are always ready
    if self:willWaitForUnloadToFinish() then
        return true
    end

    -- but, if we are full and waiting for unload, we have no choice, we must be ready ...
    if self.state == self.states.UNLOADING_ON_FIELD and self.unloadState == self.states.WAITING_FOR_UNLOAD_ON_FIELD then
        return true
    end

    -- pipe is in the fruit.
    if noUnloadWithPipeInFruit and self:isPipeInFruit() then
        self:debugSparse('isReadyToUnload(): pipe in fruit')
        return false
    end

    if not self.course then
        self:debugSparse('isReadyToUnload(): has no fieldwork course')
        return false
    end

    -- around a turn, for example already working on the next row but not done with the turn yet

    if self.course:isCloseToNextTurn(10) then
        self:debugSparse('isReadyToUnload(): too close to turn')
        return false
    end
    -- safe default, better than block unloading
    self:debugSparse('isReadyToUnload(): defaulting to ready to unload')
    return true
end

--- Will not move until unload is done? Unloaders like to know this.
function AIDriveStrategyCombineCourse:willWaitForUnloadToFinish()
    return self.state == self.states.UNLOADING_ON_FIELD and
            ((self.settings.stopForUnload:getValue() and self.unloadState == self.states.WAITING_FOR_UNLOAD_ON_FIELD) or
                    self.unloadState == self.states.WAITING_FOR_UNLOAD_IN_POCKET or
                    self.unloadState == self.states.WAITING_FOR_UNLOAD_AFTER_PULLED_BACK or
                    self.unloadState == self.states.WAITING_FOR_UNLOAD_AFTER_FIELDWORK_ENDED)
end

--- Try to not hit our Unloader after Pocket.
function AIDriveStrategyCombineCourse:isAboutToReturnFromPocket()
    return self.unloadState == self.states.WAITING_FOR_UNLOAD_IN_POCKET or
            (self.unloadState == self.states.WAITING_FOR_UNLOADER_TO_LEAVE and
                    self.stateBeforeWaitingForUnloaderToLeave == self.states.WAITING_FOR_UNLOAD_IN_POCKET)
end

------------------------------------------------------------------------------------------------------------------------
--- Proximity
------------------------------------------------------------------------------------------------------------------------

AIDriveStrategyCombineCourse.maxBackDistance = 20

function AIDriveStrategyCombineCourse:getMeasuredBackDistance()
    return self.measuredBackDistance
end

--- Determine how far the back of the combine is from the direction node
function AIDriveStrategyCombineCourse:measureBackDistance()
    -- check and adjust every 10 seconds, mainly for the towed harvesters which may be at an angle when
    -- the driver starts and our raycast may miss it.
    if not self.lastBackMeasurementDue then
        self.lastBackMeasurementDue = CpTemporaryObject(true)
    end
    if not self.lastBackMeasurementDue:get() then
        return
    end
    self.lastBackMeasurementDue:set(false, 10000)
    self.measuredBackDistance = self.measuredBackDistance or 0
    local previousMeasuredBackDistance = self.measuredBackDistance
    -- raycast from a point behind the vehicle forward towards the direction node, in different heights as harvesters
    -- can be very tricky, such as the Oxbo, which we'll get no hits at all at exactly 1.5 meters...
    for height = 1.3, 2.5, 0.2 do
        local nx, ny, nz = localDirectionToWorld(AIUtil.getDirectionNode(self.vehicle), 0, 0, 1)
        -- use the tool offset, that should cover offset towed harvesters as well
        local x, y, z = localToWorld(AIUtil.getDirectionNode(self.vehicle),
                self.settings.toolOffsetX:getValue(), height, -self.maxBackDistance)
        raycastAll(x, y, z, nx, ny, nz, self.maxBackDistance, 'raycastBackCallback', self, CpUtil.getVehicleCollisionFlags())
    end
    if previousMeasuredBackDistance ~= self.measuredBackDistance then
        self:debug('Measured back distance changed from %.1f to %.1f m', previousMeasuredBackDistance, self.measuredBackDistance)
    end
end

-- I believe this tries to figure out how far the back of a combine is from its direction node.
function AIDriveStrategyCombineCourse:raycastBackCallback(hitObjectId, x, y, z, distance, nx, ny, nz, subShapeIndex)
    if hitObjectId ~= 0 then
        local object = g_currentMission:getNodeObject(hitObjectId)
        if object and object.getRootVehicle and object:getRootVehicle() == self.vehicle then
            local d = self.maxBackDistance - distance
            if d > self.measuredBackDistance then
                self.measuredBackDistance = d
            end
        end
    end
end

function AIDriveStrategyCombineCourse:onDraw()
    if CpDebug:isChannelActive(CpDebug.DBG_IMPLEMENTS, self.vehicle) then

        local dischargeNode = self:getCurrentDischargeNode()
        if dischargeNode then
            local dx, _, dz = localToLocal(dischargeNode.node, self.vehicle:getAIDirectionNode(), 0, 0, 0)
            DebugUtil.drawDebugNode(dischargeNode.node, string.format('discharge\n%.1f %.1f', dx, dz))
        end
    end

    if CpDebug:isChannelActive(CpDebug.DBG_PATHFINDER, self.vehicle) then
        local areaToAvoid = self:getAreaToAvoid()
        if areaToAvoid then
            local x, y, z = localToWorld(areaToAvoid.node, areaToAvoid.xOffset, 0, areaToAvoid.zOffset)
            DebugUtil.drawDebugLine(x, y + 1.2, z, 10, 10, 10, x, y + 1.2, z + areaToAvoid.length)
            DebugUtil.drawDebugLine(x + areaToAvoid.width, y + 1.2, z, 10, 10, 10, x + areaToAvoid.width, y + 1.2, z + areaToAvoid.length)
        end
    end

    if CpDebug:isChannelActive(CpDebug.DBG_FIELDWORK, self.vehicle) then
        if self.state == self.states.UNLOADING_ON_FIELD and
                (self.unloadState == self.states.REVERSING_TO_MAKE_A_POCKET or self.unloadState == self.states.MAKING_POCKET or
                        self.unloadState == self.states.WAITING_FOR_UNLOAD_IN_POCKET) then
            self.pocketHelperNode:draw()
        end
    end
end

--- Don't slow down when discharging. This is a workaround for unloaders getting into the proximity
--- sensor's range.
function AIDriveStrategyCombineCourse:isProximitySlowDownEnabled(vehicle)
    -- if not on fieldwork, always enable slowing down
    if self.state ~= self.states.WORKING then
        return true
    end
    -- TODO: check if vehicle is player or AD driven, or even better, check if this is the vehicle
    -- we are discharging into
    if vehicle and self:isDischarging() then
        self:debugSparse('discharging, not slowing down for nearby %s', CpUtil.getName(vehicle))
        return false
    else
        return true
    end
end

--- This is called by the proximity controller if we have been blocked by another vehicle for a while
function AIDriveStrategyCombineCourse:onBlockingVehicle(vehicle, isBack)
    if isBack then
        self:debug('Proximity sensor: blocking vehicle %s behind us', CpUtil.getName(vehicle))
        self:checkBlockingUnloader()
    else
        self:debug('Proximity sensor: blocking vehicle %s in front of us', CpUtil.getName(vehicle))
        local strategy = vehicle.getCpDriveStrategy and vehicle:getCpDriveStrategy()
        if strategy and strategy.requestToMoveOutOfWay then
            strategy:requestToMoveOutOfWay(self.vehicle, isBack)
        end
    end
end

-- An unloader may request the harvester to ignore its proximity because the unloader will take care
-- of staying away.
function AIDriveStrategyCombineCourse:requestToIgnoreProximity(vehicle)
    self.unloaderRequestedToIgnoreProximity:set(vehicle, 1000)
end

-- Proximity controller checking if an object/vehicle should be ignored
function AIDriveStrategyCombineCourse:ignoreProximityObject(object, vehicle, moveForwards, hitTerrain)
    return vehicle ~= nil and vehicle == self.unloaderRequestedToIgnoreProximity:get()
end

--- Check if the unloader is blocking us when we are reversing in a turn and immediately notify it
function AIDriveStrategyCombineCourse:checkBlockingUnloader()
    if not self.ppc:isReversing() and not AIUtil.isReversing(self.vehicle) then
        return
    end
    local d, blockingVehicle = self.proximityController:checkBlockingVehicleBack()
    if blockingVehicle ~= self.unloaderRequestedToIgnoreProximity:get() and d < 1000 and
            blockingVehicle and AIUtil.isStopped(self.vehicle) and
            not self:isWaitingForUnload() and not self:shouldHoldInTurnManeuver() then
        -- try requesting only if the unloader really blocks us, that is we are actually backing up but
        -- can't move because of the unloader, and not when we are stopped for other reasons
        self:debugSparse('Can\'t reverse, %s at %.1f m is blocking', blockingVehicle:getName(), d)
        local strategy = blockingVehicle.getCpDriveStrategy and blockingVehicle:getCpDriveStrategy()
        if strategy and strategy.requestToBackupForReversingCombine then
            strategy:requestToBackupForReversingCombine(self.vehicle)
        end
    end
end

function AIDriveStrategyCombineCourse:getWorkingToolPositionsSetting()
    local setting = self.settings.pipeToolPositions
    return setting:getHasMoveablePipe() and setting:hasValidToolPositions() and setting
end

------------------------------------------------------------------------------------------------------------------------
--- Info texts, makes sure the unloadState also gets checked.
---------------------------------------------------------------------------------------------------------------------------

function AIDriveStrategyCombineCourse:updateInfoTexts()
    for infoText, states in pairs(self.registeredInfoTexts) do
        if states.states[self.state] and states.unloadStates[self.unloadState] then
            self:setInfoText(infoText)
        else
            self:clearInfoText(infoText)
        end
    end
end

------------------------------------------------------------------------------------------------------------------------
--- Field polygon
---------------------------------------------------------------------------------------------------------------------------
--- We don't save the field polygon with the savegame, so if a combine is started directly from the HUD after the
--- game loaded, it doesn't have the field polygon. This makes sure that in this case the detection is started.
function AIDriveStrategyCombineCourse:startFieldBoundaryDetection()
    if not self.vehicle:cpIsFieldBoundaryDetectionRunning() then
        self:debug("Need field boundary to work, start detection now.")
        -- TODO: should really store the field position (or the polygon itself?) with the course, as
        -- in some rare cases, for instance when using field margin, the start waypoint may be outside
        -- of the field, and thus the detection won't work.
        local x, _, z = self.fieldWorkCourse:getWaypointPosition(self.fieldWorkCourse:getCurrentWaypointIx())
        self.vehicle:cpDetectFieldBoundary(x, z, self, function(self)
            self:clearInfoText(InfoTextManager.WAITING_FOR_FIELD_BOUNDARY_DETECTION)
        end)
    else
        self:debug("Field boundary detection already running.")
    end
end