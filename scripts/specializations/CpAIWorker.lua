--- Base cp ai specialization.
local modName = CpAIWorker and CpAIWorker.MOD_NAME -- for reload

---@class CpAIWorker
CpAIWorker = {}

CpAIWorker.MOD_NAME = g_currentModName or modName
CpAIWorker.NAME = ".cpAIWorker"
CpAIWorker.SPEC_NAME = CpAIWorker.MOD_NAME .. CpAIWorker.NAME
CpAIWorker.KEY = "." .. CpAIWorker.MOD_NAME .. CpAIWorker.NAME .. "."
CpAIWorker.LAST_JOB_KEY = "vehicles.vehicle(?).aiJobVehicle.lastJob"

function CpAIWorker.initSpecialization()
    local schema = Vehicle.xmlSchemaSavegame
    --- Registers the last job key.
    CpJobParameters.registerXmlSchema(schema, CpAIWorker.LAST_JOB_KEY)
    CpAIWorker.registerConsoleCommands()
end

function CpAIWorker.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(AIFieldWorker, specializations)
end

function CpAIWorker.register(typeManager, typeName, specializations)
    if CpAIWorker.prerequisitesPresent(specializations) then
        typeManager:addSpecialization(typeName, CpAIWorker.SPEC_NAME)
    end
end

function CpAIWorker.registerEvents(vehicleType)
    SpecializationUtil.registerEvent(vehicleType, "onCpUnitChanged")
    SpecializationUtil.registerEvent(vehicleType, "onCpDrawHudMap")

    SpecializationUtil.registerEvent(vehicleType, "onCpFinished")
    SpecializationUtil.registerEvent(vehicleType, "onCpEmpty")
    SpecializationUtil.registerEvent(vehicleType, "onCpFull")
    SpecializationUtil.registerEvent(vehicleType, "onCpFuelEmpty")
    SpecializationUtil.registerEvent(vehicleType, "onCpBroken")
    --- internal AD Events.
    SpecializationUtil.registerEvent(vehicleType, "onCpADStartedByPlayer")
    SpecializationUtil.registerEvent(vehicleType, "onCpADRestarted")
end

function CpAIWorker.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", CpAIWorker)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", CpAIWorker)
    SpecializationUtil.registerEventListener(vehicleType, "onLoadFinished", CpAIWorker)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", CpAIWorker)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", CpAIWorker)
    SpecializationUtil.registerEventListener(vehicleType, "onLeaveVehicle", CpAIWorker)
    SpecializationUtil.registerEventListener(vehicleType, "onPreDelete", CpAIWorker)
    --- Autodrive events
    SpecializationUtil.registerEventListener(vehicleType, "onStopAutoDrive", CpAIWorker)
    SpecializationUtil.registerEventListener(vehicleType, "onStartAutoDrive", CpAIWorker)
end

function CpAIWorker.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getIsCpActive", CpAIWorker.getIsCpActive)
    SpecializationUtil.registerFunction(vehicleType, "getIsCpDriveToFieldWorkActive", CpAIWorker.getIsCpDriveToFieldWorkActive)
    SpecializationUtil.registerFunction(vehicleType, "getCpStartableJob", CpAIWorker.getCpStartableJob)
    SpecializationUtil.registerFunction(vehicleType, "getCpStartText", CpAIWorker.getCpStartText)
    SpecializationUtil.registerFunction(vehicleType, "cpStartStopDriver", CpAIWorker.cpStartStopDriver)
    SpecializationUtil.registerFunction(vehicleType, "getCanStartCp", CpAIWorker.getCanStartCp)
    SpecializationUtil.registerFunction(vehicleType, "freezeCp", CpAIWorker.freezeCp)
    SpecializationUtil.registerFunction(vehicleType, "unfreezeCp", CpAIWorker.unfreezeCp)
    SpecializationUtil.registerFunction(vehicleType, "startCpWithStrategy", CpAIWorker.startCpWithStrategy)
    SpecializationUtil.registerFunction(vehicleType, "stopCpDriver", CpAIWorker.stopCpDriver)
    SpecializationUtil.registerFunction(vehicleType, "cpHold", CpAIWorker.cpHold)
    SpecializationUtil.registerFunction(vehicleType, "cpBrakeToStop", CpAIWorker.cpBrakeToStop)
    SpecializationUtil.registerFunction(vehicleType, "getCpDriveStrategy", CpAIWorker.getCpDriveStrategy)
