--[[
This file is part of Courseplay (https://github.com/Courseplay/Courseplay_FS25)
Copyright (C) 2020-2022 Peter Vaiko

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
]]--

--- A proximity sensor raycasting parallel to the terrain to find obstacles/vehicles
---@class ProximitySensor
ProximitySensor = CpObject()
-- maximum angle we rotate the sensor into the direction the vehicle is turning
ProximitySensor.maxRotation = math.rad(30)

function ProximitySensor:init(node, yRotationDeg, range, height, xOffset, vehicle, rotationEnabled)
    self.node = node
    self.xOffset = xOffset
    self.rotationEnabled = rotationEnabled
    local _, _, dz = localToLocal(node, AIUtil.getDirectionNode(vehicle), 0, 0, 0)
    self.angleToDirectionNode = math.abs(math.atan2(xOffset, dz))
    CpUtil.debugVehicle(CpDebug.DBG_TRAFFIC, vehicle, 'Proximity sensor dx %.1f, angle %.1f, angle to root %.1f',
            xOffset, yRotationDeg, math.deg(self.angleToDirectionNode))
    self.range = range
    -- the normal rotation (direction) of this sensor when the wheels are straight
    self.baseYRotation = math.rad(yRotationDeg)
    -- current rotation, adjusted to left or right when the wheels are steered
    self.yRotation = self.baseYRotation
    self:setRotation(0)
    self.height = height or 0
    self.lastUpdateLoopIndex = 0
    self.enabled = true
    self.vehicle = vehicle
    -- vehicles can only be ignored temporarily
    self.ignoredVehicle = CpTemporaryObject()
end

function ProximitySensor:setRotation(yRotation)
    self.yRotation = self.baseYRotation + yRotation
    self.lx, self.lz = MathUtil.getDirectionFromYRotation(self.yRotation)
    self.dx, self.dz = self.lx * self.range, self.lz * self.range
end

function ProximitySensor:getRotationDeg()
    return math.deg(self.yRotation)
end

function ProximitySensor:getBaseRotationDeg()
    return math.deg(self.baseYRotation)
end

function ProximitySensor:enable()
    self.enabled = true
end

function ProximitySensor:disable()
    self.enabled = false
end

---@param vehicle table vehicle to ignore
---@param ttlMs number milliseconds to ignore this vehicle. After ttlMs ms it won't be ignored.
function ProximitySensor:setIgnoredVehicle(vehicle, ttlMs)
    self.ignoredVehicle:set(vehicle, ttlMs)
end

function ProximitySensor:update()
    -- already updated in this loop, no need to raycast again
    if g_updateLoopIndex == self.lastUpdateLoopIndex then
        return
    end
    self.lastUpdateLoopIndex = g_updateLoopIndex

    -- rotate with the steering angle
    if self.rotationEnabled and self.vehicle.rotatedTime then
        -- we add a correction here depending on the position of the sensor relative to the vehicle's root node
        -- and on the turn direction. The idea is that when the vehicle is turning, the sensor is moving on
        -- a radius around the vehicle's root node (in addition to the forward movement of the vehicle), and we want
        -- to point the sensor's ray in the resulting vector's direction. At the end, sensor's on the inside of the turn
        -- are rotated more into the turn than those on the outside due to this is what this correction factor
        -- also, rotatedTime's sign does not change when a reverse driving capable vehicle changes the driving
        -- direction (cab is rotated, driver facing to the back of the tractor), so we need getSteeringDirection()
        -- to compensate for that
        local correction = self.vehicle:getSteeringDirection() *
                ((CpMathUtil.divide(self.vehicle.rotatedTime, self.xOffset)) >= 0
                        and self.angleToDirectionNode or
                        -self.angleToDirectionNode)
        self:setRotation(CpMathUtil.clamp(
                self.vehicle.rotatedTime * (2 * self.maxRotation + correction) * self.vehicle:getSteeringDirection(),
                -2 * self.maxRotation,
                2 * self.maxRotation))
    end

    local x, y, z = localToWorld(self.node, self.xOffset, 0, 0)
    -- we want the rays run parallel to the terrain, so always use the terrain height (because the node itself
    -- can be under ground at sudden elevation changes, even node y + height, and when the ray starts from under
    -- the ground, it seems to cause a hit, even if it should not for the terrain
    local y1 = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z)
    -- get the terrain height at the end of the raycast line
    local tx, _, tz = localToWorld(self.node, self.dx + self.xOffset, 0, self.dz)
    local y2 = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, tx, 0, tz)
    if math.abs(y - y1) > 1.5 * self.height then
        -- workaround: likely on a bridge, the terrain height at the node shouldn't be much more than height
        y1, y2 = y - self.height, y - self.height
    end
    -- make sure the raycast line is parallel with the ground
    local ny = (y2 - y1) / self.range
    local nx, _, nz = localDirectionToWorld(self.node, self.lx, 0, self.lz)
    self.distanceOfClosestObject = math.huge
    self.objectId = nil
    self.hitTerrain = false
    if self.enabled then
        local raycastMask = CpUtil.getDefaultCollisionFlags()
        raycastClosest(x, y1 + self.height, z, nx, ny, nz, self.range, 'raycastCallback', self, raycastMask)
        if CpDebug:isChannelActive(CpDebug.DBG_TRAFFIC, self.vehicle) then
            DebugUtil.drawDebugLine(x, y1 + self.height, z, x + 5 * nx, y1 + self.height + 5 * ny, z + 5 * nz, 0, 1, 0)
        end
    end
    if CpDebug:isChannelActive(CpDebug.DBG_TRAFFIC, self.vehicle) and self.distanceOfClosestObject <= self.range then
        local green = self.distanceOfClosestObject / self.range
        local red = 1 - green
        DebugUtil.drawDebugLine(x, y1 + self.height, z, self.closestObjectX, self.closestObjectY, self.closestObjectZ, red, green, 0)
    end
