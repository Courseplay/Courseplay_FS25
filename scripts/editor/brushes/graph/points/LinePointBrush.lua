
--- Inserts a new waypoint at the mouse position.
---@class LinePointBrush : GraphBrush
LinePointBrush = CpObject(GraphBrush)
LinePointBrush.MIN_DIST = 2
LinePointBrush.MAX_DIST = 20
LinePointBrush.START_DIST = 6
LinePointBrush.MIN_OFFSET = -1
LinePointBrush.MAX_OFFSET = 1
LinePointBrush.MIN_CENTER = 0
LinePointBrush.MAX_CENTER = 1
LinePointBrush.START_CENTER = 0.5
LinePointBrush.START_OFFSET = 0
function LinePointBrush:init(...)
	GraphBrush.init(self, ...)
	self.supportsPrimaryButton = true
	self.supportsSecondaryButton = true
    self.supportsPrimaryAxis = true
    self.supportsSecondaryAxis = true
    
    self.offset = 0
    self.center = 0.5
end

function LinePointBrush:onButtonPrimary()
    local ix = self:getHoveredNodeId()
    local x, y, z = self.cursor:getPosition()
    if self.graphWrapper:hasSelectedNode() then 
        local tempSegment = self.graphWrapper:getTemporarySegment()
        local selectedNodeId = self.graphWrapper:getFirstSelectedNodeID()
        if tempSegment:getLength() < EditorGraphWrapper.MIN_DISTANCE then 
            self:setError("err_min_distance_to_small")
            return
        end
        local segment, err = self.graphWrapper:getSegmentByIndex(selectedNodeId)
        if not segment then 
            self:setError(err)
            return
        end
        if ix then 
            local success, err = self.graphWrapper:isFirstSegmentPoint(ix)
            if not success then 
                self:setError(err)
                return
            end
            segment:extendByChildren(tempSegment, false)
            local success, err = self.graphWrapper:mergeSegments(
                segment:getLastNodeID(), ix)
            if not success then 
                self:setError(err)
                return
            end
        else 
            segment:extendByChildren(tempSegment, false)
        end
        self.graphWrapper:clearTemporaryPoints()
        self.graphWrapper:resetSelected()
        self.graphWrapper:setSelected(segment:getLastNodeID())

    else
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
	end
end

function LinePointBrush:onButtonSecondary()
    self.graphWrapper:resetTemporaryPoints()
    self.graphWrapper:resetSelected()
end

function LinePointBrush:update(dt)
    GraphBrush.update(self, dt)
    if self.graphWrapper:hasSelectedNode() then 
        self:movePoints()
    end
end

function LinePointBrush:movePoints()
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
    local spacing = 3
	local nx, nz = MathUtil.vector2Normalize(x-tx, z-tz)
	if nx == nil or nz == nil then 
		nx = 0
		nz = 1
	end
	-- local n = math.max(math.ceil(dist/spacing), 2)
	-- spacing = dist / n
    -- if self.graphWrapper:isLastSegmentPoint(
    --     self.graphWrapper:getFirstSelectedNodeID()) then 
    --     --- Forwards 
    --     for i = 1, n + 1 do 
    --         local dx = tx + nx * i * spacing 
    --         local dz = tz + nz * i * spacing
    --         local dy = getTerrainHeightAtWorldPos(
    --             g_currentMission.terrainRootNode, dx, y, dz)
    --         if dy > y - 2 and dy < y + 2 then 
    --             y = dy
    --         end
    --         self.graphWrapper:addTemporaryPoint(dx, y, dz)
    --     end
    -- else 
    --     --- Backwards
    --     for i = 1, n + 1 do 
    --         local dx = tx + nx * i * spacing 
    --         local dz = tz + nz * i * spacing
    --         local dy = getTerrainHeightAtWorldPos(
    --             g_currentMission.terrainRootNode, dx, y, dz)
    --         if dy > y - 2 and dy < y + 2 then 
    --             y = dy
    --         end
    --         self.graphWrapper:addTemporaryPoint(dx, y, dz)
    --     end
    -- end
    local distCenter = dist*self.center
	local ax, az = tx + nx * distCenter, tz + nz * distCenter
	--- Rotation
	local ncx = nx  * math.cos(math.pi/2) - nz  * math.sin(math.pi/2)
	local ncz = nx  * math.sin(math.pi/2) + nz  * math.cos(math.pi/2)
	--- Translation
	local cx, cz = ax + ncx * self.offset * dist, az + ncz * self.offset * dist
	local halfDist = MathUtil.vector2Length(cx - tx, cz - tz)
	local dt = 2/(1.5*halfDist)
	local n = math.ceil(halfDist/spacing)
	spacing = halfDist/n
	local points = {
	    { tx, tz },
		{ cx, cz },
		{ x, z}}
	local dx, dz
	for t=dt , 1, dt do 
		dx, dz = CpMathUtil.de_casteljau(t, points)
        local dy = getTerrainHeightAtWorldPos(
            g_currentMission.terrainRootNode, dx, y, dz)
        if dy > y - 2 and dy < y + 2 then 
            y = dy
        end
		self.graphWrapper:addTemporaryPoint(dx, y, dz)
	end
end

function LinePointBrush:onAxisPrimary(inputValue)
	self.offset = math.clamp(self.offset+inputValue/50, self.MIN_OFFSET, self.MAX_OFFSET)
	self:setInputTextDirty()
end

function LinePointBrush:onAxisSecondary(inputValue)
	self.center = math.clamp(self.center+inputValue/50, self.MIN_CENTER, self.MAX_CENTER)
	self:setInputTextDirty()
end

function LinePointBrush:activate()
	self.graphWrapper:resetSelected()
	self.graphWrapper:resetTemporaryPoints()
end

function LinePointBrush:deactivate()
	self.graphWrapper:resetSelected()
	self.graphWrapper:resetTemporaryPoints()
end
function LinePointBrush:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end

function LinePointBrush:getButtonSecondaryText()
	return self:getTranslation(self.secondaryButtonText)
end

function LinePointBrush:getAxisPrimaryText()
	return self:getTranslation(self.primaryAxisText, self.offset)
end

function LinePointBrush:getAxisSecondaryText()
	return self:getTranslation(self.secondaryAxisText, self.center)
end
