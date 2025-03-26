
--- Creates a new waypoint at the mouse position.
---@class DeletePointBrush : GraphBrush
DeletePointBrush = CpObject(GraphBrush)

function DeletePointBrush:init(...)
	GraphBrush.init(self, ...)
	self.supportsPrimaryButton = true
	self.supportsPrimaryDragging = true
	-- self.supportsPrimaryAxis = true
	return self
end

function DeletePointBrush:onButtonPrimary(isDown, isDrag, isUp)
	local nodeId = self:getHoveredNodeId()	
	if nodeId ~= nil then 
		if isDown or isDrag then
			local succes, err = self.graphWrapper:removePointByIndex(nodeId)
			if not succes  then 
				self:setError(err)
			end
		end
	end
end

function DeletePointBrush:onAxisPrimary(delta)
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

function DeletePointBrush:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end

function DeletePointBrush:getAxisPrimaryText()
	return self:getTranslation(self.primaryAxisText, self.sizeModifier)
end