--- This is the interface provided to Courseplay
-- Wraps the CourseGenerator which does not depend on the CP or Giants code.
-- all course generator related code dependent on CP/Giants functions go here
---@class CourseGeneratorInterface
CourseGeneratorInterface = CpObject()

function CourseGeneratorInterface:init()
    self.logger = Logger('CourseGeneratorInterface', Logger.level.debug, CpDebug.DBG_COURSES)
    self.generatedCourse = nil
end

--- Start generating a normal (non-vine) fieldwork course, with field boundary and island detection
---@param startPosition table {x, z}
---@param vehicle table
---@param settings CpCourseGeneratorSettings
---@param object table|nil optional object with callback
---@param onFinishedFunc function callback function to call when finished: onFinishedFunc([object,] course) where
--- course may be nil on failure
function CourseGeneratorInterface:startGenerationWithDetection(startPosition, vehicle, settings, object, onFinishedFunc)
    self.startPosition = startPosition
    self.vehicle = vehicle
    self.settings = settings
    self.object = object
    self.onFinishedFunc = onFinishedFunc
    vehicle:cpDetectFieldBoundary(startPosition.x, startPosition.z, self, self.onFieldDetectionFinished)
end

--- Start generating a normal (non-vine) fieldwork course, with field boundary and islands already detected
---@param startPosition table {x, z}
---@param vehicle table
---@param settings CpCourseGeneratorSettings
---@param object table|nil optional object with callback
---@param onFinishedFunc function callback function to call when finished: onFinishedFunc([object,] course) where
--- course may be nil on failure
---@param fieldPolygon table [{x, z}] field boundary polygon
---@param islandPolygons table [[{x, z}]] island polygons
function CourseGeneratorInterface:startGeneration(startPosition, vehicle, settings, object, onFinishedFunc,
                                                  fieldPolygon, islandPolygons)
    self.vehicle = vehicle
    self.object = object
    self.onFinishedFunc = onFinishedFunc
    local ok, course = self:generate(fieldPolygon, startPosition, vehicle, settings, islandPolygons)
    if ok then
        self:triggerCallback(course)
    else
        self:triggerCallback(nil)
    end
end

function CourseGeneratorInterface:onFieldDetectionFinished(vehicle, fieldPolygon, islandPolygons)
    if fieldPolygon == nil then
        self.logger:error(vehicle, "Field detection at x = %.1f, z = %.1f failed, can't generate",
                self.startPosition.x, self.startPosition.z)
        self:triggerCallback(nil)
        return
    end
    self.logger:info(vehicle, "Field detection finished, now start generating course")
    self:startGeneration(self.startPosition, vehicle, self.settings, self.object, self.onFinishedFunc,
            fieldPolygon, islandPolygons)
end

function CourseGeneratorInterface:triggerCallback(...)
    if self.object and self.onFinishedFunc then
        self.onFinishedFunc(self.object, ...)
    elseif self.onFinishedFunc then
        self.onFinishedFunc(...)
    end
end

