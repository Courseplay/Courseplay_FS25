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
]]

---
--- High level (scope is the entire vehicle chain) utilities for the Courseplay AI

---@class AIUtil
AIUtil = {}

function AIUtil.isReverseDriving(vehicle)
	if not vehicle then
		printCallstack()
		return false
	end
	return vehicle.spec_reverseDriving and vehicle.spec_reverseDriving.isReverseDriving
end

function AIUtil.getDirectionNode(vehicle)
	-- TODO: We used this to make sure to return a direction node that always points to the
	-- forward direction, even if a vehicle had its direction reversed (cabin turned). Now we
	-- think getAIDirectionNode() guarantees this, the only reason this is still here is that
	-- we need to check if it is possible the call this with a vehicle which has no AI direction node
	-- and fall back to the root node.
	return vehicle.getAIDirectionNode and vehicle:getAIDirectionNode() or vehicle.rootNode
end

---@return number the z offset of the root node in the direction node's coordinate system: if > 0, the direction node
--- is behind the root node, otherwise in front of it
function AIUtil.getDirectionNodeToRootNodeOffset(vehicle)
	local _, _, dz = localToLocal(vehicle.rootNode, AIUtil.getDirectionNode(vehicle), 0, 0, 0)
	return dz
end

--- If we are towing an implement, move to a bigger radius in tight turns
--- making sure that the towed implement's trajectory remains closer to the
--- course.
---@param course Course
function AIUtil.calculateTightTurnOffset(vehicle, vehicleTurningRadius, course, previousOffset)
	local tightTurnOffset

	local function smoothOffset(offset)
		return (offset + 4 * (previousOffset or 0 )) / 5
	end

	-- first of all, does the current waypoint have radius data?
	local r = course:getCalculatedRadiusAtIx(course:getCurrentWaypointIx())
	if not r then
		return smoothOffset(0)
	end

	-- limit the radius we are trying to follow to the vehicle's turn radius.
	-- TODO: there's some potential here as the towed implement can move on a radius less than the vehicle's
	-- turn radius so this limit may be too pessimistic
	r = math.max(r, vehicleTurningRadius)

	local towBarLength = AIUtil.getTowBarLength(vehicle)

	if towBarLength == nil then
		-- not a towed implement, no offset
		return 0
	end
	-- Is this really a tight turn? It is when the tow bar is longer than radius / 3, otherwise
	-- we ignore it.
	if towBarLength < r / 3 then
		return smoothOffset(0)
	end

	-- Ok, looks like a tight turn, so we need to move a bit left or right of the course
	-- to keep the tool on the course. Use a little less than the calculated, this is purely empirical and should probably
	-- be reviewed why the calculated one seems to overshoot.
	local offset = 0.75 * AIUtil.getOffsetForTowBarLength(r, towBarLength)
	if offset ~= offset then
		-- check for nan
		return smoothOffset(0)
	end
	-- figure out left or right now?
	local nextAngle = course:getWaypointAngleDeg(course:getCurrentWaypointIx() + 1)
	local currentAngle = course:getWaypointAngleDeg(course:getCurrentWaypointIx())
	if not nextAngle or not currentAngle then
		return smoothOffset(0)
	end

	if CpMathUtil.getDeltaAngle(math.rad(nextAngle), math.rad(currentAngle)) > 0 then offset = -offset end

	-- smooth the offset a bit to avoid sudden changes
	tightTurnOffset = smoothOffset(offset)
	CpUtil.debugVehicle(CpDebug.DBG_TURN, vehicle,
		'Tight turn, r = %.1f, tow bar = %.1f m, currentAngle = %.0f, nextAngle = %.0f, offset = %.1f, smoothOffset = %.1f',
		r, towBarLength, currentAngle, nextAngle, offset, tightTurnOffset )
	-- remember the last value for smoothing
	return tightTurnOffset
end

