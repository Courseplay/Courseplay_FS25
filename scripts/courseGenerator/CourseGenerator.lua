---@class CourseGenerator
CourseGenerator = {}

--- Tunable parameters
-- The maximum length of a polyline/polygon edge. This means no waypoints of the
-- generated course will be further than this.
-- It is important that this is greater than the field boundary detection algorithm's
-- vertex spacing, otherwise ensureMaximumEdgeLength() will double the number of vertices
-- of each headland polygon which results in performance loss, especially because of
-- functions checking the intersections of two polygons have O(nm) complexity
CourseGenerator.cMaxEdgeLength = 5.5
-- The minimum length of a polyline/polygon edge. No waypoints will be closer than this.
-- If a vertex is closer than cMinEdgeLength to the next, it is removed
CourseGenerator.cMinEdgeLength = 0.5
-- When ensuring maxEdgeLength and adding a new vertex and the direction change at
-- the previous vertex is less than this, the new vertex will be offset from the original
-- edge so the result is an arc. Over this angle, we won't offset, so corners are kept sharp.
CourseGenerator.cMaxDeltaAngleForMaxEdgeLength = math.rad(30)
-- Approximate distance of waypoints on up/down rows
CourseGenerator.cRowWaypointDistance = 7
-- Maximum cross track error we tolerate when a vehicle follows a path. This is used to
-- find corners which the vehicle can't make due to its turning radius, without deviating more than
-- cMaxCrossTrackError meters from the vertex in the corner.
CourseGenerator.cMaxCrossTrackError = 0.2
-- Maximum cross track error when generating rows parallel to a non-straight field edge. The row will end when
-- the cross track error is bigger than this limit
CourseGenerator.cMaxCrossTrackErrorForCurvedRows = 0.15
-- The delta angle above which smoothing kicks in. No smoothing around vertices with a delta
-- angle below this
CourseGenerator.cMinSmoothingAngle = math.rad(15)
-- Minimum radius in meters where a change to the next headland is allowed. This is to ensure that
-- we only change lanes on relatively straight sections of the headland (not around corners)
CourseGenerator.cHeadlandChangeMinRadius = 20

-- When splitting a field into blocks (due to islands or non-convexity)
-- consider a block 'small' if it has less than cSmallBlockRowPercentageLimit percentage of the total rows.
-- These are not preferred and will get a penalty in the scoring
CourseGenerator.cSmallBlockRowPercentageLimit = 5

-- Just an arbitrary definition of an island 'too big': wider than s * work width, so
-- at least x rows would have to drive around the island
-- If an island is too big, we'll turn back into the next row when we reach the headland around the island,
-- If an island is not too big, we make a circle around when the first row hits it and all subsequent rows
-- will just simple drive around it. No rows intersecting the island will be split at the island.
CourseGenerator.maxRowsToBypassIsland = 5

-- Maximum angle of the transition from one headland to another. This is the angle between the
-- headland and the transition path.
CourseGenerator.cMaxHeadlandConnectorAngle = math.rad(35)

-- Headland overlap. We make headland passes slightly narrower than the working width, so they overlap
-- a bit to make sure there are no unworked gaps remaining when maneuvering. This is the overlap in percentage of
-- the working width.
CourseGenerator.cDefaultHeadlandOverlapPercentage = 5

CourseGenerator.debugPoints = {}
CourseGenerator.debugPolylines = {}

---@param boundaryId string boundary ID from the waypoint attributes
---@return boolean true if this boundary ID is associated with a headland around the field
function CourseGenerator.isHeadland(boundaryId)
    return string.sub(boundaryId, 1) == CourseGenerator.Headland.boundaryIdPrefix
end

---@param boundaryId string boundary ID from the waypoint attributes
---@return boolean true if this boundary ID is associated with a headland around an island
function CourseGenerator.isIslandHeadland(boundaryId)
    return string.sub(boundaryId, 1) == CourseGenerator.IslandHeadland.boundaryIdPrefix
