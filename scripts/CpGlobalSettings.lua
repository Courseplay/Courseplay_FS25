--- TODO: implement saving/loading

CpGlobalSettings = CpObject()
CpGlobalSettings.KEY = "GlobalSettings.GlobalSetting"

function CpGlobalSettings:init()
	self:loadSettingsSetup()
    g_messageCenter:subscribe(MessageType.SETTING_CHANGED[GameSettings.SETTING.USE_MILES], self.onUnitChanged, self)
    g_messageCenter:subscribe(MessageType.SETTING_CHANGED[GameSettings.SETTING.USE_ACRE], self.onUnitChanged, self)
    g_messageCenter:subscribe(MessageType.CP_DISTANCE_UNIT_CHANGED, self.onUnitChanged, self)

    self:registerConsoleCommands()
end

function CpGlobalSettings:registerXmlSchema(schema,baseKey)
    CpSettingsUtil.registerXmlSchema(schema, baseKey..CpGlobalSettings.KEY.."(?)")
end

--- Loads settings setup form an xmlFile.
function CpGlobalSettings:loadSettingsSetup()
    MessageType.CP_DISTANCE_UNIT_CHANGED = nextMessageTypeId()

    local filePath = Utils.getFilename("config/GlobalSettingsSetup.xml", g_Courseplay.BASE_DIRECTORY)
    CpSettingsUtil.loadSettingsFromSetup(self,filePath)
end

function CpGlobalSettings:loadFromXMLFile(xmlFile, baseKey)
    CpSettingsUtil.loadFromXmlFile(self, xmlFile, 
    baseKey .. CpGlobalSettings.KEY, nil)
    self:onDistanceUnitChanged()
end

function CpGlobalSettings:saveToXMLFile(xmlFile,baseKey)
    CpSettingsUtil.saveToXmlFile(self.settings, xmlFile, baseKey .. CpGlobalSettings.KEY, 
        nil, function (setting)
            return not setting:getIsUserSetting()
        end)
end

function CpGlobalSettings:saveUserSettingsToXmlFile(xmlFile,baseKey)
    CpSettingsUtil.saveToXmlFile(self.settings, xmlFile, baseKey .. CpGlobalSettings.KEY, 
        nil, function (setting)
            return setting:getIsUserSetting()
        end)
end

function CpGlobalSettings:getSettings()
    return self
end

function CpGlobalSettings:getSettingsTable()
    return self.settings
end

function CpGlobalSettings:getSettingSetup()
	return self.settingsBySubTitle,self.pageTitle
end

--- Callback raised by a setting.
---@param callbackStr string function to be executed.
---@param setting AIParameterSettingList setting that raised the callback.
function CpGlobalSettings:raiseCallback(callbackStr, setting, ...)
    if self[callbackStr] then 
        self[callbackStr](self, setting, ...)
    end
end

function CpGlobalSettings:raiseDirtyFlag(setting)
    GlobalSettingsEvent.sendEvent(setting)
end

function CpGlobalSettings:onCpUserSettingChanged()
    g_Courseplay:saveUserSettings()
end

function CpGlobalSettings:onHudSelectionChanged()
    local vehicle = CpUtil.getCurrentVehicle()
    if vehicle then 
        self:debug("reset action events for %s",vehicle:getName())
    --    g_inputBinding:setShowMouseCursor(false)
        CpGuiUtil.setCameraRotation(vehicle, true, vehicle.spec_cpHud.savedCameraRotatableInfo)
        vehicle:requestActionEventUpdate()
    end
end

function CpGlobalSettings:onActionEventTextVisibilityChanged()
    local vehicle = CpUtil.getCurrentVehicle()
    if vehicle then 
        vehicle:requestActionEventUpdate()
    end
    CpDebug:updateActionEventTextVisibility()
end

function CpGlobalSettings:onDistanceUnitChanged()
    g_messageCenter:publish(MessageType.CP_DISTANCE_UNIT_CHANGED)
end

function CpGlobalSettings:onUnitChanged()
    for i,setting in ipairs(self.settings) do 
        setting:validateTexts()
    end
end

function CpGlobalSettings:debug(str,...)
    CpUtil.debugFormat(CpDebug.DBG_HUD,"Global settings: "..str,...)    
end

---------------------------------------------
--- Console Commands
---------------------------------------------

function CpGlobalSettings:registerConsoleCommands()
    g_consoleCommands:registerConsoleCommand("cpSettingsPrintGlobal",
        "Prints the global settings or a given setting", 
        "consoleCommandPrintSetting", self)
end

--- Either prints all settings or a desired setting by the name or index in the setting table.
---@param name any
function CpGlobalSettings:consoleCommandPrintSetting(name)
    if name == nil then 
        CpUtil.info("%d Global settings printed", tostring(self.settings))
        return
    end
    local num = tonumber(name)
    if num then 
        CpUtil.info(tostring(self.settings[num]))
        return
    end
    CpUtil.info(tostring(self[name]))
end
