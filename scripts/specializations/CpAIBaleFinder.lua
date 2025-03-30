--- This spec is only for overwriting giants function of the AIFieldWorker.
local modName = CpAIBaleFinder and CpAIBaleFinder.MOD_NAME -- for reload

---@class CpAIBaleFinder
CpAIBaleFinder = {}

CpAIBaleFinder.startText = g_i18n:getText("CP_fieldWorkJobParameters_startAt_bales")

CpAIBaleFinder.MOD_NAME = g_currentModName or modName
CpAIBaleFinder.NAME = ".cpAIBaleFinder"
CpAIBaleFinder.SPEC_NAME = CpAIBaleFinder.MOD_NAME .. CpAIBaleFinder.NAME
CpAIBaleFinder.KEY = "."..CpAIBaleFinder.MOD_NAME..CpAIBaleFinder.NAME

function CpAIBaleFinder.initSpecialization()
    local schema = Vehicle.xmlSchemaSavegame
    local key = "vehicles.vehicle(?)" .. CpAIBaleFinder.KEY
    CpJobParameters.registerXmlSchema(schema, key..".cpJob")
    CpJobParameters.registerXmlSchema(schema, key..".cpJobStartAtLastWp")
end

function CpAIBaleFinder.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(CpAIWorker, specializations) 
end

function CpAIBaleFinder.register(typeManager,typeName,specializations)
	if CpAIBaleFinder.prerequisitesPresent(specializations) then
		typeManager:addSpecialization(typeName, CpAIBaleFinder.SPEC_NAME)
	end
end

function CpAIBaleFinder.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, 'onLoad', CpAIBaleFinder)
    SpecializationUtil.registerEventListener(vehicleType, 'onLoadFinished', CpAIBaleFinder)
    SpecializationUtil.registerEventListener(vehicleType, 'onReadStream', CpAIBaleFinder)
    SpecializationUtil.registerEventListener(vehicleType, 'onWriteStream', CpAIBaleFinder)
    SpecializationUtil.registerEventListener(vehicleType, "onCpWrapTypeSettingChanged", CpAIBaleFinder)

    SpecializationUtil.registerEventListener(vehicleType, 'onCpADStartedByPlayer', CpAIBaleFinder)
    SpecializationUtil.registerEventListener(vehicleType, 'onCpADRestarted', CpAIBaleFinder)
end

function CpAIBaleFinder.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getCanStartCpBaleFinder", CpAIBaleFinder.getCanStartCpBaleFinder)
    SpecializationUtil.registerFunction(vehicleType, "getCpBaleFinderJobParameters", CpAIBaleFinder.getCpBaleFinderJobParameters)
    SpecializationUtil.registerFunction(vehicleType, "getCpBaleFinderJob", CpAIBaleFinder.getCpBaleFinderJob)
    SpecializationUtil.registerFunction(vehicleType, "applyCpBaleFinderJobParameters", CpAIBaleFinder.applyCpBaleFinderJobParameters)

end

function CpAIBaleFinder.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCanStartCp', CpAIBaleFinder.getCanStartCp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCpStartableJob', CpAIBaleFinder.getCpStartableJob)

    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'startCpAtFirstWp', CpAIBaleFinder.startCpAtFirstWp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'startCpAtLastWp', CpAIBaleFinder.startCpAtLastWp)
end

function CpAIBaleFinder.registerEvents(vehicleType)
    SpecializationUtil.registerEvent(vehicleType, "onCpWrapTypeSettingChanged")   
end

------------------------------------------------------------------------------------------------------------------------
--- Event listeners
---------------------------------------------------------------------------------------------------------------------------
function CpAIBaleFinder:onLoad(savegame)
	--- Register the spec: spec_CpAIBaleFinder
    self.spec_cpAIBaleFinder = self["spec_" .. CpAIBaleFinder.SPEC_NAME]
    local spec = self.spec_cpAIBaleFinder
    --- This job is for starting the driving with a key bind or the mini gui.
    spec.cpJob = g_currentMission.aiJobTypeManager:createJob(AIJobType.BALE_FINDER_CP)
    spec.cpJob:setVehicle(self, true)
    spec.cpJobStartAtLastWp = g_currentMission.aiJobTypeManager:createJob(AIJobType.BALE_FINDER_CP)
    spec.cpJobStartAtLastWp:setVehicle(self, true)
end

function CpAIBaleFinder:onLoadFinished(savegame)
    local spec = self.spec_cpAIBaleFinder
    if savegame ~= nil then 
        spec.cpJob:getCpJobParameters():loadFromXMLFile(savegame.xmlFile, savegame.key.. CpAIBaleFinder.KEY..".cpJob")
        spec.cpJobStartAtLastWp:getCpJobParameters():loadFromXMLFile(savegame.xmlFile, savegame.key.. CpAIFieldWorker.KEY..".cpJobStartAtLastWp")
    end
