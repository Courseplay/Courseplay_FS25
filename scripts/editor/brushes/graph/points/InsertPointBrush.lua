
--- Inserts a new waypoint at the mouse position.
---@class InsertPointBrush : GraphBrush
InsertPointBrush = CpObject(GraphBrush)
function InsertPointBrush:init(...)
	GraphBrush.init(self, ...)
	self.supportsPrimaryButton = true
	self.supportsSecondaryButton = true
end

function InsertPointBrush:onButtonPrimary()
	self:handleButtonEvent(function (selectedId, point)
		local success, err = self.graphWrapper:insertPointBehindIndex(selectedId, point:clone())
		if not success then 
			self:setError(err)
			return
		end
		self:debug("Successfully inserted Point: %s behind index: %s", 
			point:getRelativeID(), selectedId)
	end)
end

function InsertPointBrush:onButtonSecondary()
	-- self:handleButtonEvent(function (selectedId, point)
	-- 	local success, err =  self.graphWrapper:insertPointAheadOfIndex(selectedId, point:clone())
	-- 	if not success then 
	-- 		self:setError(err)
	-- 		return
	-- 	end
	-- 	self:debug("Successfully inserted Point: %s ahead of index: %s", 
	-- 		point:getRelativeID(), selectedId)
	-- end)
	if self.graphWrapper:hasSelectedNode() then
        local ix = self.graphWrapper:getFirstSelectedNodeID() 
        if self.graphWrapper:isOnlyNodeLeftInSegment(ix) then 
            self.graphWrapper:removeSegmentByPointIndex(ix)
        end
    end
    self.graphWrapper:resetTemporaryPoints()
    self.graphWrapper:resetSelected()
end

function InsertPointBrush:handleButtonEvent(insertLambda)
	local ix = self:getHoveredNodeId()
	local x, y, z = self.cursor:getPosition()
	if self.graphWrapper:hasSelectedNode() then 
		local point = self.graphWrapper:getFirstTemporaryPoint()
		local selectedId = self.graphWrapper:getFirstSelectedNodeID()
		local segment, err = self.graphWrapper:getSegmentByIndex(selectedId)
        if not segment then 
            self:setError(err)
            return
        end
		if ix then 
			self:setError("err_min_distance_to_small")
			return
		end
		if selectedId and point then 
			insertLambda(selectedId, point)
		end
		self.graphWrapper:resetTemporaryPoints()
		self.graphWrapper:resetSelected()
		self.graphWrapper:setSelected(segment:getLastNodeID())
	else
		if ix then 
			self.graphWrapper:setSelected(ix)
		else 
			ix = self.graphWrapper:createSegmentWithPoint(x, y, z)
			if ix then
				self.graphWrapper:setSelected(ix)
			end
		end
	end
end

function InsertPointBrush:update(dt)
	GraphBrush.update(self, dt)
	local x, y, z = self.cursor:getPosition()
	if x == nil or z == nil then 
		return
	end
    local tx, ty, tz = self.graphWrapper:getPositionByIndex(
        self.graphWrapper:getFirstSelectedNodeID())
    if tx == nil or tz == nil then 
        return
    end
	self.graphWrapper:clearTemporaryPoints()
	local dist = MathUtil.vector2Length(x-tx, z-tz)
	if dist <= 1 then 
		return
	end
	self.graphWrapper:addTemporaryPoint(x, y, z)
end

function InsertPointBrush:activate()
	self.graphWrapper:resetSelected()
	self.graphWrapper:resetTemporaryPoints()
end

function InsertPointBrush:deactivate()
	self:onButtonSecondary()
end


function InsertPointBrush:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end

function InsertPointBrush:getButtonSecondaryText()
	return self:getTranslation(self.secondaryButtonText)
end
