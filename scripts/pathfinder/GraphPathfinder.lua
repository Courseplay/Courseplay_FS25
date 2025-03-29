--- A pathfinder based on A* to find the shortest path in a directed graph.
--- The graph is defined by its edges only, there are no nodes needed. 
---
--- Edges are represented by polylines, and they can unidirectional or bidirectional. 
--- Unidirectional edges can only be entered at one end (at the first vertex of the 
--- polyline) and exited at the other (last vertex of the polyline)
---
--- Bidirectional edges can be entered at either end, and exited at the other.
---
--- Edges don't have to be connected, as long as the entry of another edge is close 
--- enough to the exit of another, the entry is a valid successor node (of the exit, 
--- which is the predecessor)

---@class GraphPathfinder : HybridAStar
GraphPathfinder = CpObject(HybridAStar)

--- An edge of a directed graph
---@class GraphPathfinder.GraphEdge : Polyline
GraphPathfinder.GraphEdge = CpObject(Polyline)

GraphPathfinder.GraphEdge.UNIDIRECTIONAL = {}
GraphPathfinder.GraphEdge.BIDIRECTIONAL = {}

---@param direction table GraphEdge.UNIDIRECTIONAL or GraphEdge.BIDIRECTIONAL
---@param vertices table[] array of tables with x, y (Vector, Vertex, State3D or just plain {x, y}
function GraphPathfinder.GraphEdge:init(direction, vertices)
    Polyline.init(self, vertices)
    self.direction = direction
end

function GraphPathfinder.GraphEdge:getDirection()
    return self.direction
end

---@return boolean is this a bidirectional edge?
function GraphPathfinder.GraphEdge:isBidirectional()
    return self.direction == GraphPathfinder.GraphEdge.BIDIRECTIONAL
end

---@return Vertex[] array of vertices that can be used to enter this edge (one for 
--- unidirectional, two for bidirectional edges)
function GraphPathfinder.GraphEdge:getEntries()
    if self:isBidirectional() then
        return { self[1], self[#self] }
    else
        return { self[1] }
    end
end

---@param entry Vector
---@return Vector the exit when entered through the given entry
function GraphPathfinder.GraphEdge:getExit(entry)
    if entry == self[1] then
        return self[#self]
    else
        return self[1]
    end
end

function GraphPathfinder.GraphEdge:rollUpIterator(entry)
    local from, to, step
    if entry == self[1] then
        -- unidirectional, or bidirectional, travelling from the start to end, roll up backwards
        from, to, step = #self + 1, 1, -1
    else
        from, to, step = 0, #self, 1
    end
    local i = from
    return function()
        i = i + step
        if i == to + step then
            return nil, nil
        else
            return i, self[i]
        end
    end
end

--- A pathfinder node, specialized for the GraphPathfinder
---@class GraphPathfinder.Node : State3D
GraphPathfinder.Node = CpObject(State3D)

---@param edge GraphPathfinder.GraphEdge the edge leading to this node: when rolling up the path, we need to add all
--- vertices of the edge
---@param entry Vector the entry point to this edge (when bidirectional, we may be travelling the edge from the end to
--- the start.
function GraphPathfinder.Node:init(x, y, g, pred, d, edge, entry)
    State3D.init(self, x, y, 0, g, pred, Gear.Forward, Steer.Straight, 0, d)
    self.edge = edge
    self.entry = entry
end

---@param yieldAfter number coroutine yield after so many iterations (number of iterations in one update loop)
---@param maxIterations number maximum iterations before failing
---@param range number when an edge's exit is closer than range to another edge's entry, the
--- two edges are considered as connected (and thus can traverse from one to the other)
---@param graph GraphPathfinder.GraphEdge[] Array of edges, the graph as described in the file header
function GraphPathfinder:init(yieldAfter, maxIterations, range, graph)
    self.logger = Logger('GraphPathfinder', Logger.level.debug, CpDebug.DBG_PATHFINDER)
    HybridAStar.init(self, { }, yieldAfter, maxIterations)
    self.range = range
    self.graph = graph
    self.deltaPosGoal = self.range
    self.deltaThetaDeg = 181
    self.deltaThetaGoal = math.rad(self.deltaThetaDeg)
    self.maxDeltaTheta = self.deltaThetaGoal
    self.originalDeltaThetaGoal = self.deltaThetaGoal
    self.analyticSolverEnabled = false
    self.ignoreValidityAtStart = false
end

--- for backwards compatibility with the old pathfinder
function GraphPathfinder:debug(...)
    self.logger:debug(...)
end

function GraphPathfinder:getMotionPrimitives(turnRadius, allowReverse)
    return GraphPathfinder.GraphMotionPrimitives(self.range, self.graph)
end

--- Override path roll up since here, the path also includes all edges of the graph, not just the pathfinder nodes
---@param lastNode GraphPathfinder.Node
function GraphPathfinder:rollUpPath(lastNode, goal, path)
    path = path or {}
    local currentNode = lastNode
    self:debug('Goal node at %.2f/%.2f, cost %.1f (%.1f - %.1f)', goal.x, goal.y, lastNode.cost,
            self.nodes.lowestCost, self.nodes.highestCost)
    while currentNode.pred and currentNode ~= currentNode.pred do
        if currentNode.edge then
            -- add the edge leading to the node
            for _, node in currentNode.edge:rollUpIterator(currentNode.entry) do
                table.insert(path, 1, node)
            end
        end
        currentNode = currentNode.pred
    end
    table.insert(path, 1, currentNode)
    self:debug('Nodes %d, iterations %d, yields %d, deltaTheta %.1f', #path, self.iterations, self.yields,
            math.deg(self.deltaThetaGoal))
    return path
end

function GraphPathfinder:initRun(start, goal, ...)
    self:createGraphEntryAndExit(start, goal)
    return HybridAStar.initRun(self, start, goal, ...)
end

--- The start location may not be close to the start or end of an edge. Therefore,
--- we need to look for entries among all the vertices of all edges in the graph. When we find that vertex, and
--- it isn't the first or last point of the edge, we simply split that edge at that vertex so the parts can
--- be used as entries.
--- We do the same for the goal node to be able to exit the graph at the middle of an edge.
function GraphPathfinder:createGraphEntryAndExit(start, goal)
    local function splitClosestEdge(node)
        local closestEdge, closestVertex
        local closestDistance = math.huge
        for _, edge in ipairs(self.graph) do
            local v, d = edge:findClosestVertexToPoint(node)
            if d and d < closestDistance then
                closestDistance = d
                closestEdge = edge
                closestVertex = v
            end
        end
        if closestVertex.ix ~= 1 and closestVertex.ix ~= #closestEdge then
            self.logger:trace('Graph entry found and split at vertex %d, %.1f %.1f', closestVertex.ix, closestVertex.x, closestVertex.y)
            local newEdge = GraphPathfinder.GraphEdge(closestEdge:getDirection())
            for i = closestVertex.ix, #closestEdge do
                newEdge:append(closestEdge[i])
            end
            newEdge:calculateProperties()
            table.insert(self.graph, newEdge)
            closestEdge:cutEndAtIx(closestVertex.ix)
        end
    end
    splitClosestEdge(start)
    splitClosestEdge(goal)
end

--- Motion primitives to use with the graph pathfinder, providing the entries
--- to the next edges.
---@class GraphPathfinder.GraphMotionPrimitives : HybridAStar.MotionPrimitives
GraphPathfinder.GraphMotionPrimitives = CpObject(HybridAStar.MotionPrimitives)

---@param range number when an edge's exit is closer than range to another edge's entry, the
--- two edges are considered as connected (and thus can traverse from one to the other)
---@param graph Vector[] the graph as described in the file header
function GraphPathfinder.GraphMotionPrimitives:init(range, graph)
    self.logger = Logger('GraphMotionPrimitives', Logger.level.debug, CpDebug.DBG_PATHFINDER)
    self.range = range
    self.graph = graph
end

---@return table [{x, y, d}] array of the next possible entries, their coordinates and
--- the distance to the entry + the length of the edge
function GraphPathfinder.GraphMotionPrimitives:getPrimitives(node)
    local primitives = {}
    for _, edge in ipairs(self.graph) do
        local entries = edge:getEntries()
        for _, entry in ipairs(entries) do
            local distanceToEntry = (node - entry):length()
            if distanceToEntry <= self.range then
                local exit = edge:getExit(entry)
                table.insert(primitives, { x = exit.x, y = exit.y, d = edge:getLength() + distanceToEntry,
                                           edge = edge, entry = entry })
                self.logger:trace('\t primitives: %.1f %.1f', exit.x, exit.y)
            end
        end
    end
    return primitives
end

---@return State3D successor for the given primitive
function GraphPathfinder.GraphMotionPrimitives:createSuccessor(node, primitive, hitchLength)
    self.logger:trace('\t\tsuccessor: %.1f %.1f (d=%.1f) from node: %.1f %.1f (g=%.1f, d=%.1f)',
            primitive.x, primitive.y, primitive.d, node.x, node.y, node.g, node.d)
    return GraphPathfinder.Node(primitive.x, primitive.y, node.g, node, node.d + primitive.d, primitive.edge, primitive.entry)
end

