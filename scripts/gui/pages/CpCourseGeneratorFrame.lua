--[[
	This frame is a page for all global settings in the in game menu.
	All the layout, gui elements are cloned from the general settings page of the in game menu.
]]--

CpCourseGeneratorFrame = {
	CATEGRORIES = {
		IN_GAME_MAP = 1,
		BASIC_SETTINGS = 2,
		Vine_SETTINGS = 3
	},
	INPUT_CONTEXT_NAME = "CP_COURSE_GENERATOR_MENU",
	CATEGRORY_TEXTS = {
		"CP_ingameMenu_map_title",
		"CP_vehicle_courseGeneratorSetting_subTitle_fieldwork",
		"CP_vehicle_courseGeneratorSetting_subTitle_vineField",
	},
	CLEAR_INPUT_ACTIONS = {
		InputAction.MENU_ACTIVATE,
		InputAction.MENU_CANCEL,
		InputAction.MENU_EXTRA_1,
		InputAction.MENU_EXTRA_2,
		InputAction.SWITCH_VEHICLE,
		InputAction.SWITCH_VEHICLE_BACK,
		InputAction.CAMERA_ZOOM_IN,
		InputAction.CAMERA_ZOOM_OUT
	},
	CLEAR_CLOSE_INPUT_ACTIONS = {
		InputAction.SWITCH_VEHICLE,
		InputAction.SWITCH_VEHICLE_BACK,
		InputAction.CAMERA_ZOOM_IN,
		InputAction.CAMERA_ZOOM_OUT
	},
	CONTEXT_ACTIONS = {
		ENTER_VEHICLE 	= 1,
		CREATE_JOB		= 2,
		START_JOB		= 3,
		STOP_JOB		= 4,
		GENERATE_COURSE = 5,
		DELETE_CUSTOM_FIELD = 6,
		RENAME_CUSTOM_FIELD = 7,
		EDIT_CUSTOM_FIELD 	= 8
	},
	AI_MODE_OVERVIEW = 1,
	AI_MODE_CREATE = 2,
	AI_MODE_WORKER_LIST = 3,
	MAP_SELECTOR_HOTSPOT = 1,
	MAP_SELECTOR_CREATE_JOB = 2,
	MAP_SELECTOR_ACTIVE_JOBS = 3,
	CP_MAP_HOTSPOT_OFFSET = 200,
	BASE_XML_KEY = "CourseGenerator"

	-- POSITION_UVS = GuiUtils.getUVs({
	-- 	760,
	-- 	4,
	-- 	100,
	-- 	100
	-- }, AIPlaceableMarkerHotspot.FILE_RESOLUTION)
}
CpCourseGeneratorFrame.NUM_CATEGORIES = #CpCourseGeneratorFrame.CATEGRORY_TEXTS

local CpCourseGeneratorFrame_mt = Class(CpCourseGeneratorFrame, TabbedMenuFrameElement)

function CpCourseGeneratorFrame.new(target, custom_mt)
	local self = TabbedMenuFrameElement.new(target, custom_mt or CpCourseGeneratorFrame_mt)
	self.subCategoryPages = {}
	self.subCategoryTabs = {}
	self.contextActions = {}
	self.contextActionMapping = {}
	self.playerFarmActiveJobs = {}
	self.activeInfoTexts = {}
	self.hasFullScreenMap = true
	self.dataTables = {}
	self.hotspotModeActive = false
	self.currentHotspot = nil
	self.staticUIDeadzone = {0, 0, 0, 0}
	self.selectedVehicle = nil
	self.jobTypeInstances = {}
	self.currentJobTypes = {}
	self.currentJob = nil
	self.currentJobElements = {}
	self.statusMessages = {}
	self.mode = self.AI_MODE_OVERVIEW
	self.lastMousePosX = 0
	self.lastMousePosY = 0

	self.lastInputHelpMode = 0
	self.hotspotFilterState = {}
	self.isInputContextActive = false
	self.driveToAiTargetMapHotspot = AITargetHotspot.new()
	self.fieldSiloAiTargetMapHotspot = AITargetHotspot.new()
	self.fieldSiloAiTargetMapHotspot.icon:setUVs(
		GuiUtils.getUVs({760, 0, 100, 100}, 
		AIPlaceableMarkerHotspot.FILE_RESOLUTION))
	self.unloadAiTargetMapHotspot = AITargetHotspot.new()
	self.unloadAiTargetMapHotspot.icon:delete()
	self.unloadAiTargetMapHotspot.icon = g_overlayManager:createOverlay(
		"cpUi.unloadMarker", 0, 0, 
		self.unloadAiTargetMapHotspot.width, 
		self.unloadAiTargetMapHotspot.height)
	self.loadAiTargetMapHotspot = AITargetHotspot.new()
	self.loadAiTargetMapHotspot.icon:delete()
	self.loadAiTargetMapHotspot.icon = g_overlayManager:createOverlay(
		"cpUi.loadMarker", 0, 0, 
		self.loadAiTargetMapHotspot.width, 
		self.loadAiTargetMapHotspot.height)

	self.aiTargetMapHotspot = self.driveToAiTargetMapHotspot
	self.updateTime = 0
	self.mapSelectorTexts = {
		g_i18n:getText("ui_mapOverviewHotspots"),
		g_i18n:getText("button_createJob"),
		g_i18n:getText("ui_activeAIJobs")}

	--- Bitmask for the visible cp hotspots.
	self.cpHotspotSettingValue = 1
	return self
end

function CpCourseGeneratorFrame.setupGui()
	local courseGeneratorFrame = CpCourseGeneratorFrame.new()
	g_gui:loadGui(Utils.getFilename("config/gui/pages/CourseGeneratorFrame.xml", Courseplay.BASE_DIRECTORY),
	 			 "CpCourseGeneratorFrame", courseGeneratorFrame, true)
end

function CpCourseGeneratorFrame.createFromExistingGui(gui, guiName)
	local newGui = CpCourseGeneratorFrame.new(nil, nil)

	g_gui.frames[gui.name].target:delete()
	g_gui.frames[gui.name]:delete()
	g_gui:loadGui(gui.xmlFilename, guiName, newGui, true)

	return newGui
end

function CpCourseGeneratorFrame.registerXmlSchema(xmlSchema, xmlKey)
	xmlKey = xmlKey .. CpCourseGeneratorFrame.BASE_XML_KEY
	xmlSchema:register(XMLValueType.INT, xmlKey .. "#mapHotspotValue", "Selected hotspots")
end


function CpCourseGeneratorFrame:loadFromXMLFile(xmlFile, baseKey)
	--- We save the hotspot setting in the Courseplay User settings, 
	--- as we don't want to pollute the giants hotspot setting.
	self.cpHotspotSettingValue = xmlFile:getValue(
		string.format("%s%s#mapHotspotValue", baseKey, self.BASE_XML_KEY), 0xFF)
end

function CpCourseGeneratorFrame:saveToXMLFile(xmlFile, baseKey)
	xmlFile:setValue(string.format("%s%s#mapHotspotValue", 
		baseKey, self.BASE_XML_KEY), self.cpHotspotSettingValue)
end

function CpCourseGeneratorFrame:setInGameMap(ingameMap, hud)
	self.ingameMapBase = ingameMap
	self.ingameMap:setIngameMap(ingameMap)
	self.hud = hud
end

