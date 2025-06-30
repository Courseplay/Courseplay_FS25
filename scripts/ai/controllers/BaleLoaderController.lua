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

--- Controller for bale loaders. Not much to do here as long as we do not unload the bales,
--- loading them is pretty straightforward and automatic, once they are in range.

---@class BaleLoaderController : ImplementController
BaleLoaderController = CpObject(ImplementController)

function BaleLoaderController:init(vehicle, baleLoader)
    self.baleLoader = baleLoader
    self.baleLoaderSpec = baleLoader.spec_baleLoader
    ImplementController.init(self, vehicle, self.baleLoader)
    if self.baleLoader then
        -- Bale loaders have no AI markers (as they are not AIImplements according to Giants) so add a function here
        -- to get the markers
        self.baleLoader.getAIMarkers = function(object)
            return ImplementUtil.getAIMarkersFromGrabberNode(object, object.spec_baleLoader)
        end
    end
    self:debug('Bale loader controller initialized')
end

function BaleLoaderController:isGrabbingBale()
    return self.baleLoader.spec_baleLoader.grabberMoveState
end

--- Is at least one bale loaded?
function BaleLoaderController:hasBales()
    return self.baleLoader:getFillUnitFillLevelPercentage(self.baleLoaderSpec.fillUnitIndex) >= 0.01
end

function BaleLoaderController:isFull(ignoreBaleChanger)
    if self:isChangingBaleSize() and not ignoreBaleChanger then 
        return false
    end
    return self.baleLoader:getFillUnitFreeCapacity(self.baleLoaderSpec.fillUnitIndex) <= 0.01
end

function BaleLoaderController:canBeFolded()
    if self:isChangingBaleSize() then 
        return true
    end
    return not self:isGrabbingBale() and self.baleLoaderSpec.emptyState == BaleLoader.EMPTY_NONE
end

function BaleLoaderController:update()
    if self:isFull(true) and not self.baleLoaderSpec.fullAutomaticUnloading then 
        if self:isChangingBaleSize() then 
            if self.baleLoaderSpec.emptyState == BaleLoader.EMPTY_NONE then
                self.baleLoader:startAutomaticBaleUnloading()
            end
        end
        if not self:isBaleFinderMode() then 
            --- In the fieldwork mode the driver has to stop once full
            --- The bale finder mode controls this in the strategy.
            --- TODO: Breaks multiple trailers in fieldwork (on one tractor)!
            self.vehicle:stopCurrentAIJob(AIMessageErrorIsFull.new())
        end
    end
end

function BaleLoaderController:getDriveData()
    --- While animations are playing and the bale loader is full, then just wait.
    local maxSpeed 
    if self:isChangingBaleSize() and ( self:isFull() or self.baleLoaderSpec.emptyState ~= BaleLoader.EMPTY_NONE) then
        self:debugSparse("is full and waiting for release after animation has finished.")
        maxSpeed = 0
    end
    if self.baleLoaderSpec.emptyState == BaleLoader.EMPTY_WAIT_TO_SINK then
        maxSpeed = 1
    end
    if self:isGrabbingBale() then 
        self:debugSparse("Slowing down down during the bale grabbing.")
        maxSpeed = 2
    end
    return nil, nil, nil, maxSpeed
end

function BaleLoaderController:isFuelSaveAllowed()
    return false
end

function BaleLoaderController:onStart()
    if not self.baleLoaderSpec.isInWorkPosition then
        self.baleLoader:doStateChange(BaleLoader.CHANGE_BUTTON_WORK_TRANSPORT)
    end
end

--- Get a list of bale objects to ignore when pathfinding.
function BaleLoaderController:getBalesToIgnore()
    return {}
end

--- Is the bale loader transforming the picked up bale to a different bale size ?
function BaleLoaderController:isChangingBaleSize()
    return self.baleLoaderSpec.balePacker.node ~= nil and self.baleLoaderSpec.balePacker.filename ~= nil
end

--- Is the bale finder mode active and not a normal fieldworker?
function BaleLoaderController:isBaleFinderMode()
    --- For field work the bale loader has to wait until loading finished
    --- and needs to stop when the full.
    --- TODO: this is a more a hack and the fieldwork strategy 
    ---       or another instance should handle the is full check
    return self.driveStrategy:is_a(AIDriveStrategyFindBales)
end

--- This one is not used for the giants baleloaders
function BaleLoaderController:isReadyToLoadNextBale()
    return false
end

function BaleLoaderController:onPreFinished()
    return self:canBeFolded()
end