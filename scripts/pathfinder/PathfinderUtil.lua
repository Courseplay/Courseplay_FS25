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

PathfinderUtil = {}

PathfinderUtil.logger = Logger('PathfinderUtil')

PathfinderUtil.dubinsSolver = DubinsSolver()
PathfinderUtil.reedsSheppSolver = ReedsSheppSolver()

PathfinderUtil.defaultAreaToAvoidPenalty = 2000
PathfinderUtil.visualDebugLevel = 0
-- for troubleshooting
PathfinderUtil.overlapBoxes = {}

------------------------------------------------------------------------------------------------------------------------
---Size/turn radius all other information on the vehicle and its implements
------------------------------------------------------------------------------------------------------------------------
---@class PathfinderUtil.VehicleData
PathfinderUtil.VehicleData = CpObject()

--- VehicleData is used to perform a hierarchical collision detection. The vehicle's bounding box
--- includes all implements and checked first for collisions. If there is a hit, the individual parts
--- (vehicle and implements) are each checked for collision. This is to avoid false alarms in case of
--- non-rectangular shapes, like a combine with a wide header
--- If the vehicle has a trailer, it is handled separately from other implements to allow for the
--- pathfinding to consider the trailer's heading (which will be different from the vehicle's heading)
function PathfinderUtil.VehicleData:init(vehicle, withImplements, buffer)
    self.vehicle = vehicle
    self.rootVehicle = vehicle:getRootVehicle()
    self.name = vehicle.getName and vehicle:getName() or 'N/A'
    -- distance of the sides of a rectangle from the root node of the vehicle
    -- in other words, the X and Z offsets of the corners from the root node
    -- negative is to the rear and to the right
    -- this is the bounding box of the entire vehicle with all attached implements,
    -- except a towed trailer as that is calculated independently
    self.dFront, self.dRear, self.dLeft, self.dRight = 0, 0, 0, 0
    self.rectangles = {}
    self:calculateSizeOfObjectList(vehicle, { { object = vehicle } }, buffer, self.rectangles)
    -- we'll calculate the trailer's precise position an angle for the collision detection to not hit obstacles
    -- while turning. Get that object here, there may be more but we ignore that case.
    self.trailer = AIUtil.getFirstReversingImplementWithWheels(vehicle)
    if self.trailer then
        -- the trailer's heading is different than the vehicle's heading and will be calculated and
        -- checked for collision independently at each waypoint. Also, the trailer is rotated to its heading
        -- around the hitch (which we approximate as the front side of the size rectangle), not around the root node
        self.trailerRectangle = {
            name = self.trailer:getName(),
            vehicle = self.trailer,
            rootVehicle = self.trailer:getRootVehicle(),
            dFront = buffer or 0,
            dRear = -self.trailer.size.length - (buffer or 0),
            dLeft = AIUtil.getWidth(self.trailer) / 2 + (buffer or 0),
            dRight = -AIUtil.getWidth(self.trailer) / 2 - (buffer or 0)
        }
        local inputAttacherJoint = self.trailer:getActiveInputAttacherJoint()
        if inputAttacherJoint then
            local _, _, dz = localToLocal(inputAttacherJoint.node, AIUtil.getDirectionNode(vehicle), 0, 0, 0)
            self.trailerHitchOffset = dz
        else
            self.trailerHitchOffset = self.dRear
        end
        CpUtil.debugVehicle(CpDebug.DBG_PATHFINDER, vehicle, 'trailer for the pathfinding is %s, hitch offset is %.1f',
                self.trailer:getName(), self.trailerHitchOffset)
    end
    if withImplements then
        self:calculateSizeOfObjectList(vehicle, vehicle:getAttachedImplements(), buffer, self.rectangles)
    end
end

--- Calculate the relative coordinates of a rectangle's corners around a reference node, representing the implement
function PathfinderUtil.VehicleData:getRectangleForImplement(implement, referenceNode, buffer)

    local rootToReferenceNodeOffset = ImplementUtil.getDistanceToImplementNode(referenceNode, implement.object, implement.object.rootNode)

    -- default size, used by Giants to determine the drop area when buying something
    local rectangle = {
        dFront = rootToReferenceNodeOffset + implement.object.size.length / 2 + implement.object.size.lengthOffset + (buffer or 0),
        dRear = rootToReferenceNodeOffset - implement.object.size.length / 2 + implement.object.size.lengthOffset - (buffer or 0),
        dLeft = AIUtil.getWidth(implement.object) / 2,
        dRight = -AIUtil.getWidth(implement.object) / 2
    }
    -- now see if we have something better, then use that. Since any of the six markers may be missing, we
    -- check them one by one.
    if implement.object.getAIMarkers then
        -- otherwise try the AI markers (work area), this will be bigger than the vehicle's physical size, for example
        -- in case of sprayers
        local aiLeftMarker, aiRightMarker, aiBackMarker = implement.object:getAIMarkers()
        if aiLeftMarker and aiRightMarker then
            rectangle.dLeft, _, rectangle.dFront = localToLocal(aiLeftMarker, referenceNode, 0, 0, 0)
            rectangle.dRight, _, _ = localToLocal(aiRightMarker, referenceNode, 0, 0, 0)
            if aiBackMarker then
                _, _, rectangle.dRear = localToLocal(aiBackMarker, referenceNode, 0, 0, 0)
            end
        end
    end
    if implement.object.getAISizeMarkers then
        -- but the best case is if we have the AI size markers
        local aiSizeLeftMarker, aiSizeRightMarker, aiSizeBackMarker = implement.object:getAISizeMarkers()
        if aiSizeLeftMarker then
            rectangle.dLeft, _, rectangle.dFront = localToLocal(aiSizeLeftMarker, referenceNode, 0, 0, 0)
        end
        if aiSizeRightMarker then
            rectangle.dRight, _, _ = localToLocal(aiSizeRightMarker, referenceNode, 0, 0, 0)
        end
        if aiSizeBackMarker then
            _, _, rectangle.dRear = localToLocal(aiSizeBackMarker, referenceNode, 0, 0, 0)
        end
    end
    return rectangle