function CpCourseGeneratorFrame:initialize(menu)
	self.cpMenu = menu
	self.onClickBackCallback = menu.clickBackCallback
	self:initializeContextActions()

	self.generateCourseMenuButton = {
		["inputAction"] = InputAction.MENU_EXTRA_1,
		["text"] = g_i18n:getText("button_blocklist"),
		["callback"] = function()
			-- upvalues: (copy) p_u_39
			p_u_39:onButtonUnBan()
		end
	}


	self.booleanPrefab:unlinkElement()
	FocusManager:removeElement(self.booleanPrefab)
	self.multiTextPrefab:unlinkElement()
	FocusManager:removeElement(self.multiTextPrefab)
	self.sectionHeaderPrefab:unlinkElement()
	FocusManager:removeElement(self.sectionHeaderPrefab)
	self.selectorPrefab:unlinkElement()
	FocusManager:removeElement(self.selectorPrefab)
	self.containerPrefab:unlinkElement()
	FocusManager:removeElement(self.containerPrefab)

	self.createMultiOptionTemplate:unlinkElement()
	FocusManager:removeElement(self.createMultiOptionTemplate)
	self.createTextTemplate:unlinkElement()
	FocusManager:removeElement(self.createTextTemplate)
	self.createTitleTemplate:unlinkElement()
	FocusManager:removeElement(self.createTitleTemplate)
	self.createPositionTemplate:unlinkElement()
	FocusManager:removeElement(self.createPositionTemplate)
	self.createPositionRotationTemplate:unlinkElement()
	FocusManager:removeElement(self.createPositionRotationTemplate)
	self.createButtonTemplate:unlinkElement()
	FocusManager:removeElement(self.createButtonTemplate)
	
	for key = 1, CpCourseGeneratorFrame.NUM_CATEGORIES do 
		self.subCategoryPaging:addText(tostring(key))
		self.subCategoryTabs[key] = self.selectorPrefab:clone(self.subCategoryBox)
		FocusManager:loadElementFromCustomValues(self.subCategoryTabs[key])
		self.subCategoryTabs[key]:setText(g_i18n:getText(self.CATEGRORY_TEXTS[key]))
		self.subCategoryTabs[key]:getDescendantByName("background"):setSize(
			self.subCategoryTabs[key].size[1], self.subCategoryTabs[key].size[2])
		self.subCategoryTabs[key].onClickCallback = function ()
			self:updateSubCategoryPages(key)
		end
		if key == self.CATEGRORIES.IN_GAME_MAP then
			self.subCategoryPages[key] = self.containerMap
		else
			self.subCategoryPages[key] = self.containerPrefab:clone(self)
			local layout = self.subCategoryPages[key]:getDescendantByName("layout")
			layout.scrollDirection = "vertical"
			FocusManager:loadElementFromCustomValues(self.subCategoryPages[key])
			-- FocusManager:linkElements(self.subCategoryPages[key], FocusManager.BOTTOM, layout)
			-- FocusManager:linkElements(layout, FocusManager.TOP, self.subCategoryPages[key])
		end
	end
	self.mapOverviewSelector:setTexts(self.mapSelectorTexts)
	self.mapOverviewSelector:setState(1, true)
	self.subCategoryBox:invalidateLayout()
	self.subCategoryPaging:setSize(self.subCategoryBox.maxFlowSize + 140 * g_pixelSizeScaledX)

	self.hotspotFilterCategories = {}
	for i, v in pairs(InGameMenuMapFrame.HOTSPOT_FILTER_CATEGORIES) do 
		self.hotspotFilterCategories[i] = table.clone(v)
	end
	table.insert(self.hotspotFilterCategories[2], {
		["id"] = CustomFieldHotspot.CATEGORY,
		["sliceId"] = CustomFieldHotspot.SLICE_ID,
		["name"] = CustomFieldHotspot.NAME,
		["color"] = {CustomFieldHotspot.COLOR}})
	self.CUSTOM_FIELD_HOTSPOTS = #self.hotspotFilterCategories[2]

	self.hotspotStateFilter = {}
	for i, data in ipairs(self.hotspotFilterCategories) do 
		self.hotspotStateFilter[i] = {}
		for j, _ in ipairs(data) do 
			self.hotspotStateFilter[i][j] = false
		end

	end

	self.currentContextBox = self.contextBox 
	self.currentHotspot = nil
	self.generateCoursePending = false
end

function CpCourseGeneratorFrame:update(dt)
	if self.updateTime < g_time then
		for i = 1, self.activeWorkerList:getItemCount() do
			local element = self.activeWorkerList:getElementAtSectionIndex(1, i)
			if element ~= nil then
				local job = g_currentMission.aiSystem:getJobById(self.playerFarmActiveJobs[i])
				if job ~= nil then
					element:getAttribute("text"):setText(job:getDescription())
				end
			end
		end
		self.updateTime = g_time + 1000
		local vehicle = self.cpMenu:getCurrentVehicle()
		if vehicle then 
			if vehicle.getIsCpActive and vehicle:getIsCpActive() then 
				local status = vehicle:getCpStatus()
				self.contextBox:getDescendantByName("statusText"):setText(status:getText())
			else 
				self.contextBox:getDescendantByName("statusText"):setText("")
			end
		end
	end
	local hasChanged = false
	for i = 1, #self.statusMessages do
		local removeTime = self.statusMessages[1].removeTime
		if removeTime < g_time then
			table.remove(self.statusMessages, 1)
			hasChanged = true
		end
	end
	if hasChanged then
		self:updateStatusMessages()
	end
	CpCourseGeneratorFrame:superClass().update(self, dt)
end

function CpCourseGeneratorFrame:updateSettings(vehicle)
	local settings = vehicle:getCourseGeneratorSettings()
	local settingsBySubTitle = CpCourseGeneratorSettings.getSettingSetup()

	local layout = self.subCategoryPages[self.CATEGRORIES.BASIC_SETTINGS]:getDescendantByName("layout")
	for i = #layout.elements, 1, -1 do
		layout.elements[i]:delete()
	end
	CpSettingsUtil.generateAndBindGuiElementsToSettings(settingsBySubTitle,
		layout, self.multiTextPrefab, self.booleanPrefab, 
		self.sectionHeaderPrefab, settings)
	CpSettingsUtil.updateGuiElementsBoundToSettings(layout, vehicle)

	settings = vehicle:getCpVineSettings()
	settingsBySubTitle = CpCourseGeneratorSettings.getVineSettingSetup()
	layout = self.subCategoryPages[self.CATEGRORIES.Vine_SETTINGS]:getDescendantByName("layout")
	for i = #layout.elements, 1, -1 do
		layout.elements[i]:delete()
	end
	CpSettingsUtil.generateAndBindGuiElementsToSettings(settingsBySubTitle,
		layout, self.multiTextPrefab, self.booleanPrefab, 
		self.sectionHeaderPrefab, settings)
	CpSettingsUtil.updateGuiElementsBoundToSettings(layout, vehicle)
end

function CpCourseGeneratorFrame:onFrameOpen()
	self.ingameMap:setTerrainSize(g_currentMission.terrainSize)
	g_messageCenter:subscribe(MessageType.GUI_CP_INGAME_CURRENT_VEHICLE_CHANGED, 
		function(self, vehicle)
			local _, pageTitle = CpCourseGeneratorSettings.getSettingSetup()
			local title = string.format(g_i18n:getText(pageTitle), vehicle and vehicle:getName() or "--")
			self.categoryHeaderText:setText(title)
		end, self)

	g_messageCenter:subscribe(MessageType.AI_VEHICLE_STATE_CHANGE, function(self, _, vehicle)
		if self.cpMenu:getCurrentVehicle() == vehicle then
			self:updateContextActions()
		end
	end, self)

	g_messageCenter:subscribe(MessageType.AI_JOB_STARTED, function(self, job, farmId)
		if g_localPlayer ~= nil and farmId == g_localPlayer.farmId then
			table.insert(self.playerFarmActiveJobs, job.jobId)
		end
		self.activeWorkerList:reloadData()
	end, self)

	g_messageCenter:subscribe(MessageType.AI_JOB_STOPPED, function(self, job, aiMessage)
		if aiMessage ~= nil and job ~= nil and g_localPlayer ~= nil then
			if job.startedFarmId == g_localPlayer.farmId then
				local text = aiMessage:getMessage(job)
				local releaseMessage= g_infoTextManager:getInfoTextDataByAIMessage(aiMessage)
				if g_Courseplay.globalSettings.infoTextHudActive:getValue() == g_Courseplay.globalSettings.DISABLED or 
					not releaseMessage then 
					self:addStatusMessage(text)
				end 
			end
		end
	end, self)
	g_messageCenter:subscribe(MessageType.AI_JOB_REMOVED, function(self, jobId)
		table.removeElement(self.playerFarmActiveJobs, jobId)
		self.activeWorkerList:reloadData()
		InGameMenuMapUtil.hideContextBox(self.contextBox)
		InGameMenuMapUtil.hideContextBox(self.contextBoxPlayer)
		InGameMenuMapUtil.hideContextBox(self.contextBoxFarmland)
	end, self)
	g_messageCenter:subscribe(MessageType.CP_INFO_TEXT_CHANGED, function (menu)
		self.infoTextList:reloadData()
	end, self)
	g_messageCenter:subscribe(MessageType.CP_CUSTOM_FIELD_CHANGED, function (menu)
		if self.currentHotspot and self.currentHotspot:isa(CustomFieldHotspot) then 
			self:setMapSelectionItem(self.currentHotspot)
		end
		self.infoTextList:reloadData()
	end, self)
	-- g_messageCenter:subscribe(MessageType.AI_TASK_SKIPPED, self.onAITaskSkipped, self)
	local hotspotValue = g_gameSettings:getValue(GameSettings.SETTING.INGAME_MAP_HOTSPOT_FILTER)
	------------------------------------------
	--- Loads the hotspot selection
	------------------------------------------
	for i, hotspotCategory in pairs(self.hotspotFilterCategories[1]) do 
		local isBitSet = Utils.isBitSet(hotspotValue, hotspotCategory.id)
		if hotspotCategory.id >= self.CP_MAP_HOTSPOT_OFFSET then 
			--- Every hotspot selection with a greater ID than X will be saved in the courseplay user settings.
			isBitSet = Utils.isBitSet(self.cpHotspotSettingValue, hotspotCategory.id - self.CP_MAP_HOTSPOT_OFFSET)
		end
		self.hotspotStateFilter[1][i] = isBitSet
		self.ingameMapBase:setDefaultFilterValue(hotspotCategory.id, isBitSet)
	end
	for i, hotspotCategory in pairs(self.hotspotFilterCategories[2]) do 
		local isBitSet = Utils.isBitSet(hotspotValue, hotspotCategory.id)
		if hotspotCategory.id >= self.CP_MAP_HOTSPOT_OFFSET then 
			--- Every hotspot selection with a greater ID than X will be saved in the courseplay user settings.
			isBitSet = Utils.isBitSet(self.cpHotspotSettingValue, hotspotCategory.id - self.CP_MAP_HOTSPOT_OFFSET)
		end
		self.hotspotStateFilter[2][i] = isBitSet
		self.ingameMapBase:setDefaultFilterValue(hotspotCategory.id, isBitSet)
	end
	local allDeactivated = true
	for _, filter in pairs(self.hotspotStateFilter) do 
		for i, state in pairs(filter) do
			allDeactivated = allDeactivated and not state
		end
	end
	if allDeactivated then 
		self.buttonDeselectAllText:setText(g_i18n:getText(InGameMenuMapFrame.L10N_SYMBOL.SELECT_ALL))
	else 
		self.buttonDeselectAllText:setText(g_i18n:getText(InGameMenuMapFrame.L10N_SYMBOL.DESELECT_ALL))
	end
	local farmId = g_localPlayer == nil and 1 or g_localPlayer.farmId
	for _, job in ipairs(g_currentMission.aiSystem:getActiveJobs()) do
		if job.startedFarmId == farmId then
			table.insert(self.playerFarmActiveJobs, job.jobId)
		end
	end
	self.activeWorkerList:reloadData()
	self.filterList:reloadData()
	if g_Courseplay.globalSettings.infoTextHudActive:getValue() > 0 then 
		self.infoTextList:reloadData()
		self.infoTextHud:setVisible(true)
	else 
		self.infoTextHud:setVisible(false)
	end
	self.ingameMapBase:restoreDefaultFilter()
	self:generateJobTypes()
	self.mode = self.AI_MODE_OVERVIEW
	self.currentJob = nil
	self.currentJobVehicle = nil
	self.currentHotspot = nil
	self:setJobMenuVisible(false)
	self.startJobPending = false
	self.ingameMap:onOpen()

	self:updateSubCategoryPages(self.CATEGRORIES.IN_GAME_MAP)

	CpCourseGeneratorFrame:superClass().onFrameOpen(self)
	self:updateCourseGenerator(false)
	local vehicle = self.cpMenu:getCurrentVehicle()
	if vehicle and self.currentHotspot == nil then
		self:setAIVehicle(vehicle)
	elseif vehicle == nil then
		self:updateSubCategoryPages(self.CATEGRORIES.IN_GAME_MAP)
		self:setMapSelectionItem(nil)
	end	
	g_customFieldManager:refresh()
