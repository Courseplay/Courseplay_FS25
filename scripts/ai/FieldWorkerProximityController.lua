--- The purpose of the FieldWorkerProximityController is to make sure a vehicle operating on
--- a field does not bump into another vehicle working on the same field, using the same
--- field work course.
FieldWorkerProximityController = CpObject()

-- How many meters between the points of the trail
FieldWorkerProximityController.trailSpacing = 5
-- Other vehicles are considered as long as their direction is within sameDirectionLimit (radians)
-- of the own vehicle
FieldWorkerProximityController.sameDirectionLimit = math.rad(45)
-- Other vehicles are considered only as long as the lateral distance to them is less than
-- lateralDistanceLimit * working width
FieldWorkerProximityController.lateralDistanceLimit = 1.1

function FieldWorkerProximityController:init(vehicle, workingWidth)
    self.vehicle = vehicle
    self.workingWidth = workingWidth
    self.fieldWorkCourse = self.vehicle:getFieldWorkCourse()
    ---@type Waypoint[]
    self.trail = {}
    -- we use a moving average for slowing down to avoid that sudden, temporary lows in distance immediately
    -- stop a the vehicle. Such a temporary low can happen for instance when a vehicle is turning and during
    -- the turn it has momentarily the same direction as a waypoint in the following vehicle's trail, and
    -- that waypoint is also now within the lateralDistanceLimit (as the first vehicle is not parallel to the row)
    self.slowDownFactor = MovingAverage(10)
end

function FieldWorkerProximityController:debug(...)
    CpUtil.debugVehicle(CpDebug.DBG_TRAFFIC, self.vehicle, 'FieldWorkerProximityController: '.. string.format(...))
end

function FieldWorkerProximityController:debugSparse(...)
    -- since we are not called on every loop (maybe every 4th) use a prime number which should
    -- make sure that we are called once in a while
    if g_updateLoopIndex % 19 == 0 then
        self:debug(...)
    end
end

function FieldWorkerProximityController:info(...)
    CpUtil.infoVehicle(self.vehicle, ...)
end

function FieldWorkerProximityController:draw()
    if CpDebug:isChannelActive(CpDebug.DBG_TRAFFIC, self.vehicle) then
        for i, p in ipairs(self.trail) do
            local x, y, z = p:getPosition()
            Utils.renderTextAtWorldPosition(x, y + 2.2, z,
                    string.format('%d', self:getDistanceAtIx(i)), getCorrectTextSize(0.012), 0)
            if p.distance then
                Utils.renderTextAtWorldPosition(x, y + 2.5, z,
                        string.format('(%.1f)', p.distance), getCorrectTextSize(0.012), 0, { 1, 0.3, 0, 1 })
            end
            DebugUtil.drawDebugLine(x, y + 1.5, z, x, y + 2, z, 0, 0, 1)
        end
    end
end

