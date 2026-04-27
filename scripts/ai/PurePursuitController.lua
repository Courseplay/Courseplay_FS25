--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2018-2021 Peter Vaiko

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

--[[

This is a simplified implementation of a pure pursuit algorithm
to follow a two dimensional path consisting of waypoints.

See the paper

Steering Control of an Autonomous Ground Vehicle with Application to the DARPA
Urban Challenge By Stefan F. Campbell

We use the terminology of that paper here, like 'relevant path segment', 'goal point', etc. and follow the
algorithm to search for the goal point as described in this paper.

PURPOSE

1. Provide a goal point to steer towards to.
   Contrary to the old implementation, we are not steering to a waypoint, instead to a goal
   point which is in a given look ahead distance from the vehicle on the path.

2. Determine when to switch to the next waypoint (and avoid circling)
   Regardless of the above, the rest of the Courseplay code still needs to know the current
   waypoint as we progress along the path.

HOW TO USE

1. add a PPC to the vehicle with new()
2. when the vehicle starts driving, call initialize()
3. in every update cycle, call update(). This will calculate the goal point and the current waypoint
4. use the convenience functions getCurrentWaypointPosition(), reachedLastWaypoint()
   in your code instead of directly checking and manipulating vehicle.Waypoints. These provide the legacy behavior when
   the PPC is not active (for example due to reverse driving) or when disabled
6. you can use enable() and disable() to enable/disable the PPC. When disabled and you are using the above functions,
   it'll behave as the legacy code.

]]

---@class PurePursuitController
PurePursuitController = CpObject()

--- if the vehicle is more than cutOutDistanceLimit meters from the current segment's endpoints, cut-out the
--- controller to stop. Some error must have caused us to wander way off-track, unlikely to recover.
PurePursuitController.cutOutDistanceLimit = 50

