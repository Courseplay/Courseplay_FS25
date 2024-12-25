
--[[
	This course editor uses the giants build menu.
	It works on a given course, that gets loaded
	and saved on closing of the editor. 
]]
CourseEditor = CpObject()
CourseEditor.TRANSLATION_PREFIX = "CP_editor_course_"

function CourseEditor:init()
	--- Simple course display for the selected course.
	self.courseDisplay = EditorCourseDisplay(self)
	self.title = ""
	self.isActive = false
end

function CourseEditor:getTitle()
	return self.title
end

function CourseEditor:getIsActive()
	return self.isActive
end

function CourseEditor:isEditingCustomField()
	return self.field ~= nil
end

function CourseEditor:getStartPosition()
	if not self:getIsActive() then 
		return
	end
	local x, _, z = self.courseWrapper:getFirstWaypointPosition()
	return x, z
end

function CourseEditor:getCourseWrapper()
	return self.courseWrapper
end

--- Loads the course, might be a good idea to consolidate this with the loading of CpCourseManager.
function CourseEditor:loadCourse(file)
	local function load(self, xmlFile, baseKey, noEventSend, name)
		local course = nil
		xmlFile:iterate(baseKey, function (i, key)
			CpUtil.debugVehicle(CpDebug.DBG_COURSES, self, "Loading assigned course: %s", key)
			course = Course.createFromXml(nil, xmlFile, key)
			course:setName(name)
		end)  
		if course then
			self.courseWrapper = EditorCourseWrapper(course)
			return true
		end
		return false
	end
    if file:load(CpCourseManager.xmlSchema, CpCourseManager.xmlKeyFileManager, 
    	load, self, false) then
		self.courseDisplay:setCourse(self.courseWrapper)
		local course = self.courseWrapper:getCourse()
		if course and course:getMultiTools() > 1 then
			self.needsMultiToolDialog = true
		end
		return true
	end
	return false
end

--- Saves the course, might be a good idea to consolidate this with the saving of CpCourseManager.
function CourseEditor:saveCourse()
	local function save(self, xmlFile, baseKey)
		if self.courseWrapper then
			local key = string.format("%s(%d)", baseKey, 0)
			self.courseWrapper:getCourse():setEditedByCourseEditor()
			self.courseWrapper:getCourse():saveToXml(xmlFile, key)
		end
	end
	self.file:save(CpCourseManager.rootKeyFileManager, CpCourseManager.xmlSchema, 
		CpCourseManager.xmlKeyFileManager, save, self)
end

function CourseEditor:update(dt)
	-- if not g_gui:getIsDialogVisible() and self.needsMultiToolDialog then
	-- 	self.needsMultiToolDialog = false
	-- end
end

function CourseEditor:onClickLaneOffsetSetting(closure, ignoreDialog)
	local course = self.courseWrapper:getCourse()
	local allowedValues = Course.MultiVehicleData.getAllowedPositions(course:getMultiTools())
	local texts = CpFieldWorkJobParameters.laneOffset:getTextsForValues(allowedValues)
	if not ignoreDialog and not g_gui:getIsDialogVisible() then 
		OptionDialog.show(
			function (item)
				if item > 0 then
					local value = allowedValues[item]
					self.courseWrapper:getCourse():setPosition(value)
					self.courseDisplay:setCourse(self.courseWrapper)
					closure(texts[item])
				end
			end,
			CpFieldWorkJobParameters.laneOffset:getTitle(),
				"", texts)
	else
		local position = course.multiVehicleData.position
		for ix, v in ipairs(allowedValues) do 
			if v == position then 
				closure(texts[ix])
			end
		end
	end
end

--- Activates the editor with a given course file.
--- Also open the custom build menu only for CP.
function CourseEditor:activate(file)
	if self:getIsActive() then 
		return false
	end
	if file then 
		if self:loadCourse(file) then
			self.isActive = true
			self.file = file
			self.title = string.format(g_i18n:getText("CP_editor_course_title"), self.file:getName())
			g_messageCenter:publish(MessageType.GUI_CP_INGAME_OPEN_CONSTRUCTION_MENU)
			return true
		end
	end
	return false
end

function CourseEditor:activateCustomField(file, field)
	if self:getIsActive() then 
		return false
	end
	if file then 
		self.isActive = true
		self.file = file
		self.field = field
		self.courseWrapper = EditorCourseWrapper(Course(nil, field:getVertices()))
		self.courseDisplay:setCourse(self.courseWrapper)
		self.title = string.format(g_i18n:getText("CP_editor_custom_field_title"), self.file:getName())
		g_messageCenter:publish(MessageType.GUI_CP_INGAME_OPEN_CONSTRUCTION_MENU)
		return true
	end
	return false
end


--- Deactivates the editor and saves the course.
function CourseEditor:deactivate()
	if not self:getIsActive() then 
		return
	end
	self.isActive = false
	self.courseDisplay:deleteSigns()
	if self.field then 
		self.field:setVertices(self.courseWrapper:getAllWaypoints())
		g_customFieldManager:saveField(self.file, self.field, true)
	else 
		self:saveCourse()
	end
	self.file = nil 
	self.field = nil
	self.courseWrapper = nil
	self.needsMultiToolDialog = false
end


function CourseEditor:showYesNoDialog(title, callbackFunc)
	YesNoDialog.show(
		function (self, clickOk, viewEntry)
			callbackFunc(self, clickOk, viewEntry)
			self:updateLists()
		end,
		self, string.format(g_i18n:getText(title)))
end

function CourseEditor:delete()
	if self.courseDisplay then
		self.courseDisplay:delete()
	end
end

--- Updates the course display, when a waypoint change happened.
function CourseEditor:updateChanges(ix)
	self.courseDisplay:updateChanges(ix)
end

--- Updates the course display, when a single waypoint change happened.
function CourseEditor:updateChangeSingle(ix)
	self.courseDisplay:updateWaypoint(ix)
end

--- Updates the course display, between to waypoints.
function CourseEditor:updateChangesBetween(firstIx, lastIx)
	self.courseDisplay:updateChangesBetween(firstIx, lastIx)
end
g_courseEditor = CourseEditor()