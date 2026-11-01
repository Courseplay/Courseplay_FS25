--- Enables the user to activate/deactivate the fertilizer use for cultivators with a setting.
--- Also stops the driver, when the setting is active and the fertilizer tank is empty.
---@class FertilizingCultivatorController : ImplementController
FertilizingCultivatorController = CpObject(ImplementController)

function FertilizingCultivatorController:init(vehicle, cultivator)
	self.cultivator = cultivator
    ImplementController.init(self, vehicle, self.cultivator)
end

local function processCultivatorArea(cultivator,superFunc,...)
	local rootVehicle = cultivator.rootVehicle
	if not rootVehicle.getIsCpActive or not rootVehicle:getIsCpActive() then 
		return superFunc(cultivator, ...)
	end
	local specSpray = cultivator.spec_sprayer
	local sprayerParams = specSpray.workAreaParameters
	local fertilizingEnabled = rootVehicle:getCpSettings().sowingMachineFertilizerEnabled:getValue()
	if not fertilizingEnabled then 
		sprayerParams.sprayFillLevel = 0
        sprayerParams.lastAIHasSprayed = nil
	elseif ImplementUtil.isSprayerEmpty(cultivator, rootVehicle:getCpSettings()) then
		CpUtil.debugImplement(CpDebug.DBG_IMPLEMENTS, cultivator, "Stopped Cp, as fertilizer for cultivator is empty.")
		rootVehicle:stopCurrentAIJob(AIMessageErrorOutOfFill.new())
	end
	return superFunc(cultivator, ...)
end
FertilizingCultivator.processCultivatorArea = Utils.overwrittenFunction(
	FertilizingCultivator.processCultivatorArea,processCultivatorArea)

