--- This specialization is used for visual changing of settings values in a vehicle.

---@class CpGamePadHud
CpGamePadHud = {}

CpGamePadHud.MOD_NAME = g_currentModName
CpGamePadHud.NAME = ".cpGamePadHud"
CpGamePadHud.SPEC_NAME = CpGamePadHud.MOD_NAME .. CpGamePadHud.NAME
CpGamePadHud.XML_KEY = "Settings.Setting"
CpGamePadHud.XML_KEY_TITLE = "Settings#title"
CpGamePadHud.GUI_NAME = "CpGamePadHudDialog"

CpGamePadHud.SETTING_TYPES = {
	vehicleSettings = CpVehicleSettings,
	courseGeneratorSettings = CpCourseGeneratorSettings,
	fieldWorkJobParameters = CpFieldWorkJobParameters,
	baleFinderJobParameters = CpBaleFinderJobParameters,
	combineUnloaderJobParameters = CpCombineUnloaderJobParameters,
	bunkerSiloJobParameters = CpBunkerSiloJobParameters,
	siloLoaderJobParameters = CpSiloLoaderJobParameters,
	globalSettings = CpGlobalSettings
}

CpGamePadHud.FIELDWORK_PAGE = "cpFieldworkGamePadHudPage"
CpGamePadHud.BALE_LOADER_PAGE = "cpBaleLoaderGamePadHudPage"
CpGamePadHud.UNLOADER_PAGE = "cpUnloaderGamePadHudPage"
CpGamePadHud.BUNKER_SILO_PAGE = "cpBunkerSiloGamePadHudPage"
CpGamePadHud.SILO_LOADER_PAGE = "cpSiloLoaderGamePadHudPage"

CpGamePadHud.PAGE_FILES = {
	[CpGamePadHud.FIELDWORK_PAGE ] = {"config/gamePadHud/FieldworkGamePadHudPage.xml", CpGamePadHudFieldWorkScreen},
	[CpGamePadHud.BALE_LOADER_PAGE] = {"config/gamePadHud/BaleLoaderGamePadHudPage.xml", CpGamePadHudBaleLoaderScreen},
	[CpGamePadHud.UNLOADER_PAGE] = {"config/gamePadHud/UnloaderGamePadHudPage.xml", CpGamePadHudUnloaderScreen},
	[CpGamePadHud.BUNKER_SILO_PAGE] = {"config/gamePadHud/BunkerSiloGamePadHudPage.xml", CpGamePadHudBunkerSiloScreen},
	[CpGamePadHud.SILO_LOADER_PAGE] = {"config/gamePadHud/SiloLoaderGamePadHudPage.xml", CpGamePadHudSiloLoaderScreen}
}

function CpGamePadHud.initSpecialization()
	CpGamePadHud.xmlSchema = XMLSchema.new("CpGamePadHudSchema")
	local schema = CpGamePadHud.xmlSchema
	schema:register(XMLValueType.STRING, CpGamePadHud.XML_KEY_TITLE, "Title of the display.")
	schema:register(XMLValueType.STRING, CpGamePadHud.XML_KEY.."(?)#name", "Setting name to bind.")
	schema:register(XMLValueType.STRING, CpGamePadHud.XML_KEY.."(?)#type", "Setting parent.")
end

function CpGamePadHud.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(CpAIWorker, specializations) 
end

function CpGamePadHud.register(typeManager, typeName, specializations)
	if CpGamePadHud.prerequisitesPresent(specializations) then
		typeManager:addSpecialization(typeName, CpGamePadHud.SPEC_NAME)
	end
end

