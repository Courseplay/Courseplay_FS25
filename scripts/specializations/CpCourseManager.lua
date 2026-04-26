--- High level control of the Course object in the vehicle.
--- TODO: improve relations to the courseManager

---@class CpCourseManager
CpCourseManager = {}

CpCourseManager.MOD_NAME = g_currentModName
CpCourseManager.NAME = ".cpCourseManager"
CpCourseManager.SPEC_NAME = CpCourseManager.MOD_NAME .. CpCourseManager.NAME
CpCourseManager.KEY = "." .. CpCourseManager.MOD_NAME .. CpCourseManager.NAME
CpCourseManager.xmlKey = "Course"
CpCourseManager.rootKey = "AssignedCourses"
CpCourseManager.rootKeyFileManager = "Courses"
CpCourseManager.xmlKeyFileManager = "Courses.Course"

CpCourseManager.i18n = {
	["noCurrentCourse"] = "CP_courseManager_no_current_course",
	["temporaryCourse"] = "CP_courseManager_temporary_course",
}

-- shortcut to access the spec
function CpCourseManager.getSpec(self) 
    return self["spec_" .. CpCourseManager.SPEC_NAME]
end

--- generic xml course schema for saving/loading.
function CpCourseManager.registerXmlSchemaValues(schema,baseKey)
	baseKey = baseKey or ""
	schema:register(XMLValueType.STRING, baseKey .. "#name", "Course name")
	schema:register(XMLValueType.FLOAT, baseKey  .. "#workWidth", "Course work width")
	schema:register(XMLValueType.INT, baseKey .. "#numHeadlands", "Course number of headlands")
	schema:register(XMLValueType.INT, baseKey .. "#nVehicles", "Number of vehicles for a multi-vehicle course")
    schema:register(XMLValueType.BOOL, baseKey .. "#headlandClockwise", "Headlands are clockwise.")
    schema:register(XMLValueType.BOOL, baseKey .. "#islandHeadlandClockwise", "Headlands around islands are clockwise.")
    schema:register(XMLValueType.BOOL, baseKey .. "#wasEdited", "Was the course edited by the course editor.")
    schema:register(XMLValueType.BOOL, baseKey .. "#compacted", "Rows are compacted, only start and end is saved.")
    Waypoint.registerXmlSchema(schema, baseKey)
    Course.MultiVehicleData.registerXmlSchema(schema, baseKey)
end

function CpCourseManager.initSpecialization()
    CpCourseManager.xmlSchema = XMLSchema.new("Course")
	local schema = CpCourseManager.xmlSchema
	CpCourseManager.registerXmlSchemaValues(schema,CpCourseManager.xmlKeyFileManager .."(?)")

    local schema = Vehicle.xmlSchemaSavegame
    local key = "vehicles.vehicle(?)" .. CpCourseManager.KEY
    --- Saves the remembered wp ix to start fieldwork from, if it's set.
    schema:register(XMLValueType.INT, key .. "#rememberedWpIx", "Last waypoint driven with the saved course.")
    --- Saves the assigned courses id.
    schema:register(XMLValueType.INT, key .. "#assignedCoursesID", "Assigned Courses id.")
end

function CpCourseManager.register(typeManager,typeName,specializations)
	if CpCourseManager.prerequisitesPresent(specializations) then
		typeManager:addSpecialization(typeName, CpCourseManager.SPEC_NAME)
	end
end

function CpCourseManager.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(CpAIWorker, specializations) 
end

function CpCourseManager.registerEventListeners(vehicleType)	
--	SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", CpCourseManager)
	SpecializationUtil.registerEventListener(vehicleType, "onLoad", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, "onCpCourseChange", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, "onPreDelete", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, "onCpDrawHudMap", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, "onEnterVehicle", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, "onLeaveVehicle", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, 'onCpShowCourseSettingChanged', CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, 'onCpFieldworkWaypointChanged', CpCourseManager)
    SpecializationUtil.registerEventListener(vehicleType, 'onCpFinished', CpCourseManager)
end

function CpCourseManager.registerEvents(vehicleType)
    SpecializationUtil.registerEvent(vehicleType, 'onCpCourseChange')
    SpecializationUtil.registerEvent(vehicleType, 'onCpFieldworkWaypointChanged')
    SpecializationUtil.registerEvent(vehicleType, 'onCpShowCourseSettingChanged')
