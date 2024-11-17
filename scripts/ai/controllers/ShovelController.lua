---@class ShovelController : ImplementController
ShovelController = CpObject(ImplementController)

ShovelController.POSITIONS = {
    DEACTIVATED = 0, 
    LOADING = 1,
    TRANSPORT = 2,
    PRE_UNLOADING = 3,
    UNLOADING = 4,
}
ShovelController.MAX_TRIGGER_HEIGHT = 8
ShovelController.MIN_TRIGGER_HEIGHT = 1
ShovelController.TRIGGER_HEIGHT_RAYCAST_COLLISION_MASK =
    CollisionFlag.DEFAULT + CollisionFlag.STATIC_OBJECT + CollisionFlag.VEHICLE

function ShovelController:init(vehicle, implement, isConsoleCommand)
    ImplementController.init(self, vehicle, implement)
    self.shovelSpec = self.implement.spec_shovel
    self.shovelNode = ImplementUtil.getShovelNode(implement)
    self.turnOnSpec = self.implement.spec_turnOnVehicle
    self.isConsoleCommand = isConsoleCommand
    --- Sugar can unlading is still WIP
    self.isSugarCaneTrailer = self.implement.spec_trailer ~= nil
    self.sugarCaneTrailer = {
        isDischargeActive = false,
        isDischargingTimer = CpTemporaryObject(false),
        movingTool = nil,
        isMovingToolDirty = false,
        isDischargingToGround = false
    }
    if self.isSugarCaneTrailer then 
        --- Find the moving tool for the sugar cane trailer
        for i, tool in pairs(implement.cylindered.movingTools) do 
            if tool.axis then 
                self.sugarCaneTrailer.movingTool = tool
            end
        end
    end
end

function ShovelController:getDriveData()
	local maxSpeed
    if self.isSugarCaneTrailer then
        --- Sugar cane trailer discharge
        if self.sugarCaneTrailer.isDischargeActive then
            if self.sugarCaneTrailer.isDischargingTimer:get() then
                --- Waiting until the discharging stopped or 
                --- the trailer is empty
                maxSpeed = 0
                self:debugSparse("Waiting for unloading!")
            end
            
            -- if self.trailerSpec.tipState == Trailer.TIPSTATE_OPENING then 
            --     --- Trailer not yet ready to unload.
            --     maxSpeed = 0
            --     self:debugSparse("Waiting for trailer animation opening!")
            -- end
            if self:isEmpty() then  
                --- Waiting for the trailer animation to finish.
                maxSpeed = 0
                self:debugSparse("Waiting for trailer animation closing!")
            end
        else 
            -- ImplementUtil.moveMovingToolToRotation(self.implement, 
            --     self.sugarCaneTrailerMovingTool, dt , )
        end
    end
	return nil, nil, nil, maxSpeed
end

function ShovelController:update(dt)
    if self.isSugarCaneTrailer then
        --- Sugar cane trailer discharge
        if self.sugarCaneTrailer.isDischargeActive then
            if self:isEmpty() then 
                self:finishedSugarCaneTrailerDischarge()
            end
            if self.implement:getCanDischargeToGround(self.dischargeData.dischargeNode) then 
                --- Update discharge timer
                self.sugarCaneTrailer.isDischargingTimer:set(true, 500)
                if not self:isDischarging() then 
                    -- self.implement:setDischargeState(Dischargeable.DISCHARGE_STATE_GROUND)
                end
            end
            -- ImplementUtil.moveMovingToolToRotation(self.implement, 
            --     self.sugarCaneTrailerMovingTool, dt , )
        else 
            -- ImplementUtil.moveMovingToolToRotation(self.implement, 
            --     self.sugarCaneTrailerMovingTool, dt , )
        end
    end
end

function ShovelController:getShovelNode()
	return self.shovelNode.node
end

function ShovelController:isFull()
    return self:getFillLevelPercentage() >= 99
end

function ShovelController:isEmpty()
    return self:getFillLevelPercentage() <= 1
end

function ShovelController:getFillLevelPercentage()
    return self.implement:getFillUnitFillLevelPercentage(self.shovelNode.fillUnitIndex) * 100
end

function ShovelController:isTiltedForUnloading()
    return self.implement:getShovelTipFactor() >= 0
end

function ShovelController:isUnloading()
    return self:isTiltedForUnloading() and self.implement:getDischargeState() ~= Dischargeable.DISCHARGE_STATE_OFF
end

--- Gets current loading fill type.
function ShovelController:getShovelFillType()
    return self.shovelSpec.loadingFillType
end

function ShovelController:getDischargeFillType()
    return self.implement:getDischargeFillType(self:getDischargeNode())
end

function ShovelController:getDischargeNode()
    return self.implement:getCurrentDischargeNode()
end

