package.path = package.path .. ";../../test/?.lua;../../geometry/?.lua;../../courseGenerator/geometry/?.lua;../../courseGenerator/?.lua;../?.lua;../../?.lua;../../util/?.lua"
lu = require("luaunit")
require('mock-GiantsEngine')
require('mock-Courseplay')
require('CpObject')
require('CpUtil')
require('Logger')
require('BinaryHeap')
require('CpMathUtil')
require('Dubins')
require('ReedsShepp')
require('ReedsSheppSolver')
require('AnalyticSolution')
require('CourseGenerator')
require('WaypointAttributes')
require('Vector')
require('LineSegment')
require('State3D')
require('Vertex')
require('Polyline')
require('Polygon')
require('PathfinderUtil')
require('HybridAStar')
require('GraphPathfinder')

local GraphEdge = GraphPathfinder.GraphEdge
local TestConstraints = CpObject(PathfinderConstraintInterface)
local pathfinder, start, goal, done, path, goalNodeInvalid
local function printPath()
    for _, p in ipairs(path) do
        print(p)
    end
end

function testDirection()
    local graph = {
        GraphEdge(GraphEdge.UNIDIRECTIONAL,
                {
                    Vertex(100, 100),
                    Vertex(110, 100),
                    Vertex(120, 100)
                }),
        GraphEdge(
                GraphEdge.UNIDIRECTIONAL,
                {
                    Vertex(120, 105),
                    Vertex(110, 105),
                    Vertex(100, 105),
                }),
    }
    pathfinder = GraphPathfinder(math.huge, 500, 20, graph)
    start = State3D(90, 105, 0, 0)
    goal = State3D(130, 105, 0, 0)
    done, path, goalNodeInvalid = pathfinder:run(start, goal, 1, false, TestConstraints(), 0)
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 4)
    -- path contains the start node and all points of the edge it goes through
    lu.assertEquals(start, path[1])
    path[2]:assertAlmostEquals(Vector(100, 100))
    path[3]:assertAlmostEquals(Vector(110, 100))
    path[#path]:assertAlmostEquals(Vector(120, 100))
    start, goal = goal, start
    done, path, goalNodeInvalid = pathfinder:run(start, goal, 1, false, TestConstraints(), 0)
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 4)
    lu.assertEquals(start, path[1])
    path[2]:assertAlmostEquals(Vector(120, 105))
    path[3]:assertAlmostEquals(Vector(110, 105))
    path[#path]:assertAlmostEquals(Vector(100, 105))
end

function testBidirectional()
    local graph = {
        GraphEdge(GraphEdge.BIDIRECTIONAL,
                {
                    Vertex(120, 100),
                    Vertex(110, 100),
                    Vertex(100, 100),
                }),
        GraphEdge(
                GraphEdge.UNIDIRECTIONAL,
                {
                    Vertex(120, 105),
                    Vertex(110, 105),
                    Vertex(100, 105),
                }),
    }
    pathfinder = GraphPathfinder(math.huge, 500, 20, graph)
    start = State3D(90, 105, 0, 0)
    goal = State3D(130, 105, 0, 0)
    done, path, goalNodeInvalid = pathfinder:run(start, goal, 1, false, TestConstraints(), 0)
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 4)
    -- path contains the start node and all points of the edge it goes through
    lu.assertEquals(start, path[1])
    path[2]:assertAlmostEquals(Vector(100, 100))
    path[3]:assertAlmostEquals(Vector(110, 100))
    path[#path]:assertAlmostEquals(Vector(120, 100))
    start, goal = goal, start
    done, path, goalNodeInvalid = pathfinder:run(start, goal, 1, false, TestConstraints(), 0)
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 4)
    lu.assertEquals(start, path[1])
    -- TODO: here, it should have taken the other path, over y = 105, as it is slightly shorter since both start and
    -- goal are on y = 105, but since we reach the goal in a single step,
    -- it just goes with the first one it finds. This isn't the hill we want to die on, so for now,
    -- we will just accept this behavior.
    path[2]:assertAlmostEquals(Vector(120, 100))
    path[3]:assertAlmostEquals(Vector(110, 100))
    path[#path]:assertAlmostEquals(Vector(100, 100))
end

function testShorterPath()
    local graph = {
        GraphEdge(GraphEdge.UNIDIRECTIONAL,
                {
                    Vertex(100, 100),
                    Vertex(110, 100),
                    Vertex(120, 100)
                }),
        GraphEdge(
                GraphEdge.UNIDIRECTIONAL,
                {
                    Vertex(100, 105),
                    Vertex(110, 200),
                    Vertex(120, 105),
                }),
    }
    pathfinder = GraphPathfinder(math.huge, 500, 20, graph)
    start = State3D(90, 105, 0, 0)
    goal = State3D(130, 105, 0, 0)
    done, path, goalNodeInvalid = pathfinder:run(start, goal, 1, false, TestConstraints(), 0)
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 4)
    -- path contains the start node and all points of the edge it goes through
    lu.assertEquals(start, path[1])
    path[2]:assertAlmostEquals(Vector(100, 100))
    path[3]:assertAlmostEquals(Vector(110, 100))
    path[#path]:assertAlmostEquals(Vector(120, 100))
end

function testRange()
    local graph = {
        GraphEdge(GraphEdge.UNIDIRECTIONAL,
                {
                    Vertex(100, 100),
                    Vertex(110, 100),
                    Vertex(120, 100)
                }),
        GraphEdge(
                GraphEdge.UNIDIRECTIONAL,
                {
                    Vertex(120, 105),
                    Vertex(110, 105),
                    Vertex(100, 105),
                }),
        GraphEdge(GraphEdge.UNIDIRECTIONAL,
                {
                    Vertex(130, 100),
                    Vertex(140, 100),
                    Vertex(150, 100)
                }),
    }
    pathfinder = GraphPathfinder(math.huge, 500, 20, graph)
    start = State3D(90, 105, 0, 0)
    goal = State3D(150, 105, 0, 0)
    done, path, goalNodeInvalid = pathfinder:run(start, goal, 1, false, TestConstraints(), 0)
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 7)
    -- path contains the start node and all points of the edge it goes through
    lu.assertEquals(start, path[1])
    path[2]:assertAlmostEquals(Vector(100, 100))
    path[3]:assertAlmostEquals(Vector(110, 100))
    path[#path]:assertAlmostEquals(Vector(150, 100))
    pathfinder = GraphPathfinder(math.huge, 500, 10, graph)
    done, path, goalNodeInvalid = pathfinder:run(start, goal, 1, false, TestConstraints(), 0)
    lu.assertIsNil(path)
end

function testStartInTheMiddle()
    local graph = {
        GraphEdge(GraphEdge.BIDIRECTIONAL,
                {
                    Vertex(200, 100),
                    Vertex(150, 100),
                    Vertex(100, 100),
                }),
        GraphEdge(
                GraphEdge.UNIDIRECTIONAL,
                {
                    Vertex(200, 105),
                    Vertex(150, 105),
                    Vertex(100, 105),
                }),
    }
    pathfinder = GraphPathfinder(math.huge, 500, 20, graph)
    start = State3D(150, 95, 0, 0)
    goal = State3D(95, 95, 0, 0)
    done, path, goalNodeInvalid = pathfinder:run(start, goal, 1, false, TestConstraints(), 0)
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 3)
    -- path contains the start node and all points of the edge it goes through
    lu.assertEquals(start, path[1])
    path[2]:assertAlmostEquals(Vector(150, 100))
    path[3]:assertAlmostEquals(Vector(100, 100))
    graph = {
        GraphEdge(GraphEdge.BIDIRECTIONAL,
                {
                    Vertex(200, 100),
                    Vertex(150, 100),
                    Vertex(100, 100),
                }),
        GraphEdge(
                GraphEdge.UNIDIRECTIONAL,
                {
                    Vertex(200, 105),
                    Vertex(150, 105),
                    Vertex(100, 105),
                }),
    }
    pathfinder = GraphPathfinder(math.huge, 500, 10, graph)
    start, goal = goal, start
    done, path, goalNodeInvalid = pathfinder:run(start, goal, 1, false, TestConstraints(), 0)
    printPath()
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 3)
    lu.assertEquals(start, path[1])
    path[2]:assertAlmostEquals(Vector(100, 100))
    path[3]:assertAlmostEquals(Vector(150, 100))
end

os.exit(lu.LuaUnit.run())
