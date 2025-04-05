---@class AIDriveStrategyStreetDriveToPoint : AIDriveStrategyCourse
AIDriveStrategyStreetDriveToPoint = CpObject(AIDriveStrategyCourse)

AIDriveStrategyStreetDriveToPoint.myStates = {
    PREPARE_TO_DRIVE = {},
    PREPARE_FINISHED = {},
    DRIVING_TO_COURSE_START = {},
    DRIVING_COURSE = {}
}
function AIDriveStrategyStreetDriveToPoint:init(task, job)
    AIDriveStrategyCourse.init(self, task, job)
    AIDriveStrategyCourse.initStates(self, AIDriveStrategyStreetDriveToPoint.myStates)
    self.state = self.states.INITIAL
    self.prepareState = self.states.PREPARE_TO_DRIVE
    self.debugChannel = CpDebug.DBG_FIELDWORK
    self.prepareTimeout = 0
    self.emergencyBrake = CpTemporaryObject(true)
end

function AIDriveStrategyStreetDriveToPoint:setAllStaticParameters()
    AIDriveStrategyCourse.setAllStaticParameters(self)
    self.turningRadius = AIUtil.getTurningRadius(self.vehicle)
    self:setFrontAndBackMarkers()
end

function AIDriveStrategyStreetDriveToPoint:initializeImplementControllers(vehicle)
    self:addImplementController(vehicle, MotorController, Motorized, {})
    self:addImplementController(vehicle, WearableController, Wearable, {})
end

---@param target GraphTarget
function AIDriveStrategyStreetDriveToPoint:setTarget(target)
    self.target = target
end

function AIDriveStrategyStreetDriveToPoint:isGeneratedCourseNeeded()
    return false
end

function AIDriveStrategyStreetDriveToPoint:getProximitySensorWidth()
    return AIUtil.getWidth(self.vehicle) * 1.2
end

function AIDriveStrategyStreetDriveToPoint:startWithoutCourse(jobParameters)
    -- to always have a valid course (for the traffic conflict detector mainly)
    local course = Course.createStraightForwardCourse(self.vehicle, 25)
    self:startCourse(course, 1)
end

function AIDriveStrategyStreetDriveToPoint:update(dt)
    AIDriveStrategyCourse.update(self, dt)
    self:updateImplementControllers(dt)
    if self.ppc:getCourse() and CpDebug:isChannelActive(CpDebug.DBG_FIELDWORK, self.vehicle) then
        self.ppc:getCourse():draw()
    end
end

function AIDriveStrategyStreetDriveToPoint:getDriveData(dt, vX, vY, vZ)
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
        self:setMaxSpeed(0)
        if self.target then
            self.vehicle:prepareForAIDriving()
            local targetVector = self.target:toVector()
            local goal = State3D(targetVector.x, targetVector.y, 0, 0)
            local context = PathfinderContext(self.vehicle)
            self.pathfinderController:findPathOnStreet(context, goal, 0)
            self.pathfinderController:registerListeners(self, self.onStreetPathfindingDone)
            self.state = self.states.WAITING_FOR_PATHFINDER
        else
            self:debug("Skipping drive to start point strategy, as no course was given!")
            self:setCurrentTaskFinished()
        end
    elseif self.state == self.states.DRIVING_TO_COURSE_START then
        self:setMaxSpeed(self.settings.streetSpeed:getValue())
    elseif self.state == self.states.DRIVING_COURSE then
        self:drivingCourse()
        self:setMaxSpeed(self.settings.streetSpeed:getValue())
    end

    if self.prepareState == self.states.PREPARE_TO_DRIVE then
        self:setMaxSpeed(0)
        local isReadyToDrive, blockingVehicle = self.vehicle:getIsAIReadyToDrive()
        if isReadyToDrive then
            self.prepareState = self.states.PREPARE_FINISHED
            self:debug('Ready to drive')
        else
            self:debugSparse('Not ready to drive because of %s, preparing ...', CpUtil.getName(blockingVehicle))
            if not self.vehicle:getIsAIPreparingToDrive() then
                self.prepareTimeout = self.prepareTimeout + dt
                if 2000 < self.prepareTimeout then
                    self:debug('Timeout preparing, continue anyway')
                    self.prepareState = self.states.PREPARE_FINISHED
                end
            end
        end
    end
    self:limitSpeed()
    self:checkProximitySensors(moveForwards)
    return gx, gz, moveForwards, self.maxSpeed, 100
end

