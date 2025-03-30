--- A pathfinder combining the (slow) hybrid A * and the (fast) regular A * star.
--- Near the start and the goal the hybrid A * is used to ensure the generated path is drivable (direction changes
--- always obey the turn radius), but use the A * between the two.
--- We'll run 3 pathfindings: one A * between start and goal (phase 1), then trim the ends of the result in hybridRange
--- Now run a hybrid A * from the start to the beginning of the trimmed A * path (phase 2), then another hybrid A * from the
--- end of the trimmed A * to the goal (phase 3).
HybridAStarWithAStarInTheMiddle = CpObject(PathfinderInterface)

---@param yieldAfter number coroutine yield after so many iterations (number of iterations in one update loop)
---@param mustBeAccurate boolean must be accurately find the goal position/angle (optional)
---@param analyticSolver AnalyticSolver the analytic solver the use (optional)
function HybridAStarWithAStarInTheMiddle:init(vehicle, yieldAfter, maxIterations, mustBeAccurate, analyticSolver)
    -- path generation phases
    self.vehicle = vehicle
    self.START_TO_MIDDLE = 1
    self.ASTAR = 2
    self.MIDDLE_TO_END = 3
    self.ALL_HYBRID = 4 -- start and goal close enough, we only need a single phase with hybrid
    self.hybridRange = 20 -- default range around start/goal to use hybrid A *
    self.yieldAfter = yieldAfter or 100
    self.maxIterations = maxIterations
    -- the only reason we have a separate instance for start and end is to be able to draw the nodes after
    -- the pathfinding is done for debug purposes
    self.startHybridAStarPathfinder = HybridAStar(vehicle, self.yieldAfter, maxIterations, mustBeAccurate)
    self.aStarPathfinder = self:getAStar()
    self.endHybridAStarPathfinder = HybridAStar(vehicle, self.yieldAfter, maxIterations, mustBeAccurate)
    self.analyticSolver = analyticSolver
end

function HybridAStarWithAStarInTheMiddle:getAStar()
    return AStar(self.vehicle, self.yieldAfter, self.maxIterations)
end

---@param start State3D start node
---@param goal State3D goal node
---@param turnRadius number
---@param allowReverse boolean allow reverse driving
---@param constraints PathfinderConstraintInterface constraints (validity, penalty) for the pathfinder
--- must have the following functions defined:
---   getNodePenalty() function get penalty for a node, see getNodePenalty()
---   isValidNode()) function function to check if a node should even be considered
---   isValidAnalyticSolutionNode()) function function to check if a node of an analytic solution should even be considered.
---                              when we search for a valid analytic solution we use this instead of isValidNode()
---@param hitchLength number hitch length of a trailer (length between hitch on the towing vehicle and the
--- rear axle of the trailer), can be nil
---@return PathfinderResult
function HybridAStarWithAStarInTheMiddle:start(start, goal, turnRadius, allowReverse, constraints, hitchLength)
    self.startNode, self.goalNode = State3D.copy(start), State3D.copy(goal)
    self.originalStartNode = State3D.copy(self.startNode)
    self.turnRadius, self.allowReverse, self.hitchLength = turnRadius, allowReverse, hitchLength
    self.hybridRange = self.turnRadius * 4
    self.constraints = constraints
    self.hybridRange = self.hybridRange and self.hybridRange or turnRadius * 3
    -- how far is start/goal apart?
    self.startNode:updateH(self.goalNode, turnRadius)
    self.phase = self.ASTAR
    self:debug('Finding fast A* path between start and goal...')
    self.coroutine = coursePlayCoroutine.create(self.aStarPathfinder.run)
    self.currentPathfinder = self.aStarPathfinder
    -- strict mode for the middle part, stay close to the field, for future improvements, disabled for now
    -- self.constraints:setStrictMode()
    return self:resume(self.startNode, self.goalNode, turnRadius, false, constraints, hitchLength)
end

-- distance between start and goal is relatively short, one phase hybrid A* all the way
---@return PathfinderResult
function HybridAStarWithAStarInTheMiddle:findHybridStartToEnd()
    self.phase = self.ALL_HYBRID
    self:debug('Goal is closer than %d, use one phase pathfinding only', self.hybridRange * 3)
    self.coroutine = coursePlayCoroutine.create(self.startHybridAStarPathfinder.run)
    self.currentPathfinder = self.startHybridAStarPathfinder
    return self:resume(self.startNode, self.goalNode, self.turnRadius, self.allowReverse, self.constraints, self.hitchLength)
