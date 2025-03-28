---@class EditorGraphWrapper
EditorGraphWrapper = CpObject()
EditorGraphWrapper.MIN_DISTANCE = 1
function EditorGraphWrapper:init(graph)
	---@type Graph
	self.graph = graph
	
	self.selectedNodeIds = {}
	self.hoveredNodeId = nil
	self.disabledBuffer = {}

	self.visiblePoints = {}
	self.lastPosition = {0, 0, 0}
	self.isDirty = false

	---@type GraphSegment
	self.temporarySegment = GraphSegment()
	---@type GraphSegment
	self.mirrorTemporarySegment = GraphSegment()
	self.isMirrorTemporaryActive = false
end

function EditorGraphWrapper:draw(position)
	self.graph:draw(self.hoveredNodeId, self.selectedNodeIds)
	self.temporarySegment:draw(nil, nil, true,
		self:getPointByIndex(self:getFirstSelectedNodeID()))
	if self.isMirrorTemporaryActive then 
		self.mirrorTemporarySegment:draw(nil, nil, true)
	end
	if not position then 
		return
	end
	local x, _, z = unpack(position)
	if x == nil or z == nil then 
		return
	end
end

--- TODO only shown points/segments in range?
function EditorGraphWrapper:getVisiblePoints()
	return self.graph:getAllPoints()
end

--- 
---@param id string|nil
---@return GraphPoint|nil
---@return string|nil
function EditorGraphWrapper:getPointByIndex(id)
	local point = self.graph:getPointByIndex(id)
	if point == nil then 
		return nil, "err_point_not_found"
	end
	return point
end

---@param id string|nil
---@return GraphSegment|nil
---@return string|nil
function EditorGraphWrapper:getSegmentByIndex(id)
	local point, err = self:getPointByIndex(id)
	if point == nil then 
		return nil, err
	end
	---@type GraphSegment
	local segment = point:getParentNode()
	if segment == nil then 
		return nil, "err_segment_not_found"
	end
	return segment
end

---@return number|nil
---@return number|nil
---@return number|nil
function EditorGraphWrapper:getPositionByIndex(id)
	local point = self:getPointByIndex(id)
	if point == nil then
		return
	end
	local x, y, z = point:getPosition()
	return x, y, z
end

---@param x number
---@param y number
---@param z number
---@return string|nil
function EditorGraphWrapper:createSegmentWithPoint(x, y, z)
	if x == nil or z == nil then 
		return
	end
	local segment = self.graph:createSegmentWithPoint(x, y, z)
	return segment:getChildNodeByIndex(1):getRelativeID()
end

---@param segment GraphSegment
function EditorGraphWrapper:addSegment(segment)
	self.graph:appendChildNode(segment)
end

---@param id string|nil
---@return boolean
---@return string|nil
function EditorGraphWrapper:removePointByIndex(id)
	local point, err = self:getPointByIndex(id)
	if point == nil then
		return false, err
	end
	point:unlink(function(p, segment)
		if not segment:hasChildNodes() then 
			segment:unlink()
		end
	end)
	return true
end

---@param id string|nil
---@return boolean
---@return string|nil
function EditorGraphWrapper:removeSegmentByPointIndex(id)
	local segment, err = self:getSegmentByIndex(id)
	if segment == nil then 
		return false, err
	end
	segment:clearChildNodes()
	segment:unlink()
	return true
end

---@param id string
---@param newPoint GraphPoint
---@return boolean
---@return string|nil
---@return string|nil
function EditorGraphWrapper:insertPointBehindIndex(id, newPoint)
	local point, err = self:getPointByIndex(id)
	if point == nil then
		return false, err
	end
	local segment, err = self:getSegmentByIndex(id)
	if segment == nil then
		return false, err
	end
	if point:getDistance2DToPoint(newPoint) <= EditorGraphWrapper.MIN_DISTANCE then
		return false, "err_min_distance_to_small"
	end
	local ix = segment:getChildNodeIndex(point)
	return true, nil, segment:insertChildNodeAtIndex(newPoint, ix + 1)
end

---@param id string
---@param newPoint GraphPoint
---@return boolean
---@return string|nil
---@return string|nil
function EditorGraphWrapper:insertPointAheadOfIndex(id, newPoint)
	local point, err = self:getPointByIndex(id)
	if point == nil then
		return false, err
	end
	local segment, err = self:getSegmentByIndex(id)
	if segment == nil then
		return false, err
	end
	if point:getDistance2DToPoint(newPoint) <= EditorGraphWrapper.MIN_DISTANCE then
		return false, "err_min_distance_to_small"
	end
	local ix = segment:getChildNodeIndex(point)
	return true, nil, segment:insertChildNodeAtIndex(newPoint, ix)
end

