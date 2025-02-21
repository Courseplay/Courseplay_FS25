--- Cp field worker that drives along a course.
local modName = CpAIFieldWorker and CpAIFieldWorker.MOD_NAME -- for reload

---@class CpAIFieldWorker
CpAIFieldWorker = {}

CpAIFieldWorker.MOD_NAME = g_currentModName or modName
CpAIFieldWorker.NAME = ".cpAIFieldWorker"
CpAIFieldWorker.SPEC_NAME = CpAIFieldWorker.MOD_NAME .. CpAIFieldWorker.NAME
CpAIFieldWorker.KEY = "."..CpAIFieldWorker.MOD_NAME..CpAIFieldWorker.NAME

function CpAIFieldWorker.initSpecialization()
    local schema = Vehicle.xmlSchemaSavegame
    local key = "vehicles.vehicle(?)" .. CpAIFieldWorker.KEY
    CpJobParameters.registerXmlSchema(schema, key..".cpJob")
    CpJobParameters.registerXmlSchema(schema, key..".cpJobStartAtLastWp")
end

function CpAIFieldWorker.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(CpAIWorker, specializations) 
end

function CpAIFieldWorker.register(typeManager,typeName,specializations)
	if CpAIFieldWorker.prerequisitesPresent(specializations) then
		typeManager:addSpecialization(typeName, CpAIFieldWorker.SPEC_NAME)
	end
end

function CpAIFieldWorker.registerEvents(vehicleType)
  --  SpecializationUtil.registerEvent(vehicleType, "onCpFinished")
	
end

function CpAIFieldWorker.registerEventListeners(vehicleType)
	SpecializationUtil.registerEventListener(vehicleType, "onLoad", CpAIFieldWorker)
    SpecializationUtil.registerEventListener(vehicleType, "onLoadFinished", CpAIFieldWorker)

    SpecializationUtil.registerEventListener(vehicleType, "onCpEmpty", CpAIFieldWorker)
    SpecializationUtil.registerEventListener(vehicleType, "onCpFull", CpAIFieldWorker)
    SpecializationUtil.registerEventListener(vehicleType, "onCpFinished", CpAIFieldWorker)

    SpecializationUtil.registerEventListener(vehicleType, "onStateChange", CpAIFieldWorker)
    SpecializationUtil.registerEventListener(vehicleType, 'onCpCourseChange', CpAIFieldWorker)

    SpecializationUtil.registerEventListener(vehicleType, 'onCpADStartedByPlayer', CpAIFieldWorker)
    SpecializationUtil.registerEventListener(vehicleType, 'onCpADRestarted', CpAIFieldWorker)
end

function CpAIFieldWorker.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getIsCpFieldWorkActive", CpAIFieldWorker.getIsCpFieldWorkActive)
    SpecializationUtil.registerFunction(vehicleType, "getCpFieldWorkProgress", CpAIFieldWorker.getCpFieldWorkProgress)
    SpecializationUtil.registerFunction(vehicleType, "getIsCpHarvesterWaitingForUnload",
            CpAIFieldWorker.getIsCpHarvesterWaitingForUnload)
    SpecializationUtil.registerFunction(vehicleType, "getIsCpHarvesterWaitingForUnloadInPocket",
            CpAIFieldWorker.getIsCpHarvesterWaitingForUnloadInPocket)
    SpecializationUtil.registerFunction(vehicleType, "getIsCpHarvesterWaitingForUnloadAfterPulledBack",
            CpAIFieldWorker.getIsCpHarvesterWaitingForUnloadAfterPulledBack)
    SpecializationUtil.registerFunction(vehicleType, "getIsCpHarvesterManeuvering", CpAIFieldWorker.getIsCpHarvesterManeuvering)
    SpecializationUtil.registerFunction(vehicleType, "holdCpHarvesterTemporarily", CpAIFieldWorker.holdCpHarvesterTemporarily)
    SpecializationUtil.registerFunction(vehicleType, "getCanStartCpFieldWork", CpAIFieldWorker.getCanStartCpFieldWork)

    SpecializationUtil.registerFunction(vehicleType, "startCpAtFirstWp", CpAIFieldWorker.startCpAtFirstWp)
    SpecializationUtil.registerFunction(vehicleType, "startCpAtLastWp", CpAIFieldWorker.startCpAtLastWp)
    SpecializationUtil.registerFunction(vehicleType, "getCpStartingPointSetting", CpAIFieldWorker.getCpStartingPointSetting)
    SpecializationUtil.registerFunction(vehicleType, "getCpLaneOffsetSetting", CpAIFieldWorker.getCpLaneOffsetSetting)
