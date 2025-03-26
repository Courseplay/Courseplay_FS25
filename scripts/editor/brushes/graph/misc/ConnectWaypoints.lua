
--- Connects two waypoints.
---@class BrushConnect : GraphBrush
BrushConnect = CpObject(GraphBrush)

BrushConnect.TYPE_NORMAL = 1
BrushConnect.TYPE_LOW_PRIO = 2
BrushConnect.TYPE_CROSSING = 3
BrushConnect.TYPE_CROSSING_LOW_PRIO = 4
BrushConnect.TYPE_REVERSE_NORMAL = 5
BrushConnect.TYPE_DISCONNECT = 6
BrushConnect.TYPE_MIN = 1
BrushConnect.TYPE_MAX = 6

BrushConnect.typeTexts = {
	[BrushConnect.TYPE_NORMAL] = "type_normal",
	[BrushConnect.TYPE_LOW_PRIO] = "type_sub_route",
	[BrushConnect.TYPE_REVERSE_NORMAL] = "type_reverse_route",
	[BrushConnect.TYPE_CROSSING] = "type_crossing_route",
	[BrushConnect.TYPE_CROSSING_LOW_PRIO] = "type_sub_crossing_route",
	[BrushConnect.TYPE_DISCONNECT] = "type_disconnect_route",
}

function BrushConnect:init(...)
	GraphBrush.init(self, ...)
	self.supportsPrimaryButton = true
	self.supportsPrimaryDragging = true
	self.supportsSecondaryButton = true
	self.supportsTertiaryButton = true

	self.changedWaypoints = {}

	self.mode = self.TYPE_NORMAL
end

function BrushConnect:onButtonPrimary(isDown, isDrag, isUp)
	if self.selectedNodeId == nil and isDown then 
		self.selectedNodeId = self:getHoveredNodeId()
		self.graphWrapper:setSelected(self.selectedNodeId)
		return
	end
	local nodeId = self:getHoveredNodeId()
	if nodeId ~= nil then 
		if isDrag then 
			if nodeId ~= self.selectedNodeId and not self.changedWaypoints[nodeId] then 
				self:connectWaypoints(self.selectedNodeId, nodeId)
				self.selectedNodeId = nodeId
				self.changedWaypoints[nodeId] = true
			end
		end
	end
	if isUp then 
		self.selectedNodeId = nil
		self.graphWrapper:resetSelected()
		self.changedWaypoints = {}
	end
end

function BrushConnect:onButtonSecondary()
	local d = self.sizeModifier + 1
	if d > self.sizeModifierMax then 
		self:changeSizeModifier(1)
	elseif d <= 0 then 
		self:changeSizeModifier(self.sizeModifierMax)
	else
		self:changeSizeModifier(d)
	end
	self:setInputTextDirty()
end

function BrushConnect:connectWaypoints(nodeId, targetNodeId, sendEvent)
	self.graphWrapper:setConnectionAndSubPriority(nodeId, targetNodeId, self:getCurrentConnectionType(), self:getIsSubPrio(), sendEvent)
end

function BrushConnect:getCurrentConnectionType()
	local dir = 1
	if self.mode == self.TYPE_CROSSING or self.mode == self.TYPE_CROSSING_LOW_PRIO then 
		dir = 3
	elseif self.mode == self.TYPE_REVERSE_NORMAL then 
		dir = 4
	elseif self.mode == self.TYPE_DISCONNECT then 
		dir = 0
	end
	return dir
end

function BrushConnect:getIsSubPrio()
	return self.mode == self.TYPE_LOW_PRIO  or self.mode == self.TYPE_CROSSING_LOW_PRIO
end

function BrushConnect:getIsReverse()
	return self.mode == self.TYPE_REVERSE_NORMAL
end

function BrushConnect:getIsCrossing()
	return self.mode == self.TYPE_CROSSING or self.mode == self.TYPE_CROSSING_LOW_PRIO
end

function BrushConnect:onButtonTertiary()
	self.mode = self.mode + 1
	if self.mode > self.TYPE_MAX then 
		self.mode = self.TYPE_MIN
	end
	self:setInputTextDirty()
end

--- Not working, as the brush classes need to be the same.
function BrushConnect:copyState(from)
	if from.mode ~= nil then 
		self.mode = from.mode
		self.sizeModifier = from.sizeModifier or 1
		self:setInputTextDirty()
	end
end

function BrushConnect:activate()
	self.selectedNodeId = nil
	self.changedWaypoints = {}
	self.graphWrapper:resetSelected()
end

function BrushConnect:deactivate()
	self.selectedNodeId = nil
	self.changedWaypoints = {}
	self.graphWrapper:resetSelected()
end

function BrushConnect:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end

function BrushConnect:getButtonSecondaryText()
	return self:getTranslation(self.secondaryButtonText, self.sizeModifier)
end

function BrushConnect:getButtonTertiaryText()
	return self:getTranslation(self.tertiaryButtonText, self:getTranslation(self.typeTexts[self.mode]))
end
