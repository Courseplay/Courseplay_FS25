
local modName = CpAISiloLoaderWorker and CpAISiloLoaderWorker.MOD_NAME -- for reload

--- Specialization for the silo loader job
--- Used for shovel loader and big silo loader, like the Ropa NarwaRo.
---@class CpAISiloLoaderWorker
CpAISiloLoaderWorker = {}

CpAISiloLoaderWorker.startText = g_i18n:getText("CP_fieldWorkJobParameters_startAt_siloLoader")

CpAISiloLoaderWorker.MOD_NAME = g_currentModName or modName
CpAISiloLoaderWorker.NAME = ".cpAISiloLoaderWorker"
CpAISiloLoaderWorker.SPEC_NAME = CpAISiloLoaderWorker.MOD_NAME .. CpAISiloLoaderWorker.NAME
CpAISiloLoaderWorker.KEY = "." .. CpAISiloLoaderWorker.MOD_NAME .. CpAISiloLoaderWorker.NAME

function CpAISiloLoaderWorker.initSpecialization()
    local schema = Vehicle.xmlSchemaSavegame
    local key = "vehicles.vehicle(?)" .. CpAISiloLoaderWorker.KEY
    CpJobParameters.registerXmlSchema(schema, key..".cpJob")
end

function CpAISiloLoaderWorker.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(CpAIWorker, specializations) 
end

function CpAISiloLoaderWorker.register(typeManager,typeName,specializations)
	if CpAISiloLoaderWorker.prerequisitesPresent(specializations) then
		typeManager:addSpecialization(typeName, CpAISiloLoaderWorker.SPEC_NAME)
	end
end

function CpAISiloLoaderWorker.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, 'onLoad', CpAISiloLoaderWorker)
    SpecializationUtil.registerEventListener(vehicleType, 'onUpdate', CpAISiloLoaderWorker)
    SpecializationUtil.registerEventListener(vehicleType, 'onLoadFinished', CpAISiloLoaderWorker)
    SpecializationUtil.registerEventListener(vehicleType, 'onReadStream', CpAISiloLoaderWorker)
    SpecializationUtil.registerEventListener(vehicleType, 'onWriteStream', CpAISiloLoaderWorker)
end

function CpAISiloLoaderWorker.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getCanStartCpSiloLoaderWorker", CpAISiloLoaderWorker.getCanStartCpSiloLoaderWorker)
    SpecializationUtil.registerFunction(vehicleType, "getCpSiloLoaderWorkerJobParameters", CpAISiloLoaderWorker.getCpSiloLoaderWorkerJobParameters)
    
    SpecializationUtil.registerFunction(vehicleType, "applyCpSiloLoaderWorkerJobParameters", CpAISiloLoaderWorker.applyCpSiloLoaderWorkerJobParameters)
    SpecializationUtil.registerFunction(vehicleType, "getCpSiloLoaderWorkerJob", CpAISiloLoaderWorker.getCpSiloLoaderWorkerJob)
end

function CpAISiloLoaderWorker.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCanStartCp', CpAISiloLoaderWorker.getCanStartCp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCpStartableJob', CpAISiloLoaderWorker.getCpStartableJob)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'startCpAtFirstWp', CpAISiloLoaderWorker.startCpAtFirstWp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'startCpAtLastWp', CpAISiloLoaderWorker.startCpAtLastWp)
end
------------------------------------------------------------------------------------------------------------------------
--- Event listeners
---------------------------------------------------------------------------------------------------------------------------
function CpAISiloLoaderWorker:onLoad(savegame)
	--- Register the spec: spec_CpAIBunkerSiloWorker
    self.spec_cpAISiloLoaderWorker = self["spec_" .. CpAISiloLoaderWorker.SPEC_NAME]
    local spec = self.spec_cpAISiloLoaderWorker
    --- This job is for starting the driving with a key bind or the mini gui.
    spec.cpJob = g_currentMission.aiJobTypeManager:createJob(AIJobType.SILO_LOADER_CP)
    spec.cpJob:setVehicle(self, true)
end