---@param id string|nil
---@param dx number
---@param dy number
---@param dz number
---@return boolean
---@return string|nil
function EditorGraphWrapper:movePointByIndex(id, dx, dy, dz)
	local point, err = self:getPointByIndex(id)
	if point == nil then 
		return false, err
	end
	point:moveTo(dx, dy, dz)
	return true
end

---@param id string|nil
---@return boolean
---@return string|nil
function EditorGraphWrapper:changeSegmentDirection(id)
	local segment, err = self:getSegmentByIndex(id)
	if segment == nil then 
		return false, err
	end
	segment:changeDirection()
	return true
end

---@param id string|nil
---@return boolean
---@return string|nil
function EditorGraphWrapper:isFirstSegmentPoint(id)
	local point, err = self:getPointByIndex(id)
	if point == nil then 
		return false, err
	end
	return point:isFirstNode()
end

---@param id string|nil
---@return boolean
---@return string|nil
function EditorGraphWrapper:isLastSegmentPoint(id)
	local point, err = self:getPointByIndex(id)
	if point == nil then 
		return false, err
	end
	return point:isLastNode()
end

---@param id string|nil
---@return boolean
---@return string|nil
function EditorGraphWrapper:isNotFirstOrLastSegmentPoint(id)
	local point, err = self:getPointByIndex(id)
	if point == nil then 
		return false, err
	end
	local isFirst = self:isFirstSegmentPoint(id)
	if isFirst then 
		return false, "err_node_is_first"
	end
	local isLast = self:isLastSegmentPoint(id)
	if isLast then 
		return false, "err_node_is_last"
	end
	return true
end

---@param id string|nil
---@return boolean
---@return string|nil
function EditorGraphWrapper:isFirstOrLastSegmentPoint(id)
	local point, err = self:getPointByIndex(id)
	if point == nil then 
		return false, err
	end
	local isFirst = self:isFirstSegmentPoint(id)
	if isFirst then 
		return true
	end
	local isLast = self:isLastSegmentPoint(id)
	if isLast then 
		return true
	end
	return false, "err_node_not_first_or_last"
end

---@param id string|nil
---@return boolean
---@return string|nil
function EditorGraphWrapper:isOnlyNodeLeftInSegment(id)
	local segment, err = self:getSegmentByIndex(id)
	if segment == nil then 
		return false, err
	end
	return segment:getNumChildNodes() <= 1
end

---@param idA string|nil
---@param idB string|nil
---@return boolean
---@return string|nil
function EditorGraphWrapper:isSegmentIDEqual(idA, idB)
	local segmentA, errA = self:getSegmentByIndex(idA)
	local segmentB, errB = self:getSegmentByIndex(idB)
	if segmentA == nil or segmentB == nil then 
		return false, errA or errB
	end
	return segmentA:getID() == segmentB:getID()
end

---@param idA string|nil
---@param idB string|nil
---@return boolean
---@return string|nil
function EditorGraphWrapper:mergeSegments(idA, idB)
	local segmentA, errA = self:getSegmentByIndex(idA)
	local segmentB, errB = self:getSegmentByIndex(idB)
	if segmentA == nil then 
		return false, errA
	end
	if  segmentB == nil then 
		return false, errB
	end
	if segmentA:getID() == segmentB:getID() then 
		return false, "err_same_segment"
	end
	local success, err = self:isFirstOrLastSegmentPoint(idA)
	if not success then 
		return false, err
	end
	local success, err = self:isFirstOrLastSegmentPoint(idB)
	if not success then 
		return false, err
	end
	if self:isFirstSegmentPoint(idA) then 
		if self:isFirstSegmentPoint(idB) then 
			segmentA:prepandByChildren(segmentB, false)
		else 
			segmentA:prepandByChildren(segmentB, true)
		end
	else 
		if self:isFirstSegmentPoint(idB) then 
			segmentA:extendByChildren(segmentB, false)
		else
			segmentA:extendByChildren(segmentB, true)
		end
	end
	segmentB:clearChildNodes()
	segmentB:unlink()
	return true
end

---@param id string|nil
---@return boolean
---@return string|nil
function EditorGraphWrapper:splitSegment(id)
	local node, err = self:getPointByIndex(id)
	if node == nil then 
		return false, err
	end
	local segment, err = self:getSegmentByIndex(id)
	if segment == nil then 
		return false, err
	end
	local success, err = self:isNotFirstOrLastSegmentPoint(id)
	if not success then
		return false, err
	end
	local ix = segment:getChildNodeIndex(node)
	local postNodes = segment:cloneChildNodesBetweenIndex(ix + 1, segment:getNumChildNodes())
	segment:removeChildNodesBetweenIndex(ix + 1, segment:getNumChildNodes())
	---@type GraphSegment
	local newSegment = GraphSegment()
	newSegment:extendByChildNodes(postNodes, false)
	self.graph:appendChildNode(segment)
	return true
end

