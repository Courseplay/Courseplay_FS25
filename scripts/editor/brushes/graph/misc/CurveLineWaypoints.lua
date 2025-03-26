
--- Connects two waypoints.
---@class BrushCurve : BrushStraightLine
BrushCurve = CpObject(BrushStraightLine)
BrushCurve.MIN_OFFSET = -1
BrushCurve.MAX_OFFSET = 1
BrushCurve.MIN_CENTER = 0
BrushCurve.MAX_CENTER = 1
BrushCurve.START_CENTER = 0.5
BrushCurve.START_OFFSET = 0

function BrushCurve:init(...)
	BrushStraightLine.init(self, ...)
	self.supportsSecondaryAxis = true
	self.secondaryAxisIsContinuous = true
	self.primaryAxisIsContinuous = true
	self.offset = 0
	self.center = self.START_CENTER
end

--- De-Casteljau algorithm
function BrushCurve:getNextPoint(t,points)
	local q0_x, q0_y = (1-t) * points[1][1] + t * points[2][1],
					(1-t) * points[1][2] + t * points[2][2]
	local q1_x, q1_y = (1-t) * points[2][1] + t * points[3][1],
					(1-t) * points[2][2] + t * points[3][2]
	
	return (1-t)*q0_x + t*q1_x, (1-t)*q0_y + t*q1_y
end

function BrushCurve:moveWaypoints()
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
	local spacing = 2
	local nx, nz = MathUtil.vector2Normalize(x-tx, z-tz)
	if nx == nil or nz == nil then 
		nx = 0
		nz = 1
	end
	local distCenter = dist*self.center
	local ax, az = tx + nx * distCenter, tz + nz * distCenter
	--- Rotation
	local ncx = nx  * math.cos(math.pi/2) - nz  * math.sin(math.pi/2)
	local ncz = nx  * math.sin(math.pi/2) + nz  * math.cos(math.pi/2)
	--- Translation
	local cx, cz = ax + ncx * self.offset * dist, az + ncz * self.offset * dist
	local halfDist = MathUtil.vector2Length(cx - tx, cz - tz)
	local dt = 2/(1.5*halfDist)
	local n = math.ceil(halfDist/spacing)
	spacing = halfDist/n
	local points = {
		{
			tx,
			tz
		},
		{
			cx,
			cz
		},
		{
			x,
			z
		}
	}

	local dx, dz
	for t=dt , 1, dt do 
		dx, dz = BrushCurve:getNextPoint(t,points)
		self.graphWrapper:addTemporaryPoint(dx, y, dz)
	end
end

function BrushCurve:onAxisPrimary(inputValue)
	self.offset = math.clamp(self.offset+inputValue/50,self.MIN_OFFSET,self.MAX_OFFSET)
	self:setInputTextDirty()
end

function BrushCurve:onAxisSecondary(inputValue)
	self.center = math.clamp(self.center+inputValue/50,self.MIN_CENTER,self.MAX_CENTER)
	self:setInputTextDirty()
end

function BrushCurve:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end

function BrushCurve:getAxisPrimaryText()
	return self:getTranslation(self.primaryAxisText, self.offset) 
end

function BrushCurve:getAxisSecondaryText()
	return self:getTranslation(self.secondaryAxisText, self.center)
end