function AIUtil.calculateTightTurnOffsetForTurnManeuver(vehicle, steeringLength, course, ix, previousOffset)
	local tightTurnOffset

	local function smoothOffset(offset)
		return (offset + 4 * (previousOffset or 0 )) / 5
	end

	-- first of all, does the current waypoint have radius data?
	local r = course:getCalculatedRadiusAtIx(ix)
	if not r then
		return smoothOffset(0)
	end

	-- Ok, looks like a tight turn, so we need to move a bit left or right of the course
	-- to keep the tool on the course. Use a little less than the calculated, this is purely empirical and should probably
	-- be reviewed why the calculated one seems to overshoot.
	local offset = 1 * AIUtil.getTractorRadiusFromImplementRadius(r, steeringLength) - r
	if offset ~= offset then
		-- check for nan
		return smoothOffset(0)
	end
	-- figure out left or right now?
	local nextAngle = course:getWaypointAngleDeg(ix + 1)
	local currentAngle = course:getWaypointAngleDeg(ix)
	if not nextAngle or not currentAngle then
		return smoothOffset(0)
	end

	if CpMathUtil.getDeltaAngle(math.rad(nextAngle), math.rad(currentAngle)) > 0 then offset = -offset end

	-- smooth the offset a bit to avoid sudden changes
	tightTurnOffset = smoothOffset(offset)
	CpUtil.debugVehicle(CpDebug.DBG_TURN, vehicle,
			'Tight turn, r = %.1f, tow bar = %.1f m, currentAngle = %.0f, nextAngle = %.0f, offset = %.1f, smoothOffset = %.1f',
			r, steeringLength, currentAngle, nextAngle, offset, tightTurnOffset )
	-- remember the last value for smoothing
	return tightTurnOffset
end


function AIUtil.getTowBarLength(vehicle)
	-- is there a wheeled implement behind the tractor and is it on a pivot?
	local implement = AIUtil.getFirstReversingImplementWithWheels(vehicle, true)
	if not implement then
		return nil
	elseif not implement.steeringAxleNode then
		CpUtil.debugVehicle(CpDebug.DBG_AI_DRIVER, vehicle, 'could not get tow bar length, using default 3 m.')
		-- default is not 0 as this is used to calculate trailer heading and 0 here may result in NaNs
		return 3
	end
	-- get the distance between the tractor and the towed implement's turn node
	-- (not quite accurate when the angle between the tractor and the tool is high)
	local tractorX, _, tractorZ = getWorldTranslation(AIUtil.getDirectionNode(vehicle))
	local toolX, _, toolZ = getWorldTranslation(implement.steeringAxleNode)
	local towBarLength = MathUtil.getPointPointDistance( tractorX, tractorZ, toolX, toolZ )
	CpUtil.debugVehicle(CpDebug.DBG_AI_DRIVER, vehicle, 'tow bar length is %.1f.', towBarLength)
	return towBarLength
end

---@return boolean, number true if this is a towed reversing implement/steeringLength
function AIUtil.getSteeringParameters(vehicle)
	local implement = AIUtil.getFirstReversingImplementWithWheels(vehicle)
	if not implement then
		return false, 0
	else
		return true, AIUtil.getTowBarLength(vehicle) or 3
	end
end

function AIUtil.getOffsetForTowBarLength(r, towBarLength)
	return AIUtil.getTractorRadiusFromImplementRadius(r, towBarLength) - r
end

--- When a tractor is towing an implement in a turn, on what radius will the implement be if
--- the radius the tractor is driving is known?
---@param r number the radius the tractor is on
---@param towBarLength number the length of the tow bar
---@return number the radius the implement will be on. Can be negative, meaning the implement will be
--- moving backwards in the turn
function AIUtil.getImplementRadiusFromTractorRadius(r, towBarLength)
	local rSquared = r * r - towBarLength * towBarLength
	local rImplement = rSquared > 0 and math.sqrt(rSquared) or -math.sqrt(-rSquared)
	return rImplement
end

--- When a tractor is towing an implement in a turn, on what radius will the tractor be if
--- the radius the implement is known?
---@param r number the radius the implement is following
---@param towBarLength number the length of the tow bar
---@return number the radius the tractor will be on
function AIUtil.getTractorRadiusFromImplementRadius(r, towBarLength)
	local rTractor = math.sqrt( r * r + towBarLength * towBarLength )
	return rTractor
end

function AIUtil.getArticulatedAxisVehicleReverserNode(vehicle)
	local reverserNode, debugText
	-- articulated axis vehicles have a special reverser node
	-- and yes, Giants has a typo in there...
	if vehicle.spec_articulatedAxis.aiRevereserNode ~= nil then
		reverserNode = vehicle.spec_articulatedAxis.aiRevereserNode
		debugText = 'vehicle articulated axis reverese'
	elseif vehicle.spec_articulatedAxis.aiReverserNode ~= nil then
		reverserNode = vehicle.spec_articulatedAxis.aiReverserNode
		debugText = 'vehicle articulated axis reverse'
	end
	return reverserNode, debugText