end

function CpAIWorker.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'stopCurrentAIJob', CpAIWorker.stopCurrentAIJob)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'getCanMotorRun', CpAIWorker.getCanMotorRun)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, 'stopFieldWorker', CpAIWorker.stopFieldWorker)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getAIReverserNode", CpAIWorker.getAIReverserNode)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getAIDirectionNode", CpAIWorker.getAIDirectionNode)
end

---------------------------------------------------
--- Event listeners
---------------------------------------------------

function CpAIWorker:onLoad(savegame)
    --- Register the spec: spec_CpAIWorker
    self.spec_cpAIWorker = self["spec_" .. CpAIWorker.SPEC_NAME]
    local spec = self.spec_cpAIWorker
    --- Flag to make sure the motor isn't being turned on again by giants code, when we want it turned off.
    spec.motorDisabled = false
    spec.driveStrategy = nil
    g_messageCenter:subscribe(MessageType.SETTING_CHANGED[GameSettings.SETTING.USE_MILES], CpAIWorker.onUnitChanged, self)
    g_messageCenter:subscribe(MessageType.SETTING_CHANGED[GameSettings.SETTING.USE_ACRE], CpAIWorker.onUnitChanged, self)
    g_messageCenter:subscribe(MessageType.CP_DISTANCE_UNIT_CHANGED, CpAIWorker.onUnitChanged, self)
end

function CpAIWorker:onUnitChanged()
    SpecializationUtil.raiseEvent(self, "onCpUnitChanged")
end

function CpAIWorker:onLoadFinished()

end

function CpAIWorker:onLeaveVehicle(wasEntered)
    if wasEntered then
        CpJobSyncOnLeaveEvent.sendEvent(self)
    end
end

