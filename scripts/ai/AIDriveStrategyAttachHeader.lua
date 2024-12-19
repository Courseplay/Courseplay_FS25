--[[
This file is part of Courseplay (https://github.com/Courseplay/Courseplay_FS25)
Copyright (C) 2023 Courseplay Dev Team

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

Drive strategy for pickup up the header of an trailer, 
which needs to be attached to the harvester.

1) Detach the trailer at the start position of this strategy.
2) Drives forward a few meters
3) Finds a path to the header joint an drives there with an offset for alignment.
4) Drives straight to the header, until it can be attached.
5) Attach the header and reverse back a bit.
6) Give back control to the job instance, as the strategy has finished.

]]--

---@class AIDriveStrategyAttachHeader : AIDriveStrategyCourse
AIDriveStrategyAttachHeader = CpObject(AIDriveStrategyCourse)

AIDriveStrategyAttachHeader.myStates = {
    WAITING_FOR_DETACH_TO_FINISH = {},
    DRIVING_AWAY_FROM_HEADER = {}, --- Drives a small distance forwards after detaching
    DRIVING_TO_HEADER = {}, --- Drives close to the header with the pathfinder
    DRIVING_TO_ATTACH_CUTTER = {}, --- Drives the last few meters to the cutter for attaching.
    WAITING_FOR_ATTACH_TO_START = {}, --- Waits a bit, to make sure the harvester stands still.
    WAITING_FOR_ATTACH_TO_FINISH = {}, --- Waits until the attach animation finished.
    REVERSING_FROM_CUTTER = {} --- If the cutter was on an extern trailer, drive back a bit.
}
AIDriveStrategyAttachHeader.MODES = {
    ATTACH_HEADER_FROM_ATTACHED_TRAILER = 1, --- The cutter/header is on an extern trailer.
    ATTACH_HEADER_WITH_WHEELS_ATTACHED = 2, --- The cutter/header is foldable with attached wheels for transport without an extra trailer.
}
AIDriveStrategyAttachHeader.DRIVING_AWAY_FROM_HEADER_FORWARD_DISTANCE = 6

function AIDriveStrategyAttachHeader:init(task, job)
    AIDriveStrategyCourse.init(self, task, job)
    AIDriveStrategyCourse.initStates(self, AIDriveStrategyAttachHeader.myStates)
    self.state = self.states.INITIAL
    self.debugChannel = CpDebug.DBG_FIELDWORK
    self.mode = self.MODES.ATTACH_HEADER_FROM_ATTACHED_TRAILER
end

--- The fieldwork course is not needed for this strategy.
function AIDriveStrategyAttachHeader:isGeneratedCourseNeeded()
    return false
end

function AIDriveStrategyAttachHeader:delete()
    if self.cutterNode then
        CpUtil.destroyNode(self.cutterNode)
    end
    AIDriveStrategyCourse.delete(self)
end

function AIDriveStrategyAttachHeader:initializeImplementControllers(vehicle)

    if AIUtil.hasCutterAsTrailerAttached(vehicle) then
        self.mode = self.MODES.ATTACH_HEADER_WITH_WHEELS_ATTACHED
        self:debug("A cutter/header with foldable wheels is attached at the back.")
        self.trailer = AIUtil.getImplementWithSpecialization(self.vehicle, Cutter)
    else
        self.mode = self.MODES.ATTACH_HEADER_FROM_ATTACHED_TRAILER
        self:debug("A cutter/header on a separate trailer is attached on the back.")
        self.trailer = AIUtil.getImplementWithSpecialization(self.vehicle, DynamicMountAttacher)
        self.dynamicMountAttacherController = DynamicMountAttacherController(vehicle, self.trailer)
    end
    self.attachableController = AttachableController(vehicle, self.trailer)
    self.attacherJointController = AttacherJointController(vehicle, vehicle)
    self:appendImplementController(self.attacherJointController)
    --- This Area is not really needed, as the pathfinder finds the trailer collision.
    --- But it might be a good idea to change this to only include the attacher area.
    --- The area to avoid around the attacher might need to be larger. 
    self.trailerAreaToAvoid = PathfinderUtil.NodeArea.createVehicleArea(self.trailer)
end

function AIDriveStrategyAttachHeader:setAllStaticParameters()
    AIDriveStrategyCourse.setAllStaticParameters(self)
    -- make sure we have a good turning radius set
    self.turningRadius = AIUtil.getTurningRadius(self.vehicle, true)
    self.proximityController:registerIgnoreObjectCallback(self, self.ignoreProximityObject)
end

function AIDriveStrategyAttachHeader:startWithoutCourse(jobParameters)
    self.course = Course.createStraightForwardCourse(self.vehicle, 25)
    self:startCourse(self.course, 1)
end

