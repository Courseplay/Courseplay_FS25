--- AI Job for silo loader like the ropa maus or wheel loaders.
---@class CpAIJobSiloLoader : CpAIJob
---@field heapPlot HeapPlot
---@field trailerAreaPlot HeapPlot
---@field heapNode number
CpAIJobSiloLoader = CpObject(CpAIJob)
CpAIJobSiloLoader.name = "SILO_LOADER_CP"
CpAIJobSiloLoader.jobName = "CP_job_siloLoader"
CpAIJobSiloLoader.maxHeapLength = 150
--- Trailer unload marker length, -TRAILER_SEARCH_LENGTH/2 to TRAILER_SEARCH_LENGTH/2 
CpAIJobSiloLoader.TRAILER_SEARCH_LENGTH = 25
--- Trailer unload marker width, -TRAILER_SEARCH_WIDTH/2 to TRAILER_SEARCH_WIDTH/2 
CpAIJobSiloLoader.TRAILER_SEARCH_WIDTH = 20
--- Max distance the trailer unload spot can be from the silo/heap.
CpAIJobSiloLoader.MAX_UNLOAD_TARGET_DISTANCE_FROM_SILO = 180

function CpAIJobSiloLoader:init(isServer)
	CpAIJob.init(self, isServer)
	self.heapPlot = HeapPlot()
	self.heapPlot:setVisible(false)
	self.trailerAreaPlot = HeapPlot()
	self.heapNode = CpUtil.createNode("siloNode", 0, 0, 0, nil)
	self.heap = nil
	self.hasValidPosition = false
	self.debugChannel = CpDebug.DBG_SILO
end

function CpAIJobSiloLoader:delete()
	CpAIJob.delete(self)
	CpUtil.destroyNode(self.heapNode)
end

function CpAIJobSiloLoader:setupTasks(isServer)
	CpAIJob.setupTasks(self, isServer)
	self.siloLoaderTask = CpAITaskSiloLoader(isServer, self)
	self:addTask(self.siloLoaderTask)
end

function CpAIJobSiloLoader:setupJobParameters()
	CpAIJob.setupJobParameters(self)
	self:setupCpJobParameters(CpSiloLoaderJobParameters(self))
	self.cpJobParameters.loadPosition:setSnappingAngle(math.pi/8) -- AI menu snapping angle of 22.5 degree.
	self.cpJobParameters.unloadPosition:setSnappingAngle(math.pi/8) -- AI menu snapping angle of 22.5 degree.
end

function CpAIJobSiloLoader:getIsAvailableForVehicle(vehicle, cpJobsAllowed)
	return CpAIJob.getIsAvailableForVehicle(self, vehicle, cpJobsAllowed) and vehicle.getCanStartCpSiloLoaderWorker and vehicle:getCanStartCpSiloLoaderWorker() -- TODO_25
end

function CpAIJobSiloLoader:getCanStartJob()
	return self.hasValidPosition
end

---@param vehicle table
---@param mission table
---@param farmId number
---@param isDirectStart boolean disables the drive to by giants
---@param isStartPositionInvalid boolean resets the drive to target position by giants and the field position to the vehicle position.
function CpAIJobSiloLoader:applyCurrentState(vehicle, mission, farmId, isDirectStart, isStartPositionInvalid)
	CpAIJob.applyCurrentState(self, vehicle, mission, farmId, isDirectStart)
	
	self.cpJobParameters:validateSettings()

	self:copyFrom(vehicle:getCpSiloLoaderWorkerJob())

	local x, z = self.cpJobParameters.loadPosition:getPosition()
	local angle = self.cpJobParameters.loadPosition:getAngle()
	-- no field position from the previous job, use the vehicle's current position
	if x == nil or z == nil or angle == nil then
		x, _, z = getWorldTranslation(vehicle.rootNode)
		local dirX, _, dirZ = localDirectionToWorld(vehicle.rootNode, 0, 0, 1)
		local angle = MathUtil.getYRotationFromDirection(dirX, dirZ)
		self.cpJobParameters.loadPosition:setPosition(x, z)
		self.cpJobParameters.loadPosition:setAngle(angle)
	end

	local x, z = self.cpJobParameters.unloadPosition:getPosition()

	-- no unload position use the vehicle's current position
	if x == nil or z == nil then
		x, _, z = getWorldTranslation(vehicle.rootNode)
		self.cpJobParameters.unloadPosition:setPosition(x, z)
	end
end

