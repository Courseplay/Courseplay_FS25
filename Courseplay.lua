
--- Global class
---@class Courseplay
---@operator call:Courseplay
Courseplay = CpObject()
Courseplay.MOD_NAME = g_currentModName
Courseplay.BASE_DIRECTORY = g_currentModDirectory
Courseplay.baseXmlKey = "Courseplay"
Courseplay.xmlKey = Courseplay.baseXmlKey.."."

function Courseplay:init()
	---TODO_25
	-- g_gui:loadProfiles( Utils.getFilename("config/gui/GUIProfiles.xml", Courseplay.BASE_DIRECTORY) )

	--- Base cp folder
	self.baseDir = getUserProfileAppPath() .. "modSettings/" .. Courseplay.MOD_NAME ..  "/"
	createFolder(self.baseDir)
	--- Base cp folder
	self.cpFilePath = self.baseDir.."courseplay.xml"
end

function Courseplay:registerXmlSchema()
	self.xmlSchema = XMLSchema.new("Courseplay")
	self.xmlSchema:register(XMLValueType.STRING, self.baseXmlKey.."#lastVersion")
	self.globalSettings:registerXmlSchema(self.xmlSchema, self.xmlKey)
	CpBaseHud.registerXmlSchema(self.xmlSchema, self.xmlKey)
	CpHudInfoTexts.registerXmlSchema(self.xmlSchema, self.xmlKey)
end

--- Loads data not tied to a savegame.
function Courseplay:loadUserSettings()
	local xmlFile = XMLFile.loadIfExists("cpXmlFile", self.cpFilePath, self.xmlSchema)
	if xmlFile then
		self:showUserInformation(xmlFile, self.baseXmlKey)
		self.globalSettings:loadFromXMLFile(xmlFile, self.xmlKey)
		CpBaseHud.loadFromXmlFile(xmlFile, self.xmlKey)
		CpHudInfoTexts.loadFromXmlFile(xmlFile, self.xmlKey)
		xmlFile:save()
		xmlFile:delete()
	else
		self:showUserInformation()
	end
end

--- Saves data not tied to a savegame.
function Courseplay:saveUserSettings()
	local xmlFile = XMLFile.create("cpXmlFile", self.cpFilePath, self.baseXmlKey, self.xmlSchema)
	if xmlFile then 
		self.globalSettings:saveUserSettingsToXmlFile(xmlFile, self.xmlKey)
		CpBaseHud.saveToXmlFile(xmlFile, self.xmlKey)
		CpHudInfoTexts.saveToXmlFile(xmlFile, self.xmlKey)
		if self.currentVersion then
			xmlFile:setValue(self.baseXmlKey.."#lastVersion", self.currentVersion)
		end
		xmlFile:save()
		xmlFile:delete()
	end
end

------------------------------------------------------------------------------------------------------------------------
-- User info with github reference and update notification.
------------------------------------------------------------------------------------------------------------------------

function Courseplay:showUserInformation(xmlFile, key)
	local showInfoDialog = true
	self.currentVersion = g_modManager:getModByName(self.MOD_NAME).version
	local lastLoadedVersion = "----"
	if xmlFile then 
		lastLoadedVersion = xmlFile:getValue(key.."#lastVersion")
		showInfoDialog = self.currentVersion ~= lastLoadedVersion
	else 
		lastLoadedVersion = "no config file!"
	end
	CpUtil.info("Current mod name: %s, Current version: %s, Last version: %s", 
		self.MOD_NAME, self.currentVersion, lastLoadedVersion)

	if showInfoDialog then
		InfoDialog.show(string.format(g_i18n:getText("CP_infoText"), self.currentVersion))
		if xmlFile then 
			xmlFile:setValue(key.."#lastVersion", self.currentVersion)
		end
	end
end

------------------------------------------------------------------------------------------------------------------------
-- Global Giants functions listener 
------------------------------------------------------------------------------------------------------------------------

--- This function is called on loading a savegame.
---@param filename string
function Courseplay:loadMap(filename)
	self.globalSettings = CpGlobalSettings()
	self:registerXmlSchema()
	self:loadUserSettings()
	--- Savegame infos here
	CpUtil.info("Map loaded: %s, Savegame name: %s(%d)", 
		g_currentMission.missionInfo.mapId, 
		g_currentMission.missionInfo.savegameName,
		g_currentMission.missionInfo.savegameIndex)
	self:load()
	self:setupGui()
	if g_currentMission.missionInfo.savegameDirectory ~= nil then
		local saveGamePath = g_currentMission.missionInfo.savegameDirectory .."/"
		local filePath = saveGamePath .. "Courseplay.xml"
		self.xmlFile = XMLFile.load("cpXml", filePath , self.xmlSchema)
		if self.xmlFile == nil then return end
		self.globalSettings:loadFromXMLFile(self.xmlFile, g_Courseplay.xmlKey)
		self.xmlFile:delete()
	end

	--- Ugly hack to get access to the global AutoDrive table, as this global is dependent on the auto drive folder name.
	self.autoDrive = FS22_AutoDrive and FS22_AutoDrive.AutoDrive
	CpUtil.info("Auto drive found: %s", tostring(self.autoDrive~=nil))

	g_courseEditor:load()
