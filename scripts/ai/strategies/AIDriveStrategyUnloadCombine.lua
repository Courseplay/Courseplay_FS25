--[[
This file is part of Courseplay (https://github.com/Courseplay/Courseplay_FS25)
Copyright (C) 2022 Peter Vaiko

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
]]--

--[[

How do we make sure the unloader does not collide with the combine?

1. ProximitySensor

The ProximitySensor is a generic AIDriver feature.

The combine has a proximity sensor on the back and will slow down and stop
if something is in range.

The unloader has a proximity sensor on the front to prevent running into the combine
and to swerve other vehicles in case of a head on collision for example.

In some states, for instance when unloading choppers, the tractor disables the generic
speed control as it has to drive very close to the chopper.

There is an additional proximity sensor dedicated to following the chopper. This has
all controlling features disabled.

2. Turns

The combine stops when discharging during a turn, so at the end of a row or headland turn
it won't start the turn until it is empty.

3. Combine Ready For Unload

The unloader can also ask the combine if it is ready to unload (isReadyToUnload()), as we
expect the combine to know best when it is going to perform some maneuvers.

4. Cooperative Collision Avoidance Using the TrafficController

This is currently screwed up...

---------------------------------------------
--- Unload target possibilities
---------------------------------------------

1. Combines working on an field(no chopper!)

2. Silo loader picking up fill types dropped to the ground(heap) on the field or near the field.

---------------------------------------------
--- Unload the loaded fill volume possibilities
---------------------------------------------

1. Auger wagon can unload to nearby trailers

2. Trailer can be sent to unload either with Autodrive or Giants unloader.

3. Unloading on the field, which means dropping it on the ground to create an heap.

]]--

--- Strategy to unload combines or stationary silo loaders.
---@class AIDriveStrategyUnloadCombine : AIDriveStrategyCourse
---@field combineUnloadStates table
---@field trailerUnloadStates table
---@field fieldUnloadStates table
AIDriveStrategyUnloadCombine = CpObject(AIDriveStrategyCourse)

-- when moving out of way of another vehicle, move at least so many meters
AIDriveStrategyUnloadCombine.minDistanceWhenMovingOutOfWay = 5
-- when moving out of way of another vehicle, move at most so many meters
AIDriveStrategyUnloadCombine.maxDistanceWhenMovingOutOfWay = 25
AIDriveStrategyUnloadCombine.safeManeuveringDistance = 30 -- distance to keep from a combine not ready to unload
AIDriveStrategyUnloadCombine.pathfindingRange = 5 -- won't do pathfinding if target is closer than this
-- The normal limit to apply a penalty for the pathfinder. This is relatively low to keep the unloader further
-- away from the fruit.
AIDriveStrategyUnloadCombine.maxFruitPercent = 10
AIDriveStrategyUnloadCombine.proximitySensorRange = 15
AIDriveStrategyUnloadCombine.maxDirectionDifferenceDeg = 35 -- under this angle the unloader considers itself aligned with the combine
-- Add a short straight section to align with the combine's course in case it is late for the rendezvous
AIDriveStrategyUnloadCombine.driveToCombineCourseExtensionLength = 10
AIDriveStrategyUnloadCombine.targetDistanceBehindChopper = 1

-- Developer hack: to check the class of an object one should use the is_a() defined in CpObject.lua.
-- However, when we reload classes on the fly during the development, the is_a() calls in other modules still
-- have the old class definition (for example CombineUnloadManager.lua) of this class and thus, is_a() fails.
-- Therefore, use this instead, this is safe after a reload.
AIDriveStrategyUnloadCombine.isACombineUnloadAIDriver = true

-- when calculating a course to a trailer, do not end the course right at the target fill node, instead
-- unloadTargetOffset meters before that. This allows for a little distance to stop after the tractor
-- reaches the last waypoint, and the logic in unloadAugerWagon() will move the rig to the exact position anyway.
AIDriveStrategyUnloadCombine.unloadTargetOffset = 1.5

--- Offset to apply at the goal marker, so we don't crash with an empty unloader waiting there with the same position.
AIDriveStrategyUnloadCombine.invertedGoalPositionOffset = -4.5

--- Field unload constants
AIDriveStrategyUnloadCombine.siloAreaOffsetFieldUnload = 2
AIDriveStrategyUnloadCombine.unloadCourseLengthFieldUnload = 50

--- Unload modes
AIDriveStrategyUnloadCombine.UNLOAD_TYPES = {
    COMBINE = 1,
    SILO_LOADER = 2
}

---------------------------------------------
--- State properties
---------------------------------------------
--[[
    fuelSaveAllowed : boolean              
    collisionAvoidanceEnabled : boolean
    proximityControllerDisabled : boolean
    openCoverAllowed : boolean
    moveablePipeDisabled : boolean
    vehicle : table|nil
    holdCombine : boolean
]]

---------------------------------------------
--- Shared states
---------------------------------------------
AIDriveStrategyUnloadCombine.myStates = {
    IDLE = { fuelSaveAllowed = true }, --- Only allow fuel save, if the unloader is waiting for a combine.
    WAITING_FOR_PATHFINDER = {},
    MOVING_BACK_BEFORE_PATHFINDING = { pathfinderController = nil, pathfinderContext = nil }, -- there is an obstacle ahead, move back a bit so the pathfinder can succeed
    --- States to maneuver away from combines and so on.
    --- No need to be assigned to a combine!
    MOVING_BACK = { vehicle = nil, holdCombine = false, denyBackupRequest = true },
    MOVING_BACK_WITH_TRAILER_FULL = { vehicle = nil, holdCombine = false, denyBackupRequest = true }, -- moving back from a combine we just unloaded (not assigned anymore)
    BACKING_UP_FOR_REVERSING_COMBINE = { vehicle = nil, denyBackupRequest = true }, -- reversing as long as the combine is reversing
    MOVING_BACK_FOR_HEADLAND_TURN = { vehicle = nil, holdCombine = false, denyBackupRequest = true }, -- making room for the harvester performing a headland turn
    MOVING_AWAY_FROM_OTHER_VEHICLE = { vehicle = nil, denyBackupRequest = true }, -- moving until we have enough space between us and an other vehicle
    WAITING_FOR_MANEUVERING_COMBINE = {},
    DRIVING_BACK_TO_START_POSITION_WHEN_FULL = {}, -- Drives to the start position with a trailer attached and gives control to giants or AD there.
    HANDLE_CHOPPER_180_TURN = { reversing = false, denyBackupRequest = true },
    HANDLE_CHOPPER_HEADLAND_TURN = { reversing = false, denyBackupRequest = true },
    FOLLOW_CHOPPER_THROUGH_TURN = {}
}

-------------------------------------------------
--- Unloading of a combine or silo loader states
--- Needs an assigned vehicle to work!
-------------------------------------------------
AIDriveStrategyUnloadCombine.myCombineUnloadStates = {
    DRIVING_TO_COMBINE = { collisionAvoidanceEnabled = true },
    DRIVING_TO_MOVING_COMBINE = { collisionAvoidanceEnabled = true },
    UNLOADING_MOVING_COMBINE = { openCoverAllowed = true },
    UNLOADING_STOPPED_COMBINE = { openCoverAllowed = true },
}

---------------------------------------------
--- Unloading into trailer states
---------------------------------------------
AIDriveStrategyUnloadCombine.myTrailerUnloadStates = {
    DRIVING_TO_SELF_UNLOAD = { collisionAvoidanceEnabled = true },
    WAITING_FOR_AUGER_PIPE_TO_OPEN = {},
    UNLOADING_AUGER_WAGON = {},
    MOVING_TO_NEXT_FILL_NODE = { moveablePipeDisabled = true },
    MOVING_AWAY_FROM_UNLOAD_TRAILER = { moveablePipeDisabled = true },
}

---------------------------------------------
--- Field unload states states
---------------------------------------------
AIDriveStrategyUnloadCombine.myFieldUnloadStates = {
    DRIVE_TO_FIELD_UNLOAD_POSITION = { collisionAvoidanceEnabled = true },
    WAITING_UNTIL_FIELD_UNLOAD_IS_ALLOWED = {},
    PREPARE_FOR_FIELD_UNLOAD = {},
    DRIVE_TO_REVERSE_FIELD_UNLOAD_POSITION = {},
    REVERSING_TO_THE_FIELD_UNLOAD_HEAP = {},
    UNLOADING_ON_THE_FIELD = { proximityControllerDisabled = true },
    DRIVE_TO_FIELD_UNLOAD_PARK_POSITION = {},
}

--- Register all active unloaders here to access them fast.
AIDriveStrategyUnloadCombine.activeUnloaders = {}

function AIDriveStrategyUnloadCombine:init(task, job)
    AIDriveStrategyCourse.init(self, task, job)
    self.combineUnloadStates = CpUtil.initStates(self.combineUnloadStates, AIDriveStrategyUnloadCombine.myCombineUnloadStates)
    self.trailerUnloadStates = CpUtil.initStates(self.trailerUnloadStates, AIDriveStrategyUnloadCombine.myTrailerUnloadStates)
    self.fieldUnloadStates = CpUtil.initStates(self.fieldUnloadStates, AIDriveStrategyUnloadCombine.myFieldUnloadStates)

    self.states = CpUtil.initStates(self.states, AIDriveStrategyUnloadCombine.myStates)
    --- Copies all references to the self.states table
    self.states = CpUtil.copyStates(self.states, self.combineUnloadStates)
    self.states = CpUtil.copyStates(self.states, self.trailerUnloadStates)
    self.states = CpUtil.copyStates(self.states, self.fieldUnloadStates)

    self.state = self.states.WAITING_FOR_FIELD_BOUNDARY_DETECTION
    self.debugChannel = CpDebug.DBG_UNLOAD_COMBINE
    ---@type ImplementController[]
    self.controllers = {}
    self.combineOffset = 0
    self.distanceToCombine = math.huge
    self.distanceToFront = 0
    self.combineToUnloadReversing = 0
    self.doNotSwerveForVehicle = CpTemporaryObject()
    self.justFinishedPathfindingForDistance = CpTemporaryObject()
    self.vehicleInFrontOfUS = CpTemporaryObject()
    self.vehicleRequestingBackUp = CpTemporaryObject()
    self.driveUnloadNowRequested = CpTemporaryObject(false)
    self.movingAwayDelay = CpTemporaryObject(false)
    self.checkForTrailerToUnloadTo = CpTemporaryObject(true)
    self.unloadTargetType = self.UNLOAD_TYPES.COMBINE
    self.useStreetUnload = false
    --- Register all active unloaders here to access them fast.
    AIDriveStrategyUnloadCombine.activeUnloaders[self] = self.vehicle
end

function AIDriveStrategyUnloadCombine:delete()
    if self.fieldUnloadPositionNode then
        CpUtil.destroyNode(self.fieldUnloadPositionNode)
        CpUtil.destroyNode(self.fieldUnloadTurnStartNode)
        CpUtil.destroyNode(self.fieldUnloadTurnEndNode)
    end
    if self.invertedStartPositionMarkerNode then
        CpUtil.destroyNode(self.invertedStartPositionMarkerNode)
    end

    self:releaseCombine()
    AIDriveStrategyUnloadCombine.activeUnloaders[self] = nil
    AIDriveStrategyCourse.delete(self)
end

------------------------------------------------------------------------------------------------------------------------
-- Start and initialization
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:startWithoutCourse()
    -- to always have a valid course (for the traffic conflict detector mainly)
    self.course = Course.createStraightForwardCourse(self.vehicle, 25)

    self:startCourse(self.course, 1)

    self:info('Starting combine unload')

    for _, implement in pairs(self.vehicle:getAttachedImplements()) do
        self:info(' - %s', CpUtil.getName(implement.object))
    end
end

function AIDriveStrategyUnloadCombine:getGeneratedCourse(jobParameters)
    return nil
end

function AIDriveStrategyUnloadCombine:setJobParameterValues(jobParameters)
    self.jobParameters = jobParameters
    if jobParameters.unloadWith:getValue() == CpCombineUnloaderJobParameters.UNLOAD_ON_FIELD then 
        local fieldUnloadPosition = jobParameters.fieldUnloadPosition
        if fieldUnloadPosition ~= nil and fieldUnloadPosition.x ~= nil and fieldUnloadPosition.z ~= nil and fieldUnloadPosition.angle ~= nil then
            --- Valid field unload position found and allowed.
            self.fieldUnloadPositionNode = CpUtil.createNode("Field unload position", fieldUnloadPosition.x, fieldUnloadPosition.z, fieldUnloadPosition.angle, nil)
            self.fieldUnloadTurnStartNode = CpUtil.createNode("Reverse field unload turn start position", fieldUnloadPosition.x, fieldUnloadPosition.z, fieldUnloadPosition.angle, nil)
            self.fieldUnloadTurnEndNode = CpUtil.createNode("Reverse field unload turn end position", fieldUnloadPosition.x, fieldUnloadPosition.z, fieldUnloadPosition.angle, nil)
            self.unloadTipSideID = jobParameters.unloadingTipSide:getValue()
        end
    elseif jobParameters.unloadWith:getValue() ~= CpCombineUnloaderJobParameters.DEACTIVATED then
        self.useStreetUnload = true
    end
    --- Setup the unload target mode.
    if jobParameters.unloadTarget:getValue() == CpCombineUnloaderJobParameters.UNLOAD_COMBINE then
        self.unloadTargetType = self.UNLOAD_TYPES.COMBINE
        self:debug("Unload target is a combine.")
    else
        self.unloadTargetType = self.UNLOAD_TYPES.SILO_LOADER
        self:debug("Unload target is a silo loader.")
    end

end

--- Gets the unload target drive strategy target.
function AIDriveStrategyUnloadCombine:getUnloadTargetType()
    return self.unloadTargetType
end

function AIDriveStrategyUnloadCombine:setAIVehicle(vehicle, jobParameters)
    AIDriveStrategyCourse.setAIVehicle(self, vehicle)
    self:setJobParameterValues(jobParameters)
    self.reverser = AIReverseDriver(self.vehicle, self.ppc)
    self.collisionAvoidanceController = CollisionAvoidanceController(self.vehicle, self)
    self.proximityController = ProximityController(self.vehicle, self:getProximitySensorWidth())
    self.proximityController:registerIsSlowdownEnabledCallback(self, AIDriveStrategyUnloadCombine.isProximitySpeedControlEnabled)
    self.proximityController:registerBlockingVehicleListener(self, AIDriveStrategyUnloadCombine.onBlockingVehicle)
    self.proximityController:registerIgnoreObjectCallback(self, AIDriveStrategyUnloadCombine.ignoreProximityObject)
    -- this is for following a chopper. The reason we are not using the proximityController's forward looking
    -- sensor is that it may be too high, and does not see the header of the chopper. Alternatively, we could
    -- lower the proximityController. Also, this is a little wider to catch the chopper during turns.
    self.followModeProximitySensor = WideForwardLookingProximitySensorPack(
            self.vehicle, Markers.getFrontMarkerNode(self.vehicle), 10, 0.5, self:getProximitySensorWidth(),
            { 20, 15, 8, 5, 0, -5, -8, -15, -20 })

    -- remove any course already loaded (for instance to not to interfere with the fieldworker proximity controller)
    vehicle:resetCpCourses()
    --- Target nodes for unloading into the trailer.
    self.trailerNodes = SelfUnloadHelper:getTrailersTargetNodes(vehicle)

end

function AIDriveStrategyUnloadCombine:initializeImplementControllers(vehicle)
    self.augerWagon, self.pipeController = self:addImplementController(vehicle, PipeController, Pipe, {}, nil)
    self:debug('Auger wagon found: %s', self.augerWagon ~= nil)
    self.trailer, self.trailerController = self:addImplementController(vehicle, TrailerController, Trailer, {}, nil)
    self:addImplementController(vehicle, MotorController, Motorized, {}, nil)
    self:addImplementController(vehicle, WearableController, Wearable, {}, nil)
    self:addImplementController(vehicle, CoverController, Cover, {}, nil)
    self:addImplementController(vehicle, FoldableController, Foldable, {})
end

function AIDriveStrategyUnloadCombine:isProximitySpeedControlEnabled()
    return not (self.state == self.states.UNLOADING_MOVING_COMBINE and self.combineToUnload:getCpDriveStrategy():hasAutoAimPipe())
end

function AIDriveStrategyUnloadCombine:ignoreProximityObject(object, vehicle, moveForwards, hitTerrain)
    return (self.state == self.states.UNLOADING_ON_THE_FIELD and hitTerrain) or
            -- these states handle the proximity by themselves
            (self.state == self.states.UNLOADING_MOVING_COMBINE and vehicle == self.combineToUnload) or
            (self.state == self.states.HANDLE_CHOPPER_HEADLAND_TURN and vehicle == self.combineToUnload)
end

function AIDriveStrategyUnloadCombine:checkCollisionWarning()
    if self.state.properties.collisionAvoidanceEnabled and
            self.collisionAvoidanceController:isCollisionWarningActive() then
        self:debugSparse('Collision warning, waiting...')
        self:setMaxSpeed(0)
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Main loop
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:getDriveData(dt, vX, vY, vZ)
    self:updateLowFrequencyImplementControllers()

    -- if applicable, calculate on which side of an auto aim pipe we should be driving, once every loop
    self:calculateAutoAimPipeOffsetX(self.combineToUnload)

    local moveForwards = not self.ppc:isReversing()
    local gx, gz

    ----------------------------------------------------------------
    if not moveForwards then
        local maxSpeed
        gx, gz, maxSpeed = self:getReverseDriveData()
        self:setMaxSpeed(maxSpeed)
    else
        gx, _, gz = self.ppc:getGoalPointPosition()
    end

    -- make sure if we have a combine we stay registered
    if self.combineToUnload and self.combineToUnload:getIsCpActive() then
        local strategy = self.combineToUnload:getCpDriveStrategy()
        if strategy then
            if strategy.registerUnloader then
                strategy:registerUnloader(self)
            else
                -- combine may have been stopped and restarted, so CP is active again but not yet the combine strategy,
                -- for instance it is now driving to work start, so it can't accept a registration
                self:debug('Lost my combine')
                self:startWaitingForSomethingToDo()
            end
        end
    end

    if self.combineToUnload == nil or not self.combineToUnload:getIsCpActive() then
        if CpUtil.isStateOneOf(self.state, self.combineUnloadStates) then

        end
    end

    if self:hasToWaitForAssignedCombine() then
        --- Safety check to make sure a combine is assigned, when needed.
        self:setMaxSpeed(0)
        self:debugSparse("Combine to unload lost during unload, waiting for something todo.")
        if self:isDriveUnloadNowRequested() then
            self:debug('Drive unload now requested')
            self:startUnloadingTrailers()
        end
    elseif self.state == self.states.WAITING_FOR_FIELD_BOUNDARY_DETECTION then
        self:setMaxSpeed(0)
        if self:waitForFieldBoundary() then
            self:debug('Have field boundary now, checking positions.')
            if self:isPositionOk() then
                self.state = self.states.INITIAL
            end
        end
    elseif self.state == self.states.INITIAL then
        if not self.startTimer then
            --- Only create one instance of the timer and wait until it finishes.
            self.startTimer = Timer.createOneshot(50, function()
                --- Pipe measurement seems to be buggy with a few over loaders, like bergman RRW 500,
                --- so a small delay of 50 ms is inserted here before unfolding starts.
                self.vehicle:raiseAIEvent("onAIFieldWorkerStart", "onAIImplementStart")
                self.state = self.states.IDLE
                self.startTimer = nil
            end)
        end
        self:setMaxSpeed(0)
    elseif self.state == self.states.IDLE then
        -- nothing to do right now, wait for one of the following:
        -- - combine calls
        -- - user sends us to unload the trailer
        -- - a trailer appears where we can unload our auger wagon if full
        self:setMaxSpeed(0)

        if self:isDriveUnloadNowRequested() then
            self:debug('Drive unload now requested')
            self:startUnloadingTrailers()
        elseif self.checkForTrailerToUnloadTo:get() and self:getAllTrailersFull(self.settings.fullThreshold:getValue()) then
            -- every now and then check if should attempt to unload our trailer/auger wagon
            self.checkForTrailerToUnloadTo:set(false, 10000)
            self:debug('Trailers over %d fill level', self.settings.fullThreshold:getValue())
            self:startUnloadingTrailers()
        end
    elseif self.state == self.states.WAITING_FOR_PATHFINDER then
        -- just wait for the pathfinder to finish
        self:setMaxSpeed(0)

    elseif self.state == self.states.DRIVING_TO_COMBINE then

        self:driveToCombine()

    elseif self.state == self.states.DRIVING_TO_MOVING_COMBINE then

        self:driveToMovingCombine()

    elseif self.state == self.states.UNLOADING_STOPPED_COMBINE then

        local x, z = self:unloadStoppedCombine()
        -- if driveBesideCombine() has a better goal point, use that, instead of the offset course
        if x ~= nil then
            gx, gz = x, z
        end

    elseif self.state == self.states.UNLOADING_MOVING_COMBINE then

        local x, z
        if self.combineToUnload:getCpDriveStrategy():hasAutoAimPipe() then
            x, z = self:unloadMovingChopper()
        else
            x, z = self:unloadMovingCombine(dt)
        end
        -- if driveBesideCombine()/followChopper() has a better goal point, use that, instead of the offset course
        if x ~= nil then
            gx, gz = x, z
        end

    elseif self.state == self.states.WAITING_FOR_MANEUVERING_COMBINE then

        self:waitForManeuveringCombine()

    elseif self.state == self.states.BACKING_UP_FOR_REVERSING_COMBINE then
        -- reversing combine asking us to move
        self:backUpForReversingCombine()

    elseif self.state == self.states.MOVING_AWAY_FROM_OTHER_VEHICLE then
        -- someone is blocking us or we are blocking someone
        self:moveAwayFromOtherVehicle()

    elseif self.state == self.states.MOVING_BACK_FOR_HEADLAND_TURN then
        self:makeRoomForCombineTurningOnHeadland()

    elseif self.state == self.states.MOVING_BACK_WITH_TRAILER_FULL then
        self:setMaxSpeed(self.settings.reverseSpeed:getValue())
        -- drive back to have some room for the pathfinder
        local _, dx, dz = self:getDistanceFromCombine(self.state.properties.vehicle)
        -- drive back more if we are close to the harvester
        if dz > ((math.abs(dx) < self.turningRadius) and 0 or -3) then
            self:startUnloadingTrailers()
        end

    elseif self.state == self.states.MOVING_BACK_BEFORE_PATHFINDING then
        self:setMaxSpeed(self.settings.reverseSpeed:getValue())
    elseif self.state == self.states.MOVING_BACK then

        self:setMaxSpeed(self.settings.reverseSpeed:getValue())
        if self.state.properties.holdCombine then
            self:debugSparse('Holding combine while backing up')
            self.combineToUnload:getCpDriveStrategy():hold(1000)
        end
        -- drive back until the combine is in front of us
        local _, _, dz = self:getDistanceFromCombine(self.state.properties.vehicle)
        if dz > 0 then
            self:debug('Stop backing up')
            self:startWaitingForSomethingToDo()
        end

    elseif self.state == self.states.DRIVING_TO_SELF_UNLOAD then
        self:driveToSelfUnload()
    elseif self.state == self.states.WAITING_FOR_AUGER_PIPE_TO_OPEN then
        self:waitForAugerPipeToOpen()
    elseif self.state == self.states.UNLOADING_AUGER_WAGON then
        moveForwards = self:unloadAugerWagon()
    elseif self.state == self.states.MOVING_TO_NEXT_FILL_NODE then
        moveForwards = self:moveToNextFillNode()
    elseif self.state == self.states.MOVING_AWAY_FROM_UNLOAD_TRAILER then
        self:moveAwayFromUnloadTrailer()
    elseif self.state == self.states.DRIVING_BACK_TO_START_POSITION_WHEN_FULL then
        self:setMaxSpeed(self:getFieldSpeed())
        ---------------------------------------------
        --- Unloading on the field
        ---------------------------------------------
    elseif self.state == self.states.DRIVE_TO_FIELD_UNLOAD_POSITION then
        self:setMaxSpeed(self:getFieldSpeed())
    elseif self.state == self.states.WAITING_UNTIL_FIELD_UNLOAD_IS_ALLOWED then
        self:waitingUntilFieldUnloadIsAllowed()
    elseif self.state == self.states.PREPARE_FOR_FIELD_UNLOAD then
        self:prepareForFieldUnload()
    elseif self.state == self.states.UNLOADING_ON_THE_FIELD then
        self:setMaxSpeed(self.settings.reverseSpeed:getValue())
    elseif self.state == self.states.DRIVE_TO_REVERSE_FIELD_UNLOAD_POSITION then
        self:setMaxSpeed(self:getFieldSpeed())
    elseif self.state == self.states.REVERSING_TO_THE_FIELD_UNLOAD_HEAP then
        self:driveToReverseFieldUnloadHeap()
    elseif self.state == self.states.HANDLE_CHOPPER_180_TURN then
        local x, z = self:handleChopper180Turn()
        if x ~= nil then
            gx, gz = x, z
        end
    elseif self.state == self.states.HANDLE_CHOPPER_HEADLAND_TURN then
        self:handleChopperHeadlandTurn()
    elseif self.state == self.states.FOLLOW_CHOPPER_THROUGH_TURN then
        self:followChopperThroughTurn()
    elseif self.state == self.states.DRIVE_TO_FIELD_UNLOAD_PARK_POSITION then
        self:setMaxSpeed(self:getFieldSpeed())
    end

    self:checkProximitySensors(moveForwards)

    self:checkCollisionWarning()
    return gx, gz, moveForwards, self.maxSpeed, 100
end

function AIDriveStrategyUnloadCombine:hasToWaitForAssignedCombine()
    if CpUtil.isStateOneOf(self.state, self.combineUnloadStates) then
        return self.combineToUnload == nil or not self.combineToUnload:getIsCpActive() or self.combineToUnload:getCpDriveStrategy() == nil
    end
    return false
end

---@param combine table
---@param combineDriver AIDriveStrategyCombineCourse
function AIDriveStrategyUnloadCombine:areThereAnyCombinesOrLoaderLeftoverOnTheField(combine, combineDriver)
    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if vehicle ~= combine and AIDriveStrategyCombineCourse.isActiveCpCombine(vehicle) then
            local x, _, z = getWorldTranslation(combine.rootNode)
            if self:isServingPosition(x, z, 10) then
                --- At least one more combine oder loader is working on this field.
                return true
            end
        end
    end
    return false
end

function AIDriveStrategyUnloadCombine:startWaitingForSomethingToDo()
    if self.state ~= self.states.IDLE then
        self:releaseCombine()
        self.course = Course.createStraightForwardCourse(self.vehicle, 25)
        self:setNewState(self.states.IDLE)
    end
end

---@return table|nil the best node (of all the fill nodes on all trailers) to use to unload a harvester
function AIDriveStrategyUnloadCombine:getBestTargetNode()
    local function isValidNode(targetNode)
        local fillType = self.combineToUnload:getCpDriveStrategy():getFillType()
        -- for some harvesters (DeWulf), fill type is unknown until they start working
        if fillType ~= FillType.UNKNOWN and not targetNode.trailer:getFillUnitAllowsFillType(targetNode.fillUnitIx, fillType) then
            self:debugSparse("Fill node %d of trailer %s doesn't accept fillType %s!",
                    targetNode.fillUnitIx, targetNode.trailer, g_fillTypeManager:getFillTypeNameByIndex(fillType))
            return false
        end
        if targetNode.trailer:getFillUnitFreeCapacity(targetNode.fillUnitIx) <= 0 then
            self:debugSparse("Fill node %d of trailer %s is completely filled!",
                    targetNode.fillUnitIx, targetNode.trailer)
            return false
        end
        return true
    end
    if not self.trailerNodes then
        self:debugSparse("Warning no valid trailer nodes found!")
        return
    end

    local bestTargetNode
    for _, targetNode in pairs(self.trailerNodes) do
        if isValidNode(targetNode) then
            bestTargetNode = targetNode
            break
        end
    end
    return bestTargetNode
end

---@return number|nil find the best target node and its distance from the pipe, > 0 when behind the pipe, < 0 when in
--- front of the pipe
function AIDriveStrategyUnloadCombine:getBestTargetNodeDistanceFromPipe()
    local bestTargetNode = self:getBestTargetNode()
    if bestTargetNode == nil then
        return
    end
    if CpUtil.isVehicleDebugActive(self.vehicle) and CpDebug:isChannelActive(self.debugChannel) then
        DebugUtil.drawDebugNode(bestTargetNode.node, 'target')
    end
    local _, offsetZ = self:getPipeOffset(self.combineToUnload)
    local _, _, dz = localToLocal(bestTargetNode.node, self.combineToUnload:getAIDirectionNode(), 0, 0, -offsetZ)
    return -dz
end

---@return number | nil, number | nil gx, gz world coordinates to steer to, instead of the PPC determined goal point (which is
--- calculated from the offset harvester course).
--- This goal point is calculated from the harvester's position. It is on a straight line parallel to the harvester,
--- under the pipe and look ahead distance ahead of the unloader
--- driveBesideCombine() creates this goal when approaching the harvester to align with the pipe better and faster than
--- just using the offset course waypoints.
function AIDriveStrategyUnloadCombine:driveBesideCombine()

    local dz = self:getBestTargetNodeDistanceFromPipe()
    if dz == nil then
        return
    end

    local strategy = self.combineToUnload:getCpDriveStrategy()
    -- use a factor to make sure we reach the pipe fast, but be more gentle while discharging
    local factor = strategy:isDischarging() and 0.75 or 2
    local combineSpeed = self.combineToUnload.lastSpeedReal * 3600
    local speed = combineSpeed + CpMathUtil.clamp(dz * factor, -10, 15)
    if dz > 0 and speed < 2 then
        -- Giants does not like speeds under 2, it just stops. So if we calculated a small speed
        -- like when the combine is stopped, but not there yet, make sure we set a speed which
        -- actually keeps the unloader moving, otherwise we will never get there.
        speed = 2
    end
    -- slow down while the pipe is unfolding to avoid crashing onto it
    if strategy:isPipeMoving() then
        speed = (math.min(speed, self.combineToUnload:getLastSpeed() + 2))
    end
    self:setMaxSpeed(math.max(0, speed))

    self:renderText(0, 0.02, "%s: driveBesideCombine: dz = %.1f, speed = %.1f, factor = %.1f",
            CpUtil.getName(self.vehicle), dz, speed, factor)

    local gx, gy, gz
    -- Calculate an artificial goal point relative to the harvester to align better when starting to unload
    if dz > 5 then
        _, _, dz = localToLocal(self.vehicle:getAIDirectionNode(), self:getPipeOffsetReferenceNode(), 0, 0, 0)
        gx, gy, gz = localToWorld(self:getPipeOffsetReferenceNode(),
        -- straight line parallel to the harvester, under the pipe, look ahead distance from the unloader
                self:getPipeOffset(self.combineToUnload), 0, dz + self.ppc:getLookaheadDistance())

        if CpUtil.isVehicleDebugActive(self.vehicle) and CpDebug:isChannelActive(self.debugChannel) then
            -- show the goal point
            DebugUtil.drawDebugGizmoAtWorldPos(gx, gy + 3, gz, 1, 0, 1, 0, 1, 0, "Unloader goal", false)
        end
    end
    return gx, gz
end

------------------------------------------------------------------------------------------------------------------------
-- Are we stuck?
-- For some reason, we are not moving but the chopper needs us
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:isInDeadlock()
    if self.combineToUnload then
        local combineStrategy = self.combineToUnload:getCpDriveStrategy()
        if self.inDeadlock == nil then
            self.inDeadlock = CpDelayedBoolean()
        end
        return self.inDeadlock:get(combineStrategy:isWaitingForUnload() and AIUtil.isStopped(self.vehicle), 10000)
    else
        return false
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Unload chopper (always moving)
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:unloadMovingChopper()

    -- recalculate offset, just in case
    self.combineOffset = self:getPipeOffset(self.combineToUnload)
    self.followCourse:setOffset(-self.combineOffset, 0)

    if self:changeToUnloadWhenTrailerFull() then
        return
    end

    if self:isInDeadlock() then
        self:debug('Deadlock situation detected while unloading moving chopper.')
        self:startMovingBackFromCombine(self.states.MOVING_BACK, self.combineToUnload)
        return
    end

    local combineStrategy = self.combineToUnload:getCpDriveStrategy()
    local gx, gz = self:followChopper()

    if combineStrategy:isTurning() and not combineStrategy:isFinishingRow() then
        self:startChopperTurn(combineStrategy)
    end
    return gx, gz
end

------------------------------------------------------------------------------------------------------------------------
-- Drive with the chopper, avoiding fruit and staying in the reach of the pipe.
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:followChopper()
    -- self.autoAimPipeOffsetX is set in getPipeOffset() to where we should be. If we are on the wrong side, we can't just
    -- move the goal point to the correct side, as we need to duck behind the chopper, that is, moving
    -- the goal point back first so the tractor gets behind the choppers back and then to the correct
    -- side, and then forward again.

    -- Normally, when driving beside the harvester, align the direction nodes
    local dx, _, dz = localToLocal(Markers.getFrontMarkerNode(self.vehicle), self.combineToUnload:getAIDirectionNode(), 0, 0, 0)
    -- use both proximity sensors front as they are at different heights, one may see the header, but not the
    -- choppers high back...
    local dFollowProxy = self.followModeProximitySensor:getClosestObjectDistanceAndRootVehicle()
    local dProxy = self.proximityController:checkBlockingVehicleFront()
    local speed
    -- adjust speed to the harvester's speed
    local sameDirection = CpMathUtil.isSameDirection(self.vehicle:getAIDirectionNode(), self.combineToUnload:getAIDirectionNode(), 45)
    if sameDirection then
        if math.abs(dx - self:getAutoAimPipeOffsetX()) > 1 then
            -- if the difference between the current and desired offset is big, slow down, our reference point is
            -- the back of the harvester
            dz = dz + self:getCombinesMeasuredBackDistance()
        end
        speed = self.combineToUnload.lastSpeedReal * 3600 + CpMathUtil.clamp(
                math.min(-dz, dFollowProxy - self.targetDistanceBehindChopper, dProxy - self.targetDistanceBehindChopper) * 2,
                -10, 15)
    else
        -- not aligned with the chopper, drive forward to get closer, regardless of dz
        speed = CpMathUtil.clamp(
                math.min(dFollowProxy - self.targetDistanceBehindChopper, dProxy - self.targetDistanceBehindChopper) * 2,
                0, self.settings.turnSpeed:getValue())
    end

    self:setMaxSpeed(speed)
    local _, _, dzGoal = localToLocal(self.vehicle:getAIDirectionNode(), self.combineToUnload:getAIDirectionNode(), 0, 0, 0)
    local gx, gy, gz = localToWorld(self.combineToUnload:getAIDirectionNode(),
    -- straight line parallel to the harvester, under the pipe, look ahead distance from the unloader
            self:getAutoAimPipeOffsetX(), 0, dzGoal + self.ppc:getLookaheadDistance())

    if CpUtil.isVehicleDebugActive(self.vehicle) and CpDebug:isChannelActive(self.debugChannel) then
        -- show the goal point
        DebugUtil.drawDebugGizmoAtWorldPos(gx, gy + 4, gz, 0, 0, 1, 0, 1, 0, "Virtual goal", false)
        self:renderDebugTableFromLists(
                { 'dz', 'dProxy', 'dFollowProxy', 'speed', 'autoAimOffsetX' },
                { dz, dProxy, dFollowProxy, speed, self:getAutoAimPipeOffsetX() }
        )
    end
    return gx, gz
end

------------------------------------------------------------------------------------------------------------------------
-- Chopper turns
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:startChopperTurn(combineStrategy)
    if combineStrategy:isTurningOnHeadland() then
        self:debug('Start chopper headland turn')
        self:startCourse(self.followCourse, combineStrategy:getTurnStartWpIx())
        self:setNewState(self.states.HANDLE_CHOPPER_HEADLAND_TURN)
    else
        self:debug('Start chopper 180 turn')
        self:setNewState(self.states.HANDLE_CHOPPER_180_TURN)
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Chopper turn 180
-- The default strategy here is to stop before reaching the end of the row and then wait for the combine
-- to finish the 180 turn. After it finished the turn, we drive forward a bit to make sure we are behind the
-- chopper and then continue on the chopper's fieldwork course with the appropriate offset without pathfinding.
--
-- If the combine says that it won't reverse during the turn (for example performs a wide turn because the
-- next row to work on is not adjacent the current row), we switch to 'follow chopper through the turn' mode
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:handleChopper180Turn()

    if self:changeToUnloadWhenTrailerFull() then
        return
    end

    if self.combineToUnload:getCpDriveStrategy():isTurningButNotEndingTurn() then
        if self.combineToUnload:getCpDriveStrategy():isTurnForwardOnly() then
            ---@type Course
            local turnCourse = self.combineToUnload:getCpDriveStrategy():getTurnCourse()
            if turnCourse then
                self:debug('Follow chopper through the turn')
                self:startCourse(turnCourse:copy(self.vehicle), 1)
                self:setNewState(self.states.FOLLOW_CHOPPER_THROUGH_TURN)
                return
            else
                self:debugSparse('Chopper said turn is forward only but has no turn course')
            end
        else
            self:debugSparse('Chopper said turn is not forward only, following without turn course')
            -- in a lands, or spiral pattern the row start may be very far from the row end, and we only have
            -- the normal course loaded, no field work course. So while following the chopper through the turn,
            -- we may get too far from the previous and next waypoints (row end/row start), triggering the
            -- off-track detection in PPC, which would stop the helper.
            -- To avoid this, we disable it temporarily
            self.ppc:disableStopWhenOffTrack(2000)
        end
    else
        local _, _, dz = self:getDistanceFromCombine()
        self:setMaxSpeed(self.settings.turnSpeed:getValue())
        -- start the chopper course (and thus, turning towards it) only after we are behind it
        if dz < -3 then
            self:debug('now behind chopper, continue following chopper')

            self:setNewState(self.states.UNLOADING_MOVING_COMBINE)
            return
        end
    end
    local speed, isReversing = self:handleChopperTurn(self.combineToUnload)

    self:setMaxSpeed(speed)

    if not isReversing then
        -- when driving forward, we still follow the virtual goal near the harvester (and not the course waypoints)
        return self:followChopper()
    end

