--- AI job for the silo driver.
---@class CpAIJobBunkerSilo : CpAIJob
CpAIJobBunkerSilo = CpObject(CpAIJob)
CpAIJobBunkerSilo.name = "BUNKER_SILO_CP"
CpAIJobBunkerSilo.jobName = "CP_job_bunkerSilo"
function CpAIJobBunkerSilo:init(isServer)
	CpAIJob.init(self, isServer)
	self.hasValidPosition = nil 
	self.bunkerSilo = nil
end

function CpAIJobBunkerSilo:setupTasks(isServer)
	-- this will add a standard driveTo task to drive to the target position selected by the user
	CpAIJob.setupTasks(self, isServer)
	
	self.bunkerSiloTask = CpAITaskBunkerSilo(isServer, self)
	self:addTask(self.bunkerSiloTask)
end

function CpAIJobBunkerSilo:setupJobParameters()
	CpAIJob.setupJobParameters(self)
    self:setupCpJobParameters(CpBunkerSiloJobParameters(self))
end

function CpAIJobBunkerSilo:getIsAvailableForVehicle(vehicle, cpJobsAllowed)
	return CpAIJob.getIsAvailableForVehicle(self, vehicle, cpJobsAllowed) and vehicle.getCanStartCpBunkerSiloWorker and vehicle:getCanStartCpBunkerSiloWorker() -- TODO_25
end

function CpAIJobBunkerSilo:getCanStartJob()
	return self.hasValidPosition
end

function CpAIJobBunkerSilo:applyCurrentState(vehicle, mission, farmId, isDirectStart)
	CpAIJob.applyCurrentState(self, vehicle, mission, farmId, isDirectStart)
	
	self:copyFrom(vehicle:getCpBunkerSiloWorkerJob())

	local x, z = self.cpJobParameters.siloPosition:getPosition()

	-- no silo position from the previous job, use the vehicle's current position
	if x == nil or z == nil then
		x, _, z = getWorldTranslation(vehicle.rootNode)
		self.cpJobParameters.siloPosition:setPosition(x, z)
	end

end

--- Checks the bunker silo position setting.
function CpAIJobBunkerSilo:validateBunkerSiloSetup(isValid, errorMessage)
	
	if not isValid then 
		return isValid, errorMessage
	end
	self.hasValidPosition = false 
	self.bunkerSilo = nil
	-- everything else is valid, now find the bunker silo.
	local tx, tz = self.cpJobParameters.siloPosition:getPosition()
	self.hasValidPosition, self.bunkerSilo =  g_bunkerSiloManager:getBunkerSiloAtPosition(tx, tz)
	--[[	
	if not self.hasValidPosition and self.isDirectStart then 
		local vehicle = self:getVehicle()
		if vehicle then
			local x, _, z
			x, _, z = getWorldTranslation(Markers.getFrontMarkerNode(vehicle))
			self.hasValidPosition, self.bunkerSilo =  g_bunkerSiloManager:getBunkerSiloAtPosition(x, z)
			if not self.hasValidPosition then 
				x, _, z = getWorldTranslation(Markers.getBackMarkerNode(vehicle))
				self.hasValidPosition, self.bunkerSilo =  g_bunkerSiloManager:getBunkerSiloAtPosition(x, z)
			end
		end
	end
	]]--
	self.bunkerSiloTask:setSilo(self.bunkerSilo)
	
	if not self.hasValidPosition or self.bunkerSilo == nil then 
		return false, g_i18n:getText("CP_error_no_bunkerSilo_found")
	end
	return true, ''
end

function CpAIJobBunkerSilo:setValues()
	CpAIJob.setValues(self)
	local vehicle = self.vehicleParameter:getVehicle()
	self.bunkerSiloTask:setVehicle(vehicle)
end

--- Called when parameters change, scan field
function CpAIJobBunkerSilo:validate(farmId)
	local isValid, errorMessage = CpAIJob.validate(self, farmId)
	if not isValid then
		return isValid, errorMessage
	end
	local vehicle = self.vehicleParameter:getVehicle()
	if vehicle then 
		vehicle:applyCpBunkerSiloWorkerJobParameters(self)
	end
	isValid, errorMessage = self:validateBunkerSiloSetup(isValid, errorMessage)
	if not isValid then
		return isValid, errorMessage
	end
	return true, ''
end

function CpAIJobBunkerSilo:draw(map, isOverviewMap)
	CpAIJob.draw(self, map, isOverviewMap)
	if not isOverviewMap then
		g_bunkerSiloManager:drawSilos(map, self.bunkerSilo)
	end
end

function CpAIJobBunkerSilo:readStream(streamId, connection)
	CpAIJob.readStream(self, streamId, connection)
	
	local x, z = self.cpJobParameters.siloPosition:getPosition()
	self.hasValidPosition, self.bunkerSilo =  g_bunkerSiloManager:getBunkerSiloAtPosition(x, z)
	self.bunkerSiloTask:setSilo(self.bunkerSilo)
end

--- Gets the additional task description shown.
function CpAIJobBunkerSilo:getDescription()
	local desc = CpAIJob.getDescription(self)
	local currentTask = self:getTaskByIndex(self.currentTaskIndex)
    if currentTask == self.driveToTask then
		desc = desc .. " - " .. g_i18n:getText("ai_taskDescriptionDriveToField")
	elseif currentTask == self.bunkerSiloTask then
		desc = desc .. " - " .. g_i18n:getText("CP_ai_taskDescriptionWorksInTheSilo")
	end
	return desc
end