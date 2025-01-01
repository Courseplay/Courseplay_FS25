--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2019 Peter Vaiko

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
--- Development helper utilities to easily test and diagnose things.
--- To test the pathfinding:
--- 1. mark the start location/heading with Alt + <
--- 2. mark the goal location/heading with Alt + >
--- 3. watch the path generated ...
--- 4. use Ctrl + > to regenerate the path
---
--- Also showing field/fruit/collision information when walking around
DevHelper = CpObject()

DevHelper.overlapBoxWidth = 3
DevHelper.overlapBoxHeight = 3
DevHelper.overlapBoxLength = 5

function DevHelper:init()
    self.data = {}
    self.isEnabled = false
end

function DevHelper:debug(...)
    CpUtil.info(string.format(...))
end

--- Makes sure deleting of the selected vehicle can be detected
function DevHelper:removedSelectedVehicle()
    self.vehicle = nil
end

function DevHelper:update()
    if not self.isEnabled then return end

    local lx, lz, hasCollision, vehicle

    -- make sure not calling this for something which does not have courseplay installed (only ones with spec_aiVehicle)
    if CpUtil.getCurrentVehicle() and CpUtil.getCurrentVehicle().spec_cpAIWorker then
        if self.vehicle ~= CpUtil.getCurrentVehicle() then
            if self.vehicle then
                self.vehicle:removeDeleteListener(self, "removedSelectedVehicle")
            end
            --self.vehicleData = PathfinderUtil.VehicleData(CpUtil.getCurrentVehicle(), true)
        end
        self.vehicle = CpUtil.getCurrentVehicle()
        self.vehicle:addDeleteListener(self, "removedSelectedVehicle")
        self.node = CpUtil.getCurrentVehicle():getAIDirectionNode()
        lx, _, lz = localDirectionToWorld(self.node, 0, 0, 1)

    else
        -- camera node looks backwards so need to flip everything by 180 degrees
        self.node = g_currentMission.playerSystem:getLocalPlayer():getCurrentCameraNode()
        lx, _, lz = localDirectionToWorld(self.node, 0, 0, -1)
    end

    self.yRot = math.atan2( lx, lz )
    self.data.xyDeg = math.deg(CpMathUtil.angleFromGame(self.yRot))
    self.data.yRotDeg = math.deg(self.yRot)
    local _, yRot, _ = getWorldRotation(self.node)
    self.data.yRotFromRotation = math.deg(yRot)
    self.data.yRotDeg2 = math.deg(MathUtil.getYRotationFromDirection(lx, lz))
    self.data.x, self.data.y, self.data.z = getWorldTranslation(self.node)
	-- y is always on the ground
    self.data.y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, self.data.x, self.data.y, self.data.z)

    self.data.hasFruit, self.data.fruitValue, self.data.fruit = PathfinderUtil.hasFruit(self.data.x, self.data.z, 1, 1)

    self.data.fieldId =  CpFieldUtil.getFieldIdAtWorldPosition(self.data.x, self.data.z)
    --self.data.owned =  PathfinderUtil.isWorldPositionOwned(self.data.x, self.data.z)
	self.data.farmlandId = g_farmlandManager:getFarmlandIdAtWorldPosition(self.data.x, self.data.z)

    self.data.isOnField, self.data.densityBits = FSDensityMapUtil.getFieldDataAtWorldPosition(self.data.x, self.data.y, self.data.z)
    self.data.isOnFieldArea, self.data.onFieldArea, self.data.totalOnFieldArea = CpFieldUtil.isOnFieldArea(self.data.x, self.data.z)
    self.data.nx, self.data.ny, self.data.nz = getTerrainNormalAtWorldPos(g_currentMission.terrainRootNode, self.data.x, self.data.y, self.data.z)

    local collisionMask = CpUtil.getDefaultCollisionFlags() + CollisionFlag.TERRAIN_DELTA
    self.data.collidingShapes = {}
    overlapBox(self.data.x, self.data.y + 0.2 + DevHelper.overlapBoxHeight / 2, self.data.z, 0, self.yRot, 0,
            DevHelper.overlapBoxWidth / 2, DevHelper.overlapBoxHeight / 2, DevHelper.overlapBoxLength / 2,
            "overlapBoxCallback", self, collisionMask, true, true, true, true)