end

function CpCourseManager.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, 'setFieldWorkCourse', CpCourseManager.setFieldWorkCourse)
    SpecializationUtil.registerFunction(vehicleType, 'getFieldWorkCourse', CpCourseManager.getFieldWorkCourse)
    SpecializationUtil.registerFunction(vehicleType, 'addCpCourse', CpCourseManager.addCourse)
    SpecializationUtil.registerFunction(vehicleType, 'getCpCourses', CpCourseManager.getCourses)
    SpecializationUtil.registerFunction(vehicleType, 'hasCpCourse', CpCourseManager.hasCourse)
    SpecializationUtil.registerFunction(vehicleType, 'cpCopyCourse', CpCourseManager.cpCopyCourse)
    
    SpecializationUtil.registerFunction(vehicleType, 'appendLoadedCpCourse', CpCourseManager.appendLoadedCpCourse)
    SpecializationUtil.registerFunction(vehicleType, 'saveCpCourses', CpCourseManager.saveCourses)
    SpecializationUtil.registerFunction(vehicleType, 'resetCpCourses', CpCourseManager.resetCourses)
    SpecializationUtil.registerFunction(vehicleType, 'resetCpCoursesFromGui', CpCourseManager.resetCpCoursesFromGui)
    SpecializationUtil.registerFunction(vehicleType, 'getCurrentCpCourseName', CpCourseManager.getCurrentCourseName)
    SpecializationUtil.registerFunction(vehicleType, 'setCpCourseName', CpCourseManager.setCpCourseName)
    SpecializationUtil.registerFunction(vehicleType, 'cpReverseCurrentCourse', CpCourseManager.cpReverseCurrentCourse)

    SpecializationUtil.registerFunction(vehicleType, 'drawCpCoursePlot', CpCourseManager.drawCpCoursePlot)
    SpecializationUtil.registerFunction(vehicleType, 'updateCpCourseDisplayVisibility', CpCourseManager.updateCpCourseDisplayVisibility)

    SpecializationUtil.registerFunction(vehicleType, 'loadAssignedCpCourses', CpCourseManager.loadAssignedCourses)
    SpecializationUtil.registerFunction(vehicleType, 'saveAssignedCpCourses', CpCourseManager.saveAssignedCourses)

    SpecializationUtil.registerFunction(vehicleType, 'cpStartCourseRecorder', CpCourseManager.cpStartCourseRecorder)
    SpecializationUtil.registerFunction(vehicleType, 'cpStopCourseRecorder', CpCourseManager.cpStopCourseRecorder)
    SpecializationUtil.registerFunction(vehicleType, 'getIsCpCourseRecorderActive', CpCourseManager.getIsCpCourseRecorderActive)
    SpecializationUtil.registerFunction(vehicleType, 'getCanStartCpCourseRecorder', CpCourseManager.getCanStartCpCourseRecorder)
    SpecializationUtil.registerFunction(vehicleType, 'getIsCpCourseRecorderPaused', CpCourseManager.getIsCpCourseRecorderPaused)
    SpecializationUtil.registerFunction(vehicleType, 'toggleCpCourseRecorderPause', CpCourseManager.toggleCpCourseRecorderPause)

    SpecializationUtil.registerFunction(vehicleType, 'rememberCpLastWaypointIx', CpCourseManager.rememberCpLastWaypointIx)
    SpecializationUtil.registerFunction(vehicleType, 'getCpLastRememberedWaypointIx', CpCourseManager.getCpLastRememberedWaypointIx)

    SpecializationUtil.registerFunction(vehicleType, 'getCpAssignedCoursesID', CpCourseManager.getCpAssignedCoursesID)
    SpecializationUtil.registerFunction(vehicleType, 'setCpAssignedCoursesID', CpCourseManager.setCpAssignedCoursesID)

    SpecializationUtil.registerFunction(vehicleType, 'setCpCoursesFromNetworkEvent', CpCourseManager.setCoursesFromNetworkEvent)
end