--- Checks if the shovel raycast has found an unload target.
---@param targetTrigger CpTrigger|nil
---@return boolean
function ShovelController:canDischarge(targetTrigger)
    local dischargeNode = self:getDischargeNode()
    local spec = self.implement.spec_dischargeable
	if not spec.isAsyncRaycastActive then
        local oldNode = dischargeNode.raycast.node
        dischargeNode.raycast.node = self.implement.spec_attachable.attacherJoint.node
		self.implement:updateRaycast(dischargeNode)
        dischargeNode.raycast.node = oldNode
	end
    if targetTrigger and targetTrigger:getTrigger() ~= self.implement:getDischargeTargetObject(dischargeNode) then 
        return false
    end
    return dischargeNode.dischargeHit
end

--- Is the shovel node over the trailer?
---@param refNode number
---@param margin number|nil
---@return boolean
function ShovelController:isShovelOverTrailer(refNode, margin)
    local node = self:getShovelNode()
    local _, _, distShovelToRoot = localToLocal(node, self.implement.rootVehicle:getAIDirectionNode(), 0, 0, 0)
    local _, _, distTrailerToRoot = localToLocal(refNode, self.implement.rootVehicle:getAIDirectionNode(), 0, 0, 0)
    margin = margin or 0
    if self:isHighDumpShovel() then 
        margin = margin + 1
    end
    return ( distTrailerToRoot - distShovelToRoot ) < margin
end

function ShovelController:isHighDumpShovel()
    return g_vehicleConfigurations:get(self.implement, "shovelMovingToolIx") ~= nil
end

function ShovelController:setMinimalUnloadingHeight(height)
    self.implement:setCpShovelMinimalUnloadHeight(height)
end

--- Calculates the minimal unloading height for the trigger.
---@param triggerNode number|nil
---@return boolean
function ShovelController:calculateMinimalUnloadingHeight(triggerNode)
    local sx, sy, sz = getWorldTranslation(self.vehicle:getAIDirectionNode())
    local tx, ty, tz
    if triggerNode then 
        tx, ty, tz = getWorldTranslation(triggerNode)
    else
        local dirX, _, dirZ = localDirectionToWorld(self.vehicle:getAIDirectionNode(), 0, 0, 1)
        local _, frontMarkerDistance = Markers.getFrontMarkerNode(self.vehicle)
        tx, ty, tz = sx + dirX * (frontMarkerDistance + 4), sy, sz + dirZ * (frontMarkerDistance + 4)
    end
    local length = MathUtil.vector2Length(tx - sx, tz - sz) + 0.25
    local dx, dy, dz = tx - sx, ty - sy, tz -sz
    local _, terrainHeight, _ = getWorldTranslation(self.vehicle.rootNode)
    local maxHeightObjectHit = 0
    for i=self.MIN_TRIGGER_HEIGHT, self.MAX_TRIGGER_HEIGHT, 0.1 do 
        self.objectWasHit = false
        raycastAll(sx, terrainHeight + i, sz,  dx, 0, dz, length
            "calculateMinimalUnloadingHeightRaycastCallback", self, 
            self.TRIGGER_HEIGHT_RAYCAST_COLLISION_MASK)
        if self.objectWasHit then 
            maxHeightObjectHit = i
        end
    end
    if maxHeightObjectHit > 0 then 
        self:debug("Finished raycast with minimal height: %.2f", maxHeightObjectHit)
        self.implement:setCpShovelMinimalUnloadHeight(maxHeightObjectHit + 0.5)
        return true
    end
    self:debug("Could not find a valid minimal height, so we use the maximum: %.2f", self.MAX_TRIGGER_HEIGHT)
    self.implement:setCpShovelMinimalUnloadHeight(self.MAX_TRIGGER_HEIGHT)
    return false
end

--- Callback checks if an object was hit.
function ShovelController:calculateMinimalUnloadingHeightRaycastCallback(hitObjectId, x, y, z, distance, nx, ny, nz, subShapeIndex, shapeId, isLast)
    if hitObjectId then 
        local object = g_currentMission.nodeToObject[hitObjectId]
        if object then 
            if object ~= self.vehicle and object ~= self.implement then 
                self:debug("Object: %s was hit!", CpUtil.getName(object))
                self.objectWasHit = true
                return true
            end
        else 
            self:debug("Shape was hit!")
            self.objectWasHit = true
            return true
        end
        return false
    end
    return false
end

function ShovelController:delete()
    if self.implement.cpResetShovelState then
        self.implement:cpResetShovelState()
    end
end