function CpAIJobSiloLoader:setValues()
	CpAIJob.setValues(self)
	local vehicle = self.vehicleParameter:getVehicle()
	self.siloLoaderTask:setVehicle(vehicle)

	local found, bunkerSilo, heapSilo = self:getBunkerSiloOrHeap(self.cpJobParameters.loadPosition, self.heapNode)
	if found then 
		if bunkerSilo then 
			self.bunkerSilo = bunkerSilo
		elseif heapSilo then
			self.heapPlot:setArea(heapSilo:getArea())
			self.heapPlot:setVisible(true)
			self.heap = heapSilo
		end
		self.siloLoaderTask:setSiloAndHeap(self.bunkerSilo, self.heap)
	end
end


--- Called when parameters change, scan field
function CpAIJobSiloLoader:validate(farmId)
	self.heapPlot:setVisible(false)
	self.trailerAreaPlot:setVisible(false)
	self.heap = nil
	self.bunkerSilo = nil
	self.unloadStation = nil
	self.unloadTrigger = nil
	self.hasValidPosition = false
	self:getCpJobParameters().unloadStation:setValue(-1)
	local isValid, errorMessage = CpAIJob.validate(self, farmId)
	if not isValid then
		return isValid, errorMessage
	end
	local vehicle = self.vehicleParameter:getVehicle()
	if vehicle then 
		vehicle:applyCpSiloLoaderWorkerJobParameters(self)
	end
	
	--- First we search for bunker silos:
	local found, bunkerSilo, heapSilo = self:getBunkerSiloOrHeap(self.cpJobParameters.loadPosition, self.heapNode)
	if found then 
		self.hasValidPosition = true
		if bunkerSilo then 
			self.bunkerSilo = bunkerSilo
		elseif heapSilo then
			self.heapPlot:setArea(heapSilo:getArea())
			self.heapPlot:setVisible(true)
			self.heap = heapSilo
		end
		self.siloLoaderTask:setSiloAndHeap(self.bunkerSilo, self.heap)
	else 
		return false, g_i18n:getText("CP_error_no_heap_found")
	end
	if not AIUtil.hasChildVehicleWithSpecialization(vehicle, ConveyorBelt) then 
		if self.cpJobParameters.unloadAt:getValue() == CpSiloLoaderJobParameters.UNLOAD_TRIGGER then 
			--- Validates the unload trigger setup
			local found, unloadTrigger, unloadStation, validDistanceToSilo = self:getUnloadTriggerAt(self.cpJobParameters.unloadPosition)
			if found then 
				self.unloadStation = unloadStation
				self.unloadTrigger = unloadTrigger
				if unloadStation == nil then 
					return false, g_i18n:getText("CP_error_no_unload_trigger_found")
				end
				local id = NetworkUtil.getObjectId(unloadStation)
				if id ~= nil then 
					CpUtil.debugVehicle(CpDebug.DBG_SILO, vehicle, 
						"Found a valid unload trigger: %s for %s", 
						CpUtil.getName(unloadTrigger), CpUtil.getName(unloadStation))
					self:getCpJobParameters().unloadStation:setValue(id)
					self:getCpJobParameters().unloadStation:validateUnloadingStation()
				end
			else 
				return false, g_i18n:getText("CP_error_no_unload_trigger_found")
			end
			local unloadPosition = self:getCpJobParameters().unloadPosition
			if unloadPosition.x == nil or unloadPosition.angle == nil then 
				return false, g_i18n:getText("CP_error_no_unload_trigger_found")
			end
			if not validDistanceToSilo then 
				return false, g_i18n:getText("CP_error_unload_target_to_far_away_from_silo")
			end
		else 
			local found, area, validDistanceToSilo = CpAIJobSiloLoader.getTrailerUnloadArea(
				self.cpJobParameters.unloadPosition, self.bunkerSilo or self.heap)
			if found then
				self.trailerAreaPlot:setVisible(true)
				self.trailerAreaPlot:setArea(area)
			end
			if not validDistanceToSilo then 
				return false, g_i18n:getText("CP_error_unload_target_to_far_away_from_silo")
			end
		end
	end
	return isValid, errorMessage
end

