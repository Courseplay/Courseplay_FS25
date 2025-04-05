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

Base class for all Courseplay drive strategies

]]

---@class AIDriveStrategyCourse
AIDriveStrategyCourse = CpObject()

AIDriveStrategyCourse.myStates = {
    INITIAL = {},
    WAITING_FOR_PATHFINDER = {},
    WAITING_FOR_FIELD_BOUNDARY_DETECTION = {},
}

--- Implement controller events.
--- TODO_25 a more generic implementation
AIDriveStrategyCourse.onRaisingEvent = "onRaising"
AIDriveStrategyCourse.onLoweringEvent = "onLowering"
AIDriveStrategyCourse.onFinishedEvent = "onFinished"
AIDriveStrategyCourse.onStartEvent = "onStart"
AIDriveStrategyCourse.onStartRefillingEvent = "onStartRefilling"
AIDriveStrategyCourse.onStopRefillingEvent = "onStopRefilling"
AIDriveStrategyCourse.onUpdateRefillingEvent = "onUpdateRefilling"
AIDriveStrategyCourse.updateEvent = "update"
AIDriveStrategyCourse.deleteEvent = "delete"
--- A row has just been finished, implements are being raised and about to start the actual turn
AIDriveStrategyCourse.onFinishRowEvent = "onFinishRow"
--- The actual turn is done, now we are starting into the row and will lower the implements when
--- they reach the start of the row
AIDriveStrategyCourse.onTurnEndProgressEvent = "onTurnEndProgress"

---@param task CpAITask
---@param job CpAIJob
function AIDriveStrategyCourse:init(task, job)
    self.debugChannel = CpDebug.DBG_AI_DRIVER
    self:initStates(AIDriveStrategyCourse.myStates)
    ---@type ImplementController[]
    self.controllers = {}
    self.registeredInfoTexts = {}
    --- To temporary hold a vehicle (will force speed to 0)
    self.held = CpTemporaryObject()
    self.fuelSaveActiveWhileHeld = false

    self.currentTask = task
    self.job = job
end

function AIDriveStrategyCourse:setCurrentTaskFinished()
    self.currentTask:skip()
end

--- Aggregation of states from this and all descendant classes
function AIDriveStrategyCourse:initStates(newStates)
    self.states = CpUtil.initStates(self.states, newStates)
end

function AIDriveStrategyCourse:getStateAsString()
    return self.state.name
end

function AIDriveStrategyCourse:getName()
    return CpUtil.getName(self.vehicle)
end

function AIDriveStrategyCourse:debug(...)
    CpUtil.debugVehicle(self.debugChannel, self.vehicle, self:getStateAsString() .. ': ' .. string.format(...))
end

function AIDriveStrategyCourse:debugSparse(...)
    local nowSecs = math.floor(g_time / 1000)
    -- report every 5 seconds
    -- TODO: make this a parameter in seconds?
    if not self.lastLogSecs or (nowSecs > self.lastLogSecs and nowSecs % 5 == 0) then
        self:debug(...)
        self.lastLogSecs = nowSecs
    end
end

function AIDriveStrategyCourse:info(...)
    CpUtil.infoVehicle(self.vehicle, self:getStateAsString() .. ': ' .. string.format(...))
end

function AIDriveStrategyCourse:error(...)
    CpUtil.infoVehicle(self.vehicle, self:getStateAsString() .. ': ' .. string.format(...))
end

--- Sets an info text
---@param text CpInfoTextElement
function AIDriveStrategyCourse:setInfoText(text)
    self.vehicle:setCpInfoTextActive(text)
end

--- @param text CpInfoTextElement
function AIDriveStrategyCourse:clearInfoText(text)
    if text then
        self.vehicle:resetCpActiveInfoText(text)
    end
end