--- Distance of the ix-th trail point from the vehicle
function FieldWorkerProximityController:getDistanceAtIx(ix)
    return (#self.trail - ix) * self.trailSpacing
end

function FieldWorkerProximityController:hasSameCourse(otherVehicle)
    local otherCourse = otherVehicle.getFieldWorkCourse and otherVehicle:getFieldWorkCourse()
    return otherCourse and
            otherCourse:getName() == self.fieldWorkCourse:getName() and
            otherCourse:getMultiTools() == self.fieldWorkCourse:getMultiTools()
end

function FieldWorkerProximityController:getTrailLength()
    return self:getDistanceAt(1)
end

--- Each vehicle leaves a trail consisting of its past positions in regular intervals
---@param maxLength number maximum length of the trail
function FieldWorkerProximityController:updateTrail(maxLength)

    if AIUtil.isReversing(self.vehicle) then
        -- when reversing we don't want to shorten our trail (by adding a new point and removing the last one)
        -- as in fact, we are moving closer to the last trail point, and this will let followers too close to us
        -- for instance in case of a turn maneuver with reversing
        self:debugSparse('Reversing, not recording trail point')
        return
    end

    local x, y, z = getWorldTranslation(self.vehicle.rootNode)
    local dTraveled = #self.trail > 0 and self.trail[#self.trail]:getDistanceFromPoint(x, z) or self.trailSpacing
    if dTraveled < self.trailSpacing then return end
    -- time to record a new point
    local _, yRot, _ = getWorldRotation(self.vehicle.rootNode)
    table.insert(self.trail, Waypoint({x = x, y = y, z = z, yRot = yRot}))
    self:debug('Recorded new trail point (%d)', #self.trail)
    local numberOfPoints = math.floor(maxLength / self.trailSpacing)
    while #self.trail > numberOfPoints do
        table.remove(self.trail, 1)
    end
end

--- How far is node behind us? We use our trail to figure this distance out, node is in our proximity if it
--- is anywhere within lateralDistanceLimit * workWidth our trail, provided the trail point direction is more or less the node's
--- direction.
function FieldWorkerProximityController:getFieldWorkProximity(node)
    local minDistance = math.huge
    for i = #self.trail, 1, -1 do
        local p = self.trail[i]
        local dx, _, dz = worldToLocal(node, p.x, p.y, p.z)
        local _, yRot, _ = getWorldRotation(node)
        -- we only check along the trail, in front of us, so dz > 0 but less than the length of the trail
        -- also, it is in the adjacent row, so dx is limited by the working width
        -- and finally, it needs to point into the same direction (approximately) to filter out a trail in
        -- the opposite direction
        --self:debug('%d: %.1f %.1f/%.1f %.1f (%.1f)', i, distance, dx, dz, math.deg(yRot - p.yRot), trailLength)
        if dz < self.trailSpacing and dz > 0 and math.abs(dx) < self.lateralDistanceLimit * self.workingWidth and
                math.abs(yRot - p.yRot) < self.sameDirectionLimit then
            local thisDistance = self:getDistanceAtIx(i) + dz
            if thisDistance < minDistance then
                -- just for debug paint purposes, we show where node is closest to the trail
                minDistance = thisDistance
                p.distance = thisDistance
            end
            --self:debug('   %.1f', self:getDistanceAtIx(i) + dz)
        else
            p.distance = nil
        end
    end
    return minDistance
end

--- Limit our speed if there are vehicles in front of us in the same or adjacent row
function FieldWorkerProximityController:getMaxSpeed(distanceLimit, currentMaxSpeed)
    local minDistanceFromOthers = math.huge
    -- our trail should be long enough for everyone on the field, that is, at least as long as their
    -- convoy distance setting.
    local maxConvoyDistance = distanceLimit
    for _, otherVehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if otherVehicle ~= self.vehicle and self:hasSameCourse(otherVehicle) and
                otherVehicle.getIsCpFieldWorkActive and otherVehicle:getIsCpFieldWorkActive() then
            local otherStrategy = otherVehicle:getCpDriveStrategy()
            local otherIsDone = otherStrategy and otherStrategy.isDone and otherStrategy:isDone()
            --- TODO: Might be worth to have the communication between vehicle strategies
            --- moved to a specialization, so similar nil bugs as #2637 could be avoid.
            if otherStrategy and otherStrategy.getFieldWorkProximity and not otherIsDone then
                local otherConvoyDistance = otherVehicle:getCpSettings().convoyDistance:getValue()
                maxConvoyDistance = math.max(maxConvoyDistance, otherConvoyDistance)
                local distanceFromOther = otherStrategy:getFieldWorkProximity(self.vehicle.rootNode)
                self:debugSparse('have same course as %s (done %s, convoy distance %.1f), distance %.1f',
                        CpUtil.getName(otherVehicle), otherIsDone, otherConvoyDistance, distanceFromOther)
                if distanceFromOther > 0 and distanceFromOther < distanceLimit then
                    self:debugSparse('too close (%.1f m < %.1f) to %s in front of me, slowing down.',
                    distanceFromOther, distanceLimit, CpUtil.getName(otherVehicle))
                    minDistanceFromOthers = math.min(minDistanceFromOthers, distanceFromOther)
                end
            end
        end
    end

    -- update my own trail so it is long enough for everyone
    self:updateTrail(1.5 * maxConvoyDistance)

    if minDistanceFromOthers < math.huge then
        -- the closer we are, the slower we drive, but stop at half the minDistance
        self.slowDownFactor:update(math.max(0, 2 * (1 - (distanceLimit - minDistanceFromOthers + distanceLimit / 2) / distanceLimit)))
    else
        self.slowDownFactor:update(1)
    end

    local maxSpeed = currentMaxSpeed * self.slowDownFactor:get()
    -- everything low enough should be 0 so it does not trigger the Giants didNotMoveTimer (which is disabled
    -- only when the maxSpeed we return in getDriveData is exactly 0
    maxSpeed = maxSpeed > 1 and maxSpeed or 0

    if minDistanceFromOthers < math.huge then
        self:debugSparse('minimum distance to others %.1f, maximum convoy distance from others %.1f, speed = %.1f, slow down factor = %.2f',
            minDistanceFromOthers, maxConvoyDistance, maxSpeed, self.slowDownFactor:get())
    end

    return maxSpeed
end