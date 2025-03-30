---@class Graph : GraphNode
---@field _childNodes GraphSegment[]
Graph = CpObject(GraphNode)
Graph.XML_KEY = "Graph"
function Graph:init()
    GraphNode.init(self)
    g_consoleCommands:registerConsoleCommand("cpGraphFindPathTo", 
        "Tries to find a path to: ", "consoleCommandFindPathTo", self)
    g_consoleCommands:registerConsoleCommand("cpGraphGenerateFromSplines", 
        "Generates segmenets from traffic splines", 
        "consoleCommandGenerateSegmentsFromSplines", self)

    ---@type GraphTarget[]
    self._targets = {}
    self._hasGeneratedSplines = false
end

function Graph:delete()
    
end

function Graph:consoleCommandFindPathTo(name)
    if not name then 
        return "No target given!"
    end
    local cmd = function ()
        local edges = {}
        local targetPos
        for _, seg in ipairs(self._childNodes) do 
            for _, node in ipairs(seg:getAllChildNodes()) do 
                local target = node:getTarget()
                if target and target:getName() == name then 
                    local x, z = node:getPosition2D()
                    targetPos = Vector(x, -z)
                end
            end
            local edge = seg:toGraphEdge()
            print(tostring(edge))
            table.insert(edges, edge)
        end
        if targetPos == nil or targetPos.x == nil or targetPos.y == nil then
            return "Failed to find target!"
        end
        local vehicle = CpUtil.getCurrentVehicle()
        if vehicle == nil then 
            return "Must be in a vehicle!"
        end
        local pathfinder = GraphPathfinder(1000, 500, 20, edges)
        local start = PathfinderUtil.getVehiclePositionAsState3D(vehicle)
        local goal = State3D(targetPos.x, targetPos.y, 0, 0)
        CpUtil.info("Goal: %s", tostring(goal))
        local TestConstraints = CpObject(PathfinderConstraintInterface)
        local result = pathfinder:start(start, goal, 1, false, TestConstraints(), 0)
        while not result.done do
            result = pathfinder:resume()
        end
        if result.path == nil or #result.path < 2 then
            return "Pathfinder failed!"
        end
        local course = Course.createFromAnalyticPath(vehicle, result.path, true)
        vehicle:setFieldWorkCourse(course)
    end
    local success, ret = CpUtil.try(cmd)
    if not success or ret then 
        CpUtil.info(ret)
    end
end

function Graph:consoleCommandGenerateSegmentsFromSplines()
    if self._hasGeneratedSplines then 
        CpUtil.info("Already generated from road splines!")
        return
    end
    local function isSplineEqual(segA, segB)
        local snA1 = segA:getChildNodeByIndex(1)
        local enA1 = segA:getChildNodeByIndex(segA:getNumChildNodes())
        local snA2 = segA:getChildNodeByIndex(2)
        local enA2 = segA:getChildNodeByIndex(segA:getNumChildNodes() - 1)

        local snB1 = segB:getChildNodeByIndex(1)
        local enB1 = segB:getChildNodeByIndex(segB:getNumChildNodes())
        local snB2 = segB:getChildNodeByIndex(2)
        local enB2 = segB:getChildNodeByIndex(segB:getNumChildNodes() - 1)
        local margin = 3
        if (snA1:getDistance2DToPoint(enB1) <= margin or 
            snA1:getDistance2DToPoint(enB2) <= margin or 
            snA2:getDistance2DToPoint(enB1) <= margin or 
            snA2:getDistance2DToPoint(enB2) <= margin) and
            (snB1:getDistance2DToPoint(enA1) <= margin or 
            snB1:getDistance2DToPoint(enA2) <= margin or 
            snB2:getDistance2DToPoint(enA1) <= margin or 
            snB2:getDistance2DToPoint(enA2) <= margin) then 

            return true
        end
    end

    local splineToCount = {}
    for spline, _ in pairs(g_currentMission.aiSystem:getRoadSplines()) do
        splineToCount[spline] = 0
        local sx, _, sz = getSplinePosition(spline, 0)
        local ex, _, ez = getSplinePosition(spline, 0)
        local length = getSplineLength(spline)
        for otherSpline, _ in pairs(g_currentMission.aiSystem:getRoadSplines()) do
            if spline ~= otherSpline then 
                local dsx, _, dsz = getSplinePosition(otherSpline, 0)
                local dex, _, dez = getSplinePosition(otherSpline, 0)
                if MathUtil.vector2Length(sx - dsx, sz - dsz) < 1 or 
                    MathUtil.vector2Length(sx - dex, sz - dez) < 1 or
                    MathUtil.vector2Length(ex - dsx, ez - dsz) < 1 or 
                    MathUtil.vector2Length(ex - dex, ez - dez) < 1 then
                    if length < getSplineLength(otherSpline) then
                        splineToCount[spline] = splineToCount[spline] + 1
                    end
                end
            end
        end
    end
    local splineSegments = {}
    for spline, count in pairs(splineToCount) do
        local ignoreSpline = count > 0
        local length = getSplineLength(spline)
        local segment = GraphSegment(true)
        if not ignoreSpline then
            for i = 0, 1, 6/length do 
                local posX, posY, posZ = getSplinePosition(spline, i)
                local point = GraphPoint()
                point:setPosition(posX, posY, posZ)
                segment:appendChildNode(point)
            end
            if segment:getNumChildNodes() > 1 then
                for _, seg in ipairs(splineSegments) do 
                    if isSplineEqual(segment, seg) then
                        seg:changeDirection(GraphSegmentDirection.DUAL)
                        ignoreSpline = true
                        break
                    end
                end
                if not ignoreSpline then
                    table.insert(splineSegments, segment)
                end
            end
        end
    end 
    self:extendByChildNodes(splineSegments, false)
    self._hasGeneratedSplines = true
end

function Graph:setup()
    ---@type GraphPlot
    self._ingameMapPlot = GraphPlot(self)
end

function Graph.registerXmlSchema(xmlSchema, baseKey)
    GraphSegment.registerXmlSchema(xmlSchema, 
        baseKey .. Graph.XML_KEY .. ".")
    xmlSchema:register(XMLValueType.BOOL, 
        baseKey .. Graph.XML_KEY .. "#hasGeneratedSplines", 
        "Has generated splines?", false)
end

function Graph:loadFromXMLFile(xmlFile, baseKey)
    xmlFile:iterate(baseKey .. self.XML_KEY .. "." .. GraphSegment.XML_KEY, function (ix, key)
        local segment = GraphSegment()
        segment:loadFromXMLFile(xmlFile, key)
        self:appendChildNode(segment)
    end)
    self._hasGeneratedSplines = xmlFile:getValue(
        baseKey .. self.XML_KEY .. "#hasGeneratedSplines")
end

function Graph:saveToXMLFile(xmlFile, baseKey)
    for i, segment in ipairs(self._childNodes) do 
        segment:saveToXMLFile(xmlFile, string.format("%s.%s(%i)", 
            baseKey .. self.XML_KEY, GraphSegment.XML_KEY, i - 1))
    end
    xmlFile:setValue(baseKey .. self.XML_KEY .. "#hasGeneratedSplines", 
        self._hasGeneratedSplines)
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

---@param target GraphTarget
function Graph:onTargetCreated(target)
    table.insert(self._targets, target)
end

---@param target GraphTarget
function Graph:onTargetDeleted(target)
    local ixToRemove
    for i=#self._targets, 1, -1 do
        if self._targets[i] == target then
            ixToRemove = i
            break
        end
    end
    table.remove(self._targets, ixToRemove)
end

---@type Graph
g_graph = Graph()