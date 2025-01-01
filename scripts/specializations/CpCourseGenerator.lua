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
end

function CpCourseGenerator.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, 'cpDetectFieldBoundary', CpCourseGenerator.cpDetectFieldBoundary)
    SpecializationUtil.registerFunction(vehicleType, 'cpGetFieldPolygon', CpCourseGenerator.cpGetFieldPolygon)
    SpecializationUtil.registerFunction(vehicleType, 'cpDrawFieldPolygon', CpCourseGenerator.cpDrawFieldPolygon)
end

function CpCourseGenerator:onLoad(savegame)
    -- create shortcut to this spec
    self.spec_cpCourseGenerator = self["spec_" .. CpCourseGenerator.SPEC_NAME]
end

---@param x number world X coordinate to start the detection at
---@param z number world Z coordinate to start the detection at
---@param object table|nil optional object with callback
---@param onFinishedFunc function callback function to call when finished: onFinishedFunc([object,] fieldPolygon, islandPolygons)
function CpCourseGenerator:cpDetectFieldBoundary(x, z, object, onFinishedFunc)
    local spec = self.spec_cpCourseGenerator
    spec.fieldBoundaryDetector = FieldBoundaryDetector(x, z, self)
    spec.object = object
    spec.onFinishedFunc = onFinishedFunc
end

function CpCourseGenerator:onUpdate(dt)
    local spec = self.spec_cpCourseGenerator
    if spec.fieldBoundaryDetector then
        if not spec.fieldBoundaryDetector:update(dt) then
            -- done
            spec.fieldPolygon = spec.fieldBoundaryDetector:getFieldPolygon()
            spec.islandPolygons = spec.fieldBoundaryDetector:getIslandPolygons()
            spec.fieldBoundaryDetector = nil
            if spec.object then
                spec.onFinishedFunc(spec.object, self, spec.fieldPolygon, spec.islandPolygons)
            else
                spec.onFinishedFunc(self, spec.fieldPolygon, spec.islandPolygons)
            end
        end
    end
end

function CpCourseGenerator:cpGetFieldPolygon()
    return self.spec_cpCourseGenerator.fieldPolygon
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
