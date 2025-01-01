local Island = CpObject()

---@class CourseGenerator.Island
CourseGenerator.Island = Island

-- grid spacing used for island detection. Consequently, this will be the grid spacing
-- of the island points.
Island.gridSpacing = 1
Island.logger = Logger('Island')

function Island:init(id, perimeterPoints)
    self.boundary = Polygon()
    self.id = id
    self.logger = Logger('Island ' .. self.id)
    self.headlands = {}
    self.circled = false
    self:createFromPerimeterPoints(perimeterPoints)
end

---@param id number
---@param boundary Polygon
---@return CourseGenerator.Island
function Island.createFromBoundary(id, boundary)
    local island = CourseGenerator.Island(id, {})
    island.boundary = boundary
    return island
end

function Island:getId()
    return self.id
end

function Island:__tostring()
    return self:getId()
end

------------------------------------------------------------------------------------------------------------------------
-- Functions to create an island as a polygon from a bunch of points (raster -> vector)
------------------------------------------------------------------------------------------------------------------------
local function getNumberOfIslandNeighbors(point, islandPoints, gridSpacing)
    local nNeighbors = 0
    -- the worst case, considering that our grid isn't really a grid as points can be offset between rows,
    -- so worst case is when the neighbor in the next row is offset by half grid spacing, plus 5% reserve
    local worstCase = 1.05 * (1.5 * gridSpacing * 1.5 * gridSpacing) + (gridSpacing * gridSpacing)
    for _, v in ipairs(islandPoints) do
        local dSquare = Vector.getDistanceSquared(point, v)
        -- > 0 to ignore own point
        if dSquare > 0 and dSquare < worstCase then
            nNeighbors = nNeighbors + 1
        end
    end
    return nNeighbors
end

local function findPointWithinDistance(point, otherPoints, d)
    for i, other in ipairs(otherPoints) do
        if (point - other):length() < d then
            return i, other
        end
    end
    return nil, nil
end

---@param islandPoints [{x, y}]
function Island.getIslandPerimeterPoints(islandPoints)
    local perimeterPoints = {}
    for _, v in ipairs(islandPoints) do
        -- a vertex on the perimeter has at least two non-island neighbors (out of the possible
        -- 8 neighbors at most 6 can be island vertices).
        local neighbors = getNumberOfIslandNeighbors(v, islandPoints, Island.gridSpacing)
        if neighbors <= 6 then
            table.insert(perimeterPoints, v)
            CourseGenerator.addDebugPoint(v, tostring(neighbors))
        end
    end
    return perimeterPoints
end