end

function CpAIFieldWorker.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCanStartCp', CpAIFieldWorker.getCanStartCp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCpStartableJob', CpAIFieldWorker.getCpStartableJob)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCpDriveStrategy', CpAIFieldWorker.getCpDriveStrategy)
end

------------------------------------------------------------------------------------------------------------------------
--- Event listeners
---------------------------------------------------------------------------------------------------------------------------
function CpAIFieldWorker:onLoad(savegame)
	--- Register the spec: spec_cpAIFieldWorker
    self.spec_cpAIFieldWorker = self["spec_" .. CpAIFieldWorker.SPEC_NAME]
    local spec = self.spec_cpAIFieldWorker
    if spec == nil then
        CpUtil.error("spec_cpAIFieldWorker is nil in onLoad")
        return
    end
    --- This job is for starting the driving with a key bind or the hud.
    spec.cpJob = g_currentMission.aiJobTypeManager:createJob(AIJobType.FIELDWORK_CP)
    spec.cpJob:getCpJobParameters().startAt:setValue(CpFieldWorkJobParameters.START_AT_NEAREST_POINT)
    spec.cpJob:setVehicle(self, true)
    --- Theses jobs are used for external mod, for example AutoDrive.
    spec.cpJobStartAtFirstWp = g_currentMission.aiJobTypeManager:createJob(AIJobType.FIELDWORK_CP)
    spec.cpJobStartAtFirstWp:getCpJobParameters().startAt:setValue(CpFieldWorkJobParameters.START_AT_FIRST_POINT)
    spec.cpJobStartAtLastWp = g_currentMission.aiJobTypeManager:createJob(AIJobType.FIELDWORK_CP)
    spec.cpJobStartAtLastWp:getCpJobParameters().startAt:setValue(CpFieldWorkJobParameters.START_AT_LAST_POINT)
end

function CpAIFieldWorker:onLoadFinished(savegame)
    local spec = self.spec_cpAIFieldWorker
    if spec == nil then
        CpUtil.error("spec_cpAIFieldWorker is nil in onLoadFinished")
        return
    end
    if savegame ~= nil then 
        spec.cpJob:getCpJobParameters():loadFromXMLFile(savegame.xmlFile, savegame.key.. CpAIFieldWorker.KEY..".cpJob")
        spec.cpJobStartAtLastWp:getCpJobParameters():loadFromXMLFile(savegame.xmlFile, savegame.key.. CpAIFieldWorker.KEY..".cpJobStartAtLastWp")
    end
end

function CpAIFieldWorker:saveToXMLFile(xmlFile, baseKey, usedModNames)
    local spec = self.spec_cpAIFieldWorker
    spec.cpJob:getCpJobParameters():saveToXMLFile(xmlFile, baseKey.. ".cpJob")
    spec.cpJobStartAtLastWp:getCpJobParameters():saveToXMLFile(xmlFile, baseKey.. ".cpJobStartAtLastWp")
end

function CpAIFieldWorker:onStateChange(state, data)
    local spec = self.spec_cpAIFieldWorker
    if state == VehicleStateChange.ATTACH then
        spec.cpJob:getCpJobParameters():validateSettings()
    elseif state == VehicleStateChange.DETACH then
        spec.cpJob:getCpJobParameters():validateSettings()
    end
end

function CpAIFieldWorker:onCpCourseChange()
    local spec = self.spec_cpAIFieldWorker
    if spec.cpJob then
        spec.cpJob:getCpJobParameters():validateSettings()
    end
end

function CpAIFieldWorker:getCpStartingPointSetting()
    local spec = self.spec_cpAIFieldWorker
    return spec.cpJob:getCpJobParameters().startAt
end

function CpAIFieldWorker:getCpLaneOffsetSetting()
    local spec = self.spec_cpAIFieldWorker
    return spec.cpJob:getCpJobParameters().laneOffset
end

------------------------------------------------------------------------------------------------------------------------
--- Interface for other mods, like AutoDrive
------------------------------------------------------------------------------------------------------------------------

--- Is a cp fieldwork job active ?
function CpAIFieldWorker:getIsCpFieldWorkActive()
    return self:getIsAIActive() and self:getJob() and self:getJob().is_a and self:getJob():is_a(CpAIJobFieldWork)
end

function CpAIFieldWorker:getCpFieldWorkProgress()
    local strategy = self:getCpDriveStrategy()
    if strategy then
        return strategy:getProgress()
    end
end

--- Gets the current field work drive strategy.
function CpAIFieldWorker:getCpDriveStrategy(superFunc)
    return superFunc(self) or self.spec_cpAIFieldWorker.driveStrategy
