CpInGameMenu = {}
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
		-- local index = self.pagingElement:getPageMappingIndexByElement(self.page)
		-- self.pageSelector:setState(pageAIIndex, true)
	end, self)
	self.messageCenter:subscribe(MessageType.GUI_CP_INGAME_OPEN_GLOBAL_SETTINGS, function (menu)
		g_gui:showGui("CpInGameMenu")
		self:changeScreen(CpInGameMenu)
		local index = self.pagingElement:getPageMappingIndexByElement(self.pageGlobalSettings)
		self.pageSelector:setState(index, true)
	end, self)
	self.messageCenter:subscribe(MessageType.GUI_CP_INGAME_OPEN_VEHICLE_SETTINGS, function (menu)
		g_gui:showGui("CpInGameMenu")
		self:changeScreen(CpInGameMenu)
		local index = self.pagingElement:getPageMappingIndexByElement(self.pageVehicleSettings)
		self.pageSelector:setState(index, true)
	end, self)
	self.messageCenter:subscribe(MessageType.GUI_CP_INGAME_OPEN_COURSE_GENERATOR, function (menu)
		g_gui:showGui("CpInGameMenu")
		self:changeScreen(CpInGameMenu)
		local index = self.pagingElement:getPageMappingIndexByElement(self.pageCourseGenerator)
		self.pageSelector:setState(index, true)
	end, self)
	self.messageCenter:subscribe(MessageType.GUI_CP_INGAME_OPEN_COURSE_MANAGER, function (menu)
		g_gui:showGui("CpInGameMenu")
		self:changeScreen(CpInGameMenu)
		local index = self.pagingElement:getPageMappingIndexByElement(self.pageCourseManager)
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
	MessageType.GUI_CP_INGAME_CURRENT_VEHICLE_CHANGED = nextMessageTypeId()

	CpCourseGeneratorFrame.setupGui()
	CpGlobalSettingsFrame.setupGui()
	CpVehicleSettingsFrame.setupGui()
	CpCourseManagerFrame.setupGui()

	g_cpInGameMenu = CpInGameMenu.new(nil, nil, g_messageCenter, g_i18n, g_inputBinding, courseStorage)
	g_gui:loadGui(Utils.getFilename("config/gui/CpInGameMenu.xml", Courseplay.BASE_DIRECTORY),
				"CpInGameMenu", g_cpInGameMenu)
end

-- Lines 279-324
function CpInGameMenu:initializePages()
	self.clickBackCallback = self:makeSelfCallback(self.onButtonBack)

	self.pageCourseGenerator:setInGameMap(
		g_inGameMenu.baseIngameMap, 
		g_currentMission.hud)

	self.pageGlobalSettings:initialize(self)
	self.pageVehicleSettings:initialize(self)
	self.pageCourseGenerator:initialize(self)
	self.pageCourseManager:initialize(self)
	self.pageCourseManager:setCourseStorage(self.courseStorage)
end

-- Lines 327-362
function CpInGameMenu:setupMenuPages()

	local orderedDefaultPages = {
		{
			self.pageGlobalSettings,
			function ()
				return true
			end,
			{768, 0, 128, 128}
		},
		{
			self.pageVehicleSettings,
			function ()
				return self.currentVehicle ~= nil
			end,
			{896, 0, 128, 128}
		},
		{
			self.pageCourseGenerator,
			function ()
				return true
			end,
			{128, 0, 128, 128}
		},
		{
			self.pageCourseManager,
			function ()
				return true
			end,
			{256, 0, 128, 128}
		}
	}

	for i, pageDef in ipairs(orderedDefaultPages) do
		local page, predicate, iconUVs = unpack(pageDef)

		if page ~= nil then
			self:registerPage(page, i, predicate)

			local normalizedUVs = GuiUtils.getUVs(iconUVs)

			self:addPageTab(page, Utils.getFilename('img/ui_courseplay.dds', g_Courseplay.BASE_DIRECTORY), normalizedUVs)
		end
	end
end

-- Lines 365-397
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
		[InputAction.MENU_PAGE_PREV] = onButtonPagePreviousFunction
	}
end

-- Lines 399-424
function CpInGameMenu:onGuiSetupFinished()
	CpInGameMenu:superClass().onGuiSetupFinished(self)

	self:initializePages()
	self:setupMenuPages()
end

-- Lines 431-433
function CpInGameMenu:updateBackground()
	-- self.background:setVisible(self.currentPage.needsSolidBackground)
end

-- Lines 512-527
function CpInGameMenu:reset()
	CpInGameMenu:superClass().reset(self)

end

-- Lines 529-556
function CpInGameMenu:onMenuOpened()
	-- if self.playerFarmId == FarmManager.SPECTATOR_FARM_ID then
	-- 	self:setSoundSuppressed(true)

	-- 	local farmsPageId = self.pagingElement:getPageIdByElement(self.pageMultiplayerFarms)
	-- 	local farmsPageIndex = self.pagingElement:getPageMappingIndex(farmsPageId)

	-- 	self.pageSelector:setState(farmsPageIndex, true)
	-- 	self:setSoundSuppressed(false)
	-- end

	-- if GS_IS_MOBILE_VERSION then
	-- 	g_currentMission:setManualPause(true)
	-- end

	-- if self.currentPage.dynamicMapImageLoading ~= nil then
	-- 	if not self.currentPage.dynamicMapImageLoading:getIsVisible() then
	-- 		self.messageCenter:publish(MessageType.GUI_INGAME_OPEN)
	-- 	else
	-- 		self.sendDelayedOpenMessage = true
	-- 	end
	-- else
	-- 	self.messageCenter:publish(MessageType.GUI_INGAME_OPEN)
	-- end
