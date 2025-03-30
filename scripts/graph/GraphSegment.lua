---@class GraphSegmentDirection
GraphSegmentDirection = {}
GraphSegmentDirection.FORWARD   = 1
GraphSegmentDirection.REVERSE   = 2
GraphSegmentDirection.DUAL      = 3
GraphSegmentDirection.MAX_KEY   = GraphSegmentDirection.DUAL
GraphSegmentDirection.COLORS = {
    [GraphSegmentDirection.FORWARD] = {0.0742, 0.4341, 0.6939, 1},
    [GraphSegmentDirection.REVERSE] = {0.0284, 0.0284, 0.0284, 1},
    [GraphSegmentDirection.DUAL]    = {0.8, 0.4, 0, 1},
}
GraphSegmentDirection.DEBUG_TEXTS = {
    [GraphSegmentDirection.FORWARD] = "Forward",
    [GraphSegmentDirection.REVERSE] = "Reverse",
    [GraphSegmentDirection.DUAL]    = "Dual",
}

---@class GraphSegment : GraphNode
---@field _childNodes GraphPoint[]
GraphSegment = CpObject(GraphNode)
GraphSegment.XML_KEY = "Segment"
GraphSegment.DRAW_CAMERA_RANGE = 200
function GraphSegment:init()
    GraphNode.init(self)
    self._direction = GraphSegmentDirection.FORWARD
end

function GraphSegment.registerXmlSchema(xmlSchema, baseKey)
    local key = baseKey .. GraphSegment.XML_KEY
    xmlSchema:register(XMLValueType.INT, 
        key .. "(?)#direction", 
        "Current direction", GraphSegmentDirection.FORWARD)
    GraphPoint.registerXmlSchema(xmlSchema, key .. "(?).")
end

function GraphSegment:loadFromXMLFile(xmlFile, baseKey)
    self._direction = xmlFile:getValue(baseKey .. "#direction", GraphSegmentDirection.FORWARD)
    xmlFile:iterate(baseKey .. "." .. GraphPoint.XML_KEY, function (ix, key)
        local point = GraphPoint()
        point:loadFromXMLFile(xmlFile, key)
        self:appendChildNode(point)
    end)
end

function GraphSegment:saveToXMLFile(xmlFile, baseKey)
    xmlFile:setValue(baseKey .. "#direction", self._direction)
    for i, point in ipairs(self._childNodes) do 
        local key = string.format("%s.%s(%d)", baseKey, GraphPoint.XML_KEY, i - 1)
        point:saveToXMLFile(xmlFile, key)
    end
end

---@param newNode GraphSegment
---@param unlink boolean|nil
function GraphSegment:copyTo(newNode, unlink)
    GraphNode.copyTo(self, newNode, unlink)
    newNode._direction = self._direction
end

---@return GraphSegment
---@param unlink boolean|nil
function GraphSegment:clone(unlink)
    local newSegment = GraphSegment()
    self:copyTo(newSegment, unlink)
    return newSegment
end

---@param hoveredNodeID string|nil
---@param selectedNodeIDs table<string, boolean>|nil
---@param isTemporary boolean|nil
---@param temporaryPrevPoint GraphPoint|nil
function GraphSegment:draw(hoveredNodeID, selectedNodeIDs, isTemporary, temporaryPrevPoint)
    local prevPoint = temporaryPrevPoint
    for _, point in ipairs(self._childNodes) do 
        local x, y, z = point:getPosition()
        if DebugUtil.isPositionInCameraRange(x, y, z, self.DRAW_CAMERA_RANGE) then
            point:draw(hoveredNodeID, selectedNodeIDs, isTemporary)
            self:drawLineBetween(prevPoint, point)
        end
        prevPoint = point
    end
end