--- Gets the area to search for trailers 
--- and optional check if the trailer area is close enough to the silo 
---@param position CpAIParameterPositionAngle
---@param silo CpSilo|nil
---@return boolean found?
---@return table area
---@return boolean distance to silo is valid
function CpAIJobSiloLoader.getTrailerUnloadArea(position, silo)
	local x, z = position:getPosition()
	local dirX, dirZ = position:getDirection()
	if x == nil or dirX == nil then
		return false, {}, false
	end
	--- Rotation matrix to rotate Z directions to x directions
	local dirX2 = dirX * math.cos(math.pi/2) - dirZ * math.sin(math.pi/2)
	local dirZ2 = dirX * math.sin(math.pi/2) + dirZ * math.cos(math.pi/2)
	--- Creates a rectangle for the trailer unload area 
	local area =  {
		{
			x = x + dirX * CpAIJobSiloLoader.TRAILER_SEARCH_LENGTH/2 + dirX2 * CpAIJobSiloLoader.TRAILER_SEARCH_WIDTH/2, 
			z = z + dirZ * CpAIJobSiloLoader.TRAILER_SEARCH_LENGTH/2 + dirZ2 * CpAIJobSiloLoader.TRAILER_SEARCH_WIDTH/2
		},
		{
			x = x + dirX * CpAIJobSiloLoader.TRAILER_SEARCH_LENGTH/2 - dirX2 * CpAIJobSiloLoader.TRAILER_SEARCH_WIDTH/2, 
			z = z + dirZ * CpAIJobSiloLoader.TRAILER_SEARCH_LENGTH/2 - dirZ2 * CpAIJobSiloLoader.TRAILER_SEARCH_WIDTH/2
		},
		{
			x = x - dirX * CpAIJobSiloLoader.TRAILER_SEARCH_LENGTH/2 - dirX2 * CpAIJobSiloLoader.TRAILER_SEARCH_WIDTH/2, 
			z = z - dirZ * CpAIJobSiloLoader.TRAILER_SEARCH_LENGTH/2 - dirZ2 * CpAIJobSiloLoader.TRAILER_SEARCH_WIDTH/2
		},
		{
			x = x - dirX * CpAIJobSiloLoader.TRAILER_SEARCH_LENGTH/2 + dirX2 * CpAIJobSiloLoader.TRAILER_SEARCH_WIDTH/2, 
			z = z - dirZ * CpAIJobSiloLoader.TRAILER_SEARCH_LENGTH/2 + dirZ2 * CpAIJobSiloLoader.TRAILER_SEARCH_WIDTH/2
		},
		{
			x = x + dirX * CpAIJobSiloLoader.TRAILER_SEARCH_LENGTH/2 + dirX2 * CpAIJobSiloLoader.TRAILER_SEARCH_WIDTH/2, 
			z = z + dirZ * CpAIJobSiloLoader.TRAILER_SEARCH_LENGTH/2 + dirZ2 * CpAIJobSiloLoader.TRAILER_SEARCH_WIDTH/2
		},
	}
	if silo then 
		--- Checks if the distance between the front or back of the bunker silo/heap 
		--- to the trailer unload area marker is which the max limit. 
		local fx, fz = silo:getFrontCenter()
		local bx, bz = silo:getBackCenter()
		local dist1 = MathUtil.vector2Length(x-fx, z-fz)
		local dist2 = MathUtil.vector2Length(x-bx, z-bz)
		CpUtil.debugFormat(CpDebug.DBG_SILO, "Trailer marker is %.1fm/%.1fm away from the silo", 
			math.min(dist1, dist2), CpAIJobSiloLoader.MAX_UNLOAD_TARGET_DISTANCE_FROM_SILO)
		if dist1 > CpAIJobSiloLoader.MAX_UNLOAD_TARGET_DISTANCE_FROM_SILO and
			dist2 > CpAIJobSiloLoader.MAX_UNLOAD_TARGET_DISTANCE_FROM_SILO then
			--- Trailer unload area is to far away from the silo
			return true, area, false
		end
	end	
	return true, area, true
end

--- Gets the bunker silo or heap at the loading position in that order.
---@param loadPosition CpAIParameterPositionAngle
---@param node number
---@return boolean found?
---@return CpBunkerSilo|nil
---@return CpHeapBunkerSilo|nil
function CpAIJobSiloLoader:getBunkerSiloOrHeap(loadPosition, node)
	local x, z = loadPosition:getPosition()
	local angle = loadPosition:getAngle()
	if x == nil or angle == nil then
		return false
	end
	setTranslation(self.heapNode, x, 0, z)
	setRotation(self.heapNode, 0, angle, 0)
	local vehicle = self.vehicleParameter:getVehicle()
	local found, bunkerSilo = BunkerSiloManagerUtil.getBunkerSiloBetween(vehicle, node, 0, 25, -5)
	if found then 
		return true, bunkerSilo
	end
	local found, heapSilo = BunkerSiloManagerUtil.createHeapBunkerSilo(vehicle, node, 0, self.maxHeapLength, -10)
	return found, nil, heapSilo
end

