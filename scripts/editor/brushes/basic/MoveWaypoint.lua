
--- Moves a new waypoint at the mouse position.
---@class CpBrushMoveWP : CpBrush
CpBrushMoveWP = CpObject(CpBrush)
CpBrushMoveWP.DELAY = 100
function CpBrushMoveWP:init(cursor, editor)
	CpBrush.init(self, cursor, editor)
	self.supportsPrimaryButton = true
	self.supportsPrimaryDragging = true
	self.delay = g_time
end

function CpBrushMoveWP:onButtonPrimary(isDown, isDrag, isUp)
	if isDown and not isDrag then
		self.selectedIx = self:getHoveredWaypointIx()
	end
	if isDrag then 

		if self.selectedIx then 
			local x, _, z = self.cursor:getPosition()
			self.courseWrapper:setWaypointPosition(self.selectedIx, x, z )
			self.editor:updateChangesBetween(self.selectedIx, self.selectedIx)
		end
	end
	if isUp then
		self.selectedIx = nil
	end
end

function CpBrushMoveWP:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end
