--- Live following of a manually driven forage harvester. No predicted turn course is required.
---@class ManualChopperFollower
ManualChopperFollower = CpObject()

function ManualChopperFollower:init(strategy, proxy)
    self.strategy = strategy
    self.proxy = proxy
    self.side = 0
    self.phase = 'FOLLOW'
    self.pendingSide = nil
    self.nextSideCheck = 0
    local x = localToLocal(Markers.getFrontMarkerNode(strategy.vehicle), proxy.vehicle:getAIDirectionNode(), 0, 0, 0)
    if math.abs(x) > (AIUtil.getWidth(proxy.vehicle) + self:getVehicleWidth()) / 4 then
        self.side = x > 0 and 1 or -1
    end
end

function ManualChopperFollower:getVehicleWidth()
    local width = AIUtil.getWidth(self.strategy.vehicle)
    for _, implement in pairs(self.strategy.vehicle:getChildVehicles()) do
        width = math.max(width, AIUtil.getWidth(implement))
    end
    return width
end

--- Check a corridor rather than a single plant sample. Unknown samples are not clear ground.
function ManualChopperFollower:isCorridorClear(fromX, fromZ, toX, toZ)
    local reference = self.proxy.vehicle:getAIDirectionNode()
    local halfWidth = self:getVehicleWidth() / 2 + 0.25
    -- Density queries are expensive. Reuse nearby world-space corridors for at most 200 ms.
    if not self.corridors or g_time >= self.corridorCacheUntil then
        self.corridors = {}
        self.corridorCacheUntil = g_time + 200
    end
    local startX, _, startZ = localToWorld(reference, fromX, 0, fromZ)
    local endX, _, endZ = localToWorld(reference, toX, 0, toZ)
    local key = string.format('%d:%d:%d:%d:%.2f', math.floor(startX * 2), math.floor(startZ * 2),
        math.floor(endX * 2), math.floor(endZ * 2), halfWidth)
    if self.corridors[key] ~= nil then return self.corridors[key] end
    local function remember(clear)
        self.corridors[key] = clear
        return clear
    end
    local distance = MathUtil.vector2Length(toX - fromX, toZ - fromZ)
    local steps = math.max(1, math.ceil(distance / 2))
    for i = 0, steps do
        local fraction = i / steps
        for _, lateral in ipairs({-halfWidth, 0, halfWidth}) do
            local x, _, z = localToWorld(reference,
                fromX + fraction * (toX - fromX) + lateral, 0, fromZ + fraction * (toZ - fromZ))
            if not CpFieldUtil.isOnField(x, z) then return remember(false) end
            local fruit = PathfinderUtil.hasFruit(x, z, 0.5, 0.5)
            if fruit ~= false then return remember(false) end
        end
    end
    return remember(true)
end

function ManualChopperFollower:getSideOffset(side)
    return side * ((AIUtil.getWidth(self.proxy.vehicle) + self:getVehicleWidth()) / 2 + 1)
end

function ManualChopperFollower:getRequestedSide(rearZ)
    local settings = self.proxy.vehicle:getCpSettings()
    local requested = settings.manualChopperSide and settings.manualChopperSide:getValue() or 0
    if requested == 2 then return 0 end
    local left, right = self.proxy:getFruitAtSides()
    local leftClear = left ~= nil and left == 0 and
        self:isCorridorClear(self:getSideOffset(1), rearZ, self:getSideOffset(1), 6)
    local rightClear = right ~= nil and right == 0 and
        self:isCorridorClear(self:getSideOffset(-1), rearZ, self:getSideOffset(-1), 6)
    if requested == 1 then return leftClear and 1 or 0 end
    if requested == -1 then return rightClear and -1 or 0 end
    -- Retain a usable side, including when both sides have become clear.
    if self.side == 1 and leftClear then return 1 end
    if self.side == -1 and rightClear then return -1 end
    if leftClear and not rightClear then return 1 end
    if rightClear and not leftClear then return -1 end
    return 0
end

function ManualChopperFollower:updateSide(rearZ)
    if g_time < self.nextSideCheck then return end
    self.nextSideCheck = g_time + 500
    local requested = self:getRequestedSide(rearZ)
    if requested ~= self.pendingSide then
        self.pendingSide = requested
        self.pendingSince = g_time
    end
    if requested ~= self.side and g_time - self.pendingSince >= 2000 and self.phase == 'FOLLOW' then
        self.targetSide = requested
        self.phase = 'FALL_BACK'
    end
end

function ManualChopperFollower:hold()
    self.strategy:setMaxSpeed(0)
    self.strategy:setInfoText(InfoTextManager.MANUAL_CHOPPER_WAITING)
end