end

--- calculate the bounding box of all objects in the implement list. This is not a very good way to figure out how
--- big a vehicle is as the sizes of foldable implements seem to be in the folded state but should be ok for
--- now.
function PathfinderUtil.VehicleData:calculateSizeOfObjectList(vehicle, implements, buffer, rectangles)
    for _, implement in ipairs(implements) do
        --print(implement.object:getName())
        local referenceNode = AIUtil.getDirectionNode(vehicle) --vehicle.rootNode
        if implement.object ~= self.trailer then
            -- everything else is attached to the root vehicle and calculated as it was moving with it (having
            -- the same heading)
            local rectangle = self:getRectangleForImplement(implement, referenceNode, buffer)
            table.insert(rectangles, rectangle)
            self.dFront = math.max(self.dFront, rectangle.dFront)
            self.dRear = math.min(self.dRear, rectangle.dRear)
            self.dLeft = math.max(self.dLeft, rectangle.dLeft)
            self.dRight = math.min(self.dRight, rectangle.dRight)
        end
    end
    --CpUtil.debugVehicle(CpDebug.DBG_PATHFINDER, vehicle, 'Size: dFront %.1f, dRear %.1f, dLeft = %.1f, dRight = %.1f',
    --        self.dFront, self.dRear, self.dLeft, self.dRight)
end

function PathfinderUtil.VehicleData:debug(...)
    PathfinderUtil.debug(self.vehicle, ...)
end

------------------------------------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------------------------------------
--- Is this position on a field (any field)?
function PathfinderUtil.isPosOnField(x, y, z)
    if not y then
        _, y, _ = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z)
    end
    local densityBits = 0
    local bits = getDensityAtWorldPos(g_currentMission.terrainDetailId, x, y, z)
    densityBits = bitOR(densityBits, bits)
    return densityBits ~= 0
end

--- Is this node on a field (any field)?
---@param node table Giants engine node
function PathfinderUtil.isNodeOnField(node)
    local x, y, z = getWorldTranslation(node)
    return PathfinderUtil.isPosOnField(x, y, z)
end

--- Is the land at this position owned by me?
function PathfinderUtil.isWorldPositionOwned(posX, posZ)
    local farmland = g_farmlandManager:getFarmlandAtWorldPosition(posX, posZ)
    local missionAllowed = g_missionManager:getIsMissionWorkAllowed(g_currentMission.playerSystem:getLocalPlayer().farmId, posX, posZ, nil)
    return (farmland and farmland.isOwned) or missionAllowed
end

--- Calculate the four corners of a rectangle around a node (for example the area covered by a vehicle)
--- the data returned by this is the rectangle from the vehicle data translated and rotated to the node
function PathfinderUtil.getBoundingBoxInWorldCoordinates(node, vehicleData)
    local x, y, z
    local corners = {}
    x, y, z = localToWorld(node, vehicleData.dRight, 0, vehicleData.dRear)
    table.insert(corners, { x = x, y = y, z = z })
    x, y, z = localToWorld(node, vehicleData.dRight, 0, vehicleData.dFront)
    table.insert(corners, { x = x, y = y, z = z })
    x, y, z = localToWorld(node, vehicleData.dLeft, 0, vehicleData.dFront)
    table.insert(corners, { x = x, y = y, z = z })
    x, y, z = localToWorld(node, vehicleData.dLeft, 0, vehicleData.dRear)
    table.insert(corners, { x = x, y = y, z = z })
    x, y, z = localToWorld(node, 0, 0, 0)
    local center = { x = x, y = y, z = z }
    return { name = vehicleData.name, center = center, corners = corners }
end

function PathfinderUtil.elementOf(list, key)
    for _, element in ipairs(list or {}) do
        if element == key then
            return true
        end
    end
    return false
end

--- Place node on a world position, point it to the heading and set the rotation so the y axis is parallel
--- to the terrain normal vector. In other words, set the location and rotation of this node as if it was the
--- root node of a vehicle at that position, the vehicle's chassis parallel to the terrain
---@param node number
---@param x number
---@param z number
---@param heading number heading as y rotation
---@param yOffset number position offset above ground
function PathfinderUtil.setWorldPositionAndRotationOnTerrain(node, x, z, heading, yOffset)
    local xRot, yRot, zRot = PathfinderUtil.getNormalWorldRotation(x, z)
    local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z);

    setTranslation(node, x, y + yOffset, z)
    setRotation(node, xRot, 0, zRot)
    xRot, yRot, zRot = localRotationToWorld(node, 0, heading, 0)
    setRotation(node, xRot, yRot, zRot)
