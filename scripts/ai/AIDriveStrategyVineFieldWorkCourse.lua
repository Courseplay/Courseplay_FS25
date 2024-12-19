--[[
This file is part of Courseplay (https://github.com/Courseplay/Courseplay_FS25)
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

Drive strategy for driving a vine field work course

]]--

---@class AIDriveStrategyVineFieldWorkCourse : AIDriveStrategyFieldWorkCourse
AIDriveStrategyVineFieldWorkCourse = CpObject(AIDriveStrategyFieldWorkCourse)

--- Always disables turn on field.
function AIDriveStrategyVineFieldWorkCourse:isTurnOnFieldActive()
    return false
end

function AIDriveStrategyVineFieldWorkCourse:getImplementRaiseLate()
    return true
end

function AIDriveStrategyVineFieldWorkCourse:getImplementLowerEarly()
    return true
end

-- disable proximity sensor to prevent vines stopping us...
function AIDriveStrategyVineFieldWorkCourse:checkProximitySensors(moveForwards)
    -- TODO: make proximity sensor ignore vines?
    -- TODO: enable sensor in turns only?
end

function AIDriveStrategyVineFieldWorkCourse:startTurn(ix)

    local _, frontMarkerDistance = AIUtil.getFirstAttachedImplement(self.vehicle)
    local _, backMarkerDistance = AIUtil.getLastAttachedImplement(self.vehicle)

    --- Checks if the vehicle direction is inverted.
    local directionNode = self.vehicle:getAIDirectionNode()
    local _, _, dz = localToLocal(self.vehicle.rootNode, directionNode, 0, 0, 0)
    if dz < 0 then 
        self:debug('Starting turn is inverted, because the drive direction is inverted')
        frontMarkerDistance, backMarkerDistance = backMarkerDistance, frontMarkerDistance
    end

    self:debug('Starting a turn at waypoint %d, front marker %.1f, back marker %.1f', ix, frontMarkerDistance, backMarkerDistance)
    self.ppc:setShortLookaheadDistance()


    self.turnContext = TurnContext(self.vehicle, self.course, ix, ix + 1, self.turnNodes, self:getWorkWidth(),
            frontMarkerDistance, -backMarkerDistance, 0, 0)
    self.aiTurn = VineTurn(self.vehicle, self, self.ppc, self.proximityController, self.turnContext, self.course, self.workWidth)
    self.state = self.states.TURNING
end
