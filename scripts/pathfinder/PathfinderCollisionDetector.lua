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
]]

------------------------------------------------------------------------------------------------------------------------
-- A collision detector used by the pathfinder
---------------------------------------------------------------------------------------------------------------------------
---@class PathfinderCollisionDetector
PathfinderCollisionDetector = CpObject()

--- Nodes of a trigger for example, that will be ignored as collision.
PathfinderCollisionDetector.NODES_TO_IGNORE = {}

function PathfinderCollisionDetector:init(vehicle, vehiclesToIgnore, objectsToIgnore, ignoreFruitHeaps, collisionMask)
    self.logger = Logger('PathfinderCollisionDetector', Logger.level.debug, CpDebug.DBG_PATHFINDER)
    self.vehicle = vehicle
    self.vehiclesToIgnore = vehiclesToIgnore or {}
    self.objectsToIgnore = objectsToIgnore or {}
    self.ignoreFruitHeaps = ignoreFruitHeaps
    self.collidingShapes = 0
    self.collisionMask = collisionMask or CpUtil.getDefaultCollisionFlags()
end

--- Adds a node which collision will be ignored global for every pathfinder.
---@param node number
function PathfinderCollisionDetector.addNodeToIgnore(node)
    PathfinderCollisionDetector.NODES_TO_IGNORE[node] = true
end

--- Removes a node, so it's collision is no longer applied.
---@param node number
function PathfinderCollisionDetector.removeNodeToIgnore(node)
    PathfinderCollisionDetector.NODES_TO_IGNORE[node] = nil
end

function PathfinderCollisionDetector:_overlapBoxCallback(transformId)
    if PathfinderCollisionDetector.NODES_TO_IGNORE[transformId] then
        --- Global node, that needs to be ignored
        return
    end

    local collidingObject = g_currentMission.nodeToObject[transformId]
    if collidingObject and PathfinderUtil.elementOf(self.objectsToIgnore, collidingObject) then
        -- an object we want to ignore
        return
    end
    local text, rootVehicle
    if collidingObject then
        if collidingObject.getRootVehicle then
            rootVehicle = collidingObject:getRootVehicle()
        elseif collidingObject:isa(Bale) and collidingObject.mountObject then
            rootVehicle = collidingObject.mountObject:getRootVehicle()
        end
        if rootVehicle == self.vehicle:getRootVehicle() or
                PathfinderUtil.elementOf(self.vehiclesToIgnore, rootVehicle) then
            -- just bumped into myself or a vehicle we want to ignore
            return
        end
        if collidingObject:isa(Bale) then
            text = string.format('bale %d', collidingObject.id)
        else
            text = CpUtil.getName(collidingObject)
        end
    end
    if getHasClassId(transformId, ClassIds.TERRAIN_TRANSFORM_GROUP) then

        local x, y, z = unpack(self.currentOverlapBoxPosition.pos)
        local dirX, dirZ = unpack(self.currentOverlapBoxPosition.direction)
        local size = self.currentOverlapBoxPosition.size
        --- Roughly checks the overlap box for any dropped fill type to the ground.
        --- TODO: DensityMapHeightUtil.getFillTypeAtArea() would be better.
        local fillType = DensityMapHeightUtil.getFillTypeAtLine(x, y, z, x + dirX * size, y, z + dirZ * size, size)
        if not self.ignoreFruitHeaps and fillType and fillType ~= FillType.UNKNOWN then
            text = string.format('terrain and fillType: %s.',
                    g_fillTypeManager:getFillTypeByIndex(fillType).title)
        else
            --- Ignore terrain hits, if no fillType is dropped to the ground was detected.
            return
        end
    end

    if text == nil then
        text = transformId .. ':'
        for key, classId in pairs(ClassIds) do
            if getHasClassId(transformId, classId) then
                text = text .. ' ' .. key
            end
        end
    end
    self.collidingShapesText = text
    self.collidingShapes = self.collidingShapes + 1
end

function PathfinderCollisionDetector:findCollidingShapes(node, vehicleToLog, overlapBoxParams)
    local xRot, yRot, zRot = getWorldRotation(node)
    local x, y, z = localToWorld(node, overlapBoxParams.xOffset, 1, overlapBoxParams.zOffset)
    local dirX, dirZ = MathUtil.getDirectionFromYRotation(yRot)
    --- Save these for the overlap box callback.
    self.currentOverlapBoxPosition = {
        pos = { x, y, z },
        direction = { dirX, dirZ },
        size = math.max(overlapBoxParams.width, overlapBoxParams.length)
    }
    self.collidingShapes = 0
    self.collidingShapesText = 'unknown'

    overlapBox(x, y + 0.2, z, xRot, yRot, zRot, overlapBoxParams.width, 1, overlapBoxParams.length, '_overlapBoxCallback',
            self, self.collisionMask, true, true, true, true)

    if true and self.collidingShapes > 0 then
        table.insert(PathfinderUtil.overlapBoxes,
                { x = x, y = y + 0.2, z = z, xRot = xRot, yRot = yRot, zRot = zRot, width = overlapBoxParams.width,
                  length = overlapBoxParams.length })
        self.logger:debug(self.vehicle,'my %s (%.1fx%.1f) is colliding with %s at x = %.1f, z = %.1f, yRot = %d',
                CpUtil.getName(vehicleToLog), 2 * overlapBoxParams.width, 2 * overlapBoxParams.length, self.collidingShapesText, x, z, math.deg(yRot))
    end

    return self.collidingShapes
end
