

--- Creates a new waypoint at the mouse position.
---@class DeleteTargetBrush : GraphBrush
DeleteTargetBrush = CpObject(GraphBrush)

function DeleteTargetBrush:init(...)
	GraphBrush.init(self, ...)
	self.supportsPrimaryButton = true
	--self.supportsPrimaryDragging = true
end

function DeleteTargetBrush:onButtonPrimary()
	local nodeId = self:getHoveredNodeId()
	if nodeId ~= nil then
		local target, err = self.graphWrapper:getTargetForIndex(nodeId)
		if not target then
			self:setError(err)
			return
		end
		self:showYesNoDialog(function()
			self.graphWrapper:removeTargetForIndex(nodeId)
		end, self:getTranslation(self.yesNoTitle, target:getName()), nodeId)
	end
end

function DeleteTargetBrush:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end