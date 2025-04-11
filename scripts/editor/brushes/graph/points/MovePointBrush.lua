
--- Moves a waypoint relative to the mouse position.
---@class MovePointBrush : GraphBrush
MovePointBrush = CpObject(GraphBrush)

function MovePointBrush:init(...)
	GraphBrush.init(self, ...)
	self.supportsPrimaryButton = true
	self.supportsPrimaryDragging = true

	return self
end

function MovePointBrush:onButtonPrimary(isDown, isDrag, isUp)
	if isDown then
		self.graphWrapper:setSelected(self:getHoveredNodeId())
	end
	if isDrag and self.graphWrapper:hasSelectedNode() then 
		local id = self.graphWrapper:getFirstSelectedNodeID()
		local x, y, z = self.cursor:getPosition()
		self.graphWrapper:movePointByIndex(id, x, y, z)
	end
	if isUp then
		local id = self.graphWrapper:getFirstSelectedNodeID()
		local segment = self.graphWrapper:getSegmentByIndex(id)
		if segment then 
			GraphRebuildSegmentEvent.sendEvent(segment)
		end
		self.graphWrapper:resetSelected()
	end
end

function MovePointBrush:activate()
	self.graphWrapper:resetSelected()
end

function MovePointBrush:deactivate()
	local id = self.graphWrapper:getFirstSelectedNodeID()
	local segment = self.graphWrapper:getSegmentByIndex(id)
	if segment then 
		GraphRebuildSegmentEvent.sendEvent(segment)
	end
	self.graphWrapper:resetSelected()
end

function MovePointBrush:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end