end

function Courseplay:deleteMap()
	g_courseEditor:delete()
	BufferedCourseDisplay.deleteBuffer()
	g_signPrototypes:delete()
	g_consoleCommands:delete()
end

function Courseplay:setupGui()
	CpInGameMenu.setupGui(self.courseStorage)
			  

	self.infoTextsHud = CpHudInfoTexts()

	-- TODO_25
	-- g_currentMission.hud.ingameMap.drawFields = Utils.appendedFunction(g_currentMission.hud.ingameMap.drawFields, Courseplay.drawHudMap)

	-- local page = g_gui.currentGui.target.pageSettings

	-- local newPage = page.subCategoryPages[1].copy(page.subCategoryPages[1].parent)
	-- self:fixGui()
end

--- Enables drawing onto the hud map.
function Courseplay.drawHudMap(map)
	if g_Courseplay.globalSettings.drawOntoTheHudMap:getValue() then
		local vehicle = CpUtil.getCurrentVehicle()
		if vehicle and vehicle:getIsEntered() and not g_gui:getIsGuiVisible() and vehicle.spec_cpAIWorker and not vehicle.spec_locomotive then 
			SpecializationUtil.raiseEvent(vehicle, "onCpDrawHudMap", map)
		end
	end
end

--- Saves all global data, for example global settings.
function Courseplay.saveToXMLFile(missionInfo)
	if missionInfo.isValid then 
		local saveGamePath = missionInfo.savegameDirectory .."/"
		local xmlFile = XMLFile.create("cpXml", saveGamePath.. "Courseplay.xml", 
				"Courseplay", g_Courseplay.xmlSchema)
		if xmlFile then	
			g_Courseplay.globalSettings:saveToXMLFile(xmlFile, g_Courseplay.xmlKey)
			xmlFile:save()
			xmlFile:delete()
		end
		g_Courseplay:saveUserSettings()
		g_assignedCoursesManager:saveAssignedCourses(saveGamePath)
	end
end
FSCareerMissionInfo.saveToXMLFile = Utils.prependedFunction(FSCareerMissionInfo.saveToXMLFile, Courseplay.saveToXMLFile)

function Courseplay:update(dt)
    g_devHelper:update()
    g_bunkerSiloManager:update(dt)
    g_triggerManager:update(dt)
	g_baleToCollectManager:update(dt)
	g_courseEditor:update(dt)
    if not self.postInit then 
        -- Doubles the map zoom for 4x Maps. Mainly to make it easier to set targets for unload triggers.
        self.postInit = true
        local function setIngameMapFix(mapElement)
            local factor = 2*mapElement.terrainSize/2048
            mapElement.zoomMax = mapElement.zoomMax * factor
        end
		--- TODO_25
        -- setIngameMapFix(g_currentMission.inGameMenu.pageAI.ingameMap)
        -- setIngameMapFix(g_currentMission.inGameMenu.pageMapOverview.ingameMap)
    end
end

function Courseplay:draw()
	if not g_gui:getIsGuiVisible() then
		g_vineScanner:draw()
		g_bunkerSiloManager:draw()
		g_triggerManager:draw()
		g_baleToCollectManager:draw()
	end
	g_devHelper:draw()
	CpDebug:draw()
	if not g_gui:getIsGuiVisible() and not g_noHudModeEnabled then
		self.infoTextsHud:draw()
	end
end

---@param posX number
---@param posY number
---@param isDown boolean
---@param isUp boolean
---@param button number
function Courseplay:mouseEvent(posX, posY, isDown, isUp, button)
	if not g_gui:getIsGuiVisible() then
		local vehicle = CpUtil.getCurrentVehicle()
		local hud = vehicle and vehicle.getCpHud and vehicle:getCpHud()
		if hud then
			hud:mouseEvent(posX, posY, isDown, isUp, button)
		end
		self.infoTextsHud:mouseEvent(posX, posY, isDown, isUp, button)
	end
end

---@param unicode number
---@param sym number
---@param modifier number
---@param isDown boolean
function Courseplay:keyEvent(unicode, sym, modifier, isDown)
	g_devHelper:keyEvent(unicode, sym, modifier, isDown)
end

function Courseplay:load()
	--- Sub folder for debug information
	self.debugDir = self.baseDir .. "Debug/"
	createFolder(self.debugDir) 
	--- Sub folder for debug prints
	self.debugPrintDir = self.debugDir .. "DebugPrints/"
	createFolder(self.debugPrintDir) 
	--- Default path to save prints without an explicit name.
	self.defaultDebugPrintPath = self.debugDir .. "DebugPrint.xml"

	self.courseDir = self.baseDir .. "Courses"
	createFolder(self.courseDir) 
	self.courseStorage = FileSystem(self.courseDir, g_currentMission.missionInfo.mapId)
	self.courseStorage:fixCourseStorageRoot()

	self.customFieldDir = self.baseDir .. "CustomFields"
	createFolder(self.customFieldDir)
	g_customFieldManager = CustomFieldManager(FileSystem(self.customFieldDir, g_currentMission.missionInfo.mapId))
	g_vehicleConfigurations:loadFromXml()
	g_assignedCoursesManager:registerXmlSchema()

	--- Register additional AI messages.
	CpAIMessages.register()	
	g_vineScanner:setup()
