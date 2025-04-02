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

-- allow to inherit clone
function GraphPathfinder.GraphEdge:_getNewInstance()
    return GraphPathfinder.GraphEdge()
end

function GraphPathfinder.GraphEdge:clone()
    local clone = Polyline.clone(self)
    clone.direction = self.direction
    return clone
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

GraphPathfinder.HelperGraphEdge = CpObject(GraphPathfinder.GraphEdge)
--- Helper edges are to entry/exit the graph from the goal/start. We don't want these to be part of the path, so we
--- the roll up iterator returns nothing, automatically skip the vertices of these edges
function GraphPathfinder.HelperGraphEdge:rollUpIterator(entry)
    return function()
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

--- Create a graph pathfinder.
---
--- Use start(start, goal) as described at PathfinderInterface:start() to run the pathfinder.
--- The entry at the graph will be at the vertex closest to the start location, the exit at the vertex closest
--- to the goal location. (The graph's edges are polylines, consisting of vertices). There is no limitation for the
--- distance between the entry/exit vertices and the start/goal locations.
---
--- The resulting path will only contain vertices of the edges that are traversed from the entry to the exit, it
--- will not contain the start or the goal. The caller is responsible for creating the sections from the start to the
--- entry (first point of the path) and from the exit (last point of the path) to the goal.
---
---@param yieldAfter number coroutine yield after so many iterations (number of iterations in one update loop)
---@param maxIterations number maximum iterations before failing
---@param range number when an edge's exit is closer than range to another edge's entry, the
--- two edges are considered as connected (and thus can traverse from one to the other)
---@param graph GraphPathfinder.GraphEdge[] Array of edges, the graph as described in the file header
function GraphPathfinder:init(yieldAfter, maxIterations, range, graph)
    HybridAStar.init(self, { }, yieldAfter, maxIterations)
    self.logger = Logger('GraphPathfinder', Logger.level.trace, CpDebug.DBG_PATHFINDER)
    self.range = range
    -- make a copy of the graph as we'll modify it
    self.graph = {}
    for _, e in ipairs(graph) do
        table.insert(self.graph, e:clone())
    end
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
        -- add the edge leading to the node
        for _, node in currentNode.edge:rollUpIterator(currentNode.entry) do
            if node ~= path[1] then
                -- don't insert the same node twice (we'll have the same node twice when we split edges)
                table.insert(path, 1, node)
            end
        end
        currentNode = currentNode.pred
    end
    self:debug('Nodes %d, iterations %d, yields %d, deltaTheta %.1f', #path, self.iterations, self.yields,
            math.deg(self.deltaThetaGoal))
    return path
end

function GraphPathfinder:initRun(start, goal, ...)
    local graphEntry, graphExit = self:createGraphEntryAndExit(start, goal)
    local distance = (graphExit - graphEntry):length()
    if distance <= self.range then
        -- if the distance between the entry and exit is less than the range, we can just return the entry as the exit
        self.logger:error('Graph entry and exit are closer than %.1f meters (%.1f), no point in running the pathfinder.',
                self.range, distance)
        return PathfinderResult(true, nil, true)
    end
    return HybridAStar.initRun(self, start, goal, ...)
end