end

--- To find out if a harvester is waiting to be unloaded, either because it is full or ended the fieldwork course
--- with some grain in the tank.
---@return boolean true when the harvester is waiting to be unloaded
function CpAIFieldWorker:getIsCpHarvesterWaitingForUnload()
    return self.spec_cpAIFieldWorker.combineDriveStrategy and
            self.spec_cpAIFieldWorker.combineDriveStrategy:isWaitingForUnload()
end

--- To find out if a harvester is waiting to be unloaded in a pocket. Harvesters may cut a pocket on the opposite
--- side of the pipe to make room for an unloader if:
--- * working on the first headland (so the unloader can get under the pipe while staying on the headland)
--- * cutting the first row in the middle of the field
---@return boolean true when the harvester is waiting to be unloaded in a pocket
function CpAIFieldWorker:getIsCpHarvesterWaitingForUnloadInPocket()
    return self.spec_cpAIFieldWorker.combineDriveStrategy and
            self.spec_cpAIFieldWorker.combineDriveStrategy:isWaitingInPocket()
end

--- To find out if a harvester is waiting to be unloaded after it pulled back to the side. This
--- is similar to a pocket but in this case there is no fruit on the opposite side of the pipe,
--- so the harvester just moves to the side and backwards without cutting a pocket.
---@return boolean
function CpAIFieldWorker:getIsCpHarvesterWaitingForUnloadAfterPulledBack()
    return self.spec_cpAIFieldWorker.combineDriveStrategy and
            self.spec_cpAIFieldWorker.combineDriveStrategy:isWaitingForUnloadAfterPulledBack()
end

--- Maneuvering means turning or working on a pocket or pulling back due to the pipe in fruit
---@return boolean true when the harvester is maneuvering so that an unloader should stay away.
function CpAIFieldWorker:getIsCpHarvesterManeuvering()
    return self.spec_cpAIFieldWorker.combineDriveStrategy and
            self.spec_cpAIFieldWorker.combineDriveStrategy:isManeuvering()
end

--- Hold the harvester (set its speed to 0) for a period of periodMs milliseconds.
--- Calling this again will restart the timer with the new value. Calling with 0 will end the temporary hold
--- immediately.
---@param periodMs number
function CpAIFieldWorker:holdCpHarvesterTemporarily(periodMs)
    return self.spec_cpAIFieldWorker.combineDriveStrategy and
            self.spec_cpAIFieldWorker.combineDriveStrategy:hold(periodMs)
end

--- Starts the cp driver at the first waypoint.
function CpAIFieldWorker:startCpAtFirstWp()
    local spec = self.spec_cpAIFieldWorker
    self:updateAIFieldWorkerImplementData()
    if self:hasCpCourse() and self:getCanStartCpFieldWork() then
        spec.cpJobStartAtFirstWp:applyCurrentState(self, g_currentMission, g_currentMission.playerSystem:getLocalPlayer().farmId, true, false)
        --- Applies the lane offset set in the hud, so ad can start with the correct lane offset.
        spec.cpJobStartAtFirstWp:getCpJobParameters().laneOffset:setValue(self:getCpLaneOffsetSetting():getValue())
        spec.cpJobStartAtFirstWp:setValues()
        local success = spec.cpJobStartAtFirstWp:validate(false)
        if success then
            g_client:getServerConnection():sendEvent(AIJobStartRequestEvent.new(spec.cpJobStartAtFirstWp, self:getOwnerFarmId()))
            return true
        end
    end
end

--- Starts the cp driver at the last driven waypoint.
function CpAIFieldWorker:startCpAtLastWp()
    local spec = self.spec_cpAIFieldWorker
    self:updateAIFieldWorkerImplementData()
    if self:hasCpCourse() and self:getCanStartCpFieldWork() then
        spec.cpJobStartAtLastWp:applyCurrentState(self, g_currentMission, g_currentMission.playerSystem:getLocalPlayer().farmId, true, false)
        spec.cpJobStartAtLastWp:setValues()
        CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, "lane offset: %s", spec.cpJobStartAtLastWp:getCpJobParameters().laneOffset:getString())
        local success = spec.cpJobStartAtLastWp:validate(false)
        CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, "lane offset: %s", spec.cpJobStartAtLastWp:getCpJobParameters().laneOffset:getString())
        if success then
            g_client:getServerConnection():sendEvent(AIJobStartRequestEvent.new(spec.cpJobStartAtLastWp, self:getOwnerFarmId()))
            return true
        end
    end
end

