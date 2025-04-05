--- Basic cp job.
--- Every cp job should be derived from this job.
---@class CpAIJob : AIJob
---@field namedParameters table
---@field jobTypeIndex number
---@field isDirectStart boolean
---@field getTaskByIndex function
---@field addNamedParameter function
---@field addTask function
---@field currentTaskIndex number
---@field superClass function
---@field getIsLooping function
---@field resetTasks function
---@field skipCurrentTask function
---@field tasks table
---@field groupedParameters table
---@field isServer boolean
---@field helperIndex number
CpAIJob = CpObject(AIJob, AIJob.new)
function CpAIJob:init(isServer)
	self.isDirectStart = false
	self.debugChannel = CpDebug.DBG_FIELDWORK
	self:setupJobParameters()
	self:setupTasks(isServer)
end 

---@param task CpAITask
function CpAIJob:removeTask(task)
	if task.taskIndex then
		table.remove(self.tasks, task.taskIndex)
		for i = #self.tasks, task.taskIndex, -1 do 
			self.tasks[i].taskIndex = self.tasks[i].taskIndex - 1
		end
	end
	task.taskIndex = nil
end

--- Setup all tasks.
function CpAIJob:setupTasks(isServer)
	if true then 
		self.driveToTask = CpAITaskDriveToPoint(isServer, self)
	else 
		self.driveToTask = AITaskDriveTo.new(isServer, self)
	end
	self:addTask(self.driveToTask)
end

--- Setup all job parameters.
--- For now every job has these parameters in common.
function CpAIJob:setupJobParameters()
	self.vehicleParameter = AIParameterVehicle.new()
	self:addNamedParameter("vehicle", self.vehicleParameter)
	local vehicleGroup = CpAIParameterGroup(nil, {title = "ai_parameterGroupTitleVehicle"})
	vehicleGroup:addParameter(self.vehicleParameter)
	table.insert(self.groupedParameters, vehicleGroup)
end

--- Optional to create custom cp job parameters.
function CpAIJob:setupCpJobParameters(jobParameters)
	self.cpJobParameters = jobParameters
	CpSettingsUtil.generateAiJobGuiElementsFromSettingsTable(self.cpJobParameters.settingsBySubTitle,self,self.cpJobParameters)
	self.cpJobParameters:validateSettings()
end

--- Is the ai job allowed to finish ?
--- This entry point allowes us to catch giants stop conditions.
---@param message table Stop reason can be used to reverse engineer the cause.
---@return boolean
function CpAIJob:isFinishingAllowed(message)
	return true
end

--- Gets the first task to start with.
function CpAIJob:getStartTaskIndex()
	if self.driveToTask and (self:isTargetReached() or self.isDirectStart) then 
		return 2
	end

	-- if self.currentTaskIndex ~= 0 or self.isDirectStart or self:isTargetReached() then
	-- 	-- skip Giants driveTo
	-- 	-- TODO: this isn't very nice as we rely here on the derived classes to add more tasks
	-- 	return 2
	-- end
	-- if self.driveToTask:isa(AITaskDriveTo) and self.driveToTask.x == nil then 
	-- 	CpUtil.info("Drive to task was skipped, as no valid start position is set!")
	-- 	return 2
	-- end
	return 1
end

-- function CpAIJob:getNextTaskIndex()
-- 	if self:getIsLooping() and self.currentTaskIndex >= #self.tasks then 
-- 		--- Makes sure the giants task is skipped
-- 		return self:getStartTaskIndex()
-- 	end
-- 	return AIJob.getNextTaskIndex(self)
-- end

--- Are we near the target point anyway or do we want to skip the inital street drive?
function CpAIJob:isTargetReached()
	if not self.cpJobParameters or not self.cpJobParameters.startTargetPoint then 
		return true
	end
	--- Override by sub classes
	return false
end

function CpAIJob:onPreStart()
	--- override
end

