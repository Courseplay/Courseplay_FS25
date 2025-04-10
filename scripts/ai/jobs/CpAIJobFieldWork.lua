--- AI job derived of CpAIJob.
if CpAIJobFieldWork == nil then
    -- create class only on game load once, otherwise just overwrite the members, so the class can be reloaded without
    -- restarting the game
    ---@class CpAIJobFieldWork : CpAIJob
    CpAIJobFieldWork = CpObject(CpAIJob)
end
CpAIJobFieldWork.name = "FIELDWORK_CP"
CpAIJobFieldWork.jobName = "CP_job_fieldWork"
CpAIJobFieldWork.GenerateButton = "FIELDWORK_BUTTON"
function CpAIJobFieldWork:init(isServer)
    CpAIJob.init(self, isServer)
    self.foundVines = nil
    self.selectedFieldPlot = FieldPlot(true)
    self.selectedFieldPlot:setVisible(false)
    self.selectedFieldPlot:setBrightColor(true)
    self.courseGeneratorInterface = CourseGeneratorInterface()
end

function CpAIJobFieldWork:setupTasks(isServer)
    -- this will add a standard driveTo task to drive to the target position selected by the user
    CpAIJob.setupTasks(self, isServer)
    -- then we add our own driveTo task to drive from the target position to the waypoint where the
    -- fieldwork starts (first waypoint or the one we worked on last)
    self.attachHeaderTask = CpAITaskAttachHeader(isServer, self)
    self.driveToFieldWorkStartTask = CpAITaskDriveTo(isServer, self)
    self.fieldWorkTask = CpAITaskFieldWork(isServer, self)
    self.unloadTask = CpAITaskDriveToPointUnload(isServer, self)
    self.refillTask = CpAITaskDriveToPointLoad(isServer, self)
    self.refillTaskExtra = CpAITaskDriveToPointLoad(isServer, self)
end

function CpAIJobFieldWork:onPreStart()
    CpAIJob.onPreStart(self)
    self:removeTask(self.attachHeaderTask)
    self:removeTask(self.driveToFieldWorkStartTask)
    self:removeTask(self.fieldWorkTask)
    self:removeTask(self.unloadTask)
    self:removeTask(self.refillTask)
    self:removeTask(self.refillTaskExtra)
    
    local vehicle = self:getVehicle()
    if vehicle and (AIUtil.hasCutterOnTrailerAttached(vehicle)
        or AIUtil.hasCutterAsTrailerAttached(vehicle)) then
        --- Only add the attach header task, if needed.
        self:addTask(self.attachHeaderTask)
    end
    self:addTask(self.driveToFieldWorkStartTask)
    self:addTask(self.fieldWorkTask)
    if not self.cpJobParameters:isUnloadingDisabled() then 
        self:addTask(self.unloadTask)
    elseif not self.cpJobParameters:isLoadingDisabled() then  
        self:addTask(self.refillTask)
        if not self.cpJobParameters:isUnloadRefillExtraDisabled() then
            self:addTask(self.refillTaskExtra)
        end
    end
end

function CpAIJobFieldWork:setupJobParameters()
    CpAIJob.setupJobParameters(self)
    self:setupCpJobParameters(CpFieldWorkJobParameters(self))
end

function CpAIJobFieldWork:isFinishingAllowed(message)
    local nextTaskIndex = self:getNextTaskIndex()
	if message:isa(AIMessageErrorOutOfFill) and self.cpJobParameters:isUnloadOrRefillingDisabled() then
        --- At least one implement type needs to be refilled.

        local vehicle = self:getVehicle()
        local setting = vehicle:getCpSettings().refillOnTheField

        if setting:getValue() == CpVehicleSettings.REFILL_ON_FIELD_DISABLED then
            return true
        elseif setting:getValue() == CpVehicleSettings.REFILL_ON_FIELD_WAITING then
            if self.currentTaskIndex == self.fieldWorkTask.taskIndex then
                self.fieldWorkTask:setWaitingForRefillingActive()
            end
        elseif setting:getValue() == CpVehicleSettings.REFILL_ON_FIELD_ACTIVE then
            --- TODO_25 Add driving to trailer for refilling here and so on ..
            self.fieldWorkTask:skip()
        end
        return false
    end
    return CpAIJob.isFinishingAllowed(self, message)
end

