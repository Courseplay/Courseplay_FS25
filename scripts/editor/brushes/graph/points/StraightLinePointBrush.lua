
--- Inserts a new waypoint at the mouse position.
---@class StraightLinePointBrush : GraphBrush
StraightLinePointBrush = CpObject(GraphBrush)
StraightLinePointBrush.MIN_DIST = 2
StraightLinePointBrush.MAX_DIST = 20
StraightLinePointBrush.START_DIST = 6
StraightLinePointBrush.DELAY = 1 --- The mouse event oscillates.., so we have to wait one update tick before release is allowed.
function StraightLinePointBrush:init(...)
	GraphBrush.init(self, ...)
	self.supportsPrimaryButton = true
	self.supportsPrimaryDragging = true
	self.supportsSecondaryButton = true
	self.supportsSecondaryDragging = true
    self.supportsPrimaryAxis = true
    self.spacing = self.START_DIST

    self.delay = g_updateLoopIndex
end

function StraightLinePointBrush:onButtonPrimary(isDown, isDrag, isUp)
	self:handleButtonEvent(isDown, isDrag, isUp)
end

function StraightLinePointBrush:onButtonSecondary(isDown, isDrag, isUp)

end

function StraightLinePointBrush:movePoints()
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
    local tx, ty, tz = self.graphWrapper:getPositionByIndex(
        self.graphWrapper:getFirstSelectedNodeID())
	local dist = MathUtil.vector2Length(x-tx, z-tz)
	if dist <= 1 then 
		return
	end
    local spacing = self.spacing
	local nx, nz = MathUtil.vector2Normalize(x-tx, z-tz)
	if nx == nil or nz == nil then 
		nx = 0
		nz = 1
	end
	local n = math.max(math.ceil(dist/spacing), 2)
	spacing = dist / n
    if self.graphWrapper:isLastSegmentPoint(
        self.graphWrapper:getFirstSelectedNodeID()) then 
        --- Forwards 
        for i = 1, n + 1 do 
            local dx = tx + nx * i * spacing 
            local dz = tz + nz * i * spacing
            local dy = getTerrainHeightAtWorldPos(
                g_currentMission.terrainRootNode, dx, y, dz)
            if dy > y - 2 and dy < y + 2 then 
                y = dy
            end
            self.graphWrapper:addTemporaryPoint(dx, y, dz)
        end
    else 
        --- Backwards
        for i = 1, n + 1 do 
            local dx = tx + nx * i * spacing 
            local dz = tz + nz * i * spacing
            local dy = getTerrainHeightAtWorldPos(
                g_currentMission.terrainRootNode, dx, y, dz)
            if dy > y - 2 and dy < y + 2 then 
                y = dy
            end
            self.graphWrapper:addTemporaryPoint(dx, y, dz)
        end
    end
end

function StraightLinePointBrush:onAxisPrimary(inputValue)
    self.spacing = math.clamp(self.spacing + inputValue, 
        self.MIN_DIST, self.MAX_DIST)
end

function StraightLinePointBrush:handleButtonEvent(isDown, isDrag, isUp, insertLambda)
    if isDown and not self.graphWrapper:hasSelectedNode() then 
		local ix = self:getHoveredNodeId()
		local x, y, z = self.cursor:getPosition()
		if ix then 
            local isNotFirsOrLast, err = self.graphWrapper:isNotFirstOrLastSegmentPoint(ix)
            if isNotFirsOrLast then 
                self:setError(err)
                return
            end
            if self.graphWrapper:isFirstSegmentPoint(ix) then 
                self.graphWrapper:setSelected(ix)
			    self.graphWrapper:addTemporaryPoint(x, y, z)
            elseif self.graphWrapper:isLastSegmentPoint(ix) then 
                self.graphWrapper:setSelected(ix)
			    self.graphWrapper:addTemporaryPoint(x, y, z)
            end
		else 
			ix = self.graphWrapper:createSegmentWithPoint(x, y, z)
			if ix then
				--- TODO Update editor
				self.graphWrapper:setSelected(ix)
				self.graphWrapper:addTemporaryPoint(x, y, z)
			end
		end
        self.delay = g_updateLoopIndex + self.DELAY
	end
    if isDrag and self.graphWrapper:hasSelectedNode() then 
        self:movePoints()
    end
    if isUp and self.graphWrapper:hasSelectedNode() then 
        local points = self.graphWrapper:getTemporaryPoints()
		local selectedId = self.graphWrapper:getFirstSelectedNodeID()
        local ix, success, err = selectedId, false, nil
        if self.graphWrapper:isLastSegmentPoint(selectedId) then 
            for _, p in ipairs(points) do 
                success, err, ix = self.graphWrapper:insertPointBehindIndex(ix, p:clone())
                if not success then 
                    self:setError(err)
                    break
                end
                self:debug("Successfully inserted Point: %s behind index: %s", 
                    p:getRelativeID(), ix)
            end
        else 
            for _, p in ipairs(points) do 
                success, err, ix = self.graphWrapper:insertPointAheadOfIndex(ix, p:clone())
                if not success then 
                    self:setError(err)
                    break
                end
                self:debug("Successfully inserted Point: %s ahead of index: %s", 
                    p:getRelativeID(), ix)
                
            end
        end
        self.graphWrapper:resetTemporaryPoints()
        self.graphWrapper:resetSelected()
    end
end

function StraightLinePointBrush:update(dt)
    GraphBrush.update(self, dt)

end

function StraightLinePointBrush:activate()
	self.graphWrapper:resetSelected()
	self.graphWrapper:resetTemporaryPoints()
end

function StraightLinePointBrush:deactivate()
	self.graphWrapper:resetSelected()
	self.graphWrapper:resetTemporaryPoints()
end


function StraightLinePointBrush:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end

function StraightLinePointBrush:getButtonSecondaryText()
	return self:getTranslation(self.secondaryButtonText)
end

function StraightLinePointBrush:getAxisPrimaryText()
	return self:getTranslation(self.primaryAxisText, self.spacing)
end