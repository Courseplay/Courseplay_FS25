--[[
This file is part of Courseplay (https://github.com/Courseplay/Courseplay_FS22)
Copyright (C) 2022 Peter Vaiko

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

]]--

--- The collision avoidance controller implements a simple algorithm to prevent an unloader
--- from crossing a combine's path and potentially colliding with it or blocking its way.
---
--- The controller checks if the own vehicle's course intersects with any active CP combine's course.
--- If they are, and the estimated arrival times of the combine and the own vehicle at that point are
--- within eteDiffThreshold seconds, the controller activates the collision avoidance warning.
---
---@class CollisionAvoidanceController
CollisionAvoidanceController = CpObject()

-- Only consider other vehicles within this (Eucledian) distance in meters
CollisionAvoidanceController.range = 50
-- Only check for collisions in this distance from the current waypoint on a course
CollisionAvoidanceController.lookahead = CollisionAvoidanceController.range / 2
-- Raise a warning if this vehicle's and the other vehicle's ETE at the intersection point
-- differ in less than eteDiffThreshold
CollisionAvoidanceController.eteDiffThreshold = 8
-- Warnings are cleared clearWarningDelayMs milliseconds after the controller detects
-- that there is no collision danger anymore. This is to allow the combine to move past
-- the collision point as the controller works with the current waypoints of the vehicles,
-- which are the waypoints in front of the vehicle.
CollisionAvoidanceController.clearWarningDelayMs = 3000

---@param strategy AIDriveStrategyCourse
function CollisionAvoidanceController:init(vehicle, strategy)
    self.vehicle = vehicle
    self.strategy = strategy
    self.warning = CpTemporaryObject()
end

function CollisionAvoidanceController:debug(...)
    CpUtil.debugVehicle(CpDebug.DBG_TRAFFIC, self.vehicle, 'CollisionAvoidanceController: ' .. string.format(...))
end

function CollisionAvoidanceController:isCollisionWarningActive()
    self:findPotentialCollisions()
    return self.warning:get()
end

function CollisionAvoidanceController:findPotentialCollisions()
    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if AIDriveStrategyCombineCourse.isActiveCpCombine(vehicle) then
            local d = calcDistanceFrom(self.vehicle.rootNode, vehicle.rootNode)
            if d < self.range then
                local myCourse = self.strategy:getCurrentCourse()
                local otherCourse = vehicle:getCpDriveStrategy():getCurrentCourse()
                local myDistanceToCollision, otherDistanceToCollision = myCourse:intersects(otherCourse, self.lookahead, true)
                if myDistanceToCollision then
                    -- our course intersects with this vehicle's course (lastSpeedReal is in m/ms)
                    -- for our own ETE, we always use the field speed and not the actual speed. This is to make sure
                    -- we come to a full stop on a warning and remain stopped while the warning is active
                    local myEte = myDistanceToCollision / (self.strategy:getFieldSpeed())
                    local otherEte = otherDistanceToCollision / (vehicle.lastSpeedReal * 1000)
                    -- self:debug('Checking %s at %.1f m, %.1f, ETE %.1f %.1f', CpUtil.getName(vehicle), d, myDistanceToCollision, myEte, otherEte)
                    if math.abs(myEte - otherEte) < self.eteDiffThreshold then
                        if not self.warning:get() or (self.warning:get() and vehicle ~= self.warningVehicle) then
                            -- no warning is active yet, or there is, but this is a different vehicle
                            self:debug('collision warning: my course intersects with %s in %.1f m, my ETE %.1f, other ETE %.1f',
                                    CpUtil.getName(vehicle), myDistanceToCollision, myEte, otherEte)
                        end
                        self.warningVehicle = vehicle
                        self.warning:set(true, self.clearWarningDelayMs)
                        return
                    end
                end
            end
        end
    end
    if self.warningVehicle and not self.warning:get() then
        self:debug('collision warning with %s cleared', CpUtil.getName(self.warningVehicle))
        self.warningVehicle = nil
    end
end