--- Registers the start stop action event.
function CpAIWorker:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if self.isClient then
        local spec = self.spec_cpAIWorker

        self:clearActionEventsTable(spec.actionEvents)

        if self.spec_aiJobVehicle.supportsAIJobs and self:getIsActiveForInput(true, true) then

            local function addActionEvent(vehicle, event, callback, text)
                local actionEventsVisible = g_Courseplay.globalSettings.showActionEventHelp:getValue()
                local _, actionEventId = vehicle:addActionEvent(spec.actionEvents, event, vehicle, callback, false, true, false, true, nil)
                g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_HIGH)
                g_inputBinding:setActionEventTextVisibility(actionEventId, actionEventsVisible)
                if text ~= nil then
                    g_inputBinding:setActionEventText(actionEventId, text)
                end
            end

            addActionEvent(self, InputAction.CP_START_STOP, function ()
                    self:cpStartStopDriver(true)
                end)
            addActionEvent(self, InputAction.CP_START_STOP_AT_FIRST_WAYPOINT, function (self)
                    local startingPointSetting = self:getCpStartingPointSetting()
                    startingPointSetting:setValue(CpFieldWorkJobParameters.START_AT_FIRST_POINT)
                    self:cpStartStopDriver(true)
                end)
            addActionEvent(self, InputAction.CP_START_STOP_AT_NEAREST_WAYPOINT, function (self)
                    local startingPointSetting = self:getCpStartingPointSetting()
                    startingPointSetting:setValue(CpFieldWorkJobParameters.START_AT_NEAREST_POINT)
                    self:cpStartStopDriver(true)
                end)
            addActionEvent(self, InputAction.CP_START_STOP_AT_LAST_WAYPOINT, function (self)
                    local startingPointSetting = self:getCpStartingPointSetting()
                    startingPointSetting:setValue(CpFieldWorkJobParameters.START_AT_LAST_POINT)
                    self:cpStartStopDriver(true)
                end)
            
            addActionEvent(self, InputAction.CP_GENERATE_COURSE, function (self)
                    if self:getCanStartCpFieldWork() then
                        CourseGeneratorInterface():generateDefaultCourse(self)
                    end
                end)
            addActionEvent(self, InputAction.CP_CHANGE_SELECTED_JOB, function (self)
                    local currentJobSetting = self:cpGetHudSelectedJobSetting()
                    currentJobSetting:setNextItem()
                end)
            addActionEvent(self, InputAction.CP_CHANGE_STARTING_POINT, function (self)
                    local startingPointSetting = self:getCpStartingPointSetting()
                    startingPointSetting:setNextItem()
                end)
            addActionEvent(self, InputAction.CP_CLEAR_COURSE, function (self)
                    self:resetCpCoursesFromGui()
                end, g_i18n:getText("input_CP_CLEAR_COURSE"))
            addActionEvent(self, InputAction.CP_CHANGE_COURSE_VISIBILITY, function ()
                    self:getCpSettings().showCourse:setNextItem()
                end)
            addActionEvent(self, InputAction.CP_OPEN_VEHICLE_SETTINGS, function ()
                    CpGuiUtil.openVehicleSettingsGui(self)
                end, g_i18n:getText("input_CP_OPEN_VEHICLE_SETTINGS"))
            addActionEvent(self, InputAction.CP_OPEN_GLOBAL_SETTINGS, function ()
                    CpGuiUtil.openGlobalSettingsGui(self)
                end, g_i18n:getText("input_CP_OPEN_GLOBAL_SETTINGS"))
            addActionEvent(self, InputAction.CP_OPEN_COURSEGENERATOR_SETTINGS, function ()
                    CpGuiUtil.openCourseGeneratorGui(self)
                end, g_i18n:getText("input_CP_OPEN_COURSEGENERATOR_SETTINGS"))
            addActionEvent(self, InputAction.CP_OPEN_COURSEMANAGER, function ()
                    CpGuiUtil.openCourseManagerGui(self)
                end, g_i18n:getText("input_CP_OPEN_COURSEMANAGER"))

            CpAIWorker.updateActionEvents(self)
        end
    end
end

