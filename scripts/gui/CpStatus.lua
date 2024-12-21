--- Summary status of Courseplay to display in the HUD
---@class CpStatus
CpStatus = CpObject()

function CpStatus:init(isActive, vehicle, currentWaypointIx, numberOfWaypoints)
    self:set(isActive, vehicle, currentWaypointIx, numberOfWaypoints)
    self.dirtyFlag = self.vehicle:getNextDirtyFlag()
end

function CpStatus:set(isActive, vehicle, currentWaypointIx, numberOfWaypoints)
    self.isActive = isActive
    self.vehicle = vehicle
    self.currentWaypointIx = currentWaypointIx
    self.numberOfWaypoints = numberOfWaypoints
end

function CpStatus:reset()
    self.isActive = false
    --- Fieldwork
    self.currentWaypointIx = nil
    self.numberOfWaypoints = nil
    self.remainingTimeText = ""
    --- Bale finder
    self.numBalesLeftOver = nil
    --- Bunker silo level driver
    self.compactionPercentage = nil
    --- Silo loader 
    self.fillLevelLeftOver = nil
    self.fillLevelLeftOverSinceStart = nil
    self.fillLevelPercentageLeftOver = nil
end

function CpStatus:start()
    
end

---@param active boolean
function CpStatus:setActive(active)
    if self.isActive ~= active then 
        self.isActive = active
        self:raiseDirtyFlag()
        if not active then 
            self:reset()
        else 
            self:start()
        end
    end
end


---@param dt number
---@param isActive boolean
---@param strategy AIDriveStrategyCourse
function CpStatus:update(dt, isActive, strategy)
    if isActive then 
        if strategy then
            strategy:updateCpStatus(self)
        end
    end 
    self:setActive(isActive)
end

---@param currentWaypointIx number
---@param numberOfWaypoints number
---@param remainingTimeText string
function CpStatus:setWaypointData(currentWaypointIx, numberOfWaypoints, remainingTimeText)
    if self.currentWaypointIx ~= currentWaypointIx then 
        self.currentWaypointIx = currentWaypointIx
        self.numberOfWaypoints = numberOfWaypoints
        self.remainingTimeText = remainingTimeText
        self:raiseDirtyFlag()
        self:updateWaypointVisibility()
    end
end

---@param numBalesLeftOver number 
function CpStatus:setBaleData(numBalesLeftOver)
    if self.numBalesLeftOver ~= numBalesLeftOver then
        self.numBalesLeftOver = numBalesLeftOver
        self:raiseDirtyFlag()
    end
end

---@param compactionPercentage number 
function CpStatus:setLevelSiloStatus(compactionPercentage)
    local roundedCompactionPercentage = MathUtil.round(compactionPercentage)
    if self.compactionPercentage ~= roundedCompactionPercentage then
        self.compactionPercentage = roundedCompactionPercentage
        self:raiseDirtyFlag()
    end
end

---@param fillLevelLeftOver number
---@param fillLevelLeftOverSinceStart number
function CpStatus:setSiloLoaderStatus(fillLevelLeftOver, fillLevelLeftOverSinceStart)
    if self.fillLevelLeftOver == nil or math.abs(self.fillLevelLeftOver - fillLevelLeftOver) > 2000 then
        self.fillLevelLeftOver = fillLevelLeftOver
        self.fillLevelLeftOverSinceStart = fillLevelLeftOverSinceStart
        self.fillLevelPercentageLeftOver = MathUtil.round(100 * (1 - fillLevelLeftOver / fillLevelLeftOverSinceStart))
        self:raiseDirtyFlag()
    end
end

function CpStatus:updateWaypointVisibility()
    SpecializationUtil.raiseEvent(self.vehicle, "onCpFieldworkWaypointChanged", self.currentWaypointIx)
end

function CpStatus:getWaypointText()
    if self.isActive and self.currentWaypointIx and self.numberOfWaypoints then 
        return string.format('%d/%d', self.currentWaypointIx, self.numberOfWaypoints)
    end 
    return '--/--'
end

function CpStatus:getBalesText()
    if self.isActive and self.numBalesLeftOver ~=nil then 
        return string.format('%d', self.numBalesLeftOver)
    end 
    return '--'
end

---@param withoutPercentageSymbol boolean|nil
---@return string
function CpStatus:getCompactionText(withoutPercentageSymbol)
    if self.isActive and self.compactionPercentage ~=nil then 
        if withoutPercentageSymbol then 
            return tostring(self.compactionPercentage)
        end
        return string.format('%d%%', self.compactionPercentage)
    end 
    return '--'
end

function CpStatus:getSiloFillLevelPercentageLeftOver(withoutPercentageSymbol)
    if self.isActive and self.fillLevelLeftOver ~= nil  then 
        local value, unitExtension = CpGuiUtil.getFixedUnitValueWithUnitSymbol(self.fillLevelLeftOver)
        return string.format("%.1f %s%s", value, unitExtension, g_i18n:getText("unit_literShort"))
    end 
    return '--'
end

function CpStatus:getTimeRemainingText()
    return self.remainingTimeText
end

function CpStatus:getText()
    if not self.isActive then 
        return ""
    end
    if self.fillLevelLeftOver ~= nil then 
        return self:getSiloFillLevelPercentageLeftOver()
    end
    if self.compactionPercentage ~= nil then 
        return self:getCompactionText()
    end
    if self.numBalesLeftOver ~= nil then 
        return self:getBalesText()
    end
    return self.remainingTimeText or ""
end

function CpStatus:getIsActive()
    return self.isActive
end

function CpStatus:raiseDirtyFlag()
    self.vehicle:raiseDirtyFlags(self.dirtyFlag)
end

function CpStatus:onWriteUpdateStream(streamId, connection, dirtyMask)
	if not connection:getIsServer() and streamWriteBool(streamId, bitAND(dirtyMask, self.dirtyFlag) ~= 0) then
        streamWriteBool(streamId, self.isActive or false)
        --- Fieldwork
		streamWriteInt32(streamId, self.numberOfWaypoints or 0)
        streamWriteInt32(streamId, self.currentWaypointIx or 0)
        streamWriteString(streamId, self.remainingTimeText or "")
        --- Bale finder
        streamWriteInt32(streamId, self.numBalesLeftOver or 0)
        --- Bunker silo level driver
        streamWriteInt32(streamId, self.compactionPercentage or 0)
        --- Silo loader 
        streamWriteInt32(streamId, self.fillLevelLeftOver or 0)
        streamWriteInt32(streamId, self.fillLevelLeftOverSinceStart or 0)
        streamWriteInt32(streamId, self.fillLevelPercentageLeftOver or 0)
	end
end

function CpStatus:onReadUpdateStream(streamId, timestamp, connection)
	if connection:getIsServer() and streamReadBool(streamId) then
        self.isActive = streamReadBool(streamId)
        --- Fieldwork
        self.numberOfWaypoints = streamReadInt32(streamId)
        self.currentWaypointIx = streamReadInt32(streamId)
        self.remainingTimeText = streamReadString(streamId)
        --- Bale finder
        self.numBalesLeftOver = streamReadInt32(streamId)
        --- Bunker silo level driver
        self.compactionPercentage = streamReadInt32(streamId)

        self.fillLevelLeftOver = streamReadInt32(streamId)
        self.fillLevelLeftOverSinceStart = streamReadInt32(streamId)
        self.fillLevelPercentageLeftOver = streamReadInt32(streamId)
        self:updateWaypointVisibility()
	end
end