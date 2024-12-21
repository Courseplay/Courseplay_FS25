--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2021 Peter Vaiko

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
]]

---
--- Implement utilities for the Courseplay AI

---@class ImplementUtil
ImplementUtil = {}

function ImplementUtil.isPartOfNode(node, parentNode)
    -- Check if Node is part of partOfNode and not in a different component
    while node ~= 0 and node ~= nil do
        if node == parentNode then
            return true
        else
            node = getParent(node)
        end
    end
    return false
end

--- ImplementUtil.findJointNodeConnectingToNode(workTool, fromNode, toNode, doReverse)
--	Returns: (node, backtrack, rotLimits)
--		node will return either:		1. The jointNode that connects to the toNode,
--										2. The toNode if no jointNode is found but the fromNode is inside the same component as the toNode
--										3. nil in case none of the above fails.
--		backTrack will return either:	1. A table of all the jointNodes found from fromNode to toNode, if the jointNode that connects to the toNode is found.
--										2: nil if no jointNode is found.
--		rotLimits will return either:	1. A table of all the rotLimits of the componentJoint, found from fromNode to toNode, if the jointNode that connects to the toNode is found.
--										2: nil if no jointNode is found.
function ImplementUtil.findJointNodeConnectingToNode(workTool, fromNode, toNode, doReverse)
    if fromNode == toNode then
        return toNode
    end

    -- Attempt to find the jointNode by backtracking the compomentJoints.
    for index, component in ipairs(workTool.components) do
        if ImplementUtil.isPartOfNode(fromNode, component.node) then
            if not doReverse then
                for _, joint in ipairs(workTool.componentJoints) do
                    if joint.componentIndices[2] == index then
                        if workTool.components[joint.componentIndices[1]].node == toNode then
                            --          node            backtrack         rotLimits
                            return joint.jointNode, { joint.jointNode }, { joint.rotLimit }
                        else
                            local node, backTrack, rotLimits = ImplementUtil.findJointNodeConnectingToNode(workTool, workTool.components[joint.componentIndices[1]].node, toNode)
                            if backTrack then
                                table.insert(backTrack, 1, joint.jointNode)
                            end
                            if rotLimits then
                                table.insert(rotLimits, 1, joint.rotLimit)
                            end
                            return node, backTrack, rotLimits
                        end
                    end
                end
            end

            -- Do Reverse in case not found
            for _, joint in ipairs(workTool.componentJoints) do
                if joint.componentIndices[1] == index then
                    if workTool.components[joint.componentIndices[2]].node == toNode then
                        --          node            backtrack         rotLimits
                        return joint.jointNode, { joint.jointNode }, { joint.rotLimit }
                    else
                        local node, backTrack, rotLimits = ImplementUtil.findJointNodeConnectingToNode(workTool, workTool.components[joint.componentIndices[2]].node, toNode, true)
                        if backTrack then
                            table.insert(backTrack, 1, joint.jointNode)
                        end
                        if rotLimits then
                            table.insert(rotLimits, 1, joint.rotLimit)
                        end
                        return node, backTrack, rotLimits
                    end
                end
            end
        end
    end

    -- Last attempt to find the jointNode by getting parent of parent untill hit or the there is no more parents.
    if ImplementUtil.isPartOfNode(fromNode, toNode) then
        return toNode, nil
    end

    -- If anything else fails, return nil
    return nil, nil
end

local allowedJointTypes = {}
---@param implement table implement object
function ImplementUtil.isWheeledImplement(implement)
    if #allowedJointTypes == 0 then
        local jointTypeList = { "implement", "trailer", "trailerLow", "semitrailer", "trailerSaddled" }
        for _, jointType in ipairs(jointTypeList) do
            local index = AttacherJoints.jointTypeNameToInt[jointType]
            if index then
                allowedJointTypes[index] = true
            end
        end
    end

    local activeInputAttacherJoint = implement.getActiveInputAttacherJoint and implement:getActiveInputAttacherJoint()
    if activeInputAttacherJoint and allowedJointTypes[activeInputAttacherJoint.jointType] and
            implement.spec_wheels and implement.spec_wheels.wheels and #implement.spec_wheels.wheels > 0 then
        -- Attempt to find the pivot node.
        local node, _ = ImplementUtil.findJointNodeConnectingToNode(implement, activeInputAttacherJoint.rootNode, implement.rootNode)
        if node then
            -- Trailers
            if (activeInputAttacherJoint.jointType ~= AttacherJoints.JOINTTYPE_IMPLEMENT)
                    -- Implements with pivot and wheels that do not lift the wheels from the ground.
                    or (node ~= implement.rootNode and activeInputAttacherJoint.jointType == AttacherJoints.JOINTTYPE_IMPLEMENT and
                    (not activeInputAttacherJoint.topReferenceNode or
                            g_vehicleConfigurations:get(implement, 'implementWheelAlwaysOnGround')))
            then
                return true
            end
        end
    end
    return false
