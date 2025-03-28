--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2019-2022 Peter Vaiko

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

--- Controller for the auto loader script: https://github.com/loki79uk/FS22_UniversalAutoload

---@class UniversalAutoloadController : BaleLoaderController
UniversalAutoloadController = CpObject(BaleLoaderController)

function UniversalAutoloadController:init(vehicle, implement)
    ImplementController.init(self, vehicle, implement)
    
    self.autoLoader = implement
    self.autoLoaderSpec = implement.spec_universalAutoload

    self.balesToIgnoreOnStart = {}
end

--- Is at least one bale loaded?
function UniversalAutoloadController:hasBales()
    return self.autoLoader.ualHasLoadedBales and self.autoLoader:ualHasLoadedBales()
end

function UniversalAutoloadController:isFull()
    return self.autoLoader.ualIsFull and self.autoLoader:ualIsFull()
end

function UniversalAutoloadController:canBeFolded()
    return true
end

function UniversalAutoloadController:isFuelSaveAllowed()
    return true
end

function UniversalAutoloadController:onStart()
    -- turning the autoloader on when CP starts
    self.vehicle:raiseAIEvent("onAIFieldWorkerStart", "onAIImplementStart")
end

function UniversalAutoloadController:onFinished()
    -- turning the autoloader on when CP starts
    self.vehicle:raiseAIEvent("onAIFieldWorkerEnd", "onAIImplementEnd")
end

--- Ignore all already loaded bales when pathfinding
function UniversalAutoloadController:getBalesToIgnore()    
    local bales = self.autoLoader.ualGetLoadedBales and self.autoLoader:ualGetLoadedBales()
    if bales then 
        return table.toList(bales)
    end
    return {}
end

function UniversalAutoloadController:getDriveData()
    local maxSpeed 
    return nil, nil, nil, maxSpeed
end

function UniversalAutoloadController:update()
    if self:isFull() then 
        if not self:isBaleFinderMode() then 
            --- In the fieldwork mode the driver has to stop once full
            --- The bale finder mode controls this in the strategy.
            --- TODO: Breaks multiple trailers in fieldwork (on one tractor)!
            self.vehicle:stopCurrentAIJob(AIMessageErrorIsFull.new())
        end
    end
end

function UniversalAutoloadController:isChangingBaleSize()
    return false
end

function UniversalAutoloadController:onStartDrivingToBale()
    self.balesToIgnoreOnStart = self:getBalesToIgnore()
end

function UniversalAutoloadController:isReadyToLoadNextBale()
    return #self:getBalesToIgnore() > #self.balesToIgnoreOnStart
end