end

------------------------------------------------------------------------------------------------------------------------
-- Chopper turn on headland
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:handleChopperHeadlandTurn()

    if self:changeToUnloadWhenTrailerFull() then
        return
    end

    local speed, _ = self:handleChopperTurn(self.combineToUnload)

    self:setMaxSpeed(speed)

    --when the turn is finished, return to follow chopper
    if not self:getCombineIsTurning() then
        self:debug('Combine stopped turning, resuming follow course')
        -- resume course beside combine
        -- skip over the turn start waypoint as it will throw the PPC off course
        self:startCourse(self.followCourse, self.combineCourse:skipOverTurnStart(self.combineCourse:getCurrentWaypointIx()))
        self:setNewState(self.states.UNLOADING_MOVING_COMBINE)
    end
end

--- Handle both 180 and headland turns. Monitor the harvester and if it changes to reverse, set up a straight
--- reverse course for the unloader to use when backing up. If it changes back to forward, set the unloader back on
--- the follow course.
--- Calculate a speed (for both forward and reverse) that makes sure the harvester does not crash into the unloader.
---@param harvester table
---@return number speed to set to stay away (but not too far) from the maneuvering harvester
---@return boolean if true, the harvester is reversing (and we are on a straight reverse course)
function AIDriveStrategyUnloadCombine:handleChopperTurn(harvester)

    -- since we are taking care of staying away, ask the chopper to ignore us
    harvester:getCpDriveStrategy():requestToIgnoreProximity(self.vehicle)

    local d, dx, dz = self:getDistanceFromCombine(harvester)
    local combineSpeed = harvester.lastSpeedReal * 3600
    local speed, dReference

    --if the chopper is reversing, drive backwards, otherwise forwards, always keeping the distance from the chopper
    if AIUtil.isReversing(harvester) then
        if not self.state.properties.reversing then
            self:debug('Harvester reversing')
            self.state.properties.reversing = true
            local reverseCourse = Course.createStraightReverseCourse(self.vehicle, 20)
            self:startCourse(reverseCourse, 1)
        end
        local sameDirection = CpMathUtil.isSameDirection(self.vehicle:getAIDirectionNode(), harvester:getAIDirectionNode(), 45)
        -- stay closer when still discharging
        if sameDirection then
            -- reverse speed is controlled around combine's speed
            dReference = harvester:getCpDriveStrategy():isDischarging() and dz or dz - 3
            speed = combineSpeed + CpMathUtil.clamp(self.targetDistanceBehindChopper - dReference, -combineSpeed,
                    self.settings.reverseSpeed:getValue() * 1.5)
        else
            -- reverse speed only depends on distance from the combine, stop when at working width
            speed = CpMathUtil.clamp(harvester:getCpDriveStrategy():getWorkWidth() - d, 0,
                    self.settings.reverseSpeed:getValue() * 1.5)
        end
    else
        if self.state.properties.reversing then
            self:debug('Harvester driving forward')
            self.state.properties.reversing = false
            self:startCourse(self.followCourse, self.combineCourse:getCurrentWaypointIx())
        end
        local turnSpeed = self.settings.turnSpeed:getValue()
        -- get closer to the chopper when beside it
        dReference = (math.abs(dx) > 3) and dz or d
        speed = combineSpeed +
                (CpMathUtil.clamp(dReference - self.targetDistanceBehindChopper, -turnSpeed, turnSpeed))
    end

    self:renderDebugTableFromLists(
            { 'reversing', 'd', 'dx', 'dz', 'speed' },
            { self.state.properties.reversing, d, dx, dz, speed }
    )

    return speed, self.state.properties.reversing
