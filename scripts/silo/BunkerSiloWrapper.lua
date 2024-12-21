---@class CpSilo
CpSilo = CpObject()

--[[

						B <:= Back center

heightNode -->	O-------B--------	
(hx,_,hz)		| X X X X X X X |  	---
				| X X X X X X X | 	 |
				| X X X X X X X | 	 |
				| X X X X X X X | 	 |
				| X X X X X X X | 	 |	 length
				| X X X X X X X | 	 |
				| X X X X X X X | 	 |   ^
				| X X X X X X X | 	 |   | (dirXLength, dirZLength)
				| X X X X X X X | 	 |    
				| X X X X X X X |  	---
startNode -->	O X	X X F X X X O	<-- widthNode
(sx, _, sz)								(wx, _, wz)
						F <:= Front center
				|---------------|
				   	  width
			 		---->
				 (dirXWidth, dirZWidth)
		
]]--


function CpSilo:init(sx, sz, wx, wz, hx, hz)
	self.sx = sx
	self.sy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, sx, 0, sz)
	self.sz = sz
	self.wx = wx
	self.wy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, wx, 0, wz)
	self.wz = wz
	self.hx = hx
	self.hy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, hx, 0, hz)
	self.hz = hz

	self.dirXLength, self.dirZLength, self.length = CpMathUtil.getPointDirection({x = sx, z = sz}, {x = hx, z = hz})
	self.dirXWidth, self.dirZWidth, self.width = CpMathUtil.getPointDirection({x = sx, z = sz}, {x = wx, z = wz})

	self.area = 	{
		{
			x = sx, 
			z = sz
		},
		{
			x = wx, 
			z = wz
		},
		{
			x = wx + self.dirXLength * self.length, 
			z = wz + self.dirZLength * self.length,
		},
		{
			x = hx, 
			z = hz
		},
		{
			x = sx, 
			z = sz
		} }

end

---@return number sx
---@return number sz
function CpSilo:getStartPosition()
	return self.sx, self.sz	
end

---@return number wx
---@return number wz
function CpSilo:getWidthPosition()
	return self.wx, self.wz	
end

---@return number hx
---@return number hz
function CpSilo:getHeightPosition()
	return self.hx, self.hz	
end

---@return number width
function CpSilo:getWidth()
	return self.width	
end

---@return number length
function CpSilo:getLength()
	return self.length
end

---@return number dirX
---@return number dirZ
function CpSilo:getLengthDirection()
	return self.dirXLength, self.dirZLength
end

---@return number dirX
---@return number dirZ
function CpSilo:getWidthDirection()
	return self.dirXWidth, self.dirZWidth
end

---@return number cx
---@return number cz
function CpSilo:getCenter()
	local cx, cz = self:getFrontCenter()
	return cx + self.dirXLength * self.length/2, cz + self.dirZLength * self.length/2
end

---@return number fcx
---@return number fcz
function CpSilo:getFrontCenter()
	local width = self:getWidth()
	return self.sx + self.dirXWidth * width/2, self.sz + self.dirZWidth * width/2
end

---@return number bcx
---@return number bcz
function CpSilo:getBackCenter()
	local length = self:getLength()
	local fcx, fcz = self:getFrontCenter()
	return fcx + self.dirXLength * length, fcz + self.dirZLength * length
end

--- Is the point directly in the silo area?
---@param x number
---@param z number
---@return boolean
function CpSilo:isPointInSilo(x, z)
	return self:isPointInArea(x, z, self.area)
end

---@param node number
---@return boolean
function CpSilo:isNodeInSilo(node)
	local x, _, z = getWorldTranslation(node)
	return self:isPointInArea(x, z, self.area)
end

---@param vehicle table
---@return boolean
function CpSilo:isVehicleInSilo(vehicle)
	return self:isNodeInSilo(vehicle.rootNode)
end

---@param x number
---@param z number
---@param area table
---@return boolean
function CpSilo:isPointInArea(x, z, area)
	return CpMathUtil.isPointInPolygon(area, x, z)	
end

---@return table area
function CpSilo:getArea()
	return self.area
end