function AIDriveStrategyCourse:setAIVehicle(vehicle, jobParameters)
    self.vehicle = vehicle
    --self:fixTurnOnEvent()
    self.jobParameters = jobParameters
    self:initializeImplementControllers(vehicle)
    self.ppc = PurePursuitController(vehicle)
    self.ppc:registerListeners(self, 'onWaypointPassed', 'onWaypointChange')

    self.storage = vehicle.spec_cpAIWorker

    self.settings = vehicle:getCpSettings()
    self.courseGeneratorSettings = vehicle:getCourseGeneratorSettings()

    -- for now, pathfinding generated courses can't be driven by towed tools
    self.allowReversePathfinding = AIUtil.getFirstReversingImplementWithWheels(self.vehicle) == nil
    self.turningRadius = AIUtil.getTurningRadius(vehicle)

    self.pathfinderController = PathfinderController(vehicle, self.turningRadius)
    self.pathfinderController:registerListeners(self, self.onPathfindingFinished, self.onPathfindingFailed)

    self:setAllStaticParameters()

    -- TODO: this may or may not be the course we need for the strategy
    local course = self:isGeneratedCourseNeeded() and self:getGeneratedCourse(jobParameters)
    if course then
        self:debug('Vehicle has a fieldwork course, figure out where to start')
        if course:wasEditedByCourseEditor() then
            self:info('The fieldwork course was edited by the course editor.')
        end
        local startIx = self:getStartingPointWaypointIx(course, jobParameters.startAt:getValue())
        self:start(course, startIx, jobParameters)
    else
        -- some strategies do not need a recorded or generated course to work, they
        -- will create the courses on the fly.
        self:debug('Vehicle has no course, start work without it.')
        self:startWithoutCourse(jobParameters)
    end
    self:raiseControllerEvent(self.onStartEvent)
end

function AIDriveStrategyCourse:fixTurnOnEvent()
    for _, action in ipairs(self.vehicle.actionController.actions) do
        for _, listener in ipairs(action.aiEventListener) do
            if listener.eventName == 'onAIImplementStart' then
                listener.direction = 1
            end
        end
    end
end

--- Does the strategy need the current assigned course?
function AIDriveStrategyCourse:isGeneratedCourseNeeded()
    return true
end

function AIDriveStrategyCourse:delete()
    self:raiseControllerEvent(self.deleteEvent)
end

function AIDriveStrategyCourse:getGeneratedCourse(jobParameters)
    return self.vehicle:getFieldWorkCourse()
end

function AIDriveStrategyCourse:getStartingPointWaypointIx(course, startAt)
    if startAt == CpFieldWorkJobParameters.START_AT_NEAREST_POINT then
        local _, _, ixClosestRightDirection, _ = course:getNearestWaypoints(self.vehicle:getAIDirectionNode())
        self:debug('Starting course at the closest waypoint in the right direction %d', ixClosestRightDirection)
        return ixClosestRightDirection
    elseif startAt == CpFieldWorkJobParameters.START_AT_LAST_POINT then
        local lastWpIx = self.vehicle:getCpLastRememberedWaypointIx()
        if lastWpIx then
            self:debug('Starting course at the last waypoint %d', lastWpIx)
            return lastWpIx
        end
    end
    self:debug('Starting course at the first waypoint')
    return 1
end

function AIDriveStrategyCourse:start(course, startIx, jobParameters)
    self:startCourse(course, startIx)
    self.state = self.states.INITIAL
end

function AIDriveStrategyCourse:startWithoutCourse(jobParameters)
end

function AIDriveStrategyCourse:updateCpStatus(status)
    --- override
end

-----------------------------------------------------------------------------------------------------------------------
--- Implement handling
-----------------------------------------------------------------------------------------------------------------------
--- Adds implement controllers for every implement, that has the given specialization.
---@param vehicle table
---@param class ImplementController
---@param spec table|nil
---@param states table|nil
---@param specReference string|nil
---@return table last implement found.
---@return table last implement controller
function AIDriveStrategyCourse:addImplementController(vehicle, class, spec, states, specReference)
    --- If multiple implements have this spec, then add a controller for each implement.
    local lastImplement, lastController
    for _, childVehicle in pairs(AIUtil.getAllChildVehiclesWithSpecialization(vehicle, spec, specReference)) do
        local controller = class(vehicle, childVehicle)
        self:appendImplementController(controller, states)
        lastImplement, lastController = childVehicle, controller
    end
    return lastImplement, lastController
