---@class ImplementController
ImplementController = CpObject()

function ImplementController:init(vehicle, implement)
    self.vehicle = vehicle
    self.implement = implement
    self.settings = vehicle:getCpSettings()
    self.disabledStates = {}
    self.refillData = {
        timer = CpTemporaryObject(true),
        hasChanged = false,
        lastFillLevels = {}
    }
end

--- Get the controlled implement
function ImplementController:getImplement()
    return self.implement
end

---@param disabledStates table list of drive strategy states where the controlling of this implement is disabled
function ImplementController:setDisabledStates(disabledStates)
    self.disabledStates = disabledStates
end

function ImplementController:setDriveStrategy(driveStrategy)
    self.driveStrategy = driveStrategy
end

---@param currentState table|nil current state of the drive strategy
---@return boolean true if currentState is not one of the disabled states
function ImplementController:isEnabled(currentState)
    if self.disabledStates and currentState ~= nil then
        for _, state in pairs(self.disabledStates) do
            if currentState == state then
                return false
            end
        end
    end
    return true
end

function ImplementController:debug(...)
    CpUtil.debugImplement(CpDebug.DBG_IMPLEMENTS, self.implement, ...)
end

function ImplementController:debugSparse(...)
    if g_updateLoopIndex % 100 == 0 then
        self:debug(...)
    end
end

function ImplementController:info(...)
    CpUtil.infoVehicle(self.vehicle, CpUtil.getName(self.implement) .. ': ' .. string.format(...))
end

--- Drive strategies can instantiate controllers for implements and call getDriveData for each
--- implement. If the implement wants to change any of the driving parameter, it'll return
--- a non nil value for that parameter, most often a speed value to slow down or stop.
---@return number|nil gx world x coordinate to drive to or nil
---@return number|nil gz world z coordinate to drive to or nil
---@return boolean|nil direction is forwards if true or nil
---@return number|nil maximum speed or nil
function ImplementController:getDriveData()
    return nil, nil, nil, nil
end

function ImplementController:update(dt)
    -- implement in the derived classes as needed
end

function ImplementController:delete()

end

--- Called by the drive strategy on lowering of the implements.
function ImplementController:onLowering()
    --- override 
end

--- Called by the drive strategy on raising of the implements.
function ImplementController:onRaising()
    --- override
end

function ImplementController:onStart()
    --- override
end

--- Event raised when the driver was stopped.
---@param hasFinished boolean|nil flag passed by the info text.
function ImplementController:onFinished(hasFinished)
    --- override
end

function ImplementController:onPreFinished()
    return true
end

function ImplementController:onFinishRow(isHeadlandTurn)
end

function ImplementController:onTurnEndProgress(workStartNode, reversing,
    shouldLower, isLeftTurn)
end

--- Any object this controller wants us to ignore, can register here a callback at the proximity controller
function ImplementController:registerIgnoreProximityObjectCallback(proximityController)

end

function ImplementController:setInfoText(infoText)
    self.driveStrategy:setInfoText(infoText)
end

function ImplementController:clearInfoText(infoText)
    self.driveStrategy:clearInfoText(infoText)
end

function ImplementController:isFuelSaveAllowed()
    return true
end

function ImplementController:canContinueWork()
    return true
end

--- Stops the drive if the use additive fillunit setting is active and the tank is empty. 
---@param additives table
function ImplementController:updateAdditiveFillUnitEmpty(additives)

    if self.settings.useAdditiveFillUnit:getValue() then
        --- If the silage additive is empty, then stop the driver.
        if additives.available then
            if self.implement:getFillUnitFillLevelPercentage(
                additives.fillUnitIndex) <= 0 then
                self:debug('Stopped Cp, as the additive fill unit is empty.')
                self.vehicle:stopCurrentAIJob(AIMessageErrorOutOfFill.new())
            end
        end
    end
end

-------------------------------------
--- Refill
-------------------------------------

--- Registers an implement and a fill unit for a possible refilling later.
---@param implement table
---@param fillUnitIndex number
function ImplementController:addRefillImplementAndFillUnit(implement,
    fillUnitIndex)
    if self.refillData.lastFillLevels[implement] == nil then
        self.refillData.lastFillLevels[implement] = {}
    end
    self.refillData.lastFillLevels[implement][fillUnitIndex] = -1
end

function ImplementController:isRefillingAllowed()
    return next(self.refillData.lastFillLevels) ~= nil
end

function ImplementController:needsRefilling()
    return self:isRefillingAllowed()
end

function ImplementController:onStartRefilling()
    if self:isRefillingAllowed() then
        if self:needsRefilling() then
            for implement, data in pairs(self.refillData.lastFillLevels) do
                for fillUnitIndex, _ in pairs(data) do
                    self:debug('Preparing %s for loading with fill unit index: %d',
                        CpUtil.getName(implement), fillUnitIndex)
                    if implement.aiPrepareLoading ~= nil then
                        implement:aiPrepareLoading(fillUnitIndex)
                    end
                end
            end
            self.refillData.timer:set(false, 30 * 1000)
        end
        self.refillData.hasChanged = false
        ImplementUtil.hasFillLevelChanged(self.refillData.lastFillLevels, true)
    end
end

--- Checks if loading from a nearby fill trigger is possible or 
--- if the fill level is currently being changed by for example an auger wagon.  
---@return boolean dirty at least one fill unit is currently being filled.
---@return boolean changed at least one fill unit fill level has been changed since the start.
function ImplementController:onUpdateRefilling()
    if self:isRefillingAllowed() then
        if ImplementUtil.tryAndCheckRefillingFillUnits(self.refillData.lastFillLevels) or
            ImplementUtil.hasFillLevelChanged(self.refillData.lastFillLevels) then

            self.refillData.timer:set(false, 10 * 1000)
            self.refillData.hasChanged = true
        end
        return self.refillData.timer:get(), self.refillData.hasChanged
    end
    return true, false
end

function ImplementController:onStopRefilling()
    if self:isRefillingAllowed() then
        for implement, _ in pairs(self.refillData.lastFillLevels) do
            if implement.aiFinishLoading ~= nil then
                implement:aiFinishLoading()
            end
            local spec = implement.spec_fillUnit
            if spec and spec.fillTrigger.isFilling then
                implement:setFillUnitIsFilling(false)
            end
        end
    end
end