-- constructor
function PurePursuitController:init(vehicle)
    self.normalLookAheadDistance = math.min(vehicle.maxTurningRadius, 6)
    self.shortLookaheadDistance = math.max(2, self.normalLookAheadDistance / 2)
    -- normal lookahead distance
    self.baseLookAheadDistance = self.normalLookAheadDistance
    -- adapted look ahead distance
    self.lookAheadDistance = self.baseLookAheadDistance
    self.temporaryLookAheadDistance = CpTemporaryObject(nil)
    -- when transitioning from forward to reverse, this close we have to be to the waypoint where we
    -- change direction before we switch to the next waypoint
    self.distToSwitchWhenChangingToReverse = 1
    self.vehicle = vehicle
    self:resetControlledNode()
    self.name = vehicle:getName()
    -- node on the current waypoint
    self.currentWpNode = WaypointNode(self.name .. '-currentWpNode', true)
    -- waypoint at the start of the relevant segment
    self.relevantWpNode = WaypointNode(self.name .. '-relevantWpNode', true)
    -- waypoint at the end of the relevant segment
    self.nextWpNode = WaypointNode(self.name .. '-nextWpNode', true)
    -- the current goal node
    self.goalWpNode = WaypointNode(self.name .. '-goalWpNode', false)
    -- vehicle position projected on the path, not used for anything other than debug display
    self.projectedPosNode = CpUtil.createNode(self.name .. '-projectedPosNode', 0, 0, 0)
    -- index of the first node of the path (where PPC is initialized and starts driving
    self.firstIx = 1
    self.crossTrackError = 0
    self.lastPassedWaypointIx = nil
    self.waypointPassedListeners = {}
    self.waypointChangeListeners = {}
    -- enable/disable stopping the vehicle when it is off-track (too far away from any waypoint)
    self.stopWhenOffTrack = CpTemporaryObject(true)
end

-- destructor
function PurePursuitController:delete()
    self.currentWpNode:destroy()
    self.relevantWpNode:destroy()
    self.nextWpNode:destroy()
    CpUtil.destroyNode(self.projectedPosNode)
    self.goalWpNode:destroy()
end

function PurePursuitController:debug(...)
    CpUtil.debugVehicle(CpDebug.DBG_PPC, self.vehicle, 'PPC: ' .. string.format(...))
end

function PurePursuitController:debugSparse(...)
    if g_updateLoopIndex % 100 == 0 then
        self:debug(...)
    end
end

---@param course Course
function PurePursuitController:setCourse(course)
    self.course = course
end

function PurePursuitController:getCourse()
    return self.course
end

--- Set an offset for the current course.
function PurePursuitController:setOffset(x, z)
    self.course:setOffset(x, z)
end

function PurePursuitController:getOffset()
    return self.course:getOffset()
end

--- Disable off-track detection temporarily, for instance while we know the vehicle must be driving
--- longer distances between two waypoints, like an unloader following a chopper through a turn, where
--- in some patterns the row end and the next row start are far apart.
function PurePursuitController:disableStopWhenOffTrack(milliseconds)
    self.stopWhenOffTrack:set(false, milliseconds)
end

--- Use a different node to track/control, for example the root node of a trailed implement
-- instead of the tractor's root node.
function PurePursuitController:setControlledNode(node)
    self.controlledNode = node
end

function PurePursuitController:getControlledNode()
    return self.controlledNode
end

--- reset controlled node to the default (vehicle's own direction node)
function PurePursuitController:resetControlledNode()
    self.controlledNode = self.vehicle:getAIDirectionNode()
end

-- initialize controller before driving
function PurePursuitController:initialize(ix)
	self.firstIx = ix
	-- relevantWpNode always points to the point where the relevant path segment starts
	self.relevantWpNode:setToWaypoint(self.course, self.firstIx )
	self.nextWpNode:setToWaypoint(self.course, self.firstIx)
	self.wpBeforeGoalPointIx = self.nextWpNode.ix
	self.currentWpNode:setToWaypoint(self.course, self.firstIx )
	self.course:setCurrentWaypointIx(self.firstIx)
	self.course:setLastPassedWaypointIx(nil)
	self:debug('initialized to waypoint %d of %d', self.firstIx, self.course:getNumberOfWaypoints())
	self.lastPassedWaypointIx = nil
    -- force calling the waypoint change callback right after initialization
    self.sendWaypointChange = { current = self.currentWpNode.ix, prev = self.currentWpNode.ix - 1}
	self.sendWaypointPassed = nil
	-- current goal point search case as described in the paper, for diagnostics only
	self.case = 0
end

-- Initialize to a waypoint when reversing.
-- TODO: this has to be called explicitly but could be done automatically by the vanilla initialize()
-- make sure the waypoint we initialize to is close to the controlled node, otherwise the PPC will
-- remain in initializing mode if the waypoint is too far back from the controlled node, and just
-- reverse forever
function PurePursuitController:initializeForReversing(ix)
    local reverserNode, debugText = self:getReverserNode(false)
    if reverserNode then
        self:debug('Reverser node %s found, initializing with it', debugText)
        -- don't use ix as it is, instead, find the waypoint closest to the reverser node
        local dPrev, d = math.huge, self.course:getWaypoint(ix):getDistanceFromNode(reverserNode)
        while d < dPrev and self.course:isReverseAt(ix) and ix < self.course:getNumberOfWaypoints() do
            dPrev = d
            ix = ix + 1
            d = self.course:getWaypoint(ix):getDistanceFromNode(reverserNode)
        end
    else
        self:debug('No reverser node found, initializing with default controlled node')
    end
    self:initialize(ix)
end

-- TODO: make this more generic and allow registering multiple listeners?
-- could also implement listeners for events like notify me when within x meters of a waypoint, etc.
function PurePursuitController:registerListeners(waypointListener, onWaypointPassedFunc, onWaypointChangeFunc)
    self.savedWaypointListener = self.waypointListener
    self.savedWaypointPassedListenerFunc = self.waypointPassedListenerFunc
    self.savedWaypointChangeListenerFunc = self.waypointChangeListenerFunc
    self.waypointListener = waypointListener
    self.waypointPassedListenerFunc = onWaypointPassedFunc
    self.waypointChangeListenerFunc = onWaypointChangeFunc
end

-- Restore the listeners that were registered before the last call of registerListeners(). If there were none,
-- do not restore anything
function PurePursuitController:restorePreviouslyRegisteredListeners()
    if self.savedWaypointListener ~= nil then
        self.waypointListener = self.savedWaypointListener
        self.waypointPassedListenerFunc = self.savedWaypointPassedListenerFunc
        self.waypointChangeListenerFunc = self.savedWaypointChangeListenerFunc
    end
end

function PurePursuitController:setLookaheadDistance(d)
    self.baseLookAheadDistance = d
end

function PurePursuitController:setNormalLookaheadDistance()
    self.baseLookAheadDistance = self.normalLookAheadDistance
end

function PurePursuitController:setShortLookaheadDistance()
    self.baseLookAheadDistance = self.shortLookaheadDistance
end

--- Set a short lookahead distance for ttlMs milliseconds
function PurePursuitController:setTemporaryShortLookaheadDistance(ttlMs)
    self.temporaryLookAheadDistance:set(self.shortLookaheadDistance, ttlMs)
end

function PurePursuitController:getLookaheadDistance()
    return self.lookAheadDistance
end

function PurePursuitController:setCurrentLookaheadDistance(cte)
    local la = self.temporaryLookAheadDistance:get() or self.baseLookAheadDistance
    self.lookAheadDistance = math.min(la + math.abs(cte), la * 2)
end

--- get index of current waypoint (one we are driving towards)
function PurePursuitController:getCurrentWaypointIx()
    return self.currentWpNode.ix
end

--- Get the current waypoint object
---@return Waypoint
function PurePursuitController:getCurrentWaypoint()
    return self.course:getWaypoint(self.currentWpNode.ix)
end

--- get index of relevant waypoint (one we are close to)
function PurePursuitController:getRelevantWaypointIx()
    return self.relevantWpNode.ix
end

function PurePursuitController:getLastPassedWaypointIx()
    return self.lastPassedWaypointIx
end

---@return number, string node that would be used for reversing, debug text explaining what node it is
function PurePursuitController:getReverserNode(suppressLog)
    if not self.reversingImplement then
        self.reversingImplement = AIUtil.getFirstReversingImplementWithWheels(self.vehicle,  suppressLog)
    end
    return AIUtil.getReverserNode(self.vehicle, self.reversingImplement, suppressLog)
end

--- When reversing, use the towed implement's node as a reference
function PurePursuitController:switchControlledNode()
    local lastControlledNode = self.controlledNode
    local debugText = 'AIDirectionNode'
    local reverserNode
    if self:isReversing() then
        reverserNode, debugText = self:getReverserNode(true)
        if reverserNode then
            self:setControlledNode(reverserNode)
        else
            self:resetControlledNode()
        end
    else
        self:resetControlledNode()
    end
    if self.controlledNode ~= lastControlledNode then
        self:debug('Switching controlled node to %s', debugText)
    end
end

function PurePursuitController:update()
    if not self.course then
        self:debugSparse('no course set.')
        return
    end
    self:showDebugTable()
    self:switchControlledNode()
    self:findRelevantSegment()
    self:findGoalPoint()
    self.course:setCurrentWaypointIx(self.currentWpNode.ix)
    self.course:setLastPassedWaypointIx(self.lastPassedWaypointIx)
    self:notifyListeners()
end

function PurePursuitController:showDebugTable()
    if self.course then
        if CpDebug:isChannelActive(CpDebug.DBG_COURSES, self.vehicle) then
            local info = {
                title = self.course:getName(),
                content = self.course:getDebugTable()
            }
            CpDebug:drawVehicleDebugTable(self.vehicle, { info })
        end
    end
end

function PurePursuitController:notifyListeners()
    if self.waypointListener then
        if self.sendWaypointChange then
            -- send waypoint change event for all waypoints between the previous and current to make sure
            -- we don't miss any
            self:debug('prev %s curr %s', self.sendWaypointChange.prev, self.sendWaypointChange.current)
            for ix = self.sendWaypointChange.prev + 1, self.sendWaypointChange.current do
                self.waypointListener[self.waypointChangeListenerFunc](self.waypointListener, ix, self.course)
            end
        end
        if self.sendWaypointPassed then
            self.waypointListener[self.waypointPassedListenerFunc](self.waypointListener, self.sendWaypointPassed, self.course)
        end
    end
    self.sendWaypointChange = nil
    self.sendWaypointPassed = nil
end

function PurePursuitController:havePassedWaypoint(wpNode)
    local vx, vy, vz = getWorldTranslation(self.controlledNode)
    local dx, _, dz = worldToLocal(wpNode.node, vx, vy, vz);
    local dFromNext = MathUtil.vector2Length(dx, dz)
    --self:debug('checking %d, dz: %.1f, dFromNext: %.1f', wpNode.ix, dz, dFromNext)
    local result = false
    if self.course:switchingDirectionAt(wpNode.ix) then
        -- switching direction at this waypoint, so this is pointing into the opposite direction.
        -- we have to make sure we drive up to this waypoint close enough before we switch to the next
        -- so wait until dz < 0, that is, we are behind the waypoint
        if dz < 0 then
            result = true
        end
    else
        -- we are not transitioning between forward and reverse
        -- we have passed the next waypoint if our dz in the waypoints coordinate system is positive, that is,
        -- when looking into the direction of the waypoint, we are ahead of it.
        -- Also, when on the process of aligning to the course, like for example the vehicle just started
        -- driving towards the first waypoint, we have to make sure we actually get close to the waypoint
        -- (as we may already be in front of it), so try get within the turn diameter * 2.
        if dz >= 0 and dFromNext < self.vehicle.maxTurningRadius * 4 then
            result = true
        end
    end
    if result then
        --and not self:reachedLastWaypoint() then
        if not self.lastPassedWaypointIx or (self.lastPassedWaypointIx ~= wpNode.ix) then
            self.lastPassedWaypointIx = wpNode.ix
            self:debug('waypoint %d passed, dz: %.1f %s %s', wpNode.ix, dz,
                    self.course.waypoints[wpNode.ix].rev and 'reverse' or '',
                    self.course:switchingDirectionAt(wpNode.ix) and 'switching direction' or '')
            -- notify listeners about the passed waypoint
            self.sendWaypointPassed = self.lastPassedWaypointIx
        end
    end
    return result
end

function PurePursuitController:havePassedAnyWaypointBetween(fromIx, toIx)
    local node = WaypointNode(self.name .. '-node', false)
    local result, passedWaypointIx = false, 0
    -- math.max so we do one loop even if toIx < fromIx
    --self:debug('checking between %d and %d', fromIx, toIx)
    for ix = fromIx, math.max(toIx, fromIx) do
        node:setToWaypoint(self.course, ix)
        if self:havePassedWaypoint(node) then
            result = true
            passedWaypointIx = ix
            break
        end

    end
    node:destroy()
    return result, passedWaypointIx
end

-- Finds the relevant segment.
-- Sets the vehicle's projected position on the path.
function PurePursuitController:findRelevantSegment()
    -- vehicle position
    local vx, vy, vz = getWorldTranslation(self.controlledNode)
    -- update the position of the relevant node (in case the course offset changed)
    self.relevantWpNode:setToWaypoint(self.course, self.relevantWpNode.ix)
    local lx, _, dzFromRelevant = worldToLocal(self.relevantWpNode.node, vx, vy, vz);
    self.crossTrackError = lx
    -- adapt our lookahead distance based on the error
    self:setCurrentLookaheadDistance(self.crossTrackError)
    -- projected vehicle position/rotation
    local px, py, pz = localToWorld(self.relevantWpNode.node, 0, 0, dzFromRelevant)
    local _, yRot, _ = getRotation(self.relevantWpNode.node)
    setTranslation(self.projectedPosNode, px, py, pz)
    setRotation(self.projectedPosNode, 0, yRot, 0)
    -- we check all waypoints between the relevant and the one before the goal point as the goal point
    -- may have moved several waypoints up if there's a very sharp turn for example and in that case
    -- the vehicle may never reach some of the waypoint in between.
    local passed, ix
    if self.course:switchingDirectionAt(self.nextWpNode.ix) then
        -- don't look beyond a direction switch as we'll always be past a reversing waypoint
        -- before we reach it.
        passed, ix = self:havePassedWaypoint(self.nextWpNode), self.nextWpNode.ix
    else
        passed, ix = self:havePassedAnyWaypointBetween(self.nextWpNode.ix, self.wpBeforeGoalPointIx)
    end
    if passed then
        self.relevantWpNode:setToWaypoint(self.course, ix, true)
        self.nextWpNode:setToWaypoint(self.course, self.relevantWpNode.ix + 1, true)
        if not self:reachedLastWaypoint() then
            -- disable debugging once we reached the last waypoint. Otherwise we'd keep logging
            -- until the user presses 'Stop driver'.
            self:debug('relevant waypoint: %d, next waypoint %d, crosstrack: %.1f',
                    self.relevantWpNode.ix, self.nextWpNode.ix, self.crossTrackError)
        end
    end
    if CpDebug:isChannelActive(CpDebug.DBG_PPC, self.vehicle) then
        DebugUtil.drawDebugLine(px, py + 3, pz, px, py + 1, pz, 1, 1, 0);
        DebugUtil.drawDebugNode(self.relevantWpNode.node, string.format('ix = %d\nrelevant\nnode', self.relevantWpNode.ix))
        DebugUtil.drawDebugNode(self.projectedPosNode, 'projected\nvehicle\nposition')
    end
end

-- Now, from the relevant section forward we search for the goal point, which is the one
-- lying lookAheadDistance in front of us on the path
-- this is the algorithm described in Chapter 2 of the paper
function PurePursuitController:findGoalPoint()

    local vx, _, vz = getWorldTranslation(self.controlledNode)
    --local vx, vy, vz = getWorldTranslation(self.projectedPosNode);

    -- create helper nodes at the relevant and the next wp. We'll move these up on the path until we reach the segment
    -- in lookAheadDistance
    local node1 = WaypointNode(self.name .. '-node1', false)
    local node2 = WaypointNode(self.name .. '-node2', false)

    -- starting at the relevant segment walk up the path to find the segment on
    -- which the goal point lies. This is the segment intersected by the circle with lookAheadDistance radius
    -- around the vehicle.
    local ix = self.relevantWpNode.ix
    while ix <= self.course:getNumberOfWaypoints() do
        node1:setToWaypoint(self.course, ix)
        node2:setToWaypointOrBeyond(self.course, ix + 1, self.lookAheadDistance)
        local x1, _, z1 = getWorldTranslation(node1.node)
        local x2, _, z2 = getWorldTranslation(node2.node)
        -- distance between the vehicle position and the ends of the segment
        local q1 = MathUtil.getPointPointDistance(x1, z1, vx, vz) -- distance from node 1
        local q2 = MathUtil.getPointPointDistance(x2, z2, vx, vz) -- distance from node 2
        local l = MathUtil.getPointPointDistance(x1, z1, x2, z2)  -- length of path segment (distance between node 1 and 2
        -- self:debug('ix=%d, q1=%.1f, q2=%.1f la=%.1f l=%.1f', ix, q1, q2, self.lookAheadDistance, l)

        -- case i (first node outside virtual circle but not yet reached) or (not the first node but we are way off the track)
        if (ix == self.firstIx and ix ~= self.lastPassedWaypointIx) and
                q1 >= self.lookAheadDistance and q2 >= self.lookAheadDistance then
            -- If we weren't on track yet (after initialization, on our way to the first/initialized waypoint)
            -- set the goal to the relevant WP
            self.goalWpNode:setToWaypoint(self.course, self.relevantWpNode.ix)
            self:setGoalTranslation()
            self:showGoalpointDiag(1, 'initializing, ix=%d, q1=%.1f, q2=%.1f, la=%.1f', ix, q1, q2, self.lookAheadDistance)
            -- and also the current waypoint is now at the relevant WP
            self:setCurrentWaypoint(self.relevantWpNode.ix)
            break
        end

        -- case ii (common case)
        if q1 <= self.lookAheadDistance and q2 >= self.lookAheadDistance then
            -- in some weird cases q1 may be 0 (when we calculate a course based on the vehicle position) so fix that
            -- to avoid a nan
            if q1 < 0.0001 then
                q1 = 0.1
            end
            local cosGamma = (q2 * q2 - q1 * q1 - l * l) / (-2 * l * q1)
            local p = q1 * cosGamma + math.sqrt(q1 * q1 * (cosGamma * cosGamma - 1) + self.lookAheadDistance * self.lookAheadDistance)
            local gx, _, gz = localToWorld(node1.node, 0, 0, p)
            self:setGoalTranslation(gx, gz)
            self.wpBeforeGoalPointIx = ix
            self:showGoalpointDiag(2, 'common case, ix=%d, q1=%.1f, q2=%.1f la=%.1f', ix, q1, q2, self.lookAheadDistance)
            -- current waypoint is the waypoint at the end of the path segment
            self:setCurrentWaypoint(ix + 1)
            --CpUtil.debugVehicle(CpDebug.DBG_PPC, self.vehicle, "PPC: %d, p=%.1f", self.currentWpNode.ix, p)
            break
        end

        -- cases iii, iv and v
        -- these two may have a problem and actually prevent the vehicle go back to the waypoint
        -- when wandering way off track, therefore we try to catch this case in case i
        if ix == self.relevantWpNode.ix and q1 >= self.lookAheadDistance and q2 >= self.lookAheadDistance then
            if math.abs(self.crossTrackError) <= self.lookAheadDistance then
                -- case iii (two intersection points)
                local p = math.sqrt(self.lookAheadDistance * self.lookAheadDistance - self.crossTrackError * self.crossTrackError)
                local gx, _, gz = localToWorld(self.projectedPosNode, 0, 0, p)
                self:setGoalTranslation(gx, gz)
                self.wpBeforeGoalPointIx = ix
                self:showGoalpointDiag(3, 'two intersection points, ix=%d, q1=%.1f, q2=%.1f, la=%.1f, cte=%.1f', ix, q1, q2,
                        self.lookAheadDistance, self.crossTrackError)
                -- current waypoint is the waypoint at the end of the path segment
                self:setCurrentWaypoint(ix + 1)
            else
                -- case iv (no intersection points)
                -- case v ( goal point dead zone)
                -- set the goal to the projected position
                local gx, _, gz = localToWorld(self.projectedPosNode, 0, 0, 0)
                self:setGoalTranslation(gx, gz)
                self.wpBeforeGoalPointIx = ix
                self:showGoalpointDiag(4, 'no intersection points, ix=%d, q1=%.1f, q2=%.1f, la=%.1f, cte=%.1f', ix, q1, q2,
                        self.lookAheadDistance, self.crossTrackError)
                -- current waypoint is the waypoint at the end of the path segment
                self:setCurrentWaypoint(ix + 1)
            end
            if (q1 > self.cutOutDistanceLimit) and (q2 > self.cutOutDistanceLimit) and self.stopWhenOffTrack:get() then
                CpUtil.infoVehicle(self.vehicle, 'vehicle off track, shutting off Courseplay now.')
                self.vehicle:stopCurrentAIJob(AIMessageCpError.new())
                return
            end
            break
        end
        -- none of the above, continue search with the next path segment
        ix = ix + 1
        -- unless there's a direction change here. This should only happen right after initialization and when
        -- the reference node is already beyond the direction switch waypoint. We should not skip that being
        -- the current waypoint otherwise the relevant waypoint won't be moved over the direction switch
        if self.course:switchingDirectionAt(ix) then
            -- force waypoint change
            self:showGoalpointDiag(100, 'switching direction while looking for goal point, ix=%d', ix)
            self.wpBeforeGoalPointIx = ix - 1
            self:setCurrentWaypoint(ix)
            break
        end
    end

    node1:destroy()
    node2:destroy()

    if CpDebug:isChannelActive(CpDebug.DBG_PPC, self.vehicle) then
        local gx, gy, gz = localToWorld(self.goalWpNode.node, 0, 0, 0)
        DebugUtil.drawDebugLine(gx, gy + 3, gz, gx, gy + 1, gz, 0, 1, 0);
        DebugUtil.drawDebugNode(self.currentWpNode.node, string.format('ix = %d\ncurrent\nwaypoint', self.currentWpNode.ix))
    end
end

-- set the goal WP node's position. This will make sure the goal node is on the same height
-- as the controlled node, avoiding issues when driving on non-level bridges where the controlled node
-- is not vertical and since the goal is very far below it, it will be much closer/further in the controlled
-- node's reference frame.
-- If everyone is on the same height, this error is negligible
function PurePursuitController:setGoalTranslation(x, z)
    local gx, _, gz = getWorldTranslation(self.goalWpNode.node)
    local _, cy, _ = getWorldTranslation(self.controlledNode)
    -- if there's an x, z passed in, use that, otherwise only adjust y to be the same as the controlled node
    setTranslation(self.goalWpNode.node, x or gx, cy + 1, z or gz)
end

-- set the current waypoint for the rest of Courseplay and to notify listeners
function PurePursuitController:setCurrentWaypoint(ix)
    -- this is the current waypoint for the rest of Courseplay code, the waypoint we are driving to
    -- but never, ever go back. Instead just leave this loop and keep driving to the current goal node
    if ix < self.currentWpNode.ix then
        if g_updateLoopIndex % 60 == 0 then
            self:debug("Won't step current waypoint back from %d to %d.", self.currentWpNode.ix, ix)
        end
    elseif ix >= self.currentWpNode.ix then
        local prevIx = self.currentWpNode.ix
        self.currentWpNode:setToWaypointOrBeyond(self.course, ix, self.lookAheadDistance)
        -- if ix > #self.course, currentWpNode.ix will always be set to #self.course and the change detection won't work
        -- therefore, only call listeners if ix <= #self.course
        if ix ~= prevIx and ix <= self.course:getNumberOfWaypoints() then
            -- remember to send notification at the end of the loop
            self.sendWaypointChange = { current = self.currentWpNode.ix, prev = prevIx }
        end
    end
end

function PurePursuitController:showGoalpointDiag(case, ...)
    local diagText = string.format(...)
    if CpDebug:isChannelActive(CpDebug.DBG_PPC, self.vehicle) then
        DebugUtil.drawDebugNode(self.goalWpNode.node, diagText)
        DebugUtil.drawDebugNode(self.controlledNode, 'controlled')
    end
    if case ~= self.case then
        self:debug(...)
        self.case = case
    end
end

--- Should we be driving in reverse based on the current position on course
function PurePursuitController:isReversing()
    if self.course then
        return self.course:isReverseAt(self:getCurrentWaypointIx()) or self.course:switchingToForwardAt(self:getCurrentWaypointIx())
    else
        return false
    end
end

-- goal point local position in the vehicle's coordinate system
function PurePursuitController:getGoalPointLocalPosition()
    return localToLocal(self.goalWpNode.node, self.controlledNode, 0, 0, 0)
end

-- goal point normalized direction
function PurePursuitController:getGoalPointDirection()
    local gx, _, gz = localToLocal(self.goalWpNode.node, self.controlledNode, 0, 0, 0)
    local dx, dz = MathUtil.vector2Normalize(gx, gz)
    -- check for NaN
    if dx ~= dx or dz ~= dz then
        return 0, 0
    end
    return dx, dz
end

function PurePursuitController:getGoalPointPosition()
    return getWorldTranslation(self.goalWpNode.node)
end

function PurePursuitController:getCurrentWaypointPosition()
    return self:getGoalPointPosition()
end

function PurePursuitController:getCurrentWaypointYRotation()
    return self.course:getYRotationCorrectedForDirectionChanges(self.currentWpNode.ix)
end

function PurePursuitController:getCrossTrackError()
    return self.crossTrackError
end

function PurePursuitController:reachedLastWaypoint()
    return self.relevantWpNode.ix >= self.course:getNumberOfWaypoints()
end

function PurePursuitController:haveJustPassedWaypoint(ix)
    return self.lastPassedWaypointIx and self.lastPassedWaypointIx == ix or false
end

function PurePursuitController:haveAlreadyPassedWaypoint(ix)
    return self.lastPassedWaypointIx and self.lastPassedWaypointIx <= ix or false
end