--- Applies the given shovel position and 
--- enables shovels that need an activation for unloading.
---@param pos number shovel position 1-4
---@return boolean reached? 
function ShovelController:moveShovelToPosition(pos)
    if self.turnOnSpec then
        if pos == ShovelController.POSITIONS.UNLOADING then 
            if not self.implement:getIsTurnedOn() and self.implement:getCanBeTurnedOn() then 
                self.implement:setIsTurnedOn(true)
                self:debug("Turning on the shovel.")
            end
            if not self.implement:getDischargeState() ~= Dischargeable.DISCHARGE_STATE_OBJECT then
                self.implement:setDischargeState(Dischargeable.DISCHARGE_STATE_OBJECT)
            end
            return false
        else
            if self.implement:getIsTurnedOn() then 
                self.implement:setIsTurnedOn(false)
                self:debug("turning off the shovel.")
            end
        end
    end
    if self.implement.cpSetShovelState == nil then 
        return false
    end
    self.implement:cpSetShovelState(pos)
    return self.implement:areCpShovelPositionsDirty()
end

--------------------------------------------
--- WIP! Sugar cane trailer functions
--------------------------------------------

--- Gets the dischargeNode and offset from a selected tip side.
---@param tipSideID number
---@param isTippingToGroundNeeded boolean
---@return table|nil dischargeNodeIndex
---@return table|nil dischargeNode
---@return number|nil xOffset 
function ShovelController:getDischargeNodeAndOffsetForTipSide(tipSideID, isTippingToGroundNeeded)
    local dischargeNode = self:getDischargeNode()
    return dischargeNode.index, dischargeNode, self:getDischargeXOffset(dischargeNode)
end

--- Gets the x offset of the discharge node relative to the implement root.
function ShovelController:getDischargeXOffset(dischargeNode)
    local node = dischargeNode.node
    local xOffset, _ ,_ = localToLocal(node, self.implement.rootNode, 0, 0, 0)
    return xOffset
end

--- Starts AI Discharge to an object/trailer.
---@param dischargeNode table discharge node to use.
---@return boolean success
function ShovelController:startDischarge(dischargeNode)
    self.sugarCaneTrailer.isDischargeActive = true
    return true
end

--- Starts discharging to the ground if possible.
function ShovelController:startDischargeToGround(dischargeNode)
    self.sugarCaneTrailer.isDischargeActive = true
    self.sugarCaneTrailer.isDischargingToGround = true
    -- self.isDischargingToGround = true
    -- self.dischargeData = {
    --     dischargeNode = dischargeNode,
    -- }
	-- local tipSide = self.trailerSpec.dischargeNodeIndexToTipSide[dischargeNode.index]
	-- if tipSide ~= nil then
	-- 	self.implement:setPreferedTipSide(tipSide.index)
	-- end
    return true
end

--- Callback for the drive strategy, when the unloading finished.
function ShovelController:setFinishDischargeCallback(finishDischargeCallback)
    self.sugarCaneTrailer.finishDischargeCallback = finishDischargeCallback
end

--- Callback for ai discharge.
function ShovelController:finishedSugarCaneTrailerDischarge()
    self:debug("Finished unloading.")
    if self.sugarCaneTrailer.finishDischargeCallback then 
        self.sugarCaneTrailer.finishDischargeCallback(self.driveStrategy, self)
    end
    self.sugarCaneTrailer.isDischargeActive = false
    self.sugarCaneTrailer.isDischargingToGround = false
end

function ShovelController:prepareForUnload()
    return true
end

function ShovelController:isDischarging()
    return self.implement:getDischargeState() ~= Dischargeable.DISCHARGE_STATE_OFF
end

--- Gets the discharge node z offset relative to the root vehicle direction node.
function ShovelController:getUnloadOffsetZ(dischargeNode)
    local node = dischargeNode.node
    local dist = ImplementUtil.getDistanceToImplementNode(self.vehicle:getAIDirectionNode(), 
        self.implement, node)
    return dist
end

--------------------------------------------
--- Debug functions
--------------------------------------------

function ShovelController:printShovelDebug()
    self:debug("--Shovel Debug--")
    if self.shovelNode then
        self:debug("Fill unit index: %d, max pickup angle: %.2f, width: %.2f", 
            self.shovelNode.fillUnitIndex, 
            math.deg(self.shovelNode.maxPickupAngle),
            self.shovelNode.width)
        if self.shovelNode.movingToolActivation then
            self:debug("Has moving tool activation => open factor: %.2f, inverted: %s", 
                self.shovelNode.movingToolActivation.openFactor, 
                tostring(self.shovelNode.movingToolActivation.isInverted))
        end
        if self.shovelSpec.shovelDischargeInfo.node then
            self:debug("min angle: %.2f, max angle: %.2f", 
                math.deg(self.shovelSpec.shovelDischargeInfo.minSpeedAngle), 
                math.deg(self.shovelSpec.shovelDischargeInfo.maxSpeedAngle))
        end
    end
    self:debug("--Shovel Debug finished--")
end

function ShovelController:debug(...)
    if self.isConsoleCommand then
        --- Ignore vehicle debug setting, if the pipe controller was created by a console command.
        self:info(...)
        return
    end
    ImplementController.debug(self, ...)    
end