---@param vehicle table
---@param mission table
---@param farmId number
---@param isDirectStart boolean disables the drive to by giants
---@param resetToVehiclePosition boolean resets the drive to target position by giants and the field position to the vehicle position.
function CpAIJobFieldWork:applyCurrentState(vehicle, mission, farmId, isDirectStart, resetToVehiclePosition)
    CpAIJob.applyCurrentState(self, vehicle, mission, farmId, isDirectStart)
    if resetToVehiclePosition then
        -- set the start and the field position to the vehicle's position (
        local x, _, z = getWorldTranslation(vehicle.rootNode)
        local dirX, _, dirZ = localDirectionToWorld(vehicle.rootNode, 0, 0, 1)
        local angle = MathUtil.getYRotationFromDirection(dirX, dirZ)

        self.cpJobParameters.startPosition:setPosition(x, z)
        self.cpJobParameters.startPosition:setAngle(angle)

        self.cpJobParameters.fieldPosition:setPosition(x, z)
    else
        local x, z = self.cpJobParameters.fieldPosition:getPosition()
        if x == nil or z == nil then
            -- if there is no field position set, set it to the vehicle's position
            x, _, z = getWorldTranslation(vehicle.rootNode)
            self.cpJobParameters.fieldPosition:setPosition(x, z)
        end
    end
    local fieldPolygon = vehicle:cpGetFieldPolygon()
    if fieldPolygon then
        -- if we already have a field polygon, show it
        self.selectedFieldPlot:setWaypoints(fieldPolygon)
        self.selectedFieldPlot:setVisible(true)
    end
end

function CpAIJobFieldWork:onFieldBoundaryDetectionFinished(vehicle, fieldPolygon, islandPolygons)
    if fieldPolygon then
        local x, z = vehicle:cpGetFieldPosition()
        self.foundVines = g_vineScanner:findVineNodesInField(fieldPolygon, x, z, self.customField ~= nil)
        if self.foundVines then
            CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, vehicle, "Found vine nodes, generating a vine field border.")
            fieldPolygon = g_vineScanner:getCourseGeneratorVertices(0, x, z)
        end
        self.selectedFieldPlot:setWaypoints(fieldPolygon)
        self.selectedFieldPlot:setVisible(true)
    else
        self.selectedFieldPlot:setVisible(false)
        self:callFieldBoundaryDetectionFinishedCallback(false, 'CP_error_field_detection_failed')
    end
    self:callFieldBoundaryDetectionFinishedCallback(true)
end

function CpAIJobFieldWork:setValues()
    CpAIJob.setValues(self)
    local vehicle = self.vehicleParameter:getVehicle()
    self.driveToFieldWorkStartTask:reset()
    self.driveToFieldWorkStartTask:setVehicle(vehicle)
    self.attachHeaderTask:setVehicle(vehicle)
    self.fieldWorkTask:setVehicle(vehicle)
end

--- Called when parameters change, scan field
---@param farmId number not used
function CpAIJobFieldWork:validate(farmId)
    local isValid, isRunning, errorMessage = CpAIJob.validate(self, farmId)
    if not isValid then
        return isValid, errorMessage
    end
    local vehicle = self.vehicleParameter:getVehicle()

    --- Only check the valid field position in the in game menu.
    if not self.isDirectStart then
        isValid, isRunning, errorMessage = self:detectFieldBoundary()
        if not isValid then
            return isValid, errorMessage
        end
        self.cpJobParameters:validateSettings()
    end

    if not self.cpJobParameters:isUnloadOrRefillingDisabled() then
        if self.cpJobParameters.unloadRefillTargetPoint:getValue() < 0 then 
			return false, g_i18n:getText("CP_error_no_target_selected")
		end
        if not self.cpJobParameters:isUnloadRefillExtraDisabled() then
            if self.cpJobParameters.unloadRefillTargetPointExtra:getValue() < 0 then 
                return false, g_i18n:getText("CP_error_no_target_selected")
            end
        end
        --- TODO fill type evaluation
    end

    if not vehicle:hasCpCourse() then
        return false, g_i18n:getText("CP_error_no_course")
    end
    return true, ''
end

function CpAIJobFieldWork:draw(map, isOverviewMap)
	CpAIJob.draw(self, map, isOverviewMap)
    if not isOverviewMap then
        if self.selectedFieldPlot then
            self.selectedFieldPlot:draw(map)
        end
    end
end

function CpAIJobFieldWork:getCanGenerateFieldWorkCourse()
    local vehicle = self:getVehicle()
    return vehicle and vehicle:cpGetFieldPolygon() ~= nil and not vehicle:cpIsFieldBoundaryDetectionRunning()
end