end

function CpCourseGeneratorFrame:saveHotspotFilter()
	local hotspotValue = 0
	self.cpHotspotSettingValue = 0
	for i, state in pairs(self.hotspotStateFilter[1]) do 
		if state then
			local id = self.hotspotFilterCategories[1][i].id
			if id >= self.CP_MAP_HOTSPOT_OFFSET then 
				self.cpHotspotSettingValue = Utils.setBit(self.cpHotspotSettingValue, id - self.CP_MAP_HOTSPOT_OFFSET)
			else 
				hotspotValue = Utils.setBit(hotspotValue, id)
			end
		end
	end
	for i, state in pairs(self.hotspotStateFilter[2]) do 
		if state then
			local id = self.hotspotFilterCategories[2][i].id
			if id >= self.CP_MAP_HOTSPOT_OFFSET then 
				self.cpHotspotSettingValue = Utils.setBit(self.cpHotspotSettingValue, id - self.CP_MAP_HOTSPOT_OFFSET)
			else 
				hotspotValue = Utils.setBit(hotspotValue, id)
			end
		end
	end
	g_gameSettings:setValue(GameSettings.SETTING.INGAME_MAP_HOTSPOT_FILTER, hotspotValue, true)
	local allDeactivated = true
	for _, filter in pairs(self.hotspotStateFilter) do 
		for i, state in pairs(filter) do
			allDeactivated = allDeactivated and not state
		end
	end
	if allDeactivated then 
		self.buttonDeselectAllText:setText(g_i18n:getText(InGameMenuMapFrame.L10N_SYMBOL.SELECT_ALL))
	else 
		self.buttonDeselectAllText:setText(g_i18n:getText(InGameMenuMapFrame.L10N_SYMBOL.DESELECT_ALL))
	end
end

function CpCourseGeneratorFrame:onFrameClose()
	self:closeMap()
	g_messageCenter:unsubscribeAll(self)
	self.jobTypeInstances = {}
	g_currentMission:removeMapHotspot(self.driveToAiTargetMapHotspot)
	g_currentMission:removeMapHotspot(self.fieldSiloAiTargetMapHotspot)
	g_currentMission:removeMapHotspot(self.unloadAiTargetMapHotspot)
	g_currentMission:removeMapHotspot(self.loadAiTargetMapHotspot)
	self.ingameMap:onClose()
	self.ingameMapBase:restoreDefaultFilter()
	if not self:getIsPicking() then
		self:executePickingCallback(false)
	end
	self.mode = self.AI_MODE_OVERVIEW
	self:setJobMenuVisible(false)
	self.statusMessages = {}
	self:updateStatusMessages()
	self.startJobPending = false
	CpCourseGeneratorFrame:superClass().onFrameClose(self)
end

function CpCourseGeneratorFrame:onClickBack(force)
	if self.startJobPending and not force then
		return false
	end
	if self.generateCoursePending and not force then 
		return false
	end
	if self.mode == self.AI_MODE_CREATE then 
		if self:getIsPicking() then
			self:executePickingCallback(false)
			self:updateContextActions()
			if not force then
				return false
			end
		end 
		self.mode = self.AI_MODE_OVERVIEW
		self:setJobMenuVisible(false)
		if not force then 
			self:setMapSelectionItem(self.currentHotspot)
			return false
		end
		self:setMapSelectionItem(nil)
	elseif self.currentHotspot then 
		self:setMapSelectionItem(nil)
		return force
	end
	return true
end

function CpCourseGeneratorFrame:onClickCpMultiTextOption(_, guiElement)
	CpSettingsUtil.updateGuiElementsBoundToSettings(guiElement.parent.parent, self.cpMenu:getCurrentVehicle())
end

function CpCourseGeneratorFrame:updateCourseGenerator(visible, vehicle)
	if visible then 
		self.subCategoryPaging:setDisabled(false)
		for ix=1, self.NUM_CATEGORIES do 
			if ix ~= self.CATEGRORIES.IN_GAME_MAP then
				self.subCategoryTabs[ix]:setDisabled(false)		
			end
		end
		self:updateSettings(vehicle)
	else
		self:updateSubCategoryPages(self.CATEGRORIES.IN_GAME_MAP)
		self.subCategoryPaging:setDisabled(true)
		for ix=1, self.NUM_CATEGORIES do 
			if ix ~= self.CATEGRORIES.IN_GAME_MAP then
				self.subCategoryTabs[ix]:setDisabled(true)		
			end
		end
	end
end

function CpCourseGeneratorFrame:updateSubCategoryPages(state)
	self.menuButtonInfo = table.clone(self.cpMenu.defaultMenuButtonInfo) 
	for i, _ in ipairs(self.subCategoryPages) do
		self.subCategoryPages[i]:setVisible(false)
		self.subCategoryTabs[i]:setSelected(false)
	end
	self.subCategoryPages[state]:setVisible(true)
	self.subCategoryTabs[state]:setSelected(true)
	local layout = self.subCategoryPages[state]:getDescendantByName("layout")
	if layout then
		self:closeMap()
		self.settingsSliderBox:setVisible(true)
		self.ingameMap:setVisible(false)
		layout:invalidateLayout()
		self.settingsSlider:setDataElement(layout)
		FocusManager:setFocus(self.subCategoryPages[state])
		table.insert(self.menuButtonInfo, {
			inputAction = InputAction.MENU_EXTRA_2,
			text = g_i18n:getText("CP_ai_page_generate_course"),
			callback = function ()
				if self:generateFieldworkCourse() then
					self:updateSubCategoryPages(self.CATEGRORIES.IN_GAME_MAP)
				end
			end})

	else
		self.settingsSliderBox:setVisible(false)
		self.ingameMap:setVisible(true)
		self:openMap()
	end 
	self:setMenuButtonInfoDirty()
end

function CpCourseGeneratorFrame:delete()
	g_messageCenter:unsubscribeAll(self)
	self.booleanPrefab:delete()
	self.multiTextPrefab:delete()
	self.sectionHeaderPrefab:delete()
	self.selectorPrefab:delete()
	self.containerPrefab:delete()
	self.driveToAiTargetMapHotspot:delete()
	self.fieldSiloAiTargetMapHotspot:delete()
	self.unloadAiTargetMapHotspot:delete()
	self.loadAiTargetMapHotspot:delete()
	CpCourseGeneratorFrame:superClass().delete(self)
end
-------------------------------
-- InGameMap
-------------------------------

