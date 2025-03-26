
--- Connects two waypoints.
---@class BrushStraightLine : BrushConnect
BrushStraightLine = CpObject(BrushConnect)
BrushStraightLine.DELAY = 1 --- The mouse event oscillates.., so we have to wait one update tick before release is allowed.
BrushStraightLine.MIN_DIST = 2
BrushStraightLine.MAX_DIST = 20
BrushStraightLine.START_DIST = 6

function BrushStraightLine:init(...)
	BrushConnect.init(self, ...)
	self.supportsPrimaryAxis = true

	self.spacing = self.START_DIST
	self.delay = g_updateLoopIndex
	self.startAnchorWaypointId = nil
end

function BrushStraightLine:onButtonPrimary(isDown, isDrag, isUp)
	if isDown then
		if not self.graphWrapper:hasTemporaryPoints() and self.startAnchorWaypointId == nil then 
			local nodeId = self:getHoveredNodeId()
			if nodeId then 
				self.startAnchorWaypointId = nodeId
				self.graphWrapper:setSelected(self.startAnchorWaypointId)
				self:debug("Start with node: %d", nodeId)
			else 
				local x, y, z = self.cursor:getPosition()	
				self.graphWrapper:addTemporaryPoint(x, y, z)
				self:debug("Start with a new temp node")
			end
			self.delay = g_updateLoopIndex + self.DELAY
		end
	end
	if isDrag and (self.graphWrapper:hasTemporaryPoints() or self.startAnchorWaypointId ~= nil) then 
		self:moveWaypoints()
	end
	if isUp then 
		if g_updateLoopIndex > self.delay and self.graphWrapper:hasTemporaryPoints() then 
			local tempWaypoints = self.graphWrapper:getTemporaryPoints()
			self:debug("Finished drawing of %d waypoints.", #tempWaypoints)
			self.graphWrapper:createSplineFromTemporyPoints(self.startAnchorWaypointId, self:getHoveredNodeId(), 
				self:getIsReverse(), self:getIsSubPrio(), self:getIsCrossing())
		end
		self.graphWrapper:resetTemporaryPoints()
		self.graphWrapper:resetSelected()
		self.startAnchorWaypointId = nil
	end
end

function BrushStraightLine:moveWaypoints()
	local x, y, z = self.cursor:getPosition()
	if x == nil then 
		return
	end
	local waypoints = self.graphWrapper:cloneTemporaryPoints()
	self.graphWrapper:clearTemporaryPoints()
	local tx, ty, tz = 0, 0, 0
	if self.startAnchorWaypointId ~= nil then 
		tx, ty, tz = self.graphWrapper:getPosition(self.startAnchorWaypointId)
	else 
		tx, ty, tz = waypoints[1].x, waypoints[1].y, waypoints[1].z
		self.graphWrapper:addTemporaryPoint(tx, ty, tz)
	end
	local dist = MathUtil.vector2Length(x-tx,z-tz)
	if dist <= 1 then 
		return
	end
	local spacing = self.spacing
	local nx, nz = MathUtil.vector2Normalize(x-tx, z-tz)
	if nx == nil or nz == nil then 
		nx = 0
		nz = 1
	end
	local n = math.max(math.ceil(dist/spacing), 2)
	spacing = dist/n
	for i = 1, n + 1 do 
		local dx, dy, dz = tx + nx * i * spacing, y, tz + nz * i * spacing
		self.graphWrapper:addTemporaryPoint(dx, dy, dz)
	end
end

function BrushStraightLine:update(dt)
	BrushConnect.update(self, dt)
	self.graphWrapper:updateTemporaryPoints(
		self:getIsReverse(), self:getIsSubPrio(), self:getIsCrossing())
end

function BrushStraightLine:onAxisPrimary(inputValue)
	self:setSpacing(inputValue)
	self:setInputTextDirty()
end

function BrushStraightLine:setSpacing(inputValue)
	self.spacing = math.clamp(self.spacing + inputValue, self.MIN_DIST, self.MAX_DIST)
end

function BrushStraightLine:activate()
	self.graphWrapper:resetTemporaryPoints()
	self.startAnchorWaypointId = nil
	BrushConnect.activate(self)
end

function BrushStraightLine:deactivate()
	self.graphWrapper:resetTemporaryPoints()
	self.graphWrapper:resetSelected()
	self.startAnchorWaypointId = nil
	BrushConnect.deactivate(self)
end

function BrushStraightLine:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end

function BrushStraightLine:getAxisPrimaryText()
	return self:getTranslation(self.primaryAxisText, self.spacing)
end

