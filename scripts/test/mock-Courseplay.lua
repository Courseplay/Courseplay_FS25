--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2021 Peter Vaiko

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

CpDebug = {}
CpDebug.isChannelActive = function () return true end
CpDebug.getText = function () return '' end

g_vehicleConfigurations = {}
function g_vehicleConfigurations:get()
	return false
end

g_Courseplay = {
	globalSettings = {
		getSettings = function()
			return {
				deltaAngleRelaxFactorDeg = {
					getValue = function()
						return 10
					end
				},
				maxDeltaAngleAtGoalDeg = {
					getValue = function()
						return 45
					end
				},
			}
		end
	}
}