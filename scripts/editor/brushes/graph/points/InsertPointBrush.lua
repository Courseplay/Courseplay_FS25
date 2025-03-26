
--- Inserts a new waypoint at the mouse position.
---@class InsertPointBrush : GraphBrush
InsertPointBrush = CpObject(GraphBrush)
function InsertPointBrush:init(...)
	GraphBrush.init(self, ...)
	self.supportsPrimaryButton = true
	self.supportsPrimaryDragging = true
	self.supportsSecondaryButton = true
	self.supportsSecondaryDragging = true
end

function InsertPointBrush:onButtonPrimary(isDown, isDrag, isUp)
	self:handleButtonEvent(isDown, isDrag, isUp, function (selectedId, point)
		local success, err = self.graphWrapper:insertPointAheadOfIndex(selectedId, point:clone())
		if not success then 
			self:setError(err)
			return
		end
		self:debug("Successfully inserted Point: %s ahead of index: %s", 
			point:getRelativeID(), selectedId)
	end)
end

function InsertPointBrush:onButtonSecondary(isDown, isDrag, isUp)
	self:handleButtonEvent(isDown, isDrag, isUp, function (selectedId, point)
		local success, err =  self.graphWrapper:insertPointBehindIndex(selectedId, point:clone())
		if not success then 
			self:setError(err)
			return
		end
		self:debug("Successfully inserted Point: %s behind index: %s", 
			point:getRelativeID(), selectedId)
	end)
end

function InsertPointBrush:handleButtonEvent(isDown, isDrag, isUp, insertLambda)
	if isDown then 
		local ix = self:getHoveredNodeId()
		local x, y, z = self.cursor:getPosition()
		if ix then 
			self.graphWrapper:setSelected(ix)
			self.graphWrapper:addTemporaryPoint(x, y, z)
		else 
			ix = self.graphWrapper:createSegmentWithPoint(x, y, z)
			if ix then
				--- TODO Update editor
				self.graphWrapper:setSelected(ix)
				self.graphWrapper:addTemporaryPoint(x, y, z)
			end
		end
	end
	if isDrag then 
		local point = self.graphWrapper:getFirstTemporaryPoint()
		if point then 
			local x, y, z = self.cursor:getPosition()
			point:moveTo(x, y, z)
		end
	end
	if isUp then 
		local point = self.graphWrapper:getFirstTemporaryPoint()
		local selectedId = self.graphWrapper:getFirstSelectedNodeID()
		if selectedId ~= nil and point then 
			insertLambda(selectedId, point)
			self.graphWrapper:resetSelected()
			self.graphWrapper:resetTemporaryPoints()
		end
	end
end

function InsertPointBrush:activate()
	self.graphWrapper:resetSelected()
	self.graphWrapper:resetTemporaryPoints()
end

function InsertPointBrush:deactivate()
	self.graphWrapper:resetSelected()
	self.graphWrapper:resetTemporaryPoints()
end


function InsertPointBrush:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end

function InsertPointBrush:getButtonSecondaryText()
	return self:getTranslation(self.secondaryButtonText)
end
