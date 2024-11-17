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
	self.pageGlobalSettings:initialize()
	self.pageVehicleSettings:initialize()
	self.pageCourseGenerator:initialize()
	self.pageCourseManager:initialize()
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
				return CpUtil.getCurrentVehicle() ~= nil
			end,
			{896, 0, 128, 128}
		},
		{
			self.pageCourseGenerator,
			function ()
				return CpUtil.getCurrentVehicle() ~= nil
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
	local onButtonQuitFunction = self:makeSelfCallback(self.onButtonQuit)
	local onButtonSaveGameFunction = self:makeSelfCallback(self.onButtonSaveGame)
	self.backButtonInfo = {
		inputAction = InputAction.MENU_BACK,
		text = self.l10n:getText(CpInGameMenu.L10N_SYMBOL.BUTTON_BACK),
		callback = onButtonBackFunction
	}
	self.saveButtonInfo = {
		showWhenPaused = true,
		inputAction = InputAction.MENU_ACTIVATE,
		text = self.l10n:getText(CpInGameMenu.L10N_SYMBOL.BUTTON_SAVE_GAME),
		callback = onButtonSaveGameFunction
	}
	self.quitButtonInfo = {
		showWhenPaused = true,
		inputAction = InputAction.MENU_CANCEL,
		text = self.l10n:getText(CpInGameMenu.L10N_SYMBOL.BUTTON_CANCEL_GAME),
		callback = onButtonQuitFunction
	}

	self.defaultMenuButtonInfo = {
		self.backButtonInfo,
		self.saveButtonInfo,
		self.quitButtonInfo
	}

	self.defaultMenuButtonInfoByActions[InputAction.MENU_BACK] = self.defaultMenuButtonInfo[1]
	self.defaultMenuButtonInfoByActions[InputAction.MENU_ACTIVATE] = self.defaultMenuButtonInfo[2]
	self.defaultMenuButtonInfoByActions[InputAction.MENU_CANCEL] = self.defaultMenuButtonInfo[3]
	self.defaultButtonActionCallbacks = {
		[InputAction.MENU_BACK] = onButtonBackFunction,
		[InputAction.MENU_CANCEL] = onButtonQuitFunction,
		[InputAction.MENU_ACTIVATE] = onButtonSaveGameFunction
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

-- Lines 559-578
function CpInGameMenu:onClose(element)
	CpInGameMenu:superClass().onClose(self)

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