function CpSilo:drawDebug()
	self:drawArea(self.area)

	DebugUtil.drawDebugGizmoAtWorldPos(self.sx, self.sy + 3, self.sz, self.dirXLength, 0, self.dirZLength, 
		0, 1, 0, "StartPoint", false)
	DebugUtil.drawDebugGizmoAtWorldPos(self.wx, self.wy + 3, self.wz, self.dirXLength, 0, self.dirZLength, 
		0, 1, 0, "WidthPoint", false)
	DebugUtil.drawDebugGizmoAtWorldPos(self.hx, self.hy + 3, self.hz, self.dirXLength, 0, self.dirZLength, 
		0, 1, 0, "HeightPoint", false)
end

function CpSilo:debug(...)
	CpUtil.debugFormat(CpUtil.DBG_SILO, ...)	
end

function CpSilo:drawArea(area)
	local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, area[1].x, 0, area[1].z) + 2
	DebugUtil.drawDebugAreaRectangle(area[1].x, y, area[1].z, area[2].x, y, area[2].z, area[4].x, y, area[4].z, false, 1, 0, 0)
end

--- Are the two silo overlapping 
function CpSilo:isOverlappingWith(otherSilo)
	if not otherSilo then 
		return false
	end
	local cx, cz = otherSilo:getCenter()
	return self:isPointInArea(cx, cz, self.area)
end

---@return number|nil fillType
function CpSilo:getFillType()
--	return DensityMapHeightUtil.getFillTypeAtArea(self.wx, self.wz, self.sx, self.sz, self.hx + self.width*self.dirXWidth, self.hz + self.width*self.dirZWidth)
	return DensityMapHeightUtil.getFillTypeAtArea( self.sx, self.sz, self.wx, self.wz, self.hx, self.hz)
end

---@return number fillLevel
function CpSilo:getTotalFillLevel()
	local fillType = self:getFillType()
	if fillType and fillType ~= FillType.UNKNOWN then 
		return DensityMapHeightUtil.getFillLevelAtArea(fillType, self.sx, self.sz, self.wx, self.wz, self.hx, self.hz)
	end
	return 0
end

function CpSilo:isTheSameSilo(object)
	--- override
	return false
end

--- Heap Bunker Silo
--- Wrapper for a heap.
---@class CpHeapBunkerSilo :CpSilo
CpHeapBunkerSilo = CpObject(CpSilo)

---@param sx number
---@param sz number
---@param wx number
---@param wz number
---@param hx number
---@param hz number
function CpHeapBunkerSilo:init(sx, sz, wx, wz, hx, hz)
	CpSilo.init(self, sx, sz, wx, wz, hx, hz)

	self.bunkerSiloArea = {
		sx = self.sx,
		sy = self.sy,
		sz = self.sz,
		wx = self.wx,
		wy = self.wy,
		wz = self.wz,
		hx = self.hx,
		hy = self.hy,
		hz = self.hz,
	}
	self.bunkerSiloArea.inner = self.bunkerSiloArea

	self.bunkerSiloArea.dhx = self.hx - self.bunkerSiloArea.sx
	self.bunkerSiloArea.dhy = self.hy - self.bunkerSiloArea.sy
	self.bunkerSiloArea.dhz = self.hz - self.bunkerSiloArea.sz
	self.bunkerSiloArea.dhx_norm, self.bunkerSiloArea.dhy_norm, self.bunkerSiloArea.dhz_norm = 
		MathUtil.vector3Normalize(self.bunkerSiloArea.dhx, self.bunkerSiloArea.dhy, self.bunkerSiloArea.dhz)
	self.bunkerSiloArea.dwx = self.bunkerSiloArea.wx - self.bunkerSiloArea.sx
	self.bunkerSiloArea.dwy = self.bunkerSiloArea.wy - self.bunkerSiloArea.sy
	self.bunkerSiloArea.dwz = self.bunkerSiloArea.wz - self.bunkerSiloArea.sz
	self.bunkerSiloArea.dwx_norm, self.bunkerSiloArea.dwy_norm, self.bunkerSiloArea.dwz_norm = 
		MathUtil.vector3Normalize(self.bunkerSiloArea.dwx, self.bunkerSiloArea.dwy, self.bunkerSiloArea.dwz)