end

function ProximitySensor:raycastCallback(objectId, x, y, z, distance)
    local object = g_currentMission:getNodeObject(objectId)
    if object and object.getRootVehicle and object:getRootVehicle() == self.ignoredVehicle:get() then
        -- ignore this vehicle
        return
    end
    self.distanceOfClosestObject = distance
    self.objectId = objectId
    self.hitTerrain = objectId == g_currentMission.terrainRootNode
    self.closestObjectX, self.closestObjectY, self.closestObjectZ = x, y, z
end

function ProximitySensor:getClosestObjectDistance()
    --self:showDebugInfo()
    return self.distanceOfClosestObject
end

function ProximitySensor:getClosestObject()
    return g_currentMission:getNodeObject(self.objectId)
end

function ProximitySensor:hasHitTerrain()
    return self.hitTerrain
end

function ProximitySensor:getClosestRootVehicle()
    if self.objectId then
        local object = g_currentMission:getNodeObject(self.objectId)
        if object and object.getRootVehicle then
            return object:getRootVehicle()
        end
    end
end

function ProximitySensor:showDebugInfo()
    if not CpDebug:isChannelActive(CpDebug.DBG_TRAFFIC, self.vehicle) then
        return
    end
    local text = string.format('%.1f ', self.distanceOfClosestObject)
    if self.objectId then
        local object = g_currentMission:getNodeObject(self.objectId)
        if object then
            if object.getRootVehicle then
                text = text .. 'vehicle ' .. object:getName()
            else
                text = text .. object:getName()
            end
        else
            for key, classId in pairs(ClassIds) do
                if getHasClassId(self.objectId, classId) then
                    text = text .. ' ' .. key
                end
            end
        end
    end
    renderText(0.6, 0.4 + self.yRotation / 5, 0.012, text .. string.format(' %d', math.deg(self.yRotation)))
end

---@class ProximitySensorPack
ProximitySensorPack = CpObject()

-- maximum angle we rotate the sensor pack into the direction the vehicle is turning
ProximitySensorPack.maxRotation = math.rad(30)