---@param prevPoint GraphPoint|nil
---@param point GraphPoint
function GraphSegment:drawLineBetween(prevPoint, point)
    if prevPoint then
        local color = {0, 0.5, 1}
        local x, y, z = point:getPosition()
        local dx, dy, dz = prevPoint:getPosition()
        DebugUtil.drawDebugLine(x, y + 2, z, 
            dx, dy + 2, dz, unpack(color), 2)
        local dist = MathUtil.vector3Length(x - dx, y - dy, z - dz)
        if dist > 1 then 
            local nx, _, nz = MathUtil.vector3Normalize(x - dx, y - dy, z - dz)
            local delta = 6
            local numArrows = dist / delta + 1 
            local spacing = dist / (numArrows + 1)
            if self._direction == GraphSegmentDirection.REVERSE then 
                nz = -1 * nz
                nx = -1 * nx
            end
            for i = spacing/2, dist, spacing do     
                if self._direction == GraphSegmentDirection.FORWARD or 
                    self._direction == GraphSegmentDirection.REVERSE then 
                
                    local tx, tz = dx + nx * i, dz + nz * i
                    if self._direction == GraphSegmentDirection.REVERSE then 
                        tx, tz = x + nx * i, z + nz * i
                    end
                    local ncx = nx * math.cos(math.pi/4) - nz * math.sin(math.pi/4)
                    local ncz = nx * math.sin(math.pi/4) + nz * math.cos(math.pi/4)                    
                    DebugUtil.drawDebugLine(tx, y + 2, tz,
                        tx - ncx * 2, y + 2, tz - ncz * 2, unpack(color))
                    ncx = nx * math.cos(-math.pi/4) - nz * math.sin(-math.pi/4)
                    ncz = nx * math.sin(-math.pi/4) + nz * math.cos(-math.pi/4)
                    DebugUtil.drawDebugLine(tx, y + 2, tz,
                        tx - ncx * 2, y + 2, tz - ncz * 2, unpack(color))
                elseif self._direction == GraphSegmentDirection.DUAL then
                    -- x, y, z, radius, steps, color, alignToTerrain, filled
                    DebugUtil.drawDebugCircle(dx + nx * i, y + 2, dz + nz * i,
                        1, 8, color)
                end
            end
        end
    end
end

---@return table
function GraphSegment:getDebugInfos()
    return {string.format("Direction: %s", self:getDirectionString())}
end

---@return GraphPoint[]
function GraphSegment:getPoints()
    return self._childNodes
end

---@param newDirection number|nil
function GraphSegment:changeDirection(newDirection)
    if newDirection == nil then 
        newDirection = self._direction + 1 
        if newDirection > GraphSegmentDirection.MAX_KEY then 
            newDirection = 1
        end
    end
    self._direction = newDirection
end

---@return string
function GraphSegment:getDirectionString()
   return GraphSegmentDirection.DEBUG_TEXTS[self._direction] or "???"
end

---@return number
---@return number
---@return number
---@return number
function GraphSegment:getDirectionColor()
    return GraphSegmentDirection.COLORS[self._direction] or 0,0,0,1
end

---@return number
function GraphSegment:getLength()
    local length = 0
    for ix, node in ipairs(self._childNodes) do 
        if ix > 1 then
            length = length + node:getDistance2DToPoint(self._childNodes[ix-1]) 
        end
    end
    return length
end

---@return boolean
function GraphSegment:isReverse()
    return self._direction == GraphSegmentDirection.REVERSE
end

---@return boolean
function GraphSegment:isDual()
    return self._direction == GraphSegmentDirection.DUAL
end

function GraphSegment:toGraphEdge()
    local points = {}
    local sx, ex, inc = 1, #self._childNodes, 1
    if self:isReverse() then 
        sx, ex, inc = #self._childNodes, 1, -1
    end
    for i = sx, ex, inc do
        table.insert(points, self._childNodes[i]:toVector())
    end
    if self:isDual() then 
        return GraphPathfinder.GraphEdge(
            GraphPathfinder.GraphEdge.BIDIRECTIONAL, points)
    else 
        return GraphPathfinder.GraphEdge(
            GraphPathfinder.GraphEdge.UNIDIRECTIONAL, points)
    end
end