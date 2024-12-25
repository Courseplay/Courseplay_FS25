
--- Inserts a new waypoint at the mouse position.
---@class CpBrushInsertWP : CpBrush
CpBrushInsertWP = CpObject(CpBrush)
function CpBrushInsertWP:init(cursor, editor)
	CpBrush.init(self, cursor, editor)
	self.supportsPrimaryButton = true
	self.supportsSecondaryButton = true
end

function CpBrushInsertWP:onButtonPrimary()
	local ix = self:getHoveredWaypointIx()
	if ix then 
		local wp, inserted = self.courseWrapper:insertWaypointBehind(ix)
		if inserted then 
			self.courseWrapper:resetHovered()
			self.editor:updateChanges(1)
			self:resetError()
		else
			self:setError()
		end
	end
end

function CpBrushInsertWP:onButtonSecondary()
	local ix = self:getHoveredWaypointIx()
	if ix then 
		local wp, inserted = self.courseWrapper:insertWaypointAhead(ix)
		if inserted then 
			self.editor:updateChanges(1)
			self:resetError()
		else
			self:setError()
		end
	end
end

function CpBrushInsertWP:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end

function CpBrushInsertWP:getButtonSecondaryText()
	return self:getTranslation(self.secondaryButtonText)
end