---@param name string a name for this sensor, when multiple sensors are attached to the same node, they need
--- a unique name
---@param vehicle table vehicle we attach the sensor to, used only to rotate the sensor with the steering angle
---@param node number node (front or back) to attach the sensor to
---@param range number range of the sensor in meters
---@param height number height relative to the node in meters
---@param directionsDeg table of numbers, list of angles in degrees to emit a ray to find objects, 0 is forward, >0 left, <0 right
---@param xOffsets table of numbers, left/right offset of the corresponding sensor in meters, left > 0, right < 0
---@param rotationEnabled boolean if true, rotate the sensors in the direction the vehicle is turning
function ProximitySensorPack:init(name, vehicle, node, range, height, directionsDeg, xOffsets, rotationEnabled)
    ---@type ProximitySensor[]
    self.sensors = {}
    self.vehicle = vehicle
    self.range = range
    self.name = name
    self.node = getChild(node, name)
    if self.node <= 0 then
        -- node with this name does not yet exist
        -- add a separate node for the pack (so we can move it independently from 'node'
        self.node = CpUtil.createNode(name, 0, 0, 0, node)
    end
    -- reset it on the parent node
    setTranslation(self.node, 0, 0, 0)
    setRotation(self.node, 0, 0, 0)
    self.directionsDeg = directionsDeg
    self.xOffsets = xOffsets
    self.rotation = 0
    for i, deg in ipairs(self.directionsDeg) do
        table.insert(self.sensors, ProximitySensor(self.node, deg, self.range, height, xOffsets[i] or 0, vehicle, rotationEnabled))
    end
end

function ProximitySensorPack:debug(...)
    CpUtil.debugVehicle(CpDebug.DBG_TRAFFIC, self.vehicle, ...)
end

function ProximitySensorPack:getXOffsets(width, nSensors)
    local xOffsets = {}
    -- spread them out evenly across the width
    local dx = width / nSensors
    for xOffset = width / 2 - dx / 2, -width / 2 + dx / 2 - 0.1, -dx do
        table.insert(xOffsets, xOffset)
    end
    return xOffsets
end

function ProximitySensorPack:adjustForwardPosition()
    -- are we looking forward
    local forward = 1
    -- if a sensor about in the middle is pointing back, we are looking back
    if math.abs(self.directionsDeg[math.max(math.floor(#self.directionsDeg / 2), 1)]) > 90 then
        forward = -1
    end
    local x, y, z = getTranslation(self.node)
    self:debug('moving proximity sensor %s %.1f so it does not interfere with own vehicle', self.name, forward * 0.1)
    -- move pack forward/back a bit
    setTranslation(self.node, x, y, z + forward * 0.1)
end

function ProximitySensorPack:getRange()
    return self.range
end

function ProximitySensorPack:callForAllSensors(func, ...)
    for _, sensor in ipairs(self.sensors) do
        func(sensor, ...)
    end
end

function ProximitySensorPack:update()

    self:callForAllSensors(ProximitySensor.update)

    -- show the position of the pack
    if CpDebug:isChannelActive(CpDebug.DBG_TRAFFIC, self.vehicle) then
        local x, y, z = getWorldTranslation(self.node)
        local x1, y1, z1 = localToWorld(self.node, 0, 0, 0.5)
        DebugUtil.drawDebugLine(x, y, z, x, y + 3, z, 0, 0, 1)
        DebugUtil.drawDebugLine(x, y + 1, z, x1, y1 + 1, z1, 0, 1, 0)
    end
end

function ProximitySensorPack:enable()
    self:callForAllSensors(ProximitySensor.enable)
end

function ProximitySensorPack:disable()
    self:callForAllSensors(ProximitySensor.disable)
end

function ProximitySensorPack:setIgnoredVehicle(vehicle, ttlMs)
    self:callForAllSensors(ProximitySensor.setIgnoredVehicle, vehicle, ttlMs)
end

--- Gets the closest hit of a proximity sensor.
---@return number distance of closest hit in meters
---@return table|nil closest root vehicle
---@return table|nil closest object
---@return boolean terrain was hit
---@return number average direction of the obstacle in degrees, > 0 right, < 0 left
---@return number
function ProximitySensorPack:getClosestObjectDistanceAndRootVehicle()
    -- make sure we have the latest info, the sensors will make sure they only raycast once per loop
    self:update()
    local closestDistance = math.huge
    local closestRootVehicle, closestObject, hitTerrain
    -- weighted average over the different direction, weight depends on how close the closest object is
    local totalWeight, totalDegs, totalDistance = 0, 0, 0
    for _, sensor in ipairs(self.sensors) do
        local d = sensor:getClosestObjectDistance()
        if d < self.range then
            local weight = (self.range - d) / self.range
            totalWeight = totalWeight + weight
            -- the direction should be in the tractor's system, therefore we need to compensate here with the
            -- current rotation of the sensor
            totalDegs = totalDegs + weight * sensor:getRotationDeg()
            totalDistance = totalDistance + weight * d
        end
        if d < closestDistance then
            closestDistance = d
            closestRootVehicle = sensor:getClosestRootVehicle()
            closestObject = sensor:getClosestObject()
            hitTerrain = sensor:hasHitTerrain()
        end
    end
    if closestRootVehicle == self.vehicle then
        self:adjustForwardPosition()
    end
    return closestDistance, closestRootVehicle, closestObject, hitTerrain,
        CpMathUtil.divide(totalDegs, totalWeight), CpMathUtil.divide(totalDistance, totalWeight)
end

function ProximitySensorPack:disableRightSide()
    for _, sensor in ipairs(self.sensors) do
        if sensor:getBaseRotationDeg() <= 0 then
            sensor:disable()
        end
    end
end

function ProximitySensorPack:enableRightSide()
    for _, sensor in ipairs(self.sensors) do
        if sensor:getBaseRotationDeg() <= 0 then
            sensor:enable()
        end
    end
end

function ProximitySensorPack:disableLeftSide()
    for _, sensor in ipairs(self.sensors) do
        if sensor:getBaseRotationDeg() > 0 then
            sensor:disable()
        end
    end
end

function ProximitySensorPack:enableLeftSide()
    for _, sensor in ipairs(self.sensors) do
        if sensor:getBaseRotationDeg() > 0 then
            sensor:enable()
        end
    end
end

---@class ForwardLookingProximitySensorPack : ProximitySensorPack
ForwardLookingProximitySensorPack = CpObject(ProximitySensorPack)

--- Pack looking forward, all sensors are in the middle of the vehicle
function ForwardLookingProximitySensorPack:init(vehicle, node, range, height)
    ProximitySensorPack.init(self, 'forward', vehicle, node, range, height,
            { 0, 15, 30, 60, 80, -15, -30, -60, -80 },
            { 0, 0, 0, 0, 0, 0, 0, 0, 0 })
end

---@class WideForwardLookingProximitySensorPack : ProximitySensorPack
WideForwardLookingProximitySensorPack = CpObject(ProximitySensorPack)

--- Pack looking forward, but sensors distributed evenly through the width of the vehicle
function WideForwardLookingProximitySensorPack:init(vehicle, node, range, height, width, directionsDeg)
    CpUtil.debugVehicle(CpDebug.DBG_TRAFFIC, vehicle, 'Creating wide forward proximity sensor %.1fm', width)
    directionsDeg = directionsDeg or { 10, 8, 5, 3, 0, -3, -5, -8, -10 }
    local xOffsets = self:getXOffsets(width, #directionsDeg)
    ProximitySensorPack.init(self, 'wideForward', vehicle, node, range, height,
            directionsDeg, xOffsets, true)
end

---@class WideBackwardLookingProximitySensorPack : ProximitySensorPack
WideBackwardLookingProximitySensorPack = CpObject(ProximitySensorPack)

--- Pack looking backward, but sensors distributed evenly through the width of the vehicle
function WideBackwardLookingProximitySensorPack:init(vehicle, node, range, height, width, rotationEnabled)
    CpUtil.debugVehicle(CpDebug.DBG_TRAFFIC, vehicle, 'Creating wide backward proximity sensor %.1fm', width)
    local directionsDeg = { -190, -188, -185, -183, 180, 183, 185, 188, 190 }
    local xOffsets = self:getXOffsets(width, #directionsDeg)
    ProximitySensorPack.init(self, 'wideBackward', vehicle, node, range, height,
            directionsDeg, xOffsets, rotationEnabled)
end

---@class BackwardLookingProximitySensorPack : ProximitySensorPack
BackwardLookingProximitySensorPack = CpObject(ProximitySensorPack)

function BackwardLookingProximitySensorPack:init(vehicle, node, range, height)
    CpUtil.debugVehicle(CpDebug.DBG_TRAFFIC, vehicle, 'Creating backward proximity sensor')
    ProximitySensorPack.init(self, 'backward', vehicle, node, range, height,
            { 120, 150, 180, -150, -120 },
            { 0, 0, 0, 0, 0 })
end

---@class SingleForwardLookingProximitySensorPack : ProximitySensorPack
SingleForwardLookingProximitySensorPack = CpObject(ProximitySensorPack)

function SingleForwardLookingProximitySensorPack:init(vehicle, node, range, height)
    CpUtil.debugVehicle(CpDebug.DBG_TRAFFIC, vehicle, 'Creating single forward proximity sensor')
    ProximitySensorPack.init(self, 'singleForward', vehicle, node, range, height,
            { 0 }, { 0 }, false)
end

---@class SingleBackwardLookingProximitySensorPack : ProximitySensorPack
SingleBackwardLookingProximitySensorPack = CpObject(ProximitySensorPack)

function SingleBackwardLookingProximitySensorPack:init(vehicle, node, range, height)
    CpUtil.debugVehicle(CpDebug.DBG_TRAFFIC, vehicle, 'Creating single backward proximity sensor')
    ProximitySensorPack.init(self, 'singleBackward', vehicle, node, range, height,
            { 180 }, { 0 }, false)
end

------------------------------------------------------------------------------------------------------------------------
--- Proximity Fence
------------------------------------------------------------------------------------------------------------------------

--- A proximity sensor raycasting vertically to find obstacles/vehicles
---@class VerticalProximitySensor : ProximitySensor
VerticalProximitySensor = CpObject(ProximitySensor)
-- raycast vertically up from just above the ground
VerticalProximitySensor.minHeightAboveGround = 0.1

---@param node number
---@param xOffset number distance sideways from the node
---@param zOffset number distance forward from the node
---@param height number the maximum height of the sensor ray, from the ground (it is a vertical line, from just above
--- the ground to this height
---@param vehicle table
function VerticalProximitySensor:init(node, xOffset, zOffset, height, vehicle)
    self.node = node
    self.xOffset = xOffset
    self.zOffset = zOffset
    self.range = math.sqrt(xOffset * xOffset + zOffset * zOffset)
    CpUtil.debugVehicle(CpDebug.DBG_TRAFFIC, vehicle, 'Vertical proximity sensor dx %.1f, dz %.1f', xOffset, zOffset)
    self.height = height or 1
    self.lastUpdateLoopIndex = 0
    self.enabled = true
    self.vehicle = vehicle
    -- vehicles can only be ignored temporarily
    self.ignoredVehicle = CpTemporaryObject()
end

function VerticalProximitySensor:update()
    -- already updated in this loop, no need to raycast again
    if g_updateLoopIndex == self.lastUpdateLoopIndex then
        return
    end
    self.lastUpdateLoopIndex = g_updateLoopIndex

    local x, _, z = localToWorld(self.node, self.xOffset, 0, self.zOffset)
    local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z)
    self.distanceOfClosestObject = math.huge
    self.objectId = nil
    self.hitTerrain = false
    if self.enabled then
        local raycastMask = CpUtil.getDefaultCollisionFlags()
        -- straight up from 10 cm above the ground to height
        raycastClosest(x, y + self.minHeightAboveGround, z, 0, 1, 0,
                self.height - self.minHeightAboveGround,
                'raycastCallback', self, raycastMask)
        if CpDebug:isChannelActive(CpDebug.DBG_TRAFFIC, self.vehicle) then
            DebugUtil.drawDebugLine(x, y + self.minHeightAboveGround, z, x, y + self.height - self.minHeightAboveGround, z, 1, 1, 0)
        end
    end
    if CpDebug:isChannelActive(CpDebug.DBG_TRAFFIC, self.vehicle) and self.distanceOfClosestObject < math.huge then
        local green = self.distanceOfClosestObject / self.range
        local red = 1 - green
        DebugUtil.drawDebugLine(x, y + self.height, z, self.closestObjectX, self.closestObjectY, self.closestObjectZ, red, green, 0)
    end
end

function VerticalProximitySensor:raycastCallback(objectId, x, y, z, distance)
    local object = g_currentMission:getNodeObject(objectId)
    if object and object.getRootVehicle and object:getRootVehicle() == self.ignoredVehicle:get() then
        -- ignore this vehicle
        return
    end
    self.distanceOfClosestObject = self.range
    self.objectId = objectId
    self.hitTerrain = objectId == g_currentMission.terrainRootNode
    self.closestObjectX, self.closestObjectY, self.closestObjectZ = x, y, z
end

---@class ProximityFence : ProximitySensorPack
ProximityFence = CpObject(ProximitySensorPack)

--- A proximity fence is a series of vertical proximity sensors in a row (just like the posts of a fence).
---@param vehicle table vehicle we attach the sensor to, used only to rotate the sensor with the steering angle
---@param node number node (front or back) to attach the sensor to
---@param range number range of the sensor in meters, that is, the distance of the fence from node
---@param height number height of the fence (of the individual vertical sensors)
---@param width number width of the fence
---@param nSensors number|nil number of sensors, these will be distributed along the width, default 5
function ProximityFence:init(vehicle, node, range, height, width, nSensors)
    ---@type VerticalProximitySensor[]
    self.sensors = {}
    self.vehicle = vehicle
    self.range = range
    self.height = height
    self.width = width
    self.name = 'fence'
    self.node = getChild(node, self.name)
    if self.node <= 0 then
        -- node with this name does not yet exist
        -- add a separate node for the pack (so we can move it independently from 'node'
        self.node = CpUtil.createNode(self.name, 0, 0, 0, node)
    end
    -- reset it on the parent node
    setTranslation(self.node, 0, 0, 0)
    setRotation(self.node, 0, 0, 0)
    self.xOffsets = self:getXOffsets(self.width, nSensors or 5)
    for _, xOffset in ipairs(self.xOffsets) do
        table.insert(self.sensors, VerticalProximitySensor(self.node, xOffset or 0, self.range, self.height, vehicle))
    end
end

function ProximityFence:update()
    self:callForAllSensors(VerticalProximitySensor.update)
end

--- Gets the closest hit of a proximity sensor.
---@return number distance of closest hit in meters
---@return table|nil closest root vehicle
---@return table|nil closest object
---@return boolean terrain was hit
---@return number xOffset of the closest obstacle in meters,  left > 0, right < 0
function ProximityFence:getClosestObjectDistanceAndRootVehicle()
    -- make sure we have the latest info, the sensors will make sure they only raycast once per loop
    self:update()
    local closestDistance = math.huge
    local closestRootVehicle, closestObject, hitTerrain, closestXOffset
    for i, sensor in ipairs(self.sensors) do
        local d = sensor:getClosestObjectDistance()
        if d < closestDistance then
            closestDistance = d
            closestXOffset = self.xOffsets[i]
            closestRootVehicle = sensor:getClosestRootVehicle()
            closestObject = sensor:getClosestObject()
            hitTerrain = sensor:hasHitTerrain()
        end
    end
    if closestRootVehicle == self.vehicle then
        self:adjustForwardPosition()
    end
    return closestDistance, closestRootVehicle, closestObject, hitTerrain, closestXOffset
end

function ProximityFence:adjustForwardPosition()
    local x, y, z = getTranslation(self.node)
    self:debug('moving proximity sensor %s %.1f so it does not interfere with own vehicle', self.name, 0.1)
    -- move pack forward/back a bit
    setTranslation(self.node, x, y, z + 0.1)
end