-- Accepts a list of perimeter points (vectors) and creates an island
-- polygon. The list may define multiple islands, in that
-- case, it creates one island, removing the vertices used 
-- for that island from perimeterPoints and returns the
-- remaining vertices.
---@param perimeterPoints Vector[]
function Island:createFromPerimeterPoints(perimeterPoints)
    if #perimeterPoints < 1 then
        return perimeterPoints
    end
    local currentPoint = perimeterPoints[1]
    self.boundary:append(currentPoint)
    table.remove(perimeterPoints, 1)
    local ix, otherPoint
    otherPoint = currentPoint
    while otherPoint do
        -- find the next vertex, try closest first. 3.01 so it is guaranteed to be closer than 3 * gridSpacing
        for _, d in ipairs({ self.gridSpacing * 1.01, 1.5 * self.gridSpacing, 2.3 * self.gridSpacing, 3.01 * self.gridSpacing }) do
            ix, otherPoint = findPointWithinDistance(currentPoint, perimeterPoints, d)
            if ix then
                self.boundary:append(otherPoint)
                table.remove(perimeterPoints, ix)
                -- next vertex found, continue from that vertex
                currentPoint = otherPoint
                break
            end
        end
    end
    self.boundary:calculateProperties()
    self.boundary:ensureMinimumEdgeLength(2)
    self.logger:debug("created with %d vertices, area %.0f", self.id, #self.boundary, self.boundary:getArea())
end

---@return Polygon
function Island:getBoundary()
    return self.boundary
end

--- Generate headlands around the island. May generate less than what the context requests if the island headland
--- would go outside the field boundary
---@param context CourseGenerator.FieldworkContext
---@param mustNotCross Polygon outermost headland of field or field boundary: island headlands must not cross this
--- otherwise the island headland will be out of the field
function Island:generateHeadlands(context, mustNotCross)
    self.context = context
    self.logger:debug('generating %d headland(s)', self.context.nIslandHeadlands, self.context.turningRadius)
    local headlands = {}
    self.boundary = CourseGenerator.FieldworkCourseHelper.createUsableBoundary(self.boundary, self.context.islandHeadlandClockwise)
    -- innermost headland is offset from the island by half width
    headlands[1] = CourseGenerator.IslandHeadland(self, self.boundary, self.context.islandHeadlandClockwise, 1,
            self.context:getHeadlandWorkingWidth() / 2)
    for i = 2, self.context.nIslandHeadlands do
        if not headlands[i - 1]:isValid() then
            self.logger:warning('headland %d is invalid, removing', i - 1)
            headlands[i - 1] = nil
            break
        end
        headlands[i] = CourseGenerator.IslandHeadland(self, headlands[i - 1]:getPolygon(), self.context.islandHeadlandClockwise,
                i, self.context:getHeadlandWorkingWidth() * (1 - self.context:getHeadlandOverlap()))
    end
    if headlands[1]:getPolygon():intersects(mustNotCross) then
        self.logger:error('First headland intersects field boundary!')
    end
    self.headlands = {headlands[1]}
    local i = 2
    -- make sure no headlands are outside of the field
    while i <= #headlands and not headlands[i]:getPolygon():intersects(mustNotCross) do
        table.insert(self.headlands, headlands[i])
        i = i + 1
    end
    if #self.headlands < self.context.nIslandHeadlands then
        self.logger:warning('Only %d headlands of %d could be generated as the rest would intersect the field boundary',
                #self.headlands, self.context.nIslandHeadlands)
    end
end

function Island:getHeadlands()
    return self.headlands
end

function Island:getOutermostHeadland()
    return self.headlands[#self.headlands]
end

function Island:getBestHeadlandToBypass()
    return self.headlands[math.min(2, #self.headlands)]
end

function Island:getInnermostHeadland()
    return self.headlands[1]
end

--- Is this island too big to just bypass? If so, we can't just drive
--- around it, we actually have to end and turn the up/down rows
function Island:isTooBigToBypass(width)
    if self.headlands[1] and self.headlands[1]:isValid() then
        local area = self.headlands[1]:getPolygon():getArea() and self.headlands[1]:getPolygon():getArea() or 0
        local isTooBig = area > CourseGenerator.maxRowsToBypassIsland * width * CourseGenerator.maxRowsToBypassIsland * width
        self.logger:debug("isTooBigToBypass = %s (area = %.0f, width = %.1f", tostring(isTooBig), area, width)
        return isTooBig
    else
        return false
    end
end

--------------------------------------------------------------------------------------------------------- ---------------
-- Find islands in the game.
------------------------------------------------------------------------------------------------------------------------
function Island.findIslands(field)
    -- the idea here is to generate a simple up/down course without headland with 1 m working width
    -- to end up with a 1x1 grid of nodes covering the islands of the field.
    Island.logger:debug('Generating grid for field with grid spacing %.1f', Island.gridSpacing)
    local context = CourseGenerator.FieldworkContext(field, Island.gridSpacing, 5, 0)
    context:setAutoRowAngle(false):setRowAngle(0):setRowWaypointDistance(Island.gridSpacing)
    context:_setGenerateBlocksOnly():setSharpenCorners(false)
    local boundary = CourseGenerator.FieldworkCourseHelper.createUsableBoundary(context.field:getBoundary(), context.headlandClockwise)
    local center = CourseGenerator.Center(context, boundary, nil, context.startLocation, {}, true)

    center:generate()
    local islandVertices = {}
    for _, b in ipairs(center:getBlocks()) do
        for _, r in ipairs(b:getUnsequencedRows()) do
            r:splitEdges(Island.gridSpacing)
            for _, v in ipairs(r) do
                local isOnField, _ = FSDensityMapUtil.getFieldDataAtWorldPosition(v.x, 0, -v.y)
                if not isOnField then
                    -- add a vertex only if it is far enough from the field boundary
                    -- to filter false positives around the field boundary
                    local _, d, _ = field:getBoundary():findClosestVertexToPoint(v)
                    -- TODO: should calculate the closest distance to polygon edge, not
                    -- the vertices. This may miss an island close enough to the field boundary
                    if d > 8 * Island.gridSpacing then
                        table.insert(islandVertices, v)
                    end
                end
            end
        end
    end
    Island.logger:debug('    Found %d island vertices', #islandVertices)
    return islandVertices
end