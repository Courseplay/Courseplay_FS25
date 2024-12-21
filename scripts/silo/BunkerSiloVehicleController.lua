--- Controls a driver in the bunker silo. 
---@class CpBunkerSiloVehicleController
CpBunkerSiloVehicleController = CpObject()
CpBunkerSiloVehicleController.WALL_OFFSET = 0.5
function CpBunkerSiloVehicleController:init(silo, vehicle, driveStrategy, directionNode)
	self.debugChannel = CpDebug.DBG_SILO
	
	---@type CpBunkerSilo
	self.silo = silo
	self.vehicle = vehicle
	self.driveStrategy = driveStrategy
	self.directionNode = directionNode
	self.isInverted = false

	local sx, sz = self.silo:getStartPosition()
	local hx, hz = self.silo:getHeightPosition()

	local _, _, dsz = worldToLocal(directionNode, sx, 0, sz)
	local _, _, dhz = worldToLocal(directionNode, hx, 0, hz)

	if self.silo.siloMode == CpBunkerSilo.SIDE_MODES.ONE_SIDED_INVERTED then
		self.isInverted = true
	elseif self.silo.siloMode ~= CpBunkerSilo.SIDE_MODES.ONE_SIDED then
		if dsz > 0 and dhz > 0 then 
			self:debug("Start distance: dsz: %.2f, dhz: %.2f", dsz, dhz)
			--- In front of the silo
			--[[
					hx
				|	|
				wx	sx
				  
				  ^
				  |
			]]
			if dsz > dhz then 
				self:debug("Silo needs to be inverted.")
				self.isInverted = true
			end
		elseif dsz > 0 and dhz < 0 then 
			self:debug("Start distance: dsz: %.2f, dhz: %.2f", dsz, dhz)
			--- Is in the silo but in the wrong direction.
			--[[
					hx
				| |	|
				| v	|
				wx	sx  
			]]
			self.isInverted = true
		elseif dsz < 0 and dhz > 0 then 
			self:debug("Start distance: dsz: %.2f, dhz: %.2f", dsz, dhz)
			--- Is in the silo and in the correct direction.
			--[[
					hx
				| ^	|
				| |	|
				wx	sx  
			]]
		elseif dsz < 0 and dhz < 0 then 
			self:debug("Start distance: dsz: %.2f, dhz: %.2f", dsz, dhz)
			--- Exited the silo
			--[[
			  ^
			  |
				hx
			| 	|
			| 	|
			wx	sx  
			]]
			if dsz < dhz then 
				self:debug("Silo needs to be inverted.")
				self.isInverted = true
			end
		end
	end
end

function CpBunkerSiloVehicleController:delete()
	
end

--- Gets the direction into the silo
--- Automatically adjust for the vehicle start position,
--- as a silo might be inverted depending on the vehicle starting point.
function CpBunkerSiloVehicleController:getDriveIntoDirection()
	local dirX, dirZ = self.silo:getLengthDirection()
	if self.isInverted then 
		dirX, dirZ = -dirX, -dirZ
	end
	return dirX, dirZ
end

--- Gets the drive data for the drive strategy.
---@param width number
---@return {x : number, z : number} start position 
---@return {dx : number, dz : number} end position 
function CpBunkerSiloVehicleController:getTarget(width)
	
	local widthCount, siloWidth = 0, self.silo:getWidth()
	widthCount = math.ceil(siloWidth/width)
	local unitWidth = siloWidth/widthCount
	self:debug('Bunker width: %.1f, working width: %.1f (passed in), unit width: %.1f', siloWidth, width, unitWidth)
	self:generateMaps(width, unitWidth, widthCount)

	local targetLine = self:getNextLine(widthCount, width)
	self:debug("target line: %d", targetLine)

	local x, z, dx, dz = self:getPositionsForLine(targetLine, width, widthCount, unitWidth)
	self.lastLine = targetLine
	self.drivingTarget = {{x, z}, {dx, dz}}
	return {x, z}, {dx, dz}	
end

--- Gets the last generated target.
function CpBunkerSiloVehicleController:getLastTarget()
	return unpack(self.drivingTarget)
end