--- Creates gui elements for the mini gui.
function CpGamePadHud.loadFromXMLFile()
	CpGamePadHud.pages = {}
	for pageName, data in pairs(CpGamePadHud.PAGE_FILES) do 
		CpUtil.debugFormat(CpDebug.DBG_HUD, "Loading game pad hud page %s from: %s", pageName, data[1])
		CpGamePadHud.pages[pageName] = {}
		CpGamePadHud.loadPageData(CpGamePadHud.pages[pageName], Utils.getFilename(data[1], Courseplay.BASE_DIRECTORY))
		-- Setup of the mini gui.
		CpGamePadHud.pages[pageName].screen = data[2].new(CpGamePadHud.pages[pageName].prefabSettingsData)
		g_gui:loadGui(Utils.getFilename("config/gui/ControllerGuiScreen.xml", Courseplay.BASE_DIRECTORY), pageName, CpGamePadHud.pages[pageName].screen)
	end
	--- Enables a few background hud elements, while the vehicle setting display is visible.
	local function getIsOverlayGuiVisible(gui, superFunc)
		return CpGamePadHud.PAGE_FILES[gui.currentGuiName] ~= nil or superFunc(gui) 
	end
	Gui.getIsOverlayGuiVisible = Utils.overwrittenFunction(Gui.getIsOverlayGuiVisible, getIsOverlayGuiVisible)

	local function isHudPopupMessageVisible(hud, superFunc, ...)
		print(tostring(CpUtil.getCurrentVehicle() and CpUtil.getCurrentVehicle().isCpGamePadHudActive and CpUtil.getCurrentVehicle():isCpGamePadHudActive()))
		return superFunc(hud, ...) or CpUtil.getCurrentVehicle() and CpUtil.getCurrentVehicle().isCpGamePadHudActive and CpUtil.getCurrentVehicle():isCpGamePadHudActive()
	end
	g_currentMission.hud.popupMessage.getIsVisible = Utils.overwrittenFunction(g_currentMission.hud.popupMessage.getIsVisible, isHudPopupMessageVisible)
end

function CpGamePadHud.loadPageData(page, filePath)
	local xmlFile = XMLFile.load("CpGamePadHudXml", filePath, CpGamePadHud.xmlSchema)
	if xmlFile then 
		page.title = xmlFile:getValue(CpGamePadHud.XML_KEY_TITLE)
		page.settingsData = {}
		page.prefabSettingsData = {}
		xmlFile:iterate(CpGamePadHud.XML_KEY, function (ix, key)
			local settingName = xmlFile:getValue(key .. "#name")
			local settingType = xmlFile:getValue(key .. "#type")
			local settingData = {
				settingName = settingName,
				settingType = settingType
			}
			table.insert(page.settingsData, settingData)

			local prefabSetting = CpGamePadHud.SETTING_TYPES[settingType][settingName]

			table.insert(page.prefabSettingsData, prefabSetting)
		end)
		xmlFile:delete()
	end
end

function CpGamePadHud.registerEventListeners(vehicleType)	
	SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", CpGamePadHud)
	SpecializationUtil.registerEventListener(vehicleType, "onLoad", CpGamePadHud)
	SpecializationUtil.registerEventListener(vehicleType, "onLoadFinished", CpGamePadHud)
--    SpecializationUtil.registerEventListener(vehicleType, "onEnterVehicle", CpGamePadHud)
--    SpecializationUtil.registerEventListener(vehicleType, "onLeaveVehicle", CpGamePadHud)

end

function CpGamePadHud.registerFunctions(vehicleType)
	SpecializationUtil.registerFunction(vehicleType, "isCpGamePadHudActive", CpGamePadHud.isCpGamePadHudActive)
	SpecializationUtil.registerFunction(vehicleType, "closeCpGamePadHud", CpGamePadHud.closeCpGamePadHud)
	SpecializationUtil.registerFunction(vehicleType, "reopenCpGamePadHud", CpGamePadHud.reopenCpGamePadHud)
end

function CpGamePadHud.registerOverwrittenFunctions(vehicleType)
   
end
------------------------------------------------------------------------------------------------------------------------
--- Event listeners
---------------------------------------------------------------------------------------------------------------------------
function CpGamePadHud:onLoad(savegame)
	--- Register the spec: spec_cpGamePadHud
    self.spec_cpGamePadHud = self["spec_" .. CpGamePadHud.SPEC_NAME]
    local spec = self.spec_cpGamePadHud
	spec.text = g_i18n:getText("input_CP_OPEN_CLOSE_VEHICLE_SETTING_DISPLAY")
	spec.hudText = g_i18n:getText("input_CP_OPEN_CLOSE_HUD")
	spec.isVisible = false
end

