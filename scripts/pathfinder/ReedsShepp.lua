--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2020 Peter Vaiko

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General function License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General function License for more details.

You should have received a copy of the GNU General function License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

This implementation of the Reeds-Schepp curve algorithm is based on
Matt Bradley's master thesis and his C# code at
https://github.com/mattbradley/AutonomousCar
--]]

--- @class ReedsShepp
ReedsShepp = CpObject()

-- The PathWords enum lists every possible Reeds-Shepp pattern. L, S, or R described the steering direction (left, straight, or right),
-- and f or b describe the gear (forward or backward).
-- Some may have attributes added so simpler driving patterns can be preferred even if they are slightly longer than
-- a more complicated one.
ReedsShepp.PathWords =
{
    LfSfLf = {p = 0.90, startForward = true, forwardOnly = true}, -- Reeds-Shepp 8.1: CSC, same turn
    LbSbLb = {p = 0.93},
    RfSfRf = {p = 0.90, startForward = true, forwardOnly = true},
    RbSbRb = {p = 0.93},


    LfSfRf = {p = 0.90, startForward = true, forwardOnly = true}, -- Reeds-Shepp 8.2: CSC, different turn
    LbSbRb = {p = 0.93},
    RfSfLf = {p = 0.90, startForward = true, forwardOnly = true},
    RbSbLb = {p = 0.93},

    LfRbLf = {p = 0.93, startForward = true}, -- Reeds-Shepp 8.3: C|C|C
    LbRfLb = {p = 0.94},
    RfLbRf = {p = 0.93, startForward = true},
    RbLfRb = {p = 0.94},

    LfRbLb = {p = 0.93, startForward = true}, -- Reeds-Shepp 8.4: C|CC
    LbRfLf = {p = 0.94},
    RfLbRb = {p = 0.93, startForward = true},
    RbLfRf = {p = 0.94},
    LfRfLb = {p = 0.93, startForward = true}, -- Reeds-Shepp 8.4: CC|C
    LbRbLf = {p = 0.94},
    RfLfRb = {p = 0.93, startForward = true},
    RbLbRf = {p = 0.94},

    LfRufLubRb = {startForward = true}, -- Reeds-Shepp 8.7: CCu|CuC
    LbRubLufRf = {},
    RfLufRubLb = {startForward = true},
    RbLubRufLf = {},

    LfRubLubRf = {startForward = true}, -- Reeds-Shepp 8.8: C|CuCu|C
    LbRufLufRb = {},
    RfLubRubLf = {startForward = true},
    RbLufRufLb = {},

    LfRbpi2SbLb = {startForward = true}, -- Reeds-Shepp 8.9: C|C(pi/2)SC, same turn
    LbRfpi2SfLf = {},
    RfLbpi2SbRb = {startForward = true},
    RbLfpi2SfRf = {},

    LfRbpi2SbRb = {startForward = true}, -- Reeds-Shepp 8.10: C|C(pi/2)SC, different turn
    LbRfpi2SfRf = {},
    RfLbpi2SbLb = {startForward = true},
    RbLfpi2SfLf = {},

    LfSfRfpi2Lb = {startForward = true}, -- Reeds-Shepp 8.9 (reversed): CSC(pi/2)|C, same turn
    LbSbRbpi2Lf = {},
    RfSfLfpi2Rb = {startForward = true},
    RbSbLbpi2Rf = {},

    LfSfLfpi2Rb = {startForward = true}, -- Reeds-Shepp 8.10 (reversed): CSC(pi/2)|C, different turn
    LbSbLbpi2Rf = {},
    RfSfRfpi2Lb = {startForward = true},
    RbSbRbpi2Lf = {},

    LfRbpi2SbLbpi2Rf = {startForward = true}, -- Reeds-Shepp 8.11: C|C(pi/2)SC(pi/2)|C
    LbRfpi2SfLfpi2Rb = {},
    RfLbpi2SbRbpi2Lf = {startForward = true},
    RbLfpi2SfRfpi2Lb = {}
}

--- The paths ending in forward gear
ReedsShepp.ForwardEndingPathWords = {}
for key, word in pairs(ReedsShepp.PathWords) do
    if string.sub(key, -1) == 'f' then
        ReedsShepp.ForwardEndingPathWords[key] = word
    end