--- The normal steering reference follows a live parallel line. Speed controls longitudinal spacing.
function ManualChopperFollower:getDriveData()
    local strategy, proxy = self.strategy, self.proxy
    local reference = proxy.vehicle:getAIDirectionNode()
    local front = Markers.getFrontMarkerNode(strategy.vehicle)
    local x, _, z = localToLocal(front, reference, 0, 0, 0)
    local rearZ = -proxy:getMeasuredBackDistance() - 2
    local lookahead = math.min(6, strategy.ppc:getNormalLookaheadDistance())
    local gx, _, gz = localToWorld(reference, x, 0, z + lookahead)
    strategy:clearInfoText(InfoTextManager.MANUAL_CHOPPER_WAITING)
    self:updateSide(rearZ)

    -- A manual turn has no known endpoint. Wait when the two vehicles cease to align.
    local aligned = CpMathUtil.isSameDirection(strategy.vehicle:getAIDirectionNode(), reference, 35)
    if not aligned then
        self.unalignedSince = self.unalignedSince or g_time
        if g_time - self.unalignedSince >= 1500 and MathUtil.vector2Length(x, z) > 25 then
            -- Once there is room, use the existing pathfinder to approach the new heading.
            strategy:setMaxSpeed(0)
            strategy:startWaitingForSomethingToDo()
            return
        end
    else
        self.unalignedSince = nil
    end
    if proxy:isReversing() or not proxy:isReadyToUnload() or not aligned then
        self:hold()
        return gx, gz
    end

    local targetX = self:getSideOffset(self.side)
    local targetZ = self.side == 0 and rearZ or 0
    if self.phase == 'FALL_BACK' then
        -- Brake in the current lane until the complete tractor front clears the harvester's rear.
        self.retreatX = self.retreatX or x
        targetX, targetZ = self.retreatX, rearZ - 2
        if z <= rearZ then self.phase = 'CROSS_BEHIND' end
    end
    if self.phase == 'CROSS_BEHIND' then
        if z > rearZ then
            self.phase = 'FALL_BACK'
            self:hold()
            return gx, gz
        end
        targetX, targetZ = self:getSideOffset(self.targetSide), rearZ - 2
        if math.abs(x - targetX) < 0.5 then
            self.side = self.targetSide
            self.phase = 'ALIGN'
            self.retreatX = nil
        end
    elseif self.phase == 'ALIGN' then
        targetX, targetZ = self:getSideOffset(self.side), self.side == 0 and rearZ or 0
        if math.abs(x - targetX) < 0.5 then self.phase = 'FOLLOW' end
    end

    -- If the current side becomes blocked, retreat first. Never sweep sideways through the harvester.
    if self.phase == 'FOLLOW' and self.side ~= 0 and
            not self:isCorridorClear(targetX, z, targetX, z + lookahead) then
        self.targetSide = 0
        self.phase = 'FALL_BACK'
        self:hold()
        return gx, gz
    end
    if not self:isCorridorClear(x, z, targetX, z + lookahead) then
        self:hold()
        return gx, gz
    end
    local goalX = x + CpMathUtil.clamp(targetX - x, -lookahead / 2, lookahead / 2)
    gx, _, gz = localToWorld(reference, goalX, 0, z + lookahead)
    local combineSpeed = math.abs(proxy.vehicle.lastSpeedReal or 0) * 3600
    local longitudinalError = targetZ - z
    if self.phase == 'FOLLOW' and self.side ~= 0 and math.abs(x - targetX) < 1 then
        -- Beside the harvester, align the actual trailer fill node with the pipe.
        -- Behind it, retain the rear clearance even when a long trailer is out of reach.
        longitudinalError = strategy:getBestTargetNodeDistanceFromPipe() or longitudinalError
    end
    local correction = CpMathUtil.clamp(longitudinalError * 2, -combineSpeed, 6)
    local speed = math.max(0, combineSpeed + correction)
    if self.phase ~= 'FOLLOW' then speed = math.min(speed, strategy.settings.turnSpeed:getValue()) end
    local distance = strategy.proximityController:checkBlockingVehicleFront()
    distance = math.min(distance, strategy.followModeProximitySensor:getClosestObjectDistanceAndRootVehicle())
    speed = math.min(speed, math.max(0, (distance - 2) * 2))
    -- Approach a stopped machine at walking speed, retaining the same clearance target.
    if combineSpeed < 0.5 then
        speed = math.min(speed, 3, math.max(0, longitudinalError * 2))
    end
    strategy:setMaxSpeed(math.min(speed, strategy.settings.fieldSpeed:getValue()))
    return gx, gz
end

--- Reuse CP's trailer-aware reverse driver, but reject blocked or sharply folded combinations first.
function ManualChopperFollower:canReverse()
    local strategy = self.strategy
    local distance = strategy.proximityController:checkBlockingVehicleBack()
    if distance < 3 then return false end
    local start = strategy.manualChopperReverseStart
    if start then
        local x, _, z = getWorldTranslation(strategy.vehicle:getAIDirectionNode())
        if MathUtil.vector2Length(x - start.x, z - start.z) >= strategy.maxDistanceWhenMovingOutOfWay - 2 then
            return false
        end
    end
    local implement = AIUtil.getFirstReversingImplementWithWheels(strategy.vehicle)
    if implement then
        local trailerNode = implement.steeringAxleNode
        if not trailerNode or not CpMathUtil.isSameDirection(
                strategy.vehicle:getAIDirectionNode(), trailerNode, 40) then return false end
    end
    local reference = self.proxy.vehicle:getAIDirectionNode()
    if not CpMathUtil.isSameDirection(strategy.vehicle:getAIDirectionNode(), reference, 35) then return false end
    local x, _, z = localToLocal(strategy.vehicle:getAIDirectionNode(), reference, 0, 0, 0)
    return self:isCorridorClear(x, z, x, z - 5)
end
