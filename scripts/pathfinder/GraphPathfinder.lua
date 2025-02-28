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

---@param yieldAfter number coroutine yield after so many iterations (number of iterations in one update loop)
---@param maxIterations number maximum iterations before failing
---@param range number when an edge's exit is closer than range to another edge's entry, the
--- two edges are considered as connected (and thus can traverse from one to the other)
---@param graph Vector[] the graph as described in the file header
function GraphPathfinder:init(yieldAfter, maxIterations, range, graph)
    HybridAStar.init(self, { }, yieldAfter, maxIterations)
    self.range = range
    self.graph = graph
    self.deltaPosGoal = self.range
    self.deltaThetaDeg = 181
    self.deltaThetaGoal = math.rad(self.deltaThetaDeg)
    self.maxDeltaTheta = math.pi
    self.originalDeltaThetaGoal = self.deltaThetaGoal
    self.analyticSolverEnabled = false
    self.ignoreValidityAtStart = false
end

function GraphPathfinder:getMotionPrimitives(turnRadius, allowReverse)
    return GraphPathfinder.GraphMotionPrimitives(self.range, self.graph)
end

--- Motion primitives to use with the graph pathfinder, providing the entries
--- to the next edges.
---@class GraphPathfinder.GraphMotionPrimitives : HybridAStar.MotionPrimitives
GraphPathfinder.GraphMotionPrimitives = CpObject(HybridAStar.MotionPrimitives)

---@param range number when an edge's exit is closer than range to another edge's entry, the
--- two edges are considered as connected (and thus can traverse from one to the other)
---@param graph Vector[] the graph as described in the file header
function GraphPathfinder.GraphMotionPrimitives:init(range, graph)
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
                table.insert(primitives, {x = exit.x, y = exit.y, d = edge:getLength() + distanceToEntry} )
            end
        end
    end
    return primitives
end

---@return State3D successor for the given primitive
function GraphPathfinder.GraphMotionPrimitives:createSuccessor(node, primitive, hitchLength)
    return State3D(primitive.x, primitive.y, 0, node.g, node, node.gear, node.steer,
            0, node.d + primitive.d)
end

