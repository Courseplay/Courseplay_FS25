--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2018 Peter Vaiko

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

---@class CoursePlot : CpObject
CoursePlot = CpObject()

-- Position and size of the course plot as normalized screen coordinates
-- x = 0, y = 0 is the bottom left corner of the screen, terrainSize is in meters
function CoursePlot:init()
	self.lineThickness = 2 / g_screenHeight -- 2 pixels
	self.arrowThickness = 10 / g_screenHeight -- 10 pixels
	-- the normal FS22 blue
	self.color = {CpGuiUtil.getNormalizedRgb(42, 193, 237)}
	-- a lighter shade of the same color
	self.lightColor = {CpGuiUtil.getNormalizedRgb(45, 207, 255)}
	-- a darker shade of the same color
	self.darkColor = {CpGuiUtil.getNormalizedRgb(19, 87, 107)}
	self.courseOverlayId = createImageOverlay('dataS/menu/base/graph_pixel.dds')
	self.startSignOverlayId = createImageOverlay(Utils.getFilename('img/signs/start_noMM.dds', Courseplay.BASE_DIRECTORY))
	self.stopSignOverlayId = createImageOverlay(Utils.getFilename('img/signs/stop_noMM.dds', Courseplay.BASE_DIRECTORY))
	self.arrowOverlayId = createImageOverlay(Utils.getFilename('img/iconSprite.dds', Courseplay.BASE_DIRECTORY))
	setOverlayUVs(self.arrowOverlayId, unpack(GuiUtils.getUVs({44, 184, 32, 32}, {256, 512})))
	self.startPosition = {}
	self.stopPosition = {}
	self.drawArrows	= true
	self.isVisible = false
	self.invertArrowDirection = false
end

function CoursePlot:delete()
	if self.courseOverlayId ~= 0 then
		delete(self.courseOverlayId)
	end
	if self.startSignOverlayId ~= 0 then
		delete(self.startSignOverlayId)
	end
	if self.stopSignOverlayId ~= 0 then 
		delete(self.stopSignOverlayId)
	end
	if self.arrowOverlayId ~= 0 then 
		delete(self.arrowOverlayId)
	end
end

function CoursePlot:setVisible( isVisible )
	self.isVisible = isVisible
end

function CoursePlot:setDrawingArrows(draw, invert)
	self.drawArrows = draw
	self.invertArrowDirection = invert
end

