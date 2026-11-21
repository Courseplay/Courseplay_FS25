--- Vehicle specialization for the "bale windrows" job: makes the job available when a baler is attached.
--- Minimal by design -- the job itself is created by the AI menu via getIsAvailableForVehicle; this spec
--- only has to answer "can this vehicle run the bale-windrows job?" (a baler is attached).
local modName = CpAIBaleWindrows and CpAIBaleWindrows.MOD_NAME -- for reload

---@class CpAIBaleWindrows
CpAIBaleWindrows = {}

CpAIBaleWindrows.MOD_NAME = g_currentModName or modName
CpAIBaleWindrows.NAME = ".cpAIBaleWindrows"
CpAIBaleWindrows.SPEC_NAME = CpAIBaleWindrows.MOD_NAME .. CpAIBaleWindrows.NAME

function CpAIBaleWindrows.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(CpAIWorker, specializations)
end

function CpAIBaleWindrows.register(typeManager, typeName, specializations)
    if CpAIBaleWindrows.prerequisitesPresent(specializations) then
        typeManager:addSpecialization(typeName, CpAIBaleWindrows.SPEC_NAME)
    end
end

function CpAIBaleWindrows.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getCanStartCpBaleWindrows", CpAIBaleWindrows.getCanStartCpBaleWindrows)
end

--- Available when a baler (that makes bales from a windrow) is attached. This is the complement of the
--- bale finder, which collects finished bales and explicitly excludes balers.
function CpAIBaleWindrows:getCanStartCpBaleWindrows()
    return AIUtil.hasChildVehicleWithSpecialization(self, Baler)
end
