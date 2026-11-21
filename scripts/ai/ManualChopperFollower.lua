--- Live following of a manually driven forage harvester. No predicted turn course is required.
---@class ManualChopperFollower
ManualChopperFollower = CpObject()

--- Keep a short, distance-sampled history of the actual forward movement.
function ManualChopperFollower.recordPosition(proxy)
    if proxy:isReversing() then
        proxy.chopperTrail = nil
        return
    end
    local node = proxy.vehicle:getAIDirectionNode()
    local x, _, z = getWorldTranslation(node)
    local dx, _, dz = localDirectionToWorld(node, 0, 0, 1)
    local directionLength = MathUtil.vector2Length(dx,dz)
    if directionLength < 0.001 then return end
    dx, dz = dx/directionLength, dz/directionLength
    local trail = proxy.chopperTrail or {}
    local previous = trail[#trail]
    local distance = previous and MathUtil.vector2Length(x - previous.x, z - previous.z) or 0
    if previous and distance < 0.5 then return end
    if distance > 30 then trail, previous = {}, nil end
    local progress = previous and previous.progress + distance or 0
    local curvature = 0
    if previous and distance > 0 then
        local anchor = trail[math.max(1,#trail-3)]
        curvature = math.atan2(dx * anchor.dz - dz * anchor.dx, dx * anchor.dx + dz * anchor.dz) / (progress-anchor.progress)
    end
    table.insert(trail, {x=x,z=z,dx=dx,dz=dz,progress=progress,curvature=curvature})
    while #trail > 2 and progress - trail[2].progress > 150 do table.remove(trail, 1) end
    proxy.chopperTrail = trail
end

function ManualChopperFollower:getGuidePosition(progress, offset)
    local trail = self.proxy.chopperTrail
    local first, last = trail[1], trail[#trail]
    local x, z, dx, dz
    if progress <= first.progress then
        dx, dz = first.dx, first.dz
        x, z = first.x + dx * (progress - first.progress), first.z + dz * (progress - first.progress)
    elseif progress >= last.progress then
        dx, dz = last.dx, last.dz
        local distance = progress - last.progress
        local curvature = last.curvature
        if math.abs(curvature) > 0.001 then
            -- A short continuation of the measured curvature gives a leading tractor
            -- a usable steering target while its trailer is beside the harvester.
            local curvedDistance = math.min(distance, 12)
            local startAngle = math.atan2(dx,dz)
            local angle = startAngle + curvature*curvedDistance
            x = last.x + (math.cos(startAngle)-math.cos(angle))/curvature
            z = last.z + (math.sin(angle)-math.sin(startAngle))/curvature
            dx,dz = math.sin(angle),math.cos(angle)
            x,z = x+dx*(distance-curvedDistance),z+dz*(distance-curvedDistance)
        else
            x, z = last.x + dx * distance, last.z + dz * distance
        end
    else
        for i=2,#trail do
            local a, b = trail[i-1], trail[i]
            if progress <= b.progress then
                local fraction = (progress - a.progress) / (b.progress - a.progress)
                x, z = a.x + fraction * (b.x - a.x), a.z + fraction * (b.z - a.z)
                dx, dz = a.dx + fraction * (b.dx - a.dx), a.dz + fraction * (b.dz - a.dz)
                local length = MathUtil.vector2Length(dx, dz)
                if length < 0.001 then
                    dx, dz = b.dx, b.dz
                else
                    dx, dz = dx / length, dz / length
                end
                break
            end
        end
    end
    return x + dz * offset, z - dx * offset, dx, dz
end

function ManualChopperFollower:projectOnGuide(node, previousProjection)
    local trail = self.proxy.chopperTrail
    local x, _, z = getWorldTranslation(node)
    local bestDistance, bestProgress, bestOffset = math.huge, 0, 0
    local previousX, previousZ = self:getGuidePosition(trail[1].progress - 40, 0)
    local previousProgress = trail[1].progress - 40
    for i=1,#trail+20 do
        local progress = i <= #trail and trail[i].progress or trail[#trail].progress + (i-#trail)*2
        local nextX, nextZ
        if i <= #trail then
            nextX, nextZ = trail[i].x, trail[i].z
        else
            nextX, nextZ = self:getGuidePosition(progress, 0)
        end
        local dx, dz = nextX - previousX, nextZ - previousZ
        local lengthSquared = dx * dx + dz * dz
        local fraction = CpMathUtil.clamp(((x-previousX)*dx + (z-previousZ)*dz) / lengthSquared, 0, 1)
        local px, pz = previousX + fraction*dx, previousZ + fraction*dz
        local distance = (x-px)^2 + (z-pz)^2
        local candidateProgress = previousProgress + fraction * (progress - previousProgress)
        if distance < bestDistance and (not previousProjection or math.abs(candidateProgress-previousProjection) <= 12) then
            local length = math.sqrt(lengthSquared)
            bestDistance, bestProgress = distance, candidateProgress
            bestOffset = ((x-px)*dz - (z-pz)*dx) / length
        end
        previousX, previousZ, previousProgress = nextX, nextZ, progress
    end
    if bestDistance == math.huge and previousProjection then return self:projectOnGuide(node) end
    return bestProgress, bestOffset
end

function ManualChopperFollower:isInsideTightTurn(side, offset)
    local trail = self.proxy.chopperTrail
    local curvature = trail and trail[#trail].curvature or 0
    offset = offset or self:getSideOffset(side)
    return offset * curvature > 0.001 and
        1 / math.abs(curvature) - math.abs(offset) < (self.strategy.turningRadius or 6)
end

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
    local width = AIUtil.getWidth(self.proxy.vehicle)
    for _, implement in pairs(self.proxy.vehicle:getChildVehicles()) do
        width = math.max(width, AIUtil.getWidth(implement))
    end
    return side * ((width + self:getVehicleWidth()) / 2 + 1)
end

--- Assigned-harvester sensor hits may be beside the tractor in an inside curve.
--- Ignore those hits only when all vehicle and implement footprints remain separate.
function ManualChopperFollower:hasHarvesterClearance()
    local function box(object)
        local size = object.size
        if not size or not size.width or not size.length or size.width <= 0 or size.length <= 0 or not object.rootNode then return end
        local x, _, z = localToWorld(object.rootNode, 0, 0, size.lengthOffset or 0)
        local dx, _, dz = localDirectionToWorld(object.rootNode, 0, 0, 1)
        local length = MathUtil.vector2Length(dx, dz)
        if length < 0.001 then return end
        return {x=x,z=z,dx=dx/length,dz=dz/length,width=size.width/2,length=size.length/2}
    end
    local function separated(a,b)
        for _, axis in ipairs({{a.dx,a.dz},{a.dz,-a.dx},{b.dx,b.dz},{b.dz,-b.dx}}) do
            local x,z = axis[1],axis[2]
            local radiusA = a.length*math.abs(a.dx*x+a.dz*z) + a.width*math.abs(a.dz*x-a.dx*z)
            local radiusB = b.length*math.abs(b.dx*x+b.dz*z) + b.width*math.abs(b.dz*x-b.dx*z)
            if math.abs((a.x-b.x)*x+(a.z-b.z)*z) > radiusA+radiusB+0.5 then return true end
        end
        return false
    end
    local ownVehicles = self.strategy.vehicle:getChildVehicles()
    local otherVehicles = self.proxy.vehicle:getChildVehicles()
    if not next(ownVehicles) or not next(otherVehicles) then return false end
    for _, own in pairs(ownVehicles) do
        local a = box(own)
        if not a then return false end
        for _, other in pairs(otherVehicles) do
            local b = box(other)
            if not b or not separated(a,b) then return false end
        end
    end
    return true
end

function ManualChopperFollower:getRequestedSide(rearZ)
    local settings = self.proxy.vehicle:getCpSettings()
    local requested = settings.manualChopperSide and settings.manualChopperSide:getValue() or 0
    if requested == 2 then return 0 end
    local left, right = self.proxy:getFruitAtSides()
    local leftClear = left ~= nil and left == 0 and not self:isInsideTightTurn(1) and
        self:isCorridorClear(self:getSideOffset(1), rearZ, self:getSideOffset(1), 6)
    local rightClear = right ~= nil and right == 0 and not self:isInsideTightTurn(-1) and
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

function ManualChopperFollower:hold(recheck)
    local strategy, proxy = self.strategy, self.proxy
    strategy:setMaxSpeed(0)
    strategy:setInfoText(InfoTextManager.MANUAL_CHOPPER_WAITING)
    if not recheck or proxy:isReversing() or not proxy:isReadyToUnload() then
        self.waitingSince = nil
        return false
    end
    self.waitingSince = self.waitingSince or g_time
    if g_time - self.waitingSince < 3000 or g_time < (strategy.manualChopperReapproachAfter or 0) then return false end
    -- Reuse the normal assignment/pathfinding flow only once there is room for an approach.
    local x, _, z = localToLocal(Markers.getFrontMarkerNode(strategy.vehicle), proxy.vehicle:getAIDirectionNode(), 0, 0, 0)
    if MathUtil.vector2Length(x, z) <= 25 then return false end
    strategy.manualChopperReapproachAfter = g_time + 15000
    self.waitingSince = nil
    strategy:debugSparse('Manual chopper: waiting, releasing assignment for a fresh approach')
    strategy:startWaitingForSomethingToDo()
    return true
end

--- The normal steering reference follows a live parallel line. Speed controls longitudinal spacing.
function ManualChopperFollower:getDriveData()
    local strategy, proxy = self.strategy, self.proxy
    ManualChopperFollower.recordPosition(proxy)
    local reference = proxy.vehicle:getAIDirectionNode()
    local front = Markers.getFrontMarkerNode(strategy.vehicle)
    local x, _, z = localToLocal(front, reference, 0, 0, 0)
    local rearZ = -proxy:getMeasuredBackDistance() - 2
    local lookahead = math.min(6, strategy.ppc:getNormalLookaheadDistance())
    local gx, _, gz = localToWorld(reference, x, 0, z + lookahead)
    strategy:clearInfoText(InfoTextManager.MANUAL_CHOPPER_WAITING)
    if proxy:isReversing() or not proxy.chopperTrail then
        self:hold()
        return gx, gz
    end
    if self.guideTrail ~= proxy.chopperTrail then
        self.guideTrail = proxy.chopperTrail
        self.lastGuideProgress = nil
    end
    local progress, lateral = self:projectOnGuide(strategy.vehicle:getAIDirectionNode(), self.lastGuideProgress)
    self.lastGuideProgress = progress
    local frontProgress = self:projectOnGuide(front)
    local headProgress = proxy.chopperTrail[#proxy.chopperTrail].progress
    self:updateSide(rearZ)

    -- Compare with the recorded track at the tractor, not the harvester's newer heading.
    local _, _, guideDX, guideDZ = self:getGuidePosition(progress + lookahead / 2, 0)
    local tractorDX, _, tractorDZ = localDirectionToWorld(strategy.vehicle:getAIDirectionNode(), 0, 0, 1)
    local aligned = tractorDX * guideDX + tractorDZ * guideDZ >= math.cos(math.rad(45))
    if not proxy:isReadyToUnload() or not aligned then
        if self:hold(true) then return end
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
            self.trailerTrim = 0
        end
    elseif self.phase == 'ALIGN' then
        targetX, targetZ = self:getSideOffset(self.side), self.side == 0 and rearZ or 0
        if math.abs(x - targetX) < 0.5 then self.phase = 'FOLLOW' end
    end

    local fillProgress
    if self.phase == 'FOLLOW' and self.side ~= 0 then
        local target = strategy:getBestTargetNode()
        if target then
            fillProgress = self:projectOnGuide(target.node)
            -- Derive the tractor's curve radius from the actual fill-node offset.
            -- A long trailer cannot follow the same radius as the steering reference.
            local fillX, _, fillZ = localToLocal(target.node, strategy.vehicle:getAIDirectionNode(), 0, 0, 0)
            local offset = self:getSideOffset(self.side)
            local rootOffset = offset-fillX
            local curvature = proxy.chopperTrail[#proxy.chopperTrail].curvature
            if math.abs(curvature) > 0.001 then
                local radius = 1/curvature
                local radiusSquared = (radius-offset)^2-fillZ^2
                if radiusSquared <= 0 then
                    self.targetSide, self.phase = 0, 'FALL_BACK'
                    self:hold()
                    return gx,gz
                end
                rootOffset = radius-fillX-(curvature>0 and 1 or -1)*math.sqrt(radiusSquared)
            end
            local observedTrim = CpMathUtil.clamp(rootOffset-offset,-6,6)
            local elapsed = self.lastTrimUpdate and math.min(0.5,(g_time-self.lastTrimUpdate)/1000) or 0
            self.trailerTrim = (self.trailerTrim or 0) + (observedTrim-(self.trailerTrim or 0))*elapsed/(0.75+elapsed)
            self.lastTrimUpdate = g_time
            targetX = offset + self.trailerTrim
        end
    end

    -- If the current side becomes blocked, retreat first. Never sweep sideways through the harvester.
    if self.phase == 'FOLLOW' and self.side ~= 0 and
            (self:isInsideTightTurn(self.side, targetX) or not self:isCorridorClear(targetX, z, targetX, z + lookahead)) then
        self.targetSide = 0
        self.phase = 'FALL_BACK'
        self:hold()
        return gx, gz
    end
    local goalOffset = lateral + CpMathUtil.clamp(targetX - lateral, -lookahead / 2, lookahead / 2)
    gx, gz = self:getGuidePosition(progress + lookahead, goalOffset)
    local goalLocalX, _, goalLocalZ = worldToLocal(reference, gx, 0, gz)
    if not self:isCorridorClear(x, z, goalLocalX, goalLocalZ) then
        if self:hold(true) then return end
        return gx, gz
    end
    local combineSpeed = math.abs(proxy.vehicle.lastSpeedReal or 0) * 3600
    local longitudinalError = headProgress + targetZ - frontProgress
    if self.phase == 'FOLLOW' and self.side ~= 0 then
        -- Beside the harvester, align the actual trailer fill node with the pipe.
        -- Behind it, retain the rear clearance even when a long trailer is out of reach.
        if fillProgress then
            local _, pipeZ = strategy:getPipeOffset(proxy.vehicle)
            longitudinalError = headProgress + pipeZ - fillProgress
        else
            longitudinalError = strategy:getBestTargetNodeDistanceFromPipe() or longitudinalError
        end
    end
    local beforeX, beforeZ = self:getGuidePosition(progress - 0.5, targetX)
    local afterX, afterZ = self:getGuidePosition(progress + 0.5, targetX)
    local curveFactor = CpMathUtil.clamp(MathUtil.vector2Length(afterX-beforeX,afterZ-beforeZ), 0.4, 1.5)
    local correction = CpMathUtil.clamp(longitudinalError * 2.5, -combineSpeed, 12)
    local speed = math.max(0, combineSpeed * curveFactor + correction)
    if self.phase == 'FOLLOW' and self.side == 0 and longitudinalError < -1 then speed = 0 end
    if self.phase ~= 'FOLLOW' then speed = math.min(speed, strategy.settings.turnSpeed:getValue()) end
    local distance, frontVehicle = strategy.proximityController:checkBlockingVehicleFront()
    local followDistance, followVehicle = strategy.followModeProximitySensor:getClosestObjectDistanceAndRootVehicle()
    if (frontVehicle == proxy.vehicle or followVehicle == proxy.vehicle) and self:hasHarvesterClearance() then
        if frontVehicle == proxy.vehicle then distance = math.huge end
        if followVehicle == proxy.vehicle then followDistance = math.huge end
    end
    distance = math.min(distance, followDistance)
    speed = math.min(speed, math.max(0, (distance - 2) * 2))
    -- Approach a stopped machine at walking speed, retaining the same clearance target.
    if combineSpeed < 0.5 then
        local approachLimit = math.abs(longitudinalError) > 4 and 8 or 4
        speed = math.min(speed, approachLimit, math.max(0, longitudinalError * 2.5))
    end
    if speed <= 0 and combineSpeed >= 0.5 and longitudinalError > 1 then
        if self:hold(true) then return end
    else
        self.waitingSince = nil
    end
    strategy:setMaxSpeed(math.min(speed, strategy.settings.fieldSpeed:getValue()))
    strategy:debugSparse('Manual chopper: %s side=%d error=%.1f speed=%.1f front=%.1f follow=%.1f',
        self.phase, self.side, longitudinalError, strategy.maxSpeed or speed, distance, followDistance)
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
