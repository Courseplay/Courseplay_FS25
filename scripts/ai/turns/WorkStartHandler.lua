--- Handle all implements at the start of the row (or wherever the vehicle must start working and lower implements)
---@class WorkStartHandler
WorkStartHandler = CpObject()

---@param vehicle table
---@param driveStrategy AIDriveStrategyFieldWorkCourse
function WorkStartHandler:init(vehicle, driveStrategy)
    self.logger = Logger('WorkStartHandler', CpDebug.DBG_TURN)
    self.vehicle = vehicle
    self.driveStrategy = driveStrategy
    self.settings = vehicle:getCpSettings()
    self.objectsAlreadyLowered = {}
    self.objectsNotYetLowered = {}
    -- the vehicle itself may have AI markers -> has work areas (built-in implements like a mower or cotton harvester)
    self.objectsNotYetLowered[vehicle] = true
    self.nObjectsToLower = 1
    for _, implement in pairs(AIUtil.getAllAIImplements(self.vehicle)) do
        self.objectsNotYetLowered[implement.object] = true
        self.nObjectsToLower = self.nObjectsToLower + 1
    end
end

---@return boolean true if all implements are being lowered (they not necessarily have been completely lowered yet)
function WorkStartHandler:allLowered()
    return #self.objectsAlreadyLowered == self.nObjectsToLower
end

---@return boolean true if at least one implement has been lowered
function WorkStartHandler:oneLowered()
    return #self.objectsAlreadyLowered > 0
end

--- Call this in update loop while the vehicle is approaching the start of the row. This will lower the implements
--- individually as they reach the work start node. Call until WorkStartHandler:allLowered() returns true.
---@param workStartNode number same as turn end node as in TurnContext, a node pointing into same direction as the row being started
---@param reversing boolean are we reversing? When reversing towards the work start, we'll have to lower all implements at the
--- same time, once all of them are beyond the work start node.
function WorkStartHandler:lowerImplementsAsNeeded(workStartNode, reversing)
    local function lowerThis(object)
        self.logger:debug('Lowering implement %s', CpUtil.getName(object))
        object:aiImplementStartLine()
        self.objectsNotYetLowered[object] = nil
        table.insert(self.objectsAlreadyLowered, object)
    end

    local allShouldBeLowered, dz = true
    for object in pairs(self.objectsNotYetLowered) do
        local shouldLowerThis, thisDz = self:shouldLowerThisImplement(object, workStartNode, reversing)
        dz = dz and math.max(dz, thisDz) or thisDz
        if reversing then
            allShouldBeLowered = allShouldBeLowered and shouldLowerThis
        elseif shouldLowerThis and self.objectsNotYetLowered[object] then
            lowerThis(object)
            if self:oneLowered() then
                self.driveStrategy:raiseControllerEvent(AIDriveStrategyCourse.onLoweringEvent)
            end
            if self:allLowered() then
                self.vehicle:raiseStateChange(VehicleStateChange.AI_START_LINE)
            end
        end
    end
    if reversing and allShouldBeLowered then
        self.logger:debug('Reversing and now all implements should be lowered')
        for object in pairs(self.objectsNotYetLowered) do
            lowerThis(object)
        end
        self.driveStrategy:raiseControllerEvent(AIDriveStrategyCourse.onLoweringEvent)
        self.vehicle:raiseStateChange(VehicleStateChange.AI_START_LINE)
    end
    return dz
end

---@param object table is a vehicle or implement object with AI markers (marking the working area of the implement)
---@param workStartNode number node at the first waypoint of the row, pointing in the direction of travel. This is where
--- the implement should be in the working position after a turn
---@param reversing boolean are we reversing? When reversing towards the turn end point, we must lower the implements
--- when we are _behind_ the turn end node (dz < 0), otherwise once we reach it (dz > 0)
---@return boolean, boolean, number the second one is true when the first is valid, and the distance to the work start
--- in meters (<0) when driving forward, nil when driving backwards.
function WorkStartHandler:shouldLowerThisImplement(object, workStartNode, reversing)
    local aiLeftMarker, aiRightMarker, aiBackMarker = WorkWidthUtil.getAIMarkers(object, true)
    if not aiLeftMarker then
        return true, nil
    end
    local dxLeft, _, dzLeft = localToLocal(aiLeftMarker, workStartNode, 0, 0, 0)
    local dxRight, _, dzRight = localToLocal(aiRightMarker, workStartNode, 0, 0, 0)
    local dxBack, _, dzBack = localToLocal(aiBackMarker, workStartNode, 0, 0, 0)
    local loweringDistance
    if AIUtil.hasAIImplementWithSpecialization(self.vehicle, SowingMachine) then
        -- sowing machines are stopped while lowering, but leave a little reserve to allow for stopping
        -- TODO: rather slow down while approaching the lowering point
        loweringDistance = 0.5
    else
        -- others can be lowered without stopping so need to start lowering before we get to the turn end to be
        -- in the working position by the time we get to the first waypoint of the next row
        loweringDistance = math.min(self.vehicle.lastSpeed, self.settings.turnSpeed:getValue() / 3600) *
                self.driveStrategy:getLoweringDurationMs() + 0.5 -- vehicle.lastSpeed is in meters per millisecond
    end
    local aligned = CpMathUtil.isSameDirection(object.rootNode, workStartNode, 15)
    -- some implements, especially plows may have the left and right markers offset longitudinally
    -- so if the implement is aligned with the row direction already, then just take the front one
    -- if not aligned, work with an average
    local dzFront = aligned and math.max(dzLeft, dzRight) or (dzLeft + dzRight) / 2
    local dxFront = (dxLeft + dxRight) / 2
    self.logger:debug('%s: dzLeft = %.1f, dzRight = %.1f, aligned = %s, dzFront = %.1f, dxFront = %.1f, dzBack = %.1f, loweringDistance = %.1f, reversing %s',
            CpUtil.getName(object), dzLeft, dzRight, aligned, dzFront, dxFront, dzBack, loweringDistance, tostring(reversing))
    local dz = self.driveStrategy:getImplementLowerEarly() and dzFront or dzBack
    if reversing then
        return dz < 0, nil
    else
        -- dz will be negative as we are behind the target node. Also, dx must be close enough, otherwise
        -- we'll lower them way too early if approaching the turn end from the side at about 90° (and we
        -- want a constant value here, certainly not the loweringDistance which changes with the current speed
        -- and thus introduces a feedback loop, causing the return value to oscillate, that is, we say should be
        -- lowered, than the vehicle stops, but now the loweringDistance will be low, so we say should not be
        -- lowering, vehicle starts again, and so on ...
        local normalLoweringDistance = self.driveStrategy:getLoweringDurationMs() * self.settings.turnSpeed:getValue() / 3600
        return dz > -loweringDistance and math.abs(dxFront) < normalLoweringDistance * 1.5, dz
    end
end
