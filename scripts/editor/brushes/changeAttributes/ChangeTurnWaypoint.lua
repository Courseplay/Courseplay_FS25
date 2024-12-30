
--- Changes a new waypoint at the mouse position.
---@class CpBrushChangeTurnWP : CpBrush
CpBrushChangeTurnWP = CpObject(CpBrush)
CpBrushChangeTurnWP.TYPES = {
	NORMAL = 1,
	TURN_START = 2,
	TURN_END = 3
}

CpBrushChangeTurnWP.TYPES_TRANSLATIONS = {
	[CpBrushChangeTurnWP.TYPES.NORMAL] = "type_normal",
	[CpBrushChangeTurnWP.TYPES.TURN_START] = "type_turnStart",
	[CpBrushChangeTurnWP.TYPES.TURN_END] = "type_turnEnd",
}
function CpBrushChangeTurnWP:init(cursor, editor)
	CpBrush.init(self, cursor, editor)
	self.supportsPrimaryButton = true
end

function CpBrushChangeTurnWP:onButtonPrimary()
	local ix = self:getHoveredWaypointIx()
	if ix then 
		if self.courseWrapper:changeWaypointTurnType(ix) then
			self.editor:updateChangesBetween(ix - 1, ix + 1)
			self:resetError()
		else
			self:setError()
		end
	end
end

function CpBrushChangeTurnWP:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end