end

-- The ReedsSheppAction class represents a single steering and motion action over some length.
---@class ReedsShepp.Action
ReedsShepp.Action = CpObject()
function ReedsShepp.Action:init(steer, gear, length)
    self.steer = steer
    self.gear = gear
    self.length = length
end

function ReedsShepp.Action:__tostring()
    local steer = 'Straight'
    if self.steer == Steer.Left then
        steer = 'Left'
    elseif self.steer == Steer.Right then
        steer = 'Right'
    end
    local gear = self.gear == Gear.Forward and 'Forward' or 'Backward'
    return string.format('%s %s %.1f\n', steer, gear, self.length)

end
--- The ReedsSheppActionSet class is a set of ReedsSheppActions. As actions are added, their lengths are summed together.
--- The total cost of the set can be calculated using a reverse gear cost and a gear switch cost.
---@class ReedsShepp.ActionSet : AnalyticSolution
ReedsShepp.ActionSet = CpObject(AnalyticSolution)

function ReedsShepp.ActionSet:init(length)
    self.actions = {}
    self.length = length or 0
end

function ReedsShepp.ActionSet:getLength(turnRadius)
    return self.length * turnRadius
end

function ReedsShepp.ActionSet:addAction(steer, gear, length)
    table.insert(self.actions, ReedsShepp.Action(steer, gear, length))
    self.length = self.length + length
end

function ReedsShepp.ActionSet:calculateCost(unit, reverseCostMultiplier, gearSwitchCost)
    if reverseCostMultiplier == 1 and gearSwitchCost == 0 then return self.length * unit end
    if self.length == math.huge or #self.actions == 0 then return math.huge end
    local cost = 0
    local prevGear = self.actions[1].gear
    for _, a in ipairs(self.actions) do
        local actionCost = a.length * unit
        if a.gear == Gear.Backward then
            actionCost = actionCost * reverseCostMultiplier
        end
        if a.gear ~= prevGear then
            actionCost = actionCost + gearSwitchCost
        end
        prevGear = a.gear
        cost = cost + actionCost
    end
    return cost
end

function ReedsShepp.ActionSet:__tostring()
    local str = ''
    for _, action in ipairs(self.actions) do
        str = str .. tostring(action)
    end
    return str
end


---@param start State3D
function ReedsShepp.ActionSet:getWaypoints(start, turnRadius)
    local prev = State3D.copy(start)
		-- start is always forward, make sure if we generated a path starting in reverse is now
	  -- reflected in the first waypoint, otherwise the first wp would always be forward
	  prev.gear = self.actions[1].gear
    local waypoints = {}
    table.insert(waypoints, prev)
    for _, action in ipairs(self.actions) do
        -- waypoints are 1 m apart, but make sure there are at least 12 waypoints per half circle
        -- even with very small radii
        local n = math.ceil(math.max(action.length * turnRadius, action.length / math.pi * 12))
        if action.steer ~= Steer.Straight then
            local pieceAngle = action.length / n

            local phi = pieceAngle / 2
            local sinPhi = math.sin(phi)
            local L = 2 * sinPhi * turnRadius
            local dx = L * math.cos(phi)
            local dy = L * sinPhi

            if action.steer == Steer.Right then
                dy = -dy
                pieceAngle = -pieceAngle
            end
            if action.gear == Gear.Backward then
                dx = -dx
                pieceAngle = -pieceAngle
            end

            for _ = 1, n do
                prev = State3D.copy(prev)
                local v = Vector(dx, dy)
                prev:add(v:rotate(prev.t))
                prev:addHeading(pieceAngle)
                prev.gear = action.gear
                prev.steer = action.steer
                table.insert(waypoints, prev)
            end
        else
            local pieceLength = action.length * turnRadius / n
            local dx = pieceLength * math.cos(prev.t)
            local dy = pieceLength * math.sin(prev.t)
            if action.gear == Gear.Backward then
                dx = -dx
                dy = -dy
            end
            for _ = 1, n do
                prev = State3D(dx + prev.x, dy + prev.y, prev.t, 0, prev, action.gear, action.steer)
                table.insert(waypoints, prev)
            end
        end
    end
    return waypoints
end