function CpCourseManager:onLoad(savegame)
    local spec = CpCourseManager.getSpec(self) 
 
    spec.coursePlot = CoursePlot(g_inGameMenu.ingameMap)

    spec.courses = {}

    spec.courseDisplay = BufferedCourseDisplay() 
    spec.courseRecorder = CourseRecorder(spec.courseDisplay)
    g_assignedCoursesManager:registerVehicle(self, self.id)

    spec.assignedCoursesID = nil
end

function CpCourseManager:onPostLoad(savegame)
    if savegame == nil or savegame.resetVehicles then return end
    local baseKey = savegame.key..CpCourseManager.KEY
    self:rememberCpLastWaypointIx(savegame.xmlFile:getValue(baseKey.."#rememberedWpIx"))
    local id = savegame.xmlFile:getValue(baseKey.."#assignedCoursesID")
    g_assignedCoursesManager:loadAssignedCoursesByVehicle(self, id)
end

function CpCourseManager:loadAssignedCourses(xmlFile, baseKey, noEventSend, name)
    local spec = CpCourseManager.getSpec(self) 
    local courses = {}
    xmlFile:iterate(baseKey,function (i,key)
        CpUtil.debugVehicle(CpDebug.DBG_COURSES,self,"Loading assigned course: %s",key)
        local course = Course.createFromXml(self,xmlFile,key)
        course:setVehicle(self)
        table.insert(courses, course)
    end)    
    if courses ~= nil and next(courses) then
        spec.courses = courses
        if name then 
            spec.courses[1]:setName(name)
        end

        SpecializationUtil.raiseEvent(self, "onCpCourseChange", courses[1], noEventSend)
    end
end

function CpCourseManager:saveToXMLFile(xmlFile, baseKey, usedModNames)
    local ix = self:getCpLastRememberedWaypointIx()
    if ix then
        xmlFile:setValue(baseKey.."#rememberedWpIx",ix)
    end
    local id = self:getCpAssignedCoursesID()
    if id then
        xmlFile:setValue(baseKey.."#assignedCoursesID",id)
    end
end

function CpCourseManager:saveAssignedCourses(xmlFile, baseKey,name)
    local spec = CpCourseManager.getSpec(self) 
    local courses = spec.courses
    if courses ~=nil and next(courses) then
        for i=1,#courses do 
            local key = string.format("%s(%d)",baseKey,i-1)
            local course = courses[i]
            if name then 
                course:setName(name)
            end
            course:saveToXml(xmlFile, key)
        end
    end
end

function CpCourseManager:setCpAssignedCoursesID(id)
    local spec = CpCourseManager.getSpec(self) 
    spec.assignedCoursesID = id
end

function CpCourseManager:getCpAssignedCoursesID()
    local spec = CpCourseManager.getSpec(self) 
    return spec.assignedCoursesID
end

---@param course  Course
function CpCourseManager:setFieldWorkCourse(course)
    CpCourseManager.resetCourses(self)
    CpCourseManager.addCourse(self, course)
    course:setVehicle(self)
end

--- Copy the fieldwork course from another vehicle.
function CpCourseManager:cpCopyCourse(course)
    if course then
        self:setFieldWorkCourse(course:copy())
    end    
end

function CpCourseManager:setCoursesFromNetworkEvent(courses)
    CpCourseManager.resetCourses(self)
    CpCourseManager.addCourse(self,courses[1],true)   
end

function CpCourseManager:addCourse(course,noEventSend)
    local spec = CpCourseManager.getSpec(self) 
    course:setVehicle(self)
    table.insert(spec.courses,course)
    SpecializationUtil.raiseEvent(self,"onCpCourseChange",course,noEventSend)
end

function CpCourseManager:resetCourses()
    local spec = CpCourseManager.getSpec(self) 
    if spec and spec.courses then
        spec.courses = {}
        spec.assignedCoursesID = nil
        SpecializationUtil.raiseEvent(self,"onCpCourseChange")
    end
end

function CpCourseManager:resetCpCoursesFromGui()
    CpCourseManager.resetCourses(self)
    CoursesEvent.sendEvent(self)   
end

---@return Course
function CpCourseManager:getFieldWorkCourse()
    local spec = CpCourseManager.getSpec(self) 
    --- TODO: For now only returns the first course.
    return spec.courses and spec.courses[1]
end

function CpCourseManager:getCourses()
    local spec = CpCourseManager.getSpec(self) 
    return spec.courses
end

