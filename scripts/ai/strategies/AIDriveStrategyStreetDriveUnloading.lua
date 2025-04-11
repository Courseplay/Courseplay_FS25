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
    self.baleLoader = self:addImplementController(vehicle, BaleLoaderController, BaleLoader)
    self.hasAutoLoader = self:addImplementController(vehicle, UniversalAutoloadController, nil, {}, "spec_universalAutoload") ~= nil
end

function AIDriveStrategyStreetDriveUnloading:setAllStaticParameters()
    AIDriveStrategyStreetDriveToPoint.setAllStaticParameters(self)
   
end

function AIDriveStrategyStreetDriveUnloading:delete()
    AIDriveStrategyStreetDriveToPoint.delete(self)
    if self.lastWaypointNode then 
        self.lastWaypointNode:destroy()
    end
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

---@param course Course
---@param ix number
function AIDriveStrategyStreetDriveUnloading:startDrivingCourse(course, ix)
    AIDriveStrategyStreetDriveToPoint.startDrivingCourse(self, course, ix)
    -- ---@type WaypointNode
    -- self.lastWaypointNode = WaypointNode("lastWaypoint")
    -- self.lastWaypointNode:setToWaypoint(course, course:getNumberOfWaypoints())
end

function AIDriveStrategyStreetDriveUnloading:updateUnloading()
    local targetDischargeNode, targetObject
    local isDischarging = false

    if self.baleLoader ~= nil then 
        local course = self.ppc:getCourse()
        if course:isCloseToLastWaypoint(1) then 
            if self.baleLoader:getIsAutomaticBaleUnloadingAllowed() then
                self.baleLoader:startAutomaticBaleUnloading()
                self:setMaxSpeed(0)
            elseif self.baleLoader:getIsAutomaticBaleUnloadingInProgress() then
                self:setMaxSpeed(0)
            end
        end
    elseif self.hasAutoLoader then
        --- TODO
    else
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
end

function AIDriveStrategyStreetDriveUnloading:getTargetExtension()
    local length = AIUtil.getLength(self.vehicle)
    return length + self.COURSE_EXTENSION
end