---@param fieldPolygon table [{x, z}]
---@param startPosition table {x, z}
---@param vehicle table
---@param settings CpCourseGeneratorSettings
---@param islandPolygons|nil table [[{x, z}]] island polygons
function CourseGeneratorInterface:generate(fieldPolygon,
                                           startPosition,
                                           vehicle,
                                           settings,
                                           islandPolygons
)
    CourseGenerator.clearDebugObjects()
    local field = CourseGenerator.Field('', 0, CpMathUtil.pointsFromGame(fieldPolygon))

    local context = CourseGenerator.FieldworkContext(field, settings.workWidth:getValue(),
            settings.turningRadius:getValue(), settings.numberOfHeadlands:getValue())
    local rowPatternNumber = settings.centerMode:getValue()
    if rowPatternNumber == CourseGenerator.RowPattern.ALTERNATING and settings.rowsToSkip:getValue() == 0 then
        context:setRowPattern(CourseGenerator.RowPatternAlternating())
    elseif rowPatternNumber == CourseGenerator.RowPattern.ALTERNATING and settings.rowsToSkip:getValue() > 0 then
        context:setRowPattern(CourseGenerator.RowPatternSkip(settings.rowsToSkip:getValue(), false))
    elseif rowPatternNumber == CourseGenerator.RowPattern.SPIRAL then
        context:setRowPattern(CourseGenerator.RowPatternSpiral(settings.centerClockwise:getValue(), settings.spiralFromInside:getValue()))
    elseif rowPatternNumber == CourseGenerator.RowPattern.LANDS then
        -- TODO: auto fill clockwise from self:isPipeOnLeftSide(vehicle)?
        context:setRowPattern(CourseGenerator.RowPatternLands(settings.centerClockwise:getValue(), settings.rowsPerLand:getValue()))
    elseif rowPatternNumber == CourseGenerator.RowPattern.RACETRACK then
        context:setRowPattern(CourseGenerator.RowPatternRacetrack(settings.numberOfCircles:getValue()))
    end

    context:setStartLocation(startPosition.x, -startPosition.z)
    context:setBaselineEdge(startPosition.x, -startPosition.z)
    context:setFieldMargin(settings.fieldMargin:getValue())
    context:setUseBaselineEdge(settings.useBaseLineEdge:getValue())
    context:setFieldCornerRadius(7) --using a default, that is used during testing
    context:setHeadlandFirst(settings.startOnHeadland:getValue())
    context:setHeadlandClockwise(settings.headlandClockwise:getValue())
    context:setHeadlandOverlap(settings.headlandOverlapPercent:getValue())
    context:setSharpenCorners(settings.sharpenCorners:getValue())
    context:setHeadlandsWithRoundCorners(settings.headlandsWithRoundCorners:getValue())
    context:setAutoRowAngle(settings.autoRowAngle:getValue())
    -- the Course Generator UI uses the geographical direction angles (0 - North, 90 - East, etc), convert it to
    -- the mathematical angle (0 - x+, 90 - y+, etc)
    context:setRowAngle(math.rad(-(settings.manualRowAngleDeg:getValue() - 90)))
    context:setEvenRowDistribution(settings.evenRowWidth:getValue())
    context:setBypassIslands(settings.bypassIslands:getValue())
    context:setIslandHeadlands(settings.nIslandHeadlands:getValue())
    context:setIslandHeadlandClockwise(settings.islandHeadlandClockwise:getValue())
    if settings.bypassIslands:getValue() then
        if islandPolygons then
            -- islands were detected already, create them from the polygons and add to the field
            for i, islandPolygon in ipairs(islandPolygons) do
                context.field:addIsland(CourseGenerator.Island.createFromBoundary(i,
                        Polygon(CpMathUtil.pointsFromGame(islandPolygon))))
            end
        end
    end

    local status
    if settings.multiTools:getValue() > 1 then
        settings.narrowField:setValue(false)
        context:setNumberOfVehicles(settings.multiTools:getValue())
        context:setHeadlands(settings.multiTools:getValue() * settings.numberOfHeadlands:getValue())
        context:setIslandHeadlands(settings.multiTools:getValue() * settings.nIslandHeadlands:getValue())
        context:setUseSameTurnWidth(settings.useSameTurnWidth:getValue())
        status, self.generatedCourse = xpcall(
                function()
                    return CourseGenerator.FieldworkCourseMultiVehicle(context)
                end,
                function(err)
                    printCallstack();
                    return err
                end
        )
    elseif settings.narrowField:getValue() and settings.numberOfHeadlands:getValue() > 0 then
        -- two sided must have headlands and must start on headland
        context:setHeadlandFirst(true)
        -- and must not have multiple vehicles
        settings.multiTools:setValue(1)
        status, self.generatedCourse = xpcall(
                function()
                    return CourseGenerator.FieldworkCourseTwoSided(context)
                end,
                function(err)
                    printCallstack();
                    return err
                end
        )
    else
        status, self.generatedCourse = xpcall(
                function()
                    return CourseGenerator.FieldworkCourse(context)
                end,
                function(err)
                    printCallstack();
                    return err
                end
        )
    end

    -- return on exception or if the result is not usable
    if not status or self.generatedCourse == nil then
        return false
    end

    -- the actual number of headlands generated may be less than the requested
    local numberOfHeadlands = self.generatedCourse:getNumberOfHeadlands()

    self.logger:debug(vehicle, 'Generated course: %s', self.generatedCourse)

    local course = Course.createFromGeneratedCourse(vehicle, self.generatedCourse,
            settings.workWidth:getValue(), numberOfHeadlands, settings.multiTools:getValue(),
            settings.headlandClockwise:getValue(), settings.islandHeadlandClockwise:getValue(), not settings.useBaseLineEdge:getValue())
    self:setCourse(vehicle, course)
    return true, course
end

