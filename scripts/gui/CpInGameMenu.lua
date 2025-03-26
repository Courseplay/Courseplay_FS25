CpInGameMenu = {
	BASE_XML_KEY = "InGameMenu"
}
local CpInGameMenu_mt = Class(CpInGameMenu, TabbedMenu)
function CpInGameMenu.new(target, customMt, messageCenter, l10n, inputManager, courseStorage)
	local self = CpInGameMenu:superClass().new(target, customMt or CpInGameMenu_mt, messageCenter, l10n, inputManager)

	self.messageCenter = messageCenter
	self.l10n = l10n
	self.inputManager = inputManager
	self.courseStorage = courseStorage

	self.defaultMenuButtonInfo = {}
	self.backButtonInfo = {}
	self.currentVehicle = nil

	self.messageCenter:subscribe(MessageType.GUI_CP_INGAME_OPEN, function (menu)
		g_gui:showGui("CpInGameMenu")
		self:changeScreen(CpInGameMenu)
		self:updatePages()
		-- local index = self.pagingElement:getPageMappingIndexByElement(self.page)
		-- self.pageSelector:setState(pageAIIndex, true)
	end, self)
	self.messageCenter:subscribe(MessageType.GUI_CP_INGAME_OPEN_GLOBAL_SETTINGS, function (menu)
		g_gui:showGui("CpInGameMenu")
		self:changeScreen(CpInGameMenu)
		self:updatePages()
		local index = self.pagingElement:getPageMappingIndexByElement(self.pageGlobalSettings)
		self.pageSelector:setState(index, true)
	end, self)
	self.messageCenter:subscribe(MessageType.GUI_CP_INGAME_OPEN_VEHICLE_SETTINGS, function (menu)
		g_gui:showGui("CpInGameMenu")
		self:changeScreen(CpInGameMenu)
		self:updatePages()
		local index = self.pagingElement:getPageMappingIndexByElement(self.pageVehicleSettings)
		self.pageSelector:setState(index, true)
	end, self)
	self.messageCenter:subscribe(MessageType.GUI_CP_INGAME_OPEN_COURSE_GENERATOR, function (menu)
		g_gui:showGui("CpInGameMenu")
		self:changeScreen(CpInGameMenu)
		self:updatePages()
		local index = self.pagingElement:getPageMappingIndexByElement(self.pageCourseGenerator)
		self.pageSelector:setState(index, true)
	end, self)
	self.messageCenter:subscribe(MessageType.GUI_CP_INGAME_OPEN_COURSE_MANAGER, function (menu)
		g_gui:showGui("CpInGameMenu")
		self:changeScreen(CpInGameMenu)
		self:updatePages()
		local index = self.pagingElement:getPageMappingIndexByElement(self.pageCourseManager)
		self.pageSelector:setState(index, true)
	end, self)
	self.messageCenter:subscribe(MessageType.GUI_CP_INGAME_OPEN_HELP_MENU, function (menu)
		g_gui:showGui("CpInGameMenu")
		self:changeScreen(CpInGameMenu)
		self:updatePages()
		local index = self.pagingElement:getPageMappingIndexByElement(self.pageHelpLine)
		self.pageSelector:setState(index, true)
	end, self)
	self.messageCenter:subscribe(MessageType.GUI_CP_INGAME_OPEN_CONSTRUCTION_MENU, function (menu, ...)
		self.pageConstruction:setData(...)
		g_gui:showGui("CpInGameMenu")
		self:changeScreen(CpInGameMenu)
		self:updatePages()
		local index = self.pagingElement:getPageMappingIndexByElement(self.pageConstruction)
		self.pageSelector:setState(index, true)
	end, self)

	self.messageCenter:subscribe(MessageType.GUI_CP_INGAME_CURRENT_VEHICLE_CHANGED, 
		self.onCurrentVehicleChanged, self)
	return self
end