end

--- Wrapper for a bunker silo.
---@class CpBunkerSilo : CpSilo
CpBunkerSilo = CpObject(CpSilo)

CpBunkerSilo.UNLOADER_LENGTH_OFFSET = 50
CpBunkerSilo.UNLOADER_WIDTH_OFFSET = 20
CpBunkerSilo.DRAW_DEBUG = false
CpBunkerSilo.SIDE_MODES = {
	OPEN = 0,
	ONE_SIDED = 1,
	ONE_SIDED_INVERTED = 2
}


function CpBunkerSilo:init(silo)
	local area = silo.bunkerSiloArea.inner
	self.startNode = area.start
	self.widthNode = area.width
	self.heightNode = area.height
	CpSilo.init(self, area.sx, area.sz, area.wx, area.wz, area.hx, area.hz)
	
	self.silo = silo
	self.controllers = {}
	self.numControllers = 0
	self.nearbyUnloaders = {}
	self.numNearbyUnloaders = 0
	self.siloMode = self.SIDE_MODES.OPEN
	self.initialized = false

	self.plot = BunkerSiloPlot()

	--- Small delay to make sure the bunker silo back wall is detected correctly.
	self.initDelay = CpTemporaryObject(true)
	self.initDelay:set(false, 30)
end

--- Checks if the silo has a back wall and sets the plot area afterwards. 
function CpBunkerSilo:initialize()
	local x, z = self.sx + self.dirXWidth * self.width/2 + self.dirXLength * 2, self.sz + self.dirZWidth * self.width/2 + self.dirZLength * 2
	local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z) + 2 

	raycastAll(x, y, z, self.dirXLength, 0, self.dirZLength, self.length + 2, 'rayCastCallbackOneSidedSilo', self)

	local x, z = self.hx + self.dirXWidth * self.width/2 - self.dirXLength * 2, self.hz + self.dirZWidth * self.width/2 - self.dirZLength * 2
	local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z) + 2 

	raycastAll(x, y, z, -self.dirXLength, 0, -self.dirZLength,  self.length + 2, 'rayCastCallbackOneSidedSiloInverted', self)


	self.plot:setAreas(self:getPlotAreas())
	self.initialized = true
end

BunkerSilo.readStream = Utils.appendedFunction(BunkerSilo.readStream,
	function(silo)
		local wrapper = g_bunkerSiloManager:getSiloWrapperByNode(silo.interactionTriggerNode)
		if wrapper then 
			wrapper:initialize()
		end
	end)

function CpBunkerSilo:rayCastCallbackOneSidedSilo(hitObjectId, x, y, z, distance, nx, ny, nz, subShapeIndex, shapeId, isLast)
	if hitObjectId then 
		local object = g_currentMission:getNodeObject(hitObjectId)
		if self:isTheSameSilo(object) then 

			--- Back wall was found.
			self.siloMode = self.SIDE_MODES.ONE_SIDED
			return true
		end
	end
end

function CpBunkerSilo:rayCastCallbackOneSidedSiloInverted(hitObjectId, x, y, z, distance, nx, ny, nz, subShapeIndex, shapeId, isLast)
	if hitObjectId then 
		local object = g_currentMission:getNodeObject(hitObjectId)
		if self:isTheSameSilo(object) then 

			--- Back wall was found.
			self.siloMode = self.SIDE_MODES.ONE_SIDED_INVERTED
			return true
		end
	end
end

--- Is the placeable object the same as the silo?  
function CpBunkerSilo:isTheSameSilo(object)
	if object and object:isa(Placeable) then 
		if object.spec_bunkerSilo then 
			if self.silo == object.spec_bunkerSilo.bunkerSilo then 
				return true
			end
		end
	end
	return false
end

function CpBunkerSilo:getFrontArea(length, sideOffset)
	if self.siloMode == self.SIDE_MODES.ONE_SIDED_INVERTED then 
		return self:getBackAreaInternal(length, sideOffset)
	else 
		return self:getFrontAreaInternal(length, sideOffset)
	end
