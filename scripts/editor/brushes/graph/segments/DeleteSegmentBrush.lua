
--- Creates a new waypoint at the mouse position.
---@class DeleteSegmentBrush : GraphBrush
DeleteSegmentBrush = CpObject(GraphBrush)

function DeleteSegmentBrush:init(...)
	GraphBrush.init(self, ...)
	self.supportsPrimaryButton = true
	self.supportsPrimaryDragging = true
	self.supportsPrimaryAxis = true
	return self
end

function DeleteSegmentBrush:onButtonPrimary(isDown, isDrag, isUp)
	local nodeId = self:getHoveredNodeId()	
	if nodeId ~= nil then 
		if isDown or isDrag then
			if not self.graphWrapper:removeSegmentByPointIndex(nodeId) then 
				self:setError()
			end
		end
	end
end

function DeleteSegmentBrush:onAxisPrimary(delta)
	local d = self.sizeModifier + delta
	if d > self.sizeModifierMax then 
		self:changeSizeModifier(1)
	elseif d <= 0 then 
		self:changeSizeModifier(self.sizeModifierMax)
	else
		self:changeSizeModifier(d)
	end
	self:setInputTextDirty()
end

function DeleteSegmentBrush:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end

function DeleteSegmentBrush:getAxisPrimaryText()
	return self:getTranslation(self.primaryAxisText, self.sizeModifier)
end