function CpAIFieldWorker:onCpADStartedByPlayer()
    local spec = self.spec_cpAIFieldWorker
    --- Applies the lane offset set in the hud, so ad can start with the correct one.
    spec.cpJobStartAtLastWp:getCpJobParameters().laneOffset:setValue(self:getCpLaneOffsetSetting():getValue())
end

function CpAIFieldWorker:onCpADRestarted()
    local spec = self.spec_cpAIFieldWorker
  
end

--- Event listener called, when an implement is full.
function CpAIFieldWorker:onCpFull()
  
end

--- Event listener called, when an implement is empty.
function CpAIFieldWorker:onCpEmpty()
  
end

--- Event listener called, when the cp job is finished.
function CpAIFieldWorker:onCpFinished()
 
end

function CpAIFieldWorker:getCanStartCpFieldWork()
    self:updateAIFieldWorkerImplementData()
    -- built in helper can't handle it, but we may be able to ...
    if AIUtil.hasChildVehicleWithSpecialization(self, nil, "spec_pdlc_goeweilPack.balerStationary") then 
        --- Make sure stationary balers are ignored!
        return false
    end
    if AIUtil.hasChildVehicleWithSpecialization(self, Baler) or
            AIUtil.hasChildVehicleWithSpecialization(self, StonePicker) or
            AIUtil.hasImplementWithSpecialization(self, BaleWrapper) or
            AIUtil.hasImplementWithSpecialization(self, BaleLoader) or
            AIUtil.hasChildVehicleWithSpecialization(self, ForageWagon) or
            -- built in helper can't handle forage harvesters.
            AIUtil.hasImplementWithSpecialization(self, Cutter) or
            AIUtil.hasChildVehicleWithSpecialization(self, VineCutter) or
            AIUtil.hasChildVehicleWithSpecialization(self, VinePrepruner) or
            --- This also allows the use of stump cutters, that work like a mulcher.
            AIUtil.hasChildVehicleWithSpecialization(self, Plow) or
            --- A few mowers can't be used by the giants fieldworker 
            AIUtil.hasChildVehicleWithSpecialization(self, Mower) or
            --- Pushed hand tools can't be used by the giants fieldworker 
            AIUtil.hasChildVehicleWithSpecialization(self, PushHandTool) or
            -- Harvester with cutter on trailer attached.
            AIUtil.hasCutterOnTrailerAttached(self) or
            --- precision farming
            AIUtil.hasChildVehicleWithSpecialization(self, nil, "spec_soilSampler") or 
            --- FS22_aPalletAutoLoader from Achimobil: https://bitbucket.org/Achimobil79/ls22_palletautoloader/src/master/
            AIUtil.hasChildVehicleWithSpecialization(self, nil, "spec_aPalletAutoLoader")  or 
            --- FS22_UniversalAutoload from Loki79uk: https://github.com/loki79uk/FS22_UniversalAutoload
            AIUtil.hasValidUniversalTrailerAttached(self) then
                
        return true
    end
    return self:getCanStartFieldWork()
end

--- Only allow the basic field work job to start, if a course is assigned.
function CpAIFieldWorker:getCanStartCp(superFunc)
    return not self:getIsCpCourseRecorderActive() and  self:hasCpCourse() and self:getCanStartCpFieldWork() or superFunc(self)
end

--- Gets the field work job for the hud or start action event.
function CpAIFieldWorker:getCpStartableJob(superFunc, isStartedByHud)
    local spec = self.spec_cpAIFieldWorker
    if isStartedByHud and self:cpIsHudFieldWorkJobSelected() then 
        return self:getCanStartCpFieldWork() and self:hasCpCourse() and spec.cpJob
    end
	return superFunc(self, isStartedByHud) or not isStartedByHud and self:getCanStartCpFieldWork() and self:hasCpCourse() and spec.cpJob
end

--- Makes sure a callstack is printed, when an error appeared.
--- TODO: Might be a good idea to stop the cp helper.
local function onUpdate(vehicle, superFunc, ...)
    CpUtil.try(superFunc, vehicle, ...)
end

AIFieldWorker.onUpdate = Utils.overwrittenFunction(AIFieldWorker.onUpdate, onUpdate)

--- Ugly hack to avoid restarting the giants helper after loading a savegame,
--- if cp was active prior to saving the game ...
local function saveToXMLFile(vehicle, superFunc, xmlFile, key, ...)
    superFunc(vehicle, xmlFile, key, ...)
    if vehicle.getIsCpActive and vehicle:getIsCpActive() then 
        xmlFile:setValue(key .. "#isActive", false)
    end
end

AIFieldWorker.saveToXMLFile = Utils.overwrittenFunction(AIFieldWorker.saveToXMLFile, saveToXMLFile)
