
--- Inserts a new waypoint at the mouse position.
---@class LinePointBrush : GraphBrush
LinePointBrush = CpObject(GraphBrush)
LinePointBrush.MIN_OFFSET = -1
LinePointBrush.MAX_OFFSET = 1
LinePointBrush.MIN_CENTER = 1
LinePointBrush.MAX_CENTER = 5
function LinePointBrush:init(...)
	GraphBrush.init(self, ...)
	self.supportsPrimaryButton = true
	self.supportsSecondaryButton = true
    self.supportsTertiaryButton = true
    self.supportsPrimaryAxis = true
    self.primaryAxisIsContinuous = true
    self.supportsSecondaryAxis = true
    self.secondaryAxisIsContinuous = true
    self.offset = 0
    self.center = -3.5
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
        if self.graphWrapper:isMirrorSegmentActive() then 
            local mirrorSegment = self.graphWrapper:getMirrorSegment()
            self.graphWrapper:addSegment(mirrorSegment:clone(true))
        end
        self.graphWrapper:clearTemporaryPoints()
        self.graphWrapper:resetSelected()
        self.graphWrapper:setSelected(segment:getLastNodeID())
        self.offset = 0
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
				self.graphWrapper:setSelected(ix)
				self.graphWrapper:addTemporaryPoint(x, y, z)
			end
		end
	end
end

function LinePointBrush:onButtonSecondary()
    if self.graphWrapper:hasSelectedNode() then
        local ix = self.graphWrapper:getFirstSelectedNodeID() 
        if self.graphWrapper:isOnlyNodeLeftInSegment(ix) then 
            self.graphWrapper:removeSegmentByPointIndex(ix)
        end
    end
    self.offset = 0
    self.graphWrapper:resetTemporaryPoints()
    self.graphWrapper:resetSelected()
end

function LinePointBrush:onButtonTertiary()
    self.graphWrapper:toggleMirrorSegmentActive()
    self:setInputTextDirty()
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
    local distCenter = dist * 0.5
	local ax, az = tx + nx * distCenter, tz + nz * distCenter
	--- Rotation
	local ncx = nx  * math.cos(math.pi/2) - nz  * math.sin(math.pi/2)
	local ncz = nx  * math.sin(math.pi/2) + nz  * math.cos(math.pi/2)
	--- Translation
	local cx, cz = ax + ncx * self.offset * dist, az + ncz * self.offset * dist
	local halfDist = MathUtil.vector2Length(cx - tx, cz - tz)
	local dt = 3/halfDist
	local n = math.ceil(halfDist/spacing)
	spacing = halfDist/n
	local points = {
	    { tx, tz },
		{ cx, cz },
		{ x, z}}
	local dx, dz
    self.graphWrapper:addMirrorTemporaryPoint(
        tx + ncx * self.center, ty, tz + ncz * self.center)
    local lastY = ty
	for t=dt , 1, dt do 
		dx, dz = CpMathUtil.de_casteljau(t, points)
        local _, _, dy = RaycastUtil.raycastClosest(dx, lastY + 3, dz, 0, -1, 0, 5, 
            CollisionFlag.STATIC_OBJECT + CollisionFlag.ROAD + CollisionFlag.AI_DRIVABLE + CollisionFlag.TERRAIN)
		lastY = dy
        self.graphWrapper:addTemporaryPoint(dx, y, dz)
        local mx, mz = dx + ncx * self.center, dz + ncz * self.center
        self.graphWrapper:addMirrorTemporaryPoint(mx, y, mz)
	end
end

function LinePointBrush:onAxisPrimary(inputValue)
	self.offset = math.clamp(self.offset+inputValue/125, self.MIN_OFFSET, self.MAX_OFFSET)
	self:setInputTextDirty()
end

function LinePointBrush:onAxisSecondary(inputValue)
    local newCenter = self.center - inputValue/20
    if self.center < 0 and newCenter > -1 then
        self.center = 1
    elseif self.center > 0 and newCenter < 1 then
        self.center = -1
    else 
        self.center = math.clamp(newCenter, -self.MAX_CENTER, self.MAX_CENTER)
    end
	self:setInputTextDirty()
end

function LinePointBrush:activate()
	self.graphWrapper:resetSelected()
	self.graphWrapper:resetTemporaryPoints()
end

function LinePointBrush:deactivate()
	self:onButtonSecondary()
    self.graphWrapper:setMirrorSegmentActive(false)
end
function LinePointBrush:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end

function LinePointBrush:getButtonSecondaryText()
	return self:getTranslation(self.secondaryButtonText)
end

function LinePointBrush:getButtonTertiaryText()
	return self:getTranslation(self.tertiaryButtonText)
end

function LinePointBrush:getAxisPrimaryText()
	return self:getTranslation(self.primaryAxisText, self.offset)
end

function LinePointBrush:getAxisSecondaryText()
	return self:getTranslation(self.secondaryAxisText, self.center)
end
