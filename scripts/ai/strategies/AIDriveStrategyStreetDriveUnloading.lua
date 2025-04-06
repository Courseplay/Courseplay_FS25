---@class AIDriveStrategyStreetDriveUnloading : AIDriveStrategyStreetDriveToPoint
AIDriveStrategyStreetDriveUnloading = CpObject(AIDriveStrategyStreetDriveToPoint)

AIDriveStrategyStreetDriveUnloading.myStates = {

}
AIDriveStrategyStreetDriveUnloading.COURSE_EXTENSION = 2

function AIDriveStrategyStreetDriveUnloading:init(task, job)
    AIDriveStrategyStreetDriveToPoint.init(self, task, job)
    AIDriveStrategyCourse.initStates(self, AIDriveStrategyStreetDriveUnloading.myStates)

end

function AIDriveStrategyStreetDriveUnloading:initializeImplementControllers(vehicle)
    AIDriveStrategyStreetDriveToPoint.initializeImplementControllers(self, vehicle)

end

function AIDriveStrategyStreetDriveUnloading:drivingCourse()
    local course = self.ppc:getCourse()
    local length = AIUtil.getLength(self.vehicle)
    if course:isCloseToLastWaypoint(length * 3 + self.COURSE_EXTENSION) then
        self:setMaxSpeed(self.settings.turnSpeed:getValue())
        self:debugSparse("Slowing down close to the unloading point.")
    end
    if course:isCloseToLastWaypoint(length * 1.5 + self.COURSE_EXTENSION) then
        self:updateUnloading()
    end
end

function AIDriveStrategyStreetDriveUnloading:onCourseEndReached()
    --- TODO 
    self:setCurrentTaskFinished()
end

function AIDriveStrategyStreetDriveUnloading:updateUnloading()
    local targetDischargeNode, targetObject
    local isDischarging = false
    local nodes, nodesToObject = AIUtil.getAllDischargeNodes(self.vehicle)
    for _, node in pairs(nodes) do 
        isDischarging = isDischarging or nodesToObject[node]:getDischargeState() == Dischargeable.DISCHARGE_STATE_OBJECT
        if node.dischargeObject ~= nil then
            targetDischargeNode = node
            targetObject = nodesToObject[node]
        end
    end
    if isDischarging then 
        self:setMaxSpeed(0)
    elseif targetObject then
        self:setMaxSpeed(0)
        if targetObject:getCanDischargeToObject(targetDischargeNode) then
            targetObject:setCurrentDischargeNodeIndex(targetDischargeNode.index)
            targetObject:setDischargeState(Dischargeable.DISCHARGE_STATE_OBJECT)
        end
    end
end

function AIDriveStrategyStreetDriveUnloading:getTargetExtension()
    local length = AIUtil.getLength(self.vehicle)
    return length + self.COURSE_EXTENSION
end