function CpAIWorker:onUpdateTick(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    CpAIWorker.updateActionEvents(self)
end

function CpAIWorker:onPreDelete()

end

-----------------------------------------------
--- Action input events
-----------------------------------------------

--- Updates the action event visibility and text.
function CpAIWorker:updateActionEvents()
    local spec = self.spec_cpAIWorker
    local giantsSpec = self.spec_aiJobVehicle
    if self.isActiveForInputIgnoreSelectionIgnoreAI and giantsSpec.supportsAIJobs then
        local actionEvent = spec.actionEvents[InputAction.CP_START_STOP]
        if not actionEvent then
            --- No action events registered.
            return
        end
        if self:getShowAIToggleActionEvent() then
            if self:getIsAIActive() then
                g_inputBinding:setActionEventText(actionEvent.actionEventId, "CP: " .. giantsSpec.texts.dismissEmployee)
            else
                local text = string.format("CP: %s\n(%s)", giantsSpec.texts.hireEmployee, self:getCpStartText())
                g_inputBinding:setActionEventText(actionEvent.actionEventId, text)
            end

            g_inputBinding:setActionEventActive(actionEvent.actionEventId, true)
        else
            g_inputBinding:setActionEventActive(actionEvent.actionEventId, false)
        end
        actionEvent = spec.actionEvents[InputAction.CP_CHANGE_SELECTED_JOB]
        local selectedJobSetting = self:cpGetHudSelectedJobSetting()
        g_inputBinding:setActionEventText(actionEvent.actionEventId, string.format("CP: %s (%s)", 
            selectedJobSetting:getTitle(), selectedJobSetting:getString()))
        g_inputBinding:setActionEventActive(actionEvent.actionEventId, 
            self:getShowAIToggleActionEvent() and not self:getIsAIActive())

        actionEvent = spec.actionEvents[InputAction.CP_CHANGE_STARTING_POINT]
        local startingPointSetting = self:getCpStartingPointSetting()
        g_inputBinding:setActionEventText(actionEvent.actionEventId, string.format("CP: %s (%s)", 
            startingPointSetting:getTitle(), startingPointSetting:getString()))
        g_inputBinding:setActionEventActive(actionEvent.actionEventId, 
            self:getShowAIToggleActionEvent() and not self:getIsAIActive()
            and self:cpIsHudFieldWorkJobSelected())

        actionEvent = spec.actionEvents[InputAction.CP_CHANGE_COURSE_VISIBILITY]
        local setting = self:getCpSettings().showCourse
        g_inputBinding:setActionEventText(actionEvent.actionEventId, string.format("CP: %s (%s)", 
            setting:getTitle(), setting:getString()))
        g_inputBinding:setActionEventActive(actionEvent.actionEventId, self:hasCpCourse())

        actionEvent = spec.actionEvents[InputAction.CP_CLEAR_COURSE]
        g_inputBinding:setActionEventActive(actionEvent.actionEventId, self:hasCpCourse())

        actionEvent = spec.actionEvents[InputAction.CP_GENERATE_COURSE]
        g_inputBinding:setActionEventActive(actionEvent.actionEventId, self:getCanStartCpFieldWork())
    end
end

--- Directly starts a cp job or stops a currently active job.
function CpAIWorker:cpStartStopDriver(isStartedByHud)
    CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, "Start/stop cp helper")
    if self:getIsAIActive() then
        self:stopCurrentAIJob(AIMessageSuccessStoppedByUser.new())
        CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, "Stopped current helper.")
    else
        self:updateAIFieldWorkerImplementData()
        local job = self:getCpStartableJob(isStartedByHud)
        if job == nil then
            CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, "Could not find a CP job to start!")
            return
        end
        if self:getIsCpCourseRecorderActive() then 
            CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, "Could not start cp, as the course recorder is active!")
            return
        end
        if self:getCanStartCp() and job then

            job:applyCurrentState(self, g_currentMission, g_currentMission.playerSystem:getLocalPlayer().farmId, true, true)
            job:setValues()
            local success, message = job:validate()
            if success then
                g_client:getServerConnection():sendEvent(AIJobStartRequestEvent.new(job, self:getOwnerFarmId()))
                CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, "Cp helper started.")
            else
                CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, "Could not start CP helper: %s", tostring(message))
                if message then
                    g_currentMission:showBlinkingWarning("CP: " .. message, 5000)
                end
            end
        else
            CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, "Could not start CP helper!")
        end
    end
end

-----------------------------------------------
--- Status getter functions
-----------------------------------------------

--- Is a cp worker active ?
--- Every cp job should be an instance of type CpAIJob.
function CpAIWorker:getIsCpActive()
    return self:getIsAIActive() and self:getJob() and self:getJob().is_a and self:getJob():is_a(CpAIJob)
end

--- Is cp drive to field work active
function CpAIWorker:getIsCpDriveToFieldWorkActive()
    if not self:getIsCpActive() then
        return false
    end
    local job = self:getJob()
    local task = job:getTaskByIndex(job.currentTaskIndex)
    return task and task.is_a and task:is_a(CpAITaskDriveTo)
end

--- Is a cp job ready to be started?
function CpAIWorker:getCanStartCp()
    --- override
end

--- Gets the job to be started by the hud or the keybinding.
function CpAIWorker:getCpStartableJob()
    --- override
end

--- Gets the additional action event start text,
--- for example the starting point.
function CpAIWorker:getCpStartText()
    --- override
end

--- Makes sure giants isn't turning the motor back on, when we have turned it off.
function CpAIWorker:getCanMotorRun(superFunc, ...)
    if self:getIsCpActive() and self.spec_cpAIWorker.motorDisabled then
        return false
    end
    return superFunc(self, ...)