end

---@param implement table implement object
function ImplementUtil.getLastComponentNodeWithWheels(implement)
    -- Check if there is more than 1 component
    local wheels = implement:getWheels()
    if wheels and #wheels > 0 and #implement.components > 1 then
        -- Set default node to start from.
        local node = implement.rootNode

        -- Loop through all the components.
        for index, component in ipairs(implement.components) do
            -- Don't use the component that is the rootNode.
            if component.node ~= node then
                -- Loop through all the wheels and see if they are attached to this component.
                for i = 1, #wheels do
                    if AIUtil.isRealWheel(wheels[i]) then
                        if ImplementUtil.isPartOfNode(wheels[i].node, component.node) then
                            -- Check if they are linked together
                            for _, joint in ipairs(implement.componentJoints) do
                                if joint.componentIndices[2] == index then
                                    if implement.components[joint.componentIndices[1]].node == node then
                                        -- Check if the component is behind the node.
                                        local xJoint, yJoint, zJoint = getWorldTranslation(joint.jointNode)
                                        local offset, _, direction = worldToLocal(node, xJoint, yJoint, zJoint)
                                        --offset check to make sure we are selecting a node that is centered
                                        if direction < 0 and offset == 0 then
                                            -- Component is behind, so set the node to the new component node.
                                            node = component.node
                                        end
                                    end
                                end
                            end
                            break
                        end
                    end
                end
            end
        end

        -- Return the found node.
        return node
    end

    -- Return default rootNode if none is found.
    return implement.rootNode
end

---@param implement table implement object
function ImplementUtil.getRealTrailerFrontNode(implement)
    local activeInputAttacherJoint = implement:getActiveInputAttacherJoint()
    local jointNode, backtrack = ImplementUtil.findJointNodeConnectingToNode(implement, activeInputAttacherJoint.rootNode, implement.rootNode)
    local realFrontNode
    if jointNode and backtrack and activeInputAttacherJoint.jointType ~= AttacherJoints.JOINTTYPE_IMPLEMENT then
        local rootNode
        for _, joint in ipairs(implement.componentJoints) do
            if joint.jointNode == jointNode and joint.rotLimit ~= nil and joint.rotLimit[2] ~= nil and joint.rotLimit[2] > math.rad(15) then
                rootNode = implement.components[joint.componentIndices[2]].node
                break
            end
        end

        if rootNode then
            realFrontNode = CpUtil.createNode("realFrontNode", 0, 0, 0, rootNode)
            local x, y, z = getWorldTranslation(jointNode)
            local _, _, delta = worldToLocal(rootNode, x, y, z)
            setTranslation(realFrontNode, 0, 0, delta)
        end
    end

    if not realFrontNode then
        realFrontNode = implement.steeringAxleNode
    end

    return realFrontNode
end