--------------------------
--- Selected nodes
--------------------------

---@param ix string|nil
function EditorGraphWrapper:setSelected(ix)
	if ix ~=nil then
		self.selectedNodeIds[ix] = true
	end
end

---@return table<string, boolean>
function EditorGraphWrapper:getSelectedNodeIDs()
	return self.selectedNodeIds
end

---@return string|nil
function EditorGraphWrapper:getFirstSelectedNodeID()
	return next(self.selectedNodeIds)
end

---@param ix string|nil
---@return boolean|nil
function EditorGraphWrapper:isSelected(ix)
	return self.selectedNodeIds[ix]
end

function EditorGraphWrapper:resetSelected()
	self.selectedNodeIds = {}
end

---@return boolean|nil
function EditorGraphWrapper:hasSelectedNode()
	return next(self.selectedNodeIds) ~= nil
end

--------------------------
--- Hovered node nodes
--------------------------

function EditorGraphWrapper:setHovered(ix)
	self.hoveredNodeId = ix
end

function EditorGraphWrapper:isHovered(ix)
	return ix ~= nil and self.hoveredNodeId == ix
end

function EditorGraphWrapper:resetHovered()
	self.hoveredNodeId = nil
end

----------------------------
--- Temporary Waypoints
----------------------------

---@param x any
---@param y any
---@param z any
---@return GraphPoint|nil
function EditorGraphWrapper:addTemporaryPoint(x, y, z)
	if x == nil or y == nil or z == nil then 
		return
	end
	local point = GraphPoint()
	point:setPosition(x, y, z)
	self.temporarySegment:appendChildNode(point)
	return point
end


---@param x any
---@param y any
---@param z any
---@return GraphPoint|nil
function EditorGraphWrapper:addMirrorTemporaryPoint(x, y, z)
	if x == nil or y == nil or z == nil then 
		return
	end
	local point = GraphPoint()
	point:setPosition(x, y, z)
	self.mirrorTemporarySegment:insertChildNodeAtIndex(point, 1)
	return point
end


---@return boolean
function EditorGraphWrapper:hasTemporaryPoints()
	return self.temporarySegment:hasChildNodes()
end

---@return GraphPoint[]
function EditorGraphWrapper:getTemporaryPoints()
	return self.temporarySegment:getAllChildNodes()
end

---@return GraphSegment
function EditorGraphWrapper:getTemporarySegment()
	return self.temporarySegment
end

---@return GraphPoint|nil
function EditorGraphWrapper:getFirstTemporaryPoint()
	return self.temporarySegment:getChildNodeByIndex(1)
end

---@return GraphPoint[]
function EditorGraphWrapper:cloneTemporarySegment()
	return self.temporarySegment:clone()
end

function EditorGraphWrapper:clearTemporaryPoints()
	self.temporarySegment:clearChildNodes()
	self.mirrorTemporarySegment:clearChildNodes()
end

function EditorGraphWrapper:resetTemporaryPoints()
	self:clearTemporaryPoints()
end

---@param active boolean
function EditorGraphWrapper:setMirrorSegmentActive(active)
	self.isMirrorTemporaryActive = active
end

---@return boolean
function EditorGraphWrapper:isMirrorSegmentActive()
	return self.isMirrorTemporaryActive
end

function EditorGraphWrapper:toggleMirrorSegmentActive()
	self.isMirrorTemporaryActive = not self.isMirrorTemporaryActive
end

---@return GraphSegment
function EditorGraphWrapper:getMirrorSegment()
	return self.mirrorTemporarySegment
end

----------------------------
--- Destinations
----------------------------

---@param id string|nil
---@return boolean
---@return string|nil
function EditorGraphWrapper:hasTargetByIndex(id)
	local point, err = self:getPointByIndex(id)
	if not point then 
		return false, err
	end
	if not point:hasTarget() then 
		return false, "err_target_not_found"
	end
	return true
end

---@param id string|nil
---@return boolean
---@return string|nil
function EditorGraphWrapper:createTargetForIndex(id, name)
	local point, err = self:getPointByIndex(id)
	if not point then 
		return false, err
	end
	if not point:createTarget(name) then 
		return false, "err_already_has_target"
	end
	return point:createTarget(name)
end

---@param id string|nil
---@return boolean|nil
---@return string|nil
function EditorGraphWrapper:removeTargetForIndex(id)
	local point, err = self:getPointByIndex(id)
	if not point then 
		return false, err
	end
	if not point:removeTarget() then 
		return false, "err_target_not_found"
	end
	return true
end

---@param id string|nil
---@return GraphTarget|nil
---@return string|nil
function EditorGraphWrapper:getTargetForIndex(id)
	local point, err = self:getPointByIndex(id)
	if not point then 
		return nil, err
	end
	if not point:hasTarget() then 
		return nil, "err_target_not_found"
	end
	return point:getTarget()
end