function CpAISiloLoaderWorker:onLoadFinished(savegame)
    local spec = self.spec_cpAISiloLoaderWorker
    if savegame ~= nil then 
        spec.cpJob:loadFromXMLFile(savegame.xmlFile, savegame.key.. CpAISiloLoaderWorker.KEY..".cpJob")
    end
end

function CpAISiloLoaderWorker:saveToXMLFile(xmlFile, baseKey, usedModNames)
    local spec = self.spec_cpAISiloLoaderWorker
    spec.cpJob:saveToXMLFile(xmlFile, baseKey.. ".cpJob")
end

function CpAISiloLoaderWorker:onReadStream(streamId, connection)
    local spec = self.spec_cpAISiloLoaderWorker
    spec.cpJob:readStream(streamId, connection)
end

function CpAISiloLoaderWorker:onWriteStream(streamId, connection)
    local spec = self.spec_cpAISiloLoaderWorker
    spec.cpJob:writeStream(streamId, connection)
end

function CpAISiloLoaderWorker:onUpdate(dt)
    local spec = self.spec_cpAISiloLoaderWorker
end

function CpAISiloLoaderWorker:getCanStartCpSiloLoaderWorker()
	return not self:getCanStartCpFieldWork() 
        and not self:getCanStartCpBaleFinder() 
        and not self:getCanStartCpCombineUnloader() 
        and AIUtil.hasChildVehicleWithSpecialization(self, Shovel) 
end

function CpAISiloLoaderWorker:getCanStartCp(superFunc)
    return superFunc(self) or self:getCanStartCpSiloLoaderWorker()
end

function CpAISiloLoaderWorker:getCpStartableJob(superFunc, isStartedByHud)
    local spec = self.spec_cpAISiloLoaderWorker
    if isStartedByHud and self:cpIsHudSiloLoaderJobSelected() then 
        return self:getCanStartCpSiloLoaderWorker() and spec.cpJob
    end
	return superFunc(self, isStartedByHud) or not isStartedByHud and self:getCanStartCpSiloLoaderWorker() and spec.cpJob
end

function CpAISiloLoaderWorker:getCpSiloLoaderWorkerJobParameters()
    local spec = self.spec_cpAISiloLoaderWorker
    return spec.cpJob:getCpJobParameters()
end

function CpAISiloLoaderWorker:applyCpSiloLoaderWorkerJobParameters(job)
    local spec = self.spec_cpAISiloLoaderWorker
    spec.cpJob:getCpJobParameters():validateSettings()
    spec.cpJob:copyFrom(job)
end

function CpAISiloLoaderWorker:getCpSiloLoaderWorkerJob()
    local spec = self.spec_cpAISiloLoaderWorker
    return spec.cpJob
end


--- Starts the cp driver at the first waypoint.
function CpAISiloLoaderWorker:startCpAtFirstWp(superFunc, ...)
    if not superFunc(self, ...) then 
        if self:getCanStartCpSiloLoaderWorker() then 
            local spec = self.spec_cpAISiloLoaderWorker
            spec.cpJob:applyCurrentState(self, g_currentMission, g_currentMission.playerSystem:getLocalPlayer().farmId, true)
            spec.cpJob:setValues()
            local success = spec.cpJob:validate(false)
            if success then
                g_client:getServerConnection():sendEvent(AIJobStartRequestEvent.new(spec.cpJob, self:getOwnerFarmId()))
                return true
            end
        end
    else 
        return true
    end
end

--- Starts the cp driver at the last driven waypoint.
function CpAISiloLoaderWorker:startCpAtLastWp(superFunc, ...)
    if not superFunc(self, ...) then 
        if self:getCanStartCpSiloLoaderWorker() then 
            local spec = self.spec_cpAISiloLoaderWorker
            spec.cpJob:applyCurrentState(self, g_currentMission, g_currentMission.playerSystem:getLocalPlayer().farmId, true)
            spec.cpJob:setValues()
            local success = spec.cpJob:validate(false)
            if success then
                g_client:getServerConnection():sendEvent(AIJobStartRequestEvent.new(spec.cpJob, self:getOwnerFarmId()))
                return true
            end
        end
    else 
        return true
    end
end
