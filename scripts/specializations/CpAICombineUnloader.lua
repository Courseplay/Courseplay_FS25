--- Specialization for unloading a combine on the field.
local modName = CpAICombineUnloader and CpAICombineUnloader.MOD_NAME -- for reload

---@class CpAICombineUnloader
CpAICombineUnloader = {}

CpAICombineUnloader.startText = g_i18n:getText("CP_fieldWorkJobParameters_startAt_unload")

CpAICombineUnloader.MOD_NAME = g_currentModName or modName
CpAICombineUnloader.NAME = ".cpAICombineUnloader"
CpAICombineUnloader.SPEC_NAME = CpAICombineUnloader.MOD_NAME .. CpAICombineUnloader.NAME
CpAICombineUnloader.KEY = "."..CpAICombineUnloader.MOD_NAME..CpAICombineUnloader.NAME

function CpAICombineUnloader.initSpecialization()
    local schema = Vehicle.xmlSchemaSavegame
    local key = "vehicles.vehicle(?)" .. CpAICombineUnloader.KEY
    CpJobParameters.registerXmlSchema(schema, key..".cpJob")

    --- Registers pipe controller measurement test and debug functions
    g_consoleCommands:registerConsoleCommand("cpPipeControllerMeasurePipe",
        "Measures the pipe properties while unfolded.", "consoleCommandMeasurePipeProperties", CpAICombineUnloader)
    g_consoleCommands:registerConsoleCommand("cpPipeControllerInstantUnfoldPipe",
        "Instant unfold of the pipe", "consoleCommandInstantUnfoldPipe", CpAICombineUnloader)
    g_consoleCommands:registerConsoleCommand("cpPipeControllerInstantFoldPipeAndImplement",
        "Instant fold of the pipe + implement", "consoleCommandInstantFoldPipeAndImplement", CpAICombineUnloader)
    g_consoleCommands:registerConsoleCommand("cpPipeControllerDebugFoldablePipe",
        "Debug for foldable pipes", "consoleCommandDebugFoldablePipe", CpAICombineUnloader)
    g_consoleCommands:registerConsoleCommand("cpPipeControllerSetFoldTime",
        "Debug for setting foldable pipe time", "consoleCommandSetFoldTime", CpAICombineUnloader)
    g_consoleCommands:registerConsoleCommand("cpPipeControllerToggleMoveablePipe",
        "Enables the moveable pipe feature", "consoleCommandToggleMoveablePipe", CpAICombineUnloader)
end

local function executePipeControllerCommand(lambdaFunc, ...)
    local vehicle = CpUtil.getCurrentVehicle()
    if not vehicle then 
        CpUtil.info("Could not measure pipe properties without entering a vehicle!")
        return
    end
    local pipeObject = AIUtil.getImplementOrVehicleWithSpecialization(vehicle, Pipe)
    if not pipeObject then 
        CpUtil.info("Could not measure pipe properties, as no valid vehicle/implement with pipe was found!")
        return
    end
    local controller
    if vehicle.spec_cpAICombineUnloader and vehicle.spec_cpAICombineUnloader.pipeController then 
        controller = vehicle.spec_cpAICombineUnloader.pipeController
    else 
        controller = PipeController(vehicle, pipeObject, false)
    end
    if not lambdaFunc(controller, vehicle, ...) then
        vehicle.spec_cpAICombineUnloader.pipeController = nil
        controller:delete()
    end
end

--- Helper command to test the pipe measurement.
function CpAICombineUnloader:consoleCommandMeasurePipeProperties()
    executePipeControllerCommand(function(controller)
        controller:measurePipeProperties()
    end)
end

function CpAICombineUnloader:consoleCommandInstantUnfoldPipe()
    executePipeControllerCommand(function(controller)
        controller:printFoldableDebug()
        controller:printPipeDebug()
        controller:instantUnfold(true)
        controller:printFoldableDebug()
        controller:printPipeDebug()
    end)
end

function CpAICombineUnloader:consoleCommandInstantFoldPipeAndImplement()
    executePipeControllerCommand(function(controller)
        controller:printFoldableDebug()
        controller:printPipeDebug()
        controller:instantFold()
        controller:printFoldableDebug()
        controller:printPipeDebug()
    end)
end

function CpAICombineUnloader:consoleCommandDebugFoldablePipe()
    executePipeControllerCommand(function(controller)
        controller:measurePipeProperties()
    end)
end

