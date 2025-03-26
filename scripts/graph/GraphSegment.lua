---@class GraphSegmentDirection
GraphSegmentDirection = {}
GraphSegmentDirection.FORWARD   = 1
GraphSegmentDirection.REVERSE   = 2
GraphSegmentDirection.DUAL      = 3
GraphSegmentDirection.MAX_KEY   = GraphSegmentDirection.DUAL
GraphSegmentDirection.DEBUG_TEXTS = {
    [GraphSegmentDirection.FORWARD] = "Forward",
    [GraphSegmentDirection.REVERSE] = "Reverse",
    [GraphSegmentDirection.DUAL]    = "Dual",
}

---@class GraphSegment : GraphNode
---@field _childNodes GraphPoint[]
GraphSegment = CpObject(GraphNode)
GraphSegment.XML_KEY = "Segment"
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
---@param temporaryPrevPoint GraphNode|nil
function GraphSegment:draw(hoveredNodeID, selectedNodeIDs, isTemporary, temporaryPrevPoint)
    local prevPoint = temporaryPrevPoint
    for _, point in ipairs(self._childNodes) do 
        point:draw(hoveredNodeID, selectedNodeIDs, isTemporary)
        if prevPoint then
            local color = {0, 0.5, 1}
            local x, y, z = point:getPosition()
            local dx, dy, dz = prevPoint:getPosition()
            DebugUtil.drawDebugLine(x, y + 2, z, 
                dx, dy + 2, dz, unpack(color), 2)
            local dist = MathUtil.vector3Length(x - dx, y - dy, z - dz)
            if dist > 1 then 
                local nx, _, nz = MathUtil.vector3Normalize(x - dx, y - dy, z - dz)
                local delta = 2
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
                        DebugUtil.drawDebugLine(tx, y, tz,
                            tx - ncx * 2, y, tz - ncz * 2, unpack(color))
                        ncx = nx * math.cos(-math.pi/4) - nz * math.sin(-math.pi/4)
                        ncz = nx * math.sin(-math.pi/4) + nz * math.cos(-math.pi/4)
                        DebugUtil.drawDebugLine(tx, y, tz,
                            tx - ncx * 2, y, tz - ncz * 2, unpack(color))
                    elseif self._direction == GraphSegmentDirection.DUAL then
                        -- x, y, z, radius, steps, color, alignToTerrain, filled
                        DebugUtil.drawDebugCircle(dx + nx * i, y, dz + nz * i,
                            1, 10, color)
                    end
                end
            end
        end
        prevPoint = point
    end
end

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

function GraphSegment:getDirectionString()
   return GraphSegmentDirection.DEBUG_TEXTS[self._direction] or "???"
end