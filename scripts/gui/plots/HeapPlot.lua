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


--- Draws the fill type heap dimensions on the in game map.
---@class HeapPlot : FieldPlot
HeapPlot = CpObject(FieldPlot)

function HeapPlot:init(silo)
	FieldPlot.init(self, false)
	self.isVisible = true
end

---@param area table
function HeapPlot:setArea(area)
	self.area = area
end

--- Draws the heap area.
function HeapPlot:draw(map)
	if not self.isVisible then return end
	self:drawPoints(map, self.area, false)
end

function HeapPlot:setHighlighted(highlighted)
	if highlighted then 
		self:setBrightColor()
	else 
		self:setNormalColor()
	end
end