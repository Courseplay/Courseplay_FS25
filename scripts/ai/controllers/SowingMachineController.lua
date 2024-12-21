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

-------------------------
--- Refill handling
-------------------------

function SowingMachineController:needsRefilling()
	if not g_currentMission.missionInfo.helperBuySeeds then
		if self.implement:getFillUnitFillLevel(self.sowingMachineSpec.fillUnitIndex) <= 0 then 
			return ImplementController.needsRefilling(self)
		end
	end
	return false
end