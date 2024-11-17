--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2018 Peter Vajko

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

---@class Waypoint
Waypoint = CpObject()
Waypoint.xmlKey = ".wp"

-- Waypoint is a friend class for the Course, so it can access the private members without
-- getters. The Waypoint has getters only for other classes.
-- constructor from another waypoint
---@param wp Waypoint
function Waypoint:init(wp)
	-- we initialize explicitly, no table copy as we want to have
	-- full control over what is used in this object
	self.x = wp.x or 0
	self.z = wp.z or 0
	self.y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, self.x, 0, self.z)
	-- keep a copy of the generated attributes.
	---@type CourseGenerator.WaypointAttributes
	self.attributes = wp.attributes and wp.attributes:clone() or CourseGenerator.WaypointAttributes()
	self.angle = wp.angle or nil
	self.radius = wp.radius or nil
	self.rev = wp.rev or wp.reverse or false
	self.rev = self.rev or wp.gear and wp.gear == Gear.Backward
	-- dynamically added/calculated properties
	self.useTightTurnOffset = wp.useTightTurnOffset
	self.turnControls = table.clone(wp.turnControls)
	self.dToNext = wp.dToNext
	self.yRot = wp.yRot
	--- Set, when generated for a multi tool course
	self.usePathfinderToThisWaypoint = wp.usePathfinderToThisWaypoint
	self.usePathfinderToNextWaypoint = wp.usePathfinderToNextWaypoint
	self.headlandTransition = wp.headlandTransition
end

--- Set from a generated waypoint (output of the course generator)
---@param wp Vertex
function Waypoint.initFromGeneratedWp(wp)
	local waypoint = Waypoint({})
	waypoint.x = wp.x
	waypoint.z = -wp.y
	waypoint.y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, waypoint.x, 0, waypoint.z)
	---@type CourseGenerator.WaypointAttributes
	waypoint.attributes = wp:getAttributes():clone()
	return waypoint
end

function Waypoint.registerXmlSchema(schema, baseKey)
	local key = baseKey .. Waypoint.xmlKey .. "(?)"
	schema:register(XMLValueType.VECTOR_3, key .. "#position", "Position")
	schema:register(XMLValueType.BOOL, key .. "#rev", "Reverse")
	CourseGenerator.WaypointAttributes.registerXmlSchema(schema, key)
end

function Waypoint:setXmlValue(xmlFile, baseKey, i)
	local key = string.format("%s%s(%d)", baseKey, Waypoint.xmlKey, i - 1)
	-- round to two decimal places, to make the file smaller, centimeter precision is enough
	xmlFile:setValue(key .. "#position", math.floor(self.x * 100) / 100,
			math.floor(self.y * 100) / 100, math.floor(self.z * 100) / 100)
	CpUtil.setXmlValue(xmlFile, key .. "#rev", self.rev)
	self.attributes:setXmlValue(xmlFile, key)
end

function Waypoint:writeStream(streamId)
	streamWriteFloat32(streamId, self.x)
	streamWriteFloat32(streamId, self.z)
	streamWriteFloat32(streamId, self.y)
	CpUtil.streamWriteBool(streamId, self.rev)
	self.attributes:writeStream(streamId)
end

--- Set from a saved waypoint in a xml file.
function Waypoint.createFromXmlFile(xmlFile, key)
	local waypoint = Waypoint({})
	waypoint.x, waypoint.y, waypoint.z = xmlFile:getValue(key .. '#position')
	waypoint.rev = xmlFile:getValue(key .. '#rev')
	waypoint.attributes = CourseGenerator.WaypointAttributes.createFromXmlFile(xmlFile, key)
	return waypoint
end

function Waypoint.createFromStream(streamId)
	local waypoint = Waypoint({})
	waypoint.x = streamReadFloat32(streamId)
	waypoint.z = streamReadFloat32(streamId)
	waypoint.y = streamReadFloat32(streamId)
	waypoint.rev = CpUtil.streamReadBool(streamId)
	waypoint.attributes = CourseGenerator.WaypointAttributes.createFromStream(streamId)
	return waypoint
end