function CpCourseGeneratorFrame:onDrawPostIngameMapHotspots()
	if self.currentContextBox and self.currentHotspot and self.currentContextBox:getIsVisible() then
		local posX, posY, _ = self.currentHotspot:getLastScreenPositionCenter()
		local buttonBox = self.currentContextBox:getDescendantByName("buttonBox")
		local bottomOffset = buttonBox == nil and 0 or (buttonBox.contentSize or 0)
		local outRight = posX + self.currentContextBox.size[1] > self.rightBackground.absPosition[1]
		local outLeft = posX - self.currentContextBox.size[1] < self.leftBox.absPosition[1] + self.leftBox.size[1]
		local outTop = posY + self.currentContextBox.size[2] + bottomOffset > self.topBackground.absPosition[2]
		-- local outBottom = posY + self.currentContextBox.size[2] + bottomOffset > self.cpTopSideBackground.absPosition[2]
		local orientation = InGameMenuMapUtil.CONTEXT_BOX_ORIENTATION.TOP_RIGHT
		if outRight then
			if outTop then
				orientation = InGameMenuMapUtil.CONTEXT_BOX_ORIENTATION.BOTTOM_LEFT
			else
				orientation = InGameMenuMapUtil.CONTEXT_BOX_ORIENTATION.TOP_LEFT
			end
		elseif outLeft then
			if outTop then
				orientation = InGameMenuMapUtil.CONTEXT_BOX_ORIENTATION.BOTTOM_RIGHT
			else
				orientation = InGameMenuMapUtil.CONTEXT_BOX_ORIENTATION.TOP_RIGHT
			end
		elseif outTop then
			orientation = InGameMenuMapUtil.CONTEXT_BOX_ORIENTATION.BOTTOM_RIGHT
		end
		
		local goLeft = orientation == InGameMenuMapUtil.CONTEXT_BOX_ORIENTATION.TOP_LEFT and true or orientation == InGameMenuMapUtil.CONTEXT_BOX_ORIENTATION.BOTTOM_LEFT
		local goDown = orientation == InGameMenuMapUtil.CONTEXT_BOX_ORIENTATION.BOTTOM_LEFT and true or orientation == InGameMenuMapUtil.CONTEXT_BOX_ORIENTATION.BOTTOM_RIGHT
		if goLeft then
			posX = posX - self.currentContextBox.size[1]
		end
		if goDown then
			posY = posY - self.currentContextBox.size[2]
		end
		self.currentContextBox:setAbsolutePosition(posX, posY + ((buttonBox == nil or 
			orientation ~= InGameMenuMapUtil.CONTEXT_BOX_ORIENTATION.TOP_RIGHT and 
				orientation ~= InGameMenuMapUtil.CONTEXT_BOX_ORIENTATION.TOP_LEFT) and 
			0 or (buttonBox.contentSize or 0)))


	end
	if self.aiTargetMapHotspot ~= nil then

		local icon = self.aiTargetMapHotspot.icon
		
		--Lx: [952, 952], [19, 35], 1
		self.actionMessage:setAbsolutePosition(icon.x + icon.width * 0.5, icon.y + icon.height * 0.5)
	end
end

