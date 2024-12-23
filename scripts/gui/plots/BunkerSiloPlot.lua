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


--- Draws the bunker silo dimensions on the in game map.
---@class BunkerSiloPlot : FieldPlot
BunkerSiloPlot = CpObject(FieldPlot)

function BunkerSiloPlot:init(silo)
	FieldPlot.init(self, false)
	self.isVisible = true
end

function BunkerSiloPlot:setAreas(areaOne, areaTwo)
	self.areaOne, self.areaTwo = areaOne, areaTwo
end

--- Draws the bunker silo.
function BunkerSiloPlot:draw(map)
	if not self.isVisible then return end
	self:drawPoints(map, self.areaOne, false)
	if self.areaTwo then
		self:drawPoints(map, self.areaTwo, false)
	end
end

function BunkerSiloPlot:setHighlighted(highlighted)
	if highlighted then 
		self:setBrightColor()
	else 
		self:setNormalColor()
	end
end