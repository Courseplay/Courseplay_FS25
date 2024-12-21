--- Create a polygon representing a field in Farming Simulator.
--- We put a probe (a node) on anywhere on the field, then start moving the probe to north until we
--- find the field edge. From that point on, we trace the edge clockwise around the field.
---
--- Finally, we simplify the resulting polygon by removing unneeded vertices.
--- TODO: island detection. Currently we don't know if we found the outer edge of the field or just an island.
---
---@class FieldScanner
FieldScanner = CpObject()

---@param resolution number the resolution of the scanner in meters (scan steps).
function FieldScanner:init(resolution)
    -- minimum practical resolution depends on how many meters a pixel in the density map really is, I'm not
    -- sure if it is 1 or 0.5, so 0.2 seems to be a safe bet
    self.resolution = resolution or 0.2
    self.highResolution = 0.1
    self.normalTracerLookahead = 5.0
    self.shortTracerLookahead = self.normalTracerLookahead / 10
    self.angleStep = self.highResolution / self.normalTracerLookahead
end

function FieldScanner:debug(...)
    CpUtil.debugVehicle(CpDebug.DBG_COURSES, CpUtil.getCurrentVehicle(), 'FieldScanner: ' .. string.format(...))
end

function FieldScanner:info(...)
    CpUtil.info('FieldScanner: ' .. string.format(...))
end


function FieldScanner:moveProbeForward(probe, d)
    local x, _, z = localToWorld(probe, 0, 0, d)
    self:setProbePosition(probe, x, z)
end

function FieldScanner:setProbePosition(probe, x, z)
    local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z)
    setTranslation(probe, x, y, z)
end

function FieldScanner:rotateProbeBy(probe, angleStep)
    local _, yRot, _ = getRotation(probe)
    setRotation(probe, 0, yRot + angleStep, 0)
end

--- Rotate the probe until it aligns with the field edge
function FieldScanner:rotateProbeInFieldEdgeDirection(probe, tracerLookahead, fieldId)
    local x, y, z = localToWorld(probe, 0, 0, tracerLookahead)
    local startOnField = CpFieldUtil.isOnField(x, z, fieldId)
    -- rotate the probe and see if a point in front of us is still on the field or not.
    local a, isOnField, targetOnFieldState = 0, startOnField, not startOnField
    -- rotate probe clockwise
    while a < 2 * math.pi and isOnField ~= targetOnFieldState do
        x, y, z = localToWorld(probe, 0, 0, tracerLookahead)
        isOnField = CpFieldUtil.isOnField(x, z, fieldId)
        self:rotateProbeBy(probe, (isOnField and 1 or -1) * self.angleStep)
        a = a + self.angleStep
    end
    local _, yRot, _ = getRotation(probe)
    return yRot
end

--- Move northwards in big steps until we pass the edge of the field, then
--- back up with small steps until we are back on the field.
--- At the end, we'll be very close to the field edge.
---@return boolean true if the edge was found
function FieldScanner:findFieldEdge(probe, fieldId)
    local i = 0
    while i < 100000 and CpFieldUtil.isNodeOnField(probe, fieldId) do
        -- move probe forward
        self:moveProbeForward(probe, self.resolution)
        i = i + 1
    end
    while not CpFieldUtil.isNodeOnField(probe, fieldId) do
        self:moveProbeForward(probe, -self.highResolution)
    end
    local x, _, z = getWorldTranslation(probe)
    self:debug('Field edge found at %.1f/%.1f after %d steps', x, z, i)
    -- rotate probe here with a very short tracer to the field edge direction to avoid hitting a neighboring field
    self:rotateProbeInFieldEdgeDirection(probe, self.shortTracerLookahead, fieldId)
end