end

------------------------------------------------------------------------------------------------------------------------
-- Follow chopper through turn
-- here we drive the chopper's turn course carefully keeping our distance from the combine.
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:followChopperThroughTurn()

    if self:changeToUnloadWhenTrailerFull() then
        return
    end

    local d = self:getDistanceFromCombine()
    local turnCourse = self.combineToUnload:getCpDriveStrategy():getTurnCourse()
    if self.combineToUnload:getCpDriveStrategy():isTurning() and turnCourse ~= nil then
        -- making sure we are never ahead of the chopper on the course (we both drive the same course), this
        -- prevents the unloader cutting in front of the chopper when for example the unloader is on the
        -- right side of the chopper and the chopper reaches a right turn.
        if self.course:getCurrentWaypointIx() > turnCourse:getCurrentWaypointIx() then
            self:setMaxSpeed(0)
        end
        -- follow course, make sure we are keeping distance from the chopper
        local combineSpeed = (self.combineToUnload.lastSpeedReal * 3600)
        local speed = math.max(self.settings.turnSpeed:getValue(), combineSpeed)
        self:setMaxSpeed(speed)
        self:renderText(0, 0.7, 'd = %.1f, speed = %.1f', d, speed)
    else
        self:debug('chopper is ending/ended turn, return to follow mode')
        self:startCourse(self.followCourse, self.combineCourse:getCurrentWaypointIx())
        self:setNewState(self.states.UNLOADING_MOVING_COMBINE)
    end
end

------------------------------------------------------------------------------------------------------------------------
--- Calculate a virtual pipe offset for the unloader to drive beside the chopper based on which
--- side of the chopper is already harvested, or behind it if both sides have fruit.
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:calculateAutoAimPipeOffsetX(harvester)
    local strategy = harvester and harvester:getCpDriveStrategy()
    if strategy and strategy.hasAutoAimPipe and strategy:hasAutoAimPipe() then
        local fruitLeft, fruitRight = strategy:getFruitAtSides()
        local targetOffsetX, distanceBetweenVehicles = 0, (AIUtil.getWidth(harvester) + AIUtil.getWidth(self.vehicle)) / 2 + 1
        -- we use 20% of the average as a threshold for significant difference
        local fruitThreshold = 0.2 * 0.5 * (fruitLeft + fruitRight)
        if strategy:isOnHeadland(1) then
            -- on the first headland always drive behind the chopper
            targetOffsetX = 0
        elseif math.abs(fruitRight - fruitLeft) < fruitThreshold then
            -- about the same amount of fruit on both sides
            targetOffsetX = 0
        elseif fruitLeft > fruitRight then
            -- significantly more fruit on the left, drive to the right
            targetOffsetX = -distanceBetweenVehicles
        else
            -- significantly more fruit on the right, drive to the left
            targetOffsetX = distanceBetweenVehicles
        end
        if not self.autoAimPipeOffsetX then
            -- Side offset from a chopper. We don't want this to jump from one side to the other abruptly
            self.autoAimPipeOffsetX = CpSlowChangingObject(targetOffsetX, 0)
        else
            self.autoAimPipeOffsetX:confirm(targetOffsetX, 3000, 0.2)
        end
    end
    return self:getAutoAimPipeOffsetX()
end

function AIDriveStrategyUnloadCombine:onWaypointPassed(ix, course)
    if course:isLastWaypointIx(ix) then
        self:onLastWaypointPassed()
    end
end

------------------------------------------------------------------------------------------------------------------------
-- On last waypoint
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:onLastWaypointPassed()
    self:debug('Last waypoint passed')
    if self.state == self.states.DRIVING_TO_COMBINE then
        if self:isOkToStartUnloadingCombine() then
            -- Right behind the combine, aligned, go for the pipe
            self:startUnloadingCombine()
        else
            self:startWaitingForSomethingToDo()
        end
    elseif self.state == self.states.DRIVING_TO_MOVING_COMBINE then
        self:startCourseFollowingCombine()
    elseif self.state == self.states.BACKING_UP_FOR_REVERSING_COMBINE then
        self:setNewState(self.stateAfterMovedOutOfWay)
        self:startRememberedCourse()
    elseif self.state == self.states.MOVING_BACK_BEFORE_PATHFINDING then
        if self.state.properties.pathfinderController then
            self:debug('Retry last pathfinding after moved back a bit')
            self:setNewState(self.states.WAITING_FOR_PATHFINDER)
            self.lastState.properties.pathfinderController:retry(self.lastState.properties.pathfinderContext)
        else
            self:debug('No pathfinder controller after moving back')
            self:startWaitingForSomethingToDo()
        end
    elseif self.state == self.states.MOVING_AWAY_FROM_OTHER_VEHICLE then
        self:startWaitingForSomethingToDo()
    elseif self.state == self.states.MOVING_BACK_FOR_HEADLAND_TURN then
        self:startWaitingForSomethingToDo()
    elseif self.state == self.states.DRIVING_BACK_TO_START_POSITION_WHEN_FULL then
        self:debug('Inverted goal position reached, so give control back to the job.')
        self:onTrailerFull()
        ---------------------------------------------
        --- Self unload
        ---------------------------------------------
    elseif self.state == self.states.DRIVING_TO_SELF_UNLOAD then
        self:onLastWaypointPassedWhenDrivingToSelfUnload()
    elseif self.state == self.states.MOVING_TO_NEXT_FILL_NODE then
        -- should just for safety
        self:startMovingAwayFromUnloadTrailer()
    elseif self.state == self.states.MOVING_AWAY_FROM_UNLOAD_TRAILER then
        self:onMovedAwayFromUnloadTrailer()
        ---------------------------------------------
        --- Unloading on the field
        ---------------------------------------------
    elseif self.state == self.states.DRIVE_TO_FIELD_UNLOAD_POSITION then
        self:setNewState(self.states.WAITING_UNTIL_FIELD_UNLOAD_IS_ALLOWED)
    elseif self.state == self.states.UNLOADING_ON_THE_FIELD then
        self:onFieldUnloadingFinished()
    elseif self.state == self.states.DRIVE_TO_REVERSE_FIELD_UNLOAD_POSITION then
        self:onReverseFieldUnloadPositionReached()
    elseif self.state == self.states.REVERSING_TO_THE_FIELD_UNLOAD_HEAP then
        self:onReverseFieldUnloadHeapReached()
    elseif self.state == self.states.DRIVE_TO_FIELD_UNLOAD_PARK_POSITION then
        self:onFieldUnloadParkPositionReached()
    end
end

function AIDriveStrategyUnloadCombine:setFieldSpeed()
    if self.course then
        self:setMaxSpeed(self.settings.fieldSpeed:getValue())
    end
end

function AIDriveStrategyUnloadCombine:getFieldSpeed()
    return self.settings.fieldSpeed:getValue()
end

function AIDriveStrategyUnloadCombine:setNewState(newState)
    self.lastState = self.state
    self.state = newState
    self:debug('setNewState: %s', self.state.name)
end

function AIDriveStrategyUnloadCombine:getCourseToAlignTo(vehicle, offset)
    local waypoints = {}
    for i = -20, 20, 5 do
        local x, y, z = localToWorld(vehicle.rootNode, offset, 0, i)
        local point = { cx = x;
                        cy = y;
                        cz = z;
        }
        table.insert(waypoints, point)
    end
    local tempCourse = Course(self.vehicle, waypoints)
    return tempCourse
end

function AIDriveStrategyUnloadCombine:getPipesBaseNode(combine)
    return g_combineUnloadManager:getPipesBaseNode(combine)
end

function AIDriveStrategyUnloadCombine:getCombineIsTurning()
    return self.combineToUnload:getCpDriveStrategy() and self.combineToUnload:getCpDriveStrategy():isTurning()
end

---@return number, number x and z offset of the pipe's end from the combine's root node in the Giants coordinate system
---(x > 0 left, z > 0 forward) corrected with the manual offset settings
function AIDriveStrategyUnloadCombine:getPipeOffset(combine)
    local offsetX, offsetZ = combine:getCpDriveStrategy():getPipeOffset(-self.settings.combineOffsetX:getValue(), self.settings.combineOffsetZ:getValue())
    if combine:getCpDriveStrategy():hasAutoAimPipe() then
        return self:getAutoAimPipeOffsetX(), offsetZ
    else
        return offsetX, offsetZ
    end
end

function AIDriveStrategyUnloadCombine:getAutoAimPipeOffsetX()
    return self.autoAimPipeOffsetX and self.autoAimPipeOffsetX:get() or 0
end

function AIDriveStrategyUnloadCombine:getCombinesMeasuredBackDistance()
    return self.combineToUnload:getCpDriveStrategy():getMeasuredBackDistance()
end

function AIDriveStrategyUnloadCombine:getAllTrailersFull(fullThresholdPercentage)
    return FillLevelUtil.areAllTrailersFull(self.vehicle, fullThresholdPercentage)
end

--- Fill level in %.
function AIDriveStrategyUnloadCombine:getFillLevelPercentage()
    return FillLevelUtil.getTotalTrailerFillLevelPercentage(self.vehicle)
end

function AIDriveStrategyUnloadCombine:isDriveUnloadNowRequested()
    if self.driveUnloadNowRequested:get() then
        self.driveUnloadNowRequested:reset()
        self:debug('User requested drive unload now')
        return true
    end
    return false
end

--- Request to start unloading the trailer at our earliest convenience. We won't directly start it from
--- here, just set this flag, as we may be in the middle of something, or may want to back up before
--- starting on the (self)unload course.
function AIDriveStrategyUnloadCombine:requestDriveUnloadNow()
    -- will reset automatically after a second so we don't have to worry about it getting stuck :)
    self.driveUnloadNowRequested:set(true, 1000)
end

function AIDriveStrategyUnloadCombine:releaseCombine()
    self.combineJustUnloaded = nil
    if self.combineToUnload and self.combineToUnload:getIsCpActive() then
        local strategy = self.combineToUnload:getCpDriveStrategy()
        if strategy and strategy.deregisterUnloader then
            strategy:deregisterUnloader(self)
        end
        self.combineJustUnloaded = self.combineToUnload
    end
    self.combineToUnload = nil
end

------------------------------------------------------------------------------------------------------------------------
-- Implement controller handling.
------------------------------------------------------------------------------------------------------------------------

function AIDriveStrategyUnloadCombine:isFuelSaveAllowed()
    return self.state.properties.fuelSaveAllowed or AIDriveStrategyCourse.isFuelSaveAllowed(self)
end

function AIDriveStrategyUnloadCombine:isCoverOpeningAllowed()
    return self.state.properties.openCoverAllowed
end

function AIDriveStrategyUnloadCombine:isMoveablePipeDisabled()
    return self.state.properties.moveablePipeDisabled
end

------------------------------------------------------------------------------------------------------------------------
-- Who I am?
------------------------------------------------------------------------------------------------------------------------
---@param vehicle table
---@return boolean true if vehicle is an active Courseplay controlled unloader, in combine unload mode
function AIDriveStrategyUnloadCombine.isActiveCpCombineUnloader(vehicle)
    if vehicle.getIsCpCombineUnloaderActive and vehicle:getIsCpCombineUnloaderActive() then
        local strategy = vehicle:getCpDriveStrategy()
        if strategy then
            local unloadTargetType = strategy:getUnloadTargetType()
            if unloadTargetType ~= nil then
                return unloadTargetType == AIDriveStrategyUnloadCombine.UNLOAD_TYPES.COMBINE
            end
        end
    end
    return false
end

---@param vehicle table
---@return boolean true if vehicle is an active Courseplay controlled unloader, in silo loader mode
function AIDriveStrategyUnloadCombine.isActiveCpSiloLoader(vehicle)
    if vehicle.getIsCpCombineUnloaderActive and vehicle:getIsCpCombineUnloaderActive() then
        local strategy = vehicle:getCpDriveStrategy()
        if strategy then
            local unloadTargetType = strategy:getUnloadTargetType()
            if unloadTargetType ~= nil then
                return unloadTargetType == AIDriveStrategyUnloadCombine.UNLOAD_TYPES.SILO_LOADER
            end
        end
    end
    return false
end


------------------------------------------------------------------------------------------------------------------------
-- Where I am?
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:isWithinSafeManeuveringDistance(vehicle)
    local d = calcDistanceFrom(self.vehicle.rootNode, vehicle:getAIDirectionNode())
    return d < self.safeManeuveringDistance
end

function AIDriveStrategyUnloadCombine:debugIf(enabled, ...)
    if enabled then
        self:debug(...)
    end
end

--- Is the vehicle lined up with the pipe, based on the two offset values and a tolerance
---@param dx number side offset of the vehicle from the combine's centerline, left > 0 > right
---@param dz number front/back (+/-) offset of the vehicle from the combine's root node
---@param pipeOffset number side offset of the pipe from the combine's centerline
---@param debugEnabled boolean
function AIDriveStrategyUnloadCombine:isLinedUpWithPipe(dx, dz, pipeOffset, debugEnabled)
    -- allow more offset when further away from the pipe, this is +- 50 cm at the pipe and grows
    -- 25 cm with every meter, which is about 30 degrees (15 left and 15 right)
    local tolerance = 0.25 + 0.5 * math.abs(dz)
    self:debugIf(debugEnabled, 'isLinedUpWithPipe: dx > pipe offset +- tolerance (%.1f > %.1f +- %.1f) at dz: %.1f',
            dx, pipeOffset, tolerance, dz)
    return dx > pipeOffset - tolerance and dx < pipeOffset + tolerance
