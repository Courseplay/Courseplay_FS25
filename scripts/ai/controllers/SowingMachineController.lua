--- For now only activates optional sowing machines, for example a roller with a sowing machine configuration.
---@class SowingMachineController : ImplementController
SowingMachineController = CpObject(ImplementController)

function SowingMachineController:init(vehicle, implement)
    ImplementController.init(self, vehicle, implement)
    self.sowingMachineSpec = self.implement.spec_sowingMachine
	self:addRefillImplementAndFillUnit(self.implement, self.sowingMachineSpec.fillUnitIndex)
end

function SowingMachineController:update()
	if not self.settings.optionalSowingMachineEnabled:getIsDisabled() then
		if self.settings.optionalSowingMachineEnabled:getValue() then
			--- Makes sure the sowing machine get's turned on
			if not self.implement:getIsTurnedOn() then
				self.implement:setIsTurnedOn(true)
			end
		else
			--- Makes sure the sowing machine is turned off if not needed.
			if self.implement:getIsTurnedOn() then
				self.implement:setIsTurnedOn(false)
			end
		end
	end
	if self.sowingMachineSpec.showWrongFruitForMissionWarning then
		self:debug("Wrong fruit type for mission selected!")
		self.vehicle:stopCurrentAIJob(AIMessageErrorWrongMissionFruitType.new())
	end
	if not self.implement:getCanPlantOutsideSeason() then
		local fruitType = self.sowingMachineSpec.workAreaParameters.seedsFruitType
		-- TODO 25 no canFruitBePlanted() in growthSystem
		if false and fruitType ~= nil and not g_currentMission.growthSystem:canFruitBePlanted(fruitType) then
			self:debug("Fruit can't be planted in this season!")
			self.vehicle:stopCurrentAIJob(AIMessageErrorWrongSeason.new())
		end
	end

end

function SowingMachineController:onFinished()
    self.implement:setIsTurnedOn(false)
end

--- While Courseplay is driving and sowing was disabled by the user, the machine stays turned off.
--- Without this override, TurnOnVehicle:getCanAIImplementContinueWork() fails for machines that
--- require turning on but are turned off, so the driver would lower the implement and then just
--- stand still, waiting forever (#989).
local function getAIRequiresTurnOn(implement, superFunc, ...)
	--- Only for cultivators with a seeder unit configuration, like the Horsch Finer 6 SL.
	--- The structural check must not go through the setting's getIsDisabled() here, as that
	--- calls isOptionalSowingMachineSettingVisible(), which in turn calls getAIRequiresTurnOn(),
	--- resulting in an infinite recursion.
	if implement.spec_sowingMachine ~= nil and
			SpecializationUtil.hasSpecialization(Cultivator, implement.specializations) then
		local rootVehicle = implement.rootVehicle
		if rootVehicle ~= nil and rootVehicle.getIsCpActive and rootVehicle:getIsCpActive() then
			local setting = rootVehicle:getCpSettings().optionalSowingMachineEnabled
			if not setting:getValue() then
				return false
			end
		end
	end
	return superFunc(implement, ...)
end
TurnOnVehicle.getAIRequiresTurnOn = Utils.overwrittenFunction(
	TurnOnVehicle.getAIRequiresTurnOn, getAIRequiresTurnOn)

-------------------------
--- Refill handling
-------------------------

function SowingMachineController:needsRefilling()
	if not self.settings.optionalSowingMachineEnabled:getIsDisabled() and
			not self.settings.optionalSowingMachineEnabled:getValue() then
		--- Sowing was disabled by the user, so no seeds are needed (#989).
		return false
	end
	if self.implement:getFillUnitCapacity(self.sowingMachineSpec.fillUnitIndex) == 0 then
		--- Sowing machines without a real seed tank (capacity 0), like the seeder unit
		--- of the Horsch Finer 6 SL, don't consume seeds (see getSowingMachineCanConsume)
		--- and therefore never need refilling (#989).
		return false
	end
	if not g_currentMission.missionInfo.helperBuySeeds then
		if self.implement:getFillUnitFillLevel(self.sowingMachineSpec.fillUnitIndex) <= 0 then
			return ImplementController.needsRefilling(self)
		end
	end
	return false
end