end

-----------------------------------------------
--- Strategy handling
-----------------------------------------------


--- Used to enable/disable release of the helper
--- and handles post release functionality with for example auto drive.
--- TODO: this might by only called on the client, so 
--- server depended code has to be moved to stopJob or similar code.
function CpAIWorker:stopCurrentAIJob(superFunc, message, ...)
    if message == nil then
        CpUtil.infoVehicle(self, "no stop message was given.")
        return superFunc(self, message, ...)
    end
    
    local job = self:getJob()
    local wasCpActive = self:getIsCpActive()
    if wasCpActive then
        local driveStrategy = self:getCpDriveStrategy()
        if driveStrategy then
            -- TODO: this isn't needed if we do not return a 0 < maxSpeed < 0.5, should either be exactly 0 or greater than 0.5
            local maxSpeed = driveStrategy and driveStrategy:getMaxSpeed()
            if message:isa(AIMessageErrorBlockedByObject) then
                if self.spec_aiFieldWorker.didNotMoveTimer and self.spec_aiFieldWorker.didNotMoveTimer < 0 then
                    if maxSpeed and maxSpeed < 1 then
                        -- disable the Giants timeout which dismisses the AI worker if it does not move for 5 seconds
                        -- since we often stop for instance in convoy mode when waiting for another vehicle to turn
                        -- (when we do this, we set our maxSpeed to 0). So we also check our maxSpeed, this way the Giants timer will
                        -- fire if we are blocked (thus have a maxSpeed > 0 but not moving)
                        CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, 'Overriding the Giants did not move timer, with speed: %.2f', maxSpeed)
                        return
                    else
                        CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, 'Giants did not move timer triggered, with speed: %.2f!', maxSpeed)
                    end
                end
            end
        end
        if not job:isFinishingAllowed(message) then
            return
        end
    end
    CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, "stop message: %s", message:getI18NText())
    superFunc(self, message,...)
end

--- Sets a stop flag to make the driver stop after the worker finished.
function CpAIWorker:cpBrakeToStop()
    local spec = self.spec_cpAIWorker
    spec.brakeToStop = true
end

function CpAIWorker:onUpdate(dt)
    local spec = self.spec_cpAIWorker
    --- TODO: Check if a tick delay should be used for performance similar to AIFieldWorker or not.
    if spec.driveStrategy and self.isServer then
        --- Should drive all CP modes, except fieldwork here.
        spec.driveStrategy:update(dt)
        SpecializationUtil.raiseEvent(self, "onAIFieldWorkerActive")
        if not spec.driveStrategy then
            return
        end
        local tX, tZ, moveForwards, maxSpeedStrategy = spec.driveStrategy:getDriveData(dt)
        local maxSpeed = math.min(maxSpeedStrategy or math.huge, self:getCruiseControlMaxSpeed())
        if not spec.driveStrategy then
            return
        end
        -- same as AIFieldWorker:updateAIFieldWorker(), do the actual driving
        local tY = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, tX, 0, tZ)
        local pX, _, pZ = worldToLocal(self:getAISteeringNode(), tX, tY, tZ)
        if not moveForwards and self.spec_articulatedAxis ~= nil and
                self.spec_articulatedAxis.aiRevereserNode ~= nil then
            pX, _, pZ = worldToLocal(self.spec_articulatedAxis.aiRevereserNode, tX, tY, tZ)
        end
        if not moveForwards and self:getAIReverserNode() ~= nil then
            pX, _, pZ = worldToLocal(self:getAIReverserNode(), tX, tY, tZ)
        end
        local acceleration = 1
        local isAllowedToDrive = maxSpeed ~= 0
        AIVehicleUtil.driveToPoint(self, dt, acceleration,
                isAllowedToDrive, moveForwards, pX, pZ, maxSpeed)
    end
    if spec.brakeToStop then
        local drivableSpec = self.spec_drivable
        if spec.brakeToStop then
            --- Based on the Drivable:brakeToStop() function, but also enables vehicles with a turned cabin.
            local lastSpeed = self:getLastSpeed()
            drivableSpec.lastInputValues.targetSpeed = 0.51
            drivableSpec.lastInputValues.targetDirection = 1
            if AIUtil.isReverseDriving(self) then
                --- Works the same but needs to be inverted for the calculation in the Drivable spec.
                drivableSpec.lastInputValues.targetDirection = self.movingDirection
                drivableSpec.lastInputValues.targetSpeed = lastSpeed + 0.51

            end
            if lastSpeed < 1 then
                --- The brake request gets reset when the vehicle stopped.
                spec.brakeToStop = false
                drivableSpec.lastInputValues.targetSpeed = nil
                drivableSpec.lastInputValues.targetDirection = nil
            end
        end
    end