function AIDriveStrategyAttachHeader:update(dt)
    -- to always have a valid course (for the traffic conflict detector mainly)
    AIDriveStrategyCourse.update(self, dt)
    self:updateImplementControllers(dt)
    if CpDebug:isChannelActive(CpDebug.DBG_PATHFINDER, self.vehicle) then
        if self.pathfinder then
            PathfinderUtil.showNodes(self.pathfinder)
        end
        if self.trailerAreaToAvoid then
            --  DebugUtil.drawDebugCube(self.trailerAreaNode, self.trailer.size.width, self.trailer.size.height, self.trailer.size.length, 0, 0, 1)
            self.trailerAreaToAvoid:drawDebug()
        end
    end
    if CpDebug:isChannelActive(CpDebug.DBG_FIELDWORK, self.vehicle) then
        if self.course and self.course:isTemporary() then
            self.course:draw()
        elseif self.ppc:getCourse() and self.ppc:getCourse():isTemporary() then
            self.ppc:getCourse():draw()
        end
        if self.cutterNode then
            CpUtil.drawDebugNode(self.cutterNode, false, 3)
        end
    end
end

function AIDriveStrategyAttachHeader:getDriveData(dt, vX, vY, vZ)
    self:updateLowFrequencyImplementControllers()

    local moveForwards = not self.ppc:isReversing()
    local gx, gz
    if not moveForwards then
        local maxSpeed
        gx, gz, maxSpeed = self:getReverseDriveData()
        self:setMaxSpeed(maxSpeed)
    else
        gx, _, gz = self.ppc:getGoalPointPosition()
    end

    if self.state == self.states.WAITING_FOR_PATHFINDER then
        self:setMaxSpeed(0)
    elseif self.state == self.states.INITIAL then
        self:setMaxSpeed(0)
        if not self.settings.automaticCutterAttach:getValue() then
            self.vehicle:stopCurrentAIJob(AIMessageErrorAutomaticCutterAttachNotActive.new())
        else
            self.attachableController:detach()
            self.state = self.states.WAITING_FOR_DETACH_TO_FINISH
        end
    elseif self.state == self.states.WAITING_FOR_DETACH_TO_FINISH then
        self:setMaxSpeed(0)
        if not self.attachableController:isDetachActive() then
            Markers.setMarkerNodes(self.vehicle)
            self:setFrontAndBackMarkers()
            --- Detach has finished, so need make sure the reverse driver gets updated.
            self.reverser = AIReverseDriver(self.vehicle, self.ppc)
            local course = Course.createStraightForwardCourse(self.vehicle, self.DRIVING_AWAY_FROM_HEADER_FORWARD_DISTANCE)
            self:startCourse(course, 1)
            self.state = self.states.DRIVING_AWAY_FROM_HEADER
        end
    elseif self.state == self.states.DRIVING_AWAY_FROM_HEADER then
        self:setMaxSpeed(self.settings.fieldSpeed:getValue())
    elseif self.state == self.states.DRIVING_TO_HEADER then
        self:setMaxSpeed(self.settings.fieldSpeed:getValue())
    elseif self.state == self.states.DRIVING_TO_ATTACH_CUTTER then
        --- Slowdown near the header, to allow smooth attach timing.
        local _, _, z = localToLocal(self.attacherJointController:getCutterJointPositionNode(),
                self.cutterNode, 0, 0, 0)
        local speed = CpMathUtil.clamp(-2 * z, 1, self.settings.reverseSpeed:getValue())
        self:setMaxSpeed(speed)
        if self.attacherJointController:canAttachCutter() then
            Timer.createOneshot(120, function()
                --- Wait a small time, until the harvester stands still.
                self.state = self.states.WAITING_FOR_ATTACH_TO_START
            end)
        end
    elseif self.state == self.states.WAITING_FOR_ATTACH_TO_START then
        self:setMaxSpeed(0)
        if self.attacherJointController:attach() or self.attacherJointController:isAttachActive() then
            self.state = self.states.WAITING_FOR_ATTACH_TO_FINISH
        else
            self.vehicle:stopCurrentAIJob(AIMessageErrorCutterNotSupported.new())
        end
    elseif self.state == self.states.WAITING_FOR_ATTACH_TO_FINISH then
        self:setMaxSpeed(0)
        if not self.attacherJointController:isAttachActive() then
            self:attachHasFinished()
        end
    elseif self.state == self.states.REVERSING_FROM_CUTTER then
        self:setMaxSpeed(self.settings.reverseSpeed:getValue())
    end

    self:checkProximitySensors(moveForwards)
    return gx, gz, moveForwards, self.maxSpeed, 100
end