function CpCourseManager:hasCourse()
    local spec = CpCourseManager.getSpec(self) 
    return next(spec.courses) ~= nil
end

function CpCourseManager:updateCpCourseDisplayVisibility()
    local spec = CpCourseManager.getSpec(self) 
    local visibilityMode = self:getCpSettings().showCourse:getValue()
    spec.courseDisplay:updateVisibility(visibilityMode == CpVehicleSettings.SHOW_COURSE_ALL, 
                                        visibilityMode == CpVehicleSettings.SHOW_COURSE_START_STOP, 
                                        visibilityMode == CpVehicleSettings.SHOW_COURSE_AROUND_CURRENT_WP)
end

function CpCourseManager:onCpFieldworkWaypointChanged(wpIx)
    local course = self:getFieldWorkCourse()
    if course then 
        course:setCurrentWaypointIx(wpIx)
        if self:getCpSettings().showCourse:getValue() == CpVehicleSettings.SHOW_COURSE_AROUND_CURRENT_WP then 
            self:updateCpCourseDisplayVisibility()
        end
    end
end

function CpCourseManager:onCpShowCourseSettingChanged(showCourseSetting)
    local spec = CpCourseManager.getSpec(self) 
    if spec then
        self:updateCpCourseDisplayVisibility()
    end
end

function CpCourseManager:onEnterVehicle(isControlling)
    if isControlling then
        local spec = CpCourseManager.getSpec(self) 

        if spec.courseDisplay then
            spec.courseDisplay:setVisible(true)
            self:updateCpCourseDisplayVisibility()
        end
    end
end

function CpCourseManager:onLeaveVehicle(wasEntered)
    if wasEntered then
        local spec = CpCourseManager.getSpec(self) 
        if spec.courseDisplay then
            spec.courseDisplay:setVisible(false)
        end
    end
end

function CpCourseManager:onCpCourseChange(newCourse,noEventSend)
    local spec = CpCourseManager.getSpec(self) 
    if newCourse then
        -- we have course, show the course plot on the AI helper screen
        spec.coursePlot:setWaypoints(newCourse.waypoints)
        spec.coursePlot:setVisible(true)
        if noEventSend == nil or noEventSend == false then 
            CoursesEvent.sendEvent(self,spec.courses)   
        end
        if g_client then
            spec.courseDisplay:setCourse(self:getFieldWorkCourse())
            self:updateCpCourseDisplayVisibility()
        end
    else 
        spec.coursePlot:setVisible(false)
        self:rememberCpLastWaypointIx()
        self:updateCpCourseDisplayVisibility()
        if spec.courseDisplay then
            spec.courseDisplay:clear()
        end
    end
end

function CpCourseManager:onCpFinished()
    --- The course was completely finished, so we delete the remembered waypoint.
    self:rememberCpLastWaypointIx()
end

function CpCourseManager:drawCpCoursePlot(map, isHudMap)
    if self:hasCpCourse() then
        local spec = CpCourseManager.getSpec(self) 
        spec.coursePlot:draw(map, isHudMap)
    end
end

function CpCourseManager:onDraw()
end

function CpCourseManager:onCpDrawHudMap(map)
    if self:hasCpCourse() then
        --- Draws the course onto the hud map.
        self:drawCpCoursePlot(map, true)
    end
end

function CpCourseManager:onReadStream(streamId,connection)
    local numCourses = streamReadUInt8(streamId)
    for i=1,numCourses do 
        CpCourseManager.addCourse(self,Course.createFromStream(self, streamId, connection),true)
    end
end

