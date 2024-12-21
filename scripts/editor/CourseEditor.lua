
--[[
	This course editor uses the giants build menu.
	It works on a given course, that gets loaded
	and saved on closing of the editor. 
]]
CourseEditor = {
	MOD_NAME = g_currentModName,
	BASE_DIRECTORY = g_currentModDirectory,
	TRANSLATION_PREFIX = "CP_editor_",
	CATEGORY_COURSE = "course",
	CATEGORY_CUSTOM_FIELD = "customField",
	CATEGORIES_FILE_NAME = "config/EditorCategories.xml"
}
local CourseEditor_mt = Class(CourseEditor)
function CourseEditor.new(customMt)
	local self = setmetatable({}, customMt or CourseEditor_mt)
	self.isActive = false
	self.categories = {}
	self.categoriesByName = {}
	return self
end

function CourseEditor:getIsActive()
	return self.isActive	
end

--- Loads the course, might be a good idea to consolidate this with the loading of CpCourseManager.
function CourseEditor:loadCourse()
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
    if self.file:load(CpCourseManager.xmlSchema, CpCourseManager.xmlKeyFileManager, 
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
	if g_currentMission == nil then
		return
	end
	if file then 
		if self:loadCourse() then
			self.isActive = true
			self.file = file
			g_gui:showGui("ShopMenu")
			g_shopMenu:onButtonConstruction()
			return true
		end
	end
	return false
end

function CourseEditor:activateCustomField(file, field)
	if g_currentMission == nil then
		return
	end
	if file then 
		self.isActive = true
		self.file = file
		self.field = field
		self.courseWrapper = EditorCourseWrapper(Course(nil, field:getVertices()))
		self.courseDisplay:setCourse(self.courseWrapper)
		g_gui:showGui("ShopMenu")
		g_shopMenu:onButtonConstruction()
	end
end


--- Deactivates the editor and saves the course.
function CourseEditor:deactivate()
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

function CourseEditor:getCategoryByName(name)
	if name ~= nil then
		return self.categoriesByName[name:upper()]
	end
	return nil
end

function CourseEditor:getTabByName(name, categoryName)
	local category = self:getCategoryByName(categoryName)
	if category == nil or name == nil then
		return nil
	end
	name = name:upper()
	for i, tab in ipairs(category.tabs) do
		if tab.name == name then
			return tab
		end
	end
	return nil
end

function CourseEditor:getCategories()
	return self.categories
end

function CourseEditor:load()
	--- Simple course display for the selected course.
	self.courseDisplay = EditorCourseDisplay(self)
	self.categoriesByName, self.categories = self:loadFromXml(CourseEditor.CATEGORIES_FILE_NAME)
end

--- Loads the cp categories, tabs and brushes.
function CourseEditor:loadFromXml(filename)
	local categoriesByName, categories = {}, {}

	local filePath = Utils.getFilename(filename, CourseEditor.BASE_DIRECTORY)
	local xmlFile = XMLFile.loadIfExists("courseEditorXml", filePath)
	if xmlFile ~=0 then
		local defaultIconFilename = xmlFile:getString("Categories#defaultIconFilename")
		if defaultIconFilename then 
			defaultIconFilename = Utils.getFilename(defaultIconFilename, CourseEditor.BASE_DIRECTORY)
		end
		local defaultRefSize = xmlFile:getVector("Categories#refSize", {
			1024,
			1024
		}, 2)

		xmlFile:iterate("Categories.Category", function (_, key)
			local categoryName = xmlFile:getString(key .. "#name")
			local iconFilename = xmlFile:getString(key .. "#iconFilename")
			if iconFilename then 
				iconFilename = Utils.getFilename(iconFilename, CourseEditor.BASE_DIRECTORY)
			else 
				iconFilename = defaultIconFilename
			end
			local refSize = xmlFile:getVector(key .. "#refSize", defaultRefSize, 2)
			local iconUVs = GuiUtils.getUVs(xmlFile:getString(key .. "#iconUVs", "0 0 1 1"), refSize)
			local translation = self.TRANSLATION_PREFIX .. categoryName
			local category = {
				name = categoryName:upper(),
				title =  g_i18n:getText(translation .. "_title", CourseEditor.MOD_NAME),
				iconFilename = iconFilename,
				iconUVs = iconUVs,
				tabs = {},
				index = #categories + 1
			}
			xmlFile:iterate(key .. ".Tab", function (_, tKey)
				local tabName = xmlFile:getString(tKey .. "#name")
				local tabIconFilename = xmlFile:getString(tKey .. "#iconFilename")
				if tabIconFilename then 
					tabIconFilename = Utils.getFilename(tabIconFilename, CourseEditor.BASE_DIRECTORY)
				else 
					tabIconFilename = defaultIconFilename
				end
				local tabRefSize = xmlFile:getVector(tKey .. "#refSize", defaultRefSize, 2)
				local tabIconUVs = GuiUtils.getUVs(xmlFile:getString(tKey .. "#iconUVs", "0 0 1 1"), tabRefSize)
				local tabTranslation = translation .. "_" .. tabName
				
				local brushes = {}
				xmlFile:iterate(tKey .. ".Brush", function (_, bKey)
					local brushName = xmlFile:getString(bKey .. "#name")
					local brushClass  = xmlFile:getString(bKey .. "#class")
					local brushIconFilename = xmlFile:getString(bKey .. "#iconFilename")
					if brushIconFilename then 
						brushIconFilename = Utils.getFilename(brushIconFilename, CourseEditor.BASE_DIRECTORY)
					else 
						brushIconFilename = defaultIconFilename
					end
					local brushRefSize = xmlFile:getVector(bKey .. "#refSize", defaultRefSize, 2)
					local brushIconUVs = GuiUtils.getUVs(xmlFile:getString(bKey .. "#iconUVs", "0 0 1 1"), brushRefSize)
					local brushTranslation = tabTranslation .. "_" .. brushName
					local brushIsCourseOnly = xmlFile:getBool(bKey .. "#isCourseOnly", false) 
					local brushData = {
						translation = brushTranslation,
						title = g_i18n:getText(brushTranslation .. "_title", CourseEditor.MOD_NAME),
						className = brushClass,
						iconFilename = brushIconFilename,
						iconUvs = brushIconUVs,
						isCourseOnly = brushIsCourseOnly
					}
					table.insert(brushes, brushData)
				end)
				table.insert(category.tabs, {
					name = tabName:upper(),
					title = g_i18n:getText(tabTranslation .. "_title", CourseEditor.MOD_NAME),
					iconFilename = tabIconFilename,
					iconUVs = tabIconUVs,
					index = #category.tabs + 1,
					brushes = brushes
				})
			end)
			table.insert(categories, category)
			categoriesByName[categoryName:upper()] = category
		end)
		xmlFile:delete()
	else 
		CpUtil.info("Course editor config file %s could not be loaded.", filename)
	end
	return categoriesByName, categories
end

--- Disables the giants context, when the editor is active.
--- Also adds the cp brushes, when the editor is active.
local function buildTerrainSculptBrushes(screen, superFunc, numItems)
	if g_courseEditor:getIsActive() then
		local categoryName = CourseEditor.CATEGORY_COURSE
		local category = g_storeManager:getConstructionCategoryByName(categoryName)
		for j, tabData in ipairs(category.tabs) do 
			local tabName = tabData.name
			local ix = g_storeManager:getConstructionTabByName(tabName, categoryName).index
			local tab = screen.items[category.index][ix]
			for i, brushData in ipairs(tabData.brushes) do 
				if not brushData.isCourseOnly or brushData.isCourseOnly and g_courseEditor.field == nil then
					numItems = numItems + 1
					table.insert(tab, {
						price = 0,
						imageFilename = brushData.iconFilename,
						imageUvs = brushData.iconUvs,
						name = brushData.title,
						brushClass =  CpUtil.getClassObject(brushData.className),
						brushParameters = {
							g_courseEditor,
							brushData.translation,
							g_courseEditor.courseWrapper
						},
						uniqueIndex = numItems
					})
				end
			end
		end
	else 
		numItems = superFunc(screen, numItems)
	end
	return numItems 
end
ConstructionScreen.buildTerrainSculptBrushes = Utils.overwrittenFunction(ConstructionScreen.buildTerrainSculptBrushes, buildTerrainSculptBrushes)

--- Disables the giants context, when the editor is active.
local function buildTerrainPaintBrushes(screen, superFunc, numItems)
	if g_courseEditor:getIsActive() then
		return numItems
	end
	return superFunc(screen, numItems)
end
ConstructionScreen.buildTerrainPaintBrushes = Utils.overwrittenFunction(ConstructionScreen.buildTerrainPaintBrushes, buildTerrainPaintBrushes)

--- Fixes the tab button uvs.
local function setSelectedCategory(screen, superFunc, ix, ...)
	if screen.currentCategory == ix then
		return
	end
	superFunc(screen, ix, ...)
	if g_courseEditor:getIsActive() then
		local numTabsForCategory = 0
		if screen.currentCategory ~= nil then
			numTabsForCategory = #screen.items[screen.currentCategory]
		end
		for t, button in ipairs(screen.tabsBox.elements) do
			if t <= numTabsForCategory then
				--- Makes sure the icon are updated correctly.
				local tab = screen.categories[screen.currentCategory].tabs[t]
				GuiOverlay.deleteOverlay(button.icon)
				button:setImageFilename(screen, tab.iconFilename)
				button:setImageUVs(nil, tab.iconUVs)
			end
		end
	end
end
ConstructionScreen.setSelectedCategory = Utils.overwrittenFunction(ConstructionScreen.setSelectedCategory, setSelectedCategory)

--- Updates the uvs, as giants has not implemented this.
local function populateCellForItemInSection(screen, list, section, index, cell)
	if g_courseEditor:getIsActive() then
		local item = screen.items[screen.currentCategory][screen.currentTab][index]
		if item.imageUvs then 
			cell:getAttribute("icon"):setImageUVs(nil, unpack(item.imageUvs))
		end
	end
end
ConstructionScreen.populateCellForItemInSection = Utils.appendedFunction(ConstructionScreen.populateCellForItemInSection, populateCellForItemInSection)

--- Returns the cp tab, when the editor is active.
local function getConstructionTabByName(storeManager, superFunc, name, categoryName, ...)
	if g_courseEditor:getIsActive() then 
		return g_courseEditor:getTabByName(name, categoryName)
	end
	return superFunc(storeManager, name, categoryName, ...)
end
StoreManager.getConstructionTabByName = Utils.overwrittenFunction(StoreManager.getConstructionTabByName, getConstructionTabByName)

--- Returns the cp categories, when the editor is active.
local function getConstructionCategories(storeManager, superFunc, ...)
	if g_courseEditor:getIsActive() then 
		return g_courseEditor:getCategories()
	end
	return superFunc(storeManager, ...)
end
StoreManager.getConstructionCategories = Utils.overwrittenFunction(StoreManager.getConstructionCategories, getConstructionCategories)

--- Returns the cp category, when the editor is active.
local function getConstructionCategoryByName(storeManager, superFunc, name, ...)
	if g_courseEditor:getIsActive() then 
		return g_courseEditor:getCategoryByName(name)
	end
	return superFunc(storeManager, name, ...)
end
StoreManager.getConstructionCategoryByName = Utils.overwrittenFunction(StoreManager.getConstructionCategoryByName, getConstructionCategoryByName)

--- Disables the giants context, when the editor is active.
local function getItems(storeManager, superFunc, ...)
	if g_courseEditor:getIsActive() then 
		return {}
	end
	return superFunc(storeManager, ...)
end
StoreManager.getItems = Utils.overwrittenFunction(StoreManager.getItems, getItems)

--- Reverses the deconstruct button.
local function onClose(screen)
	if g_courseEditor:getIsActive() then 
		g_courseEditor:deactivate()
		if screen.destructBrush then 
			screen.destructBrush:delete()
			screen.destructBrush = nil
		end
	end
end
ConstructionScreen.onClose = Utils.appendedFunction(ConstructionScreen.onClose, onClose)

--- Switches the deconstruct button with the waypoint delete btn.
local function resetMenuState(screen)
	if g_courseEditor:getIsActive() then 	
		if screen.destructBrush then 
			screen.destructBrush:delete()
		end
		screen.destructBrush = CpBrushDeleteWP.new(nil, screen.cursor)
		screen.destructBrush:setParameters(
			g_courseEditor,
			CourseEditor.TRANSLATION_PREFIX .."delete",
			g_courseEditor.courseWrapper)
		screen.buttonDestruct:setText(g_i18n:getText(CourseEditor.TRANSLATION_PREFIX .. "delete_title", CourseEditor.MOD_NAME))
		local x, _, z = g_courseEditor.courseWrapper:getFirstWaypointPosition()
		screen.camera:setMapPosition(x, z)
	end
end
ConstructionScreen.resetMenuState = Utils.appendedFunction(ConstructionScreen.resetMenuState, resetMenuState)

local function registerMenuActionEvents(screen)
	if g_courseEditor.isActive and g_courseEditor.needsMultiToolDialog then 
		local _, eventId = screen.inputManager:registerActionEvent(InputAction.CONSTRUCTION_ACTION_SNAPPING, screen, 
			function(screen, actionName)
				local event = screen.inputManager:getFirstActiveEventForActionName(actionName)
				g_courseEditor:onClickLaneOffsetSetting(function(text)
					screen.inputManager:setActionEventText(event.id, string.format(g_i18n:getText("CP_editor_change_lane_offset"), text))
				end)
			end, false, true, false, true)
		g_courseEditor:onClickLaneOffsetSetting(function(text)
			screen.inputManager:setActionEventText(eventId, string.format(g_i18n:getText("CP_editor_change_lane_offset"), text))
		end, true)
		screen.inputManager:setActionEventActive(eventId, true)
		screen.inputManager:setActionEventTextVisibility(eventId, true)
	end
end
ConstructionScreen.registerMenuActionEvents = Utils.appendedFunction(ConstructionScreen.registerMenuActionEvents, registerMenuActionEvents)


g_courseEditor = CourseEditor.new()
