--- Street job.
---@class CpAIJobStreet : CpAIJob
CpAIJobStreet = CpObject(CpAIJob)
CpAIJobStreet.name = "STREET_WORKER_CP"
CpAIJobStreet.jobName = "CP_job_street"
function CpAIJobStreet:init(isServer)
	CpAIJob.init(self, isServer)

end

function CpAIJobStreet:setupTasks(isServer)
	self.driveToPointTask = CpAITaskDriveToPoint(isServer, self)
	self.driveToLoadingTask = CpAITaskDriveToPointLoad(isServer, self)
	self.driveToUnloadingTask = CpAITaskDriveToPointUnload(isServer, self)
end

function CpAIJobStreet:onPreStart()
	self:removeTask(self.driveToPointTask)
	self:removeTask(self.driveToLoadingTask)
	self:removeTask(self.driveToUnloadingTask)
	if self.cpJobParameters.loadUnloadTargetMode:getValue() == CpStreetJobParameters.UNLOAD_AT_TARGET then 
		self:addTask(self.driveToUnloadingTask)
	elseif self.cpJobParameters.loadUnloadTargetMode:getValue() == CpStreetJobParameters.LOAD_AND_UNLOAD then
		self:addTask(self.driveToLoadingTask)
		self:addTask(self.driveToUnloadingTask)
	else
		self:addTask(self.driveToPointTask)
	end
	self.driveToPointTask:setTarget(
		g_graph:getTargetByUniqueID(self.cpJobParameters.unloadTargetPoint:getValue()))
	self.driveToUnloadingTask:setTarget(
		g_graph:getTargetByUniqueID(self.cpJobParameters.unloadTargetPoint:getValue()))
	self.driveToLoadingTask:setTarget(
		g_graph:getTargetByUniqueID(self.cpJobParameters.loadTargetPoint:getValue()))
end

function CpAIJobStreet:setupJobParameters()
	CpAIJob.setupJobParameters(self)
    self:setupCpJobParameters(CpStreetJobParameters(self))
end

function CpAIJobStreet:getCanStartJob()
	return true
end

function CpAIJobStreet:getStartTaskIndex()
	--- TODO Filltype check ??
	return 1
end

function CpAIJobStreet:applyCurrentState(vehicle, mission, farmId, isDirectStart, isStartPositionInvalid)
	CpAIJob.applyCurrentState(self, vehicle, mission, farmId, isDirectStart)
	self.cpJobParameters:validateSettings()

	self:copyFrom(vehicle:getCpStreetWorkerJob())
	
end

function CpAIJobStreet:setValues()
	CpAIJob.setValues(self)
	local vehicle = self.vehicleParameter:getVehicle()
	self.driveToPointTask:setVehicle(vehicle)
	self.driveToUnloadingTask:setVehicle(vehicle)
	self.driveToLoadingTask:setVehicle(vehicle)
end

--- Called when parameters change, scan field
function CpAIJobStreet:validate(farmId)
	local isValid, isRunning, errorMessage = CpAIJob.validate(self, farmId)
	if not isValid then
		return isValid, errorMessage
	end
	local vehicle = self.vehicleParameter:getVehicle()
	if vehicle then 
		vehicle:applyCpStreetWorkerJobParameters(self)
	end
	if self.cpJobParameters.unloadTargetPoint:getValue() < 0 then 
		return false, g_i18n:getText("CP_error_no_target_selected")
	end
	if self.cpJobParameters.loadUnloadTargetMode:getValue() == CpStreetJobParameters.LOAD_AND_UNLOAD then 
		if self.cpJobParameters.loadTargetPoint:getValue() < 0 then 
			return false, g_i18n:getText("CP_error_no_target_selected")
		end
	elseif self.cpJobParameters.loadUnloadTargetMode:getValue() == CpStreetJobParameters.UNLOAD_AT_TARGET then 
		--- TODO filllevel check
	end
	return isValid or isRunning, errorMessage
end

function CpAIJobStreet:draw(map, isOverviewMap)
	CpAIJob.draw(self, map, isOverviewMap)
	-- if not isOverviewMap then
	-- 	self.selectedFieldPlot:draw(map)
	-- end
end

--- Gets the additional task description shown.
function CpAIJobStreet:getDescription()
	local desc = CpAIJob.getDescription(self)
	-- local currentTask = self:getTaskByIndex(self.currentTaskIndex)
    -- if currentTask == self.driveToTask then
	-- 	desc = desc .. " - " .. g_i18n:getText("ai_taskDescriptionDriveToField")
	-- elseif currentTask == self.baleFinderTask then
	-- 	local vehicle = self:getVehicle()
	-- 	if vehicle and AIUtil.hasChildVehicleWithSpecialization(vehicle, BaleWrapper) then
	-- 		desc = desc .. " - " .. g_i18n:getText("CP_ai_taskDescriptionWrapsBales")
	-- 	else 
	-- 		desc = desc .. " - " .. g_i18n:getText("CP_ai_taskDescriptionCollectsBales")
	-- 	end
	-- end
	return desc
end
