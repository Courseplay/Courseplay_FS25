
--- Creates a new segement with a point at the mouse position.
---@class CreateSegmentBrush : GraphBrush
CreateSegmentBrush = CpObject(GraphBrush)

function CreateSegmentBrush:init(...)
	GraphBrush.init(self, ...)
	self.supportsPrimaryButton = true
end

function CreateSegmentBrush:onButtonPrimary()
	if self:getHoveredNodeId() then 
		self:setError()
		return
	end
	local x, y, z = self.cursor:getPosition()
	if not self.graphWrapper:createSegmentWithPoint(x, y, z) then 
		self:setError()
	end
end

function CreateSegmentBrush:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end
