--- Vehicle specialization for the "bale windrows" job: makes the job available when a baler is attached
--- and holds the per-vehicle job instance (for savegame + the in-game AI menu).
local modName = CpAIBaleWindrows and CpAIBaleWindrows.MOD_NAME -- for reload

---@class CpAIBaleWindrows
CpAIBaleWindrows = {}

CpAIBaleWindrows.MOD_NAME = g_currentModName or modName
CpAIBaleWindrows.NAME = ".cpAIBaleWindrows"
CpAIBaleWindrows.SPEC_NAME = CpAIBaleWindrows.MOD_NAME .. CpAIBaleWindrows.NAME
CpAIBaleWindrows.KEY = "." .. CpAIBaleWindrows.MOD_NAME .. CpAIBaleWindrows.NAME

function CpAIBaleWindrows.initSpecialization()
    local schema = Vehicle.xmlSchemaSavegame
    local key = "vehicles.vehicle(?)" .. CpAIBaleWindrows.KEY
    CpJobParameters.registerXmlSchema(schema, key .. ".cpJob")
end

function CpAIBaleWindrows.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(CpAIWorker, specializations)
end

function CpAIBaleWindrows.register(typeManager, typeName, specializations)
    if CpAIBaleWindrows.prerequisitesPresent(specializations) then
        typeManager:addSpecialization(typeName, CpAIBaleWindrows.SPEC_NAME)
    end
end

function CpAIBaleWindrows.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, 'onLoad', CpAIBaleWindrows)
    SpecializationUtil.registerEventListener(vehicleType, 'onLoadFinished', CpAIBaleWindrows)
    SpecializationUtil.registerEventListener(vehicleType, 'onReadStream', CpAIBaleWindrows)
    SpecializationUtil.registerEventListener(vehicleType, 'onWriteStream', CpAIBaleWindrows)
end

function CpAIBaleWindrows.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getCanStartCpBaleWindrows", CpAIBaleWindrows.getCanStartCpBaleWindrows)
    SpecializationUtil.registerFunction(vehicleType, "getCpBaleWindrowsJobParameters", CpAIBaleWindrows.getCpBaleWindrowsJobParameters)
    SpecializationUtil.registerFunction(vehicleType, "getCpBaleWindrowsJob", CpAIBaleWindrows.getCpBaleWindrowsJob)
    SpecializationUtil.registerFunction(vehicleType, "applyCpBaleWindrowsJobParameters", CpAIBaleWindrows.applyCpBaleWindrowsJobParameters)
end

------------------------------------------------------------------------------------------------------------------------
--- Event listeners
------------------------------------------------------------------------------------------------------------------------
function CpAIBaleWindrows:onLoad(savegame)
    self.spec_cpAIBaleWindrows = self["spec_" .. CpAIBaleWindrows.SPEC_NAME]
    local spec = self.spec_cpAIBaleWindrows
    spec.cpJob = g_currentMission.aiJobTypeManager:createJob(AIJobType.BALE_WINDROWS_CP)
    spec.cpJob:setVehicle(self, true)
end

function CpAIBaleWindrows:onLoadFinished(savegame)
    local spec = self.spec_cpAIBaleWindrows
    if savegame ~= nil then
        spec.cpJob:getCpJobParameters():loadFromXMLFile(savegame.xmlFile, savegame.key .. CpAIBaleWindrows.KEY .. ".cpJob")
    end
end

function CpAIBaleWindrows:saveToXMLFile(xmlFile, baseKey, usedModNames)
    local spec = self.spec_cpAIBaleWindrows
    spec.cpJob:getCpJobParameters():saveToXMLFile(xmlFile, baseKey .. ".cpJob")
end

function CpAIBaleWindrows:onReadStream(streamId, connection)
    local spec = self.spec_cpAIBaleWindrows
    spec.cpJob:readStream(streamId, connection)
end

function CpAIBaleWindrows:onWriteStream(streamId, connection)
    local spec = self.spec_cpAIBaleWindrows
    spec.cpJob:writeStream(streamId, connection)
end

function CpAIBaleWindrows:getCpBaleWindrowsJobParameters()
    local spec = self.spec_cpAIBaleWindrows
    return spec.cpJob:getCpJobParameters()
end

function CpAIBaleWindrows:getCpBaleWindrowsJob()
    local spec = self.spec_cpAIBaleWindrows
    return spec.cpJob
end

function CpAIBaleWindrows:applyCpBaleWindrowsJobParameters(job)
    local spec = self.spec_cpAIBaleWindrows
    spec.cpJob:getCpJobParameters():validateSettings()
    spec.cpJob:copyFrom(job)
end

--- Available when a baler (that makes bales from a windrow) is attached. This is the complement of the
--- bale finder, which collects finished bales and explicitly excludes balers.
function CpAIBaleWindrows:getCanStartCpBaleWindrows()
    return AIUtil.hasChildVehicleWithSpecialization(self, Baler)
end
