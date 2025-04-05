--[[
This file is part of Courseplay (https://github.com/Courseplay/Courseplay_FS25)
Copyright (C) 2023 Courseplay Dev Team
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

--[[

--------------------------------------------
--- Pathfinder controller
--------------------------------------------

PathfinderController for easy access to the pathfinder.
- Enables retrying with adjustable parameters compared to the last try, like fruit allowed and so..
- Handles the pathfinder coroutines if needed.
- One callback when the path finding finished.
	- Triggered if a valid path was found.
	- Gets triggered if the goal node is invalid.
	- Also gets triggered if no valid path was found and all retry attempts are used.
- Every time the path finding failed a callback gets triggered, if there are retry attempts left over.
	- Enabled the changing of the pathfinder context and restart with the new context.
- Callback if there is an obstacle around the vehicle so the pathfinding will inevitably fail, no matter
  how many time it is retried. This check ignores everything but collisions with vehicles or objects.
  No check if no callback registered.

Example implementations: 

function Strategy:startPathfindingToGoal()
	local context = PathfinderContext(self.vehicle)
	context:set(
		...
	)
	self.pathfinderController:registerListeners(self, self.onPathfindingFinished, self.onPathfindingFailed,
	    self.onPathfindingObstacleAtStart)

	local numRetries = 2
	self.pathfinderController:findPathToNode(context, ..., numRetries)

end

function Strategy:onPathfindingFinished(controller : PathfinderController, success : boolean,
	course : Course, goalNodeInvalid : boolean|nil)
	if success then
		// Path finding finished successfully
		...
	else 
		if goalNodeInvalid then 
			// Goal position can't be reached!
		else 
			// Num retries reached without path!
		end
	end
end

function Strategy:onPathfindingFailed(controller : PathfinderController, currentContext : PathfinderContext,
	wasLastRetry : boolean, currentRetryAttempt : number, trailerCollisionsOnly : boolean,
	fruitPenaltyNodePercent : number, offFieldPenaltyNodePercent : number)
	if currentRetryAttempt == 1 then 
		// try whatever has better chances:
		currentContext:ignoreFruit()
		self.pathfinderController:findPathToNode(currentContext, ...)
	else 
		// Something else ...
		self.pathfinderController:findPathToNode(currentContext, ...)
	end
end


function onPathfindingObstacleAtStart(controller, lastContext, maxDistance,
                                      trailerCollisionsOnly, fruitPenaltyNodePercent, offFieldPenaltyNodePercent)
    if trailerCollisionsOnly then
        self:debug('Pathfinding detected obstacle at start, trailer collisions only, retry with ignoring the trailer')
        lastContext:ignoreTrailerAtStartRange(1.5 * self.turningRadius)
        controller:retry(lastContext)
    else
        self:debug('Pathfinding detected obstacle at start, back up and retry')
        self:startMovingBackBeforePathfinding(controller, lastContext)
    end
end

]]

---@class DefaultFieldPathfinderControllerContext : PathfinderContext
DefaultFieldPathfinderControllerContext = CpObject(PathfinderContext)

function DefaultFieldPathfinderControllerContext:init(...)
    PathfinderContext.init(self, ...)
end

---@class PathfinderController
PathfinderController = CpObject()

PathfinderController.defaultNumRetries = 0
PathfinderController.SUCCESS_FOUND_VALID_PATH = 0
PathfinderController.ERROR_NO_PATH_FOUND = 1
PathfinderController.ERROR_INVALID_GOAL_NODE = 2
function PathfinderController:init(vehicle, turningRadius)
    self.vehicle = vehicle
    ---@type PathfinderInterface
    self.pathfinder = nil
    ---@type PathfinderContext
    self.currentContext = nil
    self.turningRadius = turningRadius or AIUtil.getTurningRadius(vehicle)
    self:reset()
end

function PathfinderController:__tostring()
    return string.format("PathfinderController(failCount=%d, numRetries=%s, active=%s)",
            self.failCount, self.numRetries, tostring(self.pathfinder ~= nil))
end

function PathfinderController:reset()
    self.numRetries = 0
    self.failCount = 0
    self.startedAt = 0
end

function PathfinderController:update(dt)
    if self:isActive() then
        --- Applies coroutine for path finding
        local result = self.pathfinder:resume()
        if result.done then
            self:onFinish(result)
        end
    end
end

function PathfinderController:getDriveData()
    local maxSpeed
    if self:isActive() then
        --- Pathfinder is active, so we stop the driver.
        maxSpeed = 0
    end
    return nil, nil, nil, maxSpeed
end

function PathfinderController:isActive()
    return self.pathfinder and self.pathfinder:isActive()
end

---@return PathfinderContext
function PathfinderController:getCurrentContext()
    return self.currentContext
end

--- Registers listeners for pathfinder success and failures.
--- TODO: Decide if multiple registered listeners are needed or not?
---@param object table
---@param successFunc function func(PathfinderController, success, Course, goalNodeInvalid)
---@param failedFunc function
---func(PathfinderController, last context, was last retry, retry attempt number, trailerCollisionsOnly, fruitPenaltyNodePercent, offFieldPenaltyNodePercent)
---@param obstacleAtStartFunc function|nil
--- func(PathfinderController, last context, maxDistance, trailerCollisionsOnly, fruitPenaltyNodePercent, offFieldPenaltyNodePercent),
--- called when the pathfinding failed within maxDistance (there is an obstacle ahead of the vehicle) so it can't even
--- start driving anywhere forward. In this case pathfinding makes no sense. No check if no callback is registered.
---
--- trailerCollisionsOnly will be set to true if there were no other collisions other then between the trailer and
--- some other obstacle.
---
--- fruitPenaltyNodePercent and offFieldPenaltyNodePercent can be used to determine the most likely reason the pathfinding
--- failed, returning the percent of nodes with fruit/off-field penalty (of total nodes searched)
function PathfinderController:registerListeners(object, successFunc, failedFunc, obstacleAtStartFunc)
    self.callbackObject = object
    self.callbackSuccessFunction = successFunc
    self.callbackFailedFunction = failedFunc
    self.callbackObstacleAtStartFunction = obstacleAtStartFunc
end

--- Pathfinder was started
---@param context PathfinderContext
function PathfinderController:start(context, numRetries, pathfinderCall)
    self.numRetries = numRetries or self.defaultNumRetries
    self:debug("Started pathfinding with context: %s, retries: %d.", tostring(context), self.numRetries)
    self.startedAt = g_time
    self.currentContext = context
    self.currentPathfinderCall = pathfinderCall

    local pathfinder, result = self.currentPathfinderCall()
    if result.done then
        self:onFinish(result)
    else
        self:debug("Continuing as coroutine...")
        self.pathfinder = pathfinder
    end
    return true
end

function PathfinderController:handleFailedPathfinding(result)
    if self.callbackObstacleAtStartFunction and not result.goalNodeInvalid and
            result.maxDistance < (self.currentContext._obstacleAtStartRange or (1.5 * self.turningRadius)) then
        -- pathfinder failed before getting further than the range in the context, or, if not given,
        -- further than the default of 1.5 radius, which is approximately the length of a quarter circle.
        -- we most likely have an obstacle right after start
        self:callCallback(self.callbackObstacleAtStartFunction, self.currentContext, result.maxDistance,
                result.trailerCollisionsOnly)
        return
    elseif self.callbackFailedFunction then
        --- Retry is allowed, so check if any tries are leftover
        if self.failCount < self.numRetries then
            self:debug("Failed with try %d of %d.", self.failCount, self.numRetries)
            local wasLastRetry = self.failCount == self.numRetries
            self.failCount = self.failCount + 1
            --- Let the callback decide what next: retry or give up
            self:callCallback(self.callbackFailedFunction,
                    self.currentContext, wasLastRetry, self.failCount, false,
                    result.fruitPenaltyNodePercent, result.offFieldPenaltyNodePercent)
            return
        elseif self.numRetries > 0 then
            self:debug("Max number of retries already reached!")
        end
    end
    -- TODO: make failed callback mandatory and call success only on real success?
    self:callCallback(self.callbackSuccessFunction, false, nil, result.goalNodeInvalid)
end

--- Path finding has finished
---@param result PathfinderResult
function PathfinderController:onFinish(result)
    self.pathfinder = nil
    self.timeTakenMs = g_time - self.startedAt
    local hasValidPath = result.path and #result.path > 2
    if hasValidPath then
        self:debug('Pathfinding done after %d ms, result: %s', self.timeTakenMs, result)
        self:callCallback(self.callbackSuccessFunction, true, self:getTemporaryCourseFromPath(result.path),
                result.goalNodeInvalid)
        self:reset()
    else
        self:error("No path found after %d ms, result: %s", self.timeTakenMs, result)
        self:handleFailedPathfinding(result)
    end
end

--- Retry the last pathfinder call with context. Will use the exact same call with the same target parameters,
--- but the context passed in here, so constraints like off-field penalty or max fruit percent can be relaxed on retry.
---@param context PathfinderContext
---@return boolean true if retry successfully started
function PathfinderController:retry(context)
    if self.currentPathfinderCall then
        self:debug("Retrying pathfinding with context: %s, retries: %d.", tostring(context), self.numRetries)
        self:start(context, self.numRetries, self.currentPathfinderCall)
        return true
    else
        self:error('Pathfinder has not been called before, can\'t retry')
        return false
    end
end

function PathfinderController:callCallback(callbackFunc, ...)
    if self.callbackObject then
        callbackFunc(self.callbackObject, self, ...)
    else
        callbackFunc(self, ...)
    end
end

--- Finds a path to given goal node
---@param context PathfinderContext
---@param goalNode number
---@param xOffset number
---@param zOffset number
---@param numRetries number|nil how many times to retry, default 0
---@return boolean Was path finding started?
function PathfinderController:findPathToNode(context, goalNode, xOffset, zOffset, numRetries)

    if not self.callbackSuccessFunction then
        self:error("No valid success callback was given!")
        return false
    end
    self:start(context, numRetries,
            function()
                return PathfinderUtil.startPathfindingFromVehicleToNode(
                        goalNode,
                        xOffset,
                        zOffset,
                        self.currentContext
                )
            end
    )
    return true
end

--- Finds a path to a waypoint of a course.
---@param context PathfinderContext
---@param course Course
---@param waypointIndex number
---@param xOffset number
---@param zOffset number
---@param numRetries number|nil how many times to retry, default 0
---@return boolean Was path finding started?
function PathfinderController:findPathToWaypoint(context, course, waypointIndex, xOffset, zOffset, numRetries)

    if not self.callbackSuccessFunction then
        self:error("No valid success callback was given!")
        return false
    end
    self:start(context, numRetries,
            function()
                return PathfinderUtil.startPathfindingFromVehicleToWaypoint(
                        course,
                        waypointIndex,
                        xOffset,
                        zOffset,
                        self.currentContext
                )
            end
    )
    return true
end

--- Finds a path to a waypoint of a course.
---@param context PathfinderContext
---@param goal State3D
---@param numRetries number|nil how many times to retry, default 0
---@return boolean Was path finding started?
function PathfinderController:findPathToGoal(context, goal, numRetries)

    if not self.callbackSuccessFunction then
        self:error("No valid success callback was given!")
        return false
    end
    self:start(context, numRetries,
            function()
                return PathfinderUtil.startPathfindingFromVehicleToGoal(goal, self.currentContext)
            end
    )
    return true
end

function PathfinderController:findPathOnStreet(context, goal, numRetries)
    if not self.callbackSuccessFunction then
        self:error("No valid success callback was given!")
        return false
    end
    self:start(context, numRetries,
            function()
                local pathfinder = GraphPathfinder(100, 1000, 25, g_graph:getGraphEdges())
                local start = PathfinderUtil.getVehiclePositionAsState3D(self.vehicle)
                -- no constraints
                return pathfinder, pathfinder:start(start, goal, AIUtil.getTurningRadius(self.vehicle), false, PathfinderConstraintInterface(), 0)
            end
    )
    return true
end

--- Generate an analytic path from the vehicle's current position to a goal position
--- Does not need a context
---@param goal State3D goal pose
---@param allowReverse boolean allow reverse driving
function PathfinderController:findAnalyticPathFromVehicleToGoal(goal, allowReverse)
    local path, _ = PathfinderUtil.findAnalyticPathFromStartToGoal(allowReverse and ReedsSheppSolver() or DubinsSolver(),
            PathfinderUtil.getVehiclePositionAsState3D(self.vehicle), goal, self.turningRadius)
    if path then
        return Course.createFromAnalyticPath(self.vehicle, path, true)
    else
        return nil
    end
end

function PathfinderController:getTemporaryCourseFromPath(path)
    return Course(self.vehicle, CpMathUtil.pointsToGameInPlace(path), true)
end

function PathfinderController:drawNodes()
    if self.pathfinder then
        PathfinderUtil.showNodes(self.pathfinder)
    end
end

--------------------------------------------
--- Debug functions
--------------------------------------------

function PathfinderController:debugStr(str, ...)
    return "Pathfinder controller: " .. str, ...
end

function PathfinderController:debug(...)
    CpUtil.debugVehicle(CpDebug.DBG_PATHFINDER, self.vehicle, self:debugStr(...))
end

function PathfinderController:info(...)
    CpUtil.infoVehicle(self.vehicle, self:debugStr(...))
end

function PathfinderController:error(...)
    self:info(...)
end