
--- Creates a new waypoint at the mouse position.
---@class RenameTargetBrush : GraphBrush
RenameTargetBrush = CpObject(GraphBrush)

function RenameTargetBrush:init(...)
	GraphBrush.init(self, ...)
	self.supportsPrimaryButton = true
	--self.supportsPrimaryDragging = true
end

function RenameTargetBrush:onButtonPrimary()
	local nodeId = self:getHoveredNodeId()
	if nodeId ~= nil then
		local target, err = self.graphWrapper:getTargetForIndex(nodeId)
		if not target then
			self:setError(err)
			return
		end
		self:openTextInput(function(self, text, clickOk, target)
			if clickOk then 
				target:rename(text)
			end
		end, self:getTranslation(self.inputTitle, target:getName()), target)
	end
end

function RenameTargetBrush:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end