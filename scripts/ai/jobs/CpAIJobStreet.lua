--- Street job.
---@class CpAIJobStreet : CpAIJob
CpAIJobStreet = CpObject(CpAIJob)
CpAIJobStreet.name = "STREET_WORKER_CP"
CpAIJobStreet.jobName = "CP_job_street"
function CpAIJobStreet:init(isServer)
	CpAIJob.init(self, isServer)

end

function CpAIJobStreet:setupTasks(isServer)
	-- CpAIJob.setupTasks(self, isServer)
	self.driveToPointTask = CpAITaskDriveToPoint(isServer, self)
	self:addTask(self.driveToPointTask)
end

function CpAIJobStreet:onPreStart()
	self.driveToPointTask:setTarget(
		g_graph:getTargetByUniqueID(self.cpJobParameters.unloadTargetPoint:getValue()))
end


function CpAIJobStreet:setupJobParameters()
	CpAIJob.setupJobParameters(self)
    self:setupCpJobParameters(CpStreetJobParameters(self))
end

function CpAIJobStreet:getIsAvailableForVehicle(vehicle, cpJobsAllowed)
	return CpAIJob.getIsAvailableForVehicle(self, vehicle, cpJobsAllowed)
end

function CpAIJobStreet:getCanStartJob()
	return true
end

function CpAIJobStreet:applyCurrentState(vehicle, mission, farmId, isDirectStart, isStartPositionInvalid)
	CpAIJob.applyCurrentState(self, vehicle, mission, farmId, isDirectStart)
	self.cpJobParameters:validateSettings()

	-- self:copyFrom(vehicle:getCpBaleFinderJob())
	
end

function CpAIJobStreet:setValues()
	CpAIJob.setValues(self)
	local vehicle = self.vehicleParameter:getVehicle()
	self.driveToPointTask:setVehicle(vehicle)
end

--- Called when parameters change, scan field
function CpAIJobStreet:validate(farmId)
	local isValid, isRunning, errorMessage = CpAIJob.validate(self, farmId)
	if not isValid then
		return isValid, errorMessage
	end
	local vehicle = self.vehicleParameter:getVehicle()
	if vehicle then 
		-- vehicle:applyCpBaleFinderJobParameters(self)
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
