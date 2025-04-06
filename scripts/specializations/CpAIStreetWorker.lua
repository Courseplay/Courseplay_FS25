--- This spec is only for overwriting giants function of the AIFieldWorker.
local modName = CpAIStreetWorker and CpAIStreetWorker.MOD_NAME -- for reload

---@class CpAIStreetWorker
CpAIStreetWorker = {}

CpAIStreetWorker.startText = g_i18n:getText("CP_fieldWorkJobParameters_startAt_street")

CpAIStreetWorker.MOD_NAME = g_currentModName or modName
CpAIStreetWorker.NAME = ".cpAIStreetWorker"
CpAIStreetWorker.SPEC_NAME = CpAIStreetWorker.MOD_NAME .. CpAIStreetWorker.NAME
CpAIStreetWorker.KEY = "."..CpAIStreetWorker.MOD_NAME..CpAIStreetWorker.NAME

function CpAIStreetWorker.initSpecialization()
    local schema = Vehicle.xmlSchemaSavegame
    local key = "vehicles.vehicle(?)" .. CpAIStreetWorker.KEY
    CpJobParameters.registerXmlSchema(schema, key..".cpJob")
end

function CpAIStreetWorker.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(CpAIWorker, specializations) 
end

function CpAIStreetWorker.register(typeManager,typeName,specializations)
	if CpAIStreetWorker.prerequisitesPresent(specializations) then
		typeManager:addSpecialization(typeName, CpAIStreetWorker.SPEC_NAME)
	end
end

function CpAIStreetWorker.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, 'onLoad', CpAIStreetWorker)
    SpecializationUtil.registerEventListener(vehicleType, 'onLoadFinished', CpAIStreetWorker)
    SpecializationUtil.registerEventListener(vehicleType, 'onReadStream', CpAIStreetWorker)
    SpecializationUtil.registerEventListener(vehicleType, 'onWriteStream', CpAIStreetWorker)
    SpecializationUtil.registerEventListener(vehicleType, 'onUpdate', CpAIStreetWorker)
end

function CpAIStreetWorker.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getCanStartCpStreetWorker", CpAIStreetWorker.getCanStartCpStreetWorker)
    SpecializationUtil.registerFunction(vehicleType, "getCpStreetWorkerJobParameters", CpAIStreetWorker.getCpStreetWorkerJobParameters)
    SpecializationUtil.registerFunction(vehicleType, "getCpStreetWorkerJob", CpAIStreetWorker.getCpStreetWorkerJob)
    SpecializationUtil.registerFunction(vehicleType, "applyCpStreetWorkerJobParameters", CpAIStreetWorker.applyCpStreetWorkerJobParameters)

end

function CpAIStreetWorker.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCanStartCp', CpAIStreetWorker.getCanStartCp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCpStartableJob', CpAIStreetWorker.getCpStartableJob)

    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'startCpAtFirstWp', CpAIStreetWorker.startCpAtFirstWp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'startCpAtLastWp', CpAIStreetWorker.startCpAtLastWp)
end

function CpAIStreetWorker.registerEvents(vehicleType)
    -- SpecializationUtil.registerEvent(vehicleType, "onCpWrapTypeSettingChanged")   
end

------------------------------------------------------------------------------------------------------------------------
--- Event listeners
---------------------------------------------------------------------------------------------------------------------------
function CpAIStreetWorker:onLoad(savegame)
	--- Register the spec: spec_cpAIStreetWorker
    self.spec_cpAIStreetWorker = self["spec_" .. CpAIStreetWorker.SPEC_NAME]
    local spec = self.spec_cpAIStreetWorker
    --- This job is for starting the driving with a key bind or the mini gui.
    spec.cpJob = g_currentMission.aiJobTypeManager:createJob(AIJobType.STREET_WORKER_CP)
    spec.cpJob:setVehicle(self, true)
end

function CpAIStreetWorker:onLoadFinished(savegame)
    local spec = self.spec_cpAIStreetWorker
    if savegame ~= nil then 
        spec.cpJob:loadFromXMLFile(savegame.xmlFile, savegame.key.. CpAIStreetWorker.KEY..".cpJob")
    end
end

function CpAIStreetWorker:onUpdate()
    local spec = self.spec_cpAIStreetWorker
    if not spec.finishedFirstUpdate then
        spec.cpJob:getCpJobParameters():validateSettings()
        spec.cpJob:getCpJobParameters():resetToLoadedValue()
        spec.finishedFirstUpdate = true
    end
end

function CpAIStreetWorker:saveToXMLFile(xmlFile, baseKey, usedModNames)
    local spec = self.spec_cpAIStreetWorker
    spec.cpJob:saveToXMLFile(xmlFile, baseKey.. ".cpJob")
end

function CpAIStreetWorker:onReadStream(streamId, connection)
    local spec = self.spec_cpAIStreetWorker
    spec.cpJob:readStream(streamId, connection)
end

function CpAIStreetWorker:onWriteStream(streamId, connection)
    local spec = self.spec_cpAIStreetWorker
    spec.cpJob:writeStream(streamId, connection)
end

function CpAIStreetWorker:getCpStreetWorkerJobParameters()
    local spec = self.spec_cpAIStreetWorker
    return spec.cpJob:getCpJobParameters() 
end

function CpAIStreetWorker:getCpStreetWorkerJob()
    local spec = self.spec_cpAIStreetWorker
    return spec.cpJob
end


function CpAIStreetWorker:applyCpStreetWorkerJobParameters(job)
    local spec = self.spec_cpAIStreetWorker
    spec.cpJob:getCpJobParameters():validateSettings()
    spec.cpJob:copyFrom(job)
end

--- Is the Street job allowed?
function CpAIStreetWorker:getCanStartCpStreetWorker()
	return true
end

function CpAIStreetWorker:getCanStartCp(superFunc)
    return superFunc(self) or self:getCanStartCpStreetWorker()
end

--- Only use the bale finder, if the cp field work job is not possible.
function CpAIStreetWorker:getCpStartableJob(superFunc, isStartedByHud)
    local spec = self.spec_cpAIStreetWorker
    if isStartedByHud and self:cpIsHudStreetJobSelected() then 
        return self:getCanStartCpStreetWorker() and spec.cpJob
    end
	return superFunc(self, isStartedByHud) or not isStartedByHud and self:getCanStartCpStreetWorker() and spec.cpJob
end

--- Starts the cp driver at the first waypoint.
function CpAIStreetWorker:startCpAtFirstWp(superFunc)
    if not superFunc(self) then 
        if self:getCanStartCpStreetWorker() then 
            local spec = self.spec_cpAIStreetWorker
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
function CpAIStreetWorker:startCpAtLastWp(superFunc)
    CpAIStreetWorker.startCpAtFirstWp(self, superFunc)
end

function CpAIStreetWorker:onCpADStartedByPlayer()
    local spec = self.spec_cpAIStreetWorker
    --- Applies the bale wrap type set in the hud, so ad can start with the correct type.
   
end

function CpAIStreetWorker:onCpADRestarted()
    
end