function CpAIJob:start(farmId)
	self:onPreStart()
	--- If we use more than the base game helper limit, 
	--- than we have to reuse already used helper indices.
	if #g_helperManager.availableHelpers > 0 then 
		self.helperIndex = g_helperManager:getRandomHelper().index
	else 
		self.helperIndex = g_helperManager:getRandomIndex()
	end
	self.startedFarmId = farmId
	self.isRunning = true
	if self.isServer then
		self.currentTaskIndex = 0
		local vehicle = self.vehicleParameter:getVehicle()

		vehicle:createAgent(self.helperIndex)
		vehicle:aiJobStarted(self, self.helperIndex, farmId)
	end
end

function CpAIJob:stop(aiMessage)
	if not self.isServer then 
		AIJob.stop(self, aiMessage)
		return
	end
	local vehicle = self.vehicleParameter:getVehicle()
	vehicle:deleteAgent()
	vehicle:aiJobFinished()
	vehicle:resetCpAllActiveInfoTexts()
	local driveStrategy = vehicle:getCpDriveStrategy()
	if not aiMessage then 
		self:debug("No valid ai message given!")
		if driveStrategy then
			driveStrategy:onFinished()
		end
		AIJob.stop(self, aiMessage)
		return
	end
	local releaseMessage, hasFinished, event, isOnlyShownOnPlayerStart = 
		g_infoTextManager:getInfoTextDataByAIMessage(aiMessage)
	if releaseMessage then 
		self:debug("Stopped with release message %s", tostring(releaseMessage))
	end
	if releaseMessage and not vehicle:getIsControlled() and not isOnlyShownOnPlayerStart then
		--- Only shows the info text, if the vehicle is not entered.
		--- TODO: Add check if passing to ad is active maybe?
		vehicle:setCpInfoTextActive(releaseMessage)
	end
	AIJob.stop(self, aiMessage)
	if event then
		SpecializationUtil.raiseEvent(vehicle, event)
	end
	if driveStrategy then
		driveStrategy:onFinished(hasFinished)
	end
	g_messageCenter:unsubscribeAll(self)
end

--- Updates the parameter values.
function CpAIJob:applyCurrentState(vehicle, mission, farmId, isDirectStart)
	-- the only thing this does, is setting self.isDirectStart
	AIJob.applyCurrentState(self, vehicle, mission, farmId, isDirectStart)
	self.vehicleParameter:setVehicle(vehicle)
	if not self.cpJobParameters or not self.cpJobParameters.startPosition then 
		return
	end
	if not vehicle then 
		CpUtil.error("Vehicle is null!")
		return
	end
	local x, z, _ = self.cpJobParameters.startPosition:getPosition()
	local angle = self.cpJobParameters.startPosition:getAngle()

	local snappingAngle = vehicle:getDirectionSnapAngle()
	local terrainAngle = math.pi / math.max(g_currentMission.fieldGroundSystem:getGroundAngleMaxValue() + 1, 4)
	snappingAngle = math.max(snappingAngle, terrainAngle)

	self.cpJobParameters.startPosition:setSnappingAngle(snappingAngle)

	if x == nil or z == nil then
		x, _, z = getWorldTranslation(vehicle.rootNode)
	end

	if angle == nil then
		local dirX, _, dirZ = localDirectionToWorld(vehicle.rootNode, 0, 0, 1)
		angle = MathUtil.getYRotationFromDirection(dirX, dirZ)
	end
	
	self.cpJobParameters.startPosition:setPosition(x, z)
	self.cpJobParameters.startPosition:setAngle(angle)

end

--- Can the vehicle be used for this job?
function CpAIJob:getIsAvailableForVehicle(vehicle, cpJobsAllowed)
	return cpJobsAllowed
end

function CpAIJob:getTitle()
	local vehicle = self.vehicleParameter:getVehicle()

	if vehicle ~= nil then
		return vehicle:getName()
	end

	return ""
end