function CoursePlot:setWaypoints( waypoints )
	self.waypoints = {}
	-- remove waypoints from long straight lines, the plot only needs start/end. Too many waypoints
	-- in the plot are a performance problem
	table.insert(self.waypoints, waypoints[1])
	self.waypoints[1].progress = 1 / #waypoints
	for i = 2, #waypoints - 1 do
		if waypoints[i].angle == nil or math.abs(waypoints[i].angle - waypoints[i - 1].angle) > 2 
			or waypoints[i].attributes.rowStart or waypoints[i].attributes.rowEnd then
			table.insert(self.waypoints, waypoints[i])
			self.waypoints[#self.waypoints].progress = i / #waypoints
		end
	end
	table.insert(self.waypoints, waypoints[#waypoints])
	self.waypoints[1].progress = 1
	self:setStartPosition(self.waypoints[1].x, self.waypoints[1].z)
	self:setStopPosition(self.waypoints[#self.waypoints].x, self.waypoints[#self.waypoints].z)
end

-- start position used when generating the course, either first course wp
-- or the position selected by the user on the map. We'll show a sign there.
function CoursePlot:setStartPosition( x, z )
	self.startPosition.x, self.startPosition.z = x, z
end

-- end position of the course
function CoursePlot:setStopPosition( x, z )
	self.stopPosition.x, self.stopPosition.z = x, z
end

--- Draws a line between two points on the given map
---@param map table
---@param x number
---@param z number
---@param nx number
---@param nz number
---@param isHudMap boolean|nil
---@param lineThickness number
---@param r number
---@param g number
---@param b number
---@param a number|nil
---@param rowStart boolean|nil
---@param rowEnd boolean|nil
function CoursePlot:drawLineBetween(map, x, z, nx, nz, isHudMap, lineThickness, r, g, b, a, rowStart, rowEnd)
	local mapRotation = map.layout:getMapRotation()
	local startX, startY, _, sv = CpGuiUtil.worldToScreen(map, x, z, isHudMap)
	local endX, endY, _, ev = CpGuiUtil.worldToScreen(map, nx, nz, isHudMap)
	local dx, dz = nx - x, nz - z
	local length = MathUtil.vector2Length(dx, dz)
	local dirX, dirZ = 0, 1
	if length <= 0 then
		return
	end
	dirX, dirZ = MathUtil.vector2Normalize(dx, dz)
	if startX and startY and endX and endY then
		local dx2D = endX - startX
		local dy2D = ( endY - startY ) / g_screenAspectRatio
		local width = MathUtil.vector2Length(dx2D, dy2D)

		local rotation = MathUtil.getYRotationFromDirection(dirX, dirZ) - math.pi * 0.5 + mapRotation
		setOverlayColor( self.courseOverlayId, r, g, b, a or 0.8 )
		setOverlayRotation( self.courseOverlayId, rotation, 0, self.lineThickness/2 )
		renderOverlay( self.courseOverlayId, startX, startY, width, lineThickness )

		if self.drawArrows and not isHudMap 
			and (MathUtil.vector2Length(dx, dz) > 2.5 or rowStart or rowEnd) then

			if rowStart and rowEnd then
				--- Draws an arrow after a row start waypoint 
				local ax, az = x + dirX * math.min(length/2, 5), z + dirZ * math.min(length/2, 5)
				self:drawArrow(map, ax, az, rotation, r, g, b, a, isHudMap)
				--- Draws an arrow before a row end waypoint 
				ax, az = x + dirX * math.max(length/2, length - 5), z + dirZ * math.max(length/2, length - 5)
				self:drawArrow(map, ax, az, rotation, r, g, b, a, isHudMap)
				if length > 30 then 
					--- Draws an arrow in the middle between two waypoints
					ax, az = x + dirX * length/2, z + dirZ * length/2
					self:drawArrow(map, ax, az, rotation, r, g, b, a, isHudMap)
				end
			elseif rowStart then 
				--- Draws an arrow after a row start waypoint 
				local ax, az = x + dirX * math.min(length/2, 5), z + dirZ * math.min(length/2, 5)
				self:drawArrow(map, ax, az, rotation, r, g, b, a, isHudMap)
			elseif rowEnd then
				--- Draws an arrow before a row end waypoint 
				local ax, az = x + dirX * math.max(length/2, length - 5), z + dirZ * math.max(length/2, length - 5)
				self:drawArrow(map, ax, az, rotation, r, g, b, a, isHudMap)
			else
				--- Draws an arrow in the middle between two waypoints
				local ax, az = x + dirX * length/2, z + dirZ * length/2
				self:drawArrow(map, ax, az, rotation, r, g, b, a, isHudMap)
			end
		
		end
	end
end

---Draws an arrow
---@param map table
---@param x number
---@param z number
---@param rotation number
---@param r number
---@param g number
---@param b number
---@param a number|nil
---@param isHudMap boolean|nil
function CoursePlot:drawArrow(map, x, z, rotation, r, g, b, a, isHudMap)
	local zoom = map.layout:getIconZoom() * map.layout:getIconZoom()
	if isHudMap and map.state == IngameMap.STATE_MAP then 
		--- When the hud is completely open, then the signs need to be scaled down.
		zoom = zoom * 0.5
	end
	local arrowWidth = self.arrowThickness * map.uiScale * zoom
	local arrowHeight = self.arrowThickness * map.uiScale * zoom * g_screenAspectRatio
	local ax, ay, _ = CpGuiUtil.worldToScreen(map, x, z, isHudMap)
	setOverlayColor( self.arrowOverlayId, r, g, b, a or 0.8)
	if self.invertArrowDirection then 
		rotation = rotation + math.pi
	end
	setOverlayRotation(self.arrowOverlayId, rotation, arrowWidth/2, arrowHeight/2 )
	renderOverlay( self.arrowOverlayId,
		ax - arrowWidth/2,
		ay - arrowHeight/2,
		arrowWidth, arrowHeight)
end

-- Draw the waypoints in the screen area defined in new(), the bottom left corner
-- is at worldX/worldZ coordinates, the size shown is worldWidth wide (and high)
function CoursePlot:drawPoints(map, points, isHudMap)
	local lineThickness = self.lineThickness
	if isHudMap then 
		lineThickness = lineThickness/2
	end
	if points and #points > 1 then
		-- I know this is in helpers.lua already but that code has too many dependencies
		-- on global variables and vehicle.cp.
		local wp, np, r, g, b
		-- render a line between subsequent waypoints
		for i = 1, #points do
			wp = points[i]
			-- if we are drawing a polygon, we need to draw a line between the last and the first point
			if self.isPolygon and i == #points then
				np = points[1]
			else
				np = points[i + 1]
			end
			if wp and np then
				r, g, b = MathUtil.vector3ArrayLerp(self.lightColor, self.darkColor, wp.progress or 1)
				self:drawLineBetween(map, wp.x or wp._x, wp.z or wp._z, np.x or np._x, np.z or np._z,
						isHudMap, lineThickness, r, g, b, 0.8,
						wp.attributes and wp.attributes.rowStart,
						np.attributes and np.attributes.rowEnd)
			end
		end
		setOverlayRotation( self.courseOverlayId, 0, 0, 0 ) -- reset overlay rotation
		setOverlayRotation( self.arrowOverlayId, 0, 0, 0 ) -- reset overlay rotation
	end
end


function CoursePlot:draw(map, isHudMap)

	if not self.isVisible then return end

	self:drawPoints(map, self.waypoints, isHudMap)

	-- render the start and stop signs

	local signSizeMeters = 0.02
	local zoom = map.layout:getIconZoom() 
	if isHudMap and map.state == IngameMap.STATE_MAP then 
		--- When the hud is completely open, then the signs need to be scaled down.
		zoom = zoom * 0.5
	end
	local signWidth, signHeight = signSizeMeters * map.uiScale * zoom, signSizeMeters * map.uiScale * zoom * g_screenAspectRatio

	-- render a sign marking the end of the course
	if self.stopPosition.x and self.stopPosition.z then
		local x, y, rotation = CpGuiUtil.worldToScreen( map,self.stopPosition.x, self.stopPosition.z, isHudMap)
		if x and y then
			setOverlayColor( self.stopSignOverlayId, 1, 1, 1, 1 )
			renderOverlay( self.stopSignOverlayId,
				x - signWidth / 2, -- offset so the middle of the sign is on the stopping location
				y - signHeight / 2,
				signWidth, signHeight)
		end
	end

	-- render a sign marking the current position used as a starting location for the course
	if self.startPosition.x and self.startPosition.z then
		local x, y, rotation = CpGuiUtil.worldToScreen(map, self.startPosition.x, self.startPosition.z, isHudMap)
		if x and y then
			setOverlayColor( self.startSignOverlayId, 1, 1, 1, 0.8 )
			renderOverlay( self.startSignOverlayId,
				x - signWidth / 2, -- offset so the middle of the sign is on the starting location
				y - signHeight / 2,
				signWidth, signHeight)
		end
	end
end