end

--- Appends an implement controller
---@param controller ImplementController
---@param disabledStates table|nil
function AIDriveStrategyCourse:appendImplementController(controller, disabledStates)
    if disabledStates then
        controller:setDisabledStates(disabledStates)
    end
    controller:setDriveStrategy(self)
    table.insert(self.controllers, controller)
end

--- Gets all registered implement controller of a given type.
---@param controllerClass ImplementController
---@return boolean found?
---@return table all found implement controllers
function AIDriveStrategyCourse:getRegisteredImplementControllersByClass(controllerClass)
    local foundControllers = {}
    for _, controller in pairs(self.controllers) do
        if controller:is_a(controllerClass) then
            table.insert(foundControllers, controller)
        end
    end
    return #foundControllers > 0, foundControllers
end

--- Gets the first found registered implement controller and it's implement.
---@param controllerClass ImplementController
---@return ImplementController|nil found implement controller
---@return table|nil found implement
function AIDriveStrategyCourse:getFirstRegisteredImplementControllerByClass(controllerClass)
    local found, controllers = self:getRegisteredImplementControllersByClass(controllerClass)
    if found then
        return controllers[1], controllers[1]:getImplement()
    end
end

--- Checks if any controller disables fuel save, for example a round baler that is dropping a bale.
function AIDriveStrategyCourse:isFuelSaveAllowed()
    return self.fuelSaveActiveWhileHeld and self:isBeingHeld()
end

function AIDriveStrategyCourse:initializeImplementControllers(vehicle)
    --- override
end

--- Normal update function called every frame.
--- For releasing the helper in the controller, use this one.
function AIDriveStrategyCourse:updateImplementControllers(dt)
    self:raiseControllerEvent(self.updateEvent, dt)
end

--- Called in the low frequency function for the helper.
function AIDriveStrategyCourse:updateLowFrequencyImplementControllers()
    for _, controller in pairs(self.controllers) do
        ---@type ImplementController
        if controller:isEnabled() then
            -- we don't know yet if we even need anything from the controller other than the speed.
            local _, _, _, maxSpeed = controller:getDriveData()
            if maxSpeed then
                self:setMaxSpeed(maxSpeed)
            end
        end
    end
end

function AIDriveStrategyCourse:updateLowFrequencyPathfinder()
    local _, _, _, maxSpeed = self.pathfinderController:getDriveData()
    if maxSpeed then
        self:setMaxSpeed(maxSpeed)
    end
end

--- Raises a event for the controllers.
function AIDriveStrategyCourse:raiseControllerEvent(eventName, ...)
    self:raiseControllerEventWithLambda(eventName, function () end, ...)
end

function AIDriveStrategyCourse:raiseControllerEventWithLambda(eventName, lambda, ...)
    for _, controller in pairs(self.controllers) do
        ---@type ImplementController
        if controller:isEnabled() then
            if controller[eventName] then
                lambda(controller[eventName](controller, ...))
            end
        end
    end
end

function AIDriveStrategyCourse:raiseImplements()
    --- Raises all implements, that are available for the giants field worker.
    for _, implement in pairs(self.vehicle:getAttachedAIImplements()) do
        implement.object:aiImplementEndLine()
    end
    self.vehicle:raiseStateChange(VehicleStateChange.AI_END_LINE)
    --- Raises implements, that are not covered by giants.
    self:raiseControllerEvent(self.onRaisingEvent)
end

function AIDriveStrategyCourse:lowerImplements()
    self:debug('Lowering all implements')
    --- Lowers all implements, that are available for the giants field worker.
    for _, implement in pairs(self.vehicle:getAttachedAIImplements()) do
        CpUtil.debugImplement(CpDebug.DBG_IMPLEMENTS, implement.object,'Lowering implement')
        implement.object:aiImplementStartLine()
    end
    self.vehicle:raiseStateChange(VehicleStateChange.AI_START_LINE)
    --- Lowers implements, that are not covered by giants.
    self:raiseControllerEvent(self.onLoweringEvent)