end

-- Find the node to use by the PPC when driving in reverse
function AIUtil.getReverserNode(vehicle, reversingImplement, suppressLog)
	local reverserNode, debugText
	-- if there's a reverser node on the tool, use that
	reverserNode, debugText = AIVehicleUtil.getAIToolReverserDirectionNode(vehicle), 'AIToolReverserDirectionNode'
	if not reverserNode then
		reversingImplement = reversingImplement and reversingImplement or AIUtil.getFirstReversingImplementWithWheels(vehicle, suppressLog)
		if reversingImplement and reversingImplement.steeringAxleNode then
			reverserNode, debugText = reversingImplement.steeringAxleNode, 'implement steering axle node'
		end
	end
	if not reverserNode and vehicle.getAIReverserNode then
		reverserNode, debugText = vehicle:getAIReverserNode(), 'AIReverserNode'
	end
	if not reverserNode and vehicle.spec_articulatedAxis ~= nil then
		reverserNode, debugText = AIUtil.getArticulatedAxisVehicleReverserNode(vehicle)
	end
	return reverserNode, debugText
end

---@return number the offset of the reverser node from the direction node, usually negative as the
--- reverser node is behind the direction node. If there is no reverser node, return 0
function AIUtil.getDirectionNodeToReverserNodeOffset(vehicle)
	local reverserNode = AIUtil.getReverserNode(vehicle)
	if reverserNode then
		local _, _, dz = localToLocal(reverserNode, AIUtil.getDirectionNode(vehicle), 0, 0, 0)
		return dz
	else
		return 0
	end
end

-- Get the turning radius of the vehicle and its implements (copied from AIDriveStrategyStraight.updateTurnData())
---@param vehicle table
---@param logEnabled boolean only write debug logs if this is true
function AIUtil.getTurningRadius(vehicle, logEnabled)
	
	CpUtil.debugVehicleIf(logEnabled, CpDebug.DBG_IMPLEMENTS, vehicle, 'Finding turn radius:')

	local radius = vehicle.maxTurningRadius or 6
	CpUtil.debugVehicleIf(logEnabled, CpDebug.DBG_IMPLEMENTS, vehicle, '  turnRadius set to %.1f', radius)

	if g_vehicleConfigurations:get(vehicle, 'turnRadius') then
		radius = g_vehicleConfigurations:get(vehicle, 'turnRadius')
		CpUtil.debugVehicleIf(logEnabled, CpDebug.DBG_IMPLEMENTS, vehicle, '  turnRadius set from config file to %.1f', radius)
	end

	if vehicle:getAIMinTurningRadius() ~= nil then
		CpUtil.debugVehicleIf(logEnabled, CpDebug.DBG_IMPLEMENTS, vehicle, '  AIMinTurningRadius by Giants is %.1f', vehicle:getAIMinTurningRadius())
		radius = math.max(radius, vehicle:getAIMinTurningRadius())
	end

	local maxToolRadius = 0

	for _, implement in pairs(vehicle:getChildVehicles()) do
		local turnRadius = 0
		if g_vehicleConfigurations:get(implement, 'turnRadius') then
			turnRadius = g_vehicleConfigurations:get(implement, 'turnRadius')
			CpUtil.debugVehicleIf(logEnabled, CpDebug.DBG_IMPLEMENTS, vehicle, '  %s: using the configured turn radius %.1f',
				implement:getName(), turnRadius)
		elseif vehicle.isServer and SpecializationUtil.hasSpecialization(AIImplement, implement.specializations) then
			--- Make sure this function only gets called on the server, as otherwise error might appear.
			-- only call this for AIImplements, others may throw an error as the Giants code assumes AIImplement
			turnRadius = AIVehicleUtil.getMaxToolRadius({object = implement}) -- Giants should fix their code and take the implement object as the parameter
			if turnRadius > 0 then
				CpUtil.debugVehicleIf(logEnabled, CpDebug.DBG_IMPLEMENTS, vehicle, '  %s: using the Giants turn radius %.1f',
					implement:getName(), turnRadius)
			end
		end
		if turnRadius == 0 and implement ~= vehicle then
			if AIUtil.isImplementTowed(vehicle, implement) then
				if AIUtil.hasImplementWithSpecialization(vehicle, Trailer) and
						AIUtil.hasImplementWithSpecialization(vehicle, Pipe) then
					-- Auger wagons don't usually have a proper turn radius configured which causes problems when we
					-- are calculating the path to a trailer when unloading. Use this as a minimum turn radius.
					turnRadius = 10
                    CpUtil.debugVehicleIf(logEnabled, CpDebug.DBG_IMPLEMENTS, vehicle, '  %s: no Giants turn radius, auger wagon, we use a default %.1f',
                            implement:getName(), turnRadius)
				else
				    turnRadius = 6
				    CpUtil.debugVehicleIf(logEnabled, CpDebug.DBG_IMPLEMENTS, vehicle, '  %s: no Giants turn radius, towed implement, we use a default %.1f',
						implement:getName(), turnRadius)
				end
			else
				CpUtil.debugVehicleIf(logEnabled, CpDebug.DBG_IMPLEMENTS, vehicle, '  %s: no Giants turn radius, not towed, do not use turn radius',
					implement:getName())
			end
		end
		maxToolRadius = math.max(maxToolRadius, turnRadius)
		CpUtil.debugVehicleIf(logEnabled, CpDebug.DBG_IMPLEMENTS, vehicle, '  %s: max tool radius now is %.1f', implement:getName(), maxToolRadius)
	end
	radius = math.max(radius, maxToolRadius)
	CpUtil.debugVehicleIf(logEnabled, CpDebug.DBG_IMPLEMENTS, vehicle, 'getTurningRadius: %.1f m', radius)
	return radius
