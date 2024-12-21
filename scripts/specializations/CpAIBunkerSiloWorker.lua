--- This spec is only for overwriting giants function of the AIFieldWorker.
local modName = CpAIBunkerSiloWorker and CpAIBunkerSiloWorker.MOD_NAME -- for reload

---@class CpAIBunkerSiloWorker
CpAIBunkerSiloWorker = {}

CpAIBunkerSiloWorker.startText = g_i18n:getText("CP_fieldWorkJobParameters_startAt_bunkerSilo")

CpAIBunkerSiloWorker.MOD_NAME = g_currentModName or modName
CpAIBunkerSiloWorker.NAME = ".cpAIBunkerSiloWorker"
CpAIBunkerSiloWorker.SPEC_NAME = CpAIBunkerSiloWorker.MOD_NAME .. CpAIBunkerSiloWorker.NAME
CpAIBunkerSiloWorker.KEY = "."..CpAIBunkerSiloWorker.MOD_NAME..CpAIBunkerSiloWorker.NAME

function CpAIBunkerSiloWorker.initSpecialization()
    local schema = Vehicle.xmlSchemaSavegame
    local key = "vehicles.vehicle(?)" .. CpAIBunkerSiloWorker.KEY
    CpJobParameters.registerXmlSchema(schema, key..".cpJob")
end

function CpAIBunkerSiloWorker.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(CpAIWorker, specializations) 
end

function CpAIBunkerSiloWorker.register(typeManager,typeName,specializations)
	if CpAIBunkerSiloWorker.prerequisitesPresent(specializations) then
		typeManager:addSpecialization(typeName, CpAIBunkerSiloWorker.SPEC_NAME)
	end
end

function CpAIBunkerSiloWorker.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, 'onLoad', CpAIBunkerSiloWorker)
    SpecializationUtil.registerEventListener(vehicleType, 'onUpdate', CpAIBunkerSiloWorker)
    SpecializationUtil.registerEventListener(vehicleType, 'onLoadFinished', CpAIBunkerSiloWorker)
    SpecializationUtil.registerEventListener(vehicleType, 'onReadStream', CpAIBunkerSiloWorker)
    SpecializationUtil.registerEventListener(vehicleType, 'onWriteStream', CpAIBunkerSiloWorker)
end

function CpAIBunkerSiloWorker.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getCanStartCpBunkerSiloWorker", CpAIBunkerSiloWorker.getCanStartCpBunkerSiloWorker)
    SpecializationUtil.registerFunction(vehicleType, "getCpBunkerSiloWorkerJobParameters", CpAIBunkerSiloWorker.getCpBunkerSiloWorkerJobParameters)
    
    SpecializationUtil.registerFunction(vehicleType, "applyCpBunkerSiloWorkerJobParameters", CpAIBunkerSiloWorker.applyCpBunkerSiloWorkerJobParameters)
    SpecializationUtil.registerFunction(vehicleType, "getCpBunkerSiloWorkerJob", CpAIBunkerSiloWorker.getCpBunkerSiloWorkerJob)
end

function CpAIBunkerSiloWorker.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCanStartCp', CpAIBunkerSiloWorker.getCanStartCp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCpStartableJob', CpAIBunkerSiloWorker.getCpStartableJob)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'startCpAtFirstWp', CpAIBunkerSiloWorker.startCpAtFirstWp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'startCpAtLastWp', CpAIBunkerSiloWorker.startCpAtLastWp)
end
------------------------------------------------------------------------------------------------------------------------
--- Event listeners
---------------------------------------------------------------------------------------------------------------------------
function CpAIBunkerSiloWorker:onLoad(savegame)
	--- Register the spec: spec_CpAIBunkerSiloWorker
    self.spec_cpAIBunkerSiloWorker = self["spec_" .. CpAIBunkerSiloWorker.SPEC_NAME]
    local spec = self.spec_cpAIBunkerSiloWorker
    --- This job is for starting the driving with a key bind or the mini gui.
    spec.cpJob = g_currentMission.aiJobTypeManager:createJob(AIJobType.BUNKER_SILO_CP)
    spec.cpJob:setVehicle(self, true)
end


function CpAIBunkerSiloWorker:onLoadFinished(savegame)
    local spec = self.spec_cpAIBunkerSiloWorker
    if savegame ~= nil then 
        spec.cpJob:loadFromXMLFile(savegame.xmlFile, savegame.key.. CpAIBunkerSiloWorker.KEY..".cpJob")
    end
end

function CpAIBunkerSiloWorker:saveToXMLFile(xmlFile, baseKey, usedModNames)
    local spec = self.spec_cpAIBunkerSiloWorker
    spec.cpJob:saveToXMLFile(xmlFile, baseKey.. ".cpJob")
end

function CpAIBunkerSiloWorker:onReadStream(streamId, connection)
    local spec = self.spec_cpAIBunkerSiloWorker
    spec.cpJob:readStream(streamId, connection)
end

function CpAIBunkerSiloWorker:onWriteStream(streamId, connection)
    local spec = self.spec_cpAIBunkerSiloWorker
    spec.cpJob:writeStream(streamId, connection)
end

function CpAIBunkerSiloWorker:onUpdate(dt)
    local spec = self.spec_cpAIBunkerSiloWorker

end

--- Is the bunker silo allowed?
function CpAIBunkerSiloWorker:getCanStartCpBunkerSiloWorker()
    if AIUtil.hasChildVehicleWithSpecialization(self, Shovel) then 
        return false
    end
	return not self:getCanStartCpFieldWork() 
        and not self:getCanStartCpBaleFinder() 
        and not self:getCanStartCpCombineUnloader()
        and not self:getCanStartCpSiloLoaderWorker()
end

function CpAIBunkerSiloWorker:getCanStartCp(superFunc)
    return superFunc(self) or self:getCanStartCpBunkerSiloWorker()
end

function CpAIBunkerSiloWorker:getCpStartableJob(superFunc, isStartedByHud)
    local spec = self.spec_cpAIBunkerSiloWorker
    if isStartedByHud and self:cpIsHudBunkerSiloJobSelected() then 
        return self:getCanStartCpBunkerSiloWorker() and spec.cpJob
    end
	return superFunc(self, isStartedByHud) or not isStartedByHud and self:getCanStartCpBunkerSiloWorker() and spec.cpJob
end

function CpAIBunkerSiloWorker:getCpBunkerSiloWorkerJobParameters()
    local spec = self.spec_cpAIBunkerSiloWorker
    return spec.cpJob:getCpJobParameters()
end

function CpAIBunkerSiloWorker:applyCpBunkerSiloWorkerJobParameters(job)
    local spec = self.spec_cpAIBunkerSiloWorker
    spec.cpJob:getCpJobParameters():validateSettings()
    spec.cpJob:copyFrom(job)
end

function CpAIBunkerSiloWorker:getCpBunkerSiloWorkerJob()
    local spec = self.spec_cpAIBunkerSiloWorker
    return spec.cpJob
end


--- Starts the cp driver at the first waypoint.
function CpAIBunkerSiloWorker:startCpAtFirstWp(superFunc, ...)
    if not superFunc(self, ...) then 
        if self:getCanStartCpBunkerSiloWorker() then 
            local spec = self.spec_cpAIBunkerSiloWorker
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
function CpAIBunkerSiloWorker:startCpAtLastWp(superFunc, ...)
    if not superFunc(self, ...) then 
        if self:getCanStartCpBunkerSiloWorker() then 
            local spec = self.spec_cpAIBunkerSiloWorker
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
