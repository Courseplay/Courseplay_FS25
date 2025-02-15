--- Specialization implementing the course generator related functionality
---
---@class CpCourseGenerator
CpCourseGenerator = {}

CpCourseGenerator.MOD_NAME = g_currentModName
CpCourseGenerator.NAME = ".cpCourseGenerator"
CpCourseGenerator.SPEC_NAME = CpCourseGenerator.MOD_NAME .. CpCourseGenerator.NAME

function CpCourseGenerator.register(typeManager,typeName,specializations)
    if CpCourseGenerator.prerequisitesPresent(specializations) then
        typeManager:addSpecialization(typeName, CpCourseGenerator.SPEC_NAME)
    end
end

function CpCourseGenerator.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(CpAIWorker, specializations)
end

function CpCourseGenerator.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", CpCourseGenerator)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", CpCourseGenerator)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", CpCourseGenerator)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", CpCourseGenerator)
end

function CpCourseGenerator.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, 'cpDetectFieldBoundary', CpCourseGenerator.cpDetectFieldBoundary)
    SpecializationUtil.registerFunction(vehicleType, 'cpIsFieldBoundaryDetectionRunning', CpCourseGenerator.cpIsFieldBoundaryDetectionRunning)
    SpecializationUtil.registerFunction(vehicleType, 'cpGetFieldPosition', CpCourseGenerator.cpGetFieldPosition)
    SpecializationUtil.registerFunction(vehicleType, 'cpGetFieldPolygon', CpCourseGenerator.cpGetFieldPolygon)
    SpecializationUtil.registerFunction(vehicleType, 'cpGetIslandPolygons', CpCourseGenerator.cpGetIslandPolygons)
    SpecializationUtil.registerFunction(vehicleType, 'cpDrawFieldPolygon', CpCourseGenerator.cpDrawFieldPolygon)
end

function CpCourseGenerator:onLoad(savegame)
    -- create shortcut to this spec
    self.spec_cpCourseGenerator = self["spec_" .. CpCourseGenerator.SPEC_NAME]
    self.spec_cpCourseGenerator.logger = Logger(CpCourseGenerator.SPEC_NAME, nil, CpDebug.DBG_COURSES)
    -- make sure cpGetFieldPosition always has spec.position
    self.spec_cpCourseGenerator.position = {}
end

---@param x number world X coordinate to start the detection at
---@param z number world Z coordinate to start the detection at
---@param object table|nil optional object with callback
---@param onFinishedFunc function callback function to call when finished: onFinishedFunc([object,] vehicle, fieldPolygon, islandPolygons)
function CpCourseGenerator:cpDetectFieldBoundary(x, z, object, onFinishedFunc)
    local spec = self.spec_cpCourseGenerator
    if spec.isFieldBoundaryDetectionRunning then
        spec.logger:warning(self, 'Not starting field boundary detection for %.1f/%.1f, previous for %.1f/%.1f is still running',
                x, z, spec.position.x, spec.position.z)
        return
    end
    spec.position = { x = x, z = z }
    spec.object = object
    spec.onFinishedFunc = onFinishedFunc
    spec.fieldBoundaryDetector = FieldBoundaryDetector(x, z, self)
    spec.isFieldBoundaryDetectionRunning = true
end

---@return boolean true if field boundary detection is running. Field and island polygons returned while running may
--- be nil or invalid.
function CpCourseGenerator:cpIsFieldBoundaryDetectionRunning()
    return self.spec_cpCourseGenerator.isFieldBoundaryDetectionRunning
end

---@return number|nil, number|nil world X and Z coordinates of the last field boundary detection start position, nil
--- if no previous detection was started
function CpCourseGenerator:cpGetFieldPosition()
    local spec = self.spec_cpCourseGenerator
    return spec.position.x, spec.position.z
end

function CpCourseGenerator:onUpdate(dt)
    local spec = self.spec_cpCourseGenerator
    if spec.fieldBoundaryDetector then
        if not spec.fieldBoundaryDetector:update(dt) then
            -- done
            spec.isFieldBoundaryDetectionRunning = false
            spec.fieldPolygon = spec.fieldBoundaryDetector:getFieldPolygon()
            spec.islandPolygons = spec.fieldBoundaryDetector:getIslandPolygons()
            spec.fieldBoundaryDetector = nil
            if spec.object and spec.onFinishedFunc then
                spec.onFinishedFunc(spec.object, self, spec.fieldPolygon, spec.islandPolygons)
            elseif spec.onFinishedFunc then
                spec.onFinishedFunc(self, spec.fieldPolygon, spec.islandPolygons)
            else
                spec.logger:debug('Field boundary detection finished, but no callback given')
            end
        end
    end
end

---@return table|nil [{x, y, z}] field polygon with game vertices
function CpCourseGenerator:cpGetFieldPolygon()
    return self.spec_cpCourseGenerator.fieldPolygon
end

---@return table|nil [[{x, y, z}]] array of island polygons with game vertices (x, y, z)
function CpCourseGenerator:cpGetIslandPolygons()
    return self.spec_cpCourseGenerator.islandPolygons
end

-- For debug, if there is a field polygon or island polygons, draw them
function CpCourseGenerator:cpDrawFieldPolygon()
    local spec = self.spec_cpCourseGenerator
    local function drawPolygon(polygon)
        for i = 2, #polygon do
            local p, n = polygon[i - 1], polygon[i]
            Utils.renderTextAtWorldPosition(p.x, p.y + 1.2, p.z, tostring(i - 1), getCorrectTextSize(0.012), 0)
            DebugUtil.drawDebugLine(p.x, p.y + 1, p.z, n.x, n.y + 1, n.z, 0, 1, 0)
        end
    end
    if spec.fieldPolygon then
        drawPolygon(spec.fieldPolygon)
    end
    if spec.islandPolygons then
        for _, p in ipairs(spec.islandPolygons) do
            drawPolygon(p)
        end
    end
end

function CpCourseGenerator:onReadStream(streamId, connection)
    local spec = self.spec_cpCourseGenerator
    local numVertices = streamReadInt32(streamId)
    if numVertices == 0 then
        spec.fieldPolygon = nil
    else
        spec.fieldPolygon = {}
        for _ = 1, numVertices do
            local x = streamReadFloat32(streamId)
            local y = streamReadFloat32(streamId)
            local z = streamReadFloat32(streamId)
            table.insert(spec.fieldPolygon, { x = x, y = y, z = z })
        end
    end
end

function CpCourseGenerator:onWriteStream(streamId, connection)
    local spec = self.spec_cpCourseGenerator
    if spec.fieldPolygon then
        streamWriteInt32(streamId, #spec.fieldPolygon)
        for _, point in pairs(spec.fieldPolygon) do
            streamWriteFloat32(streamId, point.x)
            if point.y ~= nil then
                streamWriteFloat32(streamId, point.y)
            else 
                streamWriteFloat32(streamId, getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, point.x, 1, point.z))
            end
            streamWriteFloat32(streamId, point.z)
        end
    else
        streamWriteInt32(streamId, 0)
    end
end