end

function AIDriveStrategyUnloadCombine:isBehindAndAlignedToCombine(debugEnabled)
    -- if the harvester has an auto aim pipe, like a chopper we can relax our conditions
    local hasAutoAimPipe = self.combineToUnload:getCpDriveStrategy():hasAutoAimPipe()
    local dx, _, dz = localToLocal(self.vehicle.rootNode, self:getPipeOffsetReferenceNode(), 0, 0, 0)
    local pipeOffset = self:getPipeOffset(self.combineToUnload)
    if dz > (hasAutoAimPipe and -5 or 0) then
        self:debugIf(debugEnabled, 'isBehindAndAlignedToCombine: dz > 0')
        return false
    end
    if not hasAutoAimPipe and not self:isLinedUpWithPipe(dx, dz, pipeOffset, debugEnabled) then
        return false
    end
    local d = MathUtil.vector2Length(dx, dz)
    local dLimit = (hasAutoAimPipe and 50 or 30)
    if d > dLimit then
        self:debugIf(debugEnabled, 'isBehindAndAlignedToCombine: too far from combine (%.1f > %.1f)', d, dLimit)
        return false
    end
    local dirLimit = (hasAutoAimPipe and 2 * AIDriveStrategyUnloadCombine.maxDirectionDifferenceDeg
            or AIDriveStrategyUnloadCombine.maxDirectionDifferenceDeg)
    if not CpMathUtil.isSameDirection(self.vehicle:getAIDirectionNode(), self.combineToUnload:getAIDirectionNode(), dirLimit) then
        self:debugIf(debugEnabled, 'isBehindAndAlignedToCombine: direction difference is > %d)', dirLimit)
        return false
    end
    -- close enough and approximately same direction and behind and not too far to the left or right, about the same
    -- direction
    return true
end

--- In front of the combine, right distance from pipe to start unloading and the combine is moving
function AIDriveStrategyUnloadCombine:isInFrontAndAlignedToMovingCombine(debugEnabled)
    local dx, _, dz = localToLocal(self.vehicle.rootNode, self:getPipeOffsetReferenceNode(), 0, 0, 0)
    local pipeOffset = self:getPipeOffset(self.combineToUnload)
    if dz < 0 then
        self:debugIf(debugEnabled, 'isInFrontAndAlignedToMovingCombine: dz < 0')
        return false
    end
    if MathUtil.vector2Length(dx, dz) > 30 then
        self:debugIf(debugEnabled, 'isInFrontAndAlignedToMovingCombine: more than 30 m from combine')
        return false
    end
    if not self:isLinedUpWithPipe(dx, dz, pipeOffset, debugEnabled) then
        return false
    end
    if not CpMathUtil.isSameDirection(self.vehicle:getAIDirectionNode(), self.combineToUnload:getAIDirectionNode(),
            AIDriveStrategyUnloadCombine.maxDirectionDifferenceDeg) then
        self:debugIf(debugEnabled, 'isInFrontAndAlignedToMovingCombine: direction difference is > %d)',
                AIDriveStrategyUnloadCombine.maxDirectionDifferenceDeg)
        return false
    end
    if self.combineToUnload:getCpDriveStrategy():willWaitForUnloadToFinish() then
        self:debugIf(debugEnabled, 'isInFrontAndAlignedToMovingCombine: combine is not moving')
        return false
    end
    if self.combineToUnload:getCpDriveStrategy():alwaysNeedsUnloader() then
        -- this harvester won't move without an unloader under the pipe, so if our fill node is in front of the
        -- trailer, there is no point waiting for it
        dz = self:getBestTargetNodeDistanceFromPipe()
        if dz == nil or dz < -0.5 then
            self:debugIf(debugEnabled, 'isInFrontAndAlignedToMovingCombine: harvester always needs unloader but fill node is in front of the pipe (%s)', tostring(dz))
            return false
        end
    end
    -- in front of the combine, close enough and approximately same direction, about pipe offset side distance
    -- and is not waiting (stopped) for the unloader
    return true
end

function AIDriveStrategyUnloadCombine:isOkToStartUnloadingCombine()
    if self.combineToUnload:getCpDriveStrategy():isReadyToUnload(true) then
        -- if it always needs an unloader, it won't move without it, so can't start unloading when in front of the combine
        return self:isBehindAndAlignedToCombine() or self:isInFrontAndAlignedToMovingCombine()
    else
        self:debugSparse('combine not ready to unload, waiting')
        return false
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Start the course to unload the trailers
---@param waitForCombineIfNotFull boolean when not full, and no trailer found, start waiting for the combine
--- instead of just stopping
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:startUnloadingTrailers()
    self:setMaxSpeed(0)
    self:releaseCombine()

    if self.fieldUnloadPositionNode then
        if self.augerWagon then
            self:debug('Starting unloading on the field with an auger wagon.')
            self:startUnloadingOnField(self.pipeController, false)
        else
            self:debug('Starting unloading on the field with a trailer.')
            self:startUnloadingOnField(self.trailerController, true)
        end
        return
    end

    if self.augerWagon then
        self:debug('Have auger wagon, looking for a trailer.')
        if self:startSelfUnload() then
            self:debug('Trailer to unload to found, attempting self unload now')
        else
            self:debug('No trailer for self unload found, keep waiting')
            self:startWaitingForSomethingToDo()
        end
    else
        --- Trailer attached
        if self.invertedStartPositionMarkerNode then
            --- The start position is valid, so drive in there before releasing and giving control to giants or AD.
            self:debug('Trailer is full and a valid start position is set, so drive there before AD or giants can take over.')
            self:startPathfindingToInvertedGoalPositionMarker()
        else
            --- No valid start position was set, so release the driver and give control to giants or AD.
            self:debug('Full and have no auger wagon, stop, so eventually AD can take over.')
            self:onTrailerFull()
        end
    end
end

function AIDriveStrategyUnloadCombine:onTrailerFull()
    if self.useStreetUnload then
        self:setCurrentTaskFinished()
    else
        self.vehicle:stopCurrentAIJob(AIMessageErrorIsFull.new())
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Start to unload the combine (driving to the pipe/closer to combine)
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:startUnloadingCombine()
    if self.combineToUnload:getCpDriveStrategy():willWaitForUnloadToFinish() then
        self:debug('Close enough to a stopped combine, drive to pipe')
        self:startUnloadingStoppedCombine()
    else
        self:debug('Close enough to moving combine, copy combine course and follow')
        self:startCourseFollowingCombine()
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Start to unload a stopped combine
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:startUnloadingStoppedCombine()
    -- get a path to the pipe, make the pipe 0.5 m longer so the path will be 0.5 more to the outside to make
    -- sure we don't bump into the pipe
    local offsetX, offsetZ = self:getPipeOffset(self.combineToUnload)
    local unloadCourse = Course.createFromNode(self.vehicle, self:getPipeOffsetReferenceNode(), offsetX, offsetZ - 5, 30, 2, false)
    self:startCourse(unloadCourse, 1)
    -- make sure to get to the course as soon as possible
    self.ppc:setShortLookaheadDistance()
    self:setNewState(self.states.UNLOADING_STOPPED_COMBINE)
end

---@return Course fieldwork course of the combine
---@return number approximate waypoint index of the combine's current position
function AIDriveStrategyUnloadCombine:setupFollowCourse()
    ---@type Course
    self.combineCourse = self.combineToUnload:getCpDriveStrategy():getFieldworkCourse()
    if not self.combineCourse then
        -- TODO: handle this more gracefully, or even better, don't even allow selecting combines with no course
        self:debugSparse('Waiting for combine to set up a course, can\'t follow')
        return
    end
    local followCourse = self.combineCourse:copy(self.vehicle)
    -- relevant waypoint is the closest to the combine, prefer that so our PPC will get us on course with the proper offset faster
    local followCourseIx = self.combineToUnload:getCpDriveStrategy():getClosestFieldworkWaypointIx() or self.combineCourse:getCurrentWaypointIx()
    return followCourse, followCourseIx
end

------------------------------------------------------------------------------------------------------------------------
-- Start following a combine a course
-- This assumes we are in a good position to do that and can start on the course without pathfinding
-- or alignment, that is, we only call this when isOkToStartUnloadingCombine() says it is ok
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:startCourseFollowingCombine()
    local startIx
    self.followCourse, startIx = self:setupFollowCourse()
    self.combineOffset = self:getPipeOffset(self.combineToUnload)
    self.followCourse:setOffset(-self.combineOffset, 0)
    self.reverseForTurnCourse = nil
    self:debug('Will follow combine\'s course at waypoint %d, side offset %.1f', startIx, self.followCourse.offsetX)
    self:startCourse(self.followCourse, startIx)
    self:setNewState(self.states.UNLOADING_MOVING_COMBINE)
end

function AIDriveStrategyUnloadCombine:getCombineToUnload()
    return self.combineToUnload
end

function AIDriveStrategyUnloadCombine:getPipeOffsetReferenceNode()
    return self.combineToUnload:getCpDriveStrategy():getPipeOffsetReferenceNode()
end

------------------------------------------------------------------------------------------------------------------------
-- Pathfinding to moving combine (to a rendezvous waypoint)
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:startPathfindingToMovingCombine(waypoint, xOffset, zOffset)
    local context = PathfinderContext(self.vehicle)
    context:maxFruitPercent(self:getMaxFruitPercent())
    context:offFieldPenalty(self:getOffFieldPenalty(self.combineToUnload))
    context:useFieldNum(CpFieldUtil.getFieldNumUnderVehicle(self.combineToUnload))
    context:areaToAvoid(nil):vehiclesToIgnore({ self.combineToUnload })
    context:maxIterations(PathfinderUtil.getMaxIterationsForFieldPolygon(self.vehicle:cpGetFieldPolygon()))
    self.pathfinderController:registerListeners(self, self.onPathfindingDoneToMovingCombine,
            self.onPathfindingFailedToMovingTarget, self.onPathfindingObstacleAtStart)
    -- TODO: consider creating a variation of findPathToWaypoint() which accepts a Waypoint instead of Course/ix
    self.pathfinderController:findPathToGoal(
            context,
    -- getWaypointAsState3D expects the offset in waypoint coordinate system
            PathfinderUtil.getWaypointAsState3D(waypoint, -xOffset, zOffset))
end

function AIDriveStrategyUnloadCombine:onPathfindingDoneToMovingCombine(controller, success, course, goalNodeInvalid)
    if success and self.state == self.states.WAITING_FOR_PATHFINDER then
        self:debug('Pathfinding to moving combine successful.')
        -- add a short straight section to align in case we get there before the combine
        -- pathfinding does not guarantee the last section points into the target direction so we may
        -- end up not parallel to the combine's course when we extend the pathfinder course in the direction of the
        -- last waypoint. Therefore, use the rendezvousWaypoint's direction instead
        local dx = self.rendezvousWaypoint and self.rendezvousWaypoint.dx
        local dz = self.rendezvousWaypoint and self.rendezvousWaypoint.dz
        course:extend(AIDriveStrategyUnloadCombine.driveToCombineCourseExtensionLength, dx, dz)
        self:startCourse(course, 1)
        self:setNewState(self.states.DRIVING_TO_MOVING_COMBINE)
        return true
    else
        self:debug('Pathfinding to moving combine failed.')
        self:startWaitingForSomethingToDo()
        return false
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Pathfinding to waiting (not moving) combine
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:startPathfindingToWaitingCombine(xOffset, zOffset)
    local context = PathfinderContext(self.vehicle)
    local maxFruitPercent = self:getMaxFruitPercent(self:getPipeOffsetReferenceNode(), xOffset, zOffset)
    context:maxFruitPercent(maxFruitPercent)
    context:offFieldPenalty(self:getOffFieldPenalty(self.combineToUnload))
    context:useFieldNum(CpFieldUtil.getFieldNumUnderVehicle(self.combineToUnload))
    context:areaToAvoid(self.combineToUnload:getCpDriveStrategy():getAreaToAvoid())
    context:vehiclesToIgnore({}):maxIterations(PathfinderUtil.getMaxIterationsForFieldPolygon(self.vehicle:cpGetFieldPolygon()))
    self.pathfinderController:registerListeners(self, self.onPathfindingDoneToWaitingCombine,
            self.onPathfindingFailedToStationaryTarget, self.onPathfindingObstacleAtStart)
    self.pathfinderController:findPathToNode(context, self:getPipeOffsetReferenceNode(), xOffset or 0, zOffset or 0, 3)
end

function AIDriveStrategyUnloadCombine:onPathfindingDoneToWaitingCombine(controller, success, course, goalNodeInvalid)
    if success and self.state == self.states.WAITING_FOR_PATHFINDER then
        self:debug('Pathfinding to waiting combine successful')
        course:adjustForReversing(math.max(1, -AIUtil.getDirectionNodeToReverserNodeOffset(self.vehicle)))
        self:startCourse(course, 1)
        self:setNewState(self.states.DRIVING_TO_COMBINE)
        return true
    else
        self:debug('Pathfinding to waiting combine failed')
        self.vehicle:stopCurrentAIJob(AIMessageCpErrorNoPathFound.new())
        return false
    end
end

-- Use as a default pathfinder controller failure callback for stationary targets, where retrying later with the
-- same constraints won't help.
-- If the pathfinding fails due to a obstacle in front
-- of the vehicle, this will start the vehicle moving back on a temporary course. When the end of that course
-- reached, the pathfinding is retried with the same context (and with the same 'done' callback, to continue
-- where we left off)
-- If this was the last try, give up.
-- Otherwise, relax pathfinding constraints if we have retries left
function AIDriveStrategyUnloadCombine:onPathfindingFailedToStationaryTarget(...)
    self:debug('Pathfinding to stationary target failed.')
    self:onPathfindingFailed(
            function()
                self.vehicle:stopCurrentAIJob(AIMessageCpErrorNoPathFound.new())
            end, ...)
end

-- Same as above, but don't stop the job, as the target is moving, the situation may change by the time the
-- harvester next calls.
function AIDriveStrategyUnloadCombine:onPathfindingFailedToMovingTarget(...)
    self:debug('Pathfinding to moving target failed.')
    self:onPathfindingFailed(
            function()
                self:startWaitingForSomethingToDo()
            end, ...)
end

function AIDriveStrategyUnloadCombine:onPathfindingObstacleAtStart(controller, lastContext, maxDistance,
                                                                   trailerCollisionsOnly, fruitPenaltyNodePercent,
                                                                   offFieldPenaltyNodePercent)
    if trailerCollisionsOnly then
        self:debug('Pathfinding detected obstacle at start, trailer collisions only, retry with ignoring the trailer')
        lastContext:ignoreTrailerAtStartRange(1.5 * self.turningRadius)
        controller:retry(lastContext)
    else
        self:debug('Pathfinding detected obstacle at start, back up and retry')
        self:startMovingBackBeforePathfinding(controller, lastContext)
    end
end

function AIDriveStrategyUnloadCombine:onPathfindingFailed(giveUpFunc, controller, lastContext, wasLastRetry,
                                                          currentRetryAttempt, trailerCollisionsOnly,
                                                          fruitPenaltyNodePercent, offFieldPenaltyNodePercent)
    -- first, apply 70% of the original penalty, second retry: 40% and last one: 10%
    local offFieldPenaltyRelaxingSteps = { 0.7, 0.4, 0.1}
    local fruitPenaltyRelaxingSteps = { 2, 4, 8 }
    if wasLastRetry then
        giveUpFunc()
    elseif currentRetryAttempt < 3 then
        if fruitPenaltyNodePercent > offFieldPenaltyNodePercent then
            self:debug('%d. attempt to find path failed, trying with reduced fruit penalty', currentRetryAttempt)
            lastContext:maxFruitPercent(fruitPenaltyRelaxingSteps[currentRetryAttempt] * self:getMaxFruitPercent())
        else
            self:debug('%d. attempt to find path failed, trying with reduced off-field penalty', currentRetryAttempt)
            lastContext:offFieldPenalty(offFieldPenaltyRelaxingSteps[currentRetryAttempt] * PathfinderContext.defaultOffFieldPenalty)
        end
        controller:retry(lastContext)
    elseif currentRetryAttempt == 3 then
        self:debug('Last attempt to find path failed, trying off-field penalty and fruit avoidance disabled')
        -- On the last try, only disable off-field penalty and keep a bit fruit penalty
        lastContext:maxFruitPercent(fruitPenaltyRelaxingSteps[currentRetryAttempt] * self:getMaxFruitPercent()):offFieldPenalty(0)
        controller:retry(lastContext)
    else
        giveUpFunc()
    end
end

function AIDriveStrategyUnloadCombine:startMovingBackBeforePathfinding(pathfinderController, pathfinderContext)
    self:debug('There is an obstacle ahead, moving back before starting the pathfinding')
    self:setNewState(self.states.MOVING_BACK_BEFORE_PATHFINDING)
    self.state.properties.pathfinderContext = pathfinderContext
    self.state.properties.pathfinderController = pathfinderController
    local reverseCourse = Course.createStraightReverseCourse(self.vehicle, 1.5 * self.turningRadius)
    self:startCourse(reverseCourse, 1)
end

--- Is this position in the area I'm assigned to work?
---@param x number
---@param z number
---@param outwardsOffset number
---@return boolean
function AIDriveStrategyUnloadCombine:isServingPosition(x, z, outwardsOffset)
    if self.vehicle:cpGetFieldPolygon() then
        local closeEnough = CpMathUtil.isWithinDistanceToPolygon(self.vehicle:cpGetFieldPolygon(), x, z, outwardsOffset)
        return closeEnough or CpMathUtil.isPointInPolygon(self.vehicle:cpGetFieldPolygon(), x, z)
    else
        -- no field polygon yet. This may be called by the combine who has no idea where are we in the field boundary
        -- detection process.
        return false
    end
end

--- Am I ready to be assigned to a combine in need?
function AIDriveStrategyUnloadCombine:isIdle()
    return self.state == self.states.IDLE
end

function AIDriveStrategyUnloadCombine:isAllowedToBeCalled()
    return self:isIdle() or self:hasToWaitForAssignedCombine()
end