end

-- start and goal far away, this is the hybrid A* from start to the middle section
---@return PathfinderResult
function HybridAStarWithAStarInTheMiddle:findPathFromStartToMiddle()
    self:debug('Finding path between start and middle section...')
    self.phase = self.START_TO_MIDDLE
    -- generate a hybrid part from the start to the middle section's start
    self.coroutine = coursePlayCoroutine.create(self.startHybridAStarPathfinder.run)
    self.currentPathfinder = self.startHybridAStarPathfinder
    local goal = State3D(self.middlePath[1].x, self.middlePath[1].y, (self.middlePath[2] - self.middlePath[1]):heading())
    return self:resume(self.startNode, goal, self.turnRadius, self.allowReverse, self.constraints, self.hitchLength)
end

-- start and goal far away, this is the hybrid A* from the middle section to the goal
---@return PathfinderResult
function HybridAStarWithAStarInTheMiddle:findPathFromMiddleToEnd()
    -- generate middle to end
    self.phase = self.MIDDLE_TO_END
    self:debug('Finding path between middle section and goal (allow reverse %s)...', tostring(self.allowReverse))
    self.coroutine = coursePlayCoroutine.create(self.endHybridAStarPathfinder.run)
    self.currentPathfinder = self.endHybridAStarPathfinder
    return self:resume(self.middleToEndStart, self.goalNode, self.turnRadius, self.allowReverse, self.constraints, self.hitchLength)
end