end

function CpInGameMenu:onButtonBack()
	if self.currentPage.onClickBack then 
		if not self.currentPage:onClickBack() then 
			return
		end
	end
	CpInGameMenu:superClass().onButtonBack(self)
end

-- Lines 559-578
function CpInGameMenu:onClose(element)
	CpInGameMenu:superClass().onClose(self)
	self:unlockCurrentVehicle()
end

function CpInGameMenu:onOpen()
	CpInGameMenu:superClass().onOpen(self)
	self:lockCurrentVehicle(CpUtil.getCurrentVehicle())
end

-- Lines 650-699
function CpInGameMenu:update(dt)

	CpInGameMenu:superClass().update(self, dt)
end

-- Lines 820-823
function CpInGameMenu:onClickMenu()
	self:exitMenu()

	return true
end

-- Lines 844-866
function CpInGameMenu:onPageChange(pageIndex, pageMappingIndex, element, skipTabVisualUpdate)


	CpInGameMenu:superClass().onPageChange(self, pageIndex, pageMappingIndex, element, skipTabVisualUpdate)

	-- self.header:applyProfile(self:getTabBarProfile())
	self:updateBackground()
end

-- Lines 869-873
function CpInGameMenu:getPageButtonInfo(page)
	local buttonInfo = CpInGameMenu:superClass().getPageButtonInfo(self, page)

	return buttonInfo
end

function CpInGameMenu:lockCurrentVehicle(vehicle)
	if vehicle ~= self.currentVehicle then 
		g_messageCenter:publishDelayed(MessageType.GUI_CP_INGAME_CURRENT_VEHICLE_CHANGED, vehicle)
	end
	self.currentVehicle = vehicle
end

function CpInGameMenu:unlockCurrentVehicle()
	self.currentVehicle = nil
end

function CpInGameMenu:getCurrentVehicle()
	return self.currentVehicle
end

function CpInGameMenu:onCurrentVehicleChanged()
	if self:getIsOpen() then
		self:updatePages()
	end
end


CpInGameMenu.TAB_UV = {
	MAP = {
		0,
		0,
		65,
		65
	},
	AI = {
		910,
		65,
		65,
		65
	},
	CALENDAR = {
		65,
		0,
		65,
		65
	},
	WEATHER = {
		130,
		0,
		65,
		65
	},
	PRICES = {
		195,
		0,
		65,
		65
	},
	VEHICLES = {
		260,
		0,
		65,
		65
	},
	FINANCES = {
		325,
		0,
		65,
		65
	},
	ANIMALS = {
		390,
		0,
		65,
		65
	},
	CONTRACTS = {
		455,
		0,
		65,
		65
	},
	PRODUCTION = {
		520,
		0,
		65,
		65
	},
	STATISTICS = {
		585,
		0,
		65,
		65
	},
	GAME_SETTINGS = {
		650,
		0,
		65,
		65
	},
	GENERAL_SETTINGS = {
		715,
		0,
		65,
		65
	},
	CONTROLS_SETTINGS = {
		845,
		0,
		65,
		65
	},
	TOUR = {
		780,
		130,
		65,
		65
	},
	HELP = {
		0,
		65,
		65,
		65
	},
	FARMS = {
		260,
		65,
		65,
		65
	},
	USERS = {
		650,
		65,
		65,
		65
	}
}
CpInGameMenu.L10N_SYMBOL = {
	END_WITHOUT_SAVING = "ui_endWithoutSaving",
	BUTTON_SAVE_GAME = "button_saveGame",
	BUTTON_RESTART = "button_restart",
	SAVE_OVERWRITE = "dialog_savegameOverwrite",
	TUTORIAL_NOT_SAVED = "ui_tutorialIsNotSaved",
	END_GAME = "ui_youWantToQuitGame",
	SAVING_CONTENT = "ui_savingContent",
	SAVE_NO_SPACE = "ui_savegameSaveNoSpace",
	SELECT_DEVICE = "dialog_savegameSelectDevice",
	MASTER_SERVER_CONNECTION_LOST = "ui_masterServerConnectionLost",
	BUTTON_CANCEL_GAME = "button_cancelGame",
	END_TUTORIAL = "ui_endTutorial",
	NOT_SAVED = "ui_savegameNotSaved",
	SAVE_NO_DEVICE = "ui_savegameSaveNoDevice",
	BUTTON_BACK = "button_back"
}
CpInGameMenu.PROFILES = {
	TAB_BAR_DARK = "uiCpInGameMenuHeaderDark",
	TAB_BAR_LIGHT = "uiCpInGameMenuHeader"
}