end

---@param vehicle table
---@param implementObject table
function AIUtil.isImplementTowed(vehicle, implementObject)
	if AIUtil.isObjectAttachedOnTheBack(vehicle, implementObject) then
		if ImplementUtil.isWheeledImplement(implementObject) then
			return true
		end
	end
	return false
end

---@return table implement object
function AIUtil.getFirstReversingImplementWithWheels(vehicle, suppressLog)
	-- since some weird things like Seed Bigbag are also vehicles, check this first
	if not vehicle.getAttachedImplements then return nil end

	-- Check all attached implements if we are a wheeled workTool behind the tractor
	for _, imp in ipairs(vehicle:getAttachedImplements()) do
		-- Check if the implement is behind the tractor
		if AIUtil.isObjectAttachedOnTheBack(vehicle, imp.object) then
			if ImplementUtil.isWheeledImplement(imp.object) then
				if not suppressLog then
					CpUtil.debugVehicle(CpDebug.DBG_IMPLEMENTS, vehicle, 'Implement %s has wheels', CpUtil.getName(imp.object))
				end
				-- If the implement is a wheeled workTool, then return the object
				return imp.object
			else
				if not suppressLog then
					CpUtil.debugVehicle(CpDebug.DBG_IMPLEMENTS, vehicle, '%s has no wheels, check if anything attached to it',
							CpUtil.getName(imp.object))
				end
				-- If the implement is not a wheeled workTool, then check if that implement have an attached wheeled workTool and return that.
				local nextAttachedImplement = AIUtil.getFirstReversingImplementWithWheels(imp.object)
				if nextAttachedImplement then
					return nextAttachedImplement
				elseif not suppressLog then
					CpUtil.debugVehicle(CpDebug.DBG_IMPLEMENTS, vehicle, '%s has nothing attached, see what else is attached to %s',
							CpUtil.getName(imp.object), CpUtil.getName(vehicle))
				end
			end
		end
	end
	-- If we didnt find any workTool, return nil
	return nil
end

---@return boolean true if there are any implements attached to the back of the vehicle
function AIUtil.hasImplementsOnTheBack(vehicle)
	for _, implement in pairs(vehicle:getAttachedImplements()) do
		if implement.object ~= nil then
			local _, _, dz = localToLocal(implement.object.rootNode, AIUtil.getDirectionNode(vehicle), 0, 0, 0)
			if dz < 0 then
				return true
			end
		end
	end
	return false
end

--- Is the object attached at the front of the vehicle.
---@param vehicle table
---@param object table
---@return boolean
function AIUtil.isObjectAttachedOnTheFront(vehicle,object)
	local _, _, dz = localToLocal(object.rootNode, AIUtil.getDirectionNode(vehicle), 0, 0, 0)
	if dz > 0 then
		return true
	end
	return false