function CpGamePadHud:onLoadFinished()
	if not CpGamePadHud.initialized then 
		CpGamePadHud.loadFromXMLFile()
		CpGamePadHud.initialized = true
	end
	CpGamePadHud.linkSettings(self)
end

function CpGamePadHud:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
	if self.isClient then
		local spec = self.spec_cpGamePadHud
		self:clearActionEventsTable(spec.actionEvents)
		--- Key bind gets switch between opening hud or controller friendly gui.
		if not g_Courseplay.globalSettings.controllerHudSelected:getValue() then 
			if self.isActiveForInputIgnoreSelectionIgnoreAI then
				local _, actionEventId = self:addActionEvent(spec.actionEvents, InputAction.CP_OPEN_CLOSE_VEHICLE_SETTING_DISPLAY, self, CpHud.openClose, false, true, false, true, nil)
				g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_HIGH)
				g_inputBinding:setActionEventText(actionEventId, spec.hudText)
				g_inputBinding:setActionEventTextVisibility(actionEventId, g_Courseplay.globalSettings.showActionEventHelp:getValue())
			end
		else
			if self.isActiveForInputIgnoreSelectionIgnoreAI then
				local _, actionEventId = self:addActionEvent(spec.actionEvents, InputAction.CP_OPEN_CLOSE_VEHICLE_SETTING_DISPLAY, self, CpGamePadHud.actionEventOpenCloseDisplay, false, true, false, true, nil)
				g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_HIGH)
				g_inputBinding:setActionEventText(actionEventId, spec.text)
				g_inputBinding:setActionEventTextVisibility(actionEventId, g_Courseplay.globalSettings.showActionEventHelp:getValue())
			end
		end
	end
end

--- Gets called by the active mini gui, as vehicle:onDraw() is otherwise not displayed.
function CpGamePadHud.onDraw(vehicle)
	if vehicle then
		local settings = vehicle:getCpSettings()
		local courseGeneratorSettings = vehicle:getCourseGeneratorSettings()
		WorkWidthUtil.showWorkWidth(vehicle, courseGeneratorSettings.workWidth:getValue(), settings.toolOffsetX:getValue(), 0)
	end
end


function CpGamePadHud:linkSettings()
	local spec = self.spec_cpGamePadHud
	spec.pages = {}
	for pageName, page in pairs(CpGamePadHud.pages) do 
		spec.pages[pageName] = {}
		spec.pages[pageName].settings = {}
		for ix, data in ipairs(page.settingsData) do 
			local func = CpGamePadHud.SETTING_TYPES[data.settingType].getSettings
			local settings = func(self)
			local setting = settings[data.settingName]
			table.insert(spec.pages[pageName].settings, setting)
		end
	end
end

function CpGamePadHud:actionEventOpenCloseDisplay()
	local spec = self.spec_cpGamePadHud
	local page
	if self:cpIsHudFieldWorkJobSelected() then 
        page = CpGamePadHud.FIELDWORK_PAGE
    elseif self:cpIsHudBaleFinderJobSelected() then
        page = CpGamePadHud.BALE_LOADER_PAGE
    elseif self:cpIsHudBunkerSiloJobSelected() then
        page = CpGamePadHud.BUNKER_SILO_PAGE
    elseif self:cpIsHudSiloLoaderJobSelected() then
        page = CpGamePadHud.SILO_LOADER_PAGE
    elseif self:cpIsHudUnloaderJobSelected() then
        page = CpGamePadHud.UNLOADER_PAGE
    elseif self:cpIsHudStreetJobSelected() then
		page = CpGamePadHud.FIELDWORK_PAGE
    end
	if page then
		spec.isVisible = true
		CpGamePadHud.pages[page].screen:setData(self, spec.pages[page].settings) 
		g_gui:showGui(page)
	end
end

function CpGamePadHud:isCpGamePadHudActive()
	local spec = self.spec_cpGamePadHud
	return spec.isVisible
end

function CpGamePadHud:closeCpGamePadHud()
	local spec = self.spec_cpGamePadHud
	spec.isVisible = false
end

function CpGamePadHud:reopenCpGamePadHud()
	g_gui:showGui("")
	CpGamePadHud.actionEventOpenCloseDisplay(self)
end