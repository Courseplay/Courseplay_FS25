
--- Moves a waypoint relative to the mouse position.
---@class BrushMoveAdvanced : GraphBrush
BrushMoveAdvanced = CpObject(GraphBrush)

function BrushMoveAdvanced:init(...)
	GraphBrush.init(self, ...)
	self.supportsPrimaryButton = true
	self.supportsPrimaryDragging = true
	self.supportsSecondaryButton = true
	self.supportsSecondaryDragging = true
	self.supportsTertiaryButton = true
	self.selectedNodes = {}
	self.lastPosition = {}
end

function BrushMoveAdvanced:onButtonPrimary(isDown, isDrag, isUp)
	local x, y, z = self.cursor:getPosition() 
	if isDown then 
		self.lastPosition = {x, y, z}
	end
	if isDrag then
		if next(self.lastPosition) 	~= nil then
			local dx, dy, dz = unpack(self.lastPosition)
			local nx, ny, nz = x - dx, y - dy, z - dz 
			for nodeId, _ in pairs(self.selectedNodes) do 
				self.graphWrapper:translateTo(nodeId, nx, ny, nz)
			end
		end
		self.lastPosition = {x, y, z}
	end 
end

function BrushMoveAdvanced:onButtonSecondary(isDown, isDrag, isUp)
	if isDown or isDrag then 
		local selectedNodeId = self:getHoveredNodeId()
		if selectedNodeId then
			self.graphWrapper:setSelected(selectedNodeId)
			self.selectedNodes[selectedNodeId] = true
		end
	end
end

function BrushMoveAdvanced:onButtonTertiary()
	self.selectedNodes = {}
	self.lastPosition = {}
	self.graphWrapper:resetSelected()
end

function BrushMoveAdvanced:activate()
	self.selectedNodes = {}
	self.lastPosition = {}
	self.graphWrapper:resetSelected()
end

function BrushMoveAdvanced:deactivate()
	self.selectedNodes = {}
	self.lastPosition = {}
	self.graphWrapper:resetSelected()
end

function BrushMoveAdvanced:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end

function BrushMoveAdvanced:getButtonSecondaryText()
	return self:getTranslation(self.secondaryButtonText)
end

function BrushMoveAdvanced:getButtonTertiaryText()
	return self:getTranslation(self.tertiaryButtonText)
end
