--- Combine unloader job.
---@class CpAIJobCombineUnloader : CpAIJob
CpAIJobCombineUnloader = CpObject(CpAIJob)
CpAIJobCombineUnloader.name = "COMBINE_UNLOADER_CP"
CpAIJobCombineUnloader.jobName = "CP_job_combineUnload"
CpAIJobCombineUnloader.minStartDistanceToField = 20
CpAIJobCombineUnloader.minFieldUnloadDistanceToField = 20
CpAIJobCombineUnloader.maxHeapLength = 150
function CpAIJobCombineUnloader:init(isServer)
	CpAIJob.init(self, isServer)
	self.lastPositionX, self.lastPositionZ = math.huge, math.huge
    self.selectedFieldPlot = FieldPlot(true)
    self.selectedFieldPlot:setVisible(false)
	self.selectedFieldPlot:setBrightColor(true)
	self.heapPlot = HeapPlot()
	self.heapPlot:setVisible(false)
	self.heapNode = CpUtil.createNode("siloNode", 0, 0, 0, nil)
	--- Giants unload
	self.dischargeNodeInfos = {}
end

function CpAIJobCombineUnloader:delete()
	CpAIJob.delete(self)
	CpUtil.destroyNode(self.heapNode)
end

function CpAIJobCombineUnloader:setupTasks(isServer)
	CpAIJob.setupTasks(self, isServer)
	self.combineUnloaderTask = CpAITaskCombineUnloader(isServer, self)
	self:addTask(self.combineUnloaderTask)

	--- Giants unload
	self.waitForFillingTask = self.combineUnloaderTask
	self.driveToUnloadingTask = AITaskDriveTo.new(isServer, self)
	self.dischargeTask = AITaskDischarge.new(isServer, self)
	self:addTask(self.driveToUnloadingTask)
	self:addTask(self.dischargeTask)
	
end

function CpAIJobCombineUnloader:setupJobParameters()
	CpAIJob.setupJobParameters(self)
    self:setupCpJobParameters(CpCombineUnloaderJobParameters(self))
	self.cpJobParameters.fieldUnloadPosition:setSnappingAngle(math.pi/8) -- AI menu snapping angle of 22.5 degree.

	--- Giants unload
	self.unloadingStationParameter = self.cpJobParameters.unloadingStation
	self.waitForFillingTask = self.combineUnloaderTask
end

function CpAIJobCombineUnloader:getIsAvailableForVehicle(vehicle, cpJobsAllowed)
	return CpAIJob.getIsAvailableForVehicle(self, vehicle, cpJobsAllowed) and vehicle.getCanStartCpCombineUnloader and vehicle:getCanStartCpCombineUnloader() -- TODO_25
end

function CpAIJobCombineUnloader:getCanStartJob()
	return self:getVehicle():cpGetFieldPolygon() ~= nil
end

---@param vehicle table
---@param mission Mission
---@param farmId number
---@param isDirectStart boolean disables the drive to by giants
---@param isStartPositionInvalid boolean resets the drive to target position by giants and the field position to the vehicle position.
function CpAIJobCombineUnloader:applyCurrentState(vehicle, mission, farmId, isDirectStart, isStartPositionInvalid)
	CpAIJob.applyCurrentState(self, vehicle, mission, farmId, isDirectStart)
	
	self.cpJobParameters:validateSettings()

	self:copyFrom(vehicle:getCpCombineUnloaderJob())

	if self.cpJobParameters.fieldPosition then
		local x, z = self.cpJobParameters.fieldPosition:getPosition()
		-- no field position from the previous job, use the vehicle's current position
		if x == nil or z == nil then
			x, _, z = getWorldTranslation(vehicle.rootNode)
			self.cpJobParameters.fieldPosition:setPosition(x, z)
		end
	end

	if self.cpJobParameters.fieldUnloadPosition then
		local x, z = self.cpJobParameters.fieldUnloadPosition:getPosition()
		local angle = self.cpJobParameters.fieldUnloadPosition:getAngle()
		-- no field position from the previous job, use the vehicle's current position
		if x == nil or z == nil or angle == nil then
			x, _, z = getWorldTranslation(vehicle.rootNode)
			local dirX, _, dirZ = localDirectionToWorld(vehicle.rootNode, 0, 0, 1)
			angle = MathUtil.getYRotationFromDirection(dirX, dirZ)
			self.cpJobParameters.fieldUnloadPosition:setPosition(x, z)
			self.cpJobParameters.fieldUnloadPosition:setAngle(angle)
		end
	end
