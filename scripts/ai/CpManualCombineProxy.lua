--- Proxy that mimics the AIDriveStrategyCombineCourse interface for manually-driven
--- combines, so the existing unloader strategy can interact with them without nil checks.
---@class CpManualCombineProxy
CpManualCombineProxy = CpObject()

CpManualCombineProxy.activeCalls = {}
CpManualCombineProxy.DYNAMIC_COURSE_LENGTH = 100
CpManualCombineProxy.COURSE_REFRESH_INTERVAL = 2000

function CpManualCombineProxy:init(vehicle)
    self.vehicle = vehicle
    self.unloader = CpTemporaryObject(nil)
    self.timeToCallUnloader = CpTemporaryObject(true)
    self.dynamicCourse = nil
    self.lastCourseRefreshTime = 0
    self.measuredBackDistance = 5

    self:findPipeImplement()
    self:measureBackDistance()
    self:refreshDynamicCourse()

    CpManualCombineProxy.activeCalls[vehicle] = self
end

function CpManualCombineProxy:delete()
    CpManualCombineProxy.activeCalls[self.vehicle] = nil
    self.dynamicCourse = nil
end

function CpManualCombineProxy:findPipeImplement()
    self.pipeImplement = nil
    self.pipeSpec = nil
    for _, childVehicle in ipairs(self.vehicle:getChildVehicles()) do
        if childVehicle.spec_pipe then
            self.pipeImplement = childVehicle
            self.pipeSpec = childVehicle.spec_pipe
            break
        end
    end
    if not self.pipeSpec and self.vehicle.spec_pipe then
        self.pipeImplement = self.vehicle
        self.pipeSpec = self.vehicle.spec_pipe
    end
end

function CpManualCombineProxy:measureBackDistance()
    local backMarkerNode, _, _, backMarkerOffset = Markers.getBackMarkerNode(self.vehicle)
    if backMarkerOffset then
        self.measuredBackDistance = math.abs(backMarkerOffset)
    end
end

--- Generates a straight course from the combine's current position and heading.
function CpManualCombineProxy:refreshDynamicCourse()
    self.dynamicCourse = Course.createStraightForwardCourse(self.vehicle,
        self.DYNAMIC_COURSE_LENGTH, 0, self.vehicle:getAIDirectionNode())
    self.lastCourseRefreshTime = g_time
end

function CpManualCombineProxy:update(dt)
    if g_time - self.lastCourseRefreshTime > self.COURSE_REFRESH_INTERVAL then
        self:refreshDynamicCourse()
    end
    self:callUnloaderWhenNeeded()
end

------------------------------------------------------------------------------------------------------------------------
-- Unloader calling: simplified version that always calls with the combine's current position
------------------------------------------------------------------------------------------------------------------------
function CpManualCombineProxy:callUnloaderWhenNeeded()
    if not self.timeToCallUnloader:get() then
        return
    end
    self.timeToCallUnloader:set(false, 1500)

    if self.unloader:get() then
        return
    end

    local bestUnloader = self:findUnloader()
    if bestUnloader then
        local strategy = bestUnloader:getCpDriveStrategy()
        if strategy and strategy.call then
            strategy:call(self.vehicle, nil)
        end
    end
end

function CpManualCombineProxy:findUnloader()
    local bestScore = -math.huge
    local bestUnloader
    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if AIDriveStrategyUnloadCombine.isActiveCpCombineUnloader(vehicle) then
            local x, _, z = getWorldTranslation(self.vehicle.rootNode)
            local driveStrategy = vehicle:getCpDriveStrategy()
            if driveStrategy:isServingPosition(x, z, 10) then
                local fillPct = driveStrategy:getFillLevelPercentage()
                if driveStrategy:isAllowedToBeCalled() and fillPct < 99 then
                    local dist, _ = driveStrategy:getDistanceAndEteToVehicle(self.vehicle)
                    local score = fillPct - 0.1 * dist
                    if score > bestScore then
                        bestUnloader = vehicle
                        bestScore = score
                    end
                end
            end
        end
    end
    return bestUnloader
end

------------------------------------------------------------------------------------------------------------------------
-- Interface methods that mimic AIDriveStrategyCombineCourse for the unloader
------------------------------------------------------------------------------------------------------------------------

function CpManualCombineProxy:registerUnloader(driver)
    self.unloader:set(driver, 1000)
end

function CpManualCombineProxy:deregisterUnloader(driver, noEventSend)
    self.unloader:reset()
