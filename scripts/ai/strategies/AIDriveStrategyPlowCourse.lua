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

Derived fieldwork course strategy, which handles plows.

- Makes sure that all plows are unfolded and rotated in the correct direction,
  which was determined by the course generator.
- Applies the automatic tool offset calculation for all attached plows.


]]--

---@class AIDriveStrategyPlowCourse : AIDriveStrategyFieldWorkCourse
AIDriveStrategyPlowCourse = CpObject(AIDriveStrategyFieldWorkCourse)

AIDriveStrategyPlowCourse.myStates = {
    ROTATING_PLOW = {},
    UNFOLDING_PLOW = {},
}

function AIDriveStrategyPlowCourse:init(task, job)
    AIDriveStrategyFieldWorkCourse.init(self, task, job)
    AIDriveStrategyCourse.initStates(self, AIDriveStrategyPlowCourse.myStates)
    self.debugChannel = CpDebug.DBG_FIELDWORK
    -- the plow offset is automatically calculated on each waypoint and if it wasn't calculated for a while
    -- or when some event (like a turn) invalidated it
    self.plowOffsetUnknown = CpTemporaryObject(true)
end

function AIDriveStrategyPlowCourse:getDriveData(dt, vX, vY, vZ)
    if self.state == self.states.INITIAL then
        self:setMaxSpeed(0)
        self:updatePlowOffset()
        if self:isPlowRotating() then
            --- If the plow is already being rotated at the start,
            --- we still need to check if the rotation 
            --- is in correct direction, as the course generator directed.
            self:rotatePlows()
            self:debug("Needs to wait until the plow has finished rotating.")
            self.state = self.states.ROTATING_PLOW
        else
            --- The plow can not be rotated, 
            --- so we check if the plow is unfolded
            --- and try again to rotate the plow in the correct direction.
            self:debug("Plows have to be unfolded first!")
            self.state = self.states.UNFOLDING_PLOW
        end
    elseif self.state == self.states.ROTATING_PLOW then
        self:setMaxSpeed(0)
        if not self:isPlowRotating() then
            --- Initial Rotation has finished and fieldwork can start.
            self:updatePlowOffset()
            self:startWaitingForLower()
            self:lowerImplements()
            self:debug('Plow initial rotation finished')
        end
    elseif self.state == self.states.UNFOLDING_PLOW then
        self:setMaxSpeed(0)
        if self:isPlowRotationAllowed() then
            --- The Unfolding has finished and 
            --- we need to check if the rotation is correct.
            self:rotatePlows()
            self:debug("Plow was unfolded and rotation can begin")
            self.state = self.states.ROTATING_PLOW
        elseif self:getCanContinueWork() then
            --- Unfolding has finished and no extra rotation is needed.
            self:updatePlowOffset()
            self:startWaitingForLower()
            self:lowerImplements()
            self:debug('Plow is unfolded and ready to start')
        end
    end
    if self.plowOffsetUnknown:get() then
        self:updatePlowOffset()
    end
    return AIDriveStrategyFieldWorkCourse.getDriveData(self, dt, vX, vY, vZ)
end

function AIDriveStrategyPlowCourse:onWaypointPassed(ix, course)
    -- readjust the tool offset every now and then. This is necessary as the offset is calculated from the
    -- tractor's direction node which may need to result in incorrect values if the plow is not straight behind
    -- the tractor (which may be the case when starting). When passing waypoints we'll most likely be driving
    -- straight and thus calculating a proper tool offset
    if self.state == self.states.WORKING then
        self:updatePlowOffset()
    end
    AIDriveStrategyFieldWorkCourse.onWaypointPassed(self, ix, course)
end