end

--- Gets the giants unload station.
function CpAIJobCombineUnloader:getUnloadingStations()
	local unloadingStations = {}
	for _, unloadingStation in pairs(g_currentMission.storageSystem:getUnloadingStations()) do
		if g_currentMission.accessHandler:canPlayerAccess(unloadingStation) and unloadingStation:isa(UnloadingStation) then
			local fillTypes = unloadingStation:getAISupportedFillTypes()

			if next(fillTypes) ~= nil then
				table.insert(unloadingStations, unloadingStation)
			end
		end
	end
	return unloadingStations
end

function CpAIJobCombineUnloader:setValues()
	CpAIJob.setValues(self)
	local vehicle = self.vehicleParameter:getVehicle()
	self.combineUnloaderTask:setVehicle(vehicle)
	self:setupGiantsUnloaderData(vehicle)
end

--- Called when parameters change, scan field
function CpAIJobCombineUnloader:validate(farmId)
	self.selectedFieldPlot:setVisible(false)
	self.heapPlot:setVisible(false)
	local isValid, isRunning, errorMessage = CpAIJob.validate(self, farmId)
	if not isValid then
		return isValid, errorMessage
	end
	local vehicle = self.vehicleParameter:getVehicle()
	if vehicle then 
		vehicle:applyCpCombineUnloaderJobParameters(self)
	end
	------------------------------------
	--- Validate giants unload if needed
	-------------------------------------
	if not self.cpJobParameters.useGiantsUnload:getIsDisabled() and self.cpJobParameters.useGiantsUnload:getValue() then
		isValid, errorMessage = self.cpJobParameters.unloadingStation:validateUnloadingStation()

		if not isValid then
			return false, errorMessage
		end

		if not AIJobDeliver.getIsAvailableForVehicle(self, vehicle) then
			return false, g_i18n:getText("CP_error_giants_unloader_not_available")
		end

		isValid, errorMessage = self.cpJobParameters.startPosition:validate()
		if not isValid then
			return false, errorMessage
		end
	end

	------------------------------------
	--- Validate selected field
	-------------------------------------
	isValid, isRunning, errorMessage = self:detectFieldBoundary()

	if isValid then
		-- already have a valid boundary, continue the validation now
		return self:onFieldBoundaryDetectionFinished(vehicle, vehicle:cpGetFieldPolygon())
	else
		-- if the detection is now running at least, we are ok, the strategy will take care of the result
		return isValid or isRunning, errorMessage
	end
end

function CpAIJobCombineUnloader:onFieldBoundaryDetectionFinished(vehicle, fieldPolygon, islandPolygons)
	-- show the field
	if fieldPolygon then
		self.selectedFieldPlot:setWaypoints(fieldPolygon)
		self.selectedFieldPlot:setVisible(true)
	end
	------------------------------------
	--- Validate start distance to field
	-------------------------------------
	local useGiantsUnload = false
	if not self.cpJobParameters.useGiantsUnload:getIsDisabled() then 
		useGiantsUnload =  self.cpJobParameters.useGiantsUnload:getValue() 
	end
	local isValid, errorMessage = true
	if fieldPolygon and self.isDirectStart then
		--- Checks the distance for starting with the hud, as a safety check.
		--- Firstly check, if the vehicle is near the field.
		local x, _, z = getWorldTranslation(vehicle.rootNode)
		isValid = CpMathUtil.isPointInPolygon(fieldPolygon, x, z) or 
				  CpMathUtil.isWithinDistanceToPolygon(fieldPolygon, x, z, self.minStartDistanceToField)
		if not isValid and useGiantsUnload then 
			--- Alternatively check, if the start marker is close to the field and giants unload is active.
			x, z = self.cpJobParameters.startPosition:getPosition()
			isValid = CpMathUtil.isPointInPolygon(fieldPolygon, x, z) or 
				  CpMathUtil.isWithinDistanceToPolygon(fieldPolygon, x, z, self.minStartDistanceToField)
			if not isValid then
				return self:callFieldBoundaryDetectionFinishedCallback(false, "CP_error_start_position_to_far_away_from_field")
			end
		end
		if not isValid then
			return self:callFieldBoundaryDetectionFinishedCallback(false, "CP_error_unloader_to_far_away_from_field")
		end
	end
	------------------------------------
	--- Validate field unload if needed
	-------------------------------------
	local useFieldUnload = false
	if not self.cpJobParameters.useFieldUnload:getIsDisabled() then 
		useFieldUnload =  self.cpJobParameters.useFieldUnload:getValue() 
	end
	if useFieldUnload then 
		
		local x, z = self.cpJobParameters.fieldUnloadPosition:getPosition()
		isValid = CpMathUtil.isPointInPolygon(fieldPolygon, x, z) or 
				  CpMathUtil.isWithinDistanceToPolygon(fieldPolygon, x, z, self.minFieldUnloadDistanceToField)
		if not isValid then
			return self:callFieldBoundaryDetectionFinishedCallback(false, 'CP_error_fieldUnloadPosition_too_far_away_from_field')
		end
		--- Draws the silo
		local angle = self.cpJobParameters.fieldUnloadPosition:getAngle()
		setTranslation(self.heapNode, x, 0, z)
		setRotation(self.heapNode, 0, angle, 0)
		local found, heapSilo = BunkerSiloManagerUtil.createHeapBunkerSilo(vehicle, self.heapNode, 0, self.maxHeapLength, -10)
		if found then
			self.heapPlot:setArea(heapSilo:getArea())
			self.heapPlot:setVisible(true)
		end
	end
	return self:callFieldBoundaryDetectionFinishedCallback(true)
