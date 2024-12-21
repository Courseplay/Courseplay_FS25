--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2019-2023 Courseplay Dev Team 

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

--- Controller for foldable implements, that allows to disable the unfolding by AI.

---@class FoldableController : ImplementController
FoldableController = CpObject(ImplementController)

function FoldableController:init(vehicle, implement)
    ImplementController.init(self, vehicle, implement)
    self.foldableSpec = implement.spec_foldable
    if g_vehicleConfigurations:get(implement, "disableUnfolding") then 
        if self.foldableSpec.controlledActionFold ~= nil then 
			--- The unfolding of the implement has to be suppressed.
            self:debug("Removed ai foldable control!")
            self.foldableSpec.controlledActionFold:remove()
            self.foldActionWasRemoved = true
        end
    end
end

function FoldableController:delete()
    if self.foldActionWasRemoved then 
        --- Restores the controlledAction 
        Foldable.onRootVehicleChanged(self.implement, self.vehicle)
    end
end

function FoldableController:canContinueWork()
    if self.foldActionWasRemoved then
        return true
    else
        return self.foldableSpec:getIsUnfolded()
    end
end