end

function DevHelper:overlapBoxCallback(transformId, subShapeIndex)
    local collidingObject = g_currentMission.nodeToObject[transformId]
    local text = tostring(subShapeIndex)
    for key, classId in pairs(ClassIds) do
        if getHasClassId(transformId, classId) then
            text = text .. ' ' .. key
        end
    end
    for key, rigidBodyType in pairs(RigidBodyType) do
        if getRigidBodyType(transformId) == rigidBodyType then
            text = text .. ' ' .. key
        end
    end
    if collidingObject then
        if collidingObject.getRootVehicle then
            text = text .. ' vehicle ' .. collidingObject:getName()
        else
			if collidingObject:isa(Bale) then
				text = text .. ' Bale ' .. tostring(collidingObject.id) .. ' ' .. tostring(collidingObject.nodeId)
			else
            	text = text .. ' ' .. (collidingObject.getName and collidingObject:getName() or 'N/A')
			end
        end
    end
    for i = 0, getNumOfUserAttributes(transformId) - 1 do
        local type, name, x = getUserAttributeByIndex(transformId, i)
        text = text .. ' ' .. tostring(i) .. ':' .. (type or '?') .. '/' .. (name or '?') .. '/' .. (x or '?')
    end
    table.insert(self.data.collidingShapes, text)
end

-- Left-Alt + , (<) = mark current position as start for pathfinding
-- Left-Alt + , (<) = mark current position as start for pathfinding
-- Left-Alt + . (>) = mark current position as goal for pathfinding
-- Left-Ctrl + . (>) = start pathfinding from marked start to marked goal
-- Left-Ctrl + , (<) = mark current field as field for pathfinding
-- Left-Alt + Space = save current vehicle position
-- Left-Ctrl + Space = restore current vehicle position
function DevHelper:keyEvent(unicode, sym, modifier, isDown)
    if not self.isEnabled then return end
    if bitAND(modifier, Input.MOD_LALT) ~= 0 and isDown and sym == Input.KEY_period then
        -- Left Alt + > mark goal
        self.goal = State3D(self.data.x, -self.data.z, CpMathUtil.angleFromGameDeg(self.data.yRotDeg))

        local x, y, z = getWorldTranslation(self.node)
        local _, yRot, _ = getRotation(self.node)
        if self.goalNode then
            setTranslation( self.goalNode, x, y, z );
            setRotation( self.goalNode, 0, yRot, 0);
        else
            self.goalNode = courseplay.createNode('devhelper', x, z, yRot)
        end

        self:debug('Goal %s', tostring(self.goal))
        --self:startPathfinding()
    elseif bitAND(modifier, Input.MOD_LCTRL) ~= 0 and isDown and sym == Input.KEY_period then
        -- Left Ctrl + > find path
        self:debug('Calculate')
        self:startPathfinding()
    elseif bitAND(modifier, Input.MOD_LCTRL) ~= 0 and isDown and sym == Input.KEY_comma then
        self.fieldNumForPathfinding = CpFieldUtil.getFieldNumUnderNode(self.node)
        self:debug('Set field %d for pathfinding', self.fieldNumForPathfinding)
    elseif bitAND(modifier, Input.MOD_LALT) ~= 0 and isDown and sym == Input.KEY_space then
        -- save vehicle position
        CpUtil.getCurrentVehicle().vehiclePositionData = {}
        DevHelper.saveVehiclePosition(CpUtil.getCurrentVehicle(), CpUtil.getCurrentVehicle().vehiclePositionData)
    elseif bitAND(modifier, Input.MOD_LCTRL) ~= 0 and isDown and sym == Input.KEY_space then
        -- restore vehicle position
        DevHelper.restoreVehiclePosition(CpUtil.getCurrentVehicle())
    elseif bitAND(modifier, Input.MOD_LALT) ~= 0 and isDown and sym == Input.KEY_c then
        CpFieldUtil.detectFieldBoundary(self.data.x, self.data.z, true)
    elseif bitAND(modifier, Input.MOD_LALT) ~= 0 and isDown and sym == Input.KEY_d then
        self.vehicle:cpDetectFieldBoundary(self.data.x, self.data.z)
    elseif bitAND(modifier, Input.MOD_LALT) ~= 0 and isDown and sym == Input.KEY_g then
        local points = CpFieldUtil.detectFieldBoundary(self.data.x, self.data.z, true)
        self:debug('Generate course')

        local vehicle = CpUtil.getCurrentVehicle()
        local settings = CpUtil.getCurrentVehicle():getCourseGeneratorSettings()
        local width, offset, _, _ = WorkWidthUtil.getAutomaticWorkWidthAndOffset(vehicle)
        settings.workWidth:refresh()
        settings.workWidth:setFloatValue(width)
        vehicle:getCpSettings().toolOffsetX:setFloatValue(offset)

        local status, ok, course = CourseGeneratorInterface.generate(points,
                {x = self.data.x, z = self.data.z},
                vehicle, settings)
        if ok then
            self.course = course
        end
    elseif bitAND(modifier, Input.MOD_LALT) ~= 0 and isDown and sym == Input.KEY_n then
        self:togglePpcControlledNode()
    end