function CpCourseGeneratorFrame:onDrawPostIngameMap(element, ingameMap)
	local areCursePlotsAlwaysVisible = g_Courseplay.globalSettings:getSettings().showsAllActiveCourses:getValue()
	local vehicle = self.cpMenu:getCurrentVehicle()
	if areCursePlotsAlwaysVisible then
		local vehicles = g_assignedCoursesManager:getRegisteredVehicles()
		for _, v in pairs(vehicles) do
			if g_currentMission.accessHandler:canPlayerAccess(v) then
				v:drawCpCoursePlot(ingameMap)
			end
		end
	elseif vehicle and vehicle.drawCpCoursePlot  then 
		vehicle:drawCpCoursePlot(ingameMap)
	end
	if self.hotspotStateFilter[2][self.CUSTOM_FIELD_HOTSPOTS] then
		-- show the custom fields on the AI map
		g_customFieldManager:draw(ingameMap)
	end
	-- show the selected field on the AI screen map when creating a job
	if self.currentJob and self.currentJob.draw then
		self.currentJob:draw(ingameMap, self.mode == self.MODE_OVERVIEW)
	end
	g_graph:drawMap(ingameMap)

	--- Draws the current progress, while creating a custom field.
	-- if pageAI.mode == CpInGameMenuAIFrameExtended.MODE_DRAW_FIELD_BORDER and next(CpInGameMenuAIFrameExtended.curDrawPositions) then
	-- 	local localX, localY = pageAI.ingameMap:getLocalPosition(g_inputBinding.mousePosXLast, g_inputBinding.mousePosYLast)
	-- 	local worldX, worldZ = pageAI.ingameMap:localToWorldPos(localX, localY)

	-- 	if #CpInGameMenuAIFrameExtended.curDrawPositions > 0 then
	-- 		local pos = CpInGameMenuAIFrameExtended.curDrawPositions[#CpInGameMenuAIFrameExtended.curDrawPositions]
	-- 		local dx, dz, length = CpMathUtil.getPointDirection( pos, {x = worldX, z = worldZ})
	-- 		if Input.isKeyPressed(Input.KEY_lshift) then
	-- 			if math.abs(dx) > math.abs(dz) then 
	-- 				dz = 0
	-- 				dx = math.sign(dx)
	-- 			else
	-- 				dx = 0
	-- 				dz = math.sign(dz)
	-- 			end
	-- 			worldX = pos.x + dx * length
	-- 			worldZ = pos.z + dz * length
	-- 		end
	-- 		pageAI.customFieldPlot:setNextTargetPoint(worldX, worldZ)
	-- 	else 
	-- 		pageAI.customFieldPlot:setNextTargetPoint()
	-- 	end


	-- 	pageAI.customFieldPlot:setWaypoints(CpInGameMenuAIFrameExtended.curDrawPositions)
	-- 	pageAI.customFieldPlot:draw(self,true)
	-- 	pageAI.customFieldPlot:setVisible(true)
	-- end

end

function CpCourseGeneratorFrame:onClickMap(element ,worldX, worldZ)
	if self.isPickingLocation then 
		self:executePickingCallback(true, worldX, worldZ)
		return
	end
	if self.isPickingRotation then 
		local angle = math.atan2(worldX - self.pickingRotationOrigin[1], worldZ - self.pickingRotationOrigin[2])
		self:executePickingCallback(true, angle)
		return
	end
	self:setMapSelectionItem(nil)
end

function CpCourseGeneratorFrame:onClickHotspot(element, hotspot)
	if self.isPickingLocation then 
		self:executePickingCallback(true, hotspot.worldX, hotspot.worldZ)
		return 
	end 
	if self.isPickingRotation then 
		self:executePickingCallback(true, worldX, worldZ)
		self:executePickingCallback(true, math.atan2(hotspot.worldX - self.pickingRotationOrigin[0], hotspot.worldZ - self.pickingRotationOrigin[1]))
		return
	end
	self:setMapSelectionItem(hotspot)
end

function CpCourseGeneratorFrame:showMapHotspot(self, hotspot) 
	self:onClickHotspot(nil, hotspot)
	self.ingameMap:panToHotspot(hotspot)
end

function CpCourseGeneratorFrame:onClickMapOverviewSelector(state)
	self.filterListContainer:setVisible(false)
	self.createJobContainer:setVisible(false)
	self.workerListContainer:setVisible(false)
	for i = 1, #self.mapSelectorTexts do
		self.subCategoryDotBox.elements[i]:setSelected(false)
	end
	self.subCategoryDotBox.elements[state]:setSelected(true)
	if state == self.MAP_SELECTOR_HOTSPOT then
		self.filterListContainer:setVisible(true)
	elseif state == self.MAP_SELECTOR_CREATE_JOB then
		self.createJobContainer:setVisible(true)
		-- self.subCategoryDotBox:invalidateLayout()
	elseif state == self.MAP_SELECTOR_ACTIVE_JOBS then
		self.workerListContainer:setVisible(true)
	end
end

function CpCourseGeneratorFrame:onClickDeselectAll()
	local allDeactivated = true
	for _, filter in pairs(self.hotspotStateFilter) do 
		for i, state in pairs(filter) do
			allDeactivated = allDeactivated and not state
		end
	end
	for i, filter in pairs(self.hotspotStateFilter) do 
		for j, state in pairs(filter) do
			self.ingameMapBase:setDefaultFilterValue(self.hotspotFilterCategories[i][j].id, allDeactivated)
			self.hotspotStateFilter[i][j] = allDeactivated
		end
	end
	self.ingameMapBase:restoreDefaultFilter()
	self:saveHotspotFilter()
	self.filterList:reloadData()
end

function CpCourseGeneratorFrame:onJobTypeChanged(index)
	local jobTypeIndex = self.currentJobTypes[index]
	self:setActiveJobTypeSelection(jobTypeIndex)
end

function CpCourseGeneratorFrame:onClickMultiTextOptionParameter(index, element)
	if self.currentJob ~= nil then
		self.currentJob:onParameterValueChanged(element.aiParameter)
		self:updateParameterValueTexts()
	end
	self:validateParameters()
end

function CpCourseGeneratorFrame:onClickMultiTextOptionCenterParameter()
	
end

function CpCourseGeneratorFrame:executePickingCallback(...)
	self.ingameMap:setHotspotSelectionActive(true)
	self.isPickingLocation = false
	self.isPickingRotation = false
	self.ingameMap:unlockMapMovement()
	local cb = self.pickingCallback
	self.pickingCallback = nil
	if cb ~= nil then
		cb(...)
	end
end

function CpCourseGeneratorFrame:onClickPositionParameter(element)
	self.currentContextBox:setVisible(false)
	local parameter = element.aiParameter
	g_currentMission:removeMapHotspot(self.loadAiTargetMapHotspot)
	g_currentMission:removeMapHotspot(self.fieldSiloAiTargetMapHotspot)
	g_currentMission:removeMapHotspot(self.unloadAiTargetMapHotspot)
	g_currentMission:removeMapHotspot(self.driveToAiTargetMapHotspot)
	if parameter:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.LOAD then 
		self.aiTargetMapHotspot = self.loadAiTargetMapHotspot
	elseif parameter:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.FIELD_OR_SILO then 
		self.aiTargetMapHotspot = self.fieldSiloAiTargetMapHotspot
	elseif parameter:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.UNLOAD then 
		self.aiTargetMapHotspot = self.unloadAiTargetMapHotspot
	else
		self.aiTargetMapHotspot = self.driveToAiTargetMapHotspot
	end
	g_currentMission:addMapHotspot(self.aiTargetMapHotspot)
	self.ingameMap:setHotspotSelectionActive(false)
	self.ingameMap:setIsCursorAvailable(false)
	self.isPickingLocation = true
	self:showActionMessage("ui_ai_pickTargetLocation")
	function self.pickingCallback(success, x, z)
		self.currentContextBox:setVisible(true)
		self:showActionMessage()
		self.ingameMap:setIsCursorAvailable(true)
		if success then
			parameter:setValue(x, z)
			self.aiTargetMapHotspot:setWorldPosition(x, z)
		end
		self:validateParameters()
		self:updateParameterValueTexts()
	end
end

function CpCourseGeneratorFrame:onClickPositionRotationParameter(element)
	self.currentContextBox:setVisible(false)
	local parameter = element.aiParameter
	g_currentMission:removeMapHotspot(self.loadAiTargetMapHotspot)
	g_currentMission:removeMapHotspot(self.fieldSiloAiTargetMapHotspot)
	g_currentMission:removeMapHotspot(self.unloadAiTargetMapHotspot)
	g_currentMission:removeMapHotspot(self.driveToAiTargetMapHotspot)
	if parameter:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.LOAD then 
		self.aiTargetMapHotspot = self.loadAiTargetMapHotspot
	elseif parameter:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.FIELD_OR_SILO then 
		self.aiTargetMapHotspot = self.fieldSiloAiTargetMapHotspot
	elseif parameter:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.UNLOAD then 
		self.aiTargetMapHotspot = self.unloadAiTargetMapHotspot
	else
		self.aiTargetMapHotspot = self.driveToAiTargetMapHotspot
	end
	g_currentMission:addMapHotspot(self.aiTargetMapHotspot)
	self.isPickingLocation = true
	self.ingameMap:setHotspotSelectionActive(false)
	self.ingameMap:setIsCursorAvailable(false)
	self:showActionMessage("ui_ai_pickTargetLocation")
	function self.pickingCallback(success, x, z)
		self:showActionMessage()
		self.ingameMap:setIsCursorAvailable(true)
		self.currentContextBox:setVisible(true)

		if success then
			self.currentContextBox:setVisible(false)
			self.ingameMap:setHotspotSelectionActive(false)
			self.ingameMap:setIsCursorAvailable(false)
			self.ingameMap:lockMapMovement()
			self.aiTargetMapHotspot:setWorldPosition(x, z)
			self.isPickingRotation = true
			self.pickingRotationOrigin = {x, z}
			self.pickingRotationSnapAngle = parameter:getSnappingAngle()
			self:showActionMessage("ui_ai_pickTargetRotation")

			function self.pickingCallback(successRotation, angle)
				self:showActionMessage()
				self.ingameMap:setIsCursorAvailable(true)
				self.currentContextBox:setVisible(true)
				if successRotation then
					parameter:setPosition(x, z)
					parameter:setAngle(angle)
					local convertedAngle = parameter:getAngle()
					self.aiTargetMapHotspot:setWorldRotation(convertedAngle + math.pi)
				end
				self:validateParameters()
				self:updateParameterValueTexts()
			end
		else
			self:validateParameters()
			self:updateParameterValueTexts()
		end
	end
end

function CpCourseGeneratorFrame:getIsPicking()
	return self.isPickingRotation or self.isPickingLocation
end

function CpCourseGeneratorFrame:validateParameters()
	local isValid = true
	local errorText = ""
	if self.currentJob ~= nil then
		self.currentJob:setValues()
		self.currentJob:registerFieldBoundaryDetectionCallback(self, self.onFieldBoundaryDetectionFinished)
		isValid, errorText = self.currentJob:validate()
		self:updateWarnings()
		self:updateContextActions()
	end
	self.errorMessage:setText(errorText)
	self.errorMessage:setVisible(not isValid)
end

function CpCourseGeneratorFrame:onFieldBoundaryDetectionFinished(isValid, errorText)
	self:updateWarnings()
	self:updateContextActions()
	self.errorMessage:setText(errorText)
	self.errorMessage:setVisible(not isValid)
end

function CpCourseGeneratorFrame:updateWarnings()
	for _, element in ipairs(self.currentJobElements) do 
		local parameter = element.aiParameter
		local invalidElement = element:getDescendantByName("invalid")
		if invalidElement ~= nil then
			invalidElement:setVisible(not parameter:getIsValid() and parameter:getCanBeChanged())
		end
	end
end

function CpCourseGeneratorFrame:updateParameterValueTexts()
	g_currentMission:removeMapHotspot(self.driveToAiTargetMapHotspot)
	g_currentMission:removeMapHotspot(self.fieldSiloAiTargetMapHotspot)
	g_currentMission:removeMapHotspot(self.unloadAiTargetMapHotspot)
	g_currentMission:removeMapHotspot(self.loadAiTargetMapHotspot)
	for _, element in ipairs(self.currentJobElements) do 
		local parameter = element.aiParameter
		local invalidElement = element:getDescendantByName("invalid")
		if invalidElement ~= nil then
			invalidElement:setVisible(not parameter:getIsValid() and parameter:getCanBeChanged())
		end
		element:setDisabled(not parameter:getCanBeChanged())
		local parameterType = parameter:getType()
		if parameterType == AIParameterType.TEXT then
			local title = element:getDescendantByName("title")

			title:setText(parameter:getString())
		elseif parameter.is_a and parameter:is_a(CpAIParameterPosition) then 
			element:setText(parameter:getString())
			if parameter:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.DRIVE_TO then 
				if parameter:applyToMapHotspot(self.driveToAiTargetMapHotspot) then
					g_currentMission:addMapHotspot(self.driveToAiTargetMapHotspot)
				end
			elseif parameter:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.FIELD_OR_SILO then 
				if parameter:applyToMapHotspot(self.fieldSiloAiTargetMapHotspot) then
					g_currentMission:addMapHotspot(self.fieldSiloAiTargetMapHotspot)
				end
			elseif parameter:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.UNLOAD then 
				if parameter:applyToMapHotspot(self.unloadAiTargetMapHotspot) then
					g_currentMission:addMapHotspot(self.unloadAiTargetMapHotspot)
				end
			elseif parameter:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.LOAD then 
				if parameter:applyToMapHotspot(self.loadAiTargetMapHotspot) then
					g_currentMission:addMapHotspot(self.loadAiTargetMapHotspot)
				end
			end
		elseif element.updateTitle then
			element:updateTitle()
		end
	end
end

function CpCourseGeneratorFrame:showActionMessage(localKey)
	if localKey ~= nil then
		self.actionMessage:setVisible(true)
		self.actionMessage:setLocaKey(localKey)
		return
	end
	self.actionMessage:setVisible(false)
end

function CpCourseGeneratorFrame:getCanCancelJob()
	return self.mode == self.AI_MODE_OVERVIEW and self.canCancel and 
		not self:getIsPicking() and g_currentMission:getHasPlayerPermission("hireAssistant")
end

function CpCourseGeneratorFrame:getCanStartJob()
	return self.mode == self.AI_MODE_CREATE and not self:getIsPicking() and 
		g_currentMission:getHasPlayerPermission("hireAssistant") 
end

function CpCourseGeneratorFrame:getCanGenerateFieldWorkCourse()
	return self.mode == self.AI_MODE_CREATE and self.currentJob and 
		self.currentJob:getCanGenerateFieldWorkCourse()
end

function CpCourseGeneratorFrame:onStartCancelJob()
	if self:getCanCancelJob() then
		self:cancelJob()
	elseif self:getCanStartJob() then
		self:startJob()
	end
end

function CpCourseGeneratorFrame:generateFieldworkCourse()
	if self.generateCoursePending then
		return false
	end
	if not self:getCanGenerateFieldWorkCourse() then 
		return false
	end
	self.generateCoursePending = true
	self.currentJob:onClickGenerateFieldWorkCourse(function(course)
		self.generateCoursePending = false
		if not course then
			InfoDialog.show(g_i18n:getText('CP_error_could_not_generate_course'),
				nil, nil, DialogElement.TYPE_ERROR)
			return
		end
		self:validateParameters()
		self:updateParameterValueTexts()
	end)
	return true
end

function CpCourseGeneratorFrame:startJob()
	if self.startJobPending then
		return
	end
	self.currentJob:setValues()
	local success, errorMessage = self.currentJob:validate(g_localPlayer.farmId)
	if success then
		local function callback(state)
			if state == AIJob.START_SUCCESS then
				self.mode = self.AI_MODE_OVERVIEW
				self:setJobMenuVisible(false)
				self:setMapSelectionItem(self.currentHotspot)
			end
		end
		self:tryStartJob(self.currentJob, 
		g_localPlayer.farmId, callback)
	else
		InfoDialog.show(tostring(errorMessage), nil, nil, DialogElement.TYPE_WARNING)
		self:updateWarnings()
	end
end

function CpCourseGeneratorFrame:onStartedJob(args, state, jobTypeIndex)
	local callback = args[1]
	self.startJobPending = false
	g_messageCenter:unsubscribe(AIJobStartRequestEvent, self)
	if state == AIJob.START_SUCCESS then
		self.mapOverviewSelector:setState(self.MAP_SELECTOR_ACTIVE_JOBS, true)
	else
		local jobType = g_currentMission.aiJobTypeManager:getJobTypeByIndex(jobTypeIndex)
		local text = jobType.classObject.getIsStartErrorText(state)
		InfoDialog.show(text, nil, nil, DialogElement.TYPE_INFO)
	end
	callback(state)
end

function CpCourseGeneratorFrame:tryStartJob(job, farmId, callback)
	self.startJobPending = true

	g_messageCenter:subscribe(AIJobStartRequestEvent, 
		self.onStartedJob, self, {callback})
	g_client:getServerConnection():sendEvent(
		AIJobStartRequestEvent.new(job, farmId))
end

function CpCourseGeneratorFrame:cancelJob()
	local vehicle = self.cpMenu:getCurrentVehicle()
	if vehicle and vehicle:getIsAIActive() then
		vehicle:stopCurrentAIJob(AIMessageSuccessStoppedByUser.new())
		g_currentMission:removeMapHotspot(self.driveToAiTargetMapHotspot)
		g_currentMission:removeMapHotspot(self.fieldSiloAiTargetMapHotspot)
		g_currentMission:removeMapHotspot(self.unloadAiTargetMapHotspot)
		g_currentMission:removeMapHotspot(self.loadAiTargetMapHotspot)
	end
end

function CpCourseGeneratorFrame:getNumberOfSections(list)
	if list == self.filterList then
		return 2
	end
	return 1	
end

function CpCourseGeneratorFrame:getTitleForSectionHeader(list, section)
	if list == self.filterList then 
		if section == 1 then 
			return g_i18n:getText("ui_mapHotspotFilter_vehicles")
		end 
		return g_i18n:getText("construction_category_buildings")
	end
end

function CpCourseGeneratorFrame:getNumberOfItemsInSection(list, section) 
	if list == self.filterList then 
		return #self.hotspotFilterCategories[section]
	end
	if list == self.contextButtonList then 
		self.contextActionMapping = {}
		for index, action in pairs(self.contextActions) do 
			if action.isActive then 
				table.insert(self.contextActionMapping, index)
			end
		end
		if self.mode == self.AI_MODE_CREATE then  
			return 0
		end
		return #self.contextActionMapping
	end
	if list == self.contextButtonCustomFieldList then 
		self.contextActionMapping = {}
		for index, action in pairs(self.contextActions) do 
			if action.isActive then 
				table.insert(self.contextActionMapping, index)
			end
		end
		return #self.contextActionMapping
	end
	if list == self.activeWorkerList then 
		local farmId = 1
		if g_localPlayer then 
			farmId = g_localPlayer.farmId
		end
		local count = 0
		for _, job in ipairs(g_currentMission.aiSystem:getActiveJobs()) do 
			if job.startedFarmId == farmId then 
				count = count + 1
			end
		end
		self.activeWorkerListEmpty:setVisible(count == 0)
		return count
	elseif list == self.createJobButtonList then
		if self.mode ~= self.AI_MODE_CREATE then 
			return 0
		end
		for _, index in pairs(self.contextActionMapping) do 
			local action = self.contextActions[index]
			if action.isActive and action.action then 
				g_inputBinding:registerActionEvent(action.action, self, action.callback, false, true, false, true)
			end
		end
		return #self.contextActionMapping
	elseif list == self.infoTextList then 
		self.activeInfoTexts = g_infoTextManager:getActiveInfoTexts()
		return #self.activeInfoTexts
	end
	return 0
end

function CpCourseGeneratorFrame:populateCellForItemInSection(list, section, index, cell)
	if list == self.filterList then 
		local status = self.hotspotFilterCategories[section][index]
		cell:getAttribute("name"):setText(g_i18n:getText(status.name))
		cell:getAttribute("icon"):setImageSlice(nil, status.sliceId)
		cell:getAttribute("icon").getIsSelected = function ()
			return true
		end
		cell:getAttribute("iconBg").getIsSelected = function ()
			return self.hotspotStateFilter[section][index]
		end
		g_inGameMenu.pageMapOverview.assignItemColors(self, 
			cell:getAttribute("iconBg"), status.color, 
			cell:getAttribute("colorTemplate")) 
	elseif list == self.contextButtonList then 
		local buttonInfo = self.contextActions[self.contextActionMapping[index]]
		cell:getAttribute("text"):setText(buttonInfo.text)
		cell.onClickCallback = buttonInfo.callback
	elseif list == self.contextButtonCustomFieldList then
		local buttonInfo = self.contextActions[self.contextActionMapping[index]]
		cell:getAttribute("text"):setText(buttonInfo.text)
		cell.onClickCallback = buttonInfo.callback
	elseif list == self.activeWorkerList then 
		local count = 0
		local currentJob = nil
		local farmId = 1
		if g_localPlayer then
			farmId = g_localPlayer.farmId
		end
		for _, job in ipairs(g_currentMission.aiSystem:getActiveJobs()) do 
			if job.startedFarmId == farmId then
				count = count + 1	
				currentJob = job
				break
			end
		end
		if currentJob then 
			cell:getAttribute("text"):setText(currentJob:getDescription())
			cell:getAttribute("title"):setText(currentJob:getTitle())
			cell:getAttribute("helper"):setText(currentJob:getHelperName())
		end
	elseif list == self.createJobButtonList then
		local buttonInfo = self.contextActions[self.contextActionMapping[index]]
		cell:getAttribute("text"):setText(buttonInfo.text)
		cell:getAttribute("button"):setInputAction(buttonInfo.action)
		cell.onClickCallback = buttonInfo.callback
	elseif list == self.infoTextList then 
		cell:getAttribute("text"):setText(self.activeInfoTexts[index].text)
		cell:getAttribute("icon").getIsSelected = function ()
			return self.cpMenu:getCurrentVehicle() == self.activeInfoTexts[index].vehicle
		end
		cell.onClickCallback = function ()
			if self:getIsPicking() then 
				return
			end
			if self.mode == self.AI_MODE_CREATE then 
				self.mode = self.AI_MODE_OVERVIEW
				self:setJobMenuVisible(false)
			end
			self:setAIVehicle(self.activeInfoTexts[index].vehicle)
		end
	end
end

function CpCourseGeneratorFrame:onClickList(list, section, index, listElement)
	if list == self.filterList then 
		self.ingameMapBase:toggleDefaultFilter(self.hotspotFilterCategories[section][index].id)
		self.hotspotStateFilter[section][index] = not self.hotspotStateFilter[section][index]
		self.ingameMapBase:restoreDefaultFilter()
		self:saveHotspotFilter()
	elseif list == self.activeWorkerList then
		local job = g_currentMission.aiSystem:getJobById(self.playerFarmActiveJobs[index])
		if job ~= nil and not job.vehicleParameter then
			local vehicle = job.vehicleParameter:getVehicle()
			if vehicle ~= nil then
				local hotspot = vehicle:getMapHotspot()
				self:showMapHotspot(hotspot)
			end
		end
	elseif list == self.contextButtonList then
		listElement.onClickCallback(self)	
	elseif list == self.contextButtonCustomFieldList then
		listElement.onClickCallback(self)	
	elseif list == self.createJobButtonList then
		listElement.onClickCallback(self)	
	elseif list == self.infoTextList then 
		listElement.onClickCallback(self)
	end
end

function CpCourseGeneratorFrame:onListSelectionChanged(list, section, index)
	if list == self.activeWorkerList then
		-- local job = g_currentMission.aiSystem:getJobById(self.playerFarmActiveJobs[index])
		-- if job ~= nil and job.vehicleParameter then
		-- 	local vehicle = job.vehicleParameter:getVehicle()
		-- 	if vehicle ~= nil then
		-- 		local hotspot = vehicle:getMapHotspot()
		-- 		self.mode = InGameMenuMapFrame.AI_MODE_WORKER_LIST
		-- 		self:setMapSelectionItem(hotspot)
		-- 		self.ingameMap:panToHotspot(hotspot)
		-- 	end
		-- end
	end
end

function CpCourseGeneratorFrame:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
	if self.isPickingRotation then
		local localX, localY = self.ingameMap:getLocalPosition(posX, posY)
		local worldX, worldZ = self.ingameMap:localToWorldPos(localX, localY)
		local angle = math.atan2(worldX - self.pickingRotationOrigin[1], worldZ - self.pickingRotationOrigin[2])
		angle = angle + math.pi

		if self.pickingRotationSnapAngle > 0 then
			local numSteps = MathUtil.round(angle / self.pickingRotationSnapAngle, 0)
			angle = numSteps * self.pickingRotationSnapAngle
		end

		self.aiTargetMapHotspot:setWorldRotation(angle)
	end

	self.lastMousePoxY = posY
	self.lastMousePosX = posX

	if self.isPickingLocation then
		local localX, localY = self.ingameMap:getLocalPosition(self.lastMousePosX, self.lastMousePoxY)
		local worldX, worldZ = self.ingameMap:localToWorldPos(localX, localY)
		self.aiTargetMapHotspot:setWorldPosition(worldX, worldZ)
	end
	return CpCourseGeneratorFrame:superClass().mouseEvent(self, posX, posY, isDown, isUp, button, eventUsed)
end

function CpCourseGeneratorFrame:updateInputGlyphs()
	local moveActions, moveText = nil

	if self.lastInputHelpMode == GS_INPUT_HELP_MODE_GAMEPAD then
		moveText = self.moveCursorText
		moveActions = {
			InputAction.AXIS_MAP_SCROLL_LEFT_RIGHT,
			InputAction.AXIS_MAP_SCROLL_UP_DOWN
		}
	else
		moveText = self.panMapText
		moveActions = {
			InputAction.AXIS_LOOK_LEFTRIGHT_DRAG,
			InputAction.AXIS_LOOK_UPDOWN_DRAG
		}
	end

	self.mapMoveGlyph:setActions(moveActions, nil, nil, moveActions)
	self.mapZoomGlyph:setActions({
		InputAction.AXIS_MAP_ZOOM_IN,
		InputAction.AXIS_MAP_ZOOM_OUT
	}, nil, nil, self)
	self.mapMoveGlyphText:setText(moveText)
	self.mapZoomGlyphText:setText(self.zoomText)

end

-- Lines 992-1005
function CpCourseGeneratorFrame:registerInput()
	-- self:unregisterInput()
	-- g_inputBinding:registerActionEvent(InputAction.MENU_ACTIVATE, self, self.onStartCancelJob, false, true, false, true)
	-- g_inputBinding:registerActionEvent(InputAction.MENU_CANCEL, self, self.onStartGoToJob, false, true, false, true)
	-- g_inputBinding:registerActionEvent(InputAction.MENU_ACCEPT, self, self.onCreateJob, false, true, false, true)
	-- g_inputBinding:registerActionEvent(InputAction.MENU_EXTRA_1, self, self.onSkipJobTask, false, true, false, true)

	-- local _, switchVehicleId = g_inputBinding:registerActionEvent(InputAction.SWITCH_VEHICLE, self, self.onSwitchVehicle, false, true, false, true, 1)
	-- self.eventIdSwitchVehicle = switchVehicleId
	-- local _, switchVehicleBackId = g_inputBinding:registerActionEvent(InputAction.SWITCH_VEHICLE_BACK, self, self.onSwitchVehicle, false, true, false, true, -1)
	-- self.eventIdSwitchVehicleBack = switchVehicleBackId
end

-- Lines 1008-1017
function CpCourseGeneratorFrame:unregisterInput(customOnly)
	local list = customOnly and self.CLEAR_CLOSE_INPUT_ACTIONS or self.CLEAR_INPUT_ACTIONS

	for _, actionName in pairs(list) do
		g_inputBinding:removeActionEventsByActionName(actionName)
	end
end

function CpCourseGeneratorFrame:generateJobTypes()
	for name, jobType in pairs(AIJobType) do
		if string.match(name, "CP$") then
			self.jobTypeInstances[jobType] = g_currentMission.aiJobTypeManager:createJob(jobType)
		end
	end
end

function CpCourseGeneratorFrame:addStatusMessage(message)
	table.insert(self.statusMessages, {
		removeTime = g_time + 5000,
		text = message
	})
	self:updateStatusMessages()
end

function CpCourseGeneratorFrame:updateStatusMessages()
	local text = ""
	for _, message in ipairs(self.statusMessages) do
		text = text .. message.text .. "\n"
	end
	self.statusMessage:setText(text)
end

function CpCourseGeneratorFrame:initializeContextActions()
	self.contextActions = {
		[self.CONTEXT_ACTIONS.ENTER_VEHICLE] = {
			text = g_i18n:getText("button_enterVehicle"),
			callback = function()
				local vehicle = self.cpMenu:getCurrentVehicle()
				if vehicle then 
					if vehicle.getIsEnterableFromMenu ~= nil and vehicle:getIsEnterableFromMenu() then
						self.onClickBackCallback()
						g_localPlayer:requestToEnterVehicle(vehicle)
					end
				end
			end,
			isActive = false
		},
		[self.CONTEXT_ACTIONS.CREATE_JOB] = {
			text = g_i18n:getText("button_createJob"),
			callback = self.onCreateJob,
			isActive = false
		},
		[self.CONTEXT_ACTIONS.START_JOB] = {
			text = g_i18n:getText("button_startJob"),
			action = InputAction.MENU_EXTRA_1,
			callback = self.onStartCancelJob,
			isActive = false
		},
		[self.CONTEXT_ACTIONS.STOP_JOB] = {
			text = g_i18n:getText("button_cancelJob"),
			callback = self.onStartCancelJob,
			isActive = false
		},
		[self.CONTEXT_ACTIONS.GENERATE_COURSE] = {
			text = g_i18n:getText("CP_ai_page_generate_course"),
			action = InputAction.MENU_EXTRA_2,
			callback = function()
				if self:generateFieldworkCourse() then
					if self.subCategoryPaging:getState() ~= self.CATEGRORIES.IN_GAME_MAP then
						self:updateSubCategoryPages(self.CATEGRORIES.IN_GAME_MAP)
					end
				end
			end,
			isActive = false
		},
		[self.CONTEXT_ACTIONS.DELETE_CUSTOM_FIELD] = {
			text = g_i18n:getText("CP_customFieldManager_delete"),
			callback = function()
				if self.currentHotspot and self.currentHotspot:isa(CustomFieldHotspot) then 
					self.currentHotspot:onClickDelete()
				end
			end,
			isActive = false
		},
		[self.CONTEXT_ACTIONS.RENAME_CUSTOM_FIELD] = {
			text = g_i18n:getText("CP_customFieldManager_rename"),
			callback = function()
				if self.currentHotspot and self.currentHotspot:isa(CustomFieldHotspot) then 
					self.currentHotspot:onClickRename()
				end
			end,
			isActive = false
		},
		[self.CONTEXT_ACTIONS.EDIT_CUSTOM_FIELD] = {
			text = g_i18n:getText("CP_customFieldManager_edit"),
			callback = function()
				if self.currentHotspot and self.currentHotspot:isa(CustomFieldHotspot) then 
					self.currentHotspot:onClickEdit()
				end
			end,
			isActive = false
		}
	}
end

function CpCourseGeneratorFrame:updateContextActions()
	local vehicle = self.cpMenu:getCurrentVehicle()
	self.contextActions[self.CONTEXT_ACTIONS.ENTER_VEHICLE].isActive = vehicle and vehicle:getIsEnterableFromMenu() and self.mode ~= self.AI_MODE_CREATE
	self.canCreateJob = false
	if vehicle and not self.currentJobVehicle then
		for _, job in pairs(self.jobTypeInstances) do 
			if job:getIsAvailableForVehicle(vehicle, true) then 
				self.canCreateJob = true
			end
		end
	end
	self.canCancel = vehicle and vehicle.spec_aiJobVehicle and vehicle:getIsAIActive()
	self.contextActions[self.CONTEXT_ACTIONS.CREATE_JOB].isActive = self.canCreateJob and self.mode ~= self.AI_MODE_CREATE
	self.contextActions[self.CONTEXT_ACTIONS.START_JOB].isActive = self:getCanStartJob()
	self.contextActions[self.CONTEXT_ACTIONS.STOP_JOB].isActive = self:getCanCancelJob() and self.mode ~= self.AI_MODE_CREATE
	self.contextActions[self.CONTEXT_ACTIONS.GENERATE_COURSE].isActive = self:getCanGenerateFieldWorkCourse()
	self.contextActions[self.CONTEXT_ACTIONS.DELETE_CUSTOM_FIELD].isActive = self.currentHotspot and self.currentHotspot:isa(CustomFieldHotspot)
	self.contextActions[self.CONTEXT_ACTIONS.RENAME_CUSTOM_FIELD].isActive = self.currentHotspot and self.currentHotspot:isa(CustomFieldHotspot)
	self.contextActions[self.CONTEXT_ACTIONS.EDIT_CUSTOM_FIELD].isActive = self.currentHotspot and self.currentHotspot:isa(CustomFieldHotspot)
	for _, action in ipairs(self.contextActions) do 
		if action.action then 
			g_inputBinding:removeActionEventsByActionName(action.action)
		end
	end
	self.contextButtonList:reloadData()	
	self.contextButtonCustomFieldList:reloadData()
	self.createJobButtonList:reloadData()
end

function CpCourseGeneratorFrame:toggleMapInput(isActive)
	-- if self.isInputContextActive ~= isActive then
	-- 	self.isInputContextActive = isActive

	-- 	-- self:toggleCustomInputContext(isActive, self.INPUT_CONTEXT_NAME)

	-- 	if isActive then
	-- 		self:registerInput()
	-- 	else
	-- 		self:unregisterInput(true)
	-- 	end
	-- end
end

function CpCourseGeneratorFrame:setMapSelectionItem(hotspot)
	if self.mode == self.AI_MODE_CREATE then 
		return
	end
	if hotspot ~= nil then
		local x, _ = hotspot:getWorldPosition()
		if x == nil then
			hotspot = nil
		end
	end
	self.ingameMapBase:setSelectedHotspot(hotspot)
	self.selectedFarmland = nil

	g_currentMission:removeMapHotspot(self.driveToAiTargetMapHotspot)
	g_currentMission:removeMapHotspot(self.fieldSiloAiTargetMapHotspot)
	g_currentMission:removeMapHotspot(self.unloadAiTargetMapHotspot)
	g_currentMission:removeMapHotspot(self.loadAiTargetMapHotspot)

	local playerName = nil
	local farmId = 1
	local name = nil
	local imageFilename = nil
	local uvs = Overlay.DEFAULT_UVS

	local showContextBox = false
	self.currentHotspot = nil
	if hotspot ~= nil and hotspot.isa ~= nil then 
		local vehicle = InGameMenuMapUtil.getHotspotVehicle(hotspot)
		if vehicle ~= nil and not vehicle.spec_rideable then
			playerName = nil
			farmId = vehicle:getOwnerFarmId()
			name = vehicle:getName()
			imageFilename = vehicle:getImageFilename()
			uvs = Overlay.DEFAULT_UVS
			self.currentHotspot = hotspot
			self.currentContextBox = self.contextBox
			if hotspot:isa(PlayerHotspot) then
				local player = hotspot:getPlayer()
				if player then 
					playerName = player:getNickname()
					farmId = player:getFarmId()
				end
			end
			if vehicle.getJob ~= nil then
				local job = vehicle:getJob()					
				if job ~= nil and job.getCpJobParameters then
					--- Shows the target marker of the current job on the map.
					for _, parameter in pairs(job:getCpJobParameters():getAiTargetMapHotspotParameters()) do
						if parameter:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.DRIVE_TO then 
							if parameter:applyToMapHotspot(self.driveToAiTargetMapHotspot) then
								g_currentMission:addMapHotspot(self.driveToAiTargetMapHotspot)
							end
						elseif parameter:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.FIELD_OR_SILO then 
							if parameter:applyToMapHotspot(self.fieldSiloAiTargetMapHotspot) then
								g_currentMission:addMapHotspot(self.fieldSiloAiTargetMapHotspot)
							end
						elseif parameter:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.UNLOAD then 
							if parameter:applyToMapHotspot(self.unloadAiTargetMapHotspot) then
								g_currentMission:addMapHotspot(self.unloadAiTargetMapHotspot)
							end
						elseif parameter:getPositionType() == CpAIParameterPositionAngle.POSITION_TYPES.LOAD then 
							if parameter:applyToMapHotspot(self.loadAiTargetMapHotspot) then
								g_currentMission:addMapHotspot(self.loadAiTargetMapHotspot)
							end
						end
					end
				end
			end
			showContextBox = true
		elseif hotspot:isa(CustomFieldHotspot) then 
			farmId = g_localPlayer:getFarmId()
			name = hotspot:getName()
			uvs = Overlay.DEFAULT_UVS
			self.currentHotspot = hotspot
			self.contextBoxCustomField:getDescendantByName("farmlandSize"):setText(hotspot:getAreaText())
			self.currentContextBox = self.contextBoxCustomField
			showContextBox = true
		end
	end
	self.cpMenu:lockCurrentVehicle(self.currentHotspot and self.currentHotspot.getVehicle and self.currentHotspot:getVehicle())
	if showContextBox then
		InGameMenuMapUtil.hideContextBox(self.contextBox)
		InGameMenuMapUtil.hideContextBox(self.contextBoxCustomField)
		InGameMenuMapUtil.showContextBox(self.currentContextBox, hotspot, name, imageFilename, uvs, farmId, playerName, false, true, false)
		self:updateContextActions()
	else
		InGameMenuMapUtil.hideContextBox(self.currentContextBox)
	end
end

function CpCourseGeneratorFrame:setAIVehicle(vehicle)
	local hotspot = vehicle:getMapHotspot()
	self:setMapSelectionItem(hotspot)
	self.ingameMap:panToHotspot(hotspot)
	if not vehicle:getIsAIActive() then 
		self:onCreateJob()
	end
end

function CpCourseGeneratorFrame:onCreateJob()
	local vehicle = self.cpMenu:getCurrentVehicle()
	if vehicle then 
		self.currentJobTypes = {}
		local currentJobTypesTexts = {}
		for index, job in pairs(self.jobTypeInstances) do 
			if job:getIsAvailableForVehicle(vehicle, true) then 
				table.insert(self.currentJobTypes, index)
				table.insert(currentJobTypesTexts, g_currentMission.aiJobTypeManager:getJobTypeByIndex(index).title)
			end
		end
		if #self.currentJobTypes > 0 then 
			self.jobTypeElement:setTexts(currentJobTypesTexts)
			self.jobTypeElement:setState(1)
			self.mode = self.AI_MODE_CREATE
			self.currentJobVehicle = vehicle
			self.currentJob = nil
			self:setJobMenuVisible(true)
			FocusManager:setFocus(self.jobTypeElement)
			self:setActiveJobTypeSelection(self.currentJobTypes[1])
		end
	end
	self:updateContextActions()
end

function CpCourseGeneratorFrame:resetUIDeadzones(enable)
	self.ingameMap:clearCursorDeadzones()
	if enable then 
		self.ingameMap:addCursorDeadzone(self.rightBackground.absPosition[1], self.rightBackground.absPosition[2], self.rightBackground.size[1], self.rightBackground.size[2])
		self.ingameMap:addCursorDeadzone(self.topBackground.absPosition[1], self.topBackground.absPosition[2], self.topBackground.size[1], self.topBackground.size[2])
		self.ingameMap:addCursorDeadzone(self.bottomBackground.absPosition[1], self.bottomBackground.absPosition[2], self.bottomBackground.size[1], self.bottomBackground.size[2])
		self.ingameMap:addCursorDeadzone(0, 0, self.leftBox.absPosition[1] + self.leftBox.absSize[1], 1)
	else
	end
end

function CpCourseGeneratorFrame:setJobMenuVisible(isVisible)
	-- g_inputBinding:setActionEventActive(self.eventIdSwitchVehicle, not isVisible)
	-- g_inputBinding:setActionEventActive(self.eventIdSwitchVehicleBack, not isVisible)
	-- g_inputBinding:setContextEventsActive(InGameMenuAIFrame.INPUT_CONTEXT_NAME, InputAction.MENU_AXIS_LEFT_RIGHT, isVisible)
	self.errorMessage:setText("")
	self.actionMessage:setText("")
	self.createJobEmptyText:setVisible(not isVisible)
	self.jobTypeElement:setVisible(isVisible)
	self.jobMenuLayout:setVisible(isVisible)
	if not isVisible then
		self.currentJob = nil
		self.currentJobVehicle = nil
		self:updateCourseGenerator(false)
		FocusManager:setFocus(self.mapOverviewSelector)
		self.mapOverviewSelector:setState(self.MAP_SELECTOR_ACTIVE_JOBS, true)
	else
		self.mapOverviewSelector:setState(self.MAP_SELECTOR_CREATE_JOB, true)
		self.mapOverviewSelector:setDisabled(true)
	end
end

function CpCourseGeneratorFrame:setActiveJobTypeSelection(jobTypeIndex)
	if self.currentJob == nil or jobTypeIndex ~= self.currentJob.jobTypeIndex then
		for i = #self.jobMenuLayout.elements, 1, -1 do
			self.jobMenuLayout.elements[i]:delete()
		end
		self.currentJob = g_currentMission.aiJobTypeManager:createJob(jobTypeIndex)
		local farmId = 1
		if g_localPlayer then
			farmId = g_localPlayer.farmId
		end
		self.currentJob:applyCurrentState(self.currentJobVehicle, g_currentMission, farmId, false)
		self.currentJobElements = {}
		for _, group in ipairs(self.currentJob:getGroupedParameters()) do
			local titleElement = self.createTitleTemplate:clone(self.jobMenuLayout)

			titleElement:setText(group:getTitle())

			for _, item in ipairs(group:getParameters()) do
				local element = nil
				local parameterType = item:getType()

				if parameterType == AIParameterType.TEXT then
					element = self.createTextTemplate:clone(self.jobMenuLayout)
				elseif parameterType == AIParameterType.POSITION then
					element = self.createPositionTemplate:clone(self.jobMenuLayout)
				elseif parameterType == AIParameterType.POSITION_ANGLE then
					element = self.createPositionRotationTemplate:clone(self.jobMenuLayout)
				elseif parameterType == AIParameterType.SELECTOR or 
					parameterType == AIParameterType.LOADING_STATION or 
					parameterType == AIParameterType.FILLTYPE then
					
					element = self.createMultiOptionTemplate:clone(self.jobMenuLayout)

					element:setDataSource(item)
				end
				if element then 
					FocusManager:loadElementFromCustomValues(element)

					element.aiParameter = item
					if element.updateTitle then 
						element:updateTitle()
					end
					element:setDisabled(not item:getCanBeChanged())
					table.insert(self.currentJobElements, element)
				end
			end
		end
		self:validateParameters()
		self:updateParameterValueTexts()
		self.jobMenuLayout:invalidateLayout()
		FocusManager:setFocus(self.jobTypeElement)
		self:updateCourseGenerator(self.currentJob.is_a and self.currentJob:is_a(CpAIJobFieldWork), self.currentJobVehicle)
	end
	self:updateContextActions()
end

function CpCourseGeneratorFrame:openMap()
	self:toggleMapInput(true)
	self.ingameMap:setDisabled(false)
	self.ingameMap:registerActionEvents()
	self.ingameMapBase:restoreDefaultFilter()
	self:updateContextActions()
	self:resetUIDeadzones(true)
	if self.mode == self.AI_MODE_OVERVIEW and self.currentHotspot then 
		FocusManager:setFocus(self.currentContextBox)
	else
		FocusManager:setFocus(self.mapOverviewSelector)
	end
	-- if g_localPlayer ~= nil then
	-- 	local x, _, z = g_localPlayer:getPosition()
	-- 	self.ingameMap:setCenterToWorldPosition(x, z)
	-- end
end

function CpCourseGeneratorFrame:closeMap()
	self.ingameMap:removeActionEvents()
	self.ingameMap:setDisabled(true)
	self:toggleMapInput(false)
	if self:getIsPicking() then
		self:executePickingCallback(false)
	end
	self:resetUIDeadzones(false)
	-- g_inputBinding:setContextEventsActive(self.INPUT_CONTEXT_NAME, InputAction.MENU_AXIS_LEFT_RIGHT, true)
end