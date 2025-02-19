--- Handle all implements at the end of the row (or wherever the vehicle must stop working and raise implements)
---@class WorkEndHandler
WorkEndHandler = CpObject()

---@param vehicle table
---@param driveStrategy AIDriveStrategyFieldWorkCourse
function WorkEndHandler:init(vehicle, driveStrategy)
    self.logger = Logger('WorkEndHandler', CpDebug.DBG_TURN)
    self.vehicle = vehicle
    self.driveStrategy = driveStrategy
    self.objectsAlreadyRaised = {}
    self.objectsNotYetRaised = {}
    -- the vehicle itself may have AI markers -> has work areas (built-in implements like a mower or cotton harvester)
    self.objectsNotYetRaised[vehicle] = true
    self.nObjectsToRaise = 1
    for _, implement in pairs(AIUtil.getAllAIImplements(self.vehicle)) do
        self.objectsNotYetRaised[implement.object] = true
        self.nObjectsToRaise = self.nObjectsToRaise + 1
    end
end

---@return boolean true if all implements are being raised (they not necessarily have been completely raised yet)
function WorkEndHandler:allRaised()
    return #self.objectsAlreadyRaised == self.nObjectsToRaise
end

---@return boolean true if at least one implement has been raised
function WorkEndHandler:oneRaised()
    return #self.objectsAlreadyRaised > 0
end

--- Call this in update loop while the vehicle is approaching the end of the row. This will raise the implements
--- individually as they reach the work end node. Call until WorkEndHandler:allRaised() returns true.
---@param workEndNode number same as turn start node as in TurnContext, a node pointing into same direction as the row just ended
--- positioned where the worked area ends.
function WorkEndHandler:raiseImplementsAsNeeded(workEndNode)
    -- and then check all implements
    for object in pairs(self.objectsNotYetRaised) do
        local shouldRaiseThis = self:shouldRaiseThisImplement(object, workEndNode)
        -- only when _all_ implements can be raised will we raise them all, hence the 'and'
        if shouldRaiseThis and self.objectsNotYetRaised[object] then
            self.logger:debug('Raising implement %s', CpUtil.getName(object))
            object:aiImplementEndLine()
            self.objectsNotYetRaised[object] = false
            table.insert(self.objectsAlreadyRaised, object)
            if self:oneRaised() then
                self.driveStrategy:raiseControllerEvent(AIDriveStrategyCourse.onRaisingEvent)
            end
            if self:allRaised() then
                self.vehicle:raiseStateChange(VehicleStateChange.AI_END_LINE)
            end
        end
    end
end

---@param turnStartNode number at the last waypoint of the row, pointing in the direction of travel. This is where
--- the implement should be raised when beginning a turn
function WorkEndHandler:shouldRaiseThisImplement(object, turnStartNode)
    local aiFrontMarker, _, aiBackMarker = WorkWidthUtil.getAIMarkers(object, true)
    -- if something (like a combine) does not have an AI marker it should not prevent from raising other implements
    -- like the header, which does have markers), therefore, return true here
    if not aiBackMarker or not aiFrontMarker then
        return true
    end
    local marker = self.driveStrategy:getImplementRaiseLate() and aiBackMarker or aiFrontMarker
    -- turn start node in the back marker node's coordinate system
    local _, _, dz = localToLocal(marker, turnStartNode, 0, 0, 0)
    self.logger:debugSparse('%s: shouldRaiseImplements: dz = %.1f', CpUtil.getName(object), dz)
    -- marker is just in front of the turn start node
    return dz > 0
end