end

function DevHelper:toggle()
    self.isEnabled = not self.isEnabled
end

--- Show the data in a table in the order we want it (quick AI generated boilerplate)
function DevHelper:fillDisplayData()
    local displayData = {}
    table.insert(displayData, {name = 'x', value = self.data.x})
    table.insert(displayData, {name = 'y', value = self.data.y})
    table.insert(displayData, {name = 'z', value = self.data.z})
    table.insert(displayData, {name = 'yRotDeg', value = self.data.yRotDeg})
    table.insert(displayData, {name = 'yRotDeg2', value = self.data.yRotDeg2})
    table.insert(displayData, {name = 'yRotFromRotation', value = self.data.yRotFromRotation})
    table.insert(displayData, {name = 'xyDeg', value = self.data.xyDeg})
    table.insert(displayData, {name = 'hasFruit', value = self.data.hasFruit})
    table.insert(displayData, {name = 'fruitValue', value = self.data.fruitValue})
    table.insert(displayData, {name = 'fruit', value = self.data.fruit})
    table.insert(displayData, {name = 'fieldId', value = self.data.fieldId})
    table.insert(displayData, {name = 'farmlandId', value = self.data.farmlandId})
    table.insert(displayData, {name = 'isOnField', value = self.data.isOnField})
    table.insert(displayData, {name = 'densityBits', value = self.data.densityBits})
    table.insert(displayData, {name = 'isOnFieldArea', value = self.data.isOnFieldArea})
    table.insert(displayData, {name = 'onFieldArea', value = self.data.onFieldArea})
    table.insert(displayData, {name = 'totalOnFieldArea', value = self.data.totalOnFieldArea})
    for i = 1, #self.data.collidingShapes do
        table.insert(displayData, {name = 'collidingShapes ' .. i, value = self.data.collidingShapes[i]})
    end
    return displayData
end

function DevHelper:draw()
    if not self.isEnabled then return end
    DebugUtil.renderTable(0.3, 0.95, 0.013, self:fillDisplayData(), 0.05)

    self:showFillNodes()
    self:showAIMarkers()

    self:showDriveData()

    CourseGenerator.drawDebugPolylines()
    CourseGenerator.drawDebugPoints()

	if not self.tNode then
		self.tNode = createTransformGroup("devhelper")
		link(g_currentMission.terrainRootNode, self.tNode)
	end

	DebugUtil.drawDebugNode(self.tNode, 'Terrain normal')
	--local nx, ny, nz = getTerrainNormalAtWorldPos(g_currentMission.terrainRootNode, self.data.x, self.data.y, self.data.z)

	--local x, y, z = localToWorld(self.node, 0, -1, -3)

	--drawDebugLine(x, y, z, 1, 1, 1, x + nx, y + ny, z + nz, 1, 1, 1)
	DebugUtil.drawOverlapBox(self.data.x, self.data.y + 0.2 + DevHelper.overlapBoxHeight / 2, self.data.z, 0, self.yRot, 0,
            DevHelper.overlapBoxWidth / 2, DevHelper.overlapBoxHeight / 2, DevHelper.overlapBoxLength / 2,
            0, 100, 0)
    PathfinderUtil.showOverlapBoxes()
    g_fieldScanner:draw()
    if self.vehicle then
        self.vehicle:cpDrawFieldPolygon()
    end
end