end

--- Can the ai worker continue working?
---@return boolean
function AIDriveStrategyCourse:getCanContinueWork()
    --- Not every implement, for example balers or bale wrapper are handled by the giants function.
    for _, controller in pairs(self.controllers) do
        ---@type ImplementController
        if not controller:canContinueWork() then
            return false
        end
    end
    return self.vehicle:getCanAIFieldWorkerContinueWork()
end

-----------------------------------------------------------------------------------------------------------------------
--- Static parameters (won't change while driving)
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyCourse:setAllStaticParameters()
    self.workWidth = self.vehicle:getCourseGeneratorSettings().workWidth:getValue()
    self.reverser = AIReverseDriver(self.vehicle, self.ppc)
    self.proximityController = ProximityController(self.vehicle, self:getProximitySensorWidth())
    self.proximityController:registerIgnoreObjectCallback(self, self.ignoreBaleInFrontWithBalePusher)
    -- let all controllers register an ignore object callback if they want
    for _, controller in pairs(self.controllers) do
        controller:registerIgnoreProximityObjectCallback(self.proximityController)
    end
end

--- Find the foremost and rearmost AI marker
function AIDriveStrategyCourse:setFrontAndBackMarkers()
    local markers = {}
    local addMarkers = function(object, referenceNode)
        self:debug('Finding AI markers of %s', CpUtil.getName(object))
        local aiLeftMarker, aiRightMarker, aiBackMarker = WorkWidthUtil.getAIMarkers(object)
        if aiLeftMarker and aiBackMarker and aiRightMarker then
            local leftMarkerDistance = ImplementUtil.getDistanceToImplementNode(referenceNode, object, aiLeftMarker)
            local rightMarkerDistance = ImplementUtil.getDistanceToImplementNode(referenceNode, object, aiRightMarker)
            local backMarkerDistance = ImplementUtil.getDistanceToImplementNode(referenceNode, object, aiBackMarker)
            table.insert(markers, leftMarkerDistance)
            table.insert(markers, rightMarkerDistance)
            table.insert(markers, backMarkerDistance)
            self:debug('%s: left = %.1f, right = %.1f, back = %.1f', CpUtil.getName(object), leftMarkerDistance, rightMarkerDistance, backMarkerDistance)
        end
    end

    local referenceNode = self.vehicle:getAIDirectionNode()
    -- now go ahead and try to find the real markers
    -- work areas of the vehicle itself
    addMarkers(self.vehicle, referenceNode)
    -- and then the work areas of all the implements
    for _, implement in pairs(AIUtil.getAllAIImplements(self.vehicle)) do
        addMarkers(implement.object, referenceNode)
    end

    if #markers == 0 then
        -- make sure we always have a default front/back marker, placed on the direction node if nothing else found
        table.insert(markers, 0)
        table.insert(markers, 3)
    end
    -- now that we have all, find the foremost and the last
    self.frontMarkerDistance, self.backMarkerDistance = 0, 0
    local frontMarkerDistance, backMarkerDistance = -math.huge, math.huge
    for _, d in pairs(markers) do
        if d > frontMarkerDistance then
            frontMarkerDistance = d
        end
        if d < backMarkerDistance then
            backMarkerDistance = d
        end
    end
    self.frontMarkerDistance = frontMarkerDistance
    self.backMarkerDistance = backMarkerDistance
    self:debug('front marker: %.1f, back marker: %.1f', frontMarkerDistance, backMarkerDistance)
end

--- Gets the front and back marker offset relative to the direction node. These markers define the front
--- and the back of the work area. When negative, they are behind the direction node, when positive, in front of it.
---@return number distance of the foremost work area from the direction node, negative when behind the direction node
---@return number distance of the rearmost work area from the direction node, negative when behind the direction node
function AIDriveStrategyCourse:getFrontAndBackMarkers()
    if not self.frontMarkerDistance then
        self:setFrontAndBackMarkers()
    end
    return self.frontMarkerDistance, self.backMarkerDistance
end

function AIDriveStrategyCourse:getWorkWidth()
    return self.workWidth
end

--- Get the currently active course (temporary or not)
function AIDriveStrategyCourse:getCurrentCourse()
    return self.ppc:getCourse() or self.course
end

function AIDriveStrategyCourse:update(dt)
    self.ppc:update()
    self.pathfinderController:update(dt)
    self:updatePathfinding()
    self:updateInfoTexts()
end


function AIDriveStrategyCourse:getDriveData(dt, vX, vY, vZ)
    local moveForwards = not self.ppc:isReversing()
    local gx, _, gz = self.ppc:getGoalPointPosition()
    return gx, gz, moveForwards, self.maxSpeed, 100
end

function AIDriveStrategyCourse:getReverseDriveData()
    local gx, gz, _, maxSpeed = self.reverser:getDriveData()
    if not gx then
        -- simple reverse (not towing anything), just use PPC
        gx, _, gz = self.ppc:getGoalPointPosition()
        maxSpeed = self.settings.reverseSpeed:getValue()
    end
    return gx, gz, maxSpeed
end

-----------------------------------------------------------------------------------------------------------------------
--- Proximity
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyCourse:getProximitySensorWidth()
    -- a bit less as size.width always has plenty of buffer
    return self.vehicle.size.width - 0.5
end

function AIDriveStrategyCourse:checkProximitySensors(moveForwards)
    local _, _, _, maxSpeed = self.proximityController:getDriveData(self:getMaxSpeed(), moveForwards)
    self:setMaxSpeed(maxSpeed)
end

--- Is vehicle close to the front or rear proximity sensors?
---@param vehicle table
---@return boolean, number true if vehicle is in proximity, distance of vehicle
function AIDriveStrategyCourse:isVehicleInProximity(vehicle)
    return self.proximityController:isVehicleInRange(vehicle)
end

--- Ignoring bales in front when configured, bales back when not yet dropped from the baler
function AIDriveStrategyCourse:ignoreBaleInFrontWithBalePusher(object, vehicle, moveForwards)
    if not object then
        return
    end
    if object.isa and object:isa(Bale) and object.nodeId and entityExists(object.nodeId) then
        -- this is a bale
        if moveForwards and g_vehicleConfigurations:getRecursively(self.vehicle, 'ignoreBaleCollisionForward') then
            -- when configured, ignore bales in front, for instance using a bale pusher
            self:debugSparse('ignoring forward collision with bale')
            return true
        end
    end
    return false
end

-----------------------------------------------------------------------------------------------------------------------
--- Speed control
-----------------------------------------------------------------------------------------------------------------------
--- Set the maximum speed. The idea is that self.maxSpeed is reset at the beginning of every loop and
-- every function calls setMaxSpeed() and the speed will be set to the minimum
-- speed set in this loop.
function AIDriveStrategyCourse:setMaxSpeed(speed)
    if self.maxSpeedUpdatedLoopIndex == nil or self.maxSpeedUpdatedLoopIndex ~= g_updateLoopIndex then
        -- new loop, reset max speed. Always 0 if frozen
        self.maxSpeed = (self.frozen or self:isBeingHeld()) and 0 or self.vehicle:getSpeedLimit(true)
        self.maxSpeedUpdatedLoopIndex = g_updateLoopIndex
    end
    self.maxSpeed = math.min(self.maxSpeed, speed)
end

function AIDriveStrategyCourse:getMaxSpeed()
    return self.maxSpeed or self.vehicle:getSpeedLimit(true)
end

--- Hold the vehicle (set speed to 0) temporary. This is meant to be used for other vehicles to coordinate movements,
--- for instance tell a vehicle it should not move as the other vehicle is driving around it.
---@param milliseconds number milliseconds to hold
---@param fuelSaveAllowed boolean enables the fuel save, while the vehicle is being held.
function AIDriveStrategyCourse:hold(milliseconds, fuelSaveAllowed)
    if not self.held:get() then
        self:debug('Hold requested for %.1f seconds', milliseconds / 1000)
    end
    self.held:set(true, milliseconds)
    self.fuelSaveActiveWhileHeld = fuelSaveAllowed
end

--- Release a hold anytime, even before it is released automatically after the time given at hold()
function AIDriveStrategyCourse:unhold()
    if self.held:get() then
        self:debug("Hold reset")
    end
    self.held:reset()
    self.fuelSaveActiveWhileHeld = false
end

--- Are we currently being held?
function AIDriveStrategyCourse:isBeingHeld()
    return self.held:get()
end

--- Freeze (force speed to 0), but keep everything up and running otherwise, showing all debug
--- drawings, etc. This is for troubleshooting only. Unlike pausing the game, this still calls update() and
--- getDriveData() so all debug drawings remain visible during the freeze.
function AIDriveStrategyCourse:freeze()
    self.frozen = true
end

function AIDriveStrategyCourse:unfreeze()
    self.frozen = false
end

--- Slow down a bit towards the end of course or near direction changes, and later maybe where the turn radius is
--- small, unless we are reversing, as then (hopefully) we already have a slow speed set
function AIDriveStrategyCourse:limitSpeed()
    if self.maxSpeed > self.settings.turnSpeed:getValue() and
            not self.ppc:isReversing() and
            (self.ppc:getCourse():isCloseToLastWaypoint(15) or
                    self.ppc:getCourse():isCloseToNextDirectionChange(15)) then

        local maxSpeed = self.maxSpeed
        self:setMaxSpeed(self.settings.turnSpeed:getValue())
        self:debugSparse('speed %.1f limited to turn speed %.1f', maxSpeed, self.maxSpeed)
    else
        self:debugSparse('speed %.1f', self.maxSpeed)
    end
end

--- Start a course at waypoint ix
---@param course Course
---@param ix number
function AIDriveStrategyCourse:startCourse(course, ix)
    self:debug('Starting a course, at waypoint %d (of %d).', ix, course:getNumberOfWaypoints())
    self.course = course
    self.ppc:setCourse(self.course)
    self.ppc:initialize(ix)
end

function AIDriveStrategyCourse:getFillLevelInfoText()
    return InfoTextManager.NEEDS_UNLOADING
end

-----------------------------------------------------------------------------------------------------------------------
--- Event listeners
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyCourse:onWaypointChange(ix, course)
end

function AIDriveStrategyCourse:onWaypointPassed(ix, course)
end

--- Pathfinding has finished
---@param controller PathfinderController
---@param success boolean
---@param course Course|nil
---@param goalNodeInvalid boolean|nil
function AIDriveStrategyCourse:onPathfindingFinished(controller, success, course, goalNodeInvalid)
    -- override
end

--- Pathfinding failed, but a retry attempt is leftover.
---@param controller PathfinderController
---@param lastContext PathfinderContext
---@param wasLastRetry boolean
---@param currentRetryAttempt number
function AIDriveStrategyCourse:onPathfindingFailed(controller, lastContext, wasLastRetry, currentRetryAttempt)
    -- override
end

------------------------------------------------------------------------------------------------------------------------
--- Pathfinding
---------------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyCourse:getAllowReversePathfinding()
    return self.allowReversePathfinding and self.settings.allowReversePathfinding:getValue()
end

function AIDriveStrategyCourse:setPathfindingDoneCallback(object, func)
    self.pathfindingDoneObject = object
    self.pathfindingDoneCallbackFunc = func
end

function AIDriveStrategyCourse:updatePathfinding()
    if self.pathfinder and self.pathfinder:isActive() then
        self:setMaxSpeed(0)
        local result = self.pathfinder:resume()
        if result.done then
            self.pathfindingDoneCallbackFunc(self.pathfindingDoneObject, result.path)
        end
    end
end

--- Create an alignment course between the current vehicle position and waypoint endIx of the course
---@param course Course the course to start
---@param ix number the waypoint where start the course
function AIDriveStrategyCourse:createAlignmentCourse(course, ix)
    self:debug('Generate alignment course to waypoint %d', ix)
    local alignmentCourse = AlignmentCourse(self.vehicle, self.vehicle:getAIDirectionNode(), self.turningRadius,
            course, ix, math.min(-self.frontMarkerDistance, -1)):getCourse()
    return alignmentCourse
end

-- remember a course to start
function AIDriveStrategyCourse:rememberCourse(course, ix)
    self.rememberedCourse = course
    self.rememberedCourseStartIx = ix
end

-- start a remembered course
function AIDriveStrategyCourse:startRememberedCourse()
    self:startCourse(self.rememberedCourse, self.rememberedCourseStartIx)
end

function AIDriveStrategyCourse:getRememberedCourseAndIx()
    return self.rememberedCourse, self.rememberedCourseStartIx
end

------------------------------------------------------------------------------------------------------------------------
--- Course helpers
---------------------------------------------------------------------------------------------------------------------------

--- Are we within distance meters of the last waypoint (measured on the course, not direct path)?
function AIDriveStrategyCourse:isCloseToCourseEnd(distance)
    return self.course:getDistanceToLastWaypoint(self.ppc:getCurrentWaypointIx()) < distance
end

--- Are we within distance meters of the first waypoint (measured on the course, not direct path)?
function AIDriveStrategyCourse:isCloseToCourseStart(distance)
    return self.course:getDistanceFromFirstWaypoint(self.ppc:getCurrentWaypointIx()) < distance
end

--- Event raised when the driver was stopped.
---@param hasFinished boolean|nil flag passed by the info text
function AIDriveStrategyCourse:onFinished(hasFinished)
    self:raiseControllerEvent(self.onFinishedEvent, hasFinished)
    if hasFinished and self.settings.foldImplementAtEnd:getValue() then
        --- Folds implements at the end if the setting is active.
        self:debug("Finished with folding implements of the implements.")
        self.vehicle:prepareForAIDriving()
    end
end

--- This is to set the offsets on the course at start, or update those values
--- if the user changed them during the run or the AI driver wants to add an offset
function AIDriveStrategyCourse:updateCourseOffset(course)
    course:setOffset(self.settings.toolOffsetX:getValue() + (self.aiOffsetX or 0) + (self.tightTurnOffset or 0),
            (self.aiOffsetZ or 0))
end

------------------------------------------------------------------------------------------------------------------------
--- Info texts
---------------------------------------------------------------------------------------------------------------------------

--- Registers info texts for specific states.
---@param infoText CpInfoTextElement
---@param states table
function AIDriveStrategyCourse:registerInfoTextForStates(infoText, states)
    if self.registeredInfoTexts[infoText] == nil then
        self.registeredInfoTexts[infoText] = states
    end
end

--- Enables/disables based on the state.
function AIDriveStrategyCourse:updateInfoTexts()
    for infoText, states in pairs(self.registeredInfoTexts) do
        if states[self.state] then
            self:setInfoText(infoText)
        else
            self:clearInfoText(infoText)
        end
    end
end

------------------------------------------------------------------------------------------------------------------------
--- Field boundary detection
---------------------------------------------------------------------------------------------------------------------------
--- Some strategies need to know the field boundaries. Bale finder must search for bales on the field, combine
--- unload will look for harvesters on the field, self-unload will look for trailers around the field. When
--- these strategies are started directly from the HUD or by a shortcut, they won't necessarily have a the
--- field boundary yet, as detection is an asynchronous process. Once the detection is done, the field polygon is
--- available in the CpCourseGenerator specialization by calling cpGetFieldPolygon().
---
--- Strategies that need the boundary should set the state WAITING_FOR_FIELD_BOUNDARY_DETECTION and call this on
--- until it returns true and only then transition to the INITIAL state.
---
---@return boolean true if the field boundary is already available
function AIDriveStrategyCourse:waitForFieldBoundary()
    if self.vehicle:cpGetFieldPolygon() then
        self:clearInfoText(InfoTextManager.WAITING_FOR_FIELD_BOUNDARY_DETECTION)
        return true
    else
        self:setInfoText(InfoTextManager.WAITING_FOR_FIELD_BOUNDARY_DETECTION)
        return false
    end
end
