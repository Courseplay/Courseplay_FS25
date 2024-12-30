
--- Changes a new waypoint at the mouse position.
---@class CpBrushChangeHeadlandWP : CpBrush
CpBrushChangeHeadlandWP = CpObject(CpBrush)
CpBrushChangeHeadlandWP.MAX_HEADLANDS = 40
CpBrushChangeHeadlandWP.NO_HEADLANDS = 0
CpBrushChangeHeadlandWP.TRANSLATIONS = {
		NO_HEADLAND = "noHeadland"}
function CpBrushChangeHeadlandWP:init(cursor, editor)
	CpBrush.init(self, cursor, editor)
	self.supportsPrimaryButton = true
	self.supportsPrimaryDragging = true
	self.supportsSecondaryButton = true
	self.supportsPrimaryAxis = true
	self.mode = self.NO_HEADLANDS
end

function CpBrushChangeHeadlandWP:onButtonPrimary()
	local ix = self:getHoveredWaypointIx()
	if ix then 
		self.courseWrapper:changeHeadland(ix, self.mode)
		self.editor:updateChangeSingle(ix)
	end
end

function CpBrushChangeHeadlandWP:onButtonSecondary()
	local ix = self:getHoveredWaypointIx()
	if ix then 
		self.courseWrapper:changeHeadland(ix, self.mode)
		self.editor:updateChangeSingle(ix)
	end
end

function CpBrushChangeHeadlandWP:onAxisPrimary(inputValue)
	self.mode = self.mode + inputValue
	if self.mode > self.MAX_HEADLANDS then 
		self.mode = self.NO_HEADLANDS
	elseif self.mode < self.NO_HEADLANDS then
		self.mode = self.MAX_HEADLANDS
	end
	self.courseWrapper:setHeadlandMode(self.mode)
	self.editor:updateChanges(1)
	self:setInputTextDirty()
end

function CpBrushChangeHeadlandWP:activate()
	self.courseWrapper:setHeadlandMode(self.mode)
	self.editor:updateChanges(1)
	self:setInputTextDirty()
end

function CpBrushChangeHeadlandWP:deactivate()
	self.courseWrapper:setHeadlandMode(nil)
	self.editor:updateChanges(1)
end

function CpBrushChangeHeadlandWP:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end

function CpBrushChangeHeadlandWP:getButtonSecondaryText()
	return self:getTranslation(self.secondaryButtonText)
end

function CpBrushChangeHeadlandWP:getAxisPrimaryText()
	local text = self.mode == self.NO_HEADLANDS and self.TRANSLATIONS.NO_HEADLAND or self.mode
	return self:getTranslation(self.primaryAxisText, text)
end
