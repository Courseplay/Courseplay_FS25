---@class Graph : GraphNode
---@field _childNodes GraphSegment[]
Graph = CpObject(GraphNode)
Graph.XML_KEY = "Graph"
function Graph:init()
    GraphNode.init(self)
end

function Graph:setup()
    ---@type GraphPlot
    self._ingameMapPlot = GraphPlot(self)
end

function Graph.registerXmlSchema(xmlSchema, baseKey)
    GraphSegment.registerXmlSchema(xmlSchema, 
        baseKey .. Graph.XML_KEY .. ".")
end

function Graph:loadFromXMLFile(xmlFile, baseKey)
    xmlFile:iterate(baseKey .. self.XML_KEY .. "." .. GraphSegment.XML_KEY, function (ix, key)
        local segment = GraphSegment()
        segment:loadFromXMLFile(xmlFile, key)
        self:appendChildNode(segment)
    end)
end

function Graph:saveToXMLFile(xmlFile, baseKey)
    for i, segment in ipairs(self._childNodes) do 
        segment:saveToXMLFile(xmlFile, string.format("%s.%s(%i)", 
            baseKey .. self.XML_KEY, GraphSegment.XML_KEY, i - 1))
    end
end

---@param node GraphNode
function Graph:onAddedChildNode(node)
    GraphNode.onAddedChildNode(self, node)
 
end

---@param node GraphNode
function Graph:onRemovedChildNode(node)
    GraphNode.onRemovedChildNode(self, node)
    
end

---@param hoveredNodeID string|nil
---@param selectedNodeIDs table<string, boolean>|nil
function Graph:draw(hoveredNodeID, selectedNodeIDs)
    for i, segment in ipairs(self._childNodes) do 
        segment:draw(hoveredNodeID, selectedNodeIDs)
    end
end

function Graph:drawMap(map)
    self._ingameMapPlot:draw(map)
end

function Graph:update(dt)

end

---@return GraphSegment[]
function Graph:getSegments()
    return self._childNodes
end

---@return GraphPoint[]
function Graph:getAllPoints()
    local points = {}
    for _, segment in ipairs(self._childNodes) do 
        for _, point in ipairs(segment:getPoints()) do 
            table.insert(points, point)
        end
    end
    return points
end

---@param index string|nil
---@return GraphPoint|nil
function Graph:getPointByIndex(index)
    if index == nil then 
        return
    end
    local _, _, ix, jx = string.find(index, "(%d+).(%d+)")
    if ix ~= nil and jx ~= nil then 
        local segment = self:getChildNodeByIndex(tonumber(ix))
        if segment then 
            local point = segment:getChildNodeByIndex(tonumber(jx))
            if point then 
                return point
            else 
                CpUtil.info("Failed to get Graph segement(%d) point: %d", ix, jx)
            end
        else 
            CpUtil.info("Failed to get Graph segment for: %d", ix)
        end
    else 
        CpUtil.info("Failed to get Graph index: %s", index)
    end
end

---@param x number
---@param y number
---@param z number
---@return GraphSegment
function Graph:createSegmentWithPoint(x, y, z)
    local segment = GraphSegment()
    local point = GraphPoint()
    point:setPosition(x, y, z)
    segment:appendChildNode(point)
    self:appendChildNode(segment)
    return segment
end

---@type Graph
g_graph = Graph()