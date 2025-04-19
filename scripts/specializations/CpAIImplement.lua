--- This spec is only for overwriting giants function of the AIImplement.
local modName = CpAIImplement and CpAIImplement.MOD_NAME -- for reload

---@class CpAIImplement
CpAIImplement = {}
CpAIImplement.MOD_NAME = g_currentModName or modName
CpAIImplement.NAME = ".cpAIImplement"
CpAIImplement.SPEC_NAME = CpAIImplement.MOD_NAME .. CpAIImplement.NAME
CpAIImplement.KEY = "."..CpAIImplement.MOD_NAME..CpAIImplement.NAME
function CpAIImplement.initSpecialization()
    local schema = Vehicle.xmlSchemaSavegame
    local key = "vehicles.vehicle(?)" .. CpAIImplement.KEY
end

function CpAIImplement.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(AIImplement, specializations) 
end

function CpAIImplement.register(typeManager,typeName,specializations)
	if CpAIImplement.prerequisitesPresent(specializations) then
		typeManager:addSpecialization(typeName, CpAIImplement.SPEC_NAME)
	end
end

function CpAIImplement.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, 'onLoad', CpAIImplement)
    SpecializationUtil.registerEventListener(vehicleType, "onAIImplementStart", CpAIImplement)
    SpecializationUtil.registerEventListener(vehicleType, "onAIImplementActive", CpAIImplement)
    SpecializationUtil.registerEventListener(vehicleType, "onAIImplementEnd", CpAIImplement)
    SpecializationUtil.registerEventListener(vehicleType, "onAIImplementPrepareForWork", CpAIImplement)
    SpecializationUtil.registerEventListener(vehicleType, "onAIImplementStartLine", CpAIImplement)
    SpecializationUtil.registerEventListener(vehicleType, "onAIImplementEndLine", CpAIImplement)
    SpecializationUtil.registerEventListener(vehicleType, "onAIImplementStartTurn", CpAIImplement)
    SpecializationUtil.registerEventListener(vehicleType, "onAIImplementTurnProgress", CpAIImplement)
    SpecializationUtil.registerEventListener(vehicleType, "onAIImplementEndTurn", CpAIImplement)
    SpecializationUtil.registerEventListener(vehicleType, "onAIImplementSideOffsetChanged", CpAIImplement)
    SpecializationUtil.registerEventListener(vehicleType, "onAIImplementBlock", CpAIImplement)
    SpecializationUtil.registerEventListener(vehicleType, "onAIImplementContinue", CpAIImplement)
    SpecializationUtil.registerEventListener(vehicleType, "onAIImplementPrepareForTransport", CpAIImplement)
    SpecializationUtil.registerEventListener(vehicleType, "onAIImplementJobVehicleBlock", CpAIImplement)
    SpecializationUtil.registerEventListener(vehicleType, "onAIImplementJobVehicleContinue", CpAIImplement)
end

function CpAIImplement.registerFunctions(vehicleType)

end

function CpAIImplement.registerOverwrittenFunctions(vehicleType)
    
end

function CpAIImplement.registerEvents(vehicleType)
  
end

function CpAIImplement:onLoad(savegame)
    self.spec_cpAIImplement = self["spec_" .. CpAIImplement.SPEC_NAME]
    local spec = self.spec_cpAIImplement
end

function CpAIImplement:onAIImplementStart()
    self.spec_cpAIImplement = self["spec_" .. CpAIImplement.SPEC_NAME]
    local spec = self.spec_cpAIImplement

    CpUtil.info("onAIImplementStart()")
end

function CpAIImplement:onAIImplementActive()
    self.spec_cpAIImplement = self["spec_" .. CpAIImplement.SPEC_NAME]
    local spec = self.spec_cpAIImplement

    -- CpUtil.info("onAIImplementActive()")
end

function CpAIImplement:onAIImplementEnd()
    self.spec_cpAIImplement = self["spec_" .. CpAIImplement.SPEC_NAME]
    local spec = self.spec_cpAIImplement

    CpUtil.info("onAIImplementEnd()")
end

function CpAIImplement:onAIImplementPrepareForWork()
    self.spec_cpAIImplement = self["spec_" .. CpAIImplement.SPEC_NAME]
    local spec = self.spec_cpAIImplement

    CpUtil.info("onAIImplementPrepareForWork()")
end

function CpAIImplement:onAIImplementStartLine()
    self.spec_cpAIImplement = self["spec_" .. CpAIImplement.SPEC_NAME]
    local spec = self.spec_cpAIImplement

    CpUtil.info("onAIImplementStartLine()")
end

function CpAIImplement:onAIImplementEndLine()
    self.spec_cpAIImplement = self["spec_" .. CpAIImplement.SPEC_NAME]
    local spec = self.spec_cpAIImplement

    CpUtil.info("onAIImplementEndLine()")
end

function CpAIImplement:onAIImplementStartTurn()
    self.spec_cpAIImplement = self["spec_" .. CpAIImplement.SPEC_NAME]
    local spec = self.spec_cpAIImplement

    CpUtil.info("onAIImplementStartTurn()")
end

function CpAIImplement:onAIImplementTurnProgress()
    self.spec_cpAIImplement = self["spec_" .. CpAIImplement.SPEC_NAME]
    local spec = self.spec_cpAIImplement

    -- CpUtil.info("onAIImplementTurnProgress()")
end

function CpAIImplement:onAIImplementEndTurn()
    self.spec_cpAIImplement = self["spec_" .. CpAIImplement.SPEC_NAME]
    local spec = self.spec_cpAIImplement

    CpUtil.info("onAIImplementEndTurn()")
end

function CpAIImplement:onAIImplementSideOffsetChanged()
    self.spec_cpAIImplement = self["spec_" .. CpAIImplement.SPEC_NAME]
    local spec = self.spec_cpAIImplement

    CpUtil.info("onAIImplementSideOffsetChanged()")
end

function CpAIImplement:onAIImplementBlock()
    self.spec_cpAIImplement = self["spec_" .. CpAIImplement.SPEC_NAME]
    local spec = self.spec_cpAIImplement

    CpUtil.info("onAIImplementBlock()")
end

function CpAIImplement:onAIImplementContinue()
    self.spec_cpAIImplement = self["spec_" .. CpAIImplement.SPEC_NAME]
    local spec = self.spec_cpAIImplement

    CpUtil.info("onAIImplementContinue()")
end

function CpAIImplement:onAIImplementPrepareForTransport()
    self.spec_cpAIImplement = self["spec_" .. CpAIImplement.SPEC_NAME]
    local spec = self.spec_cpAIImplement

    CpUtil.info("onAIImplementPrepareForTransport()")
end

function CpAIImplement:onAIImplementJobVehicleBlock()
    self.spec_cpAIImplement = self["spec_" .. CpAIImplement.SPEC_NAME]
    local spec = self.spec_cpAIImplement

    CpUtil.info("onAIImplementJobVehicleBlock()")
end

function CpAIImplement:onAIImplementJobVehicleContinue()
    self.spec_cpAIImplement = self["spec_" .. CpAIImplement.SPEC_NAME]
    local spec = self.spec_cpAIImplement

    CpUtil.info("onAIImplementJobVehicleContinue()")
end