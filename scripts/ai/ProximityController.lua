ProximityController = CpObject()

ProximityController.states = {
    NO_OBSTACLE = {},
    SLOW_DOWN = {},
    STOP = {}
}

-- Proximity sensor
-- how far the sensor can see
ProximityController.sensorRange = 10
-- the sensor will proportionally reduce speed when objects are in range down to this limit (won't set a speed lower than this)
ProximityController.minLimitedSpeed = 2
-- will stop under this threshold
ProximityController.stopThresholdNormal = 1.5
ProximityController.messageThreshold = 3 * 1000 -- 3sec
function ProximityController:init(vehicle, width)
    self.vehicle = vehicle
    -- if anything closer than this, we stop
    self.stopThreshold = CpTemporaryObject(self.stopThresholdNormal)
    self.blockingVehicle = CpTemporaryObject(nil)
    self.blockingObject = CpTemporaryObject(nil)
    self.ignoreObjectCallbackRegistrations = {}
    local frontMarker, backMarker = Markers.getMarkerNodes(self.vehicle)
    self.forwardLookingProximitySensorPack = WideForwardLookingProximitySensorPack(
            self.vehicle, frontMarker, self.sensorRange, 1, width)
    self.backwardLookingProximitySensorPack = WideBackwardLookingProximitySensorPack(
            self.vehicle, backMarker, self.sensorRange, 1, self.vehicle.size.width)

    self.showBlockedByObjectMessageTimer = CpTemporaryObject(false)
    self:setState(self.states.NO_OBSTACLE, 'proximity controller initialized')
end

function ProximityController:setState(state, debugString)
    if self.state ~= state then
        CpUtil.debugVehicle(CpDebug.DBG_TRAFFIC, self.vehicle, debugString)
        self.state = state
    end
end

function ProximityController:setTemporaryStopThreshold(value, ttlMs)
    self.stopThreshold:set(value, ttlMs)
end

function ProximityController:registerIsSlowdownEnabledCallback(object, callback)
    self.isSlowdownEnabledCallback = callback
    self.isSlowdownEnabledCallbackObject = object
end

function ProximityController:isSlowdownEnabled(vehicle)
    if self.isSlowdownEnabledCallbackObject then
        return self.isSlowdownEnabledCallback(self.isSlowdownEnabledCallbackObject, vehicle)
    else
        return true
    end
end

--- Register a function the controller calls when a vehicle has been blocking us for some time.
function ProximityController:registerBlockingVehicleListener(object, callback)
    self.onBlockingVehicleCallback = callback
    self.onBlockingVehicleObject = object
end

---@param vehicle table the vehicle blocking us
---@param isBack boolean true if it was detected behind us
function ProximityController:onBlockingVehicle(vehicle, isBack)
    if self.onBlockingVehicleObject then
        -- notify our listeners
        self.onBlockingVehicleCallback(self.onBlockingVehicleObject, vehicle, isBack)
    end
end

--- Register a function the controller calls when any object which isn't a vehicle has been blocking us for some time.
function ProximityController:registerBlockingObjectListener(object, callback)
    self.onBlockingObjectCallback = callback
    self.onBlockingObjectObject = object
end

function ProximityController:unregisterBlockingObjectListener()
    self.onBlockingObjectCallback = nil
    self.onBlockingObjectObject = nil
end

---@param isBack boolean true if it was detected behind us
function ProximityController:onBlockingObject(isBack)
    if self.onBlockingObjectObject then
        -- notify our listeners
        self.onBlockingObjectCallback(self.onBlockingObjectObject, isBack)
    end
end

--- Registers a function to ignore a object or vehicle.
--- Multiple objects can register multiple callbacks.
--- An object/vehicle is ignored when any of the callbacks ignores it (OR)
--- TODO: Consider consolidating this with the other ignore logic for vehicles.
function ProximityController:registerIgnoreObjectCallback(object, callback)
    if not self.ignoreObjectCallbackRegistrations[object] then
        self.ignoreObjectCallbackRegistrations[object] = {}
    end
    self.ignoreObjectCallbackRegistrations[object][callback] = true
end

---@param object table
---@param vehicle table
---@param moveForwards boolean
---@param hitTerrain boolean
---@return boolean ignore object
function ProximityController:ignoreObject(object, vehicle, moveForwards, hitTerrain)
    for callbackObject, registeredCallbacks in pairs(self.ignoreObjectCallbackRegistrations) do
        for callbackFunction, _ in pairs(registeredCallbacks) do
            if callbackFunction(callbackObject, object, vehicle, moveForwards, hitTerrain) then
                -- one of the registered callback wants to ignore, then ignore
                return true
            end
        end
    end
    return false
end

---@return number, table distance of vehicle and vehicle if there is one in range
function ProximityController:checkBlockingVehicleFront()
    return self.forwardLookingProximitySensorPack:getClosestObjectDistanceAndRootVehicle()
end

---@return number, table distance of vehicle and vehicle if there is one in range
function ProximityController:checkBlockingVehicleBack()
    return self.backwardLookingProximitySensorPack:getClosestObjectDistanceAndRootVehicle()
end

--- Is vehicle in range of the front or rear sensors?
---@param vehicle table
---@return boolean, number true if vehicle is in range, distance of vehicle
function ProximityController:isVehicleInRange(vehicle)
    for _, sensorPack in ipairs({self.forwardLookingProximitySensorPack, self.backwardLookingProximitySensorPack}) do
        local d, otherVehicle = sensorPack:getClosestObjectDistanceAndRootVehicle()
        if otherVehicle == vehicle then
            return true, d
        end
    end
end

function ProximityController:disableLeftSide()
    self.forwardLookingProximitySensorPack:disableLeftSide()
    self.backwardLookingProximitySensorPack:disableRightSide()
end

function ProximityController:disableRightSide()
    self.forwardLookingProximitySensorPack:disableRightSide()
    self.backwardLookingProximitySensorPack:disableLeftSide()
end

function ProximityController:enableBothSides()
    self.forwardLookingProximitySensorPack:enable()
    self.backwardLookingProximitySensorPack:enable()
end

---@param maxSpeed number current maximum allowed speed for vehicle
---@param moveForwards boolean are we moving forwards?
---@return number|nil gx world x coordinate to drive to or nil
---@return number|nil gz world z coordinate to drive to or nil
---@return boolean|nil direction is forwards if true or nil
---@return number maximum speed adjusted to slow down (or 0 to stop) when obstacles are ahead, otherwise maxSpeed
function ProximityController:getDriveData(maxSpeed, moveForwards)
    local d, vehicle, object, range, deg, dAvg, hitTerrain = math.huge, nil, nil, 10, 0, 0, false
    local pack = moveForwards and self.forwardLookingProximitySensorPack or self.backwardLookingProximitySensorPack
    if pack then
        d, vehicle, object, hitTerrain, deg, dAvg = pack:getClosestObjectDistanceAndRootVehicle()
        range = pack:getRange()
    end
    if self:ignoreObject(object, vehicle, moveForwards, hitTerrain) then
        self:setState(self.states.NO_OBSTACLE, 'No obstacle')
        self.vehicle:resetCpActiveInfoText(InfoTextManager.BLOCKED_BY_OBJECT)
        return nil, nil, nil, maxSpeed
    end
    if object then 
        --- Makes sure the detected object is not an implement or the root vehicle.
        for _, childVehicle in pairs(self.vehicle:getChildVehicles()) do
            if object == childVehicle then
                self.vehicle:resetCpActiveInfoText(InfoTextManager.BLOCKED_BY_OBJECT)
                return nil, nil, nil, maxSpeed
            end
        end 
    end

    local normalizedD = d / (range - self.stopThreshold:get())
    if d < self.stopThreshold:get() then
        -- too close, stop
        self:setState(self.states.STOP,
                string.format('Obstacle ahead, d = %.1f, deg = %.1f, too close, stop.', d, deg))
        maxSpeed = 0
        self.showBlockedByObjectMessageTimer:setAndProlong(true, self.messageThreshold, self.messageThreshold)
        if vehicle ~= nil then
            if vehicle == self.blockingVehicle:get() then
                -- have been blocked by this guy long enough, try to recover
                CpUtil.debugVehicle(CpDebug.DBG_TRAFFIC, self.vehicle,
                        '%s has been blocking us for a while at %.1f m', CpUtil.getName(vehicle), d)
                self:onBlockingVehicle(vehicle, not moveForwards)
            end
            if not self.blockingVehicle:isPending() then
                -- first time we are being blocked by a vehicle, remember the time
                CpUtil.debugVehicle(CpDebug.DBG_TRAFFIC, self.vehicle, '%s is blocking us (%.1fm)', CpUtil.getName(vehicle), d)
                self.blockingVehicle:set(vehicle, nil, 7000)
            end
        else
            -- whatever is blocking us, it is not a vehicle
            if self.blockingObject:get() then
                -- have been blocked by an object long enough
                CpUtil.debugVehicle(CpDebug.DBG_TRAFFIC, self.vehicle, 'An object has been blocking us for a while at %.1f m', d)
                self:onBlockingObject(not moveForwards)
                self.blockingObject:set(false, nil, nil)
            elseif not self.blockingObject:isPending() then
                -- first time we are being blocked
                CpUtil.debugVehicle(CpDebug.DBG_TRAFFIC, self.vehicle, 'An object blocking us at %.1f m', d)
                self.blockingObject:set(true, nil, 5000)
            end
        end

    elseif normalizedD < 1 and self:isSlowdownEnabled(vehicle) then
        -- something in range, reduce speed proportionally when enabled
        local deltaV = maxSpeed - self.minLimitedSpeed
        maxSpeed = self.minLimitedSpeed + normalizedD * deltaV
        self:setState(self.states.SLOW_DOWN,
                string.format('Obstacle ahead, d = %.1f, deg = %.1f, slowing down to %.1f', d, deg, maxSpeed))
    else
        self:setState(self.states.NO_OBSTACLE, string.format('No obstacle, d = %.1f, deg = %.1f.', d, deg))
        self.blockingVehicle:reset()
    end
    if self.showBlockedByObjectMessageTimer:get() then 
        self.vehicle:setCpInfoTextActive(InfoTextManager.BLOCKED_BY_OBJECT)
    else 
        self.vehicle:resetCpActiveInfoText(InfoTextManager.BLOCKED_BY_OBJECT)
    end
    return nil, nil, nil, maxSpeed
end

function ProximityController:isStopped()
    return self.state == self.states.STOP   
end