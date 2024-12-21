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
--- Pathfinder controller context
--------------------------------------------

PathfinderContext implements all pathfinder parameters.
        - Other Context Classes could be derived for commonly used contexts.
        - Only the attributesToDefaultValue table has to be changed in the derived class.

Example usage of the builder api:

local context = PathfinderContext():maxFruitPercent(100):useFieldNum(10):vehiclesToIgnore({vehicle})

]]

---@class PathfinderContext
---@field maxFruitPercent function
---@field offFieldPenalty function
---@field useFieldNum function
---@field areaToAvoid function
---@field allowReverse function
---@field vehiclesToIgnore function
---@field mustBeAccurate function
---@field areaToIgnoreFruit function
---@field areaToIgnoreOffFieldPenalty function
---@field ignoreFruitHeaps function
---@field maxIterations function
---@field obstacleAtStartRange function
---@field ignoreTrailerAtStartRange function
---@field _maxFruitPercent number
---@field _offFieldPenalty number
---@field _useFieldNum number
---@field _areaToAvoid PathfinderUtil.NodeArea|nil
---@field _allowReverse boolean
---@field _vehiclesToIgnore table[]|nil
---@field _objectsToIgnore table[]|nil
---@field _mustBeAccurate boolean
---@field _areaToIgnoreFruit PathfinderUtil.Area|nil
---@field _areaToIgnoreOffFieldPenalty PathfinderUtil.NodeArea|nil
---@field _ignoreFruitHeaps boolean
---@field _maxIterations number
---@field _obstacleAtStartRange number
---@field _ignoreTrailerAtStartRange number
PathfinderContext = CpObject()
PathfinderContext.defaultOffFieldPenalty = 7.5
PathfinderContext.preferredPathAffinity = 5
PathfinderContext.attributesToDefaultValue = {
    -- If an 4 x 4 m area around a pathfinder node has more than this fruit, a penalty of 0.5 * actual fruit
    -- percentage will be applied to that node.
    -- TODO: check if the fruitValue returned by FSDensityMapUtil.getFruitArea() really is a percentage
    ["maxFruitPercent"] = 50,
    -- This penalty is added to the cost of each step, which is about 12% of the turning radius when using
    -- the hybrid A* and 3 with the simple A*.
    -- Simple A* is used for long-range pathfinding, in that case we are willing to drive about 3 times longer
    -- to stay on the field. Hybrid A* is more restrictive, TODO: review if these should be balanced
    ["offFieldPenalty"] = PathfinderContext.defaultOffFieldPenalty,
    -- If useFieldNum > 0, fields that are not owned have a 20% greater penalty.
    ["useFieldNum"] = 0,
    -- Pathfinder nodes in this area have a prohibitive penalty (2000)
    ["areaToAvoid"] = CpObjectUtil.BUILDER_API_NIL,
    ["allowReverse"] = false,
    ["vehiclesToIgnore"] = {},
    ["objectsToIgnore"] = {},
    -- If false, as we reach the maximum iterations, we relax our criteria to reach the goal: allow for arriving at
    -- bigger angle differences, trading off accuracy for speed. This usually results in a direction at the goal
    -- being less then 30º off which in many cases isn't a problem.
    -- Otherwise, for example when a combine self unloading must accurately find the trailer, set this to true.
    ["mustBeAccurate"] = false,
    -- No fruit penalty in this area (e.g. when we know the goal is in fruit but want to avoid fruit all the way there)
    ["areaToIgnoreFruit"] = CpObjectUtil.BUILDER_API_NIL,
    -- A path [{x, z}, {x, z}, ...] that the pathfinder will try to follow. Nodes closer than
    -- PathfinderContext.preferredPathAffinity to the path will have a negative penalty
    ["preferredPath"] = CpObjectUtil.BUILDER_API_NIL,
    -- No off-field penalty in this area (for instance when need to approach another vehicle, such as a trailer
    -- to unload to, regardless of it is on the field or not, but we do want to have normal off-field penalty for
    -- the rest of the path
    ["areaToIgnoreOffFieldPenalty"] = CpObjectUtil.BUILDER_API_NIL,
    -- Tell the collision detector to ignore heaps of fruit on the ground.
    ["ignoreFruitHeaps"] = false,
    -- If the pathfinding fails without getting further than 1.5 * turning radius, the controller triggers
    -- the "obstacle at start" callback. This is to override that limit when needed.
    ["obstacleAtStartRange"] = CpObjectUtil.BUILDER_API_NIL,
    -- If true, ignore the trailer within so many meters (actual path length, not distance) of the start.
    -- This is useful when there's another vehicle close to the starting point, and the trailer (with the
    -- buffer area around it) often triggers a collision which, when the vehicle drives the path, isn't
    -- really a problem.
    ["ignoreTrailerAtStartRange"] = 0,
    -- Maximum number of iterations before the hybrid A* pathfinding gives up. The default works well
    -- for normal sized fields, on bigger maps with huge fields you may want to double or triple this
    ["maxIterations"] = HybridAStar.defaultMaxIterations
}

function PathfinderContext:init(vehicle)
    self._vehicle = vehicle
    CpObjectUtil.registerBuilderAPI(self, self.attributesToDefaultValue)
end

--- Disables the fruit avoidance
function PathfinderContext:ignoreFruit()
    self._maxFruitPercent = math.huge
    return self
end

--- Uses the field number of the vehicle to restrict path finding.
function PathfinderContext:useVehicleFieldNumber()
    self._useFieldNum = CpFieldUtil.getFieldNumUnderVehicle(self._vehicle)
    return self
end

function PathfinderContext:__tostring()
    local str = string.format('[ %s: ', CpUtil.getName(self._vehicle))
    str = self:attributesToString(str, PathfinderContext.attributesToDefaultValue, '_')
    str = str .. ']'
    return str
end