-- Lines 135-193
function CpInGameMenu.createFromExistingGui(gui, guiName)
	CpGlobalSettingsFrame.createFromExistingGui(g_gui.frames.cpInGameMenuGlobalSettings.target, "CpGlobalSettingsFrame")
	CpVehicleSettingsFrame.createFromExistingGui(g_gui.frames.cpInGameMenuVehicleSettings.target, "CpVehicleSettingsFrame")
	CpCourseGeneratorFrame.createFromExistingGui(g_gui.frames.cpInGameMenuCourseGenerator.target, "CpCourseGeneratorFrame")
	CpCourseManagerFrame.createFromExistingGui(g_gui.frames.cpInGameMenuCourseManager.target, "CpCourseManagerFrame")
	CpHelpFrame.createFromExistingGui(g_gui.frames.cpInGameMenuHelpLine.target, "CpHelpFrame")
	CpConstructionFrame.createFromExistingGui(g_gui.frames.cpInGameMenuConstruction.target, "CpConstructionFrame")

	local messageCenter = gui.messageCenter
	local l10n = gui.l10n
	local inputManager = gui.inputManager
	local newGui = CpInGameMenu.new(nil, nil, messageCenter, l10n, inputManager, g_Courseplay.courseStorage)

	g_gui.guis.CpInGameMenu:delete()
	g_gui.guis.CpInGameMenu.target:delete()
	g_gui:loadGui(gui.xmlFilename, guiName, newGui)

	g_cpInGameMenu = newGui
	
	return newGui
end

function CpInGameMenu.setupGui(courseStorage)

	MessageType.GUI_CP_INGAME_OPEN = nextMessageTypeId()
	MessageType.GUI_CP_INGAME_OPEN_GLOBAL_SETTINGS = nextMessageTypeId()
	MessageType.GUI_CP_INGAME_OPEN_VEHICLE_SETTINGS = nextMessageTypeId()
	MessageType.GUI_CP_INGAME_OPEN_COURSE_GENERATOR = nextMessageTypeId()
	MessageType.GUI_CP_INGAME_OPEN_COURSE_MANAGER = nextMessageTypeId()
	MessageType.GUI_CP_INGAME_OPEN_HELP_MENU = nextMessageTypeId()
	MessageType.GUI_CP_INGAME_CURRENT_VEHICLE_CHANGED = nextMessageTypeId()
	MessageType.GUI_CP_INGAME_OPEN_CONSTRUCTION_MENU = nextMessageTypeId()

	CpCourseGeneratorFrame.setupGui()
	CpGlobalSettingsFrame.setupGui()
	CpVehicleSettingsFrame.setupGui()
	CpCourseManagerFrame.setupGui()
	CpHelpFrame.setupGui()
	CpConstructionFrame.setupGui()

	g_cpInGameMenu = CpInGameMenu.new(nil, nil, g_messageCenter, g_i18n, g_inputBinding, courseStorage)
	g_gui:loadGui(Utils.getFilename("config/gui/CpInGameMenu.xml", Courseplay.BASE_DIRECTORY),
				"CpInGameMenu", g_cpInGameMenu)
end

function CpInGameMenu.registerXmlSchema(xmlSchema, xmlKey)
	xmlKey = xmlKey .. CpInGameMenu.BASE_XML_KEY .. "."
	CpCourseGeneratorFrame.registerXmlSchema(xmlSchema, xmlKey)
	CpGlobalSettingsFrame.registerXmlSchema(xmlSchema, xmlKey)
	CpVehicleSettingsFrame.registerXmlSchema(xmlSchema, xmlKey)
	CpCourseManagerFrame.registerXmlSchema(xmlSchema, xmlKey)
	CpHelpFrame.registerXmlSchema(xmlSchema, xmlKey)
end

function CpInGameMenu:loadFromXMLFile(xmlFile, baseKey)
	baseKey = baseKey .. CpInGameMenu.BASE_XML_KEY .. "."
	self.pageCourseGenerator:loadFromXMLFile(xmlFile, baseKey)
	self.pageGlobalSettings:loadFromXMLFile(xmlFile, baseKey)
	self.pageVehicleSettings:loadFromXMLFile(xmlFile, baseKey)
	self.pageCourseManager:loadFromXMLFile(xmlFile, baseKey)
	self.pageHelpLine:loadFromXMLFile(xmlFile, baseKey)
	self.pageConstruction:loadFromXMLFile(xmlFile, baseKey)