end

--- Return true when running in the game
-- used by file and log functions to determine how exactly to do things,
-- for example, io.flush is not available from within the game.
--
function CourseGenerator.isRunningInGame()
    return g_currentMission ~= nil and not g_currentMission.mock;
end

-------------------------------------------------------------------------------
--- Debugging when not running in the game
-------------------------------------------------------------------------------
function CourseGenerator.clearDebugObjects()
    CourseGenerator.debugPoints = {}
    CourseGenerator.debugPolylines = {}
end

local lastDebugPointAdded = 0

--- Add a point to the list of debug points we want to show on the test display
---@param v Vector
---@param text|nil optional debug text
---@param color table|nil color in form of {r, g, b}, each in the 0..1 range
function CourseGenerator.addDebugPoint(v, text, color)
    if CourseGenerator.isRunningInGame() then
        -- if we haven't added any debug points for a while, clear the list to avoid filling the memory
        if g_time - lastDebugPointAdded > 30000 then
            CourseGenerator.debugPoints = {}
        end
        lastDebugPointAdded = g_time
    end
    local debugPoint = v:clone()
    debugPoint.debugColor = color
    debugPoint.debugText = text
    table.insert(CourseGenerator.debugPoints, debugPoint)
end

local debugId = 1
--- Get a unique ID to be used in debug messages, to identify a message and the corresponding
--- debug point on the graphics. Use this in the debug message AND in the debug point text.
function CourseGenerator.getDebugId()
    debugId = debugId + 1
    return string.format('%d', debugId)
end

function CourseGenerator.addSmallDebugPoint(v, text, color)
    if CourseGenerator.isRunningInGame() then
        return
    end
    CourseGenerator.addDebugPoint(v, text, color)
    CourseGenerator.debugPoints[#CourseGenerator.debugPoints].small = true
end

local lastDebugPolylineAdded = 0

--- Add a line to the list of debug lines we want to show on the test display
---@param p Polyline
---@param color table|nil color in form of {r, g, b}, each in the 0..1 range
function CourseGenerator.addDebugPolyline(p, color)
    if CourseGenerator.isRunningInGame() then
        -- if we haven't added any debug polylines for a while, clear the list to avoid filling the memory
        if g_time - lastDebugPolylineAdded > 30000 then
            CourseGenerator.debugPolylines = {}
        end
        lastDebugPolylineAdded = g_time
    end
    local debugPolyline = p:clone()
    debugPolyline.debugColor = color
    table.insert(CourseGenerator.debugPolylines, debugPolyline)
end

--- Draw debug polylines in the game
function CourseGenerator.drawDebugPolylines()
    if not CourseGenerator.isRunningInGame() then
        return
    end
    for _, p in ipairs(CourseGenerator.debugPolylines) do
        local color = p.debugColor or {1, 1, 1}
        for i = 1, #p - 1 do
            local v1 = p[i]
            local v2 = p[i + 1]
            if v1.x and v1.y and v2.x and v2.y then
                local y1 = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, v1.x, 0, -v1.y)
                local y2 = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, v2.x, 0, -v2.y)
                DebugUtil.drawDebugLine(v1.x, y1 + 3.5, -v1.y, v2.x, y2 + 3.5, -v2.y, color[1], color[2], color[3])
            end
        end
    end
end

--- Draw debug points in the game
function CourseGenerator.drawDebugPoints()
    if not CourseGenerator.isRunningInGame() then
        return
    end
    for _, p in ipairs(CourseGenerator.debugPoints) do
        local color = p.debugColor or {1, 1, 1}
        local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, p.x, 0, -p.y)
        DebugUtil.drawDebugCircle(p.x, y + 3.6, -p.y, 0.3, 16, color)
        if p.debugText then
            Utils.renderTextAtWorldPosition(p.x, y + 3.6, -p.y, p.debugText, getCorrectTextSize(0.012), 0)
        end
    end
end