end

--- Get the world rotation of a node at x, z when the y axis is parallel to the normal vector at that position
--- (y axis is perpendicular to the terrain)
function PathfinderUtil.getNormalWorldRotation(x, z)
    local nx, ny, nz = getTerrainNormalAtWorldPos(g_currentMission.terrainRootNode, x, 0, z)

    local xRot = MathUtil.getYRotationFromDirection(nz, ny)
    local yRot = MathUtil.getYRotationFromDirection(nx, nz)
    local zRot = -MathUtil.getYRotationFromDirection(nx, ny)

    return xRot, yRot, zRot
end

------------------------------------------------------------------------------------------------------------------------
-- PathfinderUtil.CollisionDetector
---------------------------------------------------------------------------------------------------------------------------
---@class PathfinderUtil.CollisionDetector
PathfinderUtil.CollisionDetector = CpObject()

--- Nodes of a trigger for example, that will be ignored as collision.
PathfinderUtil.CollisionDetector.NODES_TO_IGNORE = {}

function PathfinderUtil.CollisionDetector:init()
    self.vehiclesToIgnore = {}
    self.collidingShapes = 0
end

--- Adds a node which collision will be ignored global for every pathfinder.
---@param node number
function PathfinderUtil.CollisionDetector.addNodeToIgnore(node)
    PathfinderUtil.CollisionDetector.NODES_TO_IGNORE[node] = true
end

--- Removes a node, so it's collision is no longer applied.
---@param node number
function PathfinderUtil.CollisionDetector.removeNodeToIgnore(node)
    PathfinderUtil.CollisionDetector.NODES_TO_IGNORE[node] = nil
end

function PathfinderUtil.CollisionDetector:overlapBoxCallback(transformId)
    if PathfinderUtil.CollisionDetector.NODES_TO_IGNORE[transformId] then 
        --- Global node, that needs to be ignored
        return
    end

    local collidingObject = g_currentMission.nodeToObject[transformId]
    if collidingObject and PathfinderUtil.elementOf(self.objectsToIgnore, collidingObject) then
        -- an object we want to ignore
        return
    end
    if collidingObject then
        local rootVehicle
        if collidingObject.getRootVehicle then
            rootVehicle = collidingObject:getRootVehicle()
        elseif collidingObject:isa(Bale) and collidingObject.mountObject then
            rootVehicle = collidingObject.mountObject:getRootVehicle()
        end
        if rootVehicle == self.vehicleData.rootVehicle or
                PathfinderUtil.elementOf(self.vehiclesToIgnore, rootVehicle) then
            -- just bumped into myself or a vehicle we want to ignore
            return
        end
        if collidingObject:isa(Bale) then
            self:debug('collision with bale %d', collidingObject.id)
        else
            self:debug('collision: %s', collidingObject.getName and collidingObject:getName() or 'unknown')
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
            self:debug('collision with terrain and fillType: %s.',
                    g_fillTypeManager:getFillTypeByIndex(fillType).title)
        else
            --- Ignore terrain hits, if no fillType is dropped to the ground was detected.
            return
        end
    end

    local text = ''
    for key, classId in pairs(ClassIds) do
        if getHasClassId(transformId, classId) then
            text = text .. ' ' .. key
        end
    end
    self.collidingShapesText = text
    self.collidingShapes = self.collidingShapes + 1
end

function PathfinderUtil.CollisionDetector:findCollidingShapes(node, vehicleData, vehiclesToIgnore, objectsToIgnore, ignoreFruitHeaps)
    self.vehiclesToIgnore = vehiclesToIgnore or {}
    self.objectsToIgnore = objectsToIgnore or {}
    self.vehicleData = vehicleData
    self.ignoreFruitHeaps = ignoreFruitHeaps
    -- the box for overlapBox() is symmetric, so if our root node is not in the middle of the vehicle rectangle,
    -- we have to translate it into the middle
    -- right/rear is negative
    local width = (math.abs(vehicleData.dRight) + math.abs(vehicleData.dLeft)) / 2
    local length = (math.abs(vehicleData.dFront) + math.abs(vehicleData.dRear)) / 2
    local zOffset = vehicleData.dFront - length
    local xOffset = vehicleData.dLeft - width

    local xRot, yRot, zRot = getWorldRotation(node)
    local x, y, z = localToWorld(node, xOffset, 1, zOffset)
    local dirX, dirZ = MathUtil.getDirectionFromYRotation(yRot)
    --- Save these for the overlap box callback.
    self.currentOverlapBoxPosition = {
        pos = { x, y, z },
        direction = { dirX, dirZ },
        size = math.max(width, length)
    }
    self.collidingShapes = 0
    self.collidingShapesText = 'unknown'

    local collisionMask = CpUtil.getDefaultCollisionFlags() + CollisionFlag.TERRAIN_DELTA

    overlapBox(x, y + 0.2, z, xRot, yRot, zRot, width, 1, length, 'overlapBoxCallback', self, collisionMask, true, true, true)

    if true and self.collidingShapes > 0 then
        table.insert(PathfinderUtil.overlapBoxes,
                { x = x, y = y + 0.2, z = z, xRot = xRot, yRot = yRot, zRot = zRot, width = width, length = length })
        self:debug('pathfinder colliding shapes %s with %s at x = %.1f, z = %.1f, (%.1fx%.1f), yRot = %d',
                self.collidingShapesText, vehicleData.name, x, z, width, length, math.deg(yRot))
    end

    return self.collidingShapes