function CpAICombineUnloader:consoleCommandSetFoldTime(time, placeComponents)
    executePipeControllerCommand(function(controller)
        controller:printFoldableDebug()
        controller:debugSetFoldTime(time, placeComponents)
        controller:printFoldableDebug()
    end)
end

function CpAICombineUnloader:consoleCommandToggleMoveablePipe()
    executePipeControllerCommand(function(controller, vehicle)
        controller:printMoveablePipeDebug()
        if vehicle.spec_cpAICombineUnloader and vehicle.spec_cpAICombineUnloader.pipeController then 
            vehicle.spec_cpAICombineUnloader.pipeController = nil
            return
        end
        controller:measurePipeProperties()
        vehicle.spec_cpAICombineUnloader.pipeController = controller
        return true
    end)
end

function CpAICombineUnloader.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(CpAIWorker, specializations) 
end

function CpAICombineUnloader.register(typeManager,typeName,specializations)
	if CpAICombineUnloader.prerequisitesPresent(specializations) then
		typeManager:addSpecialization(typeName, CpAICombineUnloader.SPEC_NAME)
	end
end

function CpAICombineUnloader.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, 'onLoad', CpAICombineUnloader)
    SpecializationUtil.registerEventListener(vehicleType, 'onLoadFinished', CpAICombineUnloader)
    SpecializationUtil.registerEventListener(vehicleType, 'onReadStream', CpAICombineUnloader)
    SpecializationUtil.registerEventListener(vehicleType, 'onWriteStream', CpAICombineUnloader)
    SpecializationUtil.registerEventListener(vehicleType, 'onUpdate', CpAICombineUnloader)
end

function CpAICombineUnloader.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "startCpCombineUnloaderUnloading", CpAICombineUnloader.startCpCombineUnloaderUnloading)

    SpecializationUtil.registerFunction(vehicleType, "getCanStartCpCombineUnloader", CpAICombineUnloader.getCanStartCpCombineUnloader)
    SpecializationUtil.registerFunction(vehicleType, "getCpCombineUnloaderJobParameters", CpAICombineUnloader.getCpCombineUnloaderJobParameters)

    SpecializationUtil.registerFunction(vehicleType, "applyCpCombineUnloaderJobParameters", CpAICombineUnloader.applyCpCombineUnloaderJobParameters)
    SpecializationUtil.registerFunction(vehicleType, "getCpCombineUnloaderJob", CpAICombineUnloader.getCpCombineUnloaderJob)

    SpecializationUtil.registerFunction(vehicleType, "getIsCpCombineUnloaderActive", CpAICombineUnloader.getIsCpCombineUnloaderActive)
end

function CpAICombineUnloader.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCanStartCp', CpAICombineUnloader.getCanStartCp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCpStartableJob', CpAICombineUnloader.getCpStartableJob)

    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'startCpAtFirstWp', CpAICombineUnloader.startCpAtFirstWp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'startCpAtLastWp', CpAICombineUnloader.startCpAtLastWp)
end
------------------------------------------------------------------------------------------------------------------------
--- Event listeners
---------------------------------------------------------------------------------------------------------------------------
function CpAICombineUnloader:onLoad(savegame)
	--- Register the spec: spec_cpAICombineUnloader
    self.spec_cpAICombineUnloader = self["spec_" .. CpAICombineUnloader.SPEC_NAME]
    local spec = self.spec_cpAICombineUnloader
    --- This job is for starting the driving with a key bind or the mini gui.
    spec.cpJob = g_currentMission.aiJobTypeManager:createJob(AIJobType.COMBINE_UNLOADER_CP)
    spec.cpJob:setVehicle(self)
end

function CpAICombineUnloader:onLoadFinished(savegame)
    local spec = self.spec_cpAICombineUnloader
    if savegame ~= nil then 
        spec.cpJob:loadFromXMLFile(savegame.xmlFile, savegame.key.. CpAICombineUnloader.KEY..".cpJob")
    end
end

function CpAICombineUnloader:onUpdate(dt)
    local spec = self.spec_cpAICombineUnloader
    if spec.pipeController then 
        spec.pipeController:update(dt)
    end
end

function CpAICombineUnloader:saveToXMLFile(xmlFile, baseKey, usedModNames)
    local spec = self.spec_cpAICombineUnloader
    spec.cpJob:saveToXMLFile(xmlFile, baseKey.. ".cpJob")
end

function CpAICombineUnloader:onReadStream(streamId, connection)
    local spec = self.spec_cpAICombineUnloader
    spec.cpJob:readStream(streamId, connection)
