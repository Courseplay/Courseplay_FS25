--- Wrapper around the Giants field boundary detection

---@class FieldBoundaryDetector
FieldBoundaryDetector = CpObject()

--- Create a FieldBoundaryDetector instance and start the detection immediately. The detection is an asynchronous
--- process and FieldBoundaryDetector:update() must be called until it returns false to get the result.
---
--- If the user prefers custom fields, the detection will first check if there is a custom field at the given position,
--- and if so, use that as the field boundary. If not, the Giants field boundary detection is used.
--- If the Giants detection fails, the custom field is used as a fallback if exists at the position.
---
--- The result is available through getFieldPolygon(), which is a polygon representing the field boundary around
--- x, z, and through getIslandPolygons() which is an array of polygons representing the islands inside the field.
---
---@param x number world X coordinate to start the detection at
---@param z number world Z coordinate to start the detection at
---@param vehicle table vehicle, this is used to generate the field course settings the Giants detection needs.
function FieldBoundaryDetector:init(x, z, vehicle)
    self.logger = Logger('FieldBoundaryDetector', Logger.level.debug, CpDebug.DBG_COURSES)
    self.vehicle = vehicle
    self.updates = 0
    local customField = g_customFieldManager:getCustomField(x, z)
    if customField and g_Courseplay.globalSettings.preferCustomFields:getValue() then
        self.logger:info( 'Foun d custom field %s at %.1f %.1f and custom fields are preferred',
                customField:getName(), x, z)
        self:_useCustomField(customField)
        return
    end
    self.logger:info( 'Detecting field boundary at %.1f %.1f using the Giants function', x, z)
    local fieldCourseSettings, implementData = FieldCourseSettings.generate(vehicle)
    self.courseField = FieldCourseField.generateAtPosition(x, z, fieldCourseSettings, function(courseField, success)
        if success then
            self.done = true
            self.logger:info('Field boundary detection successful after %d updates, %d boundary points and %d islands',
                    self.updates, #courseField.fieldRootBoundary.boundaryLine, #courseField.islands)
            self.fieldPolygon = self:_getAsVertices(courseField.fieldRootBoundary.boundaryLine)
            self.islandPolygons = {}
            for i, island in ipairs(courseField.islands) do
                local islandBoundary = self:_getAsVertices(island.rootBoundary.boundaryLine)
                table.insert(self.islandPolygons, islandBoundary)
            end
        else
            if customField then
                self.logger:info('Field boundary detection failed after %d updates, but found custom field %s at %.1f %.1f',
                        self.updates, customField:getName(), x, z)
                self:_useCustomField(customField)
                return
            else
                self.logger:info('Field boundary detection failed after %d updates and no custom field found at %.1f %.1f',
                        self.updates, x, z)
                return
            end
        end
    end)
end

---@return boolean true if still in progress, false when done
function FieldBoundaryDetector:update(dt)
    -- when we use the custom field, we are done immediately
    self.logger:info('status: %d', self.courseField.state)
    -- FieldCourseField:update() returns true until it's state is FieldCourseDetectionState.FINISHED. Problem
    -- is, it may never go to the FINISHED state, and then our indication of done is that the callback is called with
    -- success == true, therefore use the self.done to indicate it.
    if not self.useCustomField and not self.done and self.courseField:update(dt, 0.00025) then
        self.updates = self.updates + 1
        return true
    else
        return false
    end
end

---@return table|nil [{x, y, z}] field polygon with game vertices
function FieldBoundaryDetector:getFieldPolygon()
    return self.fieldPolygon
end

---@return table|nil [[{x, y, z}]] array of island polygons with game vertices (x, y, z)
function FieldBoundaryDetector:getIslandPolygons()
    return self.islandPolygons
end

---@param boundaryLine table [[x, z]] array of arrays as the Giants functions return the field boundary
---@return table [{x, z}] array of vertices as the course generator needs it
function FieldBoundaryDetector:_getAsVertices(boundaryLine)
    local vertices = {}
    -- Giants seem to have the first vertex of the polygon repeated as the last, so skip the last one.
    for i = 1, #boundaryLine - 1 do
        local point = boundaryLine[i]
        local x, z = point[1], point[2]
        table.insert(vertices, { x = x, y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 1, z), z = z })
    end
    return vertices
end

function FieldBoundaryDetector:_useCustomField(customField)
    self.fieldPolygon = customField:getVertices()
    self.useCustomField = true
end