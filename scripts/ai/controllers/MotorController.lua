--- Adds fuel save mode.
--- Also shuts the driver down, once the fuel level is lower than the threshold.
---@class MotorController : ImplementController
MotorController = CpObject(ImplementController)
MotorController.delayMs = 10 * 1000 -- 10sec
MotorController.speedThreshold = 0.1
function MotorController:init(vehicle, implement)
    ImplementController.init(self, vehicle, implement)
    self.motorSpec = implement.spec_motorized
    self.timer = CpTemporaryObject(true)
    self.timerSet = false
    self.vehicle.spec_cpAIWorker.motorDisabled = false
    self.isValid = true
    self.fuelThresholdSetting = g_Courseplay.globalSettings.fuelThreshold
    self.refuelData = {
        timer = CpTemporaryObject(true),
        lastFillLevels = {[self.implement] = {}}
    }
    for _, fillUnitIndex in ipairs(self.motorSpec.propellantFillUnitIndices) do
        self.refuelData.lastFillLevels[self.implement][fillUnitIndex] = -1
    end
end

function MotorController:update()
    if not self.isValid then
        return
    end
    if not self.settings.fuelSave:getValue() then
        if not self:getIsStarted() then
            self:startMotor()
            self.vehicle:raiseAIEvent('onAIFieldWorkerContinue', 'onAIImplementContinue')
        end
        self.timerSet = false
        return
    end
    if self:isFuelSaveDisabled() or self.driveStrategy:getMaxSpeed() >
        self.speedThreshold then
        if not self:getIsStarted() then
            self:startMotor()
            self.vehicle:raiseAIEvent("onAIFieldWorkerContinue", "onAIImplementContinue")
        end
        self.timerSet = false
    elseif self.vehicle:getLastSpeed() <= self.speedThreshold then
        if not self.timerSet then
            --- Resets the timer
            self.timer:set(false, self.delayMs)
            self.timerSet = true
        end
        if self.timer:get() then
            if self:getIsStarted() then
                self.vehicle:raiseAIEvent('onAIFieldWorkerBlock', 'onAIImplementBlock')
                self:stopMotor()
            end
        end
    end
    local needsFuelLowInfo, needsFuelEmptyInfo = false, false
    if self:isFuelLow(self.fuelThresholdSetting:getValue()) then
        if not g_Courseplay.globalSettings.waitForRefueling:getValue() then
            self.vehicle:stopCurrentAIJob(AIMessageErrorOutOfFuel.new())
        else
            needsFuelEmptyInfo = true
        end
    elseif self:isFuelLow(self.fuelThresholdSetting:getValue() + 5) then
        needsFuelLowInfo = true
    end
    if needsFuelEmptyInfo then
        self:setInfoText(InfoTextManager.FUEL_IS_EMPTY)
    else
        self:clearInfoText(InfoTextManager.FUEL_IS_EMPTY)
    end
    if needsFuelLowInfo then
        self:setInfoText(InfoTextManager.FUEL_IS_LOW)
    else
        self:clearInfoText(InfoTextManager.FUEL_IS_LOW)
    end
end

function MotorController:getDriveData()
    local maxSpeed
    if ImplementUtil.tryAndCheckRefillingFillUnits(self.refuelData.lastFillLevels) then
        self.refuelData.timer:set(false, 10 * 1000)
    end
    if not self.refuelData.timer:get() then
        maxSpeed = 0
    end
    if g_Courseplay.globalSettings.waitForRefueling:getValue() and
        self:isFuelLow(self.fuelThresholdSetting:getValue()) then
			
        maxSpeed = 0
    end

    return nil, nil, nil, maxSpeed
end

--- There is a time problem with the release of the driver, when no player is entered,
--- so we use this flag to make sure the :update() isn't used after :delete() was called.
function MotorController:delete()
    self.isValid = false
end

function MotorController:isFuelLow(threshold)
    for _, fillUnit in pairs(self.motorSpec.propellantFillUnitIndices) do
        if self.implement:getFillUnitFillLevelPercentage(fillUnit) * 100 < threshold then
            return true
        end
    end
end

--- Fuel save disabled, then we need to make sure the motor gets turned back on.
function MotorController:isFuelSaveDisabled()
    return not self.driveStrategy:isFuelSaveAllowed()
end

function MotorController:startMotor()
    self.vehicle.spec_cpAIWorker.motorDisabled = false
    self.implement:startMotor()
    self:debug('Started motor after fuel save.')
end

function MotorController:stopMotor()
    self.implement:stopMotor()
    self.vehicle.spec_cpAIWorker.motorDisabled = true
    self:debug('Stopped motor for fuel save.')
end

function MotorController:onFinished()
    local spec = self.implement.spec_fillUnit
    if spec.fillTrigger.isFilling then
        self.implement:setFillUnitIsFilling(false)
    end
end

function MotorController:getIsStarted()
    return self.vehicle:getMotorState() ~= MotorState.OFF
end