--- Applies the parameter values to the tasks.
function CpAIJob:setValues()
	self:resetTasks()

	local vehicle = self.vehicleParameter:getVehicle()

	if self.driveToTask then 
		self.driveToTask:setVehicle(vehicle)
		self.driveToTask:setTarget(
			g_graph:getTargetByUniqueID(self.cpJobParameters.startTargetPoint:getValue()))

		-- local angle = self.cpJobParameters.startPosition:getAngle()
		-- local x, z = self.cpJobParameters.startPosition:getPosition()
		-- if angle ~= nil and x ~= nil then
		-- 	local dirX, dirZ = MathUtil.getDirectionFromYRotation(angle)
		-- 	self.driveToTask:setTargetDirection(dirX, dirZ)
		-- 	self.driveToTask:setTargetPosition(x, z)
		-- end
	end
end

--- Is the job valid?
---@param farmId number not used
function CpAIJob:validate(farmId)
	--- TODO_25
	-- self:setParamterValid(true)

	local isValid, errorMessage = self.vehicleParameter:validate()

	if not isValid then
		self.vehicleParameter:setIsValid(false)
	end

	return isValid, errorMessage
end

--- Start an asynchronous field boundary detection. Results are delivered by the callback
--- onFieldBoundaryDetectionFinished(vehicle, fieldPolygon, islandPolygons)
--- If the field position hasn't changed since the last call, the detection is skipped and this returns true.
--- In that case, the polygon from the previous run is still available from vehicle:cpGetFieldPolygon()
---@return boolean, boolean, string true if we already have a field boundary false otherwise,
--- second boolean true if the detection is still running false on error
--- error message
function CpAIJob:detectFieldBoundary()
	local vehicle = self.vehicleParameter:getVehicle()

	local tx, tz = self.cpJobParameters.fieldPosition:getPosition()
	if tx == nil or tz == nil then
		return false, false, g_i18n:getText("CP_error_not_on_field")
	end
	if vehicle:cpIsFieldBoundaryDetectionRunning() then
		return false, false, g_i18n:getText("CP_error_field_detection_still_running")
	end
	local x, z = vehicle:cpGetFieldPosition()
	if x == tx and z == tz then
		self:debug('Field position still at %.1f/%.1f, do not detect field boundary again', tx, tz)
		return true, false, ''
	end
	self:debug('Field position changed to %.1f/%.1f, start field boundary detection', tx, tz)
	self.foundVines = nil

	vehicle:cpDetectFieldBoundary(tx, tz, self, self.onFieldBoundaryDetectionFinished)
	-- TODO: return false and nothing, as the detection is still running?
	return false, true, g_i18n:getText('CP_error_field_detection_still_running')
end

function CpAIJob:onFieldBoundaryDetectionFinished(vehicle, fieldPolygon, islandPolygons)
	-- override in the derived classes to handle the detected field boundary
end

--- If registered, call the field boundary detection finished callback. This is to notify the frame
--- at the end of the async field detection.
--- It'll also return the result as a synchronous validate call would, and as the frame expects it, in case
--- someone calls the registered callback directly from validate()
---@return boolean isValid, string errorText
function CpAIJob:callFieldBoundaryDetectionFinishedCallback(isValid, errorTextName)
	local c = self.onFieldBoundaryDetectionFinishedCallback
	local errorText = errorTextName and g_i18n:getText(errorTextName) or ''
	if c and c.object and c.func then
		c.func(c.object, isValid, errorText)
	end
	return isValid, errorText
end

--- Register a callback for the field boundary detection finished event.
--- @param object table object to call the function on
--- @param func function function to call func(boolean isValid, string|nil errorTextName), errorTextName is the
--- name of the text in MasterTranslations.xml
function CpAIJob:registerFieldBoundaryDetectionCallback(object, func)
	self.onFieldBoundaryDetectionFinishedCallback = {object = object, func = func}
end

