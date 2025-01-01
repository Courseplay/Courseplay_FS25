--- Wrapper around the Giants field boundary detection

---@class FieldBoundaryDetector
FieldBoundaryDetector = CpObject()

function FieldBoundaryDetector:debug(...)
    CpUtil.debugVehicle(CpDebug.DBG_COURSES, self.vehicle, ...)
end

function FieldBoundaryDetector:info(...)
    CpUtil.infoVehicle(self.vehicle, ...)
end

--- Create a FieldBoundaryDetector instance and start the detection immediately. The detection is an asynchronous
--- process and FieldBoundaryDetector:update() must be called until it returns false to get the result.
--- The result is available through getFieldPolygon(), which is a polygon representing the field boundary around
--- x, z.
---@param x number world X coordinate to start the detection at
---@param z number world Z coordinate to start the detection at
---@param vehicle table vehicle, this is used to generate the field course settings the Giants detection needs.
function FieldBoundaryDetector:init(x, z, vehicle)
    self.vehicle = vehicle
    self.updates = 0
    self:info( 'Detecting field boundary at %.1f %.1f using the Giants function', x, z)
    local fieldCourseSettings, implementData = FieldCourseSettings.generate(vehicle)
    self.courseField = FieldCourseField.generateAtPosition(x, z, fieldCourseSettings, function(courseField, success)
        if success then
            self:info('Field boundary detection successful')
        else
            self:info('Field boundary detection failed')
        end
        self.success, self.result = success, courseField
    end)
end

---@return boolean true if still in progress, false when done
function FieldBoundaryDetector:update(dt)
    if self.courseField:update(dt, 0.00025) then
        self.updates = self.updates + 1
        return true
    else
        return false
    end
end

---@return table|nil [{x, y, z}] field polygon vertices
function FieldBoundaryDetector:getFieldPolygon()
    local vertices = {}
    if self.success then
        for _, point in ipairs(self.result.fieldRootBoundary.boundaryLine) do
            local x, z = point[1], point[2]
            table.insert(vertices, { x = x, y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 1, z), z = z })
        end
    end
    return vertices
end