end

--- Is the object attached at the back of the vehicle.
---@param vehicle table
---@param object table
---@return boolean
function AIUtil.isObjectAttachedOnTheBack(vehicle, object)
	-- TODO: now in the implement's coordinate system, this is still not 100% reliable in turns
	local _, _, dz = localToLocal(AIUtil.getDirectionNode(vehicle), object.rootNode, 0, 0, 0)
	if dz > 0 then
		return true
	end
	return false
end

function AIUtil.getAllAttachedImplements(object, implements)
	if not implements then implements = {} end
	for _, implement in ipairs(object:getAttachedImplements()) do
		table.insert(implements, implement)
		AIUtil.getAllAttachedImplements(implement.object, implements)
	end
	return implements
end

---@return table, number frontmost object and the distance between the front of that object and the direction node of the vehicle
--- when > 0 in front of the vehicle
function AIUtil.getFirstAttachedImplement(vehicle, suppressLog)
	-- by default, it is the vehicle's front
	local maxDistance = vehicle.size.length / 2 + vehicle.size.lengthOffset + AIUtil.getDirectionNodeToRootNodeOffset(vehicle)
	local firstImplement = vehicle
	for _, implement in pairs(AIUtil.getAllAttachedImplements(vehicle)) do
		if implement.object ~= nil then
			-- the distance from the vehicle's root node to the front of the implement
			local _, _, d = localToLocal(implement.object.rootNode, AIUtil.getDirectionNode(vehicle), 0, 0,
				implement.object.size.length / 2 + implement.object.size.lengthOffset)
			if implement.object.spec_leveler then
				local nodeData = ImplementUtil.getLevelerNode(implement.object)
				if nodeData then
					_, _, d = localToLocal(nodeData.node, AIUtil.getDirectionNode(vehicle), 0, 0, 0)
				end
			end
			if not suppressLog then
				CpUtil.debugVehicle(CpDebug.DBG_IMPLEMENTS, vehicle, '%s front distance %d', implement.object:getName(), d)
			end
			if d > maxDistance then
				maxDistance = d
				firstImplement = implement.object
			end
		end
	end
	return firstImplement, maxDistance
end

---@return table, number rearmost object and the distance between the back of that object and the direction node of the object
function AIUtil.getLastAttachedImplement(vehicle,suppressLog)
	-- by default, it is the vehicle's back
	local minDistance = vehicle.size.length / 2 - vehicle.size.lengthOffset + AIUtil.getDirectionNodeToRootNodeOffset(vehicle)
	-- size.lengthOffset > 0 if the root node is towards the back of the vehicle, < 0 if it is towards the front
	local lastImplement = vehicle
	for _, implement in pairs(AIUtil.getAllAttachedImplements(vehicle)) do
		if implement.object ~= nil then
			-- the distance from the vehicle's root node to the back of the implement
			local _, _, d = localToLocal(implement.object.rootNode, AIUtil.getDirectionNode(vehicle), 0, 0,
				- implement.object.size.length / 2 + implement.object.size.lengthOffset)
			if implement.object.spec_leveler then
				local nodeData = ImplementUtil.getLevelerNode(implement.object)
				if nodeData then
					_, _, d = localToLocal(nodeData.node, AIUtil.getDirectionNode(vehicle), 0, 0, 0)
				end
			end	
			if not suppressLog then
				CpUtil.debugVehicle(CpDebug.DBG_IMPLEMENTS, vehicle, '%s back distance %d', implement.object:getName(), d)
			end
			if d < minDistance then
				minDistance = d
				lastImplement = implement.object
			end
		end
	end
	return lastImplement, minDistance
end

--- These functions only find directly attached implements/trailer to the vehicle.
--- Implements of others for example a shovel attached to a front loader are not detected.
function AIUtil.hasAIImplementWithSpecialization(vehicle, specialization)
	return AIUtil.getAIImplementWithSpecialization(vehicle, specialization) ~= nil
end

function AIUtil.hasImplementWithSpecialization(vehicle, specialization)
	return AIUtil.getImplementWithSpecialization(vehicle, specialization) ~= nil
end

function AIUtil.getAIImplementWithSpecialization(vehicle, specialization)
	local aiImplements = vehicle:getAttachedAIImplements()
	return AIUtil.getImplementWithSpecializationFromList(specialization, aiImplements)