end

function CpAIJobCombineUnloader:draw(map, isOverviewMap)
	CpAIJob.draw(self, map, isOverviewMap)
	if not isOverviewMap then
		self.selectedFieldPlot:draw(map)
		self.heapPlot:draw(map)
	end
end

------------------------------------
--- Giants unload 
------------------------------------

--- Sets static data for the giants unload. 
function CpAIJobCombineUnloader:setupGiantsUnloaderData(vehicle)
	self.dischargeNodeInfos = {}
	if vehicle == nil then 
		return
	end
	if vehicle.getAIDischargeNodes ~= nil then
		for _, dischargeNode in ipairs(vehicle:getAIDischargeNodes()) do
			local _, _, z = vehicle:getAIDischargeNodeZAlignedOffset(dischargeNode, vehicle)

			table.insert(self.dischargeNodeInfos, {
				dirty = true,
				vehicle = vehicle,
				dischargeNode = dischargeNode,
				offsetZ = z
			})
		end
	end

	local childVehicles = vehicle:getChildVehicles()

	for _, childVehicle in ipairs(childVehicles) do
		if childVehicle.getAIDischargeNodes ~= nil then
			for _, dischargeNode in ipairs(childVehicle:getAIDischargeNodes()) do
				local _, _, z = childVehicle:getAIDischargeNodeZAlignedOffset(dischargeNode, vehicle)

				table.insert(self.dischargeNodeInfos, {
					dirty = true,
					vehicle = childVehicle,
					dischargeNode = dischargeNode,
					offsetZ = z
				})
			end
		end
	end
	self.driveToUnloadingTask:setVehicle(vehicle)
	self.dischargeTask:setVehicle(vehicle)
	if #self.dischargeNodeInfos > 0 then 
		table.sort(self.dischargeNodeInfos, function (a, b)
			return b.offsetZ < a.offsetZ
		end)
		local maxOffset = self.dischargeNodeInfos[#self.dischargeNodeInfos].offsetZ

		self.driveToUnloadingTask:setTargetOffset(-maxOffset)
	end
	local unloadingStation = self.unloadingStationParameter:getUnloadingStation()

	if unloadingStation == nil then
		return
	end
	self.supportedFillTypes = unloadingStation:getAISupportedFillTypes()
end

function CpAIJobCombineUnloader:getNextTaskIndex(isSkipTask)
	--- Giants unload, sets the correct dischargeNode and vehicle and unload target information.
	local index = AIJobDeliver.getNextTaskIndex(self, isSkipTask)
	return index
end

function CpAIJobCombineUnloader:canContinueWork()
	local canContinueWork, errorMessage = CpAIJob.canContinueWork(self)
	if not canContinueWork then 
		return canContinueWork, errorMessage
	end
	--- Giants unload, checks if the unloading station is still available and not full.
	if self.cpJobParameters.useGiantsUnload:getValue() then 
		
		local canContinue, errorMessage = AIJobDeliver.canContinueWork(self)
		if not canContinue then 
			return canContinue, errorMessage
		end
		if self.currentTaskIndex == self.driveToUnloadingTask.taskIndex then
			local hasSupportedFillTypeLoaded = false
			for _, dischargeNodeInfo in ipairs(self.dischargeNodeInfos) do
				local fillType = dischargeNodeInfo.vehicle:getFillUnitFillType(dischargeNodeInfo.dischargeNode.fillUnitIndex)
				if self.supportedFillTypes[fillType] then 
					hasSupportedFillTypeLoaded = true
				end
			end
			if not hasSupportedFillTypeLoaded then
				return false, AIMessageErrorNoValidFillTypeLoaded.new()
			end
			if self.driveToUnloadingTask.x == nil then 
				CpUtil.errorVehicle(self.vehicle, "No valid drive to unload task position set!")
				return false, AIMessageCpError.new()
			end
		end
	end

	return true, nil
end

function CpAIJobCombineUnloader:startTask(task)
	--- Giants unload, reset the discharge nodes before unloading.
	if task == self.driveToUnloadingTask then
		for _, dischargeNodeInfo in ipairs(self.dischargeNodeInfos) do
			dischargeNodeInfo.dirty = true
		end
	end
	CpAIJob.startTask(self, task)
end

--- Starting index for giants unload: 
---  - Close or on the field, we make sure cp pathfinder is always involved.
---  - Else if the trailer is full and we are far away from the field, then let giants drive to unload directly.
---@return number
function CpAIJobCombineUnloader:getStartTaskIndex()
	local startTask = CpAIJob.getStartTaskIndex(self)
	if not self.cpJobParameters.useGiantsUnload:getValue() then 
		return startTask
	end
	local vehicle = self:getVehicle()
	local fieldPolygon = vehicle:cpGetFieldPolygon()
	local x, _, z = getWorldTranslation(vehicle.rootNode)
	local fillLevelPercentage = FillLevelUtil.getTotalTrailerFillLevelPercentage(vehicle)
	local readyToDriveUnloading = vehicle:getCpSettings().fullThreshold:getValue() <= fillLevelPercentage
	if readyToDriveUnloading then 
		CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, vehicle, "Not close to the field and vehicle is full, so start driving to unload.")
		--- Small hack, so we can use the giants function and don't need to do copy & paste.
		local oldTaskIx = self.currentTaskIndex
		self.currentTaskIndex = self.combineUnloaderTask.taskIndex
		--- Needs to be used to set the unload target coordinates.
		self:getNextTaskIndex()
		self.currentTaskIndex = oldTaskIx
		if self.driveToUnloadingTask.x == nil then 
			CpUtil.errorVehicle(self.vehicle, "No valid drive to unload task position set!")
			return startTask
		end
		return self.driveToUnloadingTask.taskIndex
	end
	if CpMathUtil.isPointInPolygon(fieldPolygon, x, z) or 
		CpMathUtil.isWithinDistanceToPolygon(fieldPolygon, x, z, 2 * self.minStartDistanceToField) then
		CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, vehicle, "Close to the field, start cp drive strategy.")
		return startTask
	end
	return startTask
end

function CpAIJobCombineUnloader:getIsLooping()
	return true
end

--- Gets the additional task description shown.
--- TODO: Add the missing description once the task system is better implemented.
---@return unknown
function CpAIJobCombineUnloader:getDescription()
	local desc = CpAIJob.getDescription(self)
	local currentTask = self:getTaskByIndex(self.currentTaskIndex)
    if currentTask == self.driveToTask then
		desc = desc .. " - " .. g_i18n:getText("ai_taskDescriptionDriveToField")
	elseif currentTask == self.combineUnloaderTask then
		if self.cpJobParameters.unloadTarget:getValue() == CpCombineUnloaderJobParameters.UNLOAD_COMBINE then
			desc = desc .. " - " .. g_i18n:getText("CP_ai_taskDescriptionUnloadCombine")
		else 
			desc = desc .. " - " .. g_i18n:getText("CP_ai_taskDescriptionUnloadSiloLoader")
		end
	elseif currentTask == self.driveToUnloadingTask or currentTask == self.dischargeTask then 
		desc = desc .. " - " .. g_i18n:getText("CP_ai_taskDescriptionUnloadingWithGiants")
	end
	return desc
end