end

function CpManualCombineProxy:hasAutoAimPipe()
    if self.pipeSpec then
        return self.pipeSpec.numAutoAimingStates > 0
    end
    return false
end

function CpManualCombineProxy:getFillType()
    if self.pipeImplement and self.pipeImplement.getDischargeNodeByIndex then
        local dischargeNode = self.pipeImplement:getDischargeNodeByIndex(
            self.pipeImplement:getPipeDischargeNodeIndex())
        if dischargeNode then
            return self.pipeImplement:getFillUnitFillType(dischargeNode.fillUnitIndex)
        end
    end
    return FillType.UNKNOWN
end

function CpManualCombineProxy:isDischarging()
    if self.pipeImplement and self.pipeImplement.getDischargeState then
        return self.pipeImplement:getDischargeState() ~= Dischargeable.DISCHARGE_STATE_OFF
    end
    return false
end

function CpManualCombineProxy:getPipeOffset(additionalOffsetX, additionalOffsetZ)
    local pipeOffsetX, pipeOffsetZ = 0, 0
    if self.pipeSpec then
        local pipeNode = self.pipeSpec.nodes and self.pipeSpec.nodes[1]
        if pipeNode and pipeNode.node and entityExists(pipeNode.node) then
            pipeOffsetX, _, pipeOffsetZ = localToLocal(pipeNode.node,
                self.vehicle:getAIDirectionNode(), 0, 0, 0)
        else
            pipeOffsetX = self.vehicle:getCpSettings().pipeOffsetX:getValue()
            pipeOffsetZ = self.vehicle:getCpSettings().pipeOffsetZ:getValue()
        end
    end
    return pipeOffsetX + (additionalOffsetX or 0), pipeOffsetZ + (additionalOffsetZ or 0), self:hasAutoAimPipe()
end

function CpManualCombineProxy:isPipeMoving()
    if self.pipeSpec then
        return self.pipeSpec.currentState == 0
    end
    return false
end

function CpManualCombineProxy:getPipeOffsetReferenceNode()
    return self.vehicle:getAIDirectionNode()
end

function CpManualCombineProxy:getAreaToAvoid()
    return nil
end

function CpManualCombineProxy:getMeasuredBackDistance()
    return self.measuredBackDistance
end

function CpManualCombineProxy:getFieldworkCourse()
    return self.dynamicCourse
end

function CpManualCombineProxy:getClosestFieldworkWaypointIx()
    return 1
end

function CpManualCombineProxy:getWorkWidth()
    if self.vehicle.getCpSettings then
        local settings = self.vehicle:getCpSettings()
        if settings and settings.workWidth then
            return settings.workWidth:getValue()
        end
    end
    return 6
end

function CpManualCombineProxy:getFruitAtSides()
    return nil, nil
end

------------------------------------------------------------------------------------------------------------------------
-- State queries: safe defaults for a manually-driven combine
------------------------------------------------------------------------------------------------------------------------

function CpManualCombineProxy:isWaitingForUnload()
    -- Return true only when the combine is actually stopped so the unloader strategy
    -- transitions correctly between moving-combine and stopped-combine unload states,
    -- and so the deadlock detector does not misfire when the grain cart is simply pausing.
    return AIUtil.isStopped(self.vehicle)
end

function CpManualCombineProxy:isWaitingForUnloadAfterPulledBack()
    return false
end

function CpManualCombineProxy:isWaitingForUnloadAfterCourseEnded()
    return false
end

function CpManualCombineProxy:willWaitForUnloadToFinish()
    local stopped = AIUtil.isStopped(self.vehicle)
    if stopped then
        -- Debounce: only report "waiting" after the combine has been stopped for 3+ continuous seconds.
        -- A momentary GPS micro-correction or terrain hitch would otherwise cause isInFrontAndAligned-
        -- ToMovingCombine() to return false, which combined with the grain cart being in the normal
        -- forward-of-direction-node unloading position (dz>0) kills isBehindAndAlignedToCombine() too,
        -- triggering the dreaded startWaitingForSomethingToDo() → tarp cycle.
        if not self._stoppedSinceTime then
            self._stoppedSinceTime = g_time
            CpUtil.debugVehicle(CpDebug.DBG_UNLOAD, self.vehicle,
                'CpManualCombineProxy:willWaitForUnloadToFinish: combine stopped, starting 3s debounce')
        end
        local waitingLongEnough = g_time - self._stoppedSinceTime > 3000
        if waitingLongEnough then
            CpUtil.debugVehicle(CpDebug.DBG_UNLOAD, self.vehicle,
                'CpManualCombineProxy:willWaitForUnloadToFinish: combine stopped >3s, returning true')
        end
        return waitingLongEnough
    else
        if self._stoppedSinceTime then
            CpUtil.debugVehicle(CpDebug.DBG_UNLOAD, self.vehicle,
                'CpManualCombineProxy:willWaitForUnloadToFinish: combine moving again (was stopped %.1fs)',
                (g_time - self._stoppedSinceTime) / 1000)
        end
        self._stoppedSinceTime = nil
        return false
    end