--- Generates a vine course, where the fieldPolygon are the start/end of the vine node.
---@param fieldPolygon table
---@param startPosition table {x, z}
---@param vehicle table
---@param workWidth number
---@param turningRadius number
---@param manualRowAngleDeg number
---@param rowsToSkip number
---@param multiTools number
function CourseGeneratorInterface:generateVineCourse(
        fieldPolygon,
        startPosition,
        vehicle,
        workWidth,
        turningRadius,
        manualRowAngleDeg,
        rowsToSkip,
        multiTools,
        lines,
        offset
)
    CourseGenerator.clearDebugObjects()
    local field = CourseGenerator.Field('', 0, CpMathUtil.pointsFromGame(fieldPolygon))

    local context = CourseGenerator.FieldworkContext(field, workWidth, turningRadius, 0)
    if rowsToSkip == 0 then
        context:setRowPattern(CourseGenerator.RowPatternAlternating())
    else
        context:setRowPattern(CourseGenerator.RowPatternSkip(rowsToSkip, true))
    end
    context:setStartLocation(startPosition.x, -startPosition.z)
    context:setAutoRowAngle(false)
    -- the Course Generator UI uses the geographical direction angles (0 - North, 90 - East, etc), convert it to
    -- the mathematical angle (0 - x+, 90 - y+, etc)
    context:setRowAngle(CpMathUtil.angleFromGame(manualRowAngleDeg))
    context:setBypassIslands(false)
    local status
    status, self.generatedCourse = xpcall(
            function()
                return CourseGenerator.FieldworkCourseVine(context,
                        CourseGenerator.FieldworkCourseVine.generateRows(workWidth, lines, offset ~= 0))
            end,
            function(err)
                printCallstack();
                return err
            end
    )
    -- return on exception or if the result is not usable
    if not status or self.generatedCourse == nil then
        return false
    end

    self.logger:debug('Generated vine course: %d center waypoints',
            #self.generatedCourse:getCenterPath())

    local course = Course.createFromGeneratedCourse(vehicle, self.generatedCourse,
            workWidth, 0, multiTools, true, true, true)
    self:setCourse(vehicle, course)
    return true, course
end

--- Generates a course whose rows follow detected windrows (straw/hay swaths on the ground), so a baler
--- drives exactly over the product. The windrow lines are used directly as the course generator rows
--- (like the vine course), so the existing turn/headland-transition logic connects them with 180° turns.
---@param fieldPolygon table [{x, z}]
---@param startPosition table {x, z}
---@param vehicle table
---@param workWidth number baler pickup width
---@param turningRadius number
---@param lines table [{x1, z1, x2, z2}] one straight line per detected windrow (game coordinates)
---@param multiTools number number of vehicles (1 for a single baler)
function CourseGeneratorInterface:generateWindrowCourse(
        fieldPolygon,
        startPosition,
        vehicle,
        workWidth,
        turningRadius,
        lines,
        multiTools
)
    CourseGenerator.clearDebugObjects()
    local field = CourseGenerator.Field('', 0, CpMathUtil.pointsFromGame(fieldPolygon))

    local context = CourseGenerator.FieldworkContext(field, workWidth, turningRadius, 0)
    context:setRowPattern(CourseGenerator.RowPatternAlternating())
    context:setStartLocation(startPosition.x, -startPosition.z)
    context:setAutoRowAngle(false)
    context:setBypassIslands(false)
    local status
    status, self.generatedCourse = xpcall(
            function()
                -- rows ON the windrow lines (rowsBetweenLines = false)
                return CourseGenerator.FieldworkCourseVine(context,
                        CourseGenerator.FieldworkCourseVine.generateRows(workWidth, lines, false))
            end,
            function(err)
                printCallstack();
                return err
            end
    )
    if not status or self.generatedCourse == nil then
        return false
    end

    self.logger:debug('Generated windrow course: %d center waypoints',
            #self.generatedCourse:getCenterPath())

    local course = Course.createFromGeneratedCourse(vehicle, self.generatedCourse,
            workWidth, 0, multiTools, true, true, true)
    self:setCourse(vehicle, course)
    return true, course
end

--- Load the course into the vehicle
function CourseGeneratorInterface:setCourse(vehicle, course)
    if course and course:getMultiTools() > 1 then
        course:setPosition(vehicle:getCpLaneOffsetSetting():getValue())
    end
    vehicle:setFieldWorkCourse(course)
end

--- Generate a course for the vehicle, with start position at the vehicle's position
function CourseGeneratorInterface:generateDefaultCourse(vehicle)
    local settings = vehicle:getCourseGeneratorSettings()
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    self.logger:info(vehicle, 'Generating course at x = %.1f, z = %.1f', x, z)
    self:startGenerationWithDetection({x = x, z = z}, vehicle, settings, nil, function()
        self.logger:info(vehicle, 'Course generation finished')
    end)
end