-- TODO: This should go into a SpeedController?
function AIDriveStrategyStreetDriveToPoint:limitSpeed()
    AIDriveStrategyCourse.limitSpeed(self)
    if not self.lastSpeedCheck or (self.lastSpeedCheck and getTimeSec() - self.lastSpeedCheck > 1) then
        self.lastSpeedCheck = getTimeSec()
        local r = self.course:getMinRadiusWithinDistance(self.ppc:getRelevantWaypointIx(), 20)
        if r then
            -- we do not slow down over 50 m radius, but slow down to turning speed at the turningRadius,
            -- proportionally in between
            local slowDownFactor = math.min(50, math.max(self.turningRadius, r - self.turningRadius)) / 50
            self.limitedSpeed = self.settings.turnSpeed:getValue() +
                            (self.settings.streetSpeed:getValue() - self.settings.turnSpeed:getValue()) * slowDownFactor
            self:debug('Limiting speed to %.2f (r=%.2f, slowDownFactor=%.2f)', self.limitedSpeed, r, slowDownFactor)
        end
    end
    if self.limitedSpeed then
        self:setMaxSpeed(self.limitedSpeed)
    end
end

function AIDriveStrategyStreetDriveToPoint:drivingCourse()
    --- override
end

function AIDriveStrategyStreetDriveToPoint:onCourseEndReached()
    self:setCurrentTaskFinished()
end

-----------------------------------------------------------------------------------------------------------------------
--- Event listeners
-----------------------------------------------------------------------------------------------------------------------
---@param course Course
function AIDriveStrategyStreetDriveToPoint:onWaypointPassed(ix, course)
    if course:isLastWaypointIx(ix) then
        if self.state == self.states.DRIVING_TO_COURSE_START then
            local course, ix = self:getRememberedCourseAndIx()
            self:startCourse(course, ix)
            self.state = self.states.DRIVING_COURSE
        elseif self.state == self.states.DRIVING_COURSE then
            self:onCourseEndReached()
        end
    end
end

--------------------------------------------------------
--- Pathfinding
--------------------------------------------------------

---@param course Course
function AIDriveStrategyStreetDriveToPoint:isPathFindingNeeded(course)
    local ixClosest, distanceClosest, ixClosestRightDirection, distanceClosestRightDirection = course:getNearestWaypoints(self.vehicle:getAIDirectionNode())
    if distanceClosestRightDirection - distanceClosest > 25 then
        return true, ixClosest
    end
    return distanceClosestRightDirection > 10, ixClosestRightDirection
end

--- Pathfinding has finished
---@param controller PathfinderController
---@param success boolean
---@param course Course|nil
---@param goalNodeInvalid boolean|nil
function AIDriveStrategyStreetDriveToPoint:onPathfindingFinished(controller,
                                                                 success, course, goalNodeInvalid)
    if not success then
        self:debug('Pathfinding failed, giving up!')
        self.vehicle:stopCurrentAIJob(AIMessageCpErrorNoPathFound.new())
        return
    end
    if self.state == self.states.DRIVING_TO_COURSE_START then
        self:startCourse(course, 1)
    end
end

--- Pathfinding failed, but a retry attempt is leftover.
---@param controller PathfinderController
---@param lastContext PathfinderContext
---@param wasLastRetry boolean
---@param currentRetryAttempt number
function AIDriveStrategyStreetDriveToPoint:onPathfindingRetry(controller,
                                                              lastContext, wasLastRetry, currentRetryAttempt)
    --- TODO: Think of possible points of failures, that could be adjusted here.
    ---       Maybe a small reverse course might help to avoid a deadlock
    ---       after one pathfinder failure based on proximity sensor data and so on ..
    if self.state == self.states.DRIVING_TO_COURSE_START then
        local course = self:getRememberedCourseAndIx()
        controller:findPathToWaypoint(lastContext, course,
                1, 0, 0, 1)
    end
end

---@param course Course
---@param ix number
function AIDriveStrategyStreetDriveToPoint:startPathfindingToStart(course, ix)
    self.state = self.states.DRIVING_TO_COURSE_START
    self:rememberCourse(course, ix)
    self.pathfinderController:registerListeners(self, self.onPathfindingFinished, self.onPathfindingRetry)
    local context = PathfinderContext(self.vehicle):allowReverse(false):ignoreFruit():vehiclesToIgnore({ self.vehicle })
    self.pathfinderController:findPathToWaypoint(context, course,
            ix, 0, 0, 1)
end

function AIDriveStrategyStreetDriveToPoint:onStreetPathfindingDone(controller, success, course, goalNodeInvalid)
    if not success then
        self:debug('Pathfinding failed, giving up!')
        self.vehicle:stopCurrentAIJob(AIMessageCpErrorNoPathFound.new())
        return
    end
    local isNeeded, ix = self:isPathFindingNeeded(course)
    if isNeeded then
        self:startPathfindingToStart(course, ix)
    else
        self.state = self.states.DRIVING_COURSE
        self:startCourse(course, ix)
    end
end