--- Read legacy format (which used custom serialization instead of XML schema)
function Waypoint.initFromXmlFileLegacyFormat(data)
	local waypoint = Waypoint({})
	waypoint.x = data[1]
	waypoint.z = data[2]
	waypoint.y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, waypoint.x, 0, waypoint.z)
	local turnStart = data[3]
	waypoint.attributes.rowEnd = turnStart
	local turnEnd = data[4]
	waypoint.attributes.rowStart = turnEnd
	waypoint.attributes.onConnectingPath = data[5]
	-- saved course backwards compatibility, for when the headland numbers were negative
	waypoint.attributes.headlandPassNumber = data[6] and math.abs(data[6])
	waypoint.attributes.rowNumber = data[7]
	local ridgeMarker = data[8]
	if ridgeMarker == RidgeMarkerController.RIDGE_MARKER_LEFT then
		waypoint.attributes.leftSideWorked = false
		waypoint.attributes.rightSideWorked = true
	elseif ridgeMarker == RidgeMarkerController.RIDGE_MARKER_RIGHT then
		waypoint.attributes.rightSideWorked = false
		waypoint.attributes.leftSideWorked = true
	end
	waypoint.rev = data[9]
	waypoint.attributes.headlandTurn = data[10]
	waypoint.attributes.usePathfinderToNextWaypoint = data[11]
	waypoint.attributes.usePathfinderToThisWaypoint = data[12]
	waypoint.headlandTransition = data[13]
	if not waypoint.attributes.headlandTurn then
		-- guess where we have headland turns, rowEnd and rowStart used to be turnStart and turnEnd, respectively,
		if waypoint.attributes.headlandPassNumber and waypoint.attributes.headlandPassNumber > 0 then
			-- old courses have the turnEnd at the corner
			if turnEnd then
				waypoint.attributes.headlandTurn = true
			end
			-- waypoint on headland has no row start/end
			waypoint.attributes.rowEnd = nil
			waypoint.attributes.rowStart = nil
		end
	end
	return waypoint
end

--- Get the (original, non-offset) position of a waypoint
---@return number, number, number x, y, z
function Waypoint:getPosition()
	return self.x, self.y, self.z
end

--- Get the offset position of a waypoint
---@param offsetX number left/right offset (right +, left -)
---@param offsetZ number forward/backward offset (forward +)
---@param dx number delta x to use (dx to the next waypoint by default)
---@param dz number delta z to use (dz to the next waypoint by default)
---@return number, number, number x, y, z
function Waypoint:getOffsetPosition(offsetX, offsetZ, dx, dz)
	local x, y, z = self:getPosition()
	local deltaX = dx or self.dx
	local deltaZ = dz or self.dz
	-- check for NaN
	if deltaX and deltaZ and deltaX == deltaX and deltaZ == deltaZ then
		-- X offset should be inverted if we drive reverse here (left is always left regardless of the driving direction)
		local reverse = self.reverseOffset and -1 or 1
		x = x - deltaZ * reverse * offsetX + deltaX * offsetZ
		z = z + deltaX * reverse * offsetX + deltaZ * offsetZ
	end
	return x, y, z
end

function Waypoint:setOffsetPosition(offsetX, offsetZ, dx, dz)
	self.x, self.y, self.z = self:getOffsetPosition(offsetX, offsetZ, dx, dz)
end

function Waypoint:getDistanceFromPoint(x, z)
	return MathUtil.getPointPointDistance(x, z, self.x, self.z)
end

function Waypoint:getDistanceFromOther(other)
	return self:getDistanceFromPoint(other.x, other.z)
end

function Waypoint:getDistanceFromVehicle(vehicle)
	local vx, _, vz = getWorldTranslation(vehicle:getAIDirectionNode() or vehicle.rootNode)
	return self:getDistanceFromPoint(vx, vz)
end

function Waypoint:getDistanceFromNode(node)
	local x, _, z = getWorldTranslation(node)
	return self:getDistanceFromPoint(x, z)
end

function Waypoint:setPosition(x, z, y)
	self.x = x 
	self.z = z 
	if y then 
		self.y = y 
	else 
		self.y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z)
	end
end

function Waypoint:setReverseOffset(reverseOffset)
	self.reverseOffset = reverseOffset
end

function Waypoint:translate(dx, dz)
	self.x = self.x + dx
	self.z = self.z + dz
	self.y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, self.x, 0, self.z)
end

function Waypoint:clone()
	return Waypoint(self)
end

function Waypoint:getIsReverse()
	return self.rev
end

function Waypoint:isRowEnd()
	return self.attributes:isRowEnd()
end

function Waypoint:isRowStart()
	return self.attributes:isRowStart()
end

function Waypoint:isHeadlandTurn()
	return self.attributes:isHeadlandTurn()
end

function Waypoint:isHeadlandTransition()
	return self.attributes:isHeadlandTransition()
end

function Waypoint:getBoundaryId()
	return self.attributes:getBoundaryId()
end

function Waypoint:getAtBoundaryId()
	return self.attributes:getAtBoundaryId()
end

function Waypoint:isOnConnectingPath()
	return self.attributes:isOnConnectingPath()
end

function Waypoint:shouldUsePathfinderToNextWaypoint()
	return self.attributes:shouldUsePathfinderToNextWaypoint()
end

function Waypoint:shouldUsePathfinderToThisWaypoint()
	return self.attributes:shouldUsePathfinderToThisWaypoint()