end

function CpAICombineUnloader:onWriteStream(streamId, connection)
    local spec = self.spec_cpAICombineUnloader
    spec.cpJob:writeStream(streamId, connection)
end


function CpAICombineUnloader:getCpCombineUnloaderJobParameters()
    local spec = self.spec_cpAICombineUnloader
    return spec.cpJob:getCpJobParameters() 
end

--- Makes sure only trailers with discharge nodes are used.
function CpAICombineUnloader:isValidTrailer(trailer)
    if trailer.spec_woodCrusher then 
        return false
    end
    local spec = trailer.spec_dischargeable
    if not spec then 
        return false
    end
    if #spec.dischargeNodes <= 0 then 
        return false
    end
    return true
end

function CpAICombineUnloader:isOnlyOneTrailerAttached()
    --- Checks if at least one fill unit to unload into is there
    --- and only max one trailer attached.
    local vehicles = AIUtil.getAllChildVehiclesWithSpecialization(self, Trailer)
    local numTrailers = 0
    local numTrailersWithoutWheels = 0
    local vehicleHasTrailer = false
    for _, v in pairs(vehicles) do 
        vehicleHasTrailer = vehicleHasTrailer or v == self and CpAICombineUnloader.isValidTrailer(self, self)
        if v ~= self and CpAICombineUnloader.isValidTrailer(self, v) then
            if v.getWheels and #v:getWheels() > 0 and not v.spec_hookLiftContainer then 
                numTrailers = numTrailers + 1
            else 
                numTrailersWithoutWheels = numTrailersWithoutWheels + 1
            end
        end
    end
    if vehicleHasTrailer and numTrailers > 2 then 
        -- Vehicle has a trailer unit and more than one wheeled trailer is attached.
        return false
    end
    if not vehicleHasTrailer and numTrailers > 1 then 
         -- Vehicle has no trailer unit and more than one wheeled trailer is attached.
        return false
    end 
    --- Checks if at least one trailer is attached 
    return numTrailers > 0 or numTrailersWithoutWheels > 0 or vehicleHasTrailer
end

--- If we have a trailer which can be emptied, we can unload a combine
function CpAICombineUnloader:getCanStartCpCombineUnloader()
	return not self:getCanStartCpFieldWork() and CpAICombineUnloader.isOnlyOneTrailerAttached(self)
end

function CpAICombineUnloader:getCanStartCp(superFunc)
    return superFunc(self) or self:getCanStartCpCombineUnloader()
end

function CpAICombineUnloader:getCpStartableJob(superFunc, isStartedByHud)
    local spec = self.spec_cpAICombineUnloader
    if isStartedByHud and self:cpIsHudUnloaderJobSelected() then 
        return self:getCanStartCpCombineUnloader() and spec.cpJob
    end
    return superFunc(self, isStartedByHud) or not isStartedByHud and self:getCanStartCpCombineUnloader() and spec.cpJob
end

--- Starts the cp driver at the first waypoint.
function CpAICombineUnloader:startCpAtFirstWp(superFunc)
    if not superFunc(self) then 
        if self:getCanStartCpCombineUnloader() then
            local spec = self.spec_cpAICombineUnloader
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
function CpAICombineUnloader:startCpAtLastWp(superFunc)
    if not superFunc(self) then 
        if self:getCanStartCpCombineUnloader() then
            local spec = self.spec_cpAICombineUnloader
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

--- Forces the driver to unload now.
function CpAICombineUnloader:startCpCombineUnloaderUnloading()
    CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, 'Drive unload now requested')
    if self.isServer then 
        local strategy = self:getCpDriveStrategy()
        if strategy then 
            strategy:requestDriveUnloadNow()
        end
    else 
        DriveNowRequestEvent.sendEvent(self)
    end
end

function CpAICombineUnloader:applyCpCombineUnloaderJobParameters(job)
    local spec = self.spec_cpAICombineUnloader
    spec.cpJob:getCpJobParameters():validateSettings()
    spec.cpJob:copyFrom(job)
end

function CpAICombineUnloader:getCpCombineUnloaderJob()
    local spec = self.spec_cpAICombineUnloader
    return spec.cpJob
end

function CpAICombineUnloader:getIsCpCombineUnloaderActive()
    return self:getIsAIActive() and self:getJob() and self:getJob().is_a and self:getJob():is_a(CpAIJobCombineUnloader)
end