end

function CpInGameMenu:saveToXMLFile(xmlFile, baseKey)
	baseKey = baseKey .. CpInGameMenu.BASE_XML_KEY .. "."
	self.pageCourseGenerator:saveToXMLFile(xmlFile, baseKey)
	self.pageGlobalSettings:saveToXMLFile(xmlFile, baseKey)
	self.pageVehicleSettings:saveToXMLFile(xmlFile, baseKey)
	self.pageCourseManager:saveToXMLFile(xmlFile, baseKey)
	self.pageHelpLine:saveToXMLFile(xmlFile, baseKey)
	self.pageConstruction:saveToXMLFile(xmlFile, baseKey)
end

function CpInGameMenu:initializePages()
	self.clickBackCallback = function ()
		if self.currentPage.onClickBack then 
			--- Force closes the page 
			self.currentPage:onClickBack(true)
		end
		self:exitMenu()
	end
	self.pageCourseGenerator:setInGameMap(
		g_inGameMenu.baseIngameMap, 
		g_currentMission.hud)
	self.pageCourseManager:setCourseStorage(self.courseStorage)

	self.pageHelpLine:initialize(self)
	self.pageGlobalSettings:initialize(self)
	self.pageVehicleSettings:initialize(self)
	self.pageCourseGenerator:initialize(self)
	self.pageCourseManager:initialize(self)
	self.pageConstruction:initialize(self)
end

function CpInGameMenu:setupMenuPages()
	local orderedDefaultPages = {
		{
			self.pageGlobalSettings,
			function ()
				return true
			end,
			"cpUi.cogwheel"
		},
		{
			self.pageVehicleSettings,
			function ()
				return self.currentVehicle ~= nil
			end,
			"cpUi.vehicleCogwheel"
		},
		{
			self.pageCourseGenerator,
			function ()
				return true
			end,
			"cpUi.navigation"
		},
		{
			self.pageCourseManager,
			function ()
				return self.currentVehicle ~= nil
			end,
			"cpUi.navigationPath"
		},
		{
			self.pageConstruction,
			CpInGameMenu.isContructionPageAvailiable,
			"cpUi.editor"
		},
		{
			self.pageHelpLine,
			function ()
				return true
			end,
			"gui.icon_options_help2"
		}
	}
	for i, pageDef in ipairs(orderedDefaultPages) do
		local page, predicate, sliceId = unpack(pageDef)
		if page ~= nil then
			self:registerPage(page, i, predicate)
			self:addPageTab(page, nil, nil, sliceId)
		end
	end
end

function CpInGameMenu:isContructionPageAvailiable()
	return g_courseEditor:getIsActive() or g_graphEditor:getIsActive()
end

function CpInGameMenu:setupMenuButtonInfo()
	CpInGameMenu:superClass().setupMenuButtonInfo(self)
	local onButtonBackFunction = self.clickBackCallback
	local onButtonPagePreviousFunction = self:makeSelfCallback(self.onPagePrevious)
	local onButtonPageNextFunction = self:makeSelfCallback(self.onPageNext)
	self.backButtonInfo = { 
		inputAction = InputAction.MENU_BACK,  
		text = g_i18n:getText(InGameMenu.L10N_SYMBOL.BUTTON_BACK),
		callback = onButtonBackFunction }
	self.nextPageButtonInfo = { 
		inputAction = InputAction.MENU_PAGE_NEXT,
		text = g_i18n:getText("ui_ingameMenuNext"),
		callback = self.onPageNext }
	self.prevPageButtonInfo = { 
		inputAction = InputAction.MENU_PAGE_PREV,
		text = g_i18n:getText("ui_ingameMenuPrev"),
		callback = self.onPagePrevious }

	self.defaultMenuButtonInfo = {
		self.backButtonInfo,
		self.nextPageButtonInfo,
		self.prevPageButtonInfo
	}

	self.defaultMenuButtonInfoByActions[InputAction.MENU_BACK] = self.defaultMenuButtonInfo[1]
	self.defaultMenuButtonInfoByActions[InputAction.MENU_PAGE_NEXT] = self.defaultMenuButtonInfo[2]
	self.defaultMenuButtonInfoByActions[InputAction.MENU_PAGE_PREV] = self.defaultMenuButtonInfo[3]
	
	self.defaultButtonActionCallbacks = {
		[InputAction.MENU_BACK] = onButtonBackFunction,
		[InputAction.MENU_PAGE_NEXT] = onButtonPageNextFunction,
		[InputAction.MENU_PAGE_PREV] = onButtonPagePreviousFunction}