end

function CpBunkerSilo:getBackArea(length, sideOffset)
	if self.siloMode == self.SIDE_MODES.ONE_SIDED_INVERTED then 
		return self:getFrontAreaInternal(length, sideOffset)
	else 
		return self:getBackAreaInternal(length, sideOffset)
	end
end

--- Area in front of the silo, to manage possible unloaders there.
function CpBunkerSilo:getFrontAreaInternal(length, sideOffset)
	length = length or CpBunkerSilo.UNLOADER_LENGTH_OFFSET
	sideOffset = sideOffset or CpBunkerSilo.UNLOADER_WIDTH_OFFSET
	local area = 	{
		{
			x = self.sx - self.dirXWidth * sideOffset, 
			z = self.sz - self.dirZWidth * sideOffset
		},
		{
			x = self.wx + self.dirXWidth * sideOffset, 
			z = self.wz + self.dirZWidth * sideOffset
		},
		{
			x = self.wx - self.dirXLength * length + self.dirXWidth * sideOffset, 
			z = self.wz - self.dirZLength * length + self.dirZWidth * sideOffset,
		},
		{
			x = self.sx - self.dirXLength * length - self.dirXWidth * sideOffset, 
			z = self.sz - self.dirZLength * length - self.dirZWidth * sideOffset
		},
		{
			x = self.sx - self.dirXWidth * sideOffset, 
			z = self.sz - self.dirZWidth * sideOffset
		} }
	return area
end

--- Area in back of the silo, to manage possible unloaders there.
function CpBunkerSilo:getBackAreaInternal(length, sideOffset)
	length = length or CpBunkerSilo.UNLOADER_LENGTH_OFFSET
	sideOffset = sideOffset or CpBunkerSilo.UNLOADER_WIDTH_OFFSET
	local area = 	{
		{
			x = self.sx + self.dirXLength * self.length - self.dirXWidth * sideOffset, 
			z = self.sz + self.dirZLength * self.length - self.dirZWidth * sideOffset
		},
		{
			x = self.sx + self.dirXLength * (self.length + length) - self.dirXWidth * sideOffset, 
			z = self.sz + self.dirZLength * (self.length + length) - self.dirZWidth * sideOffset
		},
		{
			x = self.wx + self.dirXLength * (self.length + length) + self.dirXWidth * sideOffset, 
			z = self.wz + self.dirZLength * (self.length + length) + self.dirZWidth * sideOffset
		},
		{
			x = self.wx + self.dirXLength * self.length + self.dirXWidth * sideOffset, 
			z = self.wz + self.dirZLength * self.length + self.dirZWidth * sideOffset
		},
		{
			x = self.sx + self.dirXLength * self.length - self.dirXWidth * sideOffset, 
			z = self.sz + self.dirZLength * self.length - self.dirZWidth * sideOffset
		} }
	return area
end

--- Gets the giants bunker silo
function CpBunkerSilo:getSilo()
	return self.silo	
end

function CpBunkerSilo:getNode()
	return self.silo.interactionTriggerNode	
end

function CpBunkerSilo:getFillType()
	return self.silo.outputFillType
end

function CpBunkerSilo:getTotalFillLevel()
	return self.silo.fillLevel
end

function CpBunkerSilo:delete()
	for _, controller in pairs(self.controllers) do 
		controller:setBunkerSiloInvalid()
		controller:delete()
	end
	self.plot:delete()
end

function CpBunkerSilo:update(dt)
	if not self.initialized and self.initDelay:get() then 
		self:initialize()
	end

	--- Searches for new unloaders in the unloader area and remove unloaders, that left.
	self:updateUnloaders(dt)
end