--- Gets a lane to drive into the silo from.
---@param line number target line in the bunker silo
---@param width number correct width of a single line
---@param widthCount number total number of lines
---@param unitWidth number 
---@return number x start point
---@return number z start point
---@return number dx end point
---@return number dz end point
function CpBunkerSiloVehicleController:getPositionsForLine(line, width, widthCount, unitWidth)
	local x, z
	local sx, sz = self.silo:getStartPosition()
	local dirXWidth, dirZWidth = self.silo:getWidthDirection()
	local dirXLength, dirZLength = self.silo:getLengthDirection()
	local siloWidth = self.silo:getWidth()
	local siloLength = self.silo:getLength()
	if line == 1 then
		x = sx + dirXWidth * (width/2 + self.WALL_OFFSET)
		z = sz + dirZWidth * (width/2 + self.WALL_OFFSET)
	elseif line == widthCount then 
		x = sx + dirXWidth * (siloWidth - width/2 - self.WALL_OFFSET)
		z = sz + dirZWidth * (siloWidth - width/2 - self.WALL_OFFSET)
	else
		x = sx + dirXWidth * (line * unitWidth - unitWidth/2)
		z = sz + dirZWidth * (line * unitWidth - unitWidth/2)
	end

	local dx = x + dirXLength * siloLength
	local dz = z + dirZLength * siloLength

	if self.isInverted then 
		x, z, dx, dz = dx, dz, x, z
	end
	return x, z, dx, dz
end

--- Gets the next line to drive.
function CpBunkerSiloVehicleController:getNextLine(numLines, width)
	return 1
end

--- Gets the first line relative to the vehicle position
---@param numLines any
---@param width any
---@return unknown
function CpBunkerSiloVehicleController:getFirstLineApproach(numLines, width)
	local sx, sz = self.silo:getStartPosition()
	local hx, hz = self.silo:getHeightPosition()
	if self.isInverted then 
		sx, sz, hx, hz = hx, hz, sx, sz
	end

	local dsx, _, _ = worldToLocal(self.directionNode, sx, 0, sz)
	local dhx, _, _ = worldToLocal(self.directionNode, hx, 0, hz)
	local line = 1
	if dsx > 0 then 
		line = MathUtil.round(dsx / width)
	elseif dhx > 0 then
		line = MathUtil.round(dhx / width)
	end
	return CpMathUtil.clamp(line, 1, numLines)
end


function CpBunkerSiloVehicleController:debug(...)
	CpUtil.debugVehicle(self.debugChannel, self.vehicle,  ...)	
end

--- Tells the driver, that the bunker silo was deleted.
function CpBunkerSiloVehicleController:setBunkerSiloInvalid()
	self.driveStrategy:stopSiloWasDeleted()
end

function CpBunkerSiloVehicleController:draw()
	if self:isDebugEnabled() then
		if self.map then
			for i, lineData in ipairs(self.map) do 
				local line = self.lineMap[i]
				local x, z, dx, dz = unpack(line)
				local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z)
				local dy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, dx, 0, dz)
				drawDebugLine(x, y + 2, z, 1, 0, 1, dx, dy + 2, dz, 0, 1, 1)
				local numRows = #lineData
				for j, data in ipairs(lineData) do
					local x1, z1, x2, z2, x3, z3 = unpack(data)
					DebugUtil.drawDebugAreaRectangle(x1, y + 3, z1, 
						x2, y + 3, z2, 
						x3, y + 3, z3,
						false, 0.5 , 0.5, j/numRows, 0.2)
				end
			end
		end
	end
end

function CpBunkerSiloVehicleController:isDebugEnabled()
	return CpDebug:isChannelActive(self.debugChannel, self.vehicle)
end

--- Is the end of the silo reached.
---@param node number
---@param margin number
---@return boolean end reached?
---@return number distance to the end 
function CpBunkerSiloVehicleController:isEndReached(node, margin)
	if self.drivingTarget then
		local x, _, z = localToWorld(node, 0, 0, margin)
		local dx, dz = unpack(self.drivingTarget[2])
		local dist = MathUtil.vector2Length(x - dx, z - dz)
		return not self.silo:isPointInSilo(x, z) and dist < 5, CpMathUtil.clamp(2 * dist, 5, math.huge)
	end
	return false, math.huge
end