---@param implement table implement object
function ImplementUtil.isAttacherModule(implement)
    if implement.spec_attacherJoints.attacherJoint then
        local workToolsWheels = implement:getWheels()
        return (implement.spec_attacherJoints.attacherJoint.jointType == AttacherJoints.JOINTTYPE_SEMITRAILER and
                (not workToolsWheels or (workToolsWheels and #workToolsWheels == 0)))
    end
    return false
end

---@param dolly table implement object
function ImplementUtil.getRealDollyFrontNode(dolly)
    local frontNode
    local activeInputAttacherJoint = dolly:getActiveInputAttacherJoint()
    local node, _ = ImplementUtil.findJointNodeConnectingToNode(dolly, activeInputAttacherJoint.rootNode, dolly.rootNode)
    if node then
        -- Trailers without pivote
        if (node == dolly.rootNode and activeInputAttacherJoint.jointType ~= AttacherJoints.JOINTTYPE_IMPLEMENT)
                -- Implements with pivot and wheels that do not lift the wheels from the ground.
                or (node ~= dolly.rootNode and activeInputAttacherJoint.jointType == AttacherJoints.JOINTTYPE_IMPLEMENT and not activeInputAttacherJoint.topReferenceNode) then
            frontNode = dolly.steeringAxleNode
        else
            frontNode = nil
        end
    end

    return frontNode
end

---@param implement table implement object
function ImplementUtil.getRealTrailerDistanceToPivot(implement)
    -- Attempt to find the pivot node.
    local activeInputAttacherJoint = implement:getActiveInputAttacherJoint()
    local node, backTrack = ImplementUtil.findJointNodeConnectingToNode(implement, activeInputAttacherJoint.rootNode,
            ImplementUtil.getLastComponentNodeWithWheels(implement))
    if node then
        local x, y, z
        if node == implement.rootNode then
            x, y, z = getWorldTranslation(activeInputAttacherJoint.node)
        else
            x, y, z = getWorldTranslation(node)
        end
        local _, _, tz = worldToLocal(implement.steeringAxleNode, x, y, z)
        return tz
    else
        return 3
    end
end

function ImplementUtil.getDirectionNodeToTurnNodeLength(vehicle)

    local totalDistance = 0

    --- If this have not been set before after last stop command, we need to reset it again.
    local distances = vehicle.cp.distances

    for _, imp in ipairs(vehicle:getAttachedImplements()) do
        if AIUtil.isObjectAttachedOnTheBack(vehicle, imp.object) then
            local workTool = imp.object
            local activeInputAttacherJoint = workTool:getActiveInputAttacherJoint()
            if ImplementUtil.isWheeledImplement(workTool) then
                local workToolDistances = workTool.cp.distances

                if workToolDistances.attacherJointToPivot then
                    totalDistance = totalDistance + workToolDistances.attacherJointToPivot
                    ImplementUtil.debug(('getDirectionNodeToTurnNodeLength() -> %s: attacherJointToPivot=%.2fm'):format(
                            nameNum(workTool), workToolDistances.attacherJointToPivot), CpDebug.DBG_IMPLEMENTS)
                end

                totalDistance = totalDistance + workToolDistances.attacherJointOrPivotToTurningNode
                ImplementUtil.debug(('getDirectionNodeToTurnNodeLength() -> %s: attacherJointOrPivotToTurningNode=%.2fm'):format(
                        nameNum(workTool), workToolDistances.attacherJointOrPivotToTurningNode), CpDebug.DBG_IMPLEMENTS)
                ImplementUtil.debug(('getDirectionNodeToTurnNodeLength() -> %s: attacherJointToTurningNode=%.2fm'):format(
                        nameNum(workTool), totalDistance), CpDebug.DBG_IMPLEMENTS)
            else
                if not distances.attacherJointOrPivotToTurningNode and distances.attacherJointToRearTrailerAttacherJoints then
                    totalDistance = totalDistance + distances.attacherJointToRearTrailerAttacherJoints[activeInputAttacherJoint.jointType]
                end
                totalDistance = totalDistance + ImplementUtil.getDirectionNodeToTurnNodeLength(workTool)
                --ImplementUtil.debug(('%s: directionNodeToTurnNodeLength=%.2fm'):format(nameNum(workTool), totalDistance), CpDebug.DBG_IMPLEMENTS)
            end
            break
        end
    end

    if vehicle.cp.directionNode and totalDistance > 0 then
        for _, imp in ipairs(vehicle:getAttachedImplements()) do
            if ImplementUtil.isRearAttached(vehicle, imp.jointDescIndex) then
                local workTool = imp.object
                local activeInputAttacherJoint = workTool:getActiveInputAttacherJoint()
                totalDistance = totalDistance + distances.turningNodeToRearTrailerAttacherJoints[activeInputAttacherJoint.jointType]
                break
            end
        end
        vehicle.cp.directionNodeToTurnNodeLength = totalDistance
        ImplementUtil.debug(('getDirectionNodeToTurnNodeLength() -> %s: directionNodeToTurnNodeLength=%.2fm'):format(
                nameNum(vehicle), totalDistance), CpDebug.DBG_IMPLEMENTS)
    end

    return vehicle.cp.directionNodeToTurnNodeLength or totalDistance
end

--- Get the distance between a reference node (usually tractor's direction node) and a node on the implement,
--- considering that the implement may not be aligned with the tractor so a simple localToLocal between the
--- tractor's node and the implement node would result in errors.
---
--- Therefore, determine the distance in two steps:
--- 1. distance between the reference node and the attacher joint of the implement
--- 2. distance between the attacher joint and the implement node
---
---@param referenceNode number node, usually the tractor's direction node
---@param implementObject table implement object
---@param implementNode number node on the implement we want to know the distance of
function ImplementUtil.getDistanceToImplementNode(referenceNode, implementObject, implementNode)
    local rootToReferenceNodeOffset = 0
    local attacherJoint = implementObject.getActiveInputAttacherJoint and implementObject:getActiveInputAttacherJoint()
    if attacherJoint and attacherJoint.node then
        -- the implement may not be aligned with the vehicle so we need to calculate this distance in two
        -- steps, first the distance between the vehicle's root node and the attacher joint and then
        -- from the attacher joint to the implement's root node
        -- < 0 when the attacher joint is behind the reference node
        local _, _, referenceToAttacherJoint = localToLocal(attacherJoint.node, referenceNode, 0, 0, 0)
        -- > 0 when the attacher node is in front of the implement's root node (we don't use the attacher joint node
        -- as a reference as it may point to any direction, we know the implement's root node points forward
        local _, _, attacherJointToImplementRoot = localToLocal(attacherJoint.node, implementNode, 0, 0, 0)
        -- we call this offset, and is negative when behind the reference node, positive when in front of it
        -- (need to reverse attacherJointToImplementRoot)
        rootToReferenceNodeOffset = -attacherJointToImplementRoot + referenceToAttacherJoint
        CpUtil.debugVehicle(CpDebug.DBG_IMPLEMENTS, implementObject, '%s: ref to attacher joint %.1f, att to implement root %.1f, impl root to ref %.1f',
                implementObject:getName(), referenceToAttacherJoint, attacherJointToImplementRoot, rootToReferenceNodeOffset)
    else
        _, _, rootToReferenceNodeOffset = localToLocal(implementNode, referenceNode, 0, 0, 0)
    end
    return rootToReferenceNodeOffset
end

-- Bale loaders / wrappers have no AI markers
function ImplementUtil.getAIMarkersFromGrabberNode(object, spec)
    -- use the grabber node for all markers if exists
    if spec.baleGrabber and spec.baleGrabber.grabNode then
        return spec.baleGrabber.grabNode, spec.baleGrabber.grabNode, spec.baleGrabber.grabNode
    else
        return object.rootNode, object.rootNode, object.rootNode
    end
end

--- Is the vehicle/implement a Chopper 
function ImplementUtil.isChopper(implement)
    local spec = implement and implement.spec_combine
    return spec and implement:getFillUnitCapacity(spec.fillUnitIndex) > 10000000
end

--- Moves the moving tool rotation to a given rotation target.
---@param implement table
---@param tool table moving tool
---@param dt number
---@param rotTarget number target rotation in radiant
---@param minDiffNeeded number|nil if the difference is smaller than the moving tool is stopped.
---@return boolean
function ImplementUtil.moveMovingToolToRotation(implement, tool, dt, rotTarget, minDiffNeeded)
    if minDiffNeeded == nil then
        minDiffNeeded = 0.03
    end
    if tool.rotSpeed == nil then
		return false
	end
	local spec = implement.spec_cylindered
	tool.curRot[1], tool.curRot[2], tool.curRot[3] = getRotation(tool.node)
	local oldRot = tool.curRot[tool.rotationAxis]
	local diff = rotTarget - oldRot
    local dir = math.sign(diff)
	local rotSpeed = CpMathUtil.clamp( math.abs(diff) * math.abs(tool.rotSpeed), math.abs(tool.rotSpeed)/3, 0.5 )
    rotSpeed = dir * rotSpeed
	if math.abs(diff) < minDiffNeeded or rotSpeed == 0 then
		ImplementUtil.stopMovingTool(implement, tool)
		return false
	end
	if Cylindered.setToolRotation(implement, tool, rotSpeed, dt, diff) then
		Cylindered.setDirty(implement, tool)

		implement:raiseDirtyFlags(tool.dirtyFlag)
		implement:raiseDirtyFlags(spec.cylinderedDirtyFlag)
        return true
	end
    return false
end

--- Force stops the moving tool.
---@param implement table
---@param tool table moving tool
function ImplementUtil.stopMovingTool(implement, tool)
    if tool == nil or tool.move == nil then 
        CpUtil.error("Invalid tool called this function!")
        return
    end
    tool.move = 0
    Cylindered.setDirty(implement, tool)
    local spec = implement.spec_cylindered
    implement:raiseDirtyFlags(tool.dirtyFlag)
    implement:raiseDirtyFlags(spec.cylinderedDirtyFlag)
    local detachLock = spec.detachLockNodes and spec.detachLockNodes[tool]
    if detachLock then
        --- Fix shovel detach, as shovel might have angle requirements for detaching.
        --- These limits are implemented without a hysteresis ...
        --- So we need to force set the limit, if a difference of less than 1 degree was found.
        local node = tool.node
        local rot = {
            getRotation(node)
        }
        if detachLock.detachingRotMinLimit ~=nil and 
            math.abs(MathUtil.getAngleDifference(detachLock.detachingRotMinLimit, rot[tool.rotationAxis])) < math.pi/180 then 
            Cylindered.setAbsoluteToolRotation(implement, tool, detachLock.detachingRotMinLimit)
        end
        if detachLock.detachingRotMaxLimit ~= nil and 
            math.abs(MathUtil.getAngleDifference(detachLock.detachingRotMaxLimit, rot[tool.rotationAxis])) < math.pi/180 then 
            Cylindered.setAbsoluteToolRotation(implement, tool, detachLock.detachingRotMaxLimit)
        end
    end

end

function ImplementUtil.getLevelerNode(object)
    return object.spec_leveler and object.spec_leveler.nodes and object.spec_leveler.nodes[1]
end

function ImplementUtil.getShovelNode(object)
    return object.spec_shovel and object.spec_shovel.shovelNodes and object.spec_shovel.shovelNodes[1]
end

--- Visually displays the bale collector offset
---@param vehicle table
---@param offset number
function ImplementUtil.showBaleCollectorOffset(vehicle, offset)
    local implement = AIUtil.getImplementWithSpecialization(vehicle, BaleLoader)
    if not implement then 
        implement = AIUtil.getImplementWithSpecialization(vehicle, BaleWrapper)
    end
    if implement then
        local x, y, z = localToWorld(vehicle:getAIDirectionNode(), -offset, 3, -5)
        local dx, dy, dz = localToWorld(vehicle:getAIDirectionNode(), -offset, 3, 2)
        DebugUtil.drawDebugLine(x, y, z, dx, dy, dz, 1, 0, 0)
    end
end

--- Checks if loading from an implement to another is possible.
---@param loadTargetImplement table
---@param implementToLoadFrom table
---@param dischargeNode table|nil optional otherwise the current selected node is used.
---@param debugFunc function|nil
---@return boolean is loading possible?
---@return number|nil target implement fill unit ix to load into.
---@return number|nil fill type to load
---@return number|nil target exact fill root node
---@return number|nil alternative fill type, when the implement gets turned on
function ImplementUtil.getCanLoadTo(loadTargetImplement, implementToLoadFrom, dischargeNode, debugFunc)
    
    local function debug(str, ...)
        if debugFunc then
            debugFunc(str, ...)
        end
    end

    if dischargeNode == nil then 
        dischargeNode = implementToLoadFrom:getCurrentDischargeNode()
    end
    if dischargeNode == nil then 
        debug("No valid discharge node found!")
        return false, nil, nil, nil
    end

    local fillType = implementToLoadFrom:getDischargeFillType(dischargeNode)
    local alternativeFillType
    if implementToLoadFrom.spec_turnOnVehicle then 
        --- The discharge node flips when the implement gets turned on.
        --- The fill type might be different then.
        local turnOnDischargeNode = implementToLoadFrom.spec_turnOnVehicle.activateableDischargeNode
        if turnOnDischargeNode then 
            alternativeFillType = implementToLoadFrom:getDischargeFillType(turnOnDischargeNode)
        end
    end
    if fillType == nil or fillType == FillType.UNKNOWN then 
        debug("No valid fill type to load!")
        return false, nil, nil, nil
    end

    --- Is the fill unit a valid load target?
    ---@param fillUnitIndex number
    ---@return boolean
    ---@return number|nil
    ---@return number|nil
    local function canLoad(fillUnitIndex)
        if  not loadTargetImplement:getFillUnitSupportsFillType(fillUnitIndex, fillType) and 
            not loadTargetImplement:getFillUnitSupportsFillType(fillUnitIndex, alternativeFillType)  then
            debug("Fill unit(%d) doesn't support fill type %s", fillUnitIndex, g_fillTypeManager:getFillTypeNameByIndex(fillType))
            return false
        end
        if not loadTargetImplement:getFillUnitAllowsFillType(fillUnitIndex, fillType) and 
            not loadTargetImplement:getFillUnitAllowsFillType(fillUnitIndex, alternativeFillType) then
            debug("Fill unit(%d) doesn't allow fill type %s", fillUnitIndex, g_fillTypeManager:getFillTypeNameByIndex(fillType))
            return false
        end
        if loadTargetImplement.getFillUnitFreeCapacity and 
            loadTargetImplement:getFillUnitFreeCapacity(fillUnitIndex, fillType, implementToLoadFrom:getActiveFarm()) <= 0 and
            loadTargetImplement:getFillUnitFreeCapacity(fillUnitIndex, alternativeFillType, implementToLoadFrom:getActiveFarm()) <= 0 then
            debug("Fill unit(%d) is full with fill type %s!", fillUnitIndex, g_fillTypeManager:getFillTypeNameByIndex(fillType))
            return false  
        end
        if loadTargetImplement.getIsFillAllowedFromFarm and 
            not loadTargetImplement:getIsFillAllowedFromFarm(implementToLoadFrom:getActiveFarm()) then
            debug("Fill unit(%d) filling to target farm %s from %s not allowed!", 
                fillUnitIndex, loadTargetImplement:getOwnerFarmId(), implementToLoadFrom:getActiveFarm())
            return false
        end
        local exactFillRootNode = loadTargetImplement:getFillUnitExactFillRootNode(fillUnitIndex)
        if not exactFillRootNode then 
            debug("Fill unit(%d) has no valid exact fill root node!", fillUnitIndex)
            return false
        end
        return true, fillUnitIndex, exactFillRootNode
    end

    local validTarget, targetFillUnitIndex, exactFillRootNode
    for fillUnitIndex, fillUnit in pairs(loadTargetImplement:getFillUnits()) do 
        validTarget, targetFillUnitIndex, exactFillRootNode = canLoad(fillUnitIndex)
        if validTarget then 
            break
        end
    end

    return validTarget, targetFillUnitIndex, fillType, exactFillRootNode, alternativeFillType
end

--- Checks the passed in implements for a fill level change 
--- and also caches the current fill levels.
--- Example input table format: {["implement"]["fillUnitIndex"] = 200}  
---@param fillLevelData table<table, table<number, number>>
---@param reset boolean|nil
function ImplementUtil.hasFillLevelChanged(fillLevelData, reset)
    local hasChanged = false
    for implement, data in pairs(fillLevelData) do 
        for fillUnitIndex, fillLevel in pairs(data) do
            local curFillLevel = implement:getFillUnitFillLevel(fillUnitIndex) 
            if reset then 
                fillLevelData[implement][fillUnitIndex] = -1
            else
                if fillLevel > -1 and curFillLevel ~= fillLevel then 
                    hasChanged = true
                end
                fillLevelData[implement][fillUnitIndex] = curFillLevel
            end
        end
    end 
    return hasChanged
end

--- Trys to start loading from triggers, pallets and so on nearby.
---@param implements table<table, ...>
---@return boolean refilling is currently refilling
function ImplementUtil.tryAndCheckRefillingFillUnits(implements)
    local isFilling = false
    for implement, _ in pairs(implements) do
        local spec = implement.spec_fillUnit
        local activatable = spec.fillTrigger.activatable
        if not spec.fillTrigger.isFilling then 
            local rootVehicle = activatable.vehicle
            if rootVehicle then 
                local oldFunc = rootVehicle.getIsActiveForInput
                rootVehicle.getIsActiveForInput = function ()
                    return true
                end
                if activatable:getIsActivatable() then 
                    activatable:run()
                end
                rootVehicle.getIsActiveForInput = oldFunc
            end
        end
        isFilling = isFilling or spec.fillTrigger.isFilling
    end
    return isFilling
end