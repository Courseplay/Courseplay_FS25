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

function DevHelper:init()
    self.data = {}
    self.isEnabled = false
    self.consoleCommands = CpConsoleCommands(self)
end

function DevHelper:delete()
    self.consoleCommands:delete()
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
--    self.data.fieldNum = courseplay.fields:getFieldNumForPosition(self.data.x, self.data.z)

    self.data.hasFruit, self.data.fruitValue, self.data.fruit = PathfinderUtil.hasFruit(self.data.x, self.data.z, 1, 1)

    self.data.landId =  CpFieldUtil.getFieldIdAtWorldPosition(self.data.x, self.data.z)
    --self.data.owned =  PathfinderUtil.isWorldPositionOwned(self.data.x, self.data.z)
	self.data.farmlandId = g_farmlandManager:getFarmlandIdAtWorldPosition(self.data.x, self.data.z)
	self.data.farmland = g_farmlandManager:getFarmlandAtWorldPosition(self.data.x, self.data.z)
--    self.data.fieldAreaPercent = 100 * self.fieldArea / self.totalFieldArea

	local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, self.data.x, self.data.y, self.data.z)
    self.data.isOnField, self.data.densityBits = FSDensityMapUtil.getFieldDataAtWorldPosition(self.data.x, y, self.data.z)
    self.data.isOnFieldArea, self.data.onFieldArea, self.data.totalOnFieldArea = CpFieldUtil.isOnFieldArea(self.data.x, self.data.z)
    self.data.nx, self.data.ny, self.data.nz = getTerrainNormalAtWorldPos(g_currentMission.terrainRootNode, self.data.x, y, self.data.z)

    local collisionMask = CollisionFlag.DEFAULT + CollisionFlag.TREE + CollisionFlag.DYNAMIC_OBJECT + CollisionFlag.VEHICLE + CollisionFlag.TERRAIN_DELTA
    self.data.collidingShapes = ''
    overlapBox(self.data.x, self.data.y + 0.2, self.data.z, 0, self.yRot, 0, 1.6, 1, 8, "overlapBoxCallback", self, collisionMask, true, true, true)

end

function DevHelper:overlapBoxCallback(transformId)
    local collidingObject = g_currentMission.nodeToObject[transformId]
    local text
    if collidingObject then
        if collidingObject.getRootVehicle then
            text = 'vehicle' .. collidingObject:getName()
        else
			if collidingObject:isa(Bale) then
				text = 'Bale ' .. tostring(collidingObject.id) .. ' ' .. tostring(collidingObject.nodeId)
			else
            	text = collidingObject.getName and collidingObject:getName() or 'N/A'
			end
        end
    else
        text = ''
        for key, classId in pairs(ClassIds) do
            if getHasClassId(transformId, classId) then
                text = text .. ' ' .. key
            end
        end
    end


    self.data.collidingShapes = self.data.collidingShapes .. '|' .. text
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
        self:debug('Finding contour of current field')
        local valid, points = g_fieldScanner:findContour(self.data.x, self.data.z)
    elseif bitAND(modifier, Input.MOD_LALT) ~= 0 and isDown and sym == Input.KEY_g then
        local valid, points = g_fieldScanner:findContour(self.data.x, self.data.z)
        self:debug('Generate course')
        local status, ok, course = CourseGeneratorInterface.generate(points,
                {x = self.data.x, z = self.data.z},
                0, 6, 6, 1, true)
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

function DevHelper:draw()
    if not self.isEnabled then return end
    local data = {}
    for key, value in pairs(self.data) do
        table.insert(data, {name = key, value = value})
    end
    DebugUtil.renderTable(0.65, 0.27, 0.013, data, 0.05)

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
	--local xRot, yRot, zRot = getWorldRotation(self.tNode)
	--DebugUtil.drawOverlapBox(self.data.x, self.data.y, self.data.z, xRot, yRot, zRot, 4, 1, 4, 0, 100, 0)
    PathfinderUtil.showOverlapBoxes()
    g_fieldScanner:draw()
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
if g_devHelper then
    g_devHelper:delete()
end

g_devHelper = DevHelper()

