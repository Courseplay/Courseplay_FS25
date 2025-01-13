---@class CourseRecorder
CourseRecorder = CpObject()

function CourseRecorder:init(courseDisplay)
    self.recording = false
    self.paused = false
    self.courseDisplay = courseDisplay
end

function CourseRecorder:debug(...)
    CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, ...)
end

function CourseRecorder:update()
    if not self.recording or self.paused then return end
    local waypoint = self:getVehiclePositionAsWaypoint()
    local previousWaypoint = self.course:getWaypoint(self.course:getNumberOfWaypoints())
    local dist = previousWaypoint:getDistanceFromVehicle(self.vehicle)
    local angleDiff = math.abs(waypoint.yRot - previousWaypoint.yRot)
    if dist > 5 or angleDiff > math.rad(10) then
        self:addWaypoint(waypoint)
        self:debug('Recorded waypoint %d.', self.course:getNumberOfWaypoints())
    end
end

function CourseRecorder:start(vehicle)
    self.recording = true
    self.paused = false
    self.vehicle = vehicle
    self:debug('Course recording started')
    self.course = Course(vehicle, {})
    self.courseDisplay:setCourse(self.course)
    self:addWaypoint(self:getVehiclePositionAsWaypoint())
end

function CourseRecorder:stop()
    self.recording = false
    self.paused = false
    self:debug('Course recording stopped, recorded %d waypoints', self.course:getNumberOfWaypoints())
    self.courseDisplay:clear()
end

function CourseRecorder:pause()
    self.paused = true
    self:debug("Paused the course recording.")
end

function CourseRecorder:unpause()
    self.paused = false
    self:debug("Unpaused the course recording.")
end

function CourseRecorder:isPaused()
    return self.paused
end

function CourseRecorder:isRecording()
    return self.recording
end

function CourseRecorder:getRecordedCourse()
    return self.course
end

function CourseRecorder:getRecordedWaypoints()
    return self.course:getAllWaypoints()
end

function CourseRecorder:addWaypoint(waypoint)
    self.course:appendWaypoints({waypoint})
    self.courseDisplay:updateChanges()
end

function CourseRecorder:getVehiclePositionAsWaypoint()
    local x, _, z = getWorldTranslation(self.vehicle.rootNode)
    local dirX, _, dirZ = localDirectionToWorld(self.vehicle.rootNode, 0, 0, 1)
    local yRot = MathUtil.getYRotationFromDirection(dirX, dirZ)
    return Waypoint({x = x, z = z, yRot = yRot, rev = AIUtil.isReversing(self.vehicle)})
end