-- To pass an alignment course from the drive to fieldwork start to the fieldwork, so the
-- fieldwork strategy can continue the alignment course set up by the drive to fieldwork start strategy.
function CpAIJobFieldWork:setStartFieldWorkCourse(course, ix)
    self.startFieldWorkCourse = course
    self.startFieldWorkCourseIx = ix
end

function CpAIJobFieldWork:getStartFieldWorkCourse()
    return self.startFieldWorkCourse, self.startFieldWorkCourseIx
end

--- Is course generation allowed ?
function CpAIJobFieldWork:isCourseGenerationAllowed()
    local vehicle = self:getVehicle()
    --- Disables the course generation for bale loaders and wrappers.
    local baleFinderAllowed = vehicle and vehicle:getCanStartCpBaleFinder()
    return self:getCanGenerateFieldWorkCourse() and not baleFinderAllowed
end

function CpAIJobFieldWork:getCanStartJob()
    local vehicle = self:getVehicle()
    return vehicle and vehicle:hasCpCourse()
end

--- Button callback to generate a field work course.
function CpAIJobFieldWork:onClickGenerateFieldWorkCourse(callback)
    local vehicle = self.vehicleParameter:getVehicle()
    local settings = vehicle:getCourseGeneratorSettings()

    local tx, tz = self.cpJobParameters.fieldPosition:getPosition()
    local ok, course
    if self.foundVines then
        local vineSettings = vehicle:getCpVineSettings()
        local vertices, width, startingPoint, rowAngleDeg = g_vineScanner:getCourseGeneratorVertices(
                vineSettings.vineCenterOffset:getValue(),
                tx, tz
        )
        ok, course = self.courseGeneratorInterface:generateVineCourse(
                vertices,
                startingPoint,
                vehicle,
                width,
                AIUtil.getTurningRadius(vehicle),
                rowAngleDeg,
                vineSettings.vineRowsToSkip:getValue(),
                -- no multitools until we fix the generation for vines
                1,
                g_vineScanner:getLines(),
                vineSettings.vineCenterOffset:getValue())
        callback(course)
    else
        self.courseGeneratorInterface:startGeneration(
            { x = tx, z = tz },
            vehicle,
            settings,
            nil,
            callback,
            -- this button is only enabled if we already detected the field boundary, so use the existing polygons
            vehicle:cpGetFieldPolygon(),
            vehicle:cpGetIslandPolygons())
    end
    return true
end

function CpAIJobFieldWork:isPipeOnLeftSide(vehicle)
    local pipeObject = AIUtil.getImplementOrVehicleWithSpecialization(vehicle, Pipe)
    if pipeObject and SpecializationUtil.hasSpecialization(Combine, pipeObject.specializations) then
        --- The controller measures the pipe attributes on creation.
        local controller = PipeController(vehicle, pipeObject, true)
        local isPipeOnLeftSide = controller:isPipeOnTheLeftSide()
        controller:delete()
        return isPipeOnLeftSide
    else
        return true
    end
end

function CpAIJobFieldWork:getIsAvailableForVehicle(vehicle, cpJobsAllowed)
    return CpAIJob.getIsAvailableForVehicle(self, vehicle, cpJobsAllowed) and vehicle.getCanStartCpFieldWork and vehicle:getCanStartCpFieldWork() -- TODO_25
end

--- Ugly hack to fix a mp problem from giants, where the helper is not always reset correctly on the client side.
function CpAIJobFieldWork:stop(aiMessage)
    CpAIJob.stop(self, aiMessage)

    local vehicle = self.vehicleParameter:getVehicle()
    if vehicle and vehicle.spec_aiFieldWorker.isActive then
        vehicle.spec_aiFieldWorker.isActive = false
    end
end

function CpAIJobFieldWork:hasFoundVines()
    return self.foundVines
end

function CpAIJobFieldWork:setStartPosition(startPosition)
    if self.fieldWorkTask then
        self.fieldWorkTask:setStartPosition(startPosition)
    end
end

--- Gets the additional task description shown.
function CpAIJobFieldWork:getDescription()
	local desc = CpAIJob.getDescription(self)
	local currentTask = self:getTaskByIndex(self.currentTaskIndex)
    if currentTask == self.driveToTask then
		desc = desc .. " - " .. g_i18n:getText("ai_taskDescriptionDriveToField")
	elseif currentTask == self.fieldWorkTask then
		desc = desc .. " - " .. g_i18n:getText("ai_taskDescriptionFieldWork")
	elseif currentTask == self.attachHeaderTask then
		desc = desc .. " - " .. g_i18n:getText("CP_ai_taskDescriptionAttachHeader")
	end
	return desc
end
