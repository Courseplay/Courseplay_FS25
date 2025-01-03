---@class Field
local Field = CpObject()

---@class CourseGenerator.Field
CourseGenerator.Field = Field

---@param id string unique ID for this field for logging
---@param num number field number as shown in game
---@param boundary [{x, y}]|nil boundary of the field
function Field:init(id, num, boundary)
    self.id = id
    self.num = num
    self.logger = Logger('Field ' .. id)
    ---@type Polygon
    self.boundary = Polygon(boundary)
    ---@type CourseGenerator.Island[]
    self.islands = {}
    if boundary then
        self.boundary:calculateProperties()
        -- Giants field polygons are usually just the corner vertices, our generator likes many vertices...
        self.boundary:splitEdges(CourseGenerator.cMaxEdgeLength)
    end
end

function Field:getId()
    return self.id
end

function Field:getNum()
    return self.num
end

--- Read all fields saved in an XML file from the game console with the cpSaveAllFields command
---@return Field[] list of Fields in the file
function Field.loadSavedFields(fileName)
    local fields = {}
    local ix = 0
    for line in io.lines(fileName) do
        local fieldNum = string.match(line, '<field fieldNum="(%d+)"')
        if not fieldNum then
            fieldNum = string.match(line, '<customField name="CP%-(%d+)"')
        end
        if fieldNum then
            -- a new field started
            ix = tonumber(fieldNum)
            fields[ix] = Field(string.gsub(fileName, 'fields/', ''):gsub('fields\\', ''):gsub('.xml', '') .. '-' .. ix, ix)
            Logger(''):debug('Loading field %s', ix)
        end
        local num, x, z = string.match(line, '<point(%d+).+pos="([%d%.-]+) [%d%.-]+ ([%d%.-]+)"')
        if num then
            fields[ix].boundary:append(Vertex(tonumber(x), -tonumber(z)))
        else
            -- try the custom field format
            x, z = string.match(line, '([%d%.-]+) [%d%.-]+ ([%d%.-]+)')
            if x then
                fields[ix].boundary:append(Vertex(tonumber(x), -tonumber(z)))
            end
        end
        num, x, z = string.match(line, '<islandNode(%d+).+pos="([%d%.-]+) +([%d%.-]+)"')
        if num then
            if not fields[ix].islandPoints then
                fields[ix].islandPoints = {}
            end
            table.insert(fields[ix].islandPoints, Vertex(tonumber(x), -tonumber(z)))
        end
    end
    -- initialize all loaded fields
    for _, f in pairs(fields) do
        f:getBoundary():calculateProperties()
        f:setupIslands()
    end
    return fields
end

--- Smooth out zigzags in the boundary. Zigzags are created when the FieldScanner is running at high resolution
--- bigger than the game field pixel size
function Field:_smoothBoundary()
    CourseGenerator.SplineHelper.smooth(self:getBoundary(), 2, 1, #self:getBoundary(), math.rad(5), math.rad(45))
    self:getBoundary():ensureMinimumEdgeLength(CourseGenerator.cMaxEdgeLength, math.rad(30))
end

--- Center of the field (centroid)
---@return Vector
function Field:getCenter()
    if not self.center then
        self.center = self.boundary:getCenter()
    end
    return self.center
end

--- Bounding box
function Field:getBoundingBox()
    return self.boundary:getBoundingBox()
end

---@return Polygon
function Field:getBoundary()
    return self.boundary
end

---@return CourseGenerator.Island[]
function Field:getIslands()
    return self.islands
end

--- Vertices with coordinates unpacked, to draw with love.graphics.polygon
function Field:getUnpackedVertices()
    if not self.unpackedVertices then
        self.unpackedVertices = self.boundary:getUnpackedVertices()
    end
    return self.unpackedVertices
end

---@param island CourseGenerator.Island
function Field:addIsland(island)
    table.insert(self.islands, island)
end

-- Find islands (when running in the game)
function Field:findIslands()
    if self.islandPoints == nil then
        self.islandPoints = CourseGenerator.Island.findIslands(self)
    end
end

-- set up all island related data for the field
function Field:setupIslands()
    local islandPerimeterPoints = CourseGenerator.Island.getIslandPerimeterPoints(self.islandPoints or {})
    -- remember them for debug
    self.islandPerimeterPoints = {}
    if (#islandPerimeterPoints) > 0 then
        self.logger:debug('setting up islands from %d points', #islandPerimeterPoints)
    end
    for _, p in ipairs(islandPerimeterPoints) do
        table.insert(self.islandPerimeterPoints, p:clone())
    end
    local islandId = 1
    while #islandPerimeterPoints > 0 do
        local island = CourseGenerator.Island(islandId, islandPerimeterPoints)
        -- ignore too really small islands (under 5 sqm), there are too many issues with the
        -- headland generation for them
        CourseGenerator.addDebugPolyline(island:getBoundary())
        if island:getBoundary():getArea() > 5 then
            table.insert(self.islands, island)
            self.logger:debug('created island %d, boundary has %d vertices, area %.0f', islandId, #island:getBoundary(), island:getBoundary():getArea())
            islandId = islandId + 1
        end
    end
end