function CpCourseManager:onWriteStream(streamId,connection)
	local spec = CpCourseManager.getSpec(self) 
    streamWriteUInt8(streamId,#spec.courses)
    for i,course in ipairs(spec.courses) do 
        course:writeStream(self, streamId, connection)
    end
end

function CpCourseManager:onPreDelete()
    local spec = CpCourseManager.getSpec(self) 
    if spec then
        g_assignedCoursesManager:unregisterVehicle(self, self.id)
        CpCourseManager.resetCourses(self)
        if spec.courseDisplay then spec.courseDisplay:delete() end
        spec.courseDisplay = nil
    end
end

------------------------------------------------------------------------
-- Interaction between the course manager frame and the vehicle courses.
------------------------------------------------------------------------

function CpCourseManager:getCurrentCourseName()
    if CpCourseManager.hasCourse(self) then 
        local courses = CpCourseManager.getCourses(self)
        local name =  CpCourseManager.getCourseName(courses[1])
        for i = 2,#courses do 
            name = string.format("%s + %s",name,CpCourseManager.getCourseName(courses[i]))
        end  
      --  name = string.format("%s (%d)",name,#courses)
        return name
    end
    return g_i18n:getText(CpCourseManager.i18n.noCurrentCourse)
end

function CpCourseManager.getCourseName(course)
	local name = course:getName()
    if name == "" then
       return g_i18n:getText(CpCourseManager.i18n.temporaryCourse)
    end
    return name
end

--- Trys to load a course from the file system
---@param file File
---@return boolean success
function CpCourseManager:appendLoadedCpCourse(file)
    --- For now clear the previous courses.
    CpCourseManager.resetCourses(self)
    return file:load(CpCourseManager.xmlSchema, CpCourseManager.xmlKeyFileManager, 
        CpCourseManager.loadAssignedCourses, self, false)
end

function CpCourseManager:saveCourses(file,text)
    if file:save(CpCourseManager.rootKeyFileManager,CpCourseManager.xmlSchema,
        CpCourseManager.xmlKeyFileManager,CpCourseManager.saveAssignedCourses,self,text) then
        --- Updates the course name, so multi tool courses are working correctly.
        CourseSaveNameEvent.sendEvent(self, text)
        self:setCpCourseName(text)
        return true
    end
    return false
end

function CpCourseManager:setCpCourseName(name)
    local spec = CpCourseManager.getSpec(self) 
    local course = spec.courses[1]
    if course then 
        course:setName(name)
        course.temporary = false
    end
end

function CpCourseManager:cpReverseCurrentCourse(noEventSend)
    local spec = CpCourseManager.getSpec(self) 
    ---@type Course
    local course = spec.courses[1]
    if course then
        course:reverse()
        spec.coursePlot:setWaypoints(course.waypoints)
        spec.coursePlot:setVisible(true)
        if noEventSend == nil or noEventSend == false then
            CourseReverseEvent.sendEvent(self)
        end
        if g_client then
            spec.courseDisplay:setCourse(self:getFieldWorkCourse())
            self:updateCpCourseDisplayVisibility()
        end
    end
end

function CpCourseManager:rememberCpLastWaypointIx(ix)
    local spec = CpCourseManager.getSpec(self) 
    spec.rememberedWpIx = ix
end

function CpCourseManager:getCpLastRememberedWaypointIx()
    local spec = CpCourseManager.getSpec(self) 
    return spec.rememberedWpIx
end

------------------------------------------------------------------------------------------------------------------------
--- Recording
------------------------------------------------------------------------------------------------------------------------
function CpCourseManager:onUpdate()
    local spec = CpCourseManager.getSpec(self) 
    spec.courseRecorder:update()
end

function CpCourseManager:cpStartCourseRecorder()
    local spec = CpCourseManager.getSpec(self) 
    spec.courseRecorder:start(self)
end

function CpCourseManager:cpStopCourseRecorder()
    local spec = CpCourseManager.getSpec(self) 
    spec.courseRecorder:stop()
    g_customFieldManager:addField(spec.courseRecorder:getRecordedWaypoints())
end


function CpCourseManager:getIsCpCourseRecorderActive()
    local spec = CpCourseManager.getSpec(self) 
    return spec.courseRecorder:isRecording()
end

function CpCourseManager:getIsCpCourseRecorderPaused()
    local spec = CpCourseManager.getSpec(self) 
    return self:getIsCpCourseRecorderActive() and spec.courseRecorder:isPaused()
end

function CpCourseManager:toggleCpCourseRecorderPause()
    local spec = CpCourseManager.getSpec(self) 
    if self:getIsCpCourseRecorderActive() then
        if self:getIsCpCourseRecorderPaused() then 
            spec.courseRecorder:unpause()
        else 
            spec.courseRecorder:pause()
        end
    end
end


--- can only start recording when CP is not driving (actually, it would work, should later consider)
function CpCourseManager:getCanStartCpCourseRecorder()
    return not self:getIsCpActive() and not self:hasCpCourse()
end