--- The resume() of this pathfinder is more complicated as it handles essentially three separate pathfinding runs
---@return PathfinderResult
function HybridAStarWithAStarInTheMiddle:resume(...)
    local ok, result = coursePlayCoroutine.resume(self.coroutine, self.currentPathfinder, ...)
    if not ok then
        print(result.done)
        printCallstack()
        self:debug('Pathfinding failed')
        self.coroutine = nil
        return PathfinderResult(true, nil, result.goalNodeInvalid, self.currentPathfinder:getHighestDistance(),
                self.constraints)
    end
    if result.done then
        self.coroutine = nil
        if self.phase == self.ALL_HYBRID then
            if result.path then
                -- start and goal near, just one phase, all hybrid, we are done
                return PathfinderResult(true, result.path)
            else
                self:debug('all hybrid: no path found')
                return PathfinderResult(true, nil, result.goalNodeInvalid, self.currentPathfinder:getHighestDistance(),
                        self.constraints)
            end
        elseif self.phase == self.ASTAR then
            self.constraints:resetStrictMode()
            if not result.path then
                self:debug('fast A*: no path found')
                return PathfinderResult(true, nil, result.goalNodeInvalid, self.currentPathfinder:getHighestDistance(),
                        self.constraints)
            end
            CourseGenerator.addDebugPolyline(Polyline(result.path), {1, 0, 0})
            local lMiddlePath = HybridAStar.length(result.path)
            self:debug('Direct path is %d m', lMiddlePath)
            -- do we even need to use the normal A star or the nodes are close enough that the hybrid A star will be fast enough?
            if lMiddlePath < self.hybridRange * 2 then
                return self:findHybridStartToEnd()
            end
            -- middle part ready, now trim start and end to make room for the hybrid parts
            self.middlePath = result.path
            HybridAStar.shortenStart(self.middlePath, self.hybridRange)
            HybridAStar.shortenEnd(self.middlePath, self.hybridRange)
            if #self.middlePath < 2 then
                return PathfinderResult(true, nil, result.goalNodeInvalid, self.currentPathfinder:getHighestDistance(),
                        self.constraints)
            end
            State3D.smooth(self.middlePath)
            State3D.setAllHeadings(self.middlePath)
            State3D.calculateTrailerHeadings(self.middlePath, self.hitchLength, true)
            return self:findPathFromStartToMiddle()
        elseif self.phase == self.START_TO_MIDDLE then
            if result.path then
                CourseGenerator.addDebugPolyline(Polyline(result.path), {0, 1, 0})
                -- start and middle sections ready, continue with the piece from the middle to the end
                self.path = result.path
                -- create start point at the last waypoint of middlePath before shortening
                self.middleToEndStart = State3D.copy(self.middlePath[#self.middlePath])
                -- now shorten both ends of middlePath to avoid short fwd/reverse sections due to overlaps (as the
                -- pathfinding may end anywhere within deltaPosGoal
                HybridAStar.shortenStart(self.middlePath, self.startHybridAStarPathfinder.deltaPosGoal * 2)
                HybridAStar.shortenEnd(self.middlePath, self.startHybridAStarPathfinder.deltaPosGoal * 2)
                -- append middle to start
                for i = 1, #self.middlePath do
                    table.insert(self.path, self.middlePath[i])
                end
                return self:findPathFromMiddleToEnd()
            else
                self:debug('start to middle: no path found')
                return PathfinderResult(true, nil, result.goalNodeInvalid, self.currentPathfinder:getHighestDistance(),
                        self.constraints)
            end
        elseif self.phase == self.MIDDLE_TO_END then
            if result.path then
                CourseGenerator.addDebugPolyline(Polyline(result.path), {0, 0, 1})
                -- last piece is ready, this was generated from the goal point to the end of the middle section so
                -- first remove the last point of the middle section to make the transition smoother
                -- and then add the last section in reverse order
                -- also, for reasons we don't fully understand, this section may have a direction change at the last waypoint,
                -- so we just ignore the last one
                for i = 1, #result.path do
                    table.insert(self.path, result.path[i])
                end
                State3D.smooth(self.path)
                self.constraints:showStatistics()
                return PathfinderResult(true, self.path)
            else
                self:debug('middle to end: no path found')
                return PathfinderResult(true, nil, result.goalNodeInvalid, self.currentPathfinder:getHighestDistance(),
                        self.constraints)
            end
        end
    end
    return PathfinderResult(false)
end

function HybridAStarWithAStarInTheMiddle:nodeIterator()
    local startIt = self.startHybridAStarPathfinder:nodeIterator()
    local middleIt = self.aStarPathfinder:nodeIterator()
    local endIt = self.endHybridAStarPathfinder:nodeIterator()
    return function()
        local node, lowestCost, highestCost = startIt()
        if node then
            return node, lowestCost, highestCost
        end
        node, lowestCost, highestCost = middleIt()
        if node then
            return node, lowestCost, highestCost
        end
        return endIt()
    end
end

function HybridAStarWithAStarInTheMiddle:nodeIteratorStart()
    return self.startHybridAStarPathfinder:nodeIterator()
end

function HybridAStarWithAStarInTheMiddle:nodeIteratorMiddle()
    return self.aStarPathfinder:nodeIterator()
end

function HybridAStarWithAStarInTheMiddle:nodeIteratorEnd()
    return self.endHybridAStarPathfinder:nodeIterator()
end


--- Dummy A* pathfinder implementation, does not calculate a path, just returns a pre-calculated path passed in
--- to its constructor.
---@see HybridAStarWithPathInTheMiddle
---@class DummyAStar : HybridAStar
DummyAStar = CpObject(HybridAStar)

---@param path State3D[] collection of nodes defining the configuration space
function DummyAStar:init(vehicle, path)
    self.path = path
    self.vehicle = vehicle
end

function DummyAStar:run()
    return true, self.path
end

--- Similar to HybridAStarWithAStarInTheMiddle, but the middle section is not calculated using the A*, instead
--- it is passed in to to constructor, already created by the caller.
--- This is used to find a path on the headland to the next row. The headland section is calculated by the caller
--- based on the vehicle's course, HybridAStarWithPathInTheMiddle only finds the path from the vehicle's position
--- to the headland and from the headland to the start of the next row.
HybridAStarWithPathInTheMiddle = CpObject(HybridAStarWithAStarInTheMiddle)

---@param yieldAfter number coroutine yield after so many iterations (number of iterations in one update loop)
---@param path State3D[] path to use in the middle part
---@param mustBeAccurate boolean must be accurately find the goal position/angle (optional)
---@param analyticSolver AnalyticSolver the analytic solver the use (optional)
function HybridAStarWithPathInTheMiddle:init(vehicle, yieldAfter, path, mustBeAccurate, analyticSolver)
    self.vehicle = vehicle
    self.path = path
    HybridAStarWithAStarInTheMiddle.init(self, vehicle, yieldAfter, 10000, mustBeAccurate, analyticSolver)
end

function HybridAStarWithPathInTheMiddle:start(...)
    self:debug('Start pathfinding on headland, hybrid A* range is %.1f, %d points on headland', self.hybridRange, #self.path)
    return HybridAStarWithAStarInTheMiddle.start(self, ...)
end

function HybridAStarWithPathInTheMiddle:getAStar()
    return DummyAStar(self.vehicle, self.path)
end