end
------------------------------------------------------------------------------------------------------------------------
-- Player action events
------------------------------------------------------------------------------------------------------------------------

--- Adds player mouse action event, for global info texts.
function Courseplay.addPlayerActionEvents(mission)
	if mission.player then
		CpUtil.debugFormat(CpDebug.DBG_HUD, "Added player input events")
		mission.player.inputInformation.registrationList[InputAction.CP_TOGGLE_MOUSE] = {
			text = "",
			triggerAlways = false,
			triggerDown = false,
			eventId = "",
			textVisibility = false,
			triggerUp = true,
			callback = Courseplay.onOpenCloseMouseEvent,
			activeType = Player.INPUT_ACTIVE_TYPE.STARTS_ENABLED
		}
		mission.player.updateActionEvents = Utils.appendedFunction(mission.player.updateActionEvents, Courseplay.updatePlayerActionEvents)
		mission.player.removeActionEvents = Utils.prependedFunction(mission.player.removeActionEvents, Courseplay.removePlayerActionEvents)
	end
end
FSBaseMission.onStartMission = Utils.appendedFunction(FSBaseMission.onStartMission , Courseplay.addPlayerActionEvents)

--- Open/close mouse in player state.
function Courseplay.onOpenCloseMouseEvent(player, forceReset)
	if g_Courseplay.infoTextsHud:isVisible() and not player:hasHandtoolEquipped() then
		if forceReset or g_Courseplay.globalSettings.infoTextHudPlayerMouseActive:getValue() then
			local showMouseCursor = not g_inputBinding:getShowMouseCursor()
			g_inputBinding:setShowMouseCursor(showMouseCursor)
			local leftRightRotationEventId = player.inputInformation.registrationList[InputAction.AXIS_LOOK_LEFTRIGHT_PLAYER].eventId
			local upDownRotationEventId = player.inputInformation.registrationList[InputAction.AXIS_LOOK_UPDOWN_PLAYER].eventId
			g_inputBinding:setActionEventActive(leftRightRotationEventId, not showMouseCursor)
			g_inputBinding:setActionEventActive(upDownRotationEventId, not showMouseCursor)
			player.wasCpMouseActive = showMouseCursor
		end
	end
end

--- Enables/disables the player mouse action event, if there are any info texts.
function Courseplay.updatePlayerActionEvents(player)
	local eventId = player.inputInformation.registrationList[InputAction.CP_TOGGLE_MOUSE].eventId
	g_inputBinding:setActionEventTextVisibility(eventId, false)
	if not player:hasHandtoolEquipped() then
		if g_Courseplay.infoTextsHud:isVisible() and g_Courseplay.globalSettings.infoTextHudPlayerMouseActive:getValue() then 
			g_inputBinding:setActionEventTextVisibility(eventId, true)
		elseif player.wasCpMouseActive then 
			Courseplay.onOpenCloseMouseEvent(player, true)
		end
	end
end

--- Resets the mouse cursor on entering a vehicle for example.
function Courseplay.removePlayerActionEvents(player)
	if player.wasCpMouseActive then
		g_inputBinding:setShowMouseCursor(false)
	end
	player.wasCpMouseActive = nil
end

--- Registers all cp specializations.
---@param typeManager table
function Courseplay.register(typeManager)
	if typeManager.typeName == "vehicle" and g_modIsLoaded[Courseplay.MOD_NAME] then
		--- TODO: make this function async. 
		for typeName, typeEntry in pairs(typeManager.types) do	
			CpAIWorker.register(typeManager, typeName, typeEntry.specializations)
			CpVehicleSettings.register(typeManager, typeName, typeEntry.specializations)
			CpCourseGeneratorSettings.register(typeManager, typeName, typeEntry.specializations)
			CpCourseManager.register(typeManager, typeName, typeEntry.specializations)
			CpAIFieldWorker.register(typeManager, typeName, typeEntry.specializations)
			CpAIBaleFinder.register(typeManager, typeName, typeEntry.specializations)
			CpAICombineUnloader.register(typeManager, typeName, typeEntry.specializations)
			CpAISiloLoaderWorker.register(typeManager, typeName, typeEntry.specializations)
			CpAIBunkerSiloWorker.register(typeManager, typeName, typeEntry.specializations)
			-- TODO 25 CpGamePadHud.register(typeManager, typeName,typeEntry.specializations)
			CpHud.register(typeManager, typeName, typeEntry.specializations)
			CpInfoTexts.register(typeManager, typeName, typeEntry.specializations)
			CpShovelPositions.register(typeManager, typeName, typeEntry.specializations)
		end
		typeManager:addSpecialization("fillableImplement", "aiLoadable")
	end
end
TypeManager.finalizeTypes = Utils.prependedFunction(TypeManager.finalizeTypes, Courseplay.register)

g_Courseplay = Courseplay()
addModEventListener(g_Courseplay)