--- Get the Dubins path length and the estimated seconds en-route to gaol
---@param goal State3D
function AIDriveStrategyUnloadCombine:getDistanceAndEte(goal)
    local start = PathfinderUtil.getVehiclePositionAsState3D(self.vehicle)
    local solution = PathfinderUtil.dubinsSolver:solve(start, goal, self.turningRadius)
    local dubinsPathLength = solution:getLength(self.turningRadius)
    local estimatedSecondsEnroute = dubinsPathLength / (self.settings.fieldSpeed:getValue() / 3.6) + 3 -- add a few seconds to allow for starting the engine/accelerating
    return dubinsPathLength, estimatedSecondsEnroute
end

--- Get the Dubins path length and the estimated seconds en-route to vehicle
---@param vehicle table the other vehicle
function AIDriveStrategyUnloadCombine:getDistanceAndEteToVehicle(vehicle)
    local goal = PathfinderUtil.getVehiclePositionAsState3D(vehicle)
    return self:getDistanceAndEte(goal)
end

--- Get the Dubins path length and the estimated seconds en-route to a waypoint
---@param waypoint Waypoint
function AIDriveStrategyUnloadCombine:getDistanceAndEteToWaypoint(waypoint)
    local goal = PathfinderUtil.getWaypointAsState3D(waypoint, 0, 0)
    return self:getDistanceAndEte(goal)
end

--- Interface function for a combine to call the unloader.
---@param combine table the combine vehicle calling
---@param waypoint Waypoint if given, the combine wants to meet the unloader at this waypoint, otherwise wants the
--- unloader to come to the combine.
---@return boolean true if the unloader has accepted the request
function AIDriveStrategyUnloadCombine:call(combine, waypoint)
    local xOffset, zOffset = self:getPipeOffset(combine)
    if waypoint then
        -- combine set up a rendezvous waypoint for us, go there
        if self:isPathfindingNeeded(self.vehicle, waypoint, xOffset, zOffset, 25) then
            self.rendezvousWaypoint = waypoint
            self.combineToUnload = combine
            -- just in case, as the combine may give us a rendezvous waypoint
            -- where it is full, make sure we are behind the combine
            zOffset = -self:getCombinesMeasuredBackDistance() - 5
            self:debug('call: Start pathfinding to rendezvous waypoint, xOffset = %.1f, zOffset = %.1f', xOffset, zOffset)
            self:setNewState(self.states.WAITING_FOR_PATHFINDER)
            self:startPathfindingToMovingCombine(self.rendezvousWaypoint, xOffset, zOffset)
            return true
        else
            self:debug('call: Rendezvous waypoint to moving combine too close, wait a bit')
            self:startWaitingForSomethingToDo()
            return false
        end
    else
        -- combine wants us to drive directly to it
        self:debug('call: Combine is waiting for unload, start finding path to combine')
        self.combineToUnload = combine
        if self.combineToUnload:getCpDriveStrategy():isWaitingForUnloadAfterPulledBack() then
            -- combine pulled back so it's pipe is now out of the fruit. In this case, if the unloader is in front
            -- of the combine, it sometimes finds a path between the combine and the fruit to the pipe, we are trying to
            -- fix it here: the target is behind the combine, not under the pipe. When we get there, we may need another
            -- (short) pathfinding to get under the pipe.
            zOffset = -self:getCombinesMeasuredBackDistance() - 10
        elseif self.combineToUnload:getCpDriveStrategy():hasAutoAimPipe() then
            if math.abs(self:getAutoAimPipeOffsetX()) < 3 then
                -- will drive behind the harvester, so target must be further back, making sure there's a few meters
                -- between the harvester's back and the tractor's front
                local _, frontMarkerDistance = Markers.getFrontMarkerNode(self.vehicle)
                zOffset = -self:getCombinesMeasuredBackDistance() - frontMarkerDistance - 2
            else
                zOffset = -self:getCombinesMeasuredBackDistance()
            end
        else
            -- allow trailer space to align after sharp turns (noticed it more affects potato/sugarbeet harvesters with
            -- pipes close to vehicle)
            local pipeLength = math.abs(self:getPipeOffset(self.combineToUnload))
            -- allow for more align space for shorter pipes
            zOffset = -self:getCombinesMeasuredBackDistance() - (pipeLength > 6 and 2 or 5)
        end
        if self:isOkToStartUnloadingCombine() then
            self:startUnloadingCombine()
        elseif self:isPathfindingNeeded(self.vehicle, self:getPipeOffsetReferenceNode(), xOffset, zOffset) then
            self:setNewState(self.states.WAITING_FOR_PATHFINDER)
            self:startPathfindingToWaitingCombine(xOffset, zOffset)
        else
            self:debug('Can\'t start pathfinding to waiting combine, and not in a good position to unload, too close?')
            self:startWaitingForSomethingToDo()
        end
        return true
    end
end

------------------------------------------------------------------------------------------------------------------------
-- target can be a waypoint or a node, return a node
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:getTargetNode(target)
    local targetNode
    if type(target) ~= 'number' then
        -- target is a waypoint
        if not AIDriveStrategyUnloadCombine.helperNode then
            AIDriveStrategyUnloadCombine.helperNode = CpUtil.createNode('combineUnloadAIDriverHelper', target.x, target.z, target.yRot)
        end
        setTranslation(AIDriveStrategyUnloadCombine.helperNode, target.x, target.y, target.z)
        setRotation(AIDriveStrategyUnloadCombine.helperNode, 0, target.yRot, 0)
        targetNode = AIDriveStrategyUnloadCombine.helperNode
    elseif entityExists(target) then
        -- target is a node
        targetNode = target
    else
        self:debug('Target is not a waypoint or node')
    end
    return targetNode
end

---@param targetNode number|nil if a target node is given, will check for fruit there (accounting for xOffset and
--- zOffset), and if there is, will return math.huge to disable fruit avoidance, even if it is otherwise allowed
---@param xOffset number|nil
---@param zOffset number|nil
function AIDriveStrategyUnloadCombine:getMaxFruitPercent(targetNode, xOffset, zOffset)
    if targetNode and self:isFruitAt(targetNode, xOffset or 0, zOffset or 0) then
        self:info('There is fruit at the target, disabling fruit avoidance')
        return math.huge
    end
    if self.settings.avoidFruit:getValue() then
        return AIDriveStrategyUnloadCombine.maxFruitPercent
    else
        return math.huge
    end
end

function AIDriveStrategyUnloadCombine:getOffFieldPenalty(combineToUnload)
    local offFieldPenalty = PathfinderContext.defaultOffFieldPenalty
    if combineToUnload then
        if combineToUnload:getCpDriveStrategy():isOnHeadland(1) then
            -- when the combine is on the first headland, chances are that we have to drive off-field to it,
            -- so make the life easier for the pathfinder
            offFieldPenalty = PathfinderContext.defaultOffFieldPenalty / 5
            self:debug('Combine is on first headland, reducing off-field penalty for pathfinder to %.1f', offFieldPenalty)
        elseif combineToUnload:getCpDriveStrategy():isOnHeadland(2) then
            -- reduce less when on the second headland, there's more chance we'll be able to get to the combine
            -- on the headland
            offFieldPenalty = PathfinderContext.defaultOffFieldPenalty / 3
            self:debug('Combine is on second headland, reducing off-field penalty for pathfinder to %.1f', offFieldPenalty)
        end
    end
    return offFieldPenalty
end

------------------------------------------------------------------------------------------------------------------------
-- Check if it makes sense to start pathfinding to the target
-- This should avoid generating a big circle path to a point a few meters ahead or behind
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:isPathfindingNeeded(vehicle, target, xOffset, zOffset, range, sameDirectionThresholdDeg)
    local targetNode = self:getTargetNode(target)
    if not targetNode then
        return false
    end
    local startNode = vehicle:getAIDirectionNode()
    local dx, _, dz = localToLocal(targetNode, startNode, xOffset, 0, zOffset)
    local d = MathUtil.vector2Length(dx, dz)
    local sameDirection = CpMathUtil.isSameDirection(startNode, targetNode, sameDirectionThresholdDeg or 30)
    if d < (range or self.pathfindingRange) and sameDirection then
        self:debug('No pathfinding needed, d = %.1f, same direction %s', d, tostring(sameDirection))
        return false
    else
        self:debug('Ok to start pathfinding, d = %.1f, same direction %s', d, tostring(sameDirection))
        return true
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Is there fruit at the target (node or waypoint)
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:isFruitAt(target, xOffset, zOffset)
    local targetNode = self:getTargetNode(target)
    if not targetNode then
        return false
    end
    local x, _, z = localToWorld(targetNode, xOffset, 0, zOffset)
    local hasFruit = PathfinderUtil.hasFruit(x, z, 1, 1)
    self:debug('isFruitAt %s, x = %.1f, z = %.1f (xOffset = %.1f, zOffset = %.1f', tostring(hasFruit), x, z, xOffset, zOffset)
    return hasFruit
end

------------------------------------------------------------------------------------------------------------------------
-- Where are we related to the combine?
------------------------------------------------------------------------------------------------------------------------
---@return number, number, number distance between the tractor's front and the combine's back (always positive),
--- side offset (local x) of the combine's back in the tractor's front coordinate system (positive if the tractor is on
--- the right side of the combine)
--- back offset (local z) of the combine's back in the tractor's front coordinate system (positive if the tractor is behind
--- the combine)
function AIDriveStrategyUnloadCombine:getDistanceFromCombine(combine)
    local dx, _, dz = localToLocal(Markers.getBackMarkerNode(combine or self.combineToUnload),
            Markers.getFrontMarkerNode(self.vehicle), 0, 0, 0)
    return MathUtil.vector2Length(dx, dz), dx, dz
end

------------------------------------------------------------------------------------------------------------------------
-- Update combine status
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:updateCombineStatus()
    if not self.combineToUnload then
        return
    end
    -- add hysteresis to reversing info from combine, isReversing() may temporarily return false during reversing, make sure we need
    -- multiple update loops to change direction
    local combineToUnloadReversing = self.combineToUnloadReversing + (self.combineToUnload:getCpDriveStrategy():isReversing() and 0.1 or -0.1)
    if self.combineToUnloadReversing < 0 and combineToUnloadReversing >= 0 then
        -- direction changed
        self.combineToUnloadReversing = 1
    elseif self.combineToUnloadReversing > 0 and combineToUnloadReversing <= 0 then
        -- direction changed
        self.combineToUnloadReversing = -1
    else
        self.combineToUnloadReversing = CpMathUtil.clamp(combineToUnloadReversing, -1, 1)
    end
end

function AIDriveStrategyUnloadCombine:isMyCombineReversing()
    return self.combineToUnloadReversing > 0
end

------------------------------------------------------------------------------------------------------------------------
-- Check for full trailer when unloading a combine
---@return boolean true when changed to unload course
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:changeToUnloadWhenTrailerFull()
    --when trailer is full then go to unload
    if self:isDriveUnloadNowRequested() or self:getAllTrailersFull() then
        if self:isDriveUnloadNowRequested() then
            self:debug('drive now requested, changing to unload course.')
        else
            self:debug('trailer full, changing to unload course.')
        end
        if self.combineToUnload:getCpDriveStrategy():isTurning() or
                self.combineToUnload:getCpDriveStrategy():isAboutToTurn() then
            self:debug('... but we are too close to the end of the row, or combine is turning, moving back before changing to unload course')
        elseif self.combineToUnload and self.combineToUnload:getCpDriveStrategy():isAboutToReturnFromPocket() then
            self:debug('... letting the combine return from the pocket')
        else
            self:debug('... moving back a little in case AD wants to take over')
        end
        self:releaseCombine()
        self:startMovingBackFromCombine(self.states.MOVING_BACK_WITH_TRAILER_FULL, self.combineJustUnloaded)
        return true
    end
    return false
end

function AIDriveStrategyUnloadCombine:checkForCombineProximity()
    -- do not swerve for our combine towards the end of the course,
    -- otherwise we won't be able to align with it when coming from
    -- the wrong angle
    -- Increased distance from 20 to 75, so we don't swerve for our combine
    -- when we are coming from the front and drive to close to our combine
    if self.course:getDistanceToLastWaypoint(self.course:getCurrentWaypointIx()) < 75 then
        if not self.doNotSwerveForVehicle:get() then
            self:debug('Disable swerve for %s', CpUtil.getName(self.combineToUnload))
        end
        self.doNotSwerveForVehicle:set(self.combineToUnload, 2000)
    end

end