end

--- Freeze (set speed to 0) of the CP driver, but keep everything up and running, showing all debug
--- drawings, etc. This is for troubleshooting only
function CpAIWorker:freezeCp()
    self:getCpDriveStrategy():freeze()
end

--- Unfreeze, continue work normally.
function CpAIWorker:unfreezeCp()
    self:getCpDriveStrategy():unfreeze()
end

--- Holds the driver for a given amount of milliseconds.
function CpAIWorker:cpHold(ms, fuelSaveAllowed)
    local strategy = self:getCpDriveStrategy()
    if strategy then
        return strategy:hold(ms, fuelSaveAllowed)
    end
end

---@param strategy AIDriveStrategyCourse
function CpAIWorker:startCpWithStrategy(strategy)
    local spec = self.spec_cpAIWorker
    spec.driveStrategy = strategy
end

--- Called to stop the driver after stopping of a vehicle.
function CpAIWorker:stopCpDriver(isJobFinished)
    --- Reset the flag.
    local spec = self.spec_cpAIWorker
    spec.motorDisabled = false
    if spec.driveStrategy then
        spec.driveStrategy:delete()
        spec.driveStrategy = nil
    end
    if not isJobFinished then
        --- Job is not yet finished, 
        --- so no need to stop the 
        --- driver and fold and so on .. 
        return
    end
    if self.isServer then
        WheelsUtil.updateWheelsPhysics(self, 0, 0, 0, true, true)
    end
    if self.brake then
        self:brake(1)
    end
    self:stopVehicle()
    self:setCruiseControlState(Drivable.CRUISECONTROL_STATE_OFF, true)
    self:cpBrakeToStop()
    local actionController = self.rootVehicle.actionController

    if actionController ~= nil then
        actionController:resetCurrentState()
    end
    self:raiseAIEvent("onAIFieldWorkerEnd", "onAIImplementEnd")
end

function CpAIWorker:getCpDriveStrategy()
    local spec = self.spec_cpAIWorker
    return spec.driveStrategy
end

--- Fixes the ai reverse node rotation for articulated axis vehicles,
--- if the node is pointing backwards and not forwards.
--- TODO: Consider consolidation with AIUtil.getArticulatedAxisVehicleReverserNode
function CpAIWorker:getAIReverserNode(superFunc)
    local spec = self.spec_cpAIWorker
    -- if not self:getIsCpActive() then
    --     return superFunc(self)
    -- end
    if g_vehicleConfigurations:get(self, "articulatedAxisReverseNodeInverted") then
        if not spec.articulatedAxisReverseNode then
            spec.articulatedAxisReverseNode = CpUtil.createNode(
                    "cpAiRevereserNode", 0, 0, 0,
                    self.rootNode)
        end
        return spec.articulatedAxisReverseNode
    end
    return superFunc(self)
end

--- Fixes the Direction for the platinum wheel loader, as
--- their direction is not updated base on the rotation.
--- So we use the parent node of the arm tool node.
---@param superFunc any
function CpAIWorker:getAIDirectionNode(superFunc)
    if not self:getIsCpActive() then
        return superFunc(self)
    end
    local movingToolIx = g_vehicleConfigurations:get(self, "fixWheelLoaderDirectionNodeByMovingToolIx")
    if movingToolIx ~= nil then
        return getParent(self.spec_cylindered.movingTools[movingToolIx].node)
    end
    return superFunc(self)