--- Gets the unload trigger at the unload position.
--- Checks for the correct fill type 
--- between the silo and the unload target.
--- Also checks if the unloading target 
--- is close enough to the silo.
---@param unloadPosition CpAIParameterPositionAngle
---@return boolean found?
---@return table|nil Trigger
---@return table|nil unloadStation
---@return boolean|nil distance is close enough to the bunker silo/heap
function CpAIJobSiloLoader:getUnloadTriggerAt(unloadPosition)
	local x, z = unloadPosition:getPosition()
	local dirX, dirZ = unloadPosition:getDirection()
	if x == nil or dirX == nil then
		return false
	end	
	local fillType
	local silo = self.heap or self.bunkerSilo
	if silo then 
		fillType = silo:getFillType()
	end
	local found, trigger, station = g_triggerManager:getDischargeableUnloadTriggerAt( x, z, dirX, dirZ, 5, 25)
	if found and fillType ~= nil then 
		--- Additional check if the fill type of the silo 
		--- matches with the fill type of the unload target.
		if not trigger:getIsFillTypeAllowed(fillType) then 
			--- Fill type is not supported by the trigger.
			found = false
			local convertedOutputFillTypes = self:getConvertedFillTypes()
			for _, convertedFillType in ipairs(convertedOutputFillTypes) do 
				--- Checks possible found fill type conversions
				if trigger:getIsFillTypeAllowed(convertedFillType) then
					found = true
					break
				end
			end
		end
	end
	local fx, fz = silo:getFrontCenter()
	local bx, bz = silo:getBackCenter()
	--- Checks the distance of the unloading station to the bunker silo/heap 
	local dist1 = MathUtil.vector2Length(x-fx, z-fz)
	local dist2 = MathUtil.vector2Length(x-bx, z-bz)
	self:debug("Unloading trigger: %s is %.1fm/%.1fm away from the silo", 
		CpUtil.getName(station), math.min(dist1, dist2), 
		self.MAX_UNLOAD_TARGET_DISTANCE_FROM_SILO)
	if dist1 < CpAIJobSiloLoader.MAX_UNLOAD_TARGET_DISTANCE_FROM_SILO or
		dist2 < CpAIJobSiloLoader.MAX_UNLOAD_TARGET_DISTANCE_FROM_SILO  then
		--- Unloading point is close enough to the bunker silo.
		return found, trigger, station, true
	end
	return found, trigger, station
end

function CpAIJobSiloLoader:draw(map, isOverviewMap)
	CpAIJob.draw(self, map, isOverviewMap)
	if not isOverviewMap then
		self.heapPlot:draw(map)
		g_bunkerSiloManager:drawSilos(map, self.bunkerSilo) 
		if self.cpJobParameters.unloadAt:getValue() == CpSiloLoaderJobParameters.UNLOAD_TRIGGER then 
			local fillTypes = self:getConvertedFillTypes()
			local silo = self.heap or self.bunkerSilo
			if silo then 
				table.insert(fillTypes, silo:getFillType())
			end
			g_triggerManager:drawDischargeableTriggers(map, self.unloadTrigger, fillTypes)
		else 
			--- Drawing trailer area
			self.trailerAreaPlot:draw(map)
		end
	end
end


--- Gets all the unloading stations.
function CpAIJobSiloLoader:getUnloadingStations()
	local unloadingStations = {}
	for _, unloadingStation in pairs(g_currentMission.storageSystem:getUnloadingStations()) do
		--- TODO: Maybe a few stations need to be ignored?
		--- For example stations that have no possible correct fill type
		table.insert(unloadingStations, unloadingStation)
	end
	return unloadingStations
end

--- Gets converted fill types if there are any.
---@return table
function CpAIJobSiloLoader:getConvertedFillTypes()
	local fillTypes = {}
	local vehicle = self:getVehicle()
	if vehicle then 
		local shovels, found = AIUtil.getAllChildVehiclesWithSpecialization(vehicle, Shovel)
		local spec = found and shovels[1].spec_turnOnVehicle
		if spec and spec.activateableDischargeNode and spec.activateableDischargeNode.fillTypeConverter  then 
			for _, data in pairs(spec.activateableDischargeNode.fillTypeConverter) do 
				table.insert(fillTypes, data.targetFillTypeIndex)
			end
		end
	end
	return fillTypes
end

--- Gets the additional task description shown.
--- TODO: Add the missing task descriptions
function CpAIJobSiloLoader:getDescription()
	local desc = CpAIJob.getDescription(self)
	local currentTask = self:getTaskByIndex(self.currentTaskIndex)
    if currentTask == self.driveToTask then
		desc = desc .. " - " .. g_i18n:getText("ai_taskDescriptionDriveToField")
	elseif currentTask == self.siloLoaderTask then
		desc = desc .. " - " .. g_i18n:getText("CP_ai_taskDescriptionWorksInTheSilo")
	end
	return desc
end