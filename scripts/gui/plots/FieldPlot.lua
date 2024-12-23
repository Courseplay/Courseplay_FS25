--[[
This file is part of Courseplay (https://github.com/Courseplay/Courseplay_FS25)
Copyright (C) 2022 Peter Vaiko

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

---@class FieldPlot : CoursePlot
FieldPlot = CpObject(CoursePlot)

--- Shows custom fields on the in-game map
---@param drawLastWp boolean should the last waypoint be highlight in form on an extra point, with slightly larger size.
function FieldPlot:init(drawLastWp)
	CoursePlot.init(self)
	self:setNormalColor()
	self:setDrawingArrows(false)
	-- use a thicker line
	self.lineThickness = 4 / g_screenHeight
	self.drawLastWp = drawLastWp
	self.nextTargetPoint = {}
end

function FieldPlot:setNormalColor()
	-- use same color for the entire plot
	self.lightColor = {CpGuiUtil.getNormalizedRgb(38, 174, 214)}
	self.darkColor = {CpGuiUtil.getNormalizedRgb(38, 174, 214)}
end

function FieldPlot:setBrightColor()
	self.lightColor = {CpGuiUtil.getNormalizedRgb(255, 255, 255)}
	self.darkColor = {CpGuiUtil.getNormalizedRgb(255, 255, 255)}
end

--- This point will be draw in green.
function FieldPlot:setNextTargetPoint(x, z)
	self.nextTargetPoint = {x = x, z = z}
end

--- Draws custom fields.
---@param map table
function FieldPlot:draw(map)
	if not self.isVisible then return end
	self:drawPoints(map, self.waypoints, false)

	local lastWp = self.waypoints and  #self.waypoints>0 and self.waypoints[#self.waypoints]
	if self.drawLastWp and lastWp then 
		local x, y = CpGuiUtil.worldToScreen(map, lastWp.x, lastWp.z )
		local signSizeMeters = 1.5* self.lineThickness
		local zoom = map.fullScreenLayout:getIconZoom()
		local width, height = signSizeMeters * map.uiScale * zoom, signSizeMeters * map.uiScale * zoom * g_screenAspectRatio
		local r, g, b = unpack(self.darkColor)
		
		drawPoint(x, y, width, height, r, g, b, 0.8)
		
--		setOverlayColor( self.courseOverlayId, r, g, b, 0.8 )
--		renderOverlay( self.courseOverlayId, x, y, width, self.lineThickness )

	end
	if lastWp and self.nextTargetPoint.x ~= nil then 
		self:drawLineBetween(map, lastWp.x, lastWp.z, self.nextTargetPoint.x, self.nextTargetPoint.z,
			false, self.lineThickness, 0, 1, 0)
	end
end

