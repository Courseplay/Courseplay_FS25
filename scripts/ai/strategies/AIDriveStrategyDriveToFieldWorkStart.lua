--[[
This file is part of Courseplay (https://github.com/Courseplay/Courseplay_FS25)
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

Drive strategy for driving to the waypoint where we want to start the fieldwork.

- Make sure everything is raised (maybe folded?)
- Find a path to the start waypoint (first or last worked on), avoiding fruit
- When getting close to the end of the course (to the work start waypoint), give control
  to the field work strategy, which will then drive the last few meters making sure the
  implements are in a working position when reaching the work start waypoint.

]]--

---@class AIDriveStrategyDriveToFieldWorkStart : AIDriveStrategyCourse
---@field job CpAIJobFieldWork
AIDriveStrategyDriveToFieldWorkStart = CpObject(AIDriveStrategyCourse)

AIDriveStrategyDriveToFieldWorkStart.myStates = {
    PREPARE_TO_DRIVE = {},
    DRIVING_TO_WORK_START = {},
    WORK_START_REACHED = {},
}

-- minimum distance to the target when this strategy is even used
AIDriveStrategyDriveToFieldWorkStart.minDistanceToDrive = 20

AIDriveStrategyDriveToFieldWorkStart.normalFillLevelFullPercentage = 99.5

function AIDriveStrategyDriveToFieldWorkStart:init(task, job)
    AIDriveStrategyCourse.init(self, task, job)
    AIDriveStrategyCourse.initStates(self, AIDriveStrategyDriveToFieldWorkStart.myStates)
    self.state = self.states.INITIAL
    self.debugChannel = CpDebug.DBG_FIELDWORK
    self.prepareTimeout = 0
    self.emergencyBrake = CpTemporaryObject(true)
end

function AIDriveStrategyDriveToFieldWorkStart:delete()
    AIDriveStrategyCourse.delete(self)
end

function AIDriveStrategyDriveToFieldWorkStart:initializeImplementControllers(vehicle)
    -- these can't handle the standard Giants AI events to raise, so we need to have the controllers for them
    self:addImplementController(vehicle, PickupController, Pickup, {})
    self:addImplementController(vehicle, CutterController, Cutter, {})
    self:addImplementController(vehicle, SowingMachineController, SowingMachine, {})

    self:addImplementController(vehicle, MotorController, Motorized, {})
    self:addImplementController(vehicle, WearableController, Wearable, {})
    self:addImplementController(vehicle, FoldableController, Foldable, {})
end

function AIDriveStrategyDriveToFieldWorkStart:start(course, startIx, jobParameters)
    self:updateCourseOffset(course)
    --- Saves the course start position, so it can be given to the job instance.
    local x, _, z = course:getWaypointPosition(startIx)
    self.startPosition = {x = x, z = z}
    local distance = course:getDistanceBetweenVehicleAndWaypoint(self.vehicle, startIx)
    if distance < AIDriveStrategyDriveToFieldWorkStart.minDistanceToDrive then
        self:debug('Closer than %.0f m to start waypoint (%d), start fieldwork directly',
                AIDriveStrategyDriveToFieldWorkStart.minDistanceToDrive, startIx)
        self.state = self.states.WORK_START_REACHED
        self.job:setStartPosition(self.startPosition)
        self:setCurrentTaskFinished()
    else
        self:debug('Start driving to work start waypoint')
        local implement = AIUtil.getImplementWithSpecialization(self.vehicle, Cutter)
        if self.settings.foldImplementAtEnd:getValue() then
            self.vehicle:prepareForAIDriving()
        end
        if self:giantsPreFoldHeaderWithWheelsFix(implement) then 
            self:giantsPostFoldHeaderWithWheelsFix(implement)
        end
        self:startCourseWithPathfinding(course, startIx)
    end
end

function AIDriveStrategyDriveToFieldWorkStart:update(dt)
    AIDriveStrategyCourse.update(self, dt)
    self:updateImplementControllers(dt)
    if CpDebug:isChannelActive(CpDebug.DBG_FIELDWORK, self.vehicle) then
        if self.ppc:getCourse() and self.ppc:getCourse():isTemporary() and CpDebug:isChannelActive(CpDebug.DBG_FIELDWORK, self.vehicle) then
            self.ppc:getCourse():draw()
        end
    end
end

function AIDriveStrategyDriveToFieldWorkStart:getDriveData(dt, vX, vY, vZ)

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

    if self.state == self.states.PREPARE_TO_DRIVE then
        self:setMaxSpeed(0)
        local isReadyToDrive, blockingVehicle = self.vehicle:getIsAIReadyToDrive()
        if isReadyToDrive or not self.settings.foldImplementAtEnd:getValue() then
            self.state = self.states.DRIVING_TO_WORK_START
            self:debug('Ready to drive to work start')
        else
            self:debugSparse('Not ready to drive because of %s, preparing ...', CpUtil.getName(blockingVehicle))
            if not self.vehicle:getIsAIPreparingToDrive() then
                self.prepareTimeout = self.prepareTimeout + dt
                if 2000 < self.prepareTimeout then
                    self:debug('Timeout preparing, continue anyway')
                    self.state = self.states.DRIVING_TO_WORK_START
                end
            end
        end
    elseif self.state == self.states.DRIVING_TO_WORK_START then
        self:setMaxSpeed(self.settings.fieldSpeed:getValue())
    elseif self.state == self.states.WORK_START_REACHED then
        if self.emergencyBrake:get() then
            self:debugSparse('Work start reached but field work did not start...')
            self:setMaxSpeed(0)
        else
            self:setMaxSpeed(self.settings.turnSpeed:getValue())
        end
    end

    self:checkProximitySensors(moveForwards)

    return gx, gz, moveForwards, self.maxSpeed, 100
end

------------------------------------------------------------------------------------------------------------------------
--- Pathfinding
---------------------------------------------------------------------------------------------------------------------------
---@param course Course
---@param ix number
function AIDriveStrategyDriveToFieldWorkStart:startCourseWithPathfinding(course, ix)
    self.course = course
    self.ppc:setCourse(self.course)
    self.ppc:initialize(ix)
    self:rememberCourse(course, ix)
    self:setFrontAndBackMarkers()

    local context = PathfinderContext(self.vehicle)
    context:maxFruitPercent(self.settings.avoidFruit:getValue() and 10 or math.huge)
    -- if there is fruit at the target, create an area around it where the pathfinder ignores the fruit
    -- so there's no penalty driving there. This is to speed up pathfinding when start harvesting for instance
    local x, _, z = course:getWaypointPosition(ix)
    local fruitAtTarget = PathfinderUtil.hasFruit(x, z, self.workWidth, self.workWidth)
    local fieldNum = CpFieldUtil.getFieldIdAtWorldPosition(x, z)
    context:areaToIgnoreFruit(fruitAtTarget and PathfinderUtil.Area(x, z, 2 * self.workWidth) or nil)
    context:useFieldNum(fieldNum):allowReverse(self:getAllowReversePathfinding())

    local _, steeringLength = AIUtil.getSteeringParameters(self.vehicle)
    -- always drive a behind the target waypoint so there's room to straighten out towed implements
    -- a bit before start working
    self.zOffset = math.min(-self.frontMarkerDistance, -steeringLength)
    self:debug('Pathfinding to waypoint %d, with zOffset %.1f = min(%.1f, %.1f)', ix, self.zOffset,
            -self.frontMarkerDistance, -steeringLength)

    self.pathfinderController:findPathToWaypoint(context, course, ix, 0, self.zOffset, 1)
end

--- Pathfinding has finished
---@param controller PathfinderController
---@param success boolean
---@param course Course|nil
---@param goalNodeInvalid boolean|nil
function AIDriveStrategyDriveToFieldWorkStart:onPathfindingFinished(controller, success, course, goalNodeInvalid)
    if success then 
        course:adjustForTowedImplements(2)
    else
        self:debug('Pathfinding to start fieldwork failed, using alignment course instead')
        local fieldWorkCourse, ix = self:getRememberedCourseAndIx()
        course = self:createAlignmentCourse(fieldWorkCourse, ix)
    end
    self.state = self.states.PREPARE_TO_DRIVE
    self:startCourse(course, 1)
end

--- Pathfinding failed, but a retry attempt is leftover.
---@param controller PathfinderController
---@param lastContext PathfinderContext
---@param wasLastRetry boolean
---@param currentRetryAttempt number
function AIDriveStrategyDriveToFieldWorkStart:onPathfindingFailed(controller, lastContext, wasLastRetry, currentRetryAttempt)
    self:debug('Failed to find a path, trying with a reduced off-field penalty and no fruit avoidence again')
    lastContext:offFieldPenalty(PathfinderContext.defaultOffFieldPenalty / 2):ignoreFruit():ignoreFruitHeaps()
    controller:retry(lastContext)
end

-----------------------------------------------------------------------------------------------------------------------
--- Event listeners
-----------------------------------------------------------------------------------------------------------------------
---@param course Course
function AIDriveStrategyDriveToFieldWorkStart:onWaypointChange(ix, course)
    if course:isCloseToLastWaypoint(15) then
        self.state = self.states.WORK_START_REACHED
        -- just in case no one takes the wheel in a few seconds
        self.emergencyBrake:set(false, 2000)
        self:debug('Almost at the work start waypoint, preparing for work')
        -- let the field work strategy know where to continue
        self.job:setStartFieldWorkCourse(course, ix)
        self.job:setStartPosition(self.startPosition)
        self:setCurrentTaskFinished()
    end
end

--- For whatever reason giants decided to turn on sprayers in: 
--- Sprayer:onStartWorkAreaProcessing(dt), when AI is active.
--- Even if the AI is not a fieldworker and so on ...
function AIDriveStrategyDriveToFieldWorkStart.giantsTurnOnFix(vehicle, superFunc, ...)
    local rootVehicle = vehicle.rootVehicle
    if not rootVehicle.getIsCpActive or not rootVehicle:getIsCpActive() then 
        return superFunc(vehicle, ...)
    end
    if rootVehicle.getIsCpDriveToFieldWorkActive and rootVehicle:getIsCpDriveToFieldWorkActive() then 
        return
    end
    if not vehicle:getCanBeTurnedOn() then 
        return
    end
    return superFunc(vehicle, ...)
end
TurnOnVehicle.setIsTurnedOn = Utils.overwrittenFunction(TurnOnVehicle.setIsTurnedOn, 
                        AIDriveStrategyDriveToFieldWorkStart.giantsTurnOnFix)

--- Removes the fold ai prepare event, as these cutters with foldable wheels don't need to be folded.
---@param implement table|nil
---@return boolean|nil Event was removed
function AIDriveStrategyDriveToFieldWorkStart:giantsPreFoldHeaderWithWheelsFix(implement)
    if not implement or not implement.spec_foldable or not implement.spec_attachable then 
        return
    end
    local controller = implement.spec_foldable.controlledActionFold
    if not controller then 
        return
    end
    for _, attacherJoint in pairs(implement:getInputAttacherJoints()) do
        if attacherJoint.jointType ~= AttacherJoints.JOINTTYPE_CUTTER and
            attacherJoint.jointType ~= AttacherJoints.JOINTTYPE_CUTTERHARVESTER then  
            --- At least one attaching joint, which is not meant for a cutter was found.
            --- This properly means a foldable cutter to trailer was found, like the New Holland Superflex Draper 45 ft. 
            local ixToDelete
            for ix, listener in pairs(controller.aiEventListener) do 
                if listener.eventName == "onAIImplementPrepare" then 
                    ixToDelete = ix
                    break
                end
            end
            if ixToDelete ~= nil then 
                table.remove(controller.aiEventListener, ixToDelete)
                implement:setFoldDirection(implement.spec_foldable.turnOnFoldDirection or 1)
                return true
            end
        end
    end
end

--- Resets to status quo
---@param implement table
function AIDriveStrategyDriveToFieldWorkStart:giantsPostFoldHeaderWithWheelsFix(implement)
    implement.spec_foldable.controlledActionFold:addAIEventListener(implement, "onAIImplementPrepare", -1, true)
end