--- Generates a silo map with lines and a map with rectangle tiles.
---@param width number
---@param unitWidth number
---@param widthCount number
function CpBunkerSiloVehicleController:generateMaps(width, unitWidth, widthCount)
	self.lineMap = {}
	self.map = {}
	local x, z, dx, dz
	local x1, z1, x2, z2, x3, z3
	local lengthCount = math.ceil(self.silo:getLength() / unitWidth)
	local unitLength = self.silo:getLength() / lengthCount
	local lenDirX, lenDirZ = self.silo:getLengthDirection()
	local widthDirX, widthDirZ = self.silo:getWidthDirection()
	local sx, sz = self.silo:getStartPosition()
	for i = 1, widthCount do 
		x, z, dx, dz = self:getPositionsForLine(i, width, 
			widthCount, unitWidth)
		table.insert(self.lineMap, {x, z, dx, dz})
		self.map[i] = {}
		for j=0, lengthCount - 1 do 
			x1 = sx + j * lenDirX * unitLength + (i - 1) * widthDirX * unitWidth
			z1 = sz + j * lenDirZ * unitLength + (i - 1) * widthDirZ * unitWidth
			x2, z2 = x1 + widthDirX * unitWidth,  z1 + widthDirZ * unitWidth
			x3, z3 = x1 + lenDirX   * unitLength, z1 + lenDirZ * unitLength
			table.insert(self.map[i], {x1, z1, x2, z2, x3, z3})
		end
	end
end

--- Silo controller for a Bunker silo leveler driver.
--- Handles the bunker silo lines and the automatic 
--- selection of the next line for a new approach.
---@class CpBunkerSiloLevelerController : CpBunkerSiloVehicleController
CpBunkerSiloLevelerController = CpObject(CpBunkerSiloVehicleController)
CpBunkerSiloLevelerController.LAST_DIRECTIONS = {
	LEFT = 0,
	RIGHT = 1
}
function CpBunkerSiloLevelerController:init(silo, vehicle, driveStrategy, directionNode)
	CpBunkerSiloVehicleController.init(self, silo, vehicle, 
		driveStrategy, directionNode)
	self.lastLine = nil
	self.currentTarget = nil
	self.lastDirection = self.LAST_DIRECTIONS.LEFT
end


function CpBunkerSiloLevelerController:hasNearbyUnloader()
	return self.silo:hasNearbyUnloader()
end

function CpBunkerSiloLevelerController:isWaitingForUnloaders()
	return self.driveStrategy:isWaitingForUnloaders()
end

function CpBunkerSiloLevelerController:isWaitingAtParkPosition()
	return self.driveStrategy:isWaitingAtParkPosition()
end

--- Gets the next line to drive.
---@param numLines number
---@param width number
---@return number new line to drive on
function CpBunkerSiloLevelerController:getNextLine(numLines, width)
	if self.lastLine == nil then 
		return self:getFirstLineApproach(numLines, width)
	end
	local nextLine, nextDirection
	if self.lastDirection == self.LAST_DIRECTIONS.LEFT then 
		--- 4-3-2-1
		if self.lastLine <= 1 then
			nextLine = math.min(self.lastLine + 1, numLines)
			nextDirection = self.LAST_DIRECTIONS.RIGHT
		else 
			nextLine = self.lastLine - 1
			nextDirection = self.LAST_DIRECTIONS.LEFT
		end
	else
		--- 2-3-4-5
		if self.lastLine >= numLines then
			nextLine = math.max(self.lastLine - 1, 1)
			nextDirection = self.LAST_DIRECTIONS.LEFT
		else 
			nextLine = self.lastLine + 1
			nextDirection = self.LAST_DIRECTIONS.RIGHT
		end
	end
	self.lastDirection = nextDirection
	return nextLine
end

function CpBunkerSiloLevelerController:draw()
	CpBunkerSiloVehicleController.draw(self)
	if self:isDebugEnabled() then
		self.silo:drawDebug()
		self.silo:drawUnloaderArea()
		if CpUtil.getCurrentVehicle() == self.vehicle then
			local debugData = self.silo:getDebugData()
			table.insert(debugData, 1, {
				name = "is waiting", value = self:isWaitingAtParkPosition()
			})
			DebugUtil.renderTable(0.4, 0.4, 0.018, debugData, 0)
		end
	end
end

--- Controls the driving lines into the silo,
--- based on the fill level in the lines.
---@class CpBunkerSiloLoaderController : CpBunkerSiloVehicleController
CpBunkerSiloLoaderController = CpObject(CpBunkerSiloVehicleController)