function CpAIJob:getIsStartable(connection)

	local vehicle = self.vehicleParameter:getVehicle()

	if vehicle == nil then
		return false, AIJobFieldWork.START_ERROR_VEHICLE_DELETED
	end

	if not g_currentMission:getHasPlayerPermission("hireAssistant", connection, vehicle:getOwnerFarmId()) then
		return false, AIJobFieldWork.START_ERROR_NO_PERMISSION
	end

	if vehicle:getIsInUse(connection) then
		return false, AIJobFieldWork.START_ERROR_VEHICLE_IN_USE
	end

	return true, AIJob.START_SUCCESS
end

function CpAIJob.getIsStartErrorText(state)
	if state == AIJobFieldWork.START_ERROR_LIMIT_REACHED then
		return g_i18n:getText("ai_startStateLimitReached")
	elseif state == AIJobFieldWork.START_ERROR_VEHICLE_DELETED then
		return g_i18n:getText("ai_startStateVehicleDeleted")
	elseif state == AIJobFieldWork.START_ERROR_NO_PERMISSION then
		return g_i18n:getText("ai_startStateNoPermission")
	elseif state == AIJobFieldWork.START_ERROR_VEHICLE_IN_USE then
		return g_i18n:getText("ai_startStateVehicleInUse")
	end

	return g_i18n:getText("ai_startStateSuccess")
end

function CpAIJob:draw(map, isOverviewMap)
	
end


function CpAIJob:writeStream(streamId, connection)
	streamWriteBool(streamId, self.isDirectStart)

	if streamWriteBool(streamId, self.jobId ~= nil) then
		streamWriteInt32(streamId, self.jobId)
	end

	for _, namedParameter in ipairs(self.namedParameters) do
		namedParameter.parameter:writeStream(streamId, connection)
	end

	streamWriteUInt8(streamId, self.currentTaskIndex)

	if self.cpJobParameters then
		self.cpJobParameters:writeStream(streamId, connection)
	end
end

function CpAIJob:readStream(streamId, connection)
	self.isDirectStart = streamReadBool(streamId)

	if streamReadBool(streamId) then
		self.jobId = streamReadInt32(streamId)
	end

	for _, namedParameter in ipairs(self.namedParameters) do
		namedParameter.parameter:readStream(streamId, connection)
	end

	self.currentTaskIndex = streamReadUInt8(streamId)
	if self.cpJobParameters then
		self.cpJobParameters:validateSettings(true)
		self.cpJobParameters:readStream(streamId, connection)
	end
	if not self:getIsHudJob() then
		self:setValues()
	end
end

function CpAIJob:saveToXMLFile(xmlFile, key, usedModNames)
	AIJob.saveToXMLFile(self, xmlFile, key, usedModNames)
	if self.cpJobParameters then
		self.cpJobParameters:saveToXMLFile(xmlFile, key)
	end
	return true
end

function CpAIJob:loadFromXMLFile(xmlFile, key)
	AIJob.loadFromXMLFile(self, xmlFile, key)
	if self.cpJobParameters then
		self.cpJobParameters:validateSettings()
		self.cpJobParameters:loadFromXMLFile(xmlFile, key)
	end
end

function CpAIJob:getCpJobParameters()
	return self.cpJobParameters
end

--- Can the job be started?
function CpAIJob:getCanStartJob()
	return true
end

function CpAIJob:copyFrom(job)
	self.cpJobParameters:copyFrom(job.cpJobParameters)
end

--- Applies the global wage modifier. 
function CpAIJob:getPricePerMs()
	local modifier = g_Courseplay.globalSettings:getSettings().wageModifier:getValue()/100
	return AIJob.getPricePerMs(self) * modifier
end

--- Fix for precision farming ...
function CpAIJob.getPricePerMs_FixPrecisionFarming(vehicle, superFunc, ...)
	if vehicle then 
		return superFunc(vehicle, ...)
	end
	--- Only if the vehicle/self of AIJobFieldWork:getPricePerMs() us nil,
	--- then the call was from precision farming and needs to be fixed ...
	--- Sadly the call on their end is not dynamic ...
	local modifier = g_Courseplay.globalSettings:getSettings().wageModifier:getValue()/100
	return superFunc(vehicle, ...) * modifier
end

