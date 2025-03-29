
--- Creates a new waypoint at the mouse position.
---@class CreateTargetBrush : GraphBrush
CreateTargetBrush = CpObject(GraphBrush)
function CreateTargetBrush:init(...)
	GraphBrush.init(self, ...)
	self.supportsPrimaryButton = true
	--self.supportsPrimaryDragging = true
end

function CreateTargetBrush:onButtonPrimary()
	local nodeId = self:getHoveredNodeId()
	if nodeId ~= nil then
		local found = self.graphWrapper:hasTargetByIndex(nodeId)
		if found then
			self:setError("err_already_has_target")
			return
		end
		self:openTextInput(function(self, text, clickOk, nodeId)
			if clickOk then 
				self.graphWrapper:createTargetForIndex(nodeId, text)
			end
		end, self:getTranslation(self.inputTitle), nodeId)
	end
end
function CreateTargetBrush:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end
