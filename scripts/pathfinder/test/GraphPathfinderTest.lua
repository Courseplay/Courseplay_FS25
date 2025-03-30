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
local pathfinder, start, goal, done, path

local function printPath()
    for _, p in ipairs(path) do
        print(Vector.__tostring(p))
    end
end

local function runPathfinder()
    local result = pathfinder:start(start, goal, 1, false, TestConstraints(), 0)
    while not result.done do
        result = pathfinder:resume()
    end
    return result.done, result.path
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
    done, path, _ = runPathfinder()
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 3)
    -- path contains all points of the edge it goes through
    path[1]:assertAlmostEquals(Vector(100, 100))
    path[2]:assertAlmostEquals(Vector(110, 100))
    path[#path]:assertAlmostEquals(Vector(120, 100))
    start, goal = goal, start
    done, path, _ = runPathfinder()
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 3)
    path[1]:assertAlmostEquals(Vector(120, 105))
    path[2]:assertAlmostEquals(Vector(110, 105))
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
    done, path, _ = runPathfinder()
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 3)
    -- path contains the start node and all points of the edge it goes through
    path[1]:assertAlmostEquals(Vector(100, 100))
    path[2]:assertAlmostEquals(Vector(110, 100))
    path[#path]:assertAlmostEquals(Vector(120, 100))
    start, goal = goal, start
    done, path, _ = runPathfinder()
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 3)
    -- TODO: here, it should have taken the other path, over y = 105, as it is slightly shorter since both start and
    -- goal are on y = 105, but since we reach the goal in a single step,
    -- it just goes with the first one it finds. This isn't the hill we want to die on, so for now,
    -- we will just accept this behavior.
    path[1]:assertAlmostEquals(Vector(120, 100))
    path[2]:assertAlmostEquals(Vector(110, 100))
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
    done, path, _ = runPathfinder()
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 3)
    path[1]:assertAlmostEquals(Vector(100, 100))
    path[2]:assertAlmostEquals(Vector(110, 100))
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
    done, path, _ = runPathfinder()
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 6)
    path[1]:assertAlmostEquals(Vector(100, 100))
    path[2]:assertAlmostEquals(Vector(110, 100))
    path[#path]:assertAlmostEquals(Vector(150, 100))
    pathfinder = GraphPathfinder(math.huge, 500, 9, graph)
    done, path, _ = runPathfinder()
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
    done, path, _ = runPathfinder()
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 2)
    path[1]:assertAlmostEquals(Vector(150, 100))
    path[2]:assertAlmostEquals(Vector(100, 100))
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
    done, path, _ = runPathfinder()
    printPath()
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 2)
    path[1]:assertAlmostEquals(Vector(100, 100))
    path[2]:assertAlmostEquals(Vector(150, 100))
end

function testTwoPointSegments()
    local graph = {
        GraphEdge(GraphEdge.UNIDIRECTIONAL,
                {
                    Vertex(100, 100),
                    Vertex(120, 100)
                }),
        GraphEdge(
                GraphEdge.UNIDIRECTIONAL,
                {
                    Vertex(120, 105),
                    Vertex(100, 105),
                }),
    }
    pathfinder = GraphPathfinder(math.huge, 500, 20, graph)
    start = State3D(90, 105, 0, 0)
    goal = State3D(130, 105, 0, 0)
    done, path, _ = runPathfinder()
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 2)
    path[1]:assertAlmostEquals(Vector(100, 100))
    path[#path]:assertAlmostEquals(Vector(120, 100))
    start, goal = goal, start
    done, path, _ = runPathfinder()
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 2)
    path[1]:assertAlmostEquals(Vector(120, 105))
    path[#path]:assertAlmostEquals(Vector(100, 105))
end

function testEntryExit()
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
    -- range is 5 so goal is never within the range of start, that is in the testGoalWithinRange() function
    pathfinder = GraphPathfinder(math.huge, 500, 5, graph)
    -- start/goal far away
    start = State3D(0, 0, 0, 0)
    goal = State3D(130, 0, 0, 0)
    done, path, _ = runPathfinder()
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 3)
    -- path contains all points of the edge it goes through
    path[1]:assertAlmostEquals(Vector(100, 100))
    path[2]:assertAlmostEquals(Vector(110, 100))
    path[#path]:assertAlmostEquals(Vector(120, 100))
    -- start/goal far away
    start = State3D(130, 200, 0, 0)
    goal = State3D(0, 200, 0, 0)
    done, path, _ = runPathfinder()
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 3)
    -- path contains all points of the edge it goes through
    path[1]:assertAlmostEquals(Vector(120, 105))
    path[2]:assertAlmostEquals(Vector(110, 105))
    path[#path]:assertAlmostEquals(Vector(100, 105))
    -- start/goal far away, middle entry
    start = State3D(110, 0, 0, 0)
    goal = State3D(130, 0, 0, 0)
    done, path, _ = runPathfinder()
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 2)
    path[1]:assertAlmostEquals(Vector(110, 100))
    path[#path]:assertAlmostEquals(Vector(120, 100))
end

function testGoalWithinRange()

    local graph = {
        GraphEdge(GraphEdge.UNIDIRECTIONAL,
                {
                    Vertex(100, 100),
                    Vertex(120, 100)
                }),
    }
    pathfinder = GraphPathfinder(math.huge, 500, 21, graph)
    -- start/goal far away
    start = State3D(100, 100, 0, 0)
    goal = State3D(120, 100, 0, 0)
    print('******** single ******')
    done, path, _ = runPathfinder()
    lu.assertIsTrue(done)
    lu.assertEquals(#path, 2)
    -- path contains all points of the edge it goes through
    path[1]:assertAlmostEquals(Vector(100, 100))
    --path[2]:assertAlmostEquals(Vector(110, 100))
    path[#path]:assertAlmostEquals(Vector(120, 100))
end

os.exit(lu.LuaUnit.run())