function DevHelper:showFillNodes()
    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if SpecializationUtil.hasSpecialization(Trailer, vehicle.specializations) then
            DebugUtil.drawDebugNode(vehicle.rootNode, 'Root node')
            local fillUnits = vehicle:getFillUnits()
            for i = 1, #fillUnits do
                local fillRootNode = vehicle:getFillUnitExactFillRootNode(i)
                if fillRootNode then DebugUtil.drawDebugNode(fillRootNode, 'Fill node ' .. tostring(i)) end
                local autoAimNode = vehicle:getFillUnitAutoAimTargetNode(i)
                if autoAimNode then DebugUtil.drawDebugNode(autoAimNode, 'Auto aim node ' .. tostring(i)) end
            end
        end
    end
end

function DevHelper:showAIMarkers()

    if not self.vehicle then return end

    local function showAIMarkersOfObject(object)
        if object.getAIMarkers then
            local aiLeftMarker, aiRightMarker, aiBackMarker = object:getAIMarkers()
            if aiLeftMarker then
                DebugUtil.drawDebugNode(aiLeftMarker, object:getName() .. ' AI Left')
            end
            if aiRightMarker then
                DebugUtil.drawDebugNode(aiRightMarker, object:getName() .. ' AI Right')
            end
            if aiBackMarker then
                DebugUtil.drawDebugNode(aiBackMarker, object:getName() .. ' AI Back')
            end
        end
        if object.getAISizeMarkers then
            local aiSizeLeftMarker, aiSizeRightMarker, aiSizeBackMarker = object:getAISizeMarkers()
            if aiSizeLeftMarker then
                DebugUtil.drawDebugNode(aiSizeLeftMarker, object:getName() .. ' AI Size Left')
            end
            if aiSizeRightMarker then
                DebugUtil.drawDebugNode(aiSizeRightMarker, object:getName() .. ' AI Size Right')
            end
            if aiSizeBackMarker then
                DebugUtil.drawDebugNode(aiSizeBackMarker, object:getName() .. ' AI Size Back')
            end
        end
        DebugUtil.drawDebugNode(object.rootNode, object:getName() .. ' root')
    end

    showAIMarkersOfObject(self.vehicle)
    -- draw the Giant's supplied AI markers for all implements
    local implements = AIUtil.getAllAIImplements(self.vehicle)
    if implements then
        for _, implement in ipairs(implements) do
            showAIMarkersOfObject(implement.object)
        end
    end

    local frontMarker, backMarker = Markers.getMarkerNodes(self.vehicle)
    CpUtil.drawDebugNode(frontMarker, false, 3)
    CpUtil.drawDebugNode(backMarker, false, 3)

    local directionNode = self.vehicle:getAIDirectionNode()
    if directionNode then 
        CpUtil.drawDebugNode(self.vehicle:getAIDirectionNode(), false , 4, "AiDirectionNode")
    end
    local reverseNode = self.vehicle:getAIReverserNode()
    if reverseNode then 
        CpUtil.drawDebugNode(reverseNode, false , 4.5, "AiReverseNode")
    end
    local steeringNode = self.vehicle:getAISteeringNode()
    if steeringNode then 
        CpUtil.drawDebugNode(steeringNode, false , 5, "AiSteeringNode")
    end
    local articulatedAxisReverseNode = AIUtil.getArticulatedAxisVehicleReverserNode(self.vehicle)
    if articulatedAxisReverseNode then 
        CpUtil.drawDebugNode(articulatedAxisReverseNode, false , 5.5, "AiArticulatedAxisReverseNode")
    end   
end

function DevHelper:togglePpcControlledNode()
    if not self.vehicle then return end
    local strategy = self.vehicle:getCpDriveStrategy()
    if not strategy then return end
    if strategy.ppc:getControlledNode() == AIUtil.getReverserNode(self.vehicle) then
        strategy.pcc:resetControlledNode()
    else
        strategy.ppc:setControlledNode(AIUtil.getReverserNode(self.vehicle))
    end
end

function DevHelper:showDriveData()
    if not self.vehicle then return end
    local strategy = self.vehicle:getCpDriveStrategy()
    if not strategy then return end
    strategy.ppc:update()
    strategy.reverser:getDriveData()
end

-- make sure to recreate the global dev helper whenever this script is (re)loaded
g_devHelper = DevHelper()