AIJobFieldWork.getPricePerMs = Utils.overwrittenFunction(AIJobFieldWork.getPricePerMs, CpAIJob.getPricePerMs_FixPrecisionFarming)


--- Fruit Destruction
local function updateWheelDestructionAdjustment(vehicle, superFunc, ...)
	if g_Courseplay.globalSettings.fruitDestruction:getValue() == g_Courseplay.globalSettings.AI_FRUIT_DESTRUCTION_OFF then 
		--- AI Fruit destruction is disabled.
		superFunc(vehicle, ...)
		return
	end
	if g_Courseplay.globalSettings.fruitDestruction:getValue() == g_Courseplay.globalSettings.AI_FRUIT_DESTRUCTION_ONLY_CP 
		and (not vehicle.rootVehicle.getIsCpActive or not vehicle.rootVehicle:getIsCpActive()) then 
		--- AI Fruit destruction is disabled for other helpers than CP.
		superFunc(vehicle, ...)
		return
	end
	--- This hack enables AI Fruit destruction.
	local oldFunc = vehicle.getIsAIActive
	vehicle.getIsAIActive = function()
		return false
	end
	superFunc(vehicle, ...)
	vehicle.getIsAIActive = oldFunc
end
Wheels.onUpdate = Utils.overwrittenFunction(Wheels.onUpdate, updateWheelDestructionAdjustment)


function CpAIJob:getVehicle()
	return self.vehicleParameter:getVehicle() or self.vehicle
end

--- Makes sure that the keybinding/hud job has the vehicle.
function CpAIJob:setVehicle(v, isHudJob)
	self.vehicle = v
	self.isHudJob = isHudJob
	if self.cpJobParameters then 
		self.cpJobParameters:validateSettings()
	end
end

function CpAIJob:getIsHudJob()
	return self.isHudJob
end

function CpAIJob:showNotification(aiMessage)
	if g_Courseplay.globalSettings.infoTextHudActive:getValue() == g_Courseplay.globalSettings.DISABLED then 
		AIJob.showNotification(self, aiMessage)
		return
	end
	local releaseMessage, hasFinished, event = g_infoTextManager:getInfoTextDataByAIMessage(aiMessage)
	if not releaseMessage and not aiMessage:isa(AIMessageSuccessStoppedByUser) then 
		self:debug("No release message found, so we use the giants notification!")
		AIJob.showNotification(self, aiMessage)
		return
	end
	local vehicle = self:getVehicle()
	--- Makes sure the message is shown, when a player is in the vehicle.
	if releaseMessage and vehicle and vehicle:getIsEntered() then 
		g_currentMission:showBlinkingWarning(releaseMessage:getText(), 5000)
	end
end

function CpAIJob:getCanGenerateFieldWorkCourse()
	return false
end

function CpAIJob:debug(...)
	local vehicle = self:getVehicle()
	if vehicle then 
		CpUtil.debugVehicle(self.debugChannel, vehicle, ...)
	else 
		CpUtil.debugFormat(self.debugChannel, ...)
	end
end

--- Ugly hack to fix a mp problem from giants, where the job class can not be found.
function CpAIJob.getJobTypeIndex(aiJobTypeManager, superFunc, job)
	local ret = superFunc(aiJobTypeManager, job)
	if ret == nil then 
		if job.name then 
			return aiJobTypeManager.nameToIndex[job.name]
		end
	end
	return ret
end
AIJobTypeManager.getJobTypeIndex = Utils.overwrittenFunction(AIJobTypeManager.getJobTypeIndex ,CpAIJob.getJobTypeIndex)

--- Registers additional jobs.
function CpAIJob.registerJob(aiJobTypeManager)
	local function register(class)
		aiJobTypeManager:registerJobType(class.name, g_i18n:getText(class.jobName), class)
	end
	register(CpAIJobBaleFinder)
	register(CpAIJobFieldWork)
	register(CpAIJobCombineUnloader)
	register(CpAIJobSiloLoader)
	register(CpAIJobBunkerSilo)
	register(CpAIJobStreet)
end

