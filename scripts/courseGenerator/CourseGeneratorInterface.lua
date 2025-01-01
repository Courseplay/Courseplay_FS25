--- This is the interface provided to Courseplay
-- Wraps the CourseGenerator which does not depend on the CP or Giants code.
-- all course generator related code dependent on CP/Giants functions go here
CourseGeneratorInterface = {}
CourseGeneratorInterface.logger = Logger('CourseGeneratorInterface')

-- Generate into this global variable to be able to access the generated course for debug purposes
CourseGeneratorInterface.generatedCourse = nil

---@param fieldPolygon table [{x, z}]
---@param startPosition table {x, z}
---@param vehicle table
---@param settings CpCourseGeneratorSettings
function CourseGeneratorInterface.generate(fieldPolygon,
                                           startPosition,
                                           vehicle,
                                           settings
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
        context.field:findIslands()
        context.field:setupIslands()
    end

    local status
    if settings.narrowField:getValue() then
        -- two sided must start on headland
        context:setHeadlandFirst(true)
        status, CourseGeneratorInterface.generatedCourse = xpcall(
                function()
                    return CourseGenerator.FieldworkCourseTwoSided(context)
                end,
                function(err)
                    printCallstack();
                    return err
                end
        )
    elseif settings.multiTools:getValue() > 1 then
        context:setNumberOfVehicles(settings.multiTools:getValue())
        context:setHeadlands(settings.multiTools:getValue() * settings.numberOfHeadlands:getValue())
        context:setIslandHeadlands(settings.multiTools:getValue() * settings.nIslandHeadlands:getValue())
        context:setUseSameTurnWidth(settings.useSameTurnWidth:getValue())
        status, CourseGeneratorInterface.generatedCourse = xpcall(
                function()
                    return CourseGenerator.FieldworkCourseMultiVehicle(context)
                end,
                function(err)
                    printCallstack();
                    return err
                end
        )
    else
        status, CourseGeneratorInterface.generatedCourse = xpcall(
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
    if not status or CourseGeneratorInterface.generatedCourse == nil then
        return false
    end

    -- the actual number of headlands generated may be less than the requested
    local numberOfHeadlands = CourseGeneratorInterface.generatedCourse:getNumberOfHeadlands()

    CourseGeneratorInterface.logger:debug('Generated course: %s', CourseGeneratorInterface.generatedCourse)

    local course = Course.createFromGeneratedCourse(vehicle, CourseGeneratorInterface.generatedCourse,
            settings.workWidth:getValue(), numberOfHeadlands, settings.multiTools:getValue(),
            settings.headlandClockwise:getValue(), settings.islandHeadlandClockwise:getValue(), not settings.useBaseLineEdge:getValue())
    course:setFieldPolygon(fieldPolygon)
    CourseGeneratorInterface.setCourse(vehicle, course)
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
function CourseGeneratorInterface.generateVineCourse(
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
    status, CourseGeneratorInterface.generatedCourse = xpcall(
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
    if not status or CourseGeneratorInterface.generatedCourse == nil then
        return false
    end

    CourseGeneratorInterface.logger:debug('Generated vine course: %d center waypoints',
            #CourseGeneratorInterface.generatedCourse:getCenterPath())

    local course = Course.createFromGeneratedCourse(vehicle, CourseGeneratorInterface.generatedCourse,
            workWidth, 0, multiTools, true, true, true)
    course:setFieldPolygon(fieldPolygon)
    CourseGeneratorInterface.setCourse(vehicle, course)
    return true, course
end

--- Load the course into the vehicle
function CourseGeneratorInterface.setCourse(vehicle, course)
    if course and course:getMultiTools() > 1 then
        course:setPosition(vehicle:getCpLaneOffsetSetting():getValue())
    end
    vehicle:setFieldWorkCourse(course)
end

---------------------------------------------
--- Console Commands
---------------------------------------------

--- Generate a course with the current course generator settings
function CourseGeneratorInterface.generateDefaultCourse()
    local vehicle = CpUtil.getCurrentVehicle()
    local x, _, z = getWorldTranslation(vehicle.rootNode)

    vehicle:cpDetectFieldBoundary(x, z, nil, CourseGeneratorInterface.onFieldDetectionFinished)
end

function CourseGeneratorInterface.onFieldDetectionFinished(vehicle, fieldPolygon)
    if fieldPolygon == nil then
        CpUtil.infoVehicle(vehicle, "Not on a field, can't generate")
        return
    end
    local settings = CpUtil.getCurrentVehicle():getCourseGeneratorSettings()
    local width, offset, _, _ = WorkWidthUtil.getAutomaticWorkWidthAndOffset(vehicle)
    settings.workWidth:refresh()
    settings.workWidth:setFloatValue(width)
    vehicle:getCpSettings().toolOffsetX:setFloatValue(offset)
    settings.sharpenCorners:setValue(true)
    CpUtil.infoVehicle(vehicle, "Generating default course with %d headlands", settings.numberOfHeadlands:getValue())
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    local ok, course = CourseGeneratorInterface.generate(fieldPolygon, {x = x, z = z}, vehicle, settings)
    if ok then
        CourseGeneratorInterface.setCourse(vehicle, course)
    end
end