end

function AIUtil.getImplementWithSpecialization(vehicle, specialization)
	local implements = vehicle:getAttachedImplements()
	return AIUtil.getImplementWithSpecializationFromList(specialization, implements)
end

--- Gets a directly attached implement to the vehicle with a given specialization.
--- Additionally checks if the vehicle has the specialization and returns it, if no implement was found.
--- For example a self driving overloader.
function AIUtil.getImplementOrVehicleWithSpecialization(vehicle, specialization)
	return AIUtil.getImplementWithSpecialization(vehicle, specialization) or (
			SpecializationUtil.hasSpecialization(specialization, vehicle.specializations) and vehicle or nil)
end

function AIUtil.getImplementWithSpecializationFromList(specialization, implements)
	for _, implement in ipairs(implements) do
		if SpecializationUtil.hasSpecialization(specialization, implement.object.specializations) then
			return implement.object
		end
	end
end

--- Get number of child vehicles that have a certain specialization
---@param vehicle table
---@param specialization table specialization to check for
---@return number number of found vehicles
function AIUtil.getNumberOfChildVehiclesWithSpecialization(vehicle, specialization)
	local vehicles = AIUtil.getAllChildVehiclesWithSpecialization(vehicle, specialization, nil)

	return #vehicles
end

--- Gets all child vehicles with a given specialization.
--- This can include the rootVehicle and implements
--- that are not directly attached to the rootVehicle.
---@param vehicle table
---@param specialization table
---@param specializationReference string|nil alternative for mod specializations, as their object is not accessible by us.
---@return table all found vehicles/implements
---@return boolean at least one vehicle/implement was found
function AIUtil.getAllChildVehiclesWithSpecialization(vehicle, specialization, specializationReference)
	if vehicle == nil then
		printCallstack()
		CpUtil.info("Vehicle is nil!")
		return {}, false
	end
	local validVehicles = {}
	for _, childVehicle in pairs(vehicle:getChildVehicles()) do
		if specializationReference and childVehicle[specializationReference] then
			table.insert(validVehicles, childVehicle)
		end
		if specialization and SpecializationUtil.hasSpecialization(specialization, childVehicle.specializations) then
			table.insert(validVehicles, childVehicle)
		end
	end
	return validVehicles, #validVehicles>0
end

--- Was at least one child vehicle with the given specialization found ?
--- This can include the rootVehicle and implements,
--- that are not directly attached to the rootVehicle.
---@param vehicle table
---@param specialization table
---@param specializationReference string|nil
---@return boolean
function AIUtil.hasChildVehicleWithSpecialization(vehicle, specialization, specializationReference)
	local _, found = AIUtil.getAllChildVehiclesWithSpecialization(vehicle, specialization, specializationReference)
	return found
end

function AIUtil.getAllAIImplements(object, implements)
	if not implements then implements = {} end
	for _, implement in ipairs(object:getAttachedImplements()) do
		-- ignore everything which has no work area
		if AIUtil.isValidAIImplement(implement.object) then
			table.insert(implements, implement)
		end
		AIUtil.getAllAIImplements(implement.object, implements)
	end
	return implements
end

-- Is this and implement we should consider when deciding when to lift/raise implements at the end/start of a row?
function AIUtil.isValidAIImplement(object)
	if WorkWidthUtil.hasWorkAreas(object) then
		-- has work areas, good.
		return true
	else
		local aiLeftMarker, _, _ = WorkWidthUtil.getAIMarkers(object, true)
		if aiLeftMarker then
			-- has AI markers, good
			return true
		else
			-- no work areas, no AI markers, can't use.
			return false
		end
	end
end

--- Is this a real wheel the implement is actually rolling on (and turning around) or just some auxiliary support
--- wheel? We need to know about the real wheels when finding the turn radius/distance between attacher joint and
--- wheels.
function AIUtil.isRealWheel(wheel)
	return wheel.hasTireTracks and wheel.maxLatStiffnessLoad > 0.5
end

function AIUtil.isBehindOtherVehicle(vehicle, otherVehicle)
	local _, _, dz = localToLocal(AIUtil.getDirectionNode(vehicle), AIUtil.getDirectionNode(otherVehicle), 0, 0, 0)
	return dz < 0
end