function CpBunkerSiloLoaderController:init(silo, vehicle, driveStrategy)
	CpBunkerSiloVehicleController.init(self, silo, vehicle, 
		driveStrategy, vehicle:getAIDirectionNode())

	local sx, sz = self.silo:getStartPosition()
	local hx, hz = self.silo:getHeightPosition()
	local dx, _, dz = getWorldTranslation(vehicle:getAIDirectionNode())
	self.isInverted = false
	
	if MathUtil.vector2Length(sx-dx, sz-dz) < MathUtil.vector2Length(hx-dx, hz-dz) then
		if self.silo.siloMode == CpBunkerSilo.SIDE_MODES.ONE_SIDED_INVERTED then 
			self.isInverted = true
		end
	else
		self.isInverted = true
		if self.silo.siloMode == CpBunkerSilo.SIDE_MODES.ONE_SIDED then 
			self.isInverted = false
		end
	end

end

--- Gets the next line with the most fill level.
---@param width number
---@return number next lane to take.
function CpBunkerSiloLoaderController:getLineWithTheMostFillLevel(width)
	local bestLine, mostFillLevel, fillType, fillLevel = 1, 0, nil, 0
	local numLengthTiles = #self.map[1]
	self.bestLoadTarget = nil
	local bestRow = math.huge
	local firstRow, lastRow, deltaRow = 1, numLengthTiles, 1
	if self.isInverted then 
		bestRow = 1
		firstRow, lastRow, deltaRow = numLengthTiles, 1, -1
	end
	for row = firstRow, lastRow, deltaRow do 
		for line, lineData in ipairs(self.map) do 
			local sx, sz, wx, wz, hx, hz = unpack(lineData[row])
			fillType = DensityMapHeightUtil.getFillTypeAtArea(sx, sz, wx, wz, hx, hz)
			if fillType and fillType ~= 0 then 
				fillLevel = DensityMapHeightUtil.getFillLevelAtArea(
					fillType, sx, sz, wx, wz, hx, hz)
				self:debug("Line(%d) and row(%d) has %.2f of %s", line, row, fillLevel, 
					g_fillTypeManager:getFillTypeByIndex(fillType).title)
				if fillLevel > mostFillLevel then
					--- Searches for the closest row with the most fill level 
					if self.isInverted then 
						if row >= bestRow then 
							self:debug("New best line %d with row %d", line, row)
							mostFillLevel = fillLevel
							bestLine = line
							bestRow = row
							fillType = fillType
							self.bestLoadTarget = {
								sx, sz, wx, wz, hx, hz
							}
						end
					elseif row <= bestRow then
						self:debug("New best line %d with row %d", line, row)
						mostFillLevel = fillLevel
						bestLine = line
						bestRow = row
						fillType = fillType
						self.bestLoadTarget = {
							sx, sz, wx, wz, hx, hz
						}
					end
				end
				
			end
		end
	end
	return bestLine
end

--- Gets the next line with the most fill level.
---@param numLines number
---@param width number
---@return number next lane to take.
function CpBunkerSiloLoaderController:getNextLine(numLines, width)
	return self:getLineWithTheMostFillLevel(width)
end


--- Is the end of the silo reached.
---@param node number
---@param margin number
---@return boolean end reached?
---@return number distance to the end 
function CpBunkerSiloLoaderController:isEndReached(node, margin)
	if self.drivingTarget then
		local dx, dz = unpack(self.drivingTarget[2])
		local _, _, zOffset = localToLocal(node, AIUtil.getDirectionNode(self.vehicle), 0, 0, 0)
		local _, _, z = worldToLocal(AIUtil.getDirectionNode(self.vehicle), dx, 0, dz)
		self:debug("Silo/heap end offset %.1f", z-zOffset)
		return z - zOffset < margin, CpMathUtil.clamp(z * 2, 5, math.huge)
	end
	return false, math.huge
end

function CpBunkerSiloLoaderController:draw()
	if self:isDebugEnabled() then
		if self.bestLoadTarget then
			local x1, z1, x2, z2, x3, z3 = unpack(self.bestLoadTarget)
			local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x1, 0, z1)
			DebugUtil.drawDebugAreaRectangle(x1, y + 3.5, z1, 
				x2, y + 3.5, z2, 
				x3, y + 3.5, z3,
				false, 0 , 1, 0)
			DebugUtil.drawDebugLine(x2, y + 3.5, z2, 
				x3, y + 3.5, z3, 
				0, 1, 0)
		end
	end
	CpBunkerSiloVehicleController.draw(self)
end