--- Create the entry and exit edges for the graph.
---
--- The problem we are trying to solve here, is that the start and goal can be in any distance from any edge of the
--- graph, like when the vehicle sits in the middle of a field, surrounded by streets. Any street could be used as
--- an entry, and the closest street may not be the shortest path to the goal. A special case of this is when
--- the street is a two lane, two way street and our goal is to the left, but the closest edge is the right lane,
--- leading away from the goal, forcing us making an unnecessary detour.
---
--- Therefore, it isn't enough to find the closest vertex of the graph, we need a list of the closest vertices and
--- as long as their distance is not bigger than the distance to the closest one + the range, we can use them as
--- entries/exits.
---
--- To make sure that the algorithm actually uses these entry/exit points, we add helper edges to the graph, leading
--- from the start to the entries and from the exits to the goal.
---
--- When the closest vertex, isn't the first or last point of the edge, we simply split that edge at that vertex so
--- the parts can be used as entries/exits.
---
---@param start State3D the start location for the pathfinder
---@param goal State3D the goal location for the pathfinder
---@return State3D the entry vertex of the graph, closest to start
---@return State3D the exit vertex of the graph, closest to goal
function GraphPathfinder:createGraphEntryAndExit(start, goal)

    local function splitEdgeWhenNeeded(edge, closestVertex)
        -- if the vertex is the first or last vertex of the edge, we can use it directly as the entry/exit,
        -- otherwise, we split the edge at the vertex so we can use it as an entry/exit point.
        if closestVertex.ix ~= 1 and closestVertex.ix ~= #edge then
            self.logger:debug('Graph entry/exit found and split at vertex %d, x: %.1f y: %.1f',
                    closestVertex.ix, closestVertex.x, closestVertex.y)
            local newEdge = GraphPathfinder.GraphEdge(edge:getDirection())
            for j = closestVertex.ix, #edge do
                newEdge:append(edge[j])
            end
            newEdge:calculateProperties()
            table.insert(self.graph, newEdge)
            edge:cutEndAtIx(closestVertex.ix)
            return newEdge
        end
    end

    -- find the edges closest to node. If the closest vertex isn't the first or last vertex of the edge, we split the
    -- edge at that vertex so we can use it as an entry/exit point.
    local function findClosestEdges(node, isEntry)
        local closestEdges = {}

        local function addToClosestEdge(edge, vertex, d)
            -- only add the edge if the vertex can be used as an entry/exit point
            if edge:isBidirectional() or
                    (isEntry and vertex.ix == 1) or
                    (not isEntry and vertex.ix == #edge) then
                table.insert(closestEdges, { d = d, edge = edge, vertex = vertex })
            end
        end

        -- we'll be adding items to self.graph from within the loop, but that should be ok, because the # is evaluated
        -- before the loop starts
        for i = 1, #self.graph do
            local edge = self.graph[i]
            local vertex, d = edge:findClosestVertexToPoint(node)
            local newEdge = splitEdgeWhenNeeded(edge, vertex)
            if newEdge then
                addToClosestEdge(newEdge, newEdge[1], d)
            end
            addToClosestEdge(edge, vertex, d)
        end
        table.sort(closestEdges, function(a, b)
            return a.d < b.d
        end)
        return closestEdges
    end

    local entryEdges, exitEdges = findClosestEdges(start, true), findClosestEdges(goal, false)
    -- only use the edge if it is close enough to the closest
    local maxDistance = entryEdges[1].d + self.range
    for i = 1, math.min(#entryEdges, 2) do
        if entryEdges[i].d <= maxDistance then
            table.insert(self.graph, GraphPathfinder.HelperGraphEdge(GraphPathfinder.UNIDIRECTIONAL, { start, entryEdges[i].vertex }))
        end
    end
    maxDistance = exitEdges[1].d + self.range
    for i = 1, math.min(#exitEdges, 2) do
        if exitEdges[i].d <= maxDistance then
            table.insert(self.graph, GraphPathfinder.HelperGraphEdge(GraphPathfinder.UNIDIRECTIONAL, { exitEdges[i].vertex, goal }))
        end
    end
    return State3D(entryEdges[1].vertex.x, entryEdges[1].vertex.y, 0, 0),
    State3D(exitEdges[1].vertex.x, exitEdges[1].vertex.y, 0, 0)
end

--- Motion primitives to use with the graph pathfinder, providing the entries
--- to the next edges.
---@class GraphPathfinder.GraphMotionPrimitives : HybridAStar.MotionPrimitives
GraphPathfinder.GraphMotionPrimitives = CpObject(HybridAStar.MotionPrimitives)

---@param range number when an edge's exit is closer than range to another edge's entry, the
--- two edges are considered as connected (and thus can traverse from one to the other)
---@param graph Vector[] the graph as described in the file header
function GraphPathfinder.GraphMotionPrimitives:init(range, graph)
    self.logger = Logger('GraphMotionPrimitives', Logger.level.trace, CpDebug.DBG_PATHFINDER)
    self.range = range
    self.graph = graph
end

---@return table [{x, y, d}] array of the next possible entries, their coordinates and
--- the distance to the entry + the length of the edge
function GraphPathfinder.GraphMotionPrimitives:getPrimitives(node)
    local primitives = {}
    self.logger:trace('\tpredecessor: %.1f %.1f (%.1f)', node.x, node.y, node.g)
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

