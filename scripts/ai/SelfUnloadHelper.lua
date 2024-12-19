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
]]


--- Helper functions for finding a trailer around the field where a combine or an auger wagon can unload
---@class SelfUnloadHelper
SelfUnloadHelper = {}
SelfUnloadHelper.debugChannel = CpDebug.DBG_FIELDWORK
-- keep the helper nodes we create in this table for each vehicle so no nodes need to be created/destroyed
SelfUnloadHelper.bestFillNodes = {}
-- search for trailers within this distance from the field
SelfUnloadHelper.maxDistanceFromField = 20

--- Find a trailer we can use for self unloading
---@param fieldPolygon Polygon the field boundary. We'll look for targets on this field, or close to the boundary.
---@param myVehicle table to find the target closest to myVehicle, for logging, to exclude targets attached to this vehicle
---@param implementWithPipe table trailer or combine with the pipe
---@param pipeOffsetX number pipe side offset (distance from combine centerline, >0 left, <0 right
---@return table|nil trailer object (nil if no trailer found
---@return table|nil best fill node of trailer
---@return number|nil distance of trailer from myVehicle
function SelfUnloadHelper:findBestTrailer(fieldPolygon, myVehicle, implementWithPipe, pipeOffsetX)
    local bestTrailer, bestFillUnitIndex, bestFillType
    local minDistance = math.huge
    for _, otherVehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if SpecializationUtil.hasSpecialization(Trailer, otherVehicle.specializations) then
            local rootVehicle = otherVehicle:getRootVehicle()
            local attacherVehicle
            if SpecializationUtil.hasSpecialization(Attachable, otherVehicle.specializations) then
                attacherVehicle = otherVehicle.spec_attachable:getAttacherVehicle()
            end
            local x, _, z = getWorldTranslation(otherVehicle.rootNode)
            local closestDistance = CpMathUtil.getClosestDistanceToPolygonEdge(fieldPolygon, x, z)
            -- if the trailer is within 20 m of the field perimeter, we are good
            local isOnField = closestDistance <= SelfUnloadHelper.maxDistanceFromField
            if not isOnField then
                -- not within 20 m, but could still be on the field
                isOnField = CpMathUtil.isPointInPolygon(fieldPolygon, x, z)
            end
            local lastSpeed = rootVehicle:getLastSpeed()
            local isCpActive = rootVehicle.getIsCpActive and rootVehicle:getIsCpActive()
            CpUtil.debugVehicle(self.debugChannel, myVehicle,
                    '%s is a trailer %s on my field, closest distance to the field is %.1f, attached to %s, root vehicle is %s, last speed %.1f, CP active %s',
                    otherVehicle:getName(), isOnField and '' or 'NOT', closestDistance, attacherVehicle and attacherVehicle:getName() or 'none',
                    rootVehicle:getName(), lastSpeed, isCpActive)
            -- consider only trailer on my field or close to my field, not driven by CP and stopped
            if rootVehicle ~= myVehicle and not isCpActive and lastSpeed < 0.1 and isOnField and
                    not self:isInvalidAutoDriveTarget(myVehicle, rootVehicle) then
                local d = calcDistanceFrom(myVehicle:getAIDirectionNode(), otherVehicle.rootNode or otherVehicle.nodeId)

                local canLoad, fillUnitIndex, fillType = ImplementUtil.getCanLoadTo(
                    otherVehicle, 
                    implementWithPipe, 
                    nil,
                    function(...)
                        CpUtil.debugVehicle(self.debugChannel, myVehicle, "%s attached to: %s => %s", CpUtil.getName(otherVehicle), 
                        otherVehicle.rootVehicle and CpUtil.getName(otherVehicle.rootVehicle) or "no root vehicle", string.format(...))
                    end )
                if d < minDistance and canLoad then
                    bestTrailer = otherVehicle
                    bestFillUnitIndex = fillUnitIndex
                    bestFillType = fillType
                    minDistance = d
                end
            end
        end
    end
    local fillRootNode
    if bestTrailer then
        fillRootNode = bestTrailer:getFillUnitExactFillRootNode(bestFillUnitIndex)
        CpUtil.debugVehicle(self.debugChannel, myVehicle,
                'Best trailer is %s at %.1f meters, fill type %s, free capacity %d, fill unit index %s',
                bestTrailer:getName(), minDistance, g_fillTypeManager:getFillTypeNameByIndex(bestFillType), 
                bestTrailer:getFillUnitFreeCapacity(bestFillUnitIndex), bestFillUnitIndex)
        local bestFillNode = self:findBestFillNode(myVehicle, fillRootNode, pipeOffsetX)
        return bestTrailer, bestFillNode, minDistance
    else
        CpUtil.infoVehicle(myVehicle, 'Found no trailer to unload to.')
        return nil
    end
end

function SelfUnloadHelper:findBestFillNode(myVehicle, fillRootNode, offset)
    local dx, dy, dz = localToLocal(fillRootNode, AIUtil.getDirectionNode(myVehicle), offset, 0, 0)
    local dLeft = MathUtil.vector3Length(dx, dy, dz)
    dx, dy, dz = localToLocal(fillRootNode, AIUtil.getDirectionNode(myVehicle), -offset, 0, 0)
    local dRight = MathUtil.vector3Length(dx, dy, dz)
    CpUtil.debugVehicle(self.debugChannel, myVehicle, 'Trailer left side distance %d, right side %d', dLeft, dRight)
    if dLeft <= dRight then
        -- left side of the trailer is closer, so turn the fillRootNode around as the combine must approach the
        -- trailer from the front of the trailer
        if not self.bestFillNodes[myVehicle] then
            self.bestFillNodes[myVehicle] = CpUtil.createNode('bestFillNode', 0, 0, math.pi, fillRootNode)
        else
            unlink(self.bestFillNodes[myVehicle])
            link(fillRootNode, self.bestFillNodes[myVehicle])
            setRotation(self.bestFillNodes[myVehicle], 0, math.pi, 0)
        end
        return self.bestFillNodes[myVehicle]
    else
        -- right side closer, combine approaches the trailer from the rear, driving the same direction as the getFillUnitExactFillRootNode
        return fillRootNode
    end
end

---@param fieldPolygon Polygon the field boundary. We'll look for targets on this field, or close to the boundary.
---@param myVehicle table to find the target closest to myVehicle, for logging, to exclude targets attached to this vehicle
---@param implementWithPipe table
---@param objectWithPipeAttributes PipeController any object, usually a PipeController which has pipe offset attributes
---@param bestTrailer table|nil optional trailer object to use, will find one if nil
---@param fillRootNode number|nil optional fill node for the trailer, must not be nil if bestTrailer is not nil
function SelfUnloadHelper:getTargetParameters(fieldPolygon, myVehicle, implementWithPipe, objectWithPipeAttributes,
                                              bestTrailer, fillRootNode)

    if not bestTrailer then
        -- no trailer passed in, let's find one
        bestTrailer, fillRootNode = SelfUnloadHelper:findBestTrailer(fieldPolygon, 
            myVehicle, implementWithPipe,
            objectWithPipeAttributes.pipeOffsetX)
        if not bestTrailer then
            return nil
        end
    end

    local targetNode = fillRootNode or bestTrailer.rootNode
    local trailerRootNode = bestTrailer.rootNode
    local trailerLength = bestTrailer.size.length
    local trailerWidth = bestTrailer.size.width

    local _, _, dZ = localToLocal(trailerRootNode, targetNode, 0, 0, 0)

    -- this should put the pipe's end 1.6 m from the trailer's edge towards the middle (but not more than half the width
    -- of the trailer, so the pipe always stays on the side closer to the harvester. We are not aiming for
    -- the centerline of the trailer to avoid bumping into very wide trailers, we don't want to get closer
    -- than what is absolutely necessary.
    local offsetX = math.max(3.8, math.abs(objectWithPipeAttributes.pipeOffsetX)) + trailerWidth / 2 - math.min(1.6, trailerWidth / 2)
    offsetX = objectWithPipeAttributes.pipeOnLeftSide and -offsetX or offsetX
    -- arrive near the trailer alignLength meters behind the target, from there, continue straight a bit
    local _, steeringLength = AIUtil.getSteeringParameters(myVehicle)
    --- Make sure the front marker distance is also checked for large harvesters like the big potato harvester.
    local _, frontMarkerOffset = Markers.getFrontMarkerNode(myVehicle) 
    local alignLength = (trailerLength / 2) + dZ + math.max(myVehicle.size.length / 2 + frontMarkerOffset, steeringLength)
    CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, myVehicle,
            'Trailer length: %.1f, width: %.1f, dZ: %.1f, align length %.1f, my length: %.1f, steering length %.1f, offsetX %.1f, frontMarkerOffset: %.2f',
            trailerLength, trailerWidth, dZ, alignLength, 
            myVehicle.size.length, steeringLength, offsetX, frontMarkerOffset)
    return targetNode, alignLength, offsetX, bestTrailer
end

--- Check if this trailer is driven by AutoDrive and is really ready to be loaded. There may be
--- more than one AD trailer waiting, but we want to make sure we unload into the first one only,
--- the one which is ready to drive away.
function SelfUnloadHelper:isInvalidAutoDriveTarget(myVehicle, otherVehicle)
    if otherVehicle and otherVehicle.ad and otherVehicle.ad.stateModule and otherVehicle.ad.stateModule:isActive()
            and not otherVehicle.ad.drivePathModule:isTargetReached() then
        CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, myVehicle,
                '%s is an active AutoDrive vehicle but did not reach its target, ignoring', CpUtil.getName(otherVehicle))
        return true
    else
        return false
    end
end


--- Gets fill nodes of all fill units.
---@return table[]|nil Fill root nodes found 
---@return number Number of nodes found
function SelfUnloadHelper:getTrailersTargetNodes(vehicleWithTrailers)
    local targetNodes = {}
    local trailers = AIUtil.getAllChildVehiclesWithSpecialization(vehicleWithTrailers, Trailer)
    if not trailers then 
        CpUtil.debugVehicle(CpDebug.DBG_FIELDWORK, vehicleWithTrailers,'Can\'t find any trailers')
        return {}, 0
    end
    for _, trailer in pairs(trailers) do 
        for ix, _ in pairs(trailer:getFillUnits()) do 
            local node = trailer:getFillUnitExactFillRootNode(ix)
            local _, _, trailerOffset = localToLocal(node, trailer.rootNode, 0, 0, 0)
            local _, _, vehicleOffset = localToLocal(vehicleWithTrailers.rootNode, trailer.rootNode, 0, 0, 0)
            if node then 
                table.insert(targetNodes, {
                    node = node,
                    fillUnitIx = ix,
                    trailer = trailer,
                    trailerOffset = trailerOffset,
                    vehicleOffset = -vehicleOffset,
                })
            end
        end
    end
    table.sort(targetNodes, function (a, b)
        --- Sorts these nodes to make sure the front most node is the first.
        return b.vehicleOffset < a.vehicleOffset or b.vehicleOffset == a.vehicleOffset and b.trailerOffset < a.trailerOffset
    end)
    return targetNodes, #targetNodes
end
