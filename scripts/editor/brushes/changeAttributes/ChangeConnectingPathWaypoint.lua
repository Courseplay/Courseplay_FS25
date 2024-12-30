
--- Changes a new waypoint at the mouse position.
---@class CpBrushChangeConnectingPathWP : CpBrush
CpBrushChangeConnectingPathWP = CpObject(CpBrush)
function CpBrushChangeConnectingPathWP:init(cursor, editor)
	CpBrush.init(self, cursor, editor)
	self.supportsPrimaryButton = true
	self.supportsPrimaryDragging = true
	self.supportsSecondaryButton = true
	self.supportsSecondaryDragging = true
end

function CpBrushChangeConnectingPathWP:onButtonPrimary()
	local ix = self:getHoveredWaypointIx()
	if ix then 
		self.courseWrapper:setConnectingPath(ix, true)
		self.editor:updateChangeSingle(ix)
	end
end

function CpBrushChangeConnectingPathWP:onButtonSecondary()
	local ix = self:getHoveredWaypointIx()
	if ix then 
		self.courseWrapper:setConnectingPath(ix, false)
		self.editor:updateChangeSingle(ix)
	end
end

function CpBrushChangeConnectingPathWP:activate()
	self.courseWrapper:setConnectingPathActive(true)
	self.editor:updateChanges(1)
end

function CpBrushChangeConnectingPathWP:deactivate()
	self.courseWrapper:setConnectingPathActive(false)
	self.editor:updateChanges(1)
end

function CpBrushChangeConnectingPathWP:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end

function CpBrushChangeConnectingPathWP:getButtonSecondaryText()
	return self:getTranslation(self.secondaryButtonText)
end