end

function PathfinderUtil.CollisionDetector:debug(...)
    if self.vehicleData then
        PathfinderUtil.debug(self.vehicleData.vehicle, ...)
    end
end

PathfinderUtil.collisionDetector = PathfinderUtil.CollisionDetector()

--- Is there harvestable fruit at x, z?
---@param areaToIgnoreFruit PathfinderUtil.Area|nil
---@return boolean true if there's fruit in the length * width area around x, z
---@return number percentage of area covered by fruit
---@return string name of fruit
function PathfinderUtil.hasFruit(x, z, length, width, areaToIgnoreFruit)
    if areaToIgnoreFruit and areaToIgnoreFruit:contains(x, z) then
        return false
    end
    local fruitsToIgnore = { FruitType.POTATO, FruitType.GRASS, FruitType.MEADOW } -- POTATO, GRASS, MEADOW, we can drive through these...
    for _, fruitType in ipairs(g_fruitTypeManager.fruitTypes) do
        local ignoreThis = false
        for _, fruitToIgnore in ipairs(fruitsToIgnore) do
            if fruitType.index == fruitToIgnore then
                ignoreThis = true
                break
            end
        end
        if not ignoreThis then
            -- if the last boolean parameter is true then it returns fruitValue > 0 for fruits/states ready for forage also
            local fruitValue, numPixels, totalNumPixels, c = FSDensityMapUtil.getFruitArea(fruitType.index, x - width / 2, z - length / 2, x + width / 2, z, x, z + length / 2, true, true)
            --if g_updateLoopIndex % 200 == 0 then
            --CpUtil.debugFormat(CpDebug.DBG_PATHFINDER, '%.1f, %s, %s, %s %s', fruitValue, tostring(a), tostring(b), tostring(c), g_fruitTypeManager:getFruitTypeByIndex(fruitType.index).name)
            --end
            if fruitValue > 0 then
                return true, 100 * numPixels / totalNumPixels, g_fruitTypeManager:getFruitTypeByIndex(fruitType.index).name
            end
        end
    end
    return false
end
---------------------------------------------------------------------------------------------------------------------------
-- A generic rectangular area
---------------------------------------------------------------------------------------------------------------------------
--- @class PathfinderUtil.Area
PathfinderUtil.Area = CpObject()

--- A square area around a point.
---@param x number area center x
---@param z number area center z
---@param size number size of the rectangle
function PathfinderUtil.Area:init(x, z, size)
    self.x, self.z = x, z
    self.size = size
    self.minX = x - size / 2
    self.maxX = x + size / 2
    self.minZ = z - size / 2
    self.maxZ = z + size / 2
end

-- is x, z within the area?
function PathfinderUtil.Area:contains(x, z)
    return x > self.minX and x < self.maxX and z > self.minZ and z < self.maxZ
end

function PathfinderUtil.Area:__tostring()
    return string.format('area at %.1f %.1f, size %.1f m', self.x, self.z, self.size)
end

---------------------------------------------------------------------------------------------------------------------------
-- A generic rectangular area oriented by a node
---------------------------------------------------------------------------------------------------------------------------
--- @class PathfinderUtil.NodeArea
PathfinderUtil.NodeArea = CpObject()

--- The area is a length x width rectangle, the rectangle's bottom right corner (when looking from node) is
--- at xOffset/zOffset from node.
function PathfinderUtil.NodeArea:init(node, xOffset, zOffset, width, length)
    self.node = node
    self.xOffset, self.zOffset = xOffset, zOffset
    self.width, self.length = width, length
end

--- Is (x, z) world coordinate in the area?
function PathfinderUtil.NodeArea:contains(x, z)
    local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z)
    local dx, _, dz = worldToLocal(self.node, x, y, z)
    if self.xOffset < dx and dx < self.xOffset + self.width and
            self.zOffset < dz and dz < self.zOffset + self.length then
        --print(x, z, dx, dz, self.xOffset, self.width, 'contains')
        return true
    else
        return false
    end
end

function PathfinderUtil.NodeArea:__tostring()
    return string.format('area from node %s, %.1f x %.1f m', self.node, self.width, self.length)
end

function PathfinderUtil.NodeArea:drawDebug()
    DebugUtil.drawDebugRectangle(self.node, self.xOffset, self.xOffset + self.width,
            self.zOffset, self.zOffset + self.length, 5, 1, 1, 0, 1, false)
end

