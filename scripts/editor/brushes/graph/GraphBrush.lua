--[[
	Brushes that can be used for waypoint selection/manipulation.
]]
---@class GraphBrush : CpBrush
GraphBrush = CpObject(CpBrush)
GraphBrush.radius = 1
GraphBrush.sizeModifierMax = 10
function GraphBrush:init(...)
	CpBrush.init(self, ...)
	self.sizeModifier = 1
	---@type EditorGraphWrapper
	self.graphWrapper = self.courseWrapper
end

function GraphBrush:changeSizeModifier(modifier)
	self.sizeModifier = modifier
	self.cursor:setShapeSize(self.radius * modifier * (1+self.camera.zoomFactor))	
end

---@param point GraphPoint
---@param x number
---@param y number
---@param z number
---@return boolean|nil
function GraphBrush:isAtPos(point, x, y, z)
	local dx, dy, dz = point:getPosition()
	if MathUtil.getPointPointDistance(dx, dz, x, z) < self.radius * self.sizeModifier * (1 + self.camera.zoomFactor) then 
		return math.abs(dy + 2 - y) < 3
	end
end

---@param excludeLambda any
---@return string|nil
function GraphBrush:getHoveredNodeId(excludeLambda)
	local x, y, z = self.cursor:getPosition()
	-- try to get a waypoint in mouse range
	for _, point in pairs(self.graphWrapper:getVisiblePoints()) do
		if self:isAtPos(point, x, y, z) then
			if excludeLambda == nil or not excludeLambda(point:getRelativeID()) then
				return point:getRelativeID()
			end
		end
	end
end

function GraphBrush:update(dt)
	self.graphWrapper:setHovered(self:getHoveredNodeId())
	--- Updates the cursor size depending on the zoom.
	self.cursor:setShapeSize(self.radius * self.sizeModifier * (1 + self.camera.zoomFactor))	
	if self.errorMsgTimer:get() then
		self.cursor:setErrorMessage(self:getErrorMessage())
	end
end