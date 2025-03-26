
--- Creates a new segement with a point at the mouse position.
---@class ChangeSegmentTypBrush : GraphBrush
ChangeSegmentTypBrush = CpObject(GraphBrush)

function ChangeSegmentTypBrush:init(...)
	GraphBrush.init(self, ...)
	self.supportsPrimaryButton = true
end

function ChangeSegmentTypBrush:onButtonPrimary()
	local nodeId = self:getHoveredNodeId()  
	local success, err = self.graphWrapper:changeSegmentDirection(nodeId)
	if not success then 
		self:setError(err)
	end
end

function ChangeSegmentTypBrush:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end