end

function Waypoint:getRowNumber()
	return self.attributes:getRowNumber()
end

function Waypoint:setRowNumber(rowNumber)
	self.attributes:setRowNumber(rowNumber)
end

function Waypoint:setRowEnd(rowEnd)
	self.attributes:setRowEnd(rowEnd)
end

function Waypoint:setRowStart(rowStart)
	self.attributes:setRowStart(rowStart)
end

function Waypoint:resetRowStartEnd()
	self.attributes:setRowStart(false)
	self.attributes:setRowEnd(false)
end

function Waypoint:setHeadlandNumber(n)
	self.attributes:setHeadlandPassNumber(n)
end

function Waypoint:setOnConnectingPath(onConnectingPath)
	self.attributes:setOnConnectingPath(onConnectingPath)
end

function Waypoint:copyRowData(other)
	self.attributes.rowNumber = other.attributes.rowNumber
	self.attributes.leftSideWorked = other.attributes.leftSideWorked
	self.attributes.rightSideWorked = other.attributes.rightSideWorked
end

-- a node related to a waypoint
---@class WaypointNode
WaypointNode = CpObject()
WaypointNode.MODE_NORMAL = 1
WaypointNode.MODE_LAST_WP = 2
WaypointNode.MODE_SWITCH_DIRECTION = 3
WaypointNode.MODE_SWITCH_TO_FORWARD = 4

function WaypointNode:init(name, logChanges)
	self.logChanges = logChanges
	self.node = CpUtil.createNode(name, 0, 0, 0)
end

function WaypointNode:destroy()
	CpUtil.destroyNode(self.node)
end

---@param course Course
function WaypointNode:setToWaypoint(course, ix, suppressLog)
	local newIx = math.min(ix, course:getNumberOfWaypoints())
	if newIx ~= self.ix and self.logChanges and not suppressLog then
		CpUtil.debugVehicle(CpDebug.DBG_PPC, course.vehicle, 'PPC: %s waypoint index %d', getName(self.node), ix)
	end
	self.ix = newIx
	local x, y, z = course:getWaypointPosition(self.ix)
	setTranslation(self.node, x, y, z)
	setRotation(self.node, 0, course:getWaypointYRotation(self.ix), 0)
end

-- Allow ix > #Waypoints, in that case move the node lookAheadDistance beyond the last WP
function WaypointNode:setToWaypointOrBeyond(course, ix, distance)
	--if self.ix and self.ix > ix then return end
	if ix > course:getNumberOfWaypoints() then
		-- beyond the last, so put it on the last for now
		-- but use the direction of the one before the last as the last one's is bogus
		self:setToWaypoint(course, course:getNumberOfWaypoints())
		setRotation(self.node, 0, course:getWaypointYRotation(course:getNumberOfWaypoints() - 1), 0)
		-- And now, move ahead a bit.
		local nx, ny, nz = localToWorld(self.node, 0, 0, distance)
		setTranslation(self.node, nx, ny, nz)
		if self.logChanges and self.mode and self.mode ~= WaypointNode.MODE_LAST_WP then
			CpUtil.debugVehicle(CpDebug.DBG_PPC, course.vehicle, 'PPC: last waypoint reached, moving node beyond last: %s', getName(self.node))
		end
		
		self.mode = WaypointNode.MODE_LAST_WP
	elseif course:switchingToReverseAt(ix) or course:switchingToForwardAt(ix) then
		-- just like at the last waypoint, if there's a direction switch, we want to drive up
		-- to the waypoint so we move the goal point beyond it
		-- the angle of ix is already pointing to reverse here
		self:setToWaypoint(course, ix)
		-- turn node back as this is the one before the first reverse, already pointing to the reverse direction.
		local _, yRot, _ = getRotation(self.node)
		setRotation(self.node, 0, yRot + math.pi, 0)
		-- And now, move ahead a bit.
		local nx, ny, nz = localToWorld(self.node, 0, 0, distance)
		setTranslation(self.node, nx, ny, nz)
		if self.logChanges and self.mode and self.mode ~= WaypointNode.MODE_SWITCH_DIRECTION then
			CpUtil.debugVehicle(CpDebug.DBG_PPC, course.vehicle, 'PPC: switching direction at %d, moving node beyond it: %s', ix, getName(self.node))
		end
		self.mode = WaypointNode.MODE_SWITCH_DIRECTION
	else
		if self.logChanges and self.mode and self.mode ~= WaypointNode.MODE_NORMAL then
			CpUtil.debugVehicle(CpDebug.DBG_PPC, course.vehicle, 'PPC: normal waypoint (not last, no direction change: %s', getName(self.node))
		end
		self.mode = WaypointNode.MODE_NORMAL
		self:setToWaypoint(course, ix)
	end
end

