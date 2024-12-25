
--- Moves a new waypoint at the mouse position.
---@class CpBrushAdvancedMoveWP : CpBrush
CpBrushAdvancedMoveWP = CpObject(CpBrush)
CpBrushAdvancedMoveWP.DELAY = 100
function CpBrushAdvancedMoveWP:init(cursor, editor)
	CpBrush.init(self, cursor, editor)
	self.supportsPrimaryButton = true
	self.supportsPrimaryDragging = true
	self.supportsSecondaryButton = true
	self.delay = g_time

	self.selectedFirstIx = nil
	self.selectedSecondIx = nil
end

function CpBrushAdvancedMoveWP:onButtonPrimary(isDown, isDrag, isUp)
	if isDown and not isDrag then
		local ix = self:getHoveredWaypointIx()
		if self.selectedFirstIx == nil then 
			self.selectedFirstIx = ix
			self.courseWrapper:setSelected(self.selectedFirstIx)
		elseif self.selectedSecondIx == nil and self.selectedFirstIx ~= ix then 
			self.selectedSecondIx = ix
			self.courseWrapper:setSelected(self.selectedSecondIx)
			if self.selectedSecondIx and self.selectedSecondIx < self.selectedFirstIx then 
				self.selectedFirstIx, self.selectedSecondIx = self.selectedSecondIx, self.selectedFirstIx
			end
		end
		local x, _, z = self.cursor:getPosition()
		self.lastPosition = {x, z}
	end
	if isDrag then 
		if self.selectedFirstIx and self.selectedSecondIx then 
			local nx, _, nz = self.cursor:getPosition()
			local x, z = unpack(self.lastPosition)
			self.lastPosition = {nx, nz}
			self.courseWrapper:moveMultipleWaypoints(self.selectedFirstIx, self.selectedSecondIx, nx - x, nz - z)
			self.editor:updateChangesBetween(self.selectedFirstIx, self.selectedSecondIx)
		end
	end
	if isUp then
		
	end
end

function CpBrushAdvancedMoveWP:onButtonSecondary()
	self.courseWrapper:resetSelected()
	self.selectedFirstIx = nil
	self.selectedSecondIx = nil
	self.editor:updateChanges(1)
end

function CpBrushAdvancedMoveWP:deactivate()
	self.courseWrapper:resetSelected()
	self.editor:updateChanges(1)
end

function CpBrushAdvancedMoveWP:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end

function CpBrushAdvancedMoveWP:getButtonSecondaryText()
	return self:getTranslation(self.secondaryButtonText)
end