end

function CpManualCombineProxy:alwaysNeedsUnloader()
    return false
end

function CpManualCombineProxy:isReadyToUnload(noUnloadWithPipeInFruit)
    return true
end

function CpManualCombineProxy:isTurning()
    return false
end

function CpManualCombineProxy:isTurningButNotEndingTurn()
    return false
end

function CpManualCombineProxy:isTurnForwardOnly()
    return false
end

function CpManualCombineProxy:getTurnCourse()
    return nil
end

function CpManualCombineProxy:isFinishingRow()
    return false
end

function CpManualCombineProxy:isAboutToTurn()
    return false
end

function CpManualCombineProxy:isAboutToReturnFromPocket()
    return false
end

function CpManualCombineProxy:isManeuvering()
    return false
end

function CpManualCombineProxy:isOnHeadland(n)
    return false
end

function CpManualCombineProxy:isReversing()
    return false
end

function CpManualCombineProxy:isIdle()
    return false
end

function CpManualCombineProxy:hold(ms)
end

function CpManualCombineProxy:requestToIgnoreProximity(vehicle)
end

function CpManualCombineProxy:requestToMoveForward(requestingVehicle)
end

function CpManualCombineProxy:reconfirmRendezvous()
end

function CpManualCombineProxy:hasRendezvousWith(unloader)
    return false
end

function CpManualCombineProxy:getTurnArea()
    return nil, nil
end

function CpManualCombineProxy:isUnloadFinished()
    if self:isDischarging() then
        self._wasDischarging = true
        self._dischargeOffTime = nil
        return false
    end
    if self._wasDischarging then
        -- Require discharge to be off for 2 continuous seconds before declaring done.
        -- This prevents a momentary aim-miss (grain cart swerve, brief obstruction) from
        -- prematurely ending the unload cycle and forcing the grain cart to drive away and return.
        if not self._dischargeOffTime then
            self._dischargeOffTime = g_time
            CpUtil.debugVehicle(CpDebug.DBG_UNLOAD, self.vehicle,
                'CpManualCombineProxy:isUnloadFinished: discharge stopped, starting 2s debounce')
        end
        local elapsed = g_time - self._dischargeOffTime
        if elapsed > 2000 then
            CpUtil.debugVehicle(CpDebug.DBG_UNLOAD, self.vehicle,
                'CpManualCombineProxy:isUnloadFinished: discharge off for %.1fs, returning TRUE (unload done)', elapsed / 1000)
            self._wasDischarging = false
            self._dischargeOffTime = nil
            return true
        end
        CpUtil.debugVehicle(CpDebug.DBG_UNLOAD, self.vehicle,
            'CpManualCombineProxy:isUnloadFinished: discharge off for %.1fs, waiting for 2s debounce', elapsed / 1000)
    end
    return false
end

function CpManualCombineProxy:getFillLevelPercentage()
    -- The farmer is in full control. Fill level must never cause the grain cart to leave —
    -- the only valid exit is the pipe closing (isUnloadFinished). Always report full.
    return 1
end

function CpManualCombineProxy:isTurningOnHeadland()
    return false
end

function CpManualCombineProxy:getTurnStartWpIx()
    return 1
end

function CpManualCombineProxy:isProcessingFruit()
    return false
end

--- Marker so the unloader strategy can identify this as a manual-combine proxy
--- purely from the strategy object, without re-querying the vehicle.
function CpManualCombineProxy:isManualProxy()
    return true
end

function CpManualCombineProxy:isWaitingInPocket()
    return false
end

--- Needed so isActiveCpCombine() recognizes this as a valid combine strategy.
function CpManualCombineProxy:callUnloader()
end

function CpManualCombineProxy:getUnloadTargetType()
    return nil
end