function AIUtil.isStopped(vehicle)
	-- giants supplied last speed is in m/ms
	return math.abs(vehicle.lastSpeedReal) < 0.0001
end

-- Note that this may temporarily return false even if it is reversing
function AIUtil.isReversing(vehicle)
	if (AIUtil.isInReverseGear(vehicle) and math.abs(vehicle.lastSpeedReal) > 0.00001) then
		return true
	else
		return false
	end
end

function AIUtil.isInReverseGear(vehicle)
	return vehicle.getMotor and vehicle:getMotor():getGearRatio() < 0
end

--- Get the current normalized steering angle:
---@return number between -1 and +1, -1 full right steering, +1 full left steering
function AIUtil.getCurrentNormalizedSteeringAngle(vehicle)
	if vehicle.rotatedTime >= 0 then
		return vehicle.rotatedTime / vehicle.maxRotTime
	elseif vehicle.rotatedTime < 0 then
		return -vehicle.rotatedTime / vehicle.minRotTime
	end
end

--- Is a sugarcane trailer attached ?
---@param vehicle table
function AIUtil.hasSugarCaneTrailer(vehicle)
	if vehicle.spec_shovel and vehicle.spec_trailer then
		return true
	end
	for _, implement in pairs(AIUtil.getAllAttachedImplements(vehicle)) do
		local object = implement.object
		if object.spec_shovel and object.spec_trailer then
			return true
		end
	end
end

--- Are there any trailer under the pipe ?
---@param pipe table
---@param shouldTrailerBeStandingStill boolean
function AIUtil.isTrailerUnderPipe(pipe, shouldTrailerBeStandingStill)
	if not pipe then return end
	for trailer, value in pairs(pipe.objectsInTriggers) do
		if value > 0 then
			if shouldTrailerBeStandingStill then
				local rootVehicle = trailer:getRootVehicle()
				if rootVehicle then
					if AIUtil.isStopped(rootVehicle) then
						return true
					else
						return false
					end
				end
			end
			return true
		end
	end
	return false
end

---Gets the total length of the vehicle and all it's implements.
function AIUtil.getVehicleAndImplementsTotalLength(vehicle)
	local totalLength = vehicle.size.length
	for _, implement in pairs(AIUtil.getAllAttachedImplements(vehicle)) do
		if implement.object ~= nil then
			totalLength = totalLength + implement.object.size.length
		end
	end
	return totalLength
end

function AIUtil.findLoweringDurationMs(vehicle)
    local function getLoweringDurationMs(object)
        if object.spec_animatedVehicle then
            -- TODO: implement these in the specifications?
            return math.max(object.spec_animatedVehicle:getAnimationDuration('lowerAnimation'),
                    object.spec_animatedVehicle:getAnimationDuration('rotatePickup'))
        else
            return 0
        end
    end

	local loweringDurationMs = getLoweringDurationMs(vehicle)
	CpUtil.debugVehicle(CpDebug.DBG_IMPLEMENTS, vehicle, 'Lowering duration: %d ms', loweringDurationMs)

	-- check all implements first
	local implements = vehicle:getAttachedImplements()
	for _, implement in ipairs(implements) do
		local implementLoweringDurationMs = getLoweringDurationMs(implement.object)
		CpUtil.debugVehicle(CpDebug.DBG_IMPLEMENTS, vehicle, 'Lowering duration (%s): %d ms', implement.object:getName(), implementLoweringDurationMs)
		if implementLoweringDurationMs > loweringDurationMs then
			loweringDurationMs = implementLoweringDurationMs
		end
		local jointDescIndex = implement.jointDescIndex
		-- now check the attacher joints
		if vehicle.spec_attacherJoints and jointDescIndex then
			local ajs = vehicle.spec_attacherJoints:getAttacherJoints()
			local ajLoweringDurationMs = ajs[jointDescIndex] and ajs[jointDescIndex].moveDefaultTime or 0
			CpUtil.debugVehicle(CpDebug.DBG_IMPLEMENTS, vehicle, 'Lowering duration (%s attacher joint): %d ms', implement.object:getName(), ajLoweringDurationMs)
			if ajLoweringDurationMs > loweringDurationMs then
				loweringDurationMs = ajLoweringDurationMs
			end
		end
	end
	if not loweringDurationMs or loweringDurationMs <= 1 then
		loweringDurationMs = 2000
		CpUtil.debugVehicle(CpDebug.DBG_IMPLEMENTS, vehicle, 'No lowering duration found, setting to: %d ms', loweringDurationMs)
	end
	CpUtil.debugVehicle(CpDebug.DBG_IMPLEMENTS, vehicle, 'Final lowering duration: %d ms', loweringDurationMs)
	return loweringDurationMs