function CpBunkerSilo:draw()
	for i, controller in pairs(self.controllers) do 
		controller:draw()
	end
	if CpBunkerSilo.DRAW_DEBUG then
		self:drawUnloaderArea()

		local x, z = self.sx + self.dirXWidth * self.width/2 + self.dirXLength * 2, self.sz + self.dirZWidth * self.width/2 + self.dirZLength * 2
		local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z) + 2
		DebugUtil.drawDebugLine(x, y, z, x + self.dirXLength * (self.length + 2), y, z + self.dirZLength * self.length)

		local x, z = self.hx + self.dirXWidth * self.width/2 - self.dirXLength * 2, self.hz + self.dirZWidth * self.width/2 - self.dirZLength * 2
		local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z) + 3
		DebugUtil.drawDebugLine(x, y, z, x - self.dirXLength * (self.length + 2), y, z - self.dirZLength * self.length)
	end
end

--- Gets the compaction percentage in 0-100
---@return number
function CpBunkerSilo:getCompactionPercentage()
	return self.silo.compactedPercent
end

---@return boolean
function CpBunkerSilo:canBeFilled()
	return self.silo.state == BunkerSilo.STATE_FILL
end

---@return boolean
function CpBunkerSilo:canBeEmptied()
	return self.silo.state == BunkerSilo.STATE_DRAIN
end

--------------------------------------------------
--- Vehicle controllers.
--------------------------------------------------

--- Creates a controller for the vehicle.
---@param vehicle Vehicle
---@param driveStrategy AIDriveStrategyBunkerSilo
---@param directionNode number
---@return CpBunkerSiloLevelerController
function CpBunkerSilo:setupLevelerTarget(vehicle, driveStrategy, directionNode)
	self.controllers[vehicle.rootNode] = CpBunkerSiloLevelerController(self, vehicle, driveStrategy, directionNode)
	self.numControllers = self.numControllers + 1 
	return self.controllers[vehicle.rootNode]
end

--- Creates a controller for the vehicle.
---@param vehicle Vehicle
---@param driveStrategy AIDriveStrategySiloLoader
---@return CpBunkerSiloLoaderController
function CpBunkerSilo:setupLoaderTarget(vehicle, driveStrategy)
	self.controllers[vehicle.rootNode] = CpBunkerSiloLoaderController(self, vehicle, driveStrategy)
	self.numControllers = self.numControllers + 1 
	return self.controllers[vehicle.rootNode]
end

--- Resets the controller for the given vehicle.
function CpBunkerSilo:resetTarget(vehicle)
	if self.controllers[vehicle.rootNode] then
		self.controllers[vehicle.rootNode]:delete()
		self.controllers[vehicle.rootNode] = nil
		self.numControllers = self.numControllers - 1
	end
end

--------------------------------------------------
--- Bunker silo plot
--------------------------------------------------

function CpBunkerSilo:drawPlot(map, selectedSilo)
	self.plot:setHighlighted(self == selectedSilo)
	self.plot:draw(map)
end


function CpBunkerSilo:getPlotAreas()
	if self.siloMode == self.SIDE_MODES.ONE_SIDED then 
		return {
				{
					x = self.sx, 
					z = self.sz
				},
				{
					x = self.sx + self.dirXLength * self.length, 
					z = self.sz + self.dirZLength * self.length
				},
				{
					x = self.wx + self.dirXLength * self.length,
					z = self.wz + self.dirZLength * self.length,
				},
				{
					x = self.wx, 
					z = self.wz
				},
			}
	elseif self.siloMode == self.SIDE_MODES.ONE_SIDED_INVERTED then 
		return {
			{
				x = self.hx, 
				z = self.hz
			},
			{
				x = self.sx, 
				z = self.sz
			},
			{
				x = self.wx,
				z = self.wz,
			},
			{
				x = self.wx + self.dirXLength * self.length, 
				z = self.wz + self.dirZLength * self.length
			},
		}
	else
		return {
				{
					x = self.sx, 
					z = self.sz
				},
				{
					x = self.sx + self.dirXLength * self.length, 
					z = self.sz + self.dirZLength * self.length
				},
			},
			{
				{
					x = self.wx, 
					z = self.wz,
				},
				{
					x = self.wx + self.dirXLength * self.length, 
					z = self.wz + self.dirZLength * self.length
				},
			}
	end
end

function CpBunkerSilo:getPlot()
	return self.plot	
end