end

function CpAIWorker:stopFieldWorker(superFunc, ...)
    --- Reset the flag.
    self.spec_cpAIWorker.motorDisabled = false
    superFunc(self, ...)
end

--- Auto drive stop
function CpAIWorker:onStopAutoDrive(isPassingToCP, isStartingAIVE)
    if g_server then
        CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, "isPassingToCP: %s, isStartingAIVE: %s", tostring(isPassingToCP), tostring(isStartingAIVE))
        if self.ad.restartCP then
            --- Is restarted for refilling or unloading.
            CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, "Was refilled/unloaded by AD.")
        else
            --- Is sent to a field.
            CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, self, "Was sent to field by AD.")
        end
    end
end

--- Auto drive start
function CpAIWorker:onStartAutoDrive()
    if g_server then
        if self.ad.restartCP then
            --- Use last job parameters.
            --- Only the start point needs to be forced back!
            SpecializationUtil.raiseEvent(self, "onCpADRestarted")
        elseif CpUtil.getCurrentVehicle() == self then
            --- Apply hud variables
            SpecializationUtil.raiseEvent(self, "onCpADStartedByPlayer")
        end
    elseif CpUtil.getCurrentVehicle() == self then
        --- Apply hud variables
        SpecializationUtil.raiseEvent(self, "onCpADStartedByPlayer")
        CpJobStartAtLastWpSyncRequestEvent.sendEvent(self)
    end
end

---------------------------------------------
--- Console commands
---------------------------------------------

function CpAIWorker.registerConsoleCommands()
    g_consoleCommands:registerConsoleCommand("cpVehicleOnWorkStartTest",
            "Raise the field work start event.",
            "consoleCommandRaiseWorkStart", CpAIWorker)
    g_consoleCommands:registerConsoleCommand("cpSettingsPrintJob",
            "Prints the current job parameters",
            "consoleCommandPrintCurrentSelectedJobParameters", CpAIWorker)
    --- TODO: Adding functions to execute the lowering, raising and fieldwork end events.
end

--- Raises the fieldwork start event with implement controllers installed,
--- as these might turn on implements, that otherwise aren't turned on or
--- disables the unfolding of a given implement.
function CpAIWorker:consoleCommandRaiseWorkStart()
    local vehicle = CpUtil.getCurrentVehicle()
    if not vehicle then
        CpUtil.info("Not entered a valid vehicle!")
        return
    end
    local controllers = {}
    for i, childVehicle in pairs(vehicle:getChildVehicles()) do
        if childVehicle.spec_foldable then
            --- TODO: Adding the other implement controllers that are needed here.
            table.insert(controllers, FoldableController(vehicle, childVehicle))
        end
    end
    vehicle:raiseAIEvent("onAIFieldWorkerStart", "onAIImplementStart")
    for _, c in pairs(controllers) do
        c:delete()
    end
end

--- Either prints all settings or a desired setting by the name or index in the setting table.
---@param name any
function CpAIWorker:consoleCommandPrintCurrentSelectedJobParameters(name)
    local vehicle = CpUtil.getCurrentVehicle()
    if not vehicle or vehicle.getCpStartableJob == nil then
        CpUtil.info("Not entered a valid vehicle!")
        return
    end
    local job = vehicle:getCpStartableJob()
    if not job then
        CpUtil.infoVehicle(vehicle, "No valid job found!")
        return
    end
    local parameters = job:getCpJobParameters()
    if name == nil then
        CpUtil.infoVehicle(vehicle, "%s Job parameters", tostring(parameters))
        return
    end
    local num = tonumber(name)
    if num then
        CpUtil.infoVehicle(vehicle, tostring(parameters.settings[num]))
        return
    end
    CpUtil.infoVehicle(vehicle, tostring(parameters[name]))
end