end

function AIUtil.getWidth(vehicle)
	if vehicle.getAIAgentSize then
		local width, length, lengthOffset, frontOffset, height = vehicle:getAIAgentSize()
		return width
	else
		return vehicle.size.width
	end
end

function AIUtil.getLength(vehicle)
	if vehicle.getAIAgentSize then
		vehicle:updateAIAgentAttachments()
		local width, length, lengthOffset, frontOffset, height = vehicle:getAIAgentSize()
		for _, attachment in ipairs(vehicle.spec_aiDrivable.attachments) do
			length = length + attachment.length
		end
		return length
	else
		return vehicle.size.length
	end
end

--- Can we reverse with whatever is attached to the vehicle?
function AIUtil.canReverse(vehicle)
	if AIVehicleUtil.getAttachedImplementsBlockTurnBackward(vehicle) then
		-- Giants says no reverse
		return false
	elseif g_vehicleConfigurations:getRecursively(vehicle, 'noReverse') then
		-- our configuration disabled reverse
		return false
	else
		return true
	end
end

--- Checks if a valid Universal autoload trailer is attached.
--- FS22_UniversalAutoload from Loki79uk: https://github.com/loki79uk/FS22_UniversalAutoload
function AIUtil.hasValidUniversalTrailerAttached(vehicle)
    local implements, found = AIUtil.getAllChildVehiclesWithSpecialization(vehicle, nil, "spec_universalAutoload")
	return found and implements[1].spec_universalAutoload.isAutoloadEnabled
end

--- Checks if cutter on an trailer is attached.
function AIUtil.hasCutterOnTrailerAttached(vehicle)
	local trailer = AIUtil.getImplementWithSpecialization(vehicle, DynamicMountAttacher)
	return trailer and next(trailer.spec_dynamicMountAttacher.dynamicMountedObjects) ~= nil and next(trailer.spec_dynamicMountAttacher.dynamicMountedObjects).spec_cutter ~= nil
end

--- Checks if a cutter is attached and it's not registered as a valid combine cutter.
--- A Example is the New Holland Superflex header, when it is attached as transport trailer.
function AIUtil.hasCutterAsTrailerAttached(vehicle)
	local cutters, found = AIUtil.getAllChildVehiclesWithSpecialization(vehicle, Cutter)
	if not found then
		--- No attached cutter was found.
		return false
	end
	local combines, found = AIUtil.getAllChildVehiclesWithSpecialization(vehicle, Combine)
	if not found then
		--- No valid combine object was found.
		return false
	end
	local spec = combines[1].spec_combine
	if spec.numAttachedCutters <= 0 then
		--- The cutter is not available for threshing in this combination.
		return true
	end
	return false
end

--- SpecializationUtil.hasSpecialization(ArticulatedAxis, specialization) has no use as now every vehicle
--- seems to have a ArticulatedAxis specialization. Giants also using this check below.
function AIUtil.hasArticulatedAxis(vehicle)
	return vehicle.spec_articulatedAxis and vehicle.spec_articulatedAxis.componentJoint
end

------------------------------------------------------------------------------------------------------------------------
-- Is the other vehicle in front of us?
------------------------------------------------------------------------------------------------------------------------
function AIUtil.isOtherVehicleAhead(vehicle, otherVehicle)
	-- if we look straight left or right out of the window, is blockingVehicle in front of us or behind us?
	-- but since we may have a trailer or other implement, don't use the tractor's direction node directly, instead,
	-- a point behind it about the half length of the rig.
	-- (using the front and back markers are probably better than getVehicleAndImplementsTotalLength() as that
	-- assumes that there is no overlap between the vehicle and the implements)
	local _, frontMarkerOffset = Markers.getFrontMarkerNode(vehicle)
	local _, backMarkerOffset = Markers.getBackMarkerNode(vehicle)
	local _, _, dz = localToLocal(otherVehicle.rootNode, vehicle:getAIDirectionNode(), 0, 0, 0)
	return dz > (frontMarkerOffset + backMarkerOffset) / 2
end