--- Ignores the proximity sensor on direct approach to the header/cutter for pickup.
---@param object any
---@param vehicle any
---@param moveForwards any
---@return boolean
function AIDriveStrategyAttachHeader:ignoreProximityObject(object, vehicle, moveForwards)
    if self.state == self.states.DRIVING_TO_ATTACH_CUTTER or self.state == self.states.DRIVING_TO_HEADER then
        if vehicle == self.trailer then
            return true
        end
        if self.dynamicMountAttacherController then
            if vehicle == self.dynamicMountAttacherController:getMountedImplement() then
                return true
            end
        end
    end
end

-----------------------------------------------------------------------------------------------------------------------
--- Pathfinding
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyAttachHeader:startPathfindingToCutter()
    if not self.pathfinder or not self.pathfinder:isActive() then
        self.state = self.states.WAITING_FOR_PATHFINDER
        local goalNode, rootNode
        if self.mode == self.MODES.ATTACH_HEADER_FROM_ATTACHED_TRAILER then
            goalNode = self.dynamicMountAttacherController:getCutterJointPositionNode()
            rootNode = self.dynamicMountAttacherController:getMountedImplement().rootNode
        else
            goalNode = self.attachableController:getCutterJointPositionNode()
            rootNode = self.trailer.rootNode
        end
        local x, _, z = getWorldTranslation(goalNode)
        local dirX, _, dirZ = localDirectionToWorld(rootNode, 0, 0, 1)
        local rotY = MathUtil.getYRotationFromDirection(dirX, dirZ)
        if not self.cutterNode then
            self.cutterNode = CpUtil.createNode("cutterNode", x, z, rotY)
        else
            setTranslation(self.cutterNode, x, 0, z)
            setRotation(self.cutterNode, 0, rotY, 0)
        end
        local length = AIUtil.getLength(self.vehicle)

        local context = PathfinderContext(self.vehicle)
        context:mustBeAccurate(false):allowReverse(true):offFieldPenalty(0)
        context:vehiclesToIgnore({ self.vehicle }):areaToAvoid(self.trailerAreaToAvoid)
        context:ignoreFruit()
        local result
        self.pathfinder, result = PathfinderUtil.startPathfindingFromVehicleToNode(
                self.cutterNode, 0, -math.max(1.5 * length, 1.5 * self.turningRadius), context)
        if result.done then
            return self:onPathfindingDoneToCutter(result)
        else
            self:setPathfindingDoneCallback(self, self.onPathfindingDoneToCutter)
            return true
        end
    else
        self:debug('Pathfinder already active')
    end
end

function AIDriveStrategyAttachHeader:onPathfindingDoneToCutter(result)
    if result.path and #result.path > 2 then
        local course = Course(self.vehicle, CpMathUtil.pointsToGameInPlace(result.path), true)
        self:startCourse(course, 1)
        self.state = self.states.DRIVING_TO_HEADER
        return true
    else
        self:debug("Failed to find path to header!")
        self.vehicle:stopCurrentAIJob(AIMessageCpErrorNoPathFound.new())
        return false
    end
end

function AIDriveStrategyAttachHeader:attachHasFinished()
    if self.mode == self.MODES.ATTACH_HEADER_FROM_ATTACHED_TRAILER then
        Markers.setMarkerNodes(self.vehicle)
        --distance could be reduced, but leads into some combine driving back- and forwards for small distances to get arround the header wagon
        local course = Course.createStraightReverseCourse(self.vehicle, self.workWidth + self.turningRadius * 1.1, 0)
        self:startCourse(course, 1)
        self.state = self.states.REVERSING_FROM_CUTTER
    else
        --- The header needs to be folded, as currently the wheels for transport are active.
        self.trailer:setFoldDirection(self.trailer.spec_foldable.turnOnFoldDirection or 1)
        self:setCurrentTaskFinished()
    end
end

-----------------------------------------------------------------------------------------------------------------------
--- Event listeners
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyAttachHeader:onWaypointPassed(ix, course)
    if course:isLastWaypointIx(ix) then
        if self.state == self.states.DRIVING_AWAY_FROM_HEADER then
            self:startPathfindingToCutter()
        elseif self.state == self.states.DRIVING_TO_HEADER then
            local course = Course.createFromNodeToNode(self.vehicle, self.vehicle:getAIDirectionNode(),
                    self.cutterNode, 0, 0, 0, 3, false)
            self:startCourse(course, 1)
            self.state = self.states.DRIVING_TO_ATTACH_CUTTER
        elseif self.state == self.states.DRIVING_TO_ATTACH_CUTTER then
            if AIUtil.hasImplementWithSpecialization(self.vehicle, Cutter) then
                self:attachHasFinished()
            else
                self:info("Attaching didn't work!")
                self.vehicle:stopCurrentAIJob(AIMessageCpErrorNoPathFound.new())
            end
        elseif self.state == self.states.REVERSING_FROM_CUTTER then
            self:setCurrentTaskFinished()
        end
    end
end
