--- Bale finder job.
---@class CpAIJobBaleFinder : CpAIJobFieldWork
---@field selectedFieldPlot FieldPlot
CpAIJobBaleFinder = CpObject(CpAIJob)
CpAIJobBaleFinder.name = "BALE_FINDER_CP"
CpAIJobBaleFinder.jobName = "CP_job_baleCollect"
function CpAIJobBaleFinder:init(isServer)
	CpAIJob.init(self, isServer)
	self.selectedFieldPlot = FieldPlot(true)
    self.selectedFieldPlot:setVisible(false)
	self.selectedFieldPlot:setBrightColor()
end

function CpAIJobBaleFinder:setupTasks(isServer)
	CpAIJob.setupTasks(self, isServer)
	self.baleFinderTask = CpAITaskBaleFinder(isServer, self)
	self:addTask(self.baleFinderTask)
	self.unloadTask = CpAITaskDriveToPointUnload(isServer, self)
	self:addTask(self.unloadTask)
	
end

function CpAIJobBaleFinder:setupJobParameters()
	CpAIJob.setupJobParameters(self)
    self:setupCpJobParameters(CpBaleFinderJobParameters(self))
end

function CpAIJobBaleFinder:getIsAvailableForVehicle(vehicle, cpJobsAllowed)
	return CpAIJob.getIsAvailableForVehicle(self, vehicle, cpJobsAllowed) and vehicle.getCanStartCpBaleFinder and vehicle:getCanStartCpBaleFinder() -- TODO_25
end

function CpAIJobBaleFinder:getCanStartJob()
	return self:getVehicle():cpGetFieldPolygon() ~= nil
end

function CpAIJobBaleFinder:applyCurrentState(vehicle, mission, farmId, isDirectStart, isStartPositionInvalid)
	CpAIJob.applyCurrentState(self, vehicle, mission, farmId, isDirectStart)
	self.cpJobParameters:validateSettings()

	self:copyFrom(vehicle:getCpBaleFinderJob())
	local x, z = self.cpJobParameters.fieldPosition:getPosition()
	-- no field position from the previous job, use the vehicle's current position
	if x == nil or z == nil then
		x, _, z = getWorldTranslation(vehicle.rootNode)
		self.cpJobParameters.fieldPosition:setPosition(x, z)
	end
end

function CpAIJobBaleFinder:setValues()
	CpAIJob.setValues(self)
	local vehicle = self.vehicleParameter:getVehicle()
	self.baleFinderTask:setVehicle(vehicle)
	self.unloadTask:setVehicle(vehicle)
	self.unloadTask:setTarget(
		g_graph:getTargetByUniqueID(self.cpJobParameters.unloadTargetPoint:getValue()))
end

--- Called when parameters change, scan field
function CpAIJobBaleFinder:validate(farmId)
	local isValid, isRunning, errorMessage = CpAIJob.validate(self, farmId)
	if not isValid then
		return isValid, errorMessage
	end
	local vehicle = self.vehicleParameter:getVehicle()
	if vehicle then 
		vehicle:applyCpBaleFinderJobParameters(self)
	end
	--------------------------------------------------------------
	--- Validate field setup
	--------------------------------------------------------------
	isValid, isRunning, errorMessage = self:detectFieldBoundary(isValid, errorMessage)
	--------------------------------------------------------------
	--- Validate Unload target point
	--------------------------------------------------------------
	if self.cpJobParameters.unloadTargetPointEnabled:getValue() then 
		if self.cpJobParameters.unloadTargetPoint:getValue() < 0 then 
			return false, g_i18n:getText("CP_error_no_target_selected")
		end
	end
	
	-- if the field detection is still running, it's ok
	return isValid or isRunning, errorMessage
end

function CpAIJobBaleFinder:onFieldBoundaryDetectionFinished(vehicle, fieldPolygon, islandPolygons)
	if fieldPolygon then
		self.selectedFieldPlot:setWaypoints(fieldPolygon)
		self.selectedFieldPlot:setVisible(true)
		self:callFieldBoundaryDetectionFinishedCallback(true)
	else
		self.selectedFieldPlot:setVisible(false)
		self:callFieldBoundaryDetectionFinishedCallback(false, 'CP_error_field_detection_failed')
	end
end

function CpAIJobBaleFinder:draw(map, isOverviewMap)
	CpAIJob.draw(self, map, isOverviewMap)
	if not isOverviewMap then
		self.selectedFieldPlot:draw(map)
	end
end

--- Gets the additional task description shown.
function CpAIJobBaleFinder:getDescription()
	local desc = CpAIJob.getDescription(self)
	local currentTask = self:getTaskByIndex(self.currentTaskIndex)
    if currentTask == self.driveToTask then
		desc = desc .. " - " .. g_i18n:getText("ai_taskDescriptionDriveToField")
	elseif currentTask == self.baleFinderTask then
		local vehicle = self:getVehicle()
		if vehicle and AIUtil.hasChildVehicleWithSpecialization(vehicle, BaleWrapper) then
			desc = desc .. " - " .. g_i18n:getText("CP_ai_taskDescriptionWrapsBales")
		else 
			desc = desc .. " - " .. g_i18n:getText("CP_ai_taskDescriptionCollectsBales")
		end
	end
	return desc
end

function CpAIJobBaleFinder:getIsLooping()
	return self.cpJobParameters.unloadTargetPointEnabled:getValue()
end