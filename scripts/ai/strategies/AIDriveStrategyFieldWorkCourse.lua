--[[
This file is part of Courseplay (https://github.com/Courseplay/Courseplay_FS25)
Copyright (C) 2021 Peter Vaiko

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

Drive strategy for driving a field work course

]]--

---@class AIDriveStrategyFieldWorkCourse : AIDriveStrategyCourse
AIDriveStrategyFieldWorkCourse = CpObject(AIDriveStrategyCourse)

AIDriveStrategyFieldWorkCourse.myStates = {
    WORKING = {},
    WAITING_FOR_LOWER = {},
    WAITING_FOR_LOWER_DELAYED = {},
    WAITING_FOR_STOP = {},
    WAITING_FOR_WEATHER = {},
    TURNING = { showTurnContextDebug = true },
    TEMPORARY = {},
    RETURNING_TO_START = {},
    DRIVING_TO_WORK_START_WAYPOINT = { showTurnContextDebug = true },
}

AIDriveStrategyFieldWorkCourse.normalFillLevelFullPercentage = 99.5

function AIDriveStrategyFieldWorkCourse:init(task, job)
    AIDriveStrategyCourse.init(self, task, job)
    AIDriveStrategyCourse.initStates(self, AIDriveStrategyFieldWorkCourse.myStates)
    self.state = self.states.INITIAL
    -- cache for the nodes created by TurnContext
    self.turnNodes = {}
    -- course offsets dynamically set by the AI and added to all tool and other offsets
    self.aiOffsetX, self.aiOffsetZ = 0, 0
    self.debugChannel = CpDebug.DBG_FIELDWORK
    self.waitingForPrepare = CpTemporaryObject(false)
end

function AIDriveStrategyFieldWorkCourse:delete()
    AIDriveStrategyCourse.delete(self)
    self:raiseImplements()
    TurnContext.deleteNodes(self.turnNodes)
    self:rememberWaypointToContinueFieldWork()
end

--- Start a fieldwork course. We expect that something else dropped us off close enough to startIx so
--- the most we need is an alignment course to lower the implements
function AIDriveStrategyFieldWorkCourse:start(course, startIx, jobParameters)
    self:showAllInfo('Starting field work at waypoint %d', startIx)
    self:updateCourseOffset(course)
    self.fieldWorkCourse = course
    self.fieldWorkCourse:setCurrentWaypointIx(startIx)
    self.remainingTime = CpRemainingTime(self.vehicle, course, startIx)
    -- remember at which waypoint we started, especially for the convoy
    self.startWaypointIx = startIx
    self.vehiclesInConvoy = {}

    local distance = course:getDistanceBetweenVehicleAndWaypoint(self.vehicle, startIx)

    ---@type CpAIJobFieldWork
    local job = self.vehicle:getJob()
    local alignmentCourse, alignmentCourseStartIx = job:getStartFieldWorkCourse()

    if alignmentCourse then
        -- there is an alignment course already created by the AIDriveStrategyDriveToFieldWorkStart,
        -- and we are supposed to continue on that one
        self:debug('Continuing the alignment course at %d to start work.', alignmentCourseStartIx)
        -- make sure the alignment course is used only once
        job:setStartFieldWorkCourse(nil, nil)
        self.course = course
        self:startAlignmentTurn(course, startIx, alignmentCourse, alignmentCourseStartIx)
    elseif distance > 2 * self.turningRadius then
        self:debug('Start waypoint is far (%.1f m), use alignment course to get there.', distance)
        self.course = course
        self:startAlignmentTurn(course, startIx)
    else
        self:debug('Close enough to start waypoint %d, no alignment course needed', startIx)
        self:startCourse(course, startIx)
        self.state = self.states.INITIAL
        self:prepareForFieldWork()
    end
    --- Store a reference to the original generated course
    self.originalGeneratedFieldWorkCourse = self.vehicle:getFieldWorkCourse()
end

--- If the strategy needs a field polygon to work, it won't transition out of the INITIAL state
--- until the field detection, an asynchronous process that may have started only when the job was started, is finished.
---@return boolean true if the strategy needs the field polygon to work
function AIDriveStrategyFieldWorkCourse:needsFieldPolygon()
    return false
end

--- Make sure all implements are in the working state
function AIDriveStrategyFieldWorkCourse:prepareForFieldWork()
    self.vehicle:raiseAIEvent('onAIFieldWorkerPrepareForWork', 'onAIImplementPrepareForWork')
end

--- Event raised when the driver has finished.
function AIDriveStrategyFieldWorkCourse:onFinished(hasFinished)
    AIDriveStrategyCourse.onFinished(self, hasFinished)
    self.remainingTime:reset()
end

function AIDriveStrategyFieldWorkCourse:update(dt)
    AIDriveStrategyCourse.update(self, dt)
    if CpDebug:isChannelActive(CpDebug.DBG_TURN, self.vehicle) then
        if self.state == self.states.TURNING then
            if self.aiTurn then
                self.aiTurn:drawDebug()
            end
        end
        if self.state.properties.showTurnContextDebug then
            if self.turnContext then
                self.turnContext:drawDebug()
            end
        end
        -- TODO_22 check user setting
        if self.course:isTemporary() then
            self.course:draw()
        elseif self.ppc:getCourse():isTemporary() then
            self.ppc:getCourse():draw()
        end
    end
    if CpDebug:isChannelActive(CpDebug.DBG_PATHFINDER, self.vehicle) then
        if self.pathfinder then
            PathfinderUtil.showNodes(self.pathfinder)
        end
    end
    if self.fieldWorkerProximityController then
        self.fieldWorkerProximityController:draw()
    end
    self:updateImplementControllers(dt)
    self.remainingTime:update(dt)
end

--- This is the interface to the Giant's AIFieldWorker specialization, telling it the direction and speed
function AIDriveStrategyFieldWorkCourse:getDriveData(dt, vX, vY, vZ)

    self:updateCourseOffset(self.course)
    self:updateLowFrequencyImplementControllers()
    Markers.refreshMarkerNodes(self.vehicle, self.measuredBackDistance)

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
    ----------------------------------------------------------------
    if self.state == self.states.INITIAL then
        self:setMaxSpeed(0)
        self:startWaitingForLower()
        self:lowerImplements()
    elseif self.state == self.states.WAITING_FOR_LOWER then
        self:setMaxSpeed(0)
        if self:getCanContinueWork() then
            self:debug('all tools ready, start working')
            self.state = self.states.WORKING
        else
            self:debugSparse('waiting for all tools to lower')
        end
    elseif self.state == self.states.WAITING_FOR_LOWER_DELAYED then
        -- getCanAIVehicleContinueWork() seems to return false when the implement being lowered/raised (moving) but
        -- true otherwise. Due to some timing issues it may return true just after we started lowering it, so this
        -- here delays the check for another cycle.
        self.state = self.states.WAITING_FOR_LOWER
        self:setMaxSpeed(0)
    elseif self.state == self.states.WAITING_FOR_PATHFINDER then
        self:setMaxSpeed(0)
    elseif self.state == self.states.WORKING then
        self:setMaxSpeed(self.settings.fieldWorkSpeed:getValue())
    elseif self.state == self.states.TURNING then
        local turnGx, turnGz, turnMoveForwards, turnMaxSpeed = self.aiTurn:getDriveData(dt)
        self:setMaxSpeed(turnMaxSpeed)
        -- if turn tells us which way to go, use that, otherwise just do whatever PPC tells us
        gx, gz = turnGx or gx, turnGz or gz
        if turnMoveForwards ~= nil then
            moveForwards = turnMoveForwards
        end
    elseif self.state == self.states.RETURNING_TO_START then
        local isReadyToDrive, blockingVehicle = self.vehicle:getIsAIReadyToDrive()
        if isReadyToDrive or not self.waitingForPrepare:get() then
            -- ready to drive or we just timed out waiting to be ready
            self:setMaxSpeed(self.settings.fieldSpeed:getValue())
        else
            self:debugSparse('Not ready to drive because of %s, preparing ...', CpUtil.getName(blockingVehicle))
        end
    elseif self.state == self.states.DRIVING_TO_WORK_START_WAYPOINT then
        self:setMaxSpeed(self.settings.fieldSpeed:getValue())
        local _, _, _, maxSpeed = self.workStarter:getDriveData()
        if maxSpeed ~= nil then
            self:setMaxSpeed(maxSpeed)
        end
    end

    self:setAITarget()
    self:limitSpeed()
    self:checkProximitySensors(moveForwards)
    self:checkDistanceToOtherFieldWorkers()

    return gx, gz, moveForwards, self.maxSpeed, 100
end

function AIDriveStrategyFieldWorkCourse:checkDistanceToOtherFieldWorkers()
    -- keep away from others working on the same course
    self:setMaxSpeed(self.fieldWorkerProximityController:getMaxSpeed(self.settings.convoyDistance:getValue(), self.maxSpeed))
end

-- Seems like the Giants AIDriveStrategyCollision needs these variables on the vehicle to be set
-- to calculate an accurate path prediction
function AIDriveStrategyFieldWorkCourse:setAITarget()
    --local dx, _, dz = localDirectionToWorld(self.vehicle:getAIDirectionNode(), 0, 0, 1)
    local wp = self.ppc:getCurrentWaypoint()
    --- TODO: For some reason wp.dx and wp.dz are nil sometimes
    local dx, dz = wp.dx or 0, wp.dz or 0
    if wp.dx ~= 0 or wp.dz ~= 0 then
        local length = MathUtil.vector2Length(dx, dz)
        dx = dx / length
        dz = dz / length
    end
    self.vehicle.aiDriveDirection = { dx, dz }
    local x, _, z = getWorldTranslation(self.vehicle:getAIDirectionNode())
    self.vehicle.aiDriveTarget = { x, z }
end

-----------------------------------------------------------------------------------------------------------------------
--- Implement handling
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyFieldWorkCourse:initializeImplementControllers(vehicle)

    local defaultDisabledStates = {
        self.states.TEMPORARY,
        self.states.TURNING,
        self.states.DRIVING_TO_WORK_START_WAYPOINT
    }
    self:addImplementController(vehicle, BalerController, Baler, {})
    self:addImplementController(vehicle, BaleWrapperController, BaleWrapper, defaultDisabledStates)
    self:addImplementController(vehicle, BaleLoaderController, BaleLoader, defaultDisabledStates)
    self:addImplementController(vehicle, APalletAutoLoaderController, nil, {}, "spec_aPalletAutoLoader")
    self:addImplementController(vehicle, UniversalAutoloadController, nil, {}, "spec_universalAutoload")

    self:addImplementController(vehicle, CombineController, Combine, defaultDisabledStates)
    self:addImplementController(vehicle, FertilizingSowingMachineController, FertilizingSowingMachine, defaultDisabledStates)
    self:addImplementController(vehicle, ForageWagonController, ForageWagon, defaultDisabledStates)
    self:addImplementController(vehicle, SowingMachineController, SowingMachine, defaultDisabledStates)
    self:addImplementController(vehicle, FertilizingCultivatorController, FertilizingCultivator, defaultDisabledStates)
    self:addImplementController(vehicle, MowerController, Mower, defaultDisabledStates)

    self:addImplementController(vehicle, RidgeMarkerController, RidgeMarker, defaultDisabledStates)
    self:addImplementController(vehicle, PlowController, Plow, defaultDisabledStates)

    self:addImplementController(vehicle, PickupController, Pickup, defaultDisabledStates)
    self:addImplementController(vehicle, SprayerController, Sprayer, {})
    self:addImplementController(vehicle, CutterController, Cutter, {})
    --- Makes sure the cutter timer gets reset always.
    self:addImplementController(vehicle, StonePickerController, StonePicker, defaultDisabledStates)

    self:addImplementController(vehicle, FoldableController, Foldable, {})
    self:addImplementController(vehicle, MotorController, Motorized, {})
    self:addImplementController(vehicle, WearableController, Wearable, {})
    self:addImplementController(vehicle, VineCutterController, VineCutter, defaultDisabledStates)
    self:addImplementController(vehicle, PalletFillerController, nil, defaultDisabledStates, "spec_pdlc_premiumExpansion.palletFiller")

    self:addImplementController(vehicle, SoilSamplerController, nil, defaultDisabledStates, "spec_soilSampler")
    self:addImplementController(vehicle, StumpCutterController, StumpCutter, defaultDisabledStates)
    self:addImplementController(vehicle, TreePlanterController, TreePlanter, {})

end

--- Start waiting for the implements to lower
-- getCanAIVehicleContinueWork() seems to return false when the implement being lowered/raised (moving) but
-- true otherwise. Due to some timing issues it may return true just after we started lowering it, so we
-- set a different state for those implements
function AIDriveStrategyFieldWorkCourse:startWaitingForLower()
    -- TODO 25 looks like we always need to wait that extra cycle with FS25
    if true or AIUtil.hasAIImplementWithSpecialization(self.vehicle, SowingMachine) or self.ppc:isReversing() then
        -- sowing machines want to stop while the implement is being lowered
        -- also, when reversing, we assume that we'll switch to forward, so stop while lowering, then start forward
        self.state = self.states.WAITING_FOR_LOWER_DELAYED
        self:debug('waiting for lower delayed')
    else
        self.state = self.states.WAITING_FOR_LOWER
        self:debug('waiting for lower')
    end
end

--- Are all implements now aligned with the node? Can be used to find out if we are for instance aligned with the
--- turn end node direction in a question mark turn and can start reversing.
function AIDriveStrategyFieldWorkCourse:areAllImplementsAligned(node)
    -- see if the vehicle has AI markers -> has work areas (built-in implements like a mower or cotton harvester)
    local allAligned = self:isThisImplementAligned(self.vehicle, node)
    -- and then check all implements
    for _, implement in ipairs(AIUtil.getAllAIImplements(self.vehicle)) do
        -- _all_ implements must be aligned, hence the 'and'
        allAligned = allAligned and self:isThisImplementAligned(implement.object, node)
    end
    return allAligned
end

function AIDriveStrategyFieldWorkCourse:isThisImplementAligned(object, node)
    local aiFrontMarker, _, _ = WorkWidthUtil.getAIMarkers(object, true)
    if not aiFrontMarker then
        return true
    end
    return CpMathUtil.isSameDirection(aiFrontMarker, node, 5)
end

-----------------------------------------------------------------------------------------------------------------------
--- Event listeners
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyFieldWorkCourse:onWaypointChange(ix, course)
    self:calculateTightTurnOffset()
    if not self.state ~= self.states.TURNING
            and self.course:isTurnStartAtIx(ix) then
        if self.state == self.states.INITIAL then
            self:debug('Waypoint change (%d) to turn start right after starting work, lowering implements.', ix)
            self:startWaitingForLower()
            self:lowerImplements()
        end
        self:startTurn(ix)
    elseif self.state == self.states.WORKING then
        if (self.course:isOnConnectingPath(ix + 1) and not self.course:isOnConnectingPath(ix)) or
                self.course:shouldUsePathfinderToNextWaypoint(ix) then
            local fm, bm = self:getFrontAndBackMarkers()
            self.turnContext = RowStartOrFinishContext(self.vehicle, self.course, ix, ix, self.turnNodes, self:getWorkWidth(),
                    fm, bm, 0, 0)
            self.aiTurn = FinishRowOnly(self.vehicle, self, self.ppc, self.proximityController, self.turnContext)
            self.state = self.states.TURNING
            if self.course:isOnConnectingPath(ix + 1) then
                self:debug('finishing work before starting on the connecting path')
                self.aiTurn:registerTurnEndCallback(self, AIDriveStrategyFieldWorkCourse.startConnectingPath)
            else
                -- the generated course instructs the vehicle to use the pathfinder to the next waypoint
                self:debug('finishing work before starting pathfinding to the next waypoint')
                self.aiTurn:registerTurnEndCallback(self, AIDriveStrategyFieldWorkCourse.startPathfindingToNextWaypoint)
            end
        end
        -- towards the end of the field course make sure the implement reaches the last waypoint
        -- TODO: this needs refactoring, for now don't do this for temporary courses like a turn as it messes up reversing
        if ix > self.course:getNumberOfWaypoints() - 3 and not self.course:isTemporary() then
            local _, bm = self:getFrontAndBackMarkers()
            self:debug('adding offset (%.1f front marker) to make sure we do not miss anything when the course ends', bm)
            self.aiOffsetZ = -bm
        end
    end
end

function AIDriveStrategyFieldWorkCourse:onWaypointPassed(ix, course)
    if course:isLastWaypointIx(ix) then
        self:onLastWaypointPassed()
    end
end

--- Called when the last waypoint of a course is passed
function AIDriveStrategyFieldWorkCourse:onLastWaypointPassed()
    -- reset offset we used for the course ending to not miss anything
    self.aiOffsetZ = 0
    self:debug('Last waypoint of the course reached.')
    if self.state == self.states.RETURNING_TO_START then
        self:debug('Returned to first waypoint after fieldwork done, stopping job')
        self.vehicle:stopCurrentAIJob(AIMessageSuccessFinishedJob.new())
    elseif self.state == self.states.DRIVING_TO_WORK_START_WAYPOINT then
        self.workStarter:onLastWaypoint()
    else
        -- by default, stop the job
        self:finishFieldWork()
    end
end

-----------------------------------------------------------------------------------------------------------------------
--- Turn
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyFieldWorkCourse:startTurn(ix)
    self:debug('Starting a turn at waypoint %d', ix)
    local fm, bm = self:getFrontAndBackMarkers()
    self.ppc:setShortLookaheadDistance()
    self.turnContext = TurnContext(self.vehicle, self.course, ix, ix + 1, self.turnNodes, self:getWorkWidth(), fm, bm,
            self:getTurnEndSideOffset(), self:getTurnEndForwardOffset())
    if AITurn.canMakeKTurn(self.vehicle, self.turnContext, self.workWidth, self:isTurnOnFieldActive()) then
        self.aiTurn = KTurn(self.vehicle, self, self.ppc, self.proximityController, self.turnContext, self.workWidth)
    else
        self.aiTurn = CourseTurn(self.vehicle, self, self.ppc, self.proximityController, self.turnContext, self.course, self.workWidth)
    end
    self.state = self.states.TURNING
end

function AIDriveStrategyFieldWorkCourse:isTurning()
    return self.state == self.states.TURNING
end

-- switch back to fieldwork after the turn ended.
---@param ix number waypoint to resume fieldwork after
function AIDriveStrategyFieldWorkCourse:resumeFieldworkAfterTurn(ix)
    self.ppc:setNormalLookaheadDistance()
    self:startWaitingForLower()
    self:lowerImplements()
    local startIx = self.fieldWorkCourse:getNextFwdWaypointIxFromVehiclePosition(ix,
            self.vehicle:getAIDirectionNode(), self.workWidth / 2)
    self:startCourse(self.fieldWorkCourse, startIx)
end

--- Attempt to recover from a turn where the vehicle got blocked. This replaces the current turn with a
--- RecoveryTurn, which just backs up a bit and then uses the pathfinder to create a turn back to the
--- start of the next row.
---@param reverseDistance number|nil distance to back up before retrying pathfinding (default 10 m)
---@param retryCount number|nil how many times have we tried to recover so far? (to limit the number of retries)
---@return boolean true if a recovery turn could be created
function AIDriveStrategyFieldWorkCourse:startRecoveryTurn(reverseDistance, retryCount)
    self:debug('Blocked in a turn, attempt to recover')
    if self.turnContext then
        self.aiTurn = RecoveryTurn(self.vehicle, self, self.ppc, self.proximityController, self.turnContext,
                self.course, self.workWidth, reverseDistance, retryCount)
        self.state = self.states.TURNING
        return true
    else
        self:debug('Lost turn context to recover, remain blocked.')
        return false
    end
end

-----------------------------------------------------------------------------------------------------------------------
--- State changes
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyFieldWorkCourse:finishFieldWork()
    if self.settings.returnToStart:getValue() and self.fieldWorkCourse:startsWithHeadland() then
        self:debug('Fieldwork ended, returning to first waypoint.')
        self.vehicle:prepareForAIDriving()
        self:returnToStartAfterDone()
    else
        self:debug('Fieldwork ended, stopping job.')
        self.vehicle:stopCurrentAIJob(AIMessageSuccessFinishedJob.new())
    end
end

function AIDriveStrategyFieldWorkCourse:changeToFieldWork()
    self:debug('change to fieldwork')
    self:startWaitingForLower()
    self:lowerImplements(self.vehicle)
end

--- Start alignment turn, that is, a course to the waypoint of fieldWorkCourse where the
--- fieldwork should begin. This is performed as a turn maneuver, more specifically the end of the
--- turn maneuver where the work is started and has the logic to lower the implements exactly
--- where it needs to be.
---
--- (It is called alignment because it makes sure the vehicle is aligned with the start waypoint so
--- that it points to the right direction and the implements can start working exactly at the waypoint)
---
--- The caller can pass in an already created alignment course with an index. In that case, we'll use
--- that course, starting at alignmentStartIx for the turn, otherwise a new course is created from
--- the vehicle's current position to startIx in fieldWorkCourse.
---
---@param fieldWorkCourse Course fieldwork course
---@param startIx number index of waypoint of fieldWorkCourse where the work should start
---@param alignmentCourse Course an optional course if the caller already has one
---@param alignmentStartIx number index to start the alignment course (if supplied)
function AIDriveStrategyFieldWorkCourse:startAlignmentTurn(fieldWorkCourse, startIx, alignmentCourse, alignmentStartIx)
    if alignmentCourse then
        -- there is an alignment course, use that one, if there is a start ix, then only
        -- the part starting at startIx
        alignmentCourse = alignmentCourse:copy(self.vehicle, alignmentStartIx)
    else
        -- no alignment course given, generate one
        alignmentCourse = self:createAlignmentCourse(fieldWorkCourse, startIx)
    end
    self.ppc:setShortLookaheadDistance()
    self:prepareForFieldWork()
    if alignmentCourse then
        local fm, bm = self:getFrontAndBackMarkers()
        self.turnContext = RowStartOrFinishContext(self.vehicle, fieldWorkCourse, startIx, startIx, self.turnNodes,
                self:getWorkWidth(), fm, bm, self:getTurnEndSideOffset(), self:getTurnEndForwardOffset())
        self.workStarter = StartRowOnly(self.vehicle, self, self.ppc, self.turnContext, alignmentCourse)
        self.state = self.states.DRIVING_TO_WORK_START_WAYPOINT
        self:startCourse(self.workStarter:getCourse(), 1)
    else
        self:debug('Could not create alignment course to first up/down row waypoint, continue without it')
        self:startCourse(fieldWorkCourse, startIx)
        self.state = self.states.INITIAL
        self:prepareForFieldWork()
    end
end

--- Back to the start waypoint after done
function AIDriveStrategyFieldWorkCourse:returnToStartAfterDone()
    if not self.pathfinder or not self.pathfinder:isActive() then
        self.pathfindingStartedAt = g_currentMission.time
        self:debug('Return to first waypoint')
        local context = PathfinderContext(self.vehicle):allowReverse(self:getAllowReversePathfinding())
        local result
        self.pathfinder, result = PathfinderUtil.startPathfindingFromVehicleToWaypoint(
                self.fieldWorkCourse, 1, 0, 0, context)
        if result.done then
            return self:onPathfindingDoneToReturnToStart(result.path)
        else
            self.state = self.states.WAITING_FOR_PATHFINDER
            self:setPathfindingDoneCallback(self, self.onPathfindingDoneToReturnToStart)
        end
    else
        self:debug('Pathfinder already active, stopping job')
        self.vehicle:stopCurrentAIJob(AIMessageSuccessFinishedJob.new())
    end
end

function AIDriveStrategyFieldWorkCourse:onPathfindingDoneToReturnToStart(path)
    if path and #path > 2 then
        self:debug('Pathfinding to return to start finished with %d waypoints (%d ms)',
                #path, g_currentMission.time - (self.pathfindingStartedAt or 0))
        local returnCourse = Course(self.vehicle, CpMathUtil.pointsToGameInPlace(path), true)
        self.state = self.states.RETURNING_TO_START
        self.waitingForPrepare:set(true, 10000)
        self:startCourse(returnCourse, 1)
    else
        self:debug('No path found to return to fieldwork start after work is done (%d ms), stopping job',
                g_currentMission.time - (self.pathfindingStartedAt or 0))
        self.vehicle:stopCurrentAIJob(AIMessageSuccessFinishedJob.new())
    end
end
-----------------------------------------------------------------------------------------------------------------------
--- Use pathfinder to next waypoint
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyFieldWorkCourse:startPathfindingToNextWaypoint(ix)
    self:debug('start pathfinding to waypoint %d', ix + 1)
    local fm, bm = self:getFrontAndBackMarkers()
    self.turnContext = RowStartOrFinishContext(self.vehicle, self.fieldWorkCourse, ix + 1, ix + 1,
            self.turnNodes, self:getWorkWidth(), fm, bm, self:getTurnEndSideOffset(), self:getTurnEndForwardOffset())
    local _, steeringLength = AIUtil.getSteeringParameters(self.vehicle)
    local targetNode, zOffset = self.turnContext:getTurnEndNodeAndOffsets(steeringLength)
    local context = PathfinderContext(self.vehicle):allowReverse(self:getAllowReversePathfinding())
    self.waypointToContinueOnFailedPathfinding = ix + 1
    self.pathfinderController:registerListeners(self, self.onPathfindingDoneToNextWaypoint,
            self.onPathfindingFailedToNextWaypoint)
    self:debug('Start pathfinding to target waypoint %d, zOffset %.1f', ix + 1, zOffset)
    self.state = self.states.WAITING_FOR_PATHFINDER
    -- to have a course set while waiting for the pathfinder
    self:startCourse(self.fieldWorkCourse, self.waypointToContinueOnFailedPathfinding)
    self.pathfinderController:findPathToNode(context, targetNode, 0, zOffset)
end

function AIDriveStrategyFieldWorkCourse:onPathfindingFailedToNextWaypoint(controller, lastContext, wasLastRetry, currentRetryAttempt)
    if wasLastRetry then
        self:debug('Pathfinding to next waypoint failed again, continue directly at waypoint %d', self.waypointToContinueOnFailedPathfinding)
        self:startWaitingForLower()
        self:lowerImplements()
        self:startCourse(self.fieldWorkCourse, self.waypointToContinueOnFailedPathfinding)
    else
        self:debug('Pathfinding to next waypoint failed once, retry with disabled collisions')
        lastContext:collisionMask(0)
        controller:retry(lastContext)
    end
end

function AIDriveStrategyFieldWorkCourse:onPathfindingDoneToNextWaypoint(controller, success, course, goalNodeInvalid)
    if success then
        self:debug('Pathfinding to next waypoint finished')
        self:startCourseToWorkStart(course)
    else
        self:onPathfindingFailedToNextWaypoint()
    end
end

-----------------------------------------------------------------------------------------------------------------------
--- Connecting path
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyFieldWorkCourse:startConnectingPath(ix)
    -- ix was the last waypoint to work before the connecting path, ix + 1 is the first on the connecting path
    self:debug('Row finished before starting on a connecting path at waypoint %d.', ix + 1)
    -- gather the connecting path waypoints
    local connectingPath = {}
    local targetWaypointIx
    for i = ix + 1, self.fieldWorkCourse:getNumberOfWaypoints() do
        if self.fieldWorkCourse:isOnConnectingPath(i) then
            local x, _, z = self.fieldWorkCourse:getWaypointPosition(i)
            table.insert(connectingPath, { x = x, z = z })
        else
            targetWaypointIx = i
            break
        end
    end
    if targetWaypointIx == nil then
        self:debug('Can\'t find end of connecting path, continuing work')
        self:startWaitingForLower()
        self:lowerImplements()
        self:startCourse(self.fieldWorkCourse, ix + 1)
    else
        -- set up the turn context for the work starter to use when the pathfinding succeeds
        local fm, bm = self:getFrontAndBackMarkers()
        self.turnContext = RowStartOrFinishContext(self.vehicle, self.fieldWorkCourse, targetWaypointIx, targetWaypointIx,
                self.turnNodes, self:getWorkWidth(), fm, bm, self:getTurnEndSideOffset(), self:getTurnEndForwardOffset())
        local _, steeringLength = AIUtil.getSteeringParameters(self.vehicle)
        local targetNode, zOffset = self.turnContext:getTurnEndNodeAndOffsets(steeringLength)
        local context = PathfinderContext(self.vehicle):allowReverse(self:getAllowReversePathfinding())
        context:preferredPath(connectingPath):mustBeAccurate(true)
        self.rawConnectingPath = Course(self.vehicle, connectingPath, true)
        self.pathfinderController:registerListeners(self, self.onPathfindingDoneToConnectingPathEnd,
                self.onPathfindingFailedToConnectingPathEnd)
        self:debug('Connecting path has %d waypoints, start pathfinding to target waypoint %d, zOffset %.1f',
                #connectingPath, targetWaypointIx, zOffset)
        self.state = self.states.WAITING_FOR_PATHFINDER
        self.pathfinderController:findPathToNode(context, targetNode, 0, zOffset, 1)
    end
end

function AIDriveStrategyFieldWorkCourse:onPathfindingFailedToConnectingPathEnd(controller, lastContext, wasLastRetry, currentRetryAttempt)
    if wasLastRetry then
        self:debug('Pathfinding to end of connecting path failed again, use the connecting path as is')
        self:startCourseToWorkStart(self.rawConnectingPath)
    else
        self:debug('Pathfinding to end of connecting path failed once, retry with disabled collisions')
        lastContext:collisionMask(0)
        controller:retry(lastContext)
    end
end

function AIDriveStrategyFieldWorkCourse:onPathfindingDoneToConnectingPathEnd(controller, success, course, goalNodeInvalid)
    if success then
        self:debug('Pathfinding to end of connecting path finished')
        self:startCourseToWorkStart(course)
    else
        self:debug('Pathfinding to end of connecting path failed, use the connecting path as is')
        self:startCourseToWorkStart(self.rawConnectingPath)
    end
end

function AIDriveStrategyFieldWorkCourse:startCourseToWorkStart(course)
    self.workStarter = StartRowOnly(self.vehicle, self, self.ppc, self.turnContext, course)
    self.state = self.states.DRIVING_TO_WORK_START_WAYPOINT
    self:raiseImplements()
    self.ppc:setShortLookaheadDistance()
    self:startCourse(self.workStarter:getCourse(), 1)
end

-----------------------------------------------------------------------------------------------------------------------
--- Static parameters (won't change while driving)
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyFieldWorkCourse:setAllStaticParameters()
    AIDriveStrategyCourse.setAllStaticParameters(self)
    self:setFrontAndBackMarkers()
    self.loweringDurationMs = AIUtil.findLoweringDurationMs(self.vehicle)
    self.fieldWorkerProximityController = FieldWorkerProximityController(self.vehicle, self.workWidth)
end

-----------------------------------------------------------------------------------------------------------------------
--- Dynamic parameters (may change while driving)
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyFieldWorkCourse:getTurnEndSideOffset()
    return 0
end

function AIDriveStrategyFieldWorkCourse:getTurnEndForwardOffset()
    return 0
end

function AIDriveStrategyFieldWorkCourse:getLoweringDurationMs()
    return self.loweringDurationMs
end

function AIDriveStrategyFieldWorkCourse:getImplementRaiseLate()
    return self.settings.raiseImplementLate:getValue()
end

function AIDriveStrategyFieldWorkCourse:getImplementLowerEarly()
    return self.settings.lowerImplementEarly:getValue()
end

function AIDriveStrategyFieldWorkCourse:rememberWaypointToContinueFieldWork()
    local ix = self:getBestWaypointToContinueFieldWork()
    self.vehicle:rememberCpLastWaypointIx(ix)
end

function AIDriveStrategyFieldWorkCourse:getBestWaypointToContinueFieldWork()
    local bestKnownCurrentWpIx = self.fieldWorkCourse:getLastPassedWaypointIx() or self.fieldWorkCourse:getCurrentWaypointIx()
    -- after we return from a refill/unload, continue a bit before the point where we left to
    -- make sure not leaving any unworked patches
    local bestWpIx = self.fieldWorkCourse:getPreviousWaypointIxWithinDistanceOrToTurnEnd(bestKnownCurrentWpIx, 10)
    self:debug('Best return to fieldwork waypoint is %s (back from %d)', bestWpIx, bestKnownCurrentWpIx)
    return bestWpIx or bestKnownCurrentWpIx
end

function AIDriveStrategyFieldWorkCourse:setOffsetX()
    -- do nothing by default
end

function AIDriveStrategyFieldWorkCourse:calculateTightTurnOffset()
    if self.state == self.states.WORKING or self.state == self.states.DRIVING_TO_WORK_START_WAYPOINT then
        -- when rounding small islands or to start on a course with curves
        self.tightTurnOffset = AIUtil.calculateTightTurnOffset(self.vehicle, self.turningRadius, self.course,
                self.tightTurnOffset)
    else
        self.tightTurnOffset = 0
    end
end

function AIDriveStrategyFieldWorkCourse:isWorking()
    return self.state == self.states.WORKING or self.state == self.states.TURNING
end

--- Gets the current ridge marker state.
function AIDriveStrategyFieldWorkCourse:getRidgeMarkerState()
    return self.course:getRidgeMarkerState(self.ppc:getCurrentWaypointIx()) or 0
end

function AIDriveStrategyFieldWorkCourse:showAllInfo(note, ...)
    self:debug('%s: work width %.1f, turning radius %.1f, front marker %.1f, back marker %.1f',
            string.format(note, ...), self.workWidth, self.turningRadius, self.frontMarkerDistance, self.backMarkerDistance)
    self:debug(' - map: %s, field %s', g_currentMission.missionInfo.mapTitle,
            CpFieldUtil.getFieldNumUnderVehicle(self.vehicle))
    for _, implement in pairs(self.vehicle:getAttachedImplements()) do
        self:debug(' - %s', CpUtil.getName(implement.object))
    end
end

--- Updates the status variables.
---@param status CpStatus
function AIDriveStrategyFieldWorkCourse:updateCpStatus(status)
    ---@type Course
    if self.fieldWorkCourse then
        local ix = self.fieldWorkCourse:getCurrentWaypointIx()
        local numWps = self.fieldWorkCourse:getNumberOfWaypoints()
        status:setWaypointData(ix, numWps, self.remainingTime:getText())
    end
end

function AIDriveStrategyFieldWorkCourse:isTurnOnFieldActive()
    return self.settings.turnOnField:getValue()
end

-----------------------------------------------------------------------------------------------------------------------
--- Convoy management
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyFieldWorkCourse:getProgress()
    return self.fieldWorkCourse:getProgress()
end

function AIDriveStrategyFieldWorkCourse:isDone()
    return self.fieldWorkCourse:getCurrentWaypointIx() == self.fieldWorkCourse:getNumberOfWaypoints()
end

function AIDriveStrategyFieldWorkCourse:getFieldWorkProximity(node)
    return self.fieldWorkerProximityController:getFieldWorkProximity(node)
end

-----------------------------------------------------------------------------------------------------------------------
--- Overwrite implement functions, to enable a different cp functionality compared to giants fieldworker.
--- TODO: might have to find a better solution for these kind of problems.
-----------------------------------------------------------------------------------------------------------------------
local function emptyFunction(object, superFunc, ...)
    local rootVehicle = object.rootVehicle
    if rootVehicle.getJob then
        if rootVehicle:getIsCpActive() then
            return
        end
    end
    return superFunc(object, ...)
end
--- Makes sure the automatic work width isn't being reset.
VariableWorkWidth.onAIFieldWorkerStart = Utils.overwrittenFunction(VariableWorkWidth.onAIFieldWorkerStart, emptyFunction)
VariableWorkWidth.onAIImplementStart = Utils.overwrittenFunction(VariableWorkWidth.onAIImplementStart, emptyFunction)

-- TODO 25
-- This seems to be called when the Giants AI is done generating a field course, but we don't want the stock
-- AI to do anything when the course is loaded, so we just return if the vehicle is a CP vehicle.
local function noOpWhenCpActive(self, superFunc, ...)
    -- TODO this also comes when we just stopped a CP vehicle right after it was started
    if self.vehicle:getIsCpActive() then
        return
    end
    return superFunc(self, ...)
end
AIDriveStrategyFieldCourse.onFieldCourseLoadedCallback = Utils.overwrittenFunction(AIDriveStrategyFieldCourse.onFieldCourseLoadedCallback, noOpWhenCpActive)

-- TODO 25
-- The other thing messing us up is the delete() when we remove the Giants strategies in CpAITaskFieldWork,
-- because it triggers an AI end line event, raising all implements

AIDriveStrategyFieldCourse.delete = Utils.overwrittenFunction(AIDriveStrategyFieldCourse.delete, noOpWhenCpActive)