--- Creates an area to avoid for a vehicle based on its defined dimensions.
---@param vehicle table
---@param buffer number|nil buffer around the vehicle
---@return PathfinderUtil.NodeArea
function PathfinderUtil.NodeArea.createVehicleArea(vehicle, buffer)
    buffer = buffer or 0
    return PathfinderUtil.NodeArea(vehicle.rootNode,
            -vehicle.size.width / 2 + vehicle.size.widthOffset - buffer,
            -vehicle.size.length / 2 + vehicle.size.lengthOffset - buffer,
            vehicle.size.width + 2 * buffer,
            vehicle.size.length + 2 * buffer)
end

---@param start State3D
---@param vehicleData PathfinderUtil.VehicleData
function PathfinderUtil.initializeTrailerHeading(start, vehicleData)
    -- initialize the trailer's heading for the starting point
    if vehicleData.trailer then
        local _, _, yRot = PathfinderUtil.getNodePositionAndDirection(vehicleData.trailer.rootNode, 0, 0)
        start:setTrailerHeading(CpMathUtil.angleFromGame(yRot))
    end
end

---@param start State3D
---@param goal State3D
---@param course Course
---@param turnRadius number
---@param workingWidth number
---@param backMarkerDistance number
---@param boundaryId string|nil id of the boundary (field or island), to make sure we stay on the same headland as
--- the headland number alone may also be one of the island headlands.
---@return State3D[]
local function findShortestPathOnHeadland(start, goal, course, turnRadius, workingWidth, backMarkerDistance, boundaryId)
    local headlandWidth = course:getNumberOfHeadlands() * workingWidth
    -- distance of the vehicle's direction node from the end of the row. If the implement is on the front of the
    -- vehicle (like a combine), we move the vehicle up to the end of the row so we'll later always end up with
    -- a valid headland number (<= num of headlands)
    local distanceFromRowEnd = backMarkerDistance < 0 and -backMarkerDistance or 0
    -- this is what is in front of us, minus the turn radius as we'll need at least that space to stay on the field
    -- during a turn
    local usableHeadlandWidth = headlandWidth - (distanceFromRowEnd + turnRadius)
    local closestHeadland = math.max(1, math.min(course:getNumberOfHeadlands() - 1,
            math.floor(usableHeadlandWidth / workingWidth) + 1))
    -- to be able to use the existing getSectionBetweenPoints, we first create a Polyline[], then construct a State3D[]
    local headland = course:getHeadland(closestHeadland, boundaryId)
    CpUtil.debugVehicle(CpDebug.DBG_PATHFINDER, course:getVehicle(),
            'headland width %.1f, distance from row end %.1f, usable headland width %.1f closest headland %d (%s) with %d points',
            headlandWidth, distanceFromRowEnd, usableHeadlandWidth, closestHeadland, boundaryId, #headland)
    if #headland == 0 then
        return
    end
    headland:calculateProperties()
    local path = {}
    local startVertex = headland:findClosestVertexToPoint(start)
    local endVertex = headland:findClosestVertexToPoint(goal)
    for _, p in ipairs(headland:getShortestPathBetween(startVertex.ix, endVertex.ix)) do
        table.insert(path, State3D(p.x, p.y, 0))
    end
    return path
end

------------------------------------------------------------------------------------------------------------------------
--- Interface function to start the pathfinder
------------------------------------------------------------------------------------------------------------------------
---@param vehicle table for debugging only
---@param start State3D start node
---@param goal State3D goal node
---@param constraints PathfinderConstraints
---@param allowReverse boolean allow reverse driving
---@param mustBeAccurate boolean must be accurately find the goal position/angle
---@param maxIterations number maximum number of iterations
function PathfinderUtil.startPathfinding(vehicle, start, goal, constraints, allowReverse, mustBeAccurate, maxIterations)
    PathfinderUtil.overlapBoxes = {}
    local pathfinder = HybridAStarWithAStarInTheMiddle(vehicle, constraints.turnRadius * 4, 100, maxIterations, mustBeAccurate)
    return pathfinder, pathfinder:start(start, goal, constraints.turnRadius, allowReverse,
            constraints, constraints.trailerHitchLength)
end

------------------------------------------------------------------------------------------------------------------------
--- Interface function to start the pathfinder for a turn maneuver
------------------------------------------------------------------------------------------------------------------------
---@param vehicle table
---@param startOffset number offset in meters relative to the vehicle position (forward positive, backward negative) where
--- we want the turn to start
---@param goalReferenceNode table node used to determine the goal
---@param goalOffset number offset in meters relative to the goal node (forward positive, backward negative)
--- Together with the goalReferenceNode defines the goal
---@param turnRadius number vehicle turning radius
---@param allowReverse boolean allow reverse driving
---@param courseWithHeadland Course fieldwork course, needed to find the headland
---@param workingWidth number working width of the vehicle
---@param backMarkerDistance number back marker distance, this is approximately how far the end of the row is
--- in front of the vehicle when it stops working on that row before the turn starts. Negative values mean the
--- vehicle is towing the implements and is past the end of the row when the implement reaches the end of the row.
---@param turnOnField boolean is turn on field allowed?
---@param boundaryId string|nil id of the boundary (field or island), to make sure we stay on the same headland as
--- the headland number alone may also be one of the island headlands.
---@return PathfinderInterface pathfinder
---@return PathfinderResult
function PathfinderUtil.findPathForTurn(vehicle, startOffset, goalReferenceNode, goalOffset, turnRadius, allowReverse,
                                        courseWithHeadland, workingWidth, backMarkerDistance, turnOnField, boundaryId)
    local x, z, yRot = PathfinderUtil.getNodePositionAndDirection(vehicle:getAIDirectionNode(), 0, startOffset or 0)
    local start = State3D(x, -z, CpMathUtil.angleFromGame(yRot))
    x, z, yRot = PathfinderUtil.getNodePositionAndDirection(goalReferenceNode, 0, goalOffset or 0)
    local goal = State3D(x, -z, CpMathUtil.angleFromGame(yRot))

    -- use an analyticSolver which only yields courses ending in forward gear. This is to
    -- avoid reaching the end of turn in reverse. Implement lowering at turn end in reverse works only properly
    -- when we are driving straight, but an analytic path ending in reverse will always also end in a curve
    local analyticSolver = ReedsSheppSolver(ReedsShepp.ForwardEndingPathWords)

    PathfinderUtil.overlapBoxes = {}
    local pathfinder
    if courseWithHeadland and courseWithHeadland:getNumberOfHeadlands() > 0 then
        -- if there's a headland, we want to drive on the headland to the next row
        local headlandPath = findShortestPathOnHeadland(start, goal, courseWithHeadland, turnRadius, workingWidth,
                backMarkerDistance, boundaryId)
        if headlandPath ~= nil then
            -- is the first wp of the headland in front of us?
            local _, y, _ = getWorldTranslation(vehicle:getAIDirectionNode())
            local dx, _, dz = worldToLocal(vehicle:getAIDirectionNode(), headlandPath[1].x, y, -headlandPath[1].y)
            local dirDeg = math.deg(math.abs(math.atan2(dx, dz)))
            if dirDeg > 45 or true then
                PathfinderUtil.logger:debug('First headland waypoint isn\'t in front of us (%.1f), remove first few waypoints to avoid making a circle %.1f %.1f', dirDeg, dx, dz)
            end
            pathfinder = HybridAStarWithPathInTheMiddle(vehicle, turnRadius * 3, 200, headlandPath, true, analyticSolver)
        end
    end
    if pathfinder == nil then
        PathfinderUtil.logger:debug('No headland, or there is a headland but wasn\'t able to get the shortest path on the headland to the next row, falling back to hybrid A*')
        pathfinder = HybridAStarWithAStarInTheMiddle(vehicle, turnRadius * 6, 200, 10000, true, analyticSolver)
    end

    local context = PathfinderContext(vehicle):useFieldNum(CpFieldUtil.getFieldNumUnderVehicle(vehicle))
    context:offFieldPenalty(turnOnField and 10 or context._offFieldPenalty)
    local constraints = PathfinderConstraints(context)
    return pathfinder, pathfinder:start(start, goal, turnRadius, allowReverse, constraints, constraints.trailerHitchLength)
end

------------------------------------------------------------------------------------------------------------------------
--- Generate an analytic path between the vehicle and the goal node
------------------------------------------------------------------------------------------------------------------------
---@param solver AnalyticSolver for instance PathfinderUtil.dubinsSolver or PathfinderUtil.reedsSheppSolver
---@param vehicleDirectionNode number Giants node
---@param startXOffset number offset in meters relative to the vehicle position (left positive, right negative) where
--- we want the turn to start
---@param startZOffset number offset in meters relative to the vehicle position (forward positive, backward negative) where
--- we want the turn to start
---@param goalReferenceNode table node used to determine the goal
---@param xOffset number offset in meters relative to the goal node (left positive, right negative)
---@param zOffset number offset in meters relative to the goal node (forward positive, backward negative)
--- Together with the goalReferenceNode defines the goal
---@param turnRadius number vehicle turning radius
---@return table|nil path
---@return number length
function PathfinderUtil.findAnalyticPath(solver, vehicleDirectionNode, startXOffset, startZOffset, goalReferenceNode,
                                         xOffset, zOffset, turnRadius)
    local x, z, yRot = PathfinderUtil.getNodePositionAndDirection(vehicleDirectionNode, startXOffset, startZOffset or 0)
    local start = State3D(x, -z, CpMathUtil.angleFromGame(yRot))
    x, z, yRot = PathfinderUtil.getNodePositionAndDirection(goalReferenceNode, xOffset or 0, zOffset or 0)
    local goal = State3D(x, -z, CpMathUtil.angleFromGame(yRot))
    return PathfinderUtil.findAnalyticPathFromStartToGoal(solver, start, goal, turnRadius)
end

--- Generate an analytic path between a start and goal position (given as State3D)
---@param solver AnalyticSolver for instance PathfinderUtil.dubinsSolver or PathfinderUtil.reedsSheppSolver
---@param start State3D start pose
---@param goal State3D goal pose
---@param turnRadius number vehicle turning radius
function PathfinderUtil.findAnalyticPathFromStartToGoal(solver, start, goal, turnRadius)
    local solution = solver:solve(start, goal, turnRadius)
    local length, path = solution:getLength(turnRadius)
    -- a solution with math.huge length means no soulution found
    if length < 100000 then
        path = solution:getWaypoints(start, turnRadius)
    end
    return path, length
end

function PathfinderUtil.getNodePositionAndDirection(node, xOffset, zOffset)
    local x, _, z = localToWorld(node, xOffset or 0, 0, zOffset or 0)
    local lx, _, lz = localDirectionToWorld(node, 0, 0, 1)
    local yRot = math.atan2(lx, lz)
    return x, z, yRot
end

---@param vehicle table
---@param xOffset number|nil
---@param zOffset number|nil
---@return State3D position/heading of vehicle
function PathfinderUtil.getVehiclePositionAsState3D(vehicle, xOffset, zOffset)
    local x, z, yRot = PathfinderUtil.getNodePositionAndDirection(AIUtil.getDirectionNode(vehicle), xOffset, zOffset)
    return State3D(x, -z, CpMathUtil.angleFromGame(yRot))
end

--- Creates a State3D Vector from a given Waypoint.
---@param waypoint Waypoint
---@param xOffset number the offset in the waypoint coordinate system (left < 0 < right)
---@param zOffset number
---@return State3D
function PathfinderUtil.getWaypointAsState3D(waypoint, xOffset, zOffset)
    local result = State3D(waypoint.x, -waypoint.z, CpMathUtil.angleFromGameDeg(waypoint.angle))
    if waypoint:getIsReverse() then
        --- If it's a reverse driven waypoint, then the target heading needs to be inverted. 
        result:reverseHeading()
    end
    local offset = Vector(zOffset, -xOffset)
    result:add(offset:rotate(result.t))
    return result
end

------------------------------------------------------------------------------------------------------------------------
--- Interface function to start the pathfinder in the game, using a State3D pose as the goal
------------------------------------------------------------------------------------------------------------------------
---@param goal State3D
---@param context PathfinderContext
---@return PathfinderInterface pathfinder
---@return PathfinderResult
function PathfinderUtil.startPathfindingFromVehicleToGoal(goal, context)

    local start = PathfinderUtil.getVehiclePositionAsState3D(context._vehicle)
    local constraints = PathfinderConstraints(context)
    PathfinderUtil.initializeTrailerHeading(start, constraints.vehicleData)

    return PathfinderUtil.startPathfinding(context._vehicle, start, goal, constraints, context._allowReverse,
            context._mustBeAccurate, context._maxIterations)
end

------------------------------------------------------------------------------------------------------------------------
--- Interface function to start the pathfinder in the game, using a waypoint as the goal
------------------------------------------------------------------------------------------------------------------------
---@param course Course the course with the destination waypoint
---@param goalWaypointIx number index of the waypoint
---@param xOffset number side offset of the goal from the goalWaypoint (left < 0 < right)
---@param zOffset number length offset of the goal from the goalWaypoint
---@param context PathfinderContext
---@return PathfinderInterface pathfinder
---@return PathfinderResult
function PathfinderUtil.startPathfindingFromVehicleToWaypoint(course, goalWaypointIx, xOffset, zOffset, context)
    local goal = PathfinderUtil.getWaypointAsState3D(course:getWaypoint(goalWaypointIx), xOffset, zOffset)
    -- TODO: this was forced to true here before refactoring, but is false in the context by default
    context:mustBeAccurate(true)
    return PathfinderUtil.startPathfindingFromVehicleToGoal(goal, context)
end
------------------------------------------------------------------------------------------------------------------------
--- Interface function to start the pathfinder in the game. The goal is a point at sideOffset meters from the goal node
--- (sideOffset > 0 is left)
------------------------------------------------------------------------------------------------------------------------
---@param goalNode number The goal node
---@param xOffset number side offset of the goal from the goal node
---@param zOffset number length offset of the goal from the goal node
---@param context PathfinderContext
---@return PathfinderInterface pathfinder
---@return PathfinderResult
function PathfinderUtil.startPathfindingFromVehicleToNode(goalNode, xOffset, zOffset, context)
    local x, z, yRot = PathfinderUtil.getNodePositionAndDirection(goalNode, xOffset, zOffset)
    local goal = State3D(x, -z, CpMathUtil.angleFromGame(yRot))
    return PathfinderUtil.startPathfindingFromVehicleToGoal(goal, context)
end

------------------------------------------------------------------------------------------------------------------------
--- Interface function to start a simple A* pathfinder in the game. The goal is a node
------------------------------------------------------------------------------------------------------------------------
---@param goalNode table The goal node
---@param xOffset number side offset of the goal from the goal node (> 0 is left)
---@param zOffset number length offset of the goal from the goal node (> 0 is front)
---@param context PathfinderContext
---@return PathfinderInterface pathfinder
---@return PathfinderResult
function PathfinderUtil.startAStarPathfindingFromVehicleToNode(goalNode, xOffset, zOffset, context)
    local x, z, yRot = PathfinderUtil.getNodePositionAndDirection(context._vehicle:getAIDirectionNode())
    local start = State3D(x, -z, CpMathUtil.angleFromGame(yRot))
    x, z, yRot = PathfinderUtil.getNodePositionAndDirection(goalNode, xOffset, zOffset)
    local goal = State3D(x, -z, CpMathUtil.angleFromGame(yRot))

    local constraints = PathfinderConstraints(context)
    PathfinderUtil.initializeTrailerHeading(start, constraints.vehicleData)

    local pathfinder = AStar(context._vehicle, 100, 10000)
    return pathfinder, pathfinder:start(start, goal, constraints.turnRadius, false, constraints, constraints.trailerHitchLength)
end

--- Helper function to find a reasonable number of maximum iterations based on a field polygon
---@param fieldPolygon Polygon
---@return number maximum iterations we think has a good chance to succeed on the above polygon
function PathfinderUtil.getMaxIterationsForFieldPolygon(fieldPolygon)
    if fieldPolygon then
        local circumference = fieldPolygon.circumference
        if not circumference then
            circumference = CpMathUtil.getCircumferenceOfPolygon(fieldPolygon)
        end
        return math.floor(math.max(HybridAStar.defaultMaxIterations, 20 * circumference))
    else
        return HybridAStar.defaultMaxIterations
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Debug stuff
---------------------------------------------------------------------------------------------------------------------------
function PathfinderUtil.setVisualDebug(d)
    PathfinderUtil.visualDebugLevel = d
end

function PathfinderUtil.showNodes(pathfinder)
    if PathfinderUtil.visualDebugLevel < 1 then
        return
    end
    if pathfinder then
        local nodes
        if PathfinderUtil.visualDebugLevel > 1 and
                pathfinder.hybridAStarPathfinder and pathfinder.hybridAStarPathfinder.nodes then
            nodes = pathfinder.hybridAStarPathfinder.nodes
        elseif PathfinderUtil.visualDebugLevel > 0 and pathfinder.aStarPathfinder and pathfinder.aStarPathfinder.nodes then
            nodes = pathfinder.aStarPathfinder.nodes
        elseif PathfinderUtil.visualDebugLevel > 0 and pathfinder.nodes then
            nodes = pathfinder.nodes
        end
        if nodes then
            for _, row in pairs(nodes.nodes) do
                for _, column in pairs(row) do
                    for _, cell in pairs(column) do
                        if cell.x and cell.y then
                            local range = nodes.highestCost - nodes.lowestCost
                            local color = (cell.cost - nodes.lowestCost) / range
                            local r, g, b
                            if cell.offField then
                                r, g, b = 250 * color, 250 - 250 * color, 0
                            else
                                r, g, b = color, 1 - color, 0
                            end
                            local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, cell.x, 0, -cell.y)
                            --cpDebug:drawPoint(cell.x, y + 1, -cell.y, r, g, b)
                            if cell.pred and cell.pred.y then
                                DebugUtil.drawDebugLine(cell.x, y + 1, -cell.y,
                                        cell.pred.x, y + 1, -cell.pred.y, r, g, b)
                            end
                            if cell.isColliding then
                                --cpDebug:drawPoint(cell.x, y + 1.2, -cell.y, 100, 0, 0)
                            end
                        end
                    end
                end
            end
        end
    end
    if pathfinder and pathfinder.middlePath then
        for i = 2, #pathfinder.middlePath do
            local cp = pathfinder.middlePath[i]
            -- an in-place conversion may have taken place already, make sure we have a valid z
            cp.z = cp.y and -cp.y or cp.z
            local cy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, cp.x, 0, cp.z)
            local pp = pathfinder.middlePath[i - 1]
            pp.z = pp.y and -pp.y or pp.z
            local py = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, pp.x, 0, pp.z)
            DebugUtil.drawDebugLine(cp.x, cy + 3, cp.z, pp.x, py + 3, pp.z, 10, 0, 0)
        end
    end
    if PathfinderUtil.helperNode then
        DebugUtil.drawDebugNode(PathfinderUtil.helperNode, 'Pathfinder')
    end
    if myCollisionData then
        for i = 1, 4 do
            local cp = myCollisionData.corners[i]
            local pp = myCollisionData.corners[i > 1 and i - 1 or 4]
            DebugUtil.drawDebugLine(cp.x, cp.y + 0.4, cp.z, pp.x, pp.y + 0.4, pp.z, 1, 1, 0)
        end
    end
    if PathfinderUtil.vehicleCollisionData then
        for _, collisionData in pairs(PathfinderUtil.vehicleCollisionData) do
            for i = 1, 4 do
                local cp = collisionData.corners[i]
                local pp = collisionData.corners[i > 1 and i - 1 or 4]
                DebugUtil.drawDebugLine(cp.x, cp.y + 0.4, cp.z, pp.x, pp.y + 0.4, pp.z, 1, 1, 0)
            end
        end
    end
end

function PathfinderUtil.showOverlapBoxes()
    if not PathfinderUtil.overlapBoxes then
        return
    end
    for _, box in ipairs(PathfinderUtil.overlapBoxes) do
        DebugUtil.drawOverlapBox(box.x, box.y, box.z, box.xRot, box.yRot, box.zRot, box.width, 1, box.length, 0, 100, 0)
    end
end

function PathfinderUtil.debug(vehicle, ...)
    CpUtil.debugVehicle(CpDebug.DBG_PATHFINDER, vehicle, ...)
end