--- Updates the X Offset based on the plows attached.
function AIDriveStrategyPlowCourse:updatePlowOffset()
    local xOffset = 0
    for _, controller in pairs(self.controllers) do
        if controller.getAutomaticXOffset then
            local autoOffset = controller:getAutomaticXOffset()
            if autoOffset == nil then
                self:debugSparse('Plow offset can\'t be calculated now, leaving offset at %.2f', self.aiOffsetX)
                return
            end
            xOffset = xOffset + autoOffset
        end
    end
    local oldOffset = self.aiOffsetX
    -- set to the average of old and new to smooth a little bit to avoid oscillations
    -- when we have a valid previous value
    self.aiOffsetX = self.plowOffsetUnknown:get() and xOffset or ((0.5 * self.aiOffsetX + 1.5 * xOffset) / 2)
    if math.abs(oldOffset - xOffset) > 0.05 then
        self:debug("Plow offset calculated was %.2f and it changed from %.2f to %.2f", xOffset, oldOffset, self.aiOffsetX)
    end
    self.plowOffsetUnknown:set(false, 3000)
end

--- Is a plow currently rotating?
---@return boolean
function AIDriveStrategyPlowCourse:isPlowRotating()
    for _, controller in pairs(self.controllers) do
        if controller.isRotationActive and controller:isRotationActive() then
            return true
        end
    end
    return false
end

--- Are all plows allowed to be turned?
---@return boolean
function AIDriveStrategyPlowCourse:isPlowRotationAllowed()
    local allowed = true
    for _, controller in pairs(self.controllers) do
        if controller.getIsPlowRotationAllowed and not controller:getIsPlowRotationAllowed() then
            allowed = false
        end
    end
    return allowed
end

--- Initial plow rotation based on the ridge marker side selection by the course generator.
function AIDriveStrategyPlowCourse:rotatePlows()
    self:debug('Starting work: check if plow needs to be turned.')
    local ix = self.ppc:getCurrentWaypointIx()
    local plowShouldBeOnTheLeft = self.course:shouldPlowBeOnTheLeft(ix)
    for _, controller in pairs(self.controllers) do
        if controller.rotate then
            controller:rotate(plowShouldBeOnTheLeft)
        end
    end
end

--- Do we have at least one plow that can be rotated?
---@return boolean
function AIDriveStrategyPlowCourse:haveRotatablePlow()
    for _, controller in pairs(self.controllers) do
        if controller.isRotatablePlow and controller:isRotatablePlow() then
            return true
        end
    end
    return false
end

-----------------------------------------------------------------------------------------------------------------------
--- Dynamic parameters (may change while driving)
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyPlowCourse:getTurnEndSideOffset(isHeadlandTurn)
    -- on headland turns we do not rotate the plow, and since the course already has the offset, nothing to do,
    -- the context will calculate with the offset of the course already, no additional side offset is needed
    if self:isWorking() and not isHeadlandTurn and self:haveRotatablePlow() then
        self:updatePlowOffset()
        -- need the double tool offset as the turn end waypoint still has the current offset, but after rotating,
        -- the plow will be on the other side, (one toolOffsetX would put it to 0 only)
        self:debug('Setting turn end side offset to %.2f for the plow', 2 * self.aiOffsetX)
        return 2 * self.aiOffsetX
    else
        self:debug('No turn end side offset, working: %s, headland turn %s, have rotatable plow %s ',
                tostring(self:isWorking()), tostring(isHeadlandTurn), tostring(self:haveRotatablePlow()))
        return 0
    end
end

function AIDriveStrategyPlowCourse:updateFieldworkOffset(course)
    --- Ignore the tool offset setting.
    course:setOffset((self.aiOffsetX or 0), (self.aiOffsetZ or 0))
end

--- When we return from a turn, the offset is reverted and should immediately set, not waiting
--- for the first waypoint to pass as it is on the wrong side right after the turn
function AIDriveStrategyPlowCourse:resumeFieldworkAfterTurn(ix)
    self.plowOffsetUnknown:reset()
    AIDriveStrategyFieldWorkCourse.resumeFieldworkAfterTurn(self, ix)
end