
--[[
	This course editor uses the giants build menu.
	It works on a given course, that gets loaded
	and saved on closing of the editor. 
]]
---@class CourseEditor
CourseEditor = CpObject()
CourseEditor.TRANSLATION_PREFIX = "CP_editor_course_"

function CourseEditor:init()
	--- Simple course display for the selected course.
	self.courseDisplay = SimpleCourseDisplay()
	self.title = ""
	self.isActive = false
	self.categorySchema = XMLSchema.new("cpConstructionCategories")
	self.categorySchema:register(XMLValueType.STRING, "Category.Tab(?)#name", "Tab name")
	self.categorySchema:register(XMLValueType.STRING, "Category.Tab(?)#iconSliceId", "Tab icon slice id")
	self.categorySchema:register(XMLValueType.STRING, "Category.Tab(?).Brush(?)#name", "Brush name")
	self.categorySchema:register(XMLValueType.STRING, "Category.Tab(?).Brush(?)#class", "Brush class")
	self.categorySchema:register(XMLValueType.STRING, "Category.Tab(?).Brush(?)#iconSliceId", "Brush icon slice id")
	self.categorySchema:register(XMLValueType.BOOL, "Category.Tab(?).Brush(?)#isCourseOnly", "Is course only?", false)

	self:load()
end

function CourseEditor:draw(x, y ,z)
	
end

function CourseEditor:load()
	self.brushCategory = self:loadCategory(Utils.getFilename("config/EditorCategories.xml", g_Courseplay.BASE_DIRECTORY))
end

function CourseEditor:getBrushCategory()
	return self.brushCategory
end

function CourseEditor:loadCategory(path)
	local category = {}
	local xmlFile = XMLFile.load("cpConstructionCategories", path, self.categorySchema)
	xmlFile:iterate("Category.Tab", function (_, tabKey)
		local tabName = xmlFile:getValue(tabKey .. "#name")
		local tab = {
			name = self.TRANSLATION_PREFIX .. tabName .. "_title",
			iconSliceId = xmlFile:getValue(tabKey .. "#iconSliceId"),
			brushes = {}
		}
		xmlFile:iterate(tabKey .. ".Brush", function (_, brushKey)
			local name = xmlFile:getValue(brushKey .. "#name")
			local brush = {
				name = name,
				class = xmlFile:getValue(brushKey .. "#class"),
				iconSliceId = xmlFile:getValue(brushKey .. "#iconSliceId"),
				isCourseOnly = xmlFile:getValue(brushKey .. "#isCourseOnly"),
				brushParameters = {
					self.TRANSLATION_PREFIX .. tabName .. "_" .. name 
				}
			}
			table.insert(tab.brushes, brush)
		end)
		table.insert(category, tab)
	end)
	xmlFile:delete()
	return category
end

function CourseEditor:getBrushClass(className)
	return CpUtil.getClassObject(className)
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
	self.needsMultiToolDialog = false
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
		self.courseDisplay:setCourseWrapper(self.courseWrapper)
		self.courseDisplay:setVisible(true)
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

end

function CourseEditor:registerActionEvents(frame, events)
	if not self.needsMultiToolDialog then 
		return
	end
	local _, eventId = g_inputBinding:registerActionEvent(InputAction.CONSTRUCTION_ACTION_SNAPPING, frame, 
		function(screen, actionName)
			local event = g_inputBinding:getFirstActiveEventForActionName(actionName)
			g_courseEditor:onClickLaneOffsetSetting(function(text)
				g_inputBinding:setActionEventText(event.id, string.format(g_i18n:getText("CP_editor_change_lane_offset"), text))
			end)
		end, false, true, false, true)
	table.insert(events, eventId)
	g_courseEditor:onClickLaneOffsetSetting(function(text)
		g_inputBinding:setActionEventText(eventId, string.format(g_i18n:getText("CP_editor_change_lane_offset"), text))
	end, true)
	g_inputBinding:setActionEventActive(eventId, true)
	g_inputBinding:setActionEventTextVisibility(eventId, true)
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

function CourseEditor:onClickExit(callbackFunc)
	if not self.file then 
		return
	end 
	YesNoDialog.show(
		function (self, clickOk)
			self:deactivate(clickOk)
			callbackFunc()
		end,
		self, string.format(g_i18n:getText("CP_editor_save_changes"), self.file:getName()))
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
			g_messageCenter:publish(MessageType.GUI_CP_INGAME_OPEN_CONSTRUCTION_MENU, self)
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
		self.needsMultiToolDialog = false
		self.isActive = true
		self.file = file
		self.field = field
		self.courseWrapper = EditorCourseWrapper(Course(nil, field:getVertices()))
		self.courseDisplay:setCourseWrapper(self.courseWrapper)
		self.courseDisplay:setVisible(true)
		self.title = string.format(g_i18n:getText("CP_editor_custom_field_title"), self.file:getName())
		g_messageCenter:publish(MessageType.GUI_CP_INGAME_OPEN_CONSTRUCTION_MENU, self)
		return true
	end
	return false
end

--- Deactivates the editor and saves the course.
function CourseEditor:deactivate(needsSaving)
	if not self:getIsActive() then 
		return
	end
	self.isActive = false
	self.courseDisplay:clear()
	self.courseDisplay:setVisible(false)
	if needsSaving then
		if self.field then 
			self.field:setVertices(self.courseWrapper:getAllWaypoints())
			g_customFieldManager:saveField(self.file, self.field, true)
		else 
			self:saveCourse()
		end
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