function FieldScanner:traceFieldEdge(probe, fieldId)
    self.points = {}
    local helperNode = CpUtil.createNode('helperNode', 0, 0, 0)
    local startX, startY, startZ = getWorldTranslation(probe)
    local _, prevYRot, _ = getRotation(probe)
    table.insert(self.points, {x = startX, y = startY, z = startZ, yRot = prevYRot})
    local distanceFromStart = math.huge
    local tracerLookahead = self.normalTracerLookahead
    local totalYRot = 0
    local lost = false
    local ignoreCornerAtIx = -1
    local sharpCornerDeltaAngle = math.rad(15)
    local i = 0
    -- limit the number of iterations, also, must be close  to the start and have made almost a full circle (pi is just
    -- a half circle, but should be ok to protect us from edge cases like starting with a corner
    while i < 20000 and (i == 1 or distanceFromStart > tracerLookahead or math.abs(totalYRot) < math.pi) do
        local yRot = self:rotateProbeInFieldEdgeDirection(probe, tracerLookahead, fieldId)
        -- how much we just turned?
        local deltaYRot = yRot - (prevYRot or yRot)
        self:moveProbeForward(probe, tracerLookahead)
        if prevYRot and math.abs(deltaYRot) > sharpCornerDeltaAngle and i ~= ignoreCornerAtIx then
            -- we probably just cut a corner. Calculate where the corner exactly is and insert a point there
            -- see which way the edge goes here
            yRot = self:rotateProbeInFieldEdgeDirection(probe, tracerLookahead, fieldId)
            deltaYRot = yRot - prevYRot
            local lastWp = self.points[#self.points]
            -- this is just geometry, we figure out here how far forward the corner is from the previous waypoint
            local dx, _, _ = worldToLocal(probe, lastWp.x, lastWp.y, lastWp.z)
            setTranslation(helperNode, lastWp.x, lastWp.y, lastWp.z)
            setRotation(helperNode, 0, lastWp.yRot, 0)
            local moveForward = math.abs(dx) / math.sin(math.pi - math.abs(deltaYRot))
            local x, y, z = localToWorld(helperNode, 0, 0, moveForward)
            if moveForward < tracerLookahead and math.abs(deltaYRot) > sharpCornerDeltaAngle then
                if i == 0 then
                    -- corner detection does not work if we don't have a proper previous waypoint, so abort here
                    -- and the caller will readjust the probe so we start at a different spot, hopefully not
                    -- right in the corner
                    self:debug('Hit a corner right after starting to trace the field edge, restart tracing')
                    return false
                end
                -- only add plausible points and only when the delta angle is still above the threshold
                table.insert(self.points, {x = x, y = y, z = z, yRot = yRot})
                self:debug('Inserted a corner waypoint (%d, %.1f°), %.1f ahead of the last', i, math.deg(deltaYRot), dx / math.sin(math.pi - math.abs(deltaYRot)))
                i = i + 1
            end
        end

        local pX, pY, pZ = getWorldTranslation(probe)
        table.insert(self.points, {x = pX, y = pY, z = pZ, yRot = yRot})
        distanceFromStart = MathUtil.getPointPointDistance(pX, pZ, startX, startZ)
        totalYRot = totalYRot + deltaYRot
        -- more or less in the same direction, continue with the longer tracer beam
        prevYRot = yRot
        i = i + 1
        -- totalYRot must be around 360°, so stop after 440° as then we can be sure something is wrong, for instance
        -- fields too close and we are tracing some other fields edge now...
        if math.abs(totalYRot) > 3 * math.pi then
            lost = true
            self:debug('Looks like we are lost')
            break
        end
    end
    CpUtil.destroyNode(helperNode)
    self:debug('Field contour with %d points generated, total rotation %.1f°', #self.points, math.deg(totalYRot))
    -- a negative totalYRot means we went around the field clockwise, which we always should if we start in the
    -- middle of the field
    -- if it is positive, it means we bumped into an island and traced the island instead of the field
    return totalYRot < 0 and math.abs(totalYRot) > math.pi, lost
end

--- Find the polygon representing a field. The point (x,z) must be on the field.
---@param x number
---@param z number
---@return boolean, table true if successful, table contains points
function FieldScanner:findContour(x, z)
    -- don't start exactly at yRot 0 as folks tend to put the starting point (and so the probe)
    -- near the edge of the field. On rectangular fields, this may lead to finding the edge very
    -- close to the corner which then again, screws up our corner detection.
    -- This pi / 7 reduces the likelihood of ending up in a corner.
    local probe = CpUtil.createNode('FieldScannerProbe', x, z, math.pi / 7)
    if not CpFieldUtil.isNodeOnField(probe) then
        self:debug('%.1f/%.1f is not on a field, can\'t start scanning here', x, z)
        return false
    end
    local fieldId = CpFieldUtil.getFieldIdAtWorldPosition(x, z)
    self:debug('Start scanning field %d at %.1f/%.1f', fieldId or '', x, z)
    -- first ignore field ID as with it we can't handle merged fields.
    local limitToFieldId = nil
    local i = 2
    while i < 11 do
        self:findFieldEdge(probe, limitToFieldId)
        local done, lost = self:traceFieldEdge(probe, limitToFieldId)
        if done and not lost then
            break
        else
            if not done and not lost then
                self:debug('%d. try, edge not found, we may have hit an island or corner, reset/rotate the probe a bit and retry', i)
                setRotation(probe, 0, i * math.pi / 6, 0)
            elseif lost then
                self:info('Could not trace field edge, limit search to field %d and retry', fieldId)
                limitToFieldId = fieldId
            end
            -- move probe back to the start location
            self:setProbePosition(probe, x, z)
        end
        i = i + 1
    end
    -- TODO: see if we still need these commented out processors, if not, remove
    --self.points = self:simplifyPolygon(self.points, 1)
    self:debug('Field contour simplified, has now %d points', #self.points)
    --self:sharpenCorners(self.points)
    --self.points = self:addIntermediatePoints(self.points, 5)
    self:debug('Intermediate points added, has now %d points', #self.points)
    CpUtil.destroyNode(probe)
    return true, self.points
end

function FieldScanner:draw()
    if self.points then
        for i = 2, #self.points do
            local p, n = self.points[i - 1], self.points[i]
            Utils.renderTextAtWorldPosition(p.x, p.y + 1.2, p.z, tostring(i - 1), getCorrectTextSize(0.012), 0)
            DebugUtil.drawDebugLine(p.x, p.y + 1, p.z, n.x, n.y + 1, n.z, 0, 1, 0)
        end
    end
end

-- If two points are too close together (mostly at corners where we work with a high resolution),
-- replace the two points with a new one exactly between them
function FieldScanner:sharpenCorners(points)
    local prev = points[#points]
    local indicesToRemove = {}
    for i, p in ipairs(points) do
        local d = MathUtil.getPointPointDistance(p.x, p.z, prev.x, prev.z)
        self:debug('%d %.1f', i, d)
        if d < self.shortTracerLookahead then
            self:debug('There seems to be a corner at %i: %.1f, %.1f', i, p.x, p.z)
            table.insert(indicesToRemove, i)
            prev.x, prev.z = (p.x + prev.x) / 2, (p.z + prev.z) /2
        end
        prev = p
    end
    -- remove extra points, start from the end of the table so index of the point to be removed next won't change
    for i = #indicesToRemove, 1, -1  do
        table.remove(points, indicesToRemove[i])
    end
end

-- Simplifying a polygon results in long straight lines, worst (or best?) case four long lines in case of a
-- rectangular field. The course generator's headland algorithm likes to have vertices at least 5-10 meters apart,
-- so add them here.
-- TODO: should probably be moved to the course generator as this is its problem, not ours here...
function FieldScanner:addIntermediatePoints(points, distance)
    local newPoints = {}
    local prev = points[#points]
    for i, p in ipairs(points) do
        local d = MathUtil.getPointPointDistance(p.x, p.z, prev.x, prev.z)
        local dx, dz = MathUtil.vector2Normalize(p.x - prev.x, p.z - prev.z)
        local numberOfIntermediatePoints = math.floor(d / distance) - 1
        local dBetweenPoints = d / (numberOfIntermediatePoints + 1)
        for j = 1, d, dBetweenPoints do
            table.insert(newPoints, {x = prev.x + j * dx, z = prev.z + j * dz})
            newPoints[#newPoints].y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode,
                    newPoints[#newPoints].x, 0, newPoints[#newPoints].z)
        end
        table.insert(newPoints, p)
        prev = p
    end
    return newPoints
end


-- Distance of a point (px, pz) from a line starting between (sx, sz) and (ex, ez)GG
function FieldScanner:perpendicularDistance(px, pz, sx, sz, ex, ez)
    local dirX, dirZ = MathUtil.vector2Normalize(sx - ex, sz - ez)
    local x, z = MathUtil.projectOnLine(px, pz, sx, sz, dirX, dirZ)
    return MathUtil.getPointPointDistance(px, pz, x, z)
end

--- An implementation of the Ramer–Douglas–Peucker algorithm to smooth the non orthogonal field edges.
--- Due to the finite (I think 1 m) resolution of the density maps, our algorithm generates a zigzagged line if the
--- field edge is straight but not N-S or E-W direction.
function FieldScanner:simplifyPolygon(points, epsilon)
    -- Find the point with the maximum distance
    local dMax, index = 0, 0
    for i = 2, #points do
        local d = self:perpendicularDistance(points[i].x, points[i].z, points[1].x, points[1].z, points[#points].x, points[#points].z)
        if d > dMax then
            index = i
            dMax = d
        end
    end
    -- If max distance is greater than epsilon, recursively simplify
    if dMax > epsilon then
        local firstHalf = {}
        for i = 1, index do
            table.insert(firstHalf, points[i])
        end
        local result = self:simplifyPolygon(firstHalf, epsilon)
        local secondHalf = {}
        for i = index + 1, #points do
            table.insert(secondHalf, points[i])
        end
        local results2 = self:simplifyPolygon(secondHalf, epsilon)
        for _, p in ipairs(results2) do
            table.insert(result, p)
        end
        return result
    else
        return {points[1], points[#points]}
    end
end

g_fieldScanner = FieldScanner()