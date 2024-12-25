
--- Changes a new waypoint at the mouse position.
---@class CpBrushChangeRowNumberWP : CpBrush
CpBrushChangeRowNumberWP = CpObject(CpBrush)
CpBrushChangeRowNumberWP.NO_ROW = 0
CpBrushChangeRowNumberWP.TRANSLATIONS = {
	NO_ROW = "noRow"}
function CpBrushChangeRowNumberWP:init(cursor, editor)
	CpBrush.init(self, cursor, editor)
	self.supportsPrimaryButton = true
	self.supportsPrimaryDragging = true
	self.supportsSecondaryButton = true
	self.supportsPrimaryAxis = true
	self.mode = 0
end

function CpBrushChangeRowNumberWP:onButtonPrimary()
	local ix = self:getHoveredWaypointIx()
	if ix then 
		self.courseWrapper:changeRowNumber(ix, self.mode)
		self.editor:updateChangeSingle(ix)
	end
end

function CpBrushChangeRowNumberWP:onButtonSecondary()
	local ix = self:getHoveredWaypointIx()
	if ix then 
		self.courseWrapper:changeRowNumber(ix, self.mode)
		self.editor:updateChangeSingle(ix)
	end
end

function CpBrushChangeRowNumberWP:onAxisPrimary(inputValue)
	local max = self.courseWrapper:getMaxRowNumber() + 1
	self.mode = self.mode + inputValue
	if self.mode > max then 
		self.mode = 1
	elseif self.mode < 0 then
		self.mode = max
	end
	self.courseWrapper:setRowNumberMode(self.mode)
	self.editor:updateChanges(1)
	self:setInputTextDirty()
end

function CpBrushChangeRowNumberWP:activate()
	self.courseWrapper:setRowNumberMode(self.mode)
	self.editor:updateChanges(1)
	self:setInputTextDirty()
end

function CpBrushChangeRowNumberWP:deactivate()
	self.courseWrapper:setRowNumberMode(nil)
	self.editor:updateChanges(1)
end

function CpBrushChangeRowNumberWP:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end

function CpBrushChangeRowNumberWP:getButtonSecondaryText()
	return self:getTranslation(self.secondaryButtonText)
end

function CpBrushChangeRowNumberWP:getAxisPrimaryText()
	local text = self.mode == self.NO_ROW and self.TRANSLATIONS.NO_ROW or self.mode
	return self:getTranslation(self.primaryAxisText, text)
end
