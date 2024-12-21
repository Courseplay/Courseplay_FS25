--[[
This file is part of Courseplay (https://github.com/Courseplay/Courseplay_FS25)
Copyright (C) 2024 Courseplay Dev Team

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

---

Pathfinding is controlled by the constraints (validity and penalty) below. The pathfinder will call these functions
for each node to determine their validity and penalty.

A node (also called a pose) has a position and a heading, as we don't just want to get to position x, z but
we also need to arrive in a given direction.

Validity

A node is always invalid if it collides with an obstacle (tree, pole, other vehicle). Such nodes are ignored by
the pathfinder. You can mark other nodes invalid too, for example nodes not on the field if we need to keep the
vehicle on the field, but that's usually better handled with a penalty.

The pathfinder can use two separate functions to determine a node's validity, one for the hybrid A* nodes and
a different one for the analytic solutions (Dubins or Reeds-Shepp)

Penalty

Valid nodes can also be prioritized by a penalty, like when in the fruit or off the field. The penalty increases
the cost of a path and the pathfinder will likely avoid nodes with a higher penalty. With this we can keep the path
out of the fruit or on the field.

Context

Both the validity and penalty functions use a context to fine tune their behavior. The context can be set up before
starting the pathfinding according to the caller's preferences through a PathfinderContext.

Vehicle

The constraints also calculate the vehicle data describing the vehicle geometry.

]]--

---@class PathfinderConstraints : PathfinderConstraintInterface
PathfinderConstraints = CpObject(PathfinderConstraintInterface)

---@param context PathfinderContext
function PathfinderConstraints:init(context)
    self.vehicleData = PathfinderUtil.VehicleData(context._vehicle, true, 0.25)
    self.trailerHitchLength = AIUtil.getTowBarLength(context._vehicle) or 3
    self.turnRadius = AIUtil.getTurningRadius(context._vehicle) or 10
    self.objectsToIgnore = context._objectsToIgnore or {}
    self.vehiclesToIgnore = context._vehiclesToIgnore or {}

    self.maxFruitPercent = context._maxFruitPercent
    self.offFieldPenalty = context._offFieldPenalty
    self.fieldNum = context._useFieldNum
    self.areaToAvoid = context._areaToAvoid
    self.areaToIgnoreFruit = context._areaToIgnoreFruit
    self.areaToIgnoreOffFieldPenalty = context._areaToIgnoreOffFieldPenalty
    self.ignoreFruitHeaps = context._ignoreFruitHeaps
    self.preferredPath = context._preferredPath
    self.preferredPathAffinitySquared = PathfinderContext.preferredPathAffinity * PathfinderContext.preferredPathAffinity
    self.ignoreTrailerAtStartRange = context._ignoreTrailerAtStartRange or 0
    self.initialMaxFruitPercent = self.maxFruitPercent
    self.initialOffFieldPenalty = self.offFieldPenalty
    self.strictMode = false
    self:resetCounts()
    local areaToAvoidText = self.areaToAvoid and
            string.format('are to avoid %.1f x %.1f m', self.areaToAvoid.length, self.areaToAvoid.width) or 'none'
    self:debug('Pathfinder constraints: off field penalty %.1f, max fruit percent: %.1f, field number %d, %s, ignore fruit %s, ignore off-field penalty %s',
            self.offFieldPenalty, self.maxFruitPercent, self.fieldNum, areaToAvoidText,
            self.areaToIgnoreFruit or 'none', self.areaToIgnoreOffFieldPenalty or 'none')
end

function PathfinderConstraints:resetCounts()
    self.totalNodeCount = 0
    self.fruitPenaltyNodeCount = 0
    self.offFieldPenaltyNodeCount = 0
    self.notOwnedFieldPenaltyNodeCount = 0
    self.collisionNodeCount = 0
    self.trailerCollisionNodeCount = 0
    self.areaToAvoidPenaltyCount = 0
    self.preferredPathPenaltyCount = 0
end

--- Calculate penalty for this node. The penalty will be added to the cost of the node. This allows for
--- obstacle avoidance or forcing the search to remain in certain areas.
---@param node State3D
function PathfinderConstraints:getNodePenalty(node)
    local penalty = 0
    -- not on any field
    local offFieldPenalty = self.offFieldPenalty
    local offField = not CpFieldUtil.isOnField(node.x, -node.y)
    if not offField then
        -- we are on a field
        if not PathfinderUtil.isWorldPositionOwned(node.x, -node.y) then
            -- but we do not own this field
            if not g_missionManager:getMissionAtWorldPosition(node.x, -node.y) then
                -- the field we are on is not ours and not a mission field, more penalty!
                offField = true
                offFieldPenalty = self.offFieldPenalty * 1.2
                self.notOwnedFieldPenaltyNodeCount = self.notOwnedFieldPenaltyNodeCount + 1
            end
        end
    end
    if offField and (self.areaToIgnoreOffFieldPenalty == nil or (self.areaToIgnoreOffFieldPenalty ~= nil and
            not self.areaToIgnoreOffFieldPenalty:contains(node.x, -node.y))) then
        penalty = penalty + offFieldPenalty
        self.offFieldPenaltyNodeCount = self.offFieldPenaltyNodeCount + 1
        node.offField = true
    end
    if not offField then
        local hasFruit, fruitValue = PathfinderUtil.hasFruit(node.x, -node.y, 4, 4, self.areaToIgnoreFruit)
        if hasFruit and fruitValue > self.maxFruitPercent then
            penalty = penalty + fruitValue / 2
            self.fruitPenaltyNodeCount = self.fruitPenaltyNodeCount + 1
        end
    end
    if self.areaToAvoid and self.areaToAvoid:contains(node.x, -node.y) then
        penalty = penalty + PathfinderUtil.defaultAreaToAvoidPenalty
        self.areaToAvoidPenaltyCount = self.areaToAvoidPenaltyCount + 1
    end
    penalty = penalty + self:calculatePreferredPathPenalty(node)
    self.totalNodeCount = self.totalNodeCount + 1
    return penalty
end

--- Calculate penalty for this node based on the preferred path. The penalty will be negative to
--- encourage the pathfinder to use the preferred path.
---@param node State3D
function PathfinderConstraints:calculatePreferredPathPenalty(node)
    if self.preferredPath == nil then
        return 0
    end
    local minDistanceSquared = math.huge
    for _, waypoint in ipairs(self.preferredPath) do
        local dx = node.x - waypoint.x
        local dz = -node.y - waypoint.z
        -- if any point of the preferred path is outside the affinity limit meters of the node, we add penalty
        local distanceSquared = dx * dx + dz * dz
        if distanceSquared < minDistanceSquared then
            minDistanceSquared = distanceSquared
        end
    end
    if minDistanceSquared > self.preferredPathAffinitySquared then
        self.preferredPathPenaltyCount = self.preferredPathPenaltyCount + 1
        return 4
    else
        return 0
    end
    return minDistanceSquared
end

--- When the pathfinder tries an analytic solution for the entire path from start to goal, we can't use node penalties
--- to find the optimum path, avoiding fruit. Instead, we just check for collisions with vehicles and objects as
--- usual and also mark anything overlapping fruit as invalid. This way a path will only be considered if it is not
--- in the fruit.
--- However, we are more relaxed here and allow the double amount of fruit as being too restrictive here means
--- that analytic paths are almost always invalid when they go near the fruit. Since analytic paths are only at the
--- beginning at the end of the course and mostly curves, it is no problem getting closer to the fruit than otherwise
function PathfinderConstraints:isValidAnalyticSolutionNode(node, log)
    local hasFruit, fruitValue = PathfinderUtil.hasFruit(node.x, -node.y, 3, 3, self.areaToIgnoreFruit)
    local analyticLimit = self.maxFruitPercent * 2
    if hasFruit and fruitValue > analyticLimit then
        if log then
            self:debug('isValidAnalyticSolutionNode: fruitValue %.1f, max %.1f @ %.1f, %.1f',
                    fruitValue, analyticLimit, node.x, -node.y)
        end
        return false
    end
    -- off field nodes are always valid (they have a penalty) as we may need to make bigger loops to
    -- align properly with our target and don't want to restrict ourselves too much
    return self:isValidNode(node, false, true)
end

-- A helper node to calculate world coordinates
local function ensureHelperNode()
    if not PathfinderUtil.helperNode then
        PathfinderUtil.helperNode = CpUtil.createNode('pathfinderHelper', 0, 0, 0)
    end
end

--- Check if node is valid: would we collide with another vehicle or shape here?
---@param node State3D
---@param ignoreTrailer boolean don't check the trailer
---@param offFieldValid boolean consider nodes well off the field valid even in strict mode
function PathfinderConstraints:isValidNode(node, ignoreTrailer, offFieldValid)
    if not offFieldValid and self.strictMode then
        if not CpFieldUtil.isOnField(node.x, -node.y) then
            return false
        end
    end
    ensureHelperNode()
    PathfinderUtil.setWorldPositionAndRotationOnTerrain(PathfinderUtil.helperNode,
            node.x, -node.y, CpMathUtil.angleToGame(node.t), 0.5)

    -- for debug purposes only, store validity info on node
    node.collidingShapes = PathfinderUtil.collisionDetector:findCollidingShapes(
            PathfinderUtil.helperNode, self.vehicleData, self.vehiclesToIgnore, self.objectsToIgnore, self.ignoreFruitHeaps)
    ignoreTrailer = ignoreTrailer or node.d < self.ignoreTrailerAtStartRange
    if self.vehicleData.trailer and not ignoreTrailer then
        -- now check the trailer or towed implement
        -- move the node to the rear of the vehicle (where approximately the trailer is attached)
        local x, y, z = localToWorld(PathfinderUtil.helperNode, 0, 0, self.vehicleData.trailerHitchOffset)

        PathfinderUtil.setWorldPositionAndRotationOnTerrain(PathfinderUtil.helperNode, x, z,
                CpMathUtil.angleToGame(node.tTrailer), 0.5)

        node.collidingShapes = node.collidingShapes + PathfinderUtil.collisionDetector:findCollidingShapes(
                PathfinderUtil.helperNode, self.vehicleData.trailerRectangle, self.vehiclesToIgnore,
                self.objectsToIgnore, self.ignoreFruitHeaps)
        if node.collidingShapes > 0 then
            self.trailerCollisionNodeCount = self.trailerCollisionNodeCount + 1
        end
    end
    local isValid = node.collidingShapes == 0
    if not isValid then
        self.collisionNodeCount = self.collisionNodeCount + 1
    end
    return isValid
end

--- In strict mode there is no off field penalty, anything far enough from the field is just invalid.
--- This is to reduce the number of nodes to expand for the A* part of the algorithm to improve performance.
function PathfinderConstraints:setStrictMode()
    self.strictMode = true
end

function PathfinderConstraints:resetStrictMode()
    self.strictMode = false
end

function PathfinderConstraints:showStatistics()
    self:debug('Nodes: %d, Penalties: fruit: %d, off-field: %d, not owned field: %d, collisions: %d, trailer collisions: %d, area to avoid: %d, preferred path: %d',
            self.totalNodeCount, self.fruitPenaltyNodeCount, self.offFieldPenaltyNodeCount, self.notOwnedFieldPenaltyNodeCount,
            self.collisionNodeCount, self.trailerCollisionNodeCount, self.areaToAvoidPenaltyCount, self.preferredPathPenaltyCount)
    self:debug('  max fruit %.1f %%, off-field penalty: %.1f',
            self.maxFruitPercent, self.offFieldPenalty)
end

function PathfinderConstraints:trailerCollisionsOnly()
    return self.trailerCollisionNodeCount > 0 and self.collisionNodeCount == self.trailerCollisionNodeCount
end

function PathfinderConstraints:getFruitPenaltyNodePercent()
    return self.totalNodeCount > 0 and (self.fruitPenaltyNodeCount / self.totalNodeCount) or 0
end

function PathfinderConstraints:getOffFieldPenaltyNodePercent()
    return self.totalNodeCount > 0 and (self.offFieldPenaltyNodeCount / self.totalNodeCount) or 0
end

function PathfinderConstraints:debug(...)
    self.vehicleData:debug(...)
end