end

function CpAIBaleFinder:saveToXMLFile(xmlFile, baseKey, usedModNames)
    local spec = self.spec_cpAIBaleFinder
    spec.cpJob:getCpJobParameters():saveToXMLFile(xmlFile, baseKey.. ".cpJob")
    spec.cpJobStartAtLastWp:getCpJobParameters():saveToXMLFile(xmlFile, baseKey.. ".cpJobStartAtLastWp")
end

function CpAIBaleFinder:onReadStream(streamId, connection)
    local spec = self.spec_cpAIBaleFinder
    spec.cpJob:readStream(streamId, connection)
end

function CpAIBaleFinder:onWriteStream(streamId, connection)
    local spec = self.spec_cpAIBaleFinder
    spec.cpJob:writeStream(streamId, connection)
end

function CpAIBaleFinder:getCpBaleFinderJobParameters()
    local spec = self.spec_cpAIBaleFinder
    return spec.cpJob:getCpJobParameters() 
end

function CpAIBaleFinder:getCpBaleFinderJob()
    local spec = self.spec_cpAIBaleFinder
    return spec.cpJob
end


function CpAIBaleFinder:applyCpBaleFinderJobParameters(job)
    local spec = self.spec_cpAIBaleFinder
    spec.cpJob:getCpJobParameters():validateSettings()
    spec.cpJob:copyFrom(job)
end

--- Is the bale finder allowed?
function CpAIBaleFinder:getCanStartCpBaleFinder()
	return (AIUtil.hasImplementWithSpecialization(self, BaleWrapper) and not AIUtil.hasImplementWithSpecialization(self, Baler)) or
			AIUtil.hasImplementWithSpecialization(self, BaleLoader) or 
            --- FS22_aPalletAutoLoader from Achimobil: https://bitbucket.org/Achimobil79/ls22_palletautoloader/src/master/
            AIUtil.hasChildVehicleWithSpecialization(self, nil, "spec_aPalletAutoLoader") or 
            --- FS22_UniversalAutoload form loki79uk: https://github.com/loki79uk/FS22_UniversalAutoload
            AIUtil.hasValidUniversalTrailerAttached(self)
end

function CpAIBaleFinder:getCanStartCp(superFunc)
    return superFunc(self) or self:getCanStartCpBaleFinder()
end

--- Only use the bale finder, if the cp field work job is not possible.
function CpAIBaleFinder:getCpStartableJob(superFunc, isStartedByHud)
    local spec = self.spec_cpAIBaleFinder
    if isStartedByHud and self:cpIsHudBaleFinderJobSelected() then 
        return self:getCanStartCpBaleFinder() and spec.cpJob
    end
	return superFunc(self, isStartedByHud) or not isStartedByHud and self:getCanStartCpBaleFinder() and spec.cpJob
end

--- Starts the cp driver at the first waypoint.
function CpAIBaleFinder:startCpAtFirstWp(superFunc)
    if not superFunc(self) then 
        if self:getCanStartCpBaleFinder() then 
            local spec = self.spec_cpAIBaleFinder
            --- Applies the bale wrap type set in the hud, so ad can start with the correct type.
            --- TODO: This should only be applied, if the driver was started for the first time by ad and not every time.
            spec.cpJobStartAtLastWp:getCpJobParameters().baleWrapType:setValue(spec.cpJob:getCpJobParameters().baleWrapType:getValue())
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
function CpAIBaleFinder:startCpAtLastWp(superFunc)
    if not superFunc(self) then 
        if self:getCanStartCpBaleFinder() then 
            local spec = self.spec_cpAIBaleFinder
            spec.cpJobStartAtLastWp:applyCurrentState(self, g_currentMission, g_currentMission.playerSystem:getLocalPlayer().farmId, true)
            spec.cpJobStartAtLastWp:setValues()
            local success = spec.cpJobStartAtLastWp:validate(false)
            if success then
                g_client:getServerConnection():sendEvent(AIJobStartRequestEvent.new(spec.cpJobStartAtLastWp, self:getOwnerFarmId()))
                return true
            end
        end
    else 
        return true
    end
end

function CpAIBaleFinder:onCpADStartedByPlayer()
    local spec = self.spec_cpAIBaleFinder
    --- Applies the bale wrap type set in the hud, so ad can start with the correct type.
    spec.cpJobStartAtLastWp:getCpJobParameters().baleWrapType:setValue(spec.cpJob:getCpJobParameters().baleWrapType:getValue())
end

function CpAIBaleFinder:onCpADRestarted()
    
end

function CpAIBaleFinder:onCpWrapTypeSettingChanged()
    local strategy = self:getCpDriveStrategy()
    if strategy and strategy.findBales then 
        CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, "Refreshed bales requested by setting.")
        strategy:findBales()
    end
   
end