--------------------------------------------------
--- Manage nearby unloaders
--------------------------------------------------

--- Does the vehicle have a trailer and also is controlled by a player or AD.
--- TODO: Maybe add fill typ check ?
function CpBunkerSilo:isValidUnloader(vehicle)
	if AIUtil.hasChildVehicleWithSpecialization(vehicle, Trailer) then 
		if vehicle.getIsControlled and vehicle:getIsControlled() then 
			return true
		end
		if vehicle.ad and vehicle.ad.stateModule and vehicle.ad.stateModule:isActive() then
			return true
		end
	end
	return false
end

function CpBunkerSilo:hasNearbyUnloader()
	return self.numNearbyUnloaders > 0
end

function CpBunkerSilo:shouldUnloadersWaitForSiloWorker()
	local needsWaiting = false
	for _, controller in pairs(self.controllers) do 
		needsWaiting = needsWaiting or not controller:isWaitingForUnloaders() 
	end
	return needsWaiting
end

function CpBunkerSilo:addNearbyUnloader(vehicle)
	if not self.nearbyUnloaders[vehicle.rootNode] then
		self.nearbyUnloaders[vehicle.rootNode] = vehicle
		self.numNearbyUnloaders = self.numNearbyUnloaders + 1
		vehicle:addDeleteListener(self, "removeNearbyUnloader")
	end
end

function CpBunkerSilo:removeNearbyUnloader(vehicle)
	if self.nearbyUnloaders[vehicle.rootNode] then 
		self.nearbyUnloaders[vehicle.rootNode] = nil
		self.numNearbyUnloaders = self.numNearbyUnloaders - 1
		vehicle:removeDeleteListener(self, "removeNearbyUnloader")
	end
end

function CpBunkerSilo:getNearbyUnloaders()
	return self.nearbyUnloaders
end

function CpBunkerSilo:updateUnloaders(dt)
	--- Searches for new unloaders in the unloader area and remove unloaders, that left.
	if self.numControllers > 0 and g_updateLoopIndex % 7 == 0 then 
		for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
			local isValid = false
			if self:isValidUnloader(vehicle) then 
				for _, v in pairs(vehicle:getChildVehicles()) do 
					local x, _, z = getWorldTranslation(v.rootNode)
					if self:isUnloaderInSilo(x, z) then
						isValid = true
					end 
				end
			end
			if isValid then 
				self:addNearbyUnloader(vehicle)
			else
				self:removeNearbyUnloader(vehicle)
			end
		end
	end
	if self:shouldUnloadersWaitForSiloWorker() then
		--- Makes sure the AD driver wait for the silo worker. 
		for _, unloader in pairs(self.nearbyUnloaders) do
			if unloader.spec_autodrive and unloader.spec_autodrive.HoldDriving then 
				unloader.spec_autodrive:HoldDriving(unloader)
			end
		end
	end
end

--- Is the unloader in the silo or in front of the silo.
--- For silos without a back wall also check the back area of the silo.
function CpBunkerSilo:isUnloaderInSilo(x, z)
	return self:isPointInSilo(x, z) or 
			self:isPointInArea(x, z, self:getFrontArea())
			or self.siloMode == self.SIDE_MODES.OPEN and self:isPointInArea(x, z, self:getBackArea()) 
end

function CpBunkerSilo:drawUnloaderArea()
	self:drawArea(self:getFrontArea())
	if self.siloMode == self.SIDE_MODES.OPEN then
		self:drawArea(self:getBackArea())
	end
end

function CpBunkerSilo:getDebugData()
	local data = {
		{
			name = "unloaders should wait: ",
			value = self:shouldUnloadersWaitForSiloWorker()
		}
	}
	for _, unloader in pairs(self.nearbyUnloaders) do 
		if unloader.ad and unloader.ad.stateModule and unloader.ad.stateModule:isActive() then
			table.insert(data, {
				name = "nearby unloader", 
				value = "AD: ".. CpUtil.getName(unloader)
			})
		else 
			table.insert(data, {
				name = "nearby unloader", 
				value = CpUtil.getName(unloader)
			})
		end
	end
	return data
end