--- If the combine has a turn between its current position and the rendezvous waypoint,
--- we probably rather not approach the area around the turn so we are not in the way
--- of the combine while it is turning.
function AIDriveStrategyUnloadCombine:checkForCombineTurnArea()
    local turnAreaCenterWp, r = self.combineToUnload:getCpDriveStrategy():getTurnArea()
    if turnAreaCenterWp and turnAreaCenterWp:getDistanceFromVehicle(self.vehicle) <= r then
        self:debugSparse('Waiting for combine to pass the turn at %.1f, %.1f (r = %.1f) before the rendezvous waypoint',
                turnAreaCenterWp.x, turnAreaCenterWp.z, r)
        self:setMaxSpeed(0)
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Drive to stopped combine
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:driveToCombine()

    self:checkForCombineProximity()

    self:setFieldSpeed()

    self.combineToUnload:getCpDriveStrategy():reconfirmRendezvous()

    -- towards the end of the course we start checking if we can already switch to unload
    if self.course:getDistanceToLastWaypoint(self.course:getCurrentWaypointIx()) < 15 and
            self:isOkToStartUnloadingCombine() then
        self:startUnloadingCombine()
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Drive to moving combine
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:driveToMovingCombine()

    self:checkForCombineProximity()

    self:setFieldSpeed()

    self:checkForCombineTurnArea()

    -- stop when too close to a combine not ready to unload (wait until it is done with turning for example)
    if self:isWithinSafeManeuveringDistance(self.combineToUnload) and self.combineToUnload:getCpDriveStrategy():isManeuvering() then
        self:startWaitingForManeuveringCombine()
    elseif self:isOkToStartUnloadingCombine() then
        self:startUnloadingCombine()
    end

    if self.combineToUnload:getCpDriveStrategy():isWaitingForUnload() then
        self:debug('combine is now stopped and waiting for unload, wait for it to call again')
        self:startWaitingForSomethingToDo()
        return
    end

    if self.course:isCloseToLastWaypoint(AIDriveStrategyUnloadCombine.driveToCombineCourseExtensionLength / 2) and
            self.combineToUnload:getCpDriveStrategy():hasRendezvousWith(self.vehicle) then
        self:debugSparse('Combine is late, waiting ...')
        self:setMaxSpeed(0)
        -- stop confirming the rendezvous, allow the combine to time out if it can't get here on time
    else
        -- yes honey, I'm on my way!
        self.combineToUnload:getCpDriveStrategy():reconfirmRendezvous()
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Waiting for maneuvering combine
-----------------------------------------------`-------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:startWaitingForManeuveringCombine()
    self:debug('Too close to maneuvering combine, stop.')
    -- remember where the combine was when we started waiting
    self.lastCombinePos = {}
    self.lastCombinePos.x, self.lastCombinePos.y, self.lastCombinePos.z = getWorldTranslation(self.combineToUnload.rootNode)
    _, self.lastCombinePos.yRotation, _ = getWorldRotation(self.combineToUnload.rootNode)
    self.stateAfterWaitingForManeuveringCombine = self.state
    self:setNewState(self.states.WAITING_FOR_MANEUVERING_COMBINE)
end

function AIDriveStrategyUnloadCombine:waitForManeuveringCombine()
    if self:isWithinSafeManeuveringDistance(self.combineToUnload) and self.combineToUnload:getCpDriveStrategy():isManeuvering() then
        self:setMaxSpeed(0)
    else
        self:debug('Combine stopped maneuvering')
        --check whether the combine moved significantly while we were waiting
        local _, yRotation, _ = getWorldRotation(self.combineToUnload.rootNode)
        local dx, _, dz = worldToLocal(self.combineToUnload.rootNode, self.lastCombinePos.x, self.lastCombinePos.y, self.lastCombinePos.z)
        local distanceCombineMoved = MathUtil.vector2Length(dx, dz)
        if math.abs(yRotation - self.lastCombinePos.yRotation) > math.pi / 6 or distanceCombineMoved > 30 then
            self:debug('Combine moved (%d) or turned significantly while I was waiting, re-evaluate situation', distanceCombineMoved)
            self:startWaitingForSomethingToDo()
        else
            self:setNewState(self.stateAfterWaitingForManeuveringCombine)
        end
    end
end


------------------------------------------------------------------------------------------------------------------------
-- Unload combine (stopped)
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:unloadStoppedCombine()
    if self:changeToUnloadWhenTrailerFull() then
        return
    end
    local gx, gz
    local combineDriver = self.combineToUnload:getCpDriveStrategy()
    if combineDriver:isUnloadFinished() then
        if combineDriver:isWaitingForUnloadAfterCourseEnded() then
            if combineDriver:getFillLevelPercentage() < 0.1 then
                if self:areThereAnyCombinesOrLoaderLeftoverOnTheField(self.combineToUnload, combineDriver) then
                    self:debug('Finished unloading combine at end of fieldwork, but there are more unload targets left over on the field.')
                    self.ppc:setNormalLookaheadDistance()
                    self:releaseCombine()
                    self:startMovingBackFromCombine(self.states.MOVING_BACK, self.combineJustUnloaded)
                else
                    self:debug('Finished unloading combine at end of fieldwork, changing to unload course')
                    self.ppc:setNormalLookaheadDistance()
                    self:releaseCombine()
                    self:startMovingBackFromCombine(self.states.MOVING_BACK_WITH_TRAILER_FULL, self.combineJustUnloaded)
                end
            else
                gx, gz = self:driveBesideCombine()
            end
        else
            self:debug('finished unloading stopped combine, move back a bit to make room for it to continue')
            self:startMovingBackFromCombine(self.states.MOVING_BACK, self.combineToUnload, true)
            self.ppc:setNormalLookaheadDistance()
        end
    else
        gx, gz = self:driveBesideCombine()
    end
    return gx, gz
end

------------------------------------------------------------------------------------------------------------------------
-- Unload combine (moving)
-- We are driving on a copy of the combine's course with an offset
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:unloadMovingCombine()

    -- allow on the fly offset changes
    self.combineOffset = self:getPipeOffset(self.combineToUnload)
    self.followCourse:setOffset(-self.combineOffset, 0)

    if self:changeToUnloadWhenTrailerFull() then
        return
    end

    local combineStrategy = self.combineToUnload:getCpDriveStrategy()
    local gx, gz = self:driveBesideCombine()

    --when the combine is empty, stop and wait for next combine (unless this can't work without an unloader nearby)
    if combineStrategy:getFillLevelPercentage() <= 0.1 and not combineStrategy:alwaysNeedsUnloader() then
        self:debug('Combine empty, finish unloading.')
        self:onUnloadingMovingCombineFinished(combineStrategy)
        return
    end

    -- combine stopped in the meanwhile, like for example end of course
    if combineStrategy:willWaitForUnloadToFinish() then
        self:debug('change to unload stopped combine')
        self:setNewState(self.states.UNLOADING_STOPPED_COMBINE)
        return
    end

    if combineStrategy:isTurning() then
        if not combineStrategy:isFinishingRow() then
            -- harvester is now about the start the turn after it finished the row
            -- in any case, we stop here, don't want to follow it through the turn.
            -- We expect it to stop here as well until empty (see shouldHoldInTurnManeuver())
            self:setMaxSpeed(0)
            if combineStrategy:alwaysNeedsUnloader() then
                if not combineStrategy:isProcessingFruit() then
                    self:debug('Harvester stopped processing fruit, finish unloading')
                    self:onUnloadingMovingCombineFinished(combineStrategy)
                    return
                else
                    -- harvester has still some fruit in the belly, wait until all is discharged
                    self:debugSparse('Waiting for harvester to stop processing fruit')
                end
            else
                self:debugSparse('Combine turning, wait until it stops discharging.')
            end
        end
    elseif combineStrategy:isManeuvering() then
        -- when the combine is turning just don't move
        self:setMaxSpeed(0)
    elseif self.followCourse:isTurnStartAtIx(self.followCourse:getCurrentWaypointIx()) then
        -- big rigs may reach the turn before the combine, add a small straight course here so we have
        -- something to follow until the combine reaches the turn (so we don't try to make the turn
        -- also apply an offset as the followCourse is assumed to be the combine's course
        -- TODO: #3029
        self:debug('waypoint %d is a turn start, creating temporary course to stay on track', self.followCourse:getCurrentWaypointIx())
        -- to build a reverse course from the turn start back when we need it later, this will nicely
        -- follow the original headland even if it isn't straight
        self.reverseForTurnCourse = self.followCourse:getSectionAsNewCourse(
                self.followCourse:getCurrentWaypointIx(),
                self.followCourse:getCurrentWaypointIx() - 10,
                true)
        self.followCourse = Course.createStraightForwardCourse(self.vehicle, 20, -self.combineOffset)
        self.followCourse:setOffset(-self.combineOffset, 0)
        self:startCourse(self.followCourse, 1)
    elseif not self:isBehindAndAlignedToCombine() and not self:isInFrontAndAlignedToMovingCombine() then
        -- call these again just to log the reason
        self:isBehindAndAlignedToCombine(true)
        self:isInFrontAndAlignedToMovingCombine(true)
        self:info('not in a good position to unload, cancelling rendezvous, trying to recover')
        -- for some reason (like combine turned) we are not in a good position anymore then set us up again
        self:startWaitingForSomethingToDo()
    end
    return gx, gz
end

function AIDriveStrategyUnloadCombine:onUnloadingMovingCombineFinished(combineStrategy)
    --when the combine is in a pocket, make room to get back to course
    if combineStrategy:isWaitingInPocket() then
        self:debug('combine empty and in pocket, drive back')
        self:startMovingBackFromCombine(self.states.MOVING_BACK, self.combineToUnload)
        return
    elseif combineStrategy:isTurningOnHeadland() then
        self:debug('combine empty and turning on headland, moving back')
        self:startMakingRoomForCombineTurningOnHeadland(self.combineToUnload)
    elseif combineStrategy:isTurning() or combineStrategy:isAboutToTurn() then
        self:debug('combine empty and moving forward but we are too close to the end of the row or combine is turning, moving back')
        self:startMovingBackFromCombine(self.states.MOVING_BACK, self.combineToUnload, true)
        return
    elseif self:getAllTrailersFull(self.settings.fullThreshold:getValue()) then
        -- make some room for the pathfinder, as the trailer may not be full but has reached the threshold,
        --, which case is not caught in changeToUnloadWhenTrailerFull() as we want to keep unloading as long as
        -- we can
        self:debug('combine empty and moving forward but we want to leave, so move back a bit')
        self:startMovingBackFromCombine(self.states.MOVING_BACK_WITH_TRAILER_FULL, self.combineToUnload)
        return
    else
        self:debug('combine empty and moving forward')
        self:releaseCombine()
        self:startWaitingForSomethingToDo()
        return
    end
end
------------------------------------------------------------------------------------------------------------------------
-- Start moving back from empty combine
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:startMovingBackFromCombine(newState, combine, holdCombineWhileMovingBack)
    if self.unloadTargetType == self.UNLOAD_TYPES.SILO_LOADER then
        --- Finished unloading of silo unloader. Moving back is not needed.
        self:setNewState(self.states.IDLE)
        return
    end

    local reverseCourse = Course.createStraightReverseCourse(self.vehicle, 15)
    self:startCourse(reverseCourse, 1)
    self:setNewState(newState)
    self.state.properties.vehicle = combine
    self.state.properties.holdCombine = holdCombineWhileMovingBack
    return
end

------------------------------------------------------------------------------------------------------------------------
-- We missed a rendezvous with the combine
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:onMissedRendezvous(combine)
    self:debug('missed the rendezvous with %s', CpUtil.getName(combine))
    if self.state == self.states.DRIVING_TO_MOVING_COMBINE and
            self.combineToUnload == combine then
        if self.course:getDistanceToLastWaypoint(self.course:getCurrentWaypointIx()) > 100 then
            self:debug('over 100 m from the combine to rendezvous, re-planning')
            self:startWaitingForSomethingToDo()
        end
    else
        self:debug('ignore missed rendezvous')
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Set up a course to move out of the way of a blocking vehicle
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:createMoveAwayCourse(blockingVehicle, isAheadOfUs, trailer)
    if isAheadOfUs then
        self:debug('%s is in front, moving back', CpUtil.getName(blockingVehicle))
        -- blocking vehicle in front of us, move back, calculate course from the trailer's root node
        return Course.createFromNode(self.vehicle, trailer.rootNode, 0, -2, -27, -5, true)
    else
        -- blocking vehicle behind, move forward
        local _, frontMarkerOffset = Markers.getFrontMarkerNode(self.vehicle)
        self:debug('%s is behind us, moving forward', CpUtil.getName(blockingVehicle))
        return Course.createFromNode(self.vehicle, self.vehicle:getAIDirectionNode(), 0,
                frontMarkerOffset, frontMarkerOffset + self.maxDistanceWhenMovingOutOfWay, 5, false)
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Is there another vehicle blocking us?
------------------------------------------------------------------------------------------------------------------------
--- If the other vehicle is a combine driven by CP, we will try get out of its way. Otherwise, if we are not being
--- held already, we tell the other vehicle to hold, and will attempt to get out of its way.
--- This is to make sure that only one of the two vehicles yields to the other one
--- If the other vehicle is an unloader in the idle state, we'll ask it to move as we are busy and it has
--- nothing to do anyway. Such a situation can arise when the first unloader just finished overloading to a waiting
--- trailer and pulled ahead a bit, waiting for a combine to call, when a second unloader arrives to the trailer
--- to overload, but can't get close enough because it is blocked by the first, idle one.
function AIDriveStrategyUnloadCombine:onBlockingVehicle(blockingVehicle, isBack)
    if not self.vehicle:getIsCpActive() or isBack then
        self:debug('%s has been blocking us for a while, ignoring as either not active or in the back', CpUtil.getName(blockingVehicle))
        return
    end
    if self.state ~= self.states.MOVING_AWAY_FROM_OTHER_VEHICLE and
            self.state ~= self.states.BACKING_UP_FOR_REVERSING_COMBINE and
            self.state ~= self.states.FOLLOW_CHOPPER_THROUGH_TURN and
            not self:isBeingHeld() then
        self:debug('%s has been blocking us for a while, move a bit', CpUtil.getName(blockingVehicle))
        local course
        local isBlockingVehicleAheadOfUs = AIUtil.isOtherVehicleAhead(self.vehicle, blockingVehicle)
        -- TODO: maybe a generic getTrailer() ?
        local referenceObject = AIUtil.getImplementOrVehicleWithSpecialization(self.vehicle, Trailer) or
                AIUtil.getImplementOrVehicleWithSpecialization(self.vehicle, HookLiftTrailer) or self.vehicle
        if AIDriveStrategyCombineCourse.isActiveCpCombine(blockingVehicle) then
            -- except we are blocking our buddy, so set up a course parallel to the combine's direction,
            -- with an offset from the combine that makes sure we are clear. Use the trailer's root node (and not
            -- the tractor's) as when we reversing, it is easier when the trailer remains on the same side of the combine
            local dx, _, _ = localToLocal(referenceObject.rootNode, blockingVehicle:getAIDirectionNode(), 0, 0, 0)
            local xOffset = self.vehicle.size.width / 2 + blockingVehicle:getCpDriveStrategy():getWorkWidth() / 2 + 2
            xOffset = dx > 0 and xOffset or -xOffset
            self:setNewState(self.states.MOVING_AWAY_FROM_OTHER_VEHICLE)
            self.state.properties.vehicle = blockingVehicle
            self.state.properties.dx = nil
            if isBlockingVehicleAheadOfUs and
                    CpMathUtil.isOppositeDirection(self.vehicle:getAIDirectionNode(), blockingVehicle:getAIDirectionNode(), 30) then
                -- we are head on with the combine, so reverse
                -- we will generate a straight reverse course relative to the blocking vehicle, but we want the course start
                -- approximately where our back marker is, as we will be reversing
                local _, _, from = localToLocal(Markers.getBackMarkerNode(self.vehicle), blockingVehicle:getAIDirectionNode(), 0, 0, 0)
                self:debug('%s is a CP combine, head on, so generate a course from %.1f m, xOffset %.1f',
                        CpUtil.getName(blockingVehicle), from, xOffset)
                course = Course.createFromNode(self.vehicle, blockingVehicle:getAIDirectionNode(), xOffset, from,
                        from + self.maxDistanceWhenMovingOutOfWay, 5, true)
                -- we will stop reversing when we are far enough from the combine's path
                self.state.properties.dx = xOffset
            elseif not isBlockingVehicleAheadOfUs and
                    CpMathUtil.isSameDirection(self.vehicle:getAIDirectionNode(), blockingVehicle:getAIDirectionNode(), 30) then
                -- we are in front of the combine, same direction
                -- we will generate a straight forward course relative to the blocking vehicle, but we want the course start
                -- approximately where our front marker is
                local _, _, from = localToLocal(Markers.getFrontMarkerNode(self.vehicle), blockingVehicle:getAIDirectionNode(), 0, 0, 0)
                self:debug('%s is a CP combine, same direction, generate a course from %.1f with xOffset %.1f',
                        CpUtil.getName(blockingVehicle), from, xOffset)
                course = Course.createFromNode(self.vehicle, blockingVehicle:getAIDirectionNode(), xOffset, from,
                        from + self.maxDistanceWhenMovingOutOfWay, 5, false)
                -- drive the entire course, making sure the trailer is also out of way
                self.state.properties.dx = xOffset
            else
                self:debug('%s is a CP combine, not head on, not same direction', CpUtil.getName(blockingVehicle))
                self.state.properties.dx = nil
                course = self:createMoveAwayCourse(blockingVehicle, isBlockingVehicleAheadOfUs, referenceObject)
            end
        elseif (AIDriveStrategyUnloadCombine.isActiveCpCombineUnloader(blockingVehicle) or
                AIDriveStrategyUnloadCombine.isActiveCpSiloLoader(blockingVehicle)) and
                blockingVehicle:getCpDriveStrategy():isIdle() then
            self:debug('%s is an idle CP combine unloader, request it to move.', CpUtil.getName(blockingVehicle))
            blockingVehicle:getCpDriveStrategy():requestToMoveForward(self.vehicle)
            -- no state change, wait for the other unloader to move
            return
        else
            self:debug('%s is not a combine and not an idle unloader, moving out of their way.', CpUtil.getName(blockingVehicle))
            -- straight back or forward
            course = self:createMoveAwayCourse(blockingVehicle, isBlockingVehicleAheadOfUs, referenceObject)
            self:setNewState(self.states.MOVING_AWAY_FROM_OTHER_VEHICLE)
            self.state.properties.vehicle = blockingVehicle
            self.state.properties.dx = nil
            if blockingVehicle.cpHold then
                -- ask the other vehicle for hold until we drive around
                blockingVehicle:cpHold(20000)
            end
        end
        self:startCourse(course, 1)
    end
end

function AIDriveStrategyUnloadCombine:requestToMoveOutOfWay(vehicle)
    self:onBlockingVehicle(vehicle)
end

function AIDriveStrategyUnloadCombine:requestToMoveForward(requestingVehicle)
    self:debug('%s requests us to move forward.', CpUtil.getName(requestingVehicle))
    local course = Course.createStraightForwardCourse(self.vehicle, self.maxDistanceWhenMovingOutOfWay, 0)
    self:setNewState(self.states.MOVING_AWAY_FROM_OTHER_VEHICLE)
    self.state.properties.vehicle = requestingVehicle
    self.state.properties.dx = nil
    self:startCourse(course, 1)
end

function AIDriveStrategyUnloadCombine:moveAwayFromOtherVehicle()
    self:setMaxSpeed(self.settings.reverseSpeed:getValue())
    local driveStrategy = self.state.properties.vehicle.getCpDriveStrategy and self.state.properties.vehicle:getCpDriveStrategy()
    -- Are we still close to the vehicle we are blocking?
    if driveStrategy and driveStrategy:isVehicleInProximity(self.vehicle) then
        -- keep driving
        self:debugSparse('Still in proximity of %s', CpUtil.getName(self.state.properties.vehicle))
        self.movingAwayDelay:set(true, 2000)
        return
    end

    -- keep driving for a while after we are out of the proximity of the vehicle we were blocking, to make
    -- sure we have enough clearance
    if self.movingAwayDelay:get() then
        return
    end

    if self.state.properties.dx then
        -- moving away from a CP combine head on with us, move until dx is big enough so it can continue straight
        for _, childVehicle in ipairs(self.vehicle:getChildVehicles()) do
            local dx, _, _ = localToLocal(childVehicle.rootNode, self.state.properties.vehicle:getAIDirectionNode(), 0, 0, 0)
            self:debugSparse('dx between %s and my %s is %.1f', CpUtil.getName(self.state.properties.vehicle), CpUtil.getName(childVehicle), dx)
            if math.abs(dx) < math.abs(self.state.properties.dx) - 1 then
                return
            end
        end
        -- none of my child vehicles are closer than dx to the combine
        self:debug('Moved away from blocking CP combine %s', CpUtil.getName(self.state.properties.vehicle))
        self:startWaitingForSomethingToDo()
    else
        -- moving away from some other vehicle, or our combine not head on, just move until we can
        -- recalculate a path
        local d = calcDistanceFrom(self.vehicle.rootNode, self.state.properties.vehicle.rootNode)
        self:debugSparse('d from %s is %.1f', CpUtil.getName(self.state.properties.vehicle), d)
        if d > 2 * self.turningRadius then
            self:debug('Moved away from blocking vehicle %s', CpUtil.getName(self.state.properties.vehicle))
            self:startWaitingForSomethingToDo()
        end
    end
end

------------------------------------------------------------------------------------------------------------------------
--- Combine is reversing and we are behind it
------------------------------------------------------------------------------------------------------------------------
--- The harvester must keep calling this periodically (less than 3s), as long as it wants us to move.
function AIDriveStrategyUnloadCombine:requestToBackupForReversingCombine(blockedVehicle)
    if not self.vehicle:getIsCpActive() then
        return
    end
    if blockedVehicle ~= self.vehicleRequestingBackUp:get() then
        self:debug('%s is reversing and wants me to back up', blockedVehicle:getName())
    else
        self:debugSparse('%s is still reversing and wants me to back up', blockedVehicle:getName())
    end
    self.vehicleRequestingBackUp:set(blockedVehicle, 3000)
    -- if we are in one of these states, we are already backing up
    if not self.state.properties.denyBackupRequest then
        -- reverse back a bit, this usually solves the problem
        -- TODO: there may be better strategies depending on the situation
        self:rememberCourse(self.course, self.course:getCurrentWaypointIx())
        self.stateAfterMovedOutOfWay = self.state

        self:setNewState(self.states.BACKING_UP_FOR_REVERSING_COMBINE)
        local _, backMarker = Markers.getMarkerNodes(self.vehicle)
        local reverseCourse = Course.createStraightReverseCourse(self.vehicle,
                AIDriveStrategyUnloadCombine.maxDistanceWhenMovingOutOfWay, 0, backMarker)
        self:startCourse(reverseCourse, 1)
        self:debug('Backing up for reversing %s', blockedVehicle:getName())
        self.state.properties.vehicle = blockedVehicle
        -- this state ends when we reach the end of the course or when the combine stops reversing
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Moving out of the way of a reversing combine
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:backUpForReversingCombine()
    -- check both distances and use the smaller one, proximity sensor may not see the combine or
    -- d may be big enough but parts of the combine still close
    local blockedVehicle = self.state.properties.vehicle
    local d = self:getDistanceFromCombine(blockedVehicle)
    local dProximity, vehicleInFront = self.proximityController:checkBlockingVehicleFront()
    local combineSpeed = (blockedVehicle.lastSpeedReal * 3600)
    local speed = combineSpeed + CpMathUtil.clamp(self.minDistanceWhenMovingOutOfWay - math.min(d, dProximity),
            -combineSpeed, self.settings.reverseSpeed:getValue() * 1.2)

    self:setMaxSpeed(speed)

    -- combine not requesting anymore
    if self.vehicleRequestingBackUp:get() == nil then
        self:debug('request from %s timed out, stop backing up', blockedVehicle:getName())
        self:onLastWaypointPassed()
    end
end

------------------------------------------------------------------------------------------------------------------------
--- When we were unloading a combine on the headland while it reached a headland turn,
--- it stopped until it was empty, and now about the start the turn. We have to move 
--- out of its way now. 
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:startMakingRoomForCombineTurningOnHeadland(combine)
    self:setNewState(self.states.MOVING_BACK_FOR_HEADLAND_TURN)
    -- reversing almost straight is better this
    self.ppc:setNormalLookaheadDistance()
    if self.reverseForTurnCourse then
        -- if we have a follow course from before the turn, then use that
        self.reverseForTurnCourse:setOffset(-self.combineOffset, 0)
        self:startCourse(self.reverseForTurnCourse, 1)
    else
        local reverseCourse = Course.createStraightReverseCourse(self.vehicle,
                AIDriveStrategyUnloadCombine.maxDistanceWhenMovingOutOfWay)
        self:startCourse(reverseCourse, 1)
    end
    self.state.properties.vehicle = combine
    self.state.properties.holdCombine = true
end

------------------------------------------------------------------------------------------------------------------------
--- When the harvester is making a headland turn, stay away from it by backing up, but not too far
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:makeRoomForCombineTurningOnHeadland()
    local dProximity, _ = self.proximityController:checkBlockingVehicleFront()
    local d, _, dz = self:getDistanceFromCombine(self.combineToUnload)
    local dLimit = 0.6 * self.combineToUnload:getCpDriveStrategy():getWorkWidth()
    -- if we are already behind the harvester's back and far enough and not blocking it and
    -- not in our proximity, then stop
    if dz > 0 and d > dLimit and dProximity > dLimit then
        self:setMaxSpeed(0)
    else
        -- otherwise keep moving back
        self:setMaxSpeed(self.settings.reverseSpeed:getValue())
    end
    if not self:getCombineIsTurning() then
        self:debug('Harvester stopped turning, wait for call.')
        self:startWaitingForSomethingToDo()
    end
end

function AIDriveStrategyUnloadCombine:findOtherUnloaderAroundCombine(combine, combineOffset)
    if not combine then
        return nil
    end
    if g_currentMission then
        for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
            if vehicle ~= self.vehicle and vehicle.cp.driver and vehicle.cp.driver:is_a(AIDriveStrategyUnloadCombine) then
                local dx, _, dz = localToLocal(vehicle.rootNode, combine:getAIDirectionNode(), 0, 0, 0)
                if math.abs(dz) < 30 and math.abs(dx) <= (combineOffset + 3) then
                    -- this is another unloader not too far from my combine
                    -- which side it is?
                    self:debugSparse('There is an other unloader (%s) around my combine (%s), dx = %.1f',
                            CpUtil.getName(vehicle), CpUtil.getName(combine), dx)
                    return dx
                end
            end
        end
    end
end

-----------------------------------------------------------------------------------------------------------------------
--- Find a path to the start position marker, but in the opposite direction of the marker and an offset of 4.5 m to the side.
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:startPathfindingToInvertedGoalPositionMarker()
    self:setNewState(self.states.WAITING_FOR_PATHFINDER)
    local fieldNum = CpFieldUtil.getFieldNumUnderVehicle(self.vehicle)

    local context = PathfinderContext(self.vehicle)
    context:maxFruitPercent(self:getMaxFruitPercent()):offFieldPenalty(PathfinderContext.defaultOffFieldPenalty)
    context:useFieldNum(fieldNum):allowReverse(self:getAllowReversePathfinding())
    context:maxIterations(PathfinderUtil.getMaxIterationsForFieldPolygon(self.vehicle:cpGetFieldPolygon()))
    self.pathfinderController:registerListeners(self, self.onPathfindingDoneToInvertedGoalPositionMarker,
            self.onPathfindingFailedToStationaryTarget, self.onPathfindingObstacleAtStart)
    self.pathfinderController:findPathToNode(context, self.invertedStartPositionMarkerNode,
            self.invertedGoalPositionOffset, -1.5 * AIUtil.getLength(self.vehicle), 3)
end

--- Path to the start position was found.
---@param path table
---@param goalNodeInvalid boolean
function AIDriveStrategyUnloadCombine:onPathfindingDoneToInvertedGoalPositionMarker(controller, success, course, goalNodeInvalid)
    if success and self.state == self.states.WAITING_FOR_PATHFINDER then
        self:debug("Found a path to the inverted goal position marker. Appending the missing straight segment.")
        self:setNewState(self.states.DRIVING_BACK_TO_START_POSITION_WHEN_FULL)
        --- Append a straight alignment segment
        local x, _, z = course:getWaypointPosition(course:getNumberOfWaypoints())
        local dx, _, dz = localToWorld(self.invertedStartPositionMarkerNode, self.invertedGoalPositionOffset, 0, 0)

        course:append(Course.createFromTwoWorldPositions(self.vehicle, x, z, dx, dz,
                0, 0, 0, 3, false))
        self:startCourse(course, 1)
    else
        self:debug("Could not find a path to the start position marker, pass over to the job!")
        self:onTrailerFull()
    end
end

-----------------------------------------------------------------------------------------------------------------------
--- Self unload
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:getSelfUnloadTargetParameters()
    return SelfUnloadHelper:getTargetParameters(
            self.vehicle:cpGetFieldPolygon(),
            self.vehicle,
            self.augerWagon,
            self.pipeController)
end

--- Find a path to the best trailer to unload
---@param ignoreFruit boolean if true, do not attempt to avoid fruit
function AIDriveStrategyUnloadCombine:startSelfUnload(ignoreFruit)

    if not self.pathfinder or not self.pathfinder:isActive() then
        local alignLength, offsetX, unloadTrailer
        self.selfUnloadTargetNode, alignLength, offsetX, unloadTrailer = self:getSelfUnloadTargetParameters()
        if not self.selfUnloadTargetNode then
            return false
        end

        self.unloadTrailer = unloadTrailer

        -- little straight section parallel to the trailer to align better
        self:debug('Align course relative to target node from %.1f to %.1f, pipe offset %.1f',
                -alignLength + 1, -self.pipeController:getPipeOffsetZ() - self.unloadTargetOffset,
                self.pipeController:getPipeOffsetZ())
        self.selfUnloadAlignCourse = Course.createFromNode(self.vehicle, self.selfUnloadTargetNode,
                offsetX, -alignLength + 1,
                -self.pipeController:getPipeOffsetZ() - self.unloadTargetOffset,
                1, false)

        self:setNewState(self.states.WAITING_FOR_PATHFINDER)
        local fieldNum = CpFieldUtil.getFieldNumUnderVehicle(self.vehicle)
        local context = PathfinderContext(self.vehicle)
        -- require full accuracy from pathfinder as we must exactly line up with the trailer
        context:maxFruitPercent(self:getMaxFruitPercent()):offFieldPenalty(PathfinderContext.defaultOffFieldPenalty):mustBeAccurate(true)
        context:useFieldNum(fieldNum):allowReverse(self:getAllowReversePathfinding())
        -- ignore off-field penalty around the trailer to encourage the pathfinder to bridge that gap between the
        -- field and the trailer
        context:areaToIgnoreOffFieldPenalty(
                PathfinderUtil.NodeArea.createVehicleArea(self.unloadTrailer, 1.5 * SelfUnloadHelper.maxDistanceFromField))
        context:maxIterations(PathfinderUtil.getMaxIterationsForFieldPolygon(self.vehicle:cpGetFieldPolygon()))
        self.pathfinderController:registerListeners(self,
                self.onPathfindingDoneBeforeSelfUnload,
                self.onPathfindingFailedBeforeSelfUnload, self.onPathfindingObstacleAtStart)
        self.pathfinderController:findPathToNode(context, self.selfUnloadTargetNode, offsetX, -alignLength, 3)
    else
        self:debug('Pathfinder already active')
    end
    return true
end

function AIDriveStrategyUnloadCombine:onPathfindingFailedBeforeSelfUnload(...)
    self:debug('Pathfinding before self unload failed.')
    self:onPathfindingFailed(function()
        self.vehicle:stopCurrentAIJob(AIMessageCpErrorNoPathFound.new())
    end, ...)
end

function AIDriveStrategyUnloadCombine:onPathfindingDoneBeforeSelfUnload(controller, success, course, goalNodeInvalid)
    if success then
        course:append(self.selfUnloadAlignCourse)
        self:setNewState(self.states.DRIVING_TO_SELF_UNLOAD)
        self:startCourse(course, 1)
        return true
    else
        self:debug('No path found to self unload, stopping job.')
        self.vehicle:stopCurrentAIJob(AIMessageCpErrorNoPathFound.new())
        return false
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Driving to a trailer to unload an auger wagon
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:driveToSelfUnload()
    if self.course:isCloseToLastWaypoint(25) then
        -- disable one side of the proximity sensors to avoid being blocked by the trailer or its tractor
        -- TODO: make it work with pipe on the right side
        if self.pipeController:isPipeOnTheLeftSide() then
            self.proximityController:disableLeftSide()
        else
            self.proximityController:disableRightSide()
        end
    end
    -- slow down towards the end of course
    if self.course:isCloseToLastWaypoint(5) then
        self:setMaxSpeed(5)
    elseif self.course:isCloseToLastWaypoint(15) then
        self:setMaxSpeed(self.settings.turnSpeed:getValue())
    else
        self:setFieldSpeed()
    end
end

function AIDriveStrategyUnloadCombine:onLastWaypointPassedWhenDrivingToSelfUnload()
    self.pipeController:openPipe()
    self:setNewState(self.states.WAITING_FOR_AUGER_PIPE_TO_OPEN)
end

------------------------------------------------------------------------------------------------------------------------
-- Once at the trailer, waiting for the auger wagon's pipe to open
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:waitForAugerPipeToOpen()
    self:setMaxSpeed(0)
    if not self.pipeController:isPipeMoving() or self.pipeController:isPipeOpen() then
        self:setNewState(self.states.UNLOADING_AUGER_WAGON)
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Unload the auger wagon into the trailer
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:unloadAugerWagon()
    local currentDischargeNode = self.augerWagon:getCurrentDischargeNode()
    local _, _, dz = localToLocal(currentDischargeNode.node, self.selfUnloadTargetNode, 0, 0, 0)

    -- move forward or backward slowly until the pipe is within 20 cm of target
    self:setMaxSpeed((math.abs(dz) > 0.2) and 1 or 0)

    if not self.augerWagon:getCanDischargeToObject(currentDischargeNode) then
        local fillLevelPercentage = self:getFillLevelPercentage()
        self:debug('Unloading to trailer ended, my fill level is %.1f', fillLevelPercentage)
        if fillLevelPercentage < 10 then
            self:startMovingAwayFromUnloadTrailer()
        else
            local unloadTrailer
            self.selfUnloadTargetNode, _, _, unloadTrailer = self:getSelfUnloadTargetParameters()

            if self.selfUnloadTargetNode and unloadTrailer == self.unloadTrailer then
                self:debug('Auger wagon has fruit after unloading and the same trailer (%s) seems to have capacity',
                        CpUtil.getName(unloadTrailer))
                self:startMovingToNextFillNode(self.selfUnloadTargetNode)
            else
                -- done with this trailer, move away from it and wait for the
                self:debug('Auger wagon not empty after unloading but done with this trailer (%s) as it is full',
                        CpUtil.getName(self.unloadTrailer))
                self:startMovingAwayFromUnloadTrailer(true)
            end
        end
    end
    -- forward or backward
    return dz < 0
end

-- Start moving to the next fill node of the same trailer
function AIDriveStrategyUnloadCombine:startMovingToNextFillNode(newSelfUnloadTargetNode)
    local _, _, dz = localToLocal(newSelfUnloadTargetNode, self.vehicle:getAIDirectionNode(),
            0, 0, -self.pipeController:getPipeOffsetZ())
    local selfUnloadCourse
    if dz > 0 then
        -- next fill node is in front of us, move forward
        selfUnloadCourse = Course.createFromNode(self.vehicle, self.vehicle:getAIDirectionNode(),
                0, 0, dz + 2, 1, false)
    else
        -- next fill node behind us, need to reverse
        local reverserNode = AIUtil.getReverserNode(self.vehicle, self.augerWagon)
        selfUnloadCourse = Course.createFromNode(self.vehicle, reverserNode, 0, 0, dz - 2, 1, true)
    end
    self:debug('Course to next target node of the same trailer created, dz = %.1f', dz)
    self:setNewState(self.states.MOVING_TO_NEXT_FILL_NODE)
    self:startCourse(selfUnloadCourse, 1)
end

-- Move forward or backward until we can discharge again
function AIDriveStrategyUnloadCombine:moveToNextFillNode()
    local currentDischargeNode = self.augerWagon:getCurrentDischargeNode()
    local _, _, dz = localToLocal(currentDischargeNode.node, self.selfUnloadTargetNode, 0, 0, 0)

    -- move forward or backward slowly towards the target fill node
    self:setMaxSpeed((math.abs(dz) > 0.2) and 1 or 0)

    if self.augerWagon:getCanDischargeToObject(currentDischargeNode) then
        self:debug('Can discharge again, moving closer to the fill node')
        self:setNewState(self.states.UNLOADING_AUGER_WAGON)
    end

    return dz < 0
end

-- Move a bit forward and away from the trailer/tractor we just unloaded into so the
-- pathfinder won't have problems when search for a path to the combine
---@param attemptToUnloadAgainAfterMovedAway boolean after moved away, attempt to find a trailer to unload
--- again as the auger wagon isn't empty yet
function AIDriveStrategyUnloadCombine:startMovingAwayFromUnloadTrailer(attemptToUnloadAgainAfterMovedAway)
    self.selfUnloadTargetNode = nil
    self.attemptToUnloadAgainAfterMovedAway = attemptToUnloadAgainAfterMovedAway
    self.pipeController:closePipe(false)
    self.course = Course.createStraightForwardCourse(self.vehicle, self.maxDistanceWhenMovingOutOfWay,
            self.pipeController:isPipeOnTheLeftSide() and -2 or 2)
    self:setNewState(self.states.MOVING_AWAY_FROM_UNLOAD_TRAILER)
    self:startCourse(self.course, 1)
end

function AIDriveStrategyUnloadCombine:moveAwayFromUnloadTrailer()
    local _, _, dz = localToLocal(self.unloadTrailer.rootNode, Markers.getBackMarkerNode(self.vehicle), 0, 0, 0)
    -- (conveniently ignoring the length offset)
    -- move until our tractor's back marker does not overlap the trailer or it's tractor
    if dz < -math.max(self.unloadTrailer.size.length / 2, self.unloadTrailer.rootVehicle.size.length / 2) then
        self:onMovedAwayFromUnloadTrailer()
    else
        self:setMaxSpeed(5)
    end
end

function AIDriveStrategyUnloadCombine:onMovedAwayFromUnloadTrailer()
    self.proximityController:enableBothSides()
    if self.attemptToUnloadAgainAfterMovedAway then
        self:debug('Moved away from trailer so the pathfinder will work, look for another trailer')
        self:startUnloadingTrailers()
    else
        self:debug('Moved away from trailer so the pathfinder will work')
        self:startWaitingForSomethingToDo()
    end
end


------------------------------------------------------------------------------------------------------------------------
-- Unloading on the field
------------------------------------------------------------------------------------------------------------------------

--- Is the unloader unloading to a heap?
---@param ignoreDrivingToHeap boolean Ignore unloader, that are driving to the heap
---@return boolean
function AIDriveStrategyUnloadCombine:isUnloadingOnTheField(ignoreDrivingToHeap)
    if self.state == self.states.DRIVE_TO_FIELD_UNLOAD_POSITION and ignoreDrivingToHeap then
        return false
    end
    return CpUtil.isStateOneOf(self.state, self.fieldUnloadStates)
            or self.state == self.states.WAITING_FOR_PATHFINDER and CpUtil.isStateOneOf(self.lastState, self.fieldUnloadStates)
end

---@return CpHeapBunkerSilo|nil
function AIDriveStrategyUnloadCombine:getFieldUnloadHeap()
    return self.fieldUnloadData and self.fieldUnloadData.heapSilo
end

--- Starts the unloading on a field with an auger wagon or a trailer.
--- Drives to the heap/ field unload position:
---     For reverse unloading an offset is applied only if an already existing heap was found.
---     For side unloading the x offset of the discharge node is applied.
---@param controller ImplementController either a PipeController or TrailerController
---@param allowReverseUnloading boolean is unloading at the back allowed?
function AIDriveStrategyUnloadCombine:startUnloadingOnField(controller, allowReverseUnloading)
    --- Create unload course based on tip side setting(discharge node offset)
    local dischargeNodeIndex, dischargeNode, xOffset = controller:getDischargeNodeAndOffsetForTipSide(self.unloadTipSideID, true)
    if not xOffset then
        self:info("No valid discharge node for field unload found!")
        self.vehicle:stopCurrentAIJob(AIMessageErrorGroundUnloadNotSupported.new())
        return
    end
    self:debug("Selected tipside: %d, dischargeNodeIndex: %d, xOffset: %.2f", self.unloadTipSideID, dischargeNodeIndex, xOffset)
    self.fieldUnloadData = {
        dischargeNodeIndex = dischargeNodeIndex,
        dischargeNode = dischargeNode,
        xOffset = xOffset,
        controller = controller,
        heapSilo = nil,
        isReverseUnloading = false

    }

    --- Search for a heap at the field unload position
    --- for reverse unloading or to make sure the pathfinding
    --- is not crossing the heap area.
    local found, heapSilo = BunkerSiloManagerUtil.createHeapBunkerSilo(self.vehicle,
            self.fieldUnloadPositionNode, 0, CpAIJobCombineUnloader.maxHeapLength, -10)

    if found and heapSilo then
        --- Heap was found
        self.fieldUnloadData.heapSilo = heapSilo

        --- Set the unloading node in the center between heap sx/sz and wx/wz.
        self:updateFieldPositionByHeapSilo(heapSilo)

        if allowReverseUnloading then
            --- Reverse unloading is allowed, then check if the tip side xOffset is for reverse unloading <= 1 m.
            self.fieldUnloadData.isReverseUnloading = math.abs(self.fieldUnloadData.xOffset) - 1 <= 0
        end
        local vehicleWidth = AIUtil.getWidth(self.vehicle)
        local siloWidth = heapSilo:getWidth()
        self:debug("Vehicle width: %.2f, silo width: %.2f", vehicleWidth, siloWidth)
        if self.fieldUnloadData.isReverseUnloading then
            --- For reverse unloading the unloader needs to drive parallel to the heap.
            self.fieldUnloadData.xOffset = siloWidth / 2 + 2 * vehicleWidth / 3
        else
            --- Makes sure the x offset for unloading to the side is big enough
            --- to make sure the unloader doesn't touch the heap.
            self.fieldUnloadData.xOffset = math.sign(self.fieldUnloadData.xOffset) *
                    math.max(math.abs(self.fieldUnloadData.xOffset), siloWidth / 2 + 2 * vehicleWidth / 3)
        end

        self:debug("Found a heap for field unloading, reverseUnloading: %s, xOffset: %.2f, silo width: %.2f, vehicle width: %.2f",
                self.fieldUnloadData.isReverseUnloading, self.fieldUnloadData.xOffset, siloWidth, vehicleWidth)
    else
        self:debug("No heap found around the unloading position.")
    end

    --- Callback when the unloading has finished.
    self.fieldUnloadData.controller:setFinishDischargeToGroundCallback(self.onFieldUnloadingFinished)
    self:setNewState(self.states.WAITING_FOR_PATHFINDER)
    local context = PathfinderContext(self.vehicle)
    context:maxFruitPercent(self:getMaxFruitPercent()):offFieldPenalty(PathfinderContext.defaultOffFieldPenalty)
    context:useFieldNum(CpFieldUtil.getFieldNumUnderVehicle(self.vehicle))
    context:allowReverse(self:getAllowReversePathfinding())
    context:maxIterations(PathfinderUtil.getMaxIterationsForFieldPolygon(self.vehicle:cpGetFieldPolygon()))
    self.pathfinderController:registerListeners(self, self.onPathfindingDoneBeforeUnloadingOnField,
            self.onPathfindingFailedToStationaryTarget, self.onPathfindingObstacleAtStart)
    self.pathfinderController:findPathToNode(context, self.fieldUnloadPositionNode,
            -self.fieldUnloadData.xOffset, -AIUtil.getLength(self.vehicle) * 1.3, 3)
end

--- Moves the field unload position to the center front of the heap.
function AIDriveStrategyUnloadCombine:updateFieldPositionByHeapSilo(heapSilo)
    local cx, cz = heapSilo:getFrontCenter()
    setTranslation(self.fieldUnloadPositionNode, cx, 0, cz)
    local dirX, dirZ = heapSilo:getLengthDirection()
    local yRot = MathUtil.getYRotationFromDirection(dirX, dirZ)
    setRotation(self.fieldUnloadPositionNode, 0, yRot, 0)
    --- Move the position a little bit inwards.
    local x, _, z = localToWorld(self.fieldUnloadPositionNode, 0, 0, 3)
    local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z) + 3
    setTranslation(self.fieldUnloadPositionNode, x, y, z)
end

--- Path to the field unloading position was found.
function AIDriveStrategyUnloadCombine:onPathfindingDoneBeforeUnloadingOnField(controller, success, course, goalNodeInvalid)
    if success and self.state == self.states.WAITING_FOR_PATHFINDER then
        self:setNewState(self.states.DRIVE_TO_FIELD_UNLOAD_POSITION)
        --- Append straight alignment segment
        local x, _, z = course:getWaypointPosition(course:getNumberOfWaypoints())
        local _, _, dz = worldToLocal(self.fieldUnloadPositionNode, x, 0, z)
        local zOffset = 0
        if not self.fieldUnloadData.isReverseUnloading then
            --- For Side unloading make sure the discharge node is aligned correctly with the field unload node.
            zOffset = -self.fieldUnloadData.controller:getUnloadOffsetZ(self.fieldUnloadData.dischargeNode)
        end
        course:append(Course.createFromNode(self.vehicle, self.fieldUnloadPositionNode,
                -self.fieldUnloadData.xOffset, dz, zOffset, 3, false))
        self:startCourse(course, 1)
    else
        self:info("Could not find a path to the field unload position!")
        self.vehicle:stopCurrentAIJob(AIMessageCpErrorNoPathFound.new())
    end
end

--- Checks if the silo is clear for unloading and not another unloader is currently unloading there.
function AIDriveStrategyUnloadCombine:waitingUntilFieldUnloadIsAllowed()
    self:setMaxSpeed(0)
    for strategy, unloader in pairs(self.activeUnloaders) do
        if strategy ~= self then
            if strategy:isUnloadingOnTheField(true) then
                if self.fieldUnloadData.heapSilo and self.fieldUnloadData.heapSilo:isOverlappingWith(strategy:getFieldUnloadHeap()) then
                    self:debug("Is waiting for unloader: %s", CpUtil.getName(unloader))
                    return
                end
            end
        end
    end
    self:onFieldUnloadPositionReached()
end

--- Called when the driver reaches the field unloading position.
function AIDriveStrategyUnloadCombine:onFieldUnloadPositionReached()

    --- Re-scan heap, as another unloader might have deformed it
    local found, heapSilo = BunkerSiloManagerUtil.createHeapBunkerSilo(self.vehicle,
            self.fieldUnloadPositionNode, 0, CpAIJobCombineUnloader.maxHeapLength, -10)
    if found and heapSilo then
        self:updateFieldPositionByHeapSilo(heapSilo)
        self.fieldUnloadData.heapSilo = heapSilo
    end

    if self.fieldUnloadData.isReverseUnloading then

        --- Trying to unload at the back of the trailer.
        --- Creating an alignment course to reach the heap end.
        local length = self.fieldUnloadData.heapSilo:getLength() + 5
        local alignmentCourse = Course.createStraightForwardCourse(self.vehicle,
                length, -self.fieldUnloadData.xOffset, self.fieldUnloadPositionNode)

        local _, steeringLength = AIUtil.getSteeringParameters(self.vehicle)
        local alignLength = math.max(self.vehicle.size.length / 2, steeringLength, self.turningRadius / 2) * 3

        local x, _, z = localToWorld(self.fieldUnloadPositionNode, 0, 0, length + alignLength)
        local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z) + 3

        local dirX, _, dirZ = localDirectionToWorld(self.fieldUnloadPositionNode, 0, 0, 1)
        setTranslation(self.fieldUnloadTurnEndNode, x, y, z)
        local yRot = MathUtil.getYRotationFromDirection(dirX, dirZ)
        setRotation(self.fieldUnloadTurnEndNode, 0, yRot, 0)

        x, _, z = localToWorld(self.fieldUnloadPositionNode, -self.fieldUnloadData.xOffset, 0, length)
        y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z) + 3
        setTranslation(self.fieldUnloadTurnStartNode, x, y, z)
        setRotation(self.fieldUnloadTurnStartNode, 0, yRot, 0)

        self:debug("Starting pathfinding to the reverse unload turn end node with align length: %.2f and steering length: %.2f, turn radius: %.2f",
                alignLength, steeringLength, self.turningRadius)
        local path = PathfinderUtil.findAnalyticPath(PathfinderUtil.dubinsSolver, self.fieldUnloadTurnStartNode,
                0, 0, self.fieldUnloadTurnEndNode, 0, 3, self.turningRadius)
        if not path or #path == 0 then
            self:debug("Reverse alignment course creation failed!")
        else
            --- Adds the transition turn segment
            local alignmentTurnSegmentCourse = Course(self.vehicle, CpMathUtil.pointsToGameInPlace(path), true)
            alignmentCourse:append(alignmentTurnSegmentCourse)

            --- Add a small straight segment at the end
            --- to straighten the trailer out.
            alignmentCourse:append(Course.createStraightForwardCourse(self.vehicle,
                    AIUtil.getLength(self.vehicle), 0, self.fieldUnloadTurnEndNode))

            self:setNewState(self.states.DRIVE_TO_REVERSE_FIELD_UNLOAD_POSITION)
            self:startCourse(alignmentCourse, 1)
            self:debug("Starting to drive to the reverse unloading position for field unload.")
            return
        end
    end

    self:setNewState(self.states.PREPARE_FOR_FIELD_UNLOAD)
    self:debug("Field unload position reached and start preparing for unload.")
end

--- Driver is in front of the heap and ready to drive backwards to the heap end now.
function AIDriveStrategyUnloadCombine:onReverseFieldUnloadPositionReached()
    local course = Course.createFromNodeToNode(self.vehicle,
            self.vehicle:getAIDirectionNode(), self.fieldUnloadPositionNode,
            0, 0, 5, 3, true)
    self:setNewState(self.states.REVERSING_TO_THE_FIELD_UNLOAD_HEAP)
    self:startCourse(course, 1)
end

--- Reverse driving to the heap.
function AIDriveStrategyUnloadCombine:driveToReverseFieldUnloadHeap()
    --- Checks if the heap end was reached.
    local node = self.fieldUnloadData.dischargeNode.node
    if self.fieldUnloadData.heapSilo:isNodeInSilo(node) then
        self:onReverseFieldUnloadHeapReached()
    end
end

function AIDriveStrategyUnloadCombine:onReverseFieldUnloadHeapReached()
    self:setNewState(self.states.PREPARE_FOR_FIELD_UNLOAD)
    self:debug("Reverse field unload position reached and start preparing for unload.")
end

--- Prepares the auger wagon/trailer for unloading.
--- Waits for the pipe of the auger wagon to unfold.
--- After that unload and use a straight forward course.
function AIDriveStrategyUnloadCombine:prepareForFieldUnload()
    self:setMaxSpeed(0)
    if self.fieldUnloadData.controller:prepareForUnload(true) then
        self:debug("Finished preparing for unloading.")
        self:setNewState(self.states.UNLOADING_ON_THE_FIELD)

        if not self.fieldUnloadData.controller:startDischargeToGround(self.fieldUnloadData.dischargeNode) then
            self:info("Could not start discharge to ground!")
            self.vehicle:stopCurrentAIJob(AIMessageErrorGroundUnloadNotSupported.new())
            return
        end

        --- For now we create a simple straight forward course to unload.
        local xOffset = self.fieldUnloadData.isReverseUnloading and 0 or -self.fieldUnloadData.xOffset
        local length = self.unloadCourseLengthFieldUnload
        if self.fieldUnloadData.heapSilo and not self.fieldUnloadData.isReverseUnloading then
            length = length + self.fieldUnloadData.heapSilo:getLength()
        end
        local unloadCourse = Course.createStraightForwardCourse(self.vehicle, length, xOffset, self.fieldUnloadPositionNode)
        self:startCourse(unloadCourse, 1)
        self:debug("Started unload course with a length of %d and offset of %.2f", length, xOffset)
    end
end

------------------------------------------------------------------------------------------------------------------------
--- Finished unloading and search for a park course that is on the opposite xOffset from the heap.
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:onFieldUnloadingFinished()
    local x, _, z = localToWorld(self.fieldUnloadPositionNode, 0, 0, 0)
    setTranslation(self.fieldUnloadTurnEndNode, x, 0, z)
    local dirX, _, dirZ = localDirectionToWorld(self.fieldUnloadPositionNode, 0, 0, 1)
    local rotY = MathUtil.getYRotationFromDirection(dirX, dirZ)
    setRotation(self.fieldUnloadTurnEndNode, 0, rotY + math.pi, 0)

    if not self.fieldUnloadData.heapSilo then
        --- Set the valid heap, when trying to drive to the park position
        --- after creating the heap for the first time.
        --- This makes sure that the park position doesn't cross the heap.
        local found, heapSilo = BunkerSiloManagerUtil.createHeapBunkerSilo(self.vehicle,
                self.fieldUnloadPositionNode, 0, CpAIJobCombineUnloader.maxHeapLength, -2)

        if found and heapSilo then
            self:updateFieldPositionByHeapSilo(heapSilo)
            local vehicleWidth = AIUtil.getWidth(self.vehicle)
            local siloWidth = heapSilo:getWidth()
            self:debug("Vehicle width: %.2f, silo width: %.2f", vehicleWidth, siloWidth)
            if self.fieldUnloadData.xOffset == 0 then
                --- First time park position for reverse unload offset always on the left of the heap.
                self.fieldUnloadData.xOffset = siloWidth / 2 + 2 * vehicleWidth / 3
            else
                self.fieldUnloadData.xOffset = math.sign(self.fieldUnloadData.xOffset) *
                        math.max(math.abs(self.fieldUnloadData.xOffset), siloWidth / 2 + 2 * vehicleWidth / 3)
            end
            self:debug("Found a heap for field unloading park position xOffset: %.2f", self.fieldUnloadData.xOffset)
        end
    end

    self:setNewState(self.states.WAITING_FOR_PATHFINDER)
    self:debug("Disabling off-field penalty for driving to the park position.")
    local context = PathfinderContext(self.vehicle)
    context:maxFruitPercent(self:getMaxFruitPercent()):offFieldPenalty(0)
    context:useFieldNum(CpFieldUtil.getFieldNumUnderVehicle(self.vehicle))
    context:allowReverse(self:getAllowReversePathfinding())
    context:maxIterations(PathfinderUtil.getMaxIterationsForFieldPolygon(self.vehicle:cpGetFieldPolygon()))
    self.pathfinderController:registerListeners(self, self.onPathfindingDoneBeforeDrivingToFieldUnloadParkPosition,
            self.onPathfindingFailedToStationaryTarget, self.onPathfindingObstacleAtStart)
    self.pathfinderController:findPathToNode(context, self.fieldUnloadTurnEndNode,
            -self.fieldUnloadData.xOffset * 1.5, -AIUtil.getLength(self.vehicle), 3)
end

--- Course to the park position found.
function AIDriveStrategyUnloadCombine:onPathfindingDoneBeforeDrivingToFieldUnloadParkPosition(controller, success, course, goalNodeInvalid)
    if success and self.state == self.states.WAITING_FOR_PATHFINDER then
        self:setNewState(self.states.DRIVE_TO_FIELD_UNLOAD_PARK_POSITION)
        --- Append straight alignment segment
        local x, _, z = course:getWaypointPosition(course:getNumberOfWaypoints())
        local _, _, dz = worldToLocal(self.fieldUnloadTurnEndNode, x, 0, z)
        course:append(Course.createFromNode(self.vehicle, self.fieldUnloadTurnEndNode,
                -self.fieldUnloadData.xOffset * 1.5, dz, 0, 1, false))
        self:startCourse(course, 1)
    else
        self:debug("No path to the field unload park position found!")
        self:startWaitingForSomethingToDo()
        self.fieldUnloadData = nil
        return false
    end
end

function AIDriveStrategyUnloadCombine:onFieldUnloadParkPositionReached()
    self:debug("Field unload finished and park position reached.")
    self:startWaitingForSomethingToDo()
    self.fieldUnloadData = nil
end

function AIDriveStrategyUnloadCombine:isPositionOk()
    local x, z = self.jobParameters.startPosition:getPosition()
    local angle = self.jobParameters.startPosition:getAngle()
    if x ~= nil and z ~= nil and angle ~= nil then
        --- Additional safety check, if the position is on the field or near it.
        if CpMathUtil.isPointInPolygon(self.vehicle:cpGetFieldPolygon(), x, z)
                or CpMathUtil.isWithinDistanceToPolygon(self.vehicle:cpGetFieldPolygon(), x, z,
                2 * CpAIJobCombineUnloader.minStartDistanceToField) then
            --- Goal position marker set in the ai menu rotated by 180 degree.
            self.invertedStartPositionMarkerNode = CpUtil.createNode("Inverted Start position marker",
                    x, z, angle + math.pi)
            self:debug("Valid goal position marker was set.")
        else
            self:debug("Start position is too far away from the field for a valid goal position!")
        end
    else
        self:debug("Invalid start position found!")
    end
    -- TODO Looks like we are making these checks but pretty much ignore the result other than some debug outputs.
    return true
end


------------------------------------------------------------------------------------------------------------------------
-- Debug
------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyUnloadCombine:debug(...)
    local combineName = self.combineToUnload and (' -> ' .. CpUtil.getName(self.combineToUnload)) or '(unassigned)'
    CpUtil.debugVehicle(self.debugChannel, self.vehicle, combineName .. ' ' .. self:getStateAsString() .. ': ' .. string.format(...))
end

function AIDriveStrategyUnloadCombine:update(dt)
    AIDriveStrategyCourse.update(self)
    if CpUtil.isVehicleDebugActive(self.vehicle) and CpDebug:isChannelActive(self.debugChannel) then
        if self.course then
            self.course:draw()
        end
        if self.selfUnloadTargetNode then
            DebugUtil.drawDebugNode(self.selfUnloadTargetNode, 'Target')
        end
        if self.fieldUnloadData then
            --- Only draw the field unload data, when the field unload is active.
            if self.fieldUnloadPositionNode then
                CpUtil.drawDebugNode(self.fieldUnloadPositionNode, false, 3)
            end
            if self.fieldUnloadTurnEndNode then
                CpUtil.drawDebugNode(self.fieldUnloadTurnEndNode, false, 1)
            end
            if self.fieldUnloadTurnStartNode then
                CpUtil.drawDebugNode(self.fieldUnloadTurnStartNode, false, 1)
            end
            if self.fieldUnloadData.heapSilo then
                self.fieldUnloadData.heapSilo:drawDebug()
            end
        end
        if self.state == self.states.DRIVING_BACK_TO_START_POSITION_WHEN_FULL and self.invertedStartPositionMarkerNode then
            CpUtil.drawDebugNode(self.invertedStartPositionMarkerNode, true, 3);
        end
        for i, nodeData in pairs(self.trailerNodes) do
            CpUtil.drawDebugNode(nodeData.node, false,
                    0, string.format("%s -> Fill node %d",
                            CpUtil.getName(nodeData.trailer), i))
        end
    end
    self:updateImplementControllers(dt)
end

function AIDriveStrategyUnloadCombine:renderText(x, y, ...)

    if not CpUtil.isVehicleDebugActive(self.vehicle) or not CpDebug:isChannelActive(self.debugChannel) then
        return
    end

    renderText(0.6 + x, 0.2 + y, 0.018, string.format(...))
end

---@param names table list of names for the debug table
---@param values table corresponding values
function AIDriveStrategyUnloadCombine:renderDebugTableFromLists(names, values)
    local content = {}
    for i, value in ipairs(values) do
        if type(value) == 'number' then
            table.insert(content, { name = names[i], value = string.format('%.1f', value) })
        else
            table.insert(content, { name = names[i], value = tostring(value) })
        end
    end
    self:renderDebugTable(content)
end

---@param content table with a list of {name, value} tables
function AIDriveStrategyUnloadCombine:renderDebugTable(content)
    if CpUtil.isVehicleDebugActive(self.vehicle) and CpDebug:isChannelActive(self.debugChannel) then
        local t = {
            title = self:getStateAsString(),
            content = content
        }
        CpDebug:drawVehicleDebugTable(self.vehicle, { t }, 5, 0.07)
    end
end



--FillUnit.updateFillUnitAutoAimTarget = Utils.overwrittenFunction(FillUnit.updateFillUnitAutoAimTarget, AIDriveStrategyUnloadCombine.updateFillUnitAutoAimTarget)