end

function CpInGameMenu:onGuiSetupFinished()
	CpInGameMenu:superClass().onGuiSetupFinished(self)

	self:initializePages()
	self:setupMenuPages()
end

function CpInGameMenu:reset()
	CpInGameMenu:superClass().reset(self)

end

function CpInGameMenu:onMenuOpened()

end

function CpInGameMenu:onButtonBack()
	if self.currentPage.onClickBack then 
		if not self.currentPage:onClickBack() then 
			return
		end
	end
	if self.currentPage:requestClose(self.clickBackCallback) then
		CpInGameMenu:superClass().onButtonBack(self)
	end
end

function CpInGameMenu:onPageNext()
	if self.currentPage:requestClose(function ()
			TabbedMenu:superClass().onPageNext(self)
		end) then
		TabbedMenu:superClass().onPageNext(self)
	end
end
function CpInGameMenu:onPagePrevious()
	if self.currentPage:requestClose(function ()
			TabbedMenu:superClass().onPagePrevious(self)
		end) then
		TabbedMenu:superClass().onPagePrevious(self)
	end
end

function CpInGameMenu:onClose(element)
	CpInGameMenu:superClass().onClose(self)
	self:unlockCurrentVehicle()
end

function CpInGameMenu:onOpen()
	CpInGameMenu:superClass().onOpen(self)
	self:lockCurrentVehicle(CpUtil.getCurrentVehicle())
end

function CpInGameMenu:update(dt)

	CpInGameMenu:superClass().update(self, dt)
end

function CpInGameMenu:draw()
	if self.currentPage.drawInGame then 
		self.currentPage:drawInGame()
		new2DLayer()
	end
	CpInGameMenu:superClass().draw(self)
end

function CpInGameMenu:onClickMenu()
	self:exitMenu()

	return true
end

function CpInGameMenu:onPageChange(pageIndex, pageMappingIndex, element, skipTabVisualUpdate)
	CpInGameMenu:superClass().onPageChange(self, pageIndex, pageMappingIndex, element, skipTabVisualUpdate)
	if self.currentPage.categoryHeaderIcon then
		self.currentPage.categoryHeaderIcon:setImageSlice(nil, self.pageTabs[self.currentPage].iconSliceId)
	end
	self.background:setVisible(not self.currentPage.noBackgroundNeeded)
end

function CpInGameMenu:getPageButtonInfo(page)
	local buttonInfo = CpInGameMenu:superClass().getPageButtonInfo(self, page)

	return buttonInfo
end

function CpInGameMenu:lockCurrentVehicle(vehicle)
	local lastVehicle = self.currentVehicle
	self.currentVehicle = vehicle
	if vehicle ~= lastVehicle then 
		g_messageCenter:publish(MessageType.GUI_CP_INGAME_CURRENT_VEHICLE_CHANGED, vehicle)
	end
end

function CpInGameMenu:unlockCurrentVehicle()
	self.currentVehicle = nil
end

function CpInGameMenu:getCurrentVehicle()
	return self.currentVehicle
end

function CpInGameMenu:onCurrentVehicleChanged()
	if self:getIsOpen() then
		local prevPage = self.pagingElement:getPageElementByIndex(self.currentPageId)
		self:updatePages()
		local index = self.pagingElement:getPageMappingIndexByElement(prevPage)
		self.pagingTabList:setSelectedIndex(index, true, 0)
	end
end