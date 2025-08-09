--[[
    CourseGenerator settings
]]--

---@class CpCourseGeneratorSettings
CpCourseGeneratorSettings = {}

CpCourseGeneratorSettings.MOD_NAME = g_currentModName
CpCourseGeneratorSettings.SETTINGS_KEY = ".settings"
CpCourseGeneratorSettings.VINE_SETTINGS_KEY = ".vineSettings"
CpCourseGeneratorSettings.NAME = ".cpCourseGeneratorSettings"
CpCourseGeneratorSettings.SPEC_NAME = CpCourseGeneratorSettings.MOD_NAME .. CpCourseGeneratorSettings.NAME
CpCourseGeneratorSettings.KEY = "." .. CpCourseGeneratorSettings.MOD_NAME .. CpCourseGeneratorSettings.NAME

function CpCourseGeneratorSettings.initSpecialization()
	local schema = Vehicle.xmlSchemaSavegame
    --- Old save format
    CpSettingsUtil.registerXmlSchema(schema, 
        "vehicles.vehicle(?)"..CpCourseGeneratorSettings.KEY.."(?)")
    
    --- Normal course generator settings.
    CpSettingsUtil.registerXmlSchema(schema, 
        "vehicles.vehicle(?)"..CpCourseGeneratorSettings.KEY..CpCourseGeneratorSettings.SETTINGS_KEY.."(?)")
    
    --- Vine course generator settings.
    CpSettingsUtil.registerXmlSchema(schema, 
        "vehicles.vehicle(?)"..CpCourseGeneratorSettings.KEY..CpCourseGeneratorSettings.VINE_SETTINGS_KEY.."(?)")
    CpCourseGeneratorSettings.loadSettingsSetup()

    CpCourseGeneratorSettings.registerConsoleCommands()
end

function CpCourseGeneratorSettings.register(typeManager,typeName,specializations)
	if CpCourseGeneratorSettings.prerequisitesPresent(specializations) then
		typeManager:addSpecialization(typeName, CpCourseGeneratorSettings.SPEC_NAME)
	end
end

function CpCourseGeneratorSettings.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(CpAIWorker, specializations) 
end

function CpCourseGeneratorSettings.registerEvents(vehicleType)
 --   SpecializationUtil.registerEvent(vehicleType,"cpUpdateGui")
end

function CpCourseGeneratorSettings.registerEventListeners(vehicleType)	
	SpecializationUtil.registerEventListener(vehicleType, "onLoad", CpCourseGeneratorSettings)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", CpCourseGeneratorSettings)
    SpecializationUtil.registerEventListener(vehicleType, "onLoadFinished",CpCourseGeneratorSettings)
    SpecializationUtil.registerEventListener(vehicleType, "onCpUnitChanged", CpCourseGeneratorSettings)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", CpCourseGeneratorSettings)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", CpCourseGeneratorSettings)
end
function CpCourseGeneratorSettings.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, 'getCourseGeneratorSettings', CpCourseGeneratorSettings.getSettings)
    SpecializationUtil.registerFunction(vehicleType, 'getCourseGeneratorSettingsTable', CpCourseGeneratorSettings.getSettingsTable)
    SpecializationUtil.registerFunction(vehicleType, 'getCpVineSettings', CpCourseGeneratorSettings.getCpVineSettings)
    SpecializationUtil.registerFunction(vehicleType, 'getCpVineSettingsTable', CpCourseGeneratorSettings.getCpVineSettingsTable)
    SpecializationUtil.registerFunction(vehicleType, 'validateCourseGeneratorSettings', CpCourseGeneratorSettings.validateSettings)
end

-- shortcut to access the spec
function CpCourseGeneratorSettings.getSpec(self)
    return self["spec_" .. CpCourseGeneratorSettings.SPEC_NAME]
end

--- Gets all settings.
---@return table
function CpCourseGeneratorSettings:getSettings()
    local spec = CpCourseGeneratorSettings.getSpec(self)  
    return spec
end

--- Gets all settings.
---@return table
function CpCourseGeneratorSettings:getSettingsTable()
    local spec = CpCourseGeneratorSettings.getSpec(self)  
    return spec.settings
end

--- Gets all vine settings.
---@return table
function CpCourseGeneratorSettings:getCpVineSettings()
    local spec = CpCourseGeneratorSettings.getSpec(self)  
    return spec.vineSettings
end

--- Gets all settings.
---@return table
function CpCourseGeneratorSettings:getCpVineSettingsTable()
    local spec = CpCourseGeneratorSettings.getSpec(self)  
    return spec.vineSettings.settings
end

function CpCourseGeneratorSettings:onLoad(savegame)
    local spec = CpCourseGeneratorSettings.getSpec(self) 

    --- Clones the generic settings to create different settings containers for each vehicle. 
    CpSettingsUtil.cloneSettingsTable(spec,CpCourseGeneratorSettings.settings,self,CpCourseGeneratorSettings)

    spec.vineSettings = {}
    --- Clones the generic settings to create different settings containers for each vehicle. 
    CpSettingsUtil.cloneSettingsTable(spec.vineSettings,CpCourseGeneratorSettings.vineSettings.settings,self,CpCourseGeneratorSettings)

    CpCourseGeneratorSettings.loadSettings(self,savegame)
end

--- Apply auto work width after everything is loaded.
function CpCourseGeneratorSettings:onLoadFinished()
    CpCourseGeneratorSettings.setAutomaticWorkWidthAndOffset(self)
    CpCourseGeneratorSettings.setDefaultTurningRadius(self)
end

--- Resets the work width to a saved value after all implements are loaded and attached.
function CpCourseGeneratorSettings:onUpdate(savegame)
    if self.propertyState == VehiclePropertyState.SHOP_CONFIG then 
        return
    end
    local spec = CpCourseGeneratorSettings.getSpec(self)  
    if not spec.finishedFirstUpdate then
        spec.workWidth:resetToLoadedValue()
    end
    spec.finishedFirstUpdate = true
end

function CpCourseGeneratorSettings:onReadStream(streamId, connection)
    local spec = CpCourseGeneratorSettings.getSpec(self)  
    for i, setting in ipairs(spec.settings) do 
        setting:readStream(streamId, connection)
    end
end

function CpCourseGeneratorSettings:onWriteStream(streamId, connection)
    local spec = CpCourseGeneratorSettings.getSpec(self)  
    for i, setting in ipairs(spec.settings) do 
        setting:writeStream(streamId, connection)
    end
end

function CpCourseGeneratorSettings:isRowsToSkipVisible()
    local spec = CpCourseGeneratorSettings.getSpec(self)  
    local rowPatternNumber = spec.centerMode:getValue()
    return rowPatternNumber == CourseGenerator.RowPattern.ALTERNATING
end

function CpCourseGeneratorSettings:isNumberOfCirclesVisible()
    local spec = CpCourseGeneratorSettings.getSpec(self)  
    local rowPatternNumber = spec.centerMode:getValue()
    return rowPatternNumber == CourseGenerator.RowPattern.RACETRACK
end

function CpCourseGeneratorSettings:isRowsPerLandVisible()
    local spec = CpCourseGeneratorSettings.getSpec(self)  
    local rowPatternNumber = spec.centerMode:getValue()
    return rowPatternNumber == CourseGenerator.RowPattern.LANDS
end

function CpCourseGeneratorSettings:isSpiralFromInsideVisible()
    local spec = CpCourseGeneratorSettings.getSpec(self)  
    local rowPatternNumber = spec.centerMode:getValue()
    return rowPatternNumber == CourseGenerator.RowPattern.SPIRAL
end

function CpCourseGeneratorSettings:isManualRowAngleVisible()
    local spec = CpCourseGeneratorSettings.getSpec(self)  
    return spec.autoRowAngle:getValue() == false
end

--- Makes sure the automatic work width gets recalculated after the variable work width was changed by the user.
function CpCourseGeneratorSettings.onVariableWorkWidthSectionChanged(object)
    --- Object could be an implement, so make sure we use the root vehicle.
    local self = object.rootVehicle
    if self:getIsSynchronized() then
        CpCourseGeneratorSettings.setAutomaticWorkWidthAndOffset(self)
    end
end
VariableWorkWidth.updateSections = Utils.appendedFunction(VariableWorkWidth.updateSections,CpCourseGeneratorSettings.onVariableWorkWidthSectionChanged)

function CpCourseGeneratorSettings:setAutomaticWorkWidthAndOffset()
    local spec = CpCourseGeneratorSettings.getSpec(self)  
    local width, offset, _, _ = WorkWidthUtil.getAutomaticWorkWidthAndOffset(self)
    spec.workWidth:refresh()
    spec.workWidth:setFloatValue(width, nil, true)
    self:getCpSettings().toolOffsetX:setFloatValue(offset, nil, true)
end

function CpCourseGeneratorSettings:setDefaultTurningRadius()
    local spec = CpCourseGeneratorSettings.getSpec(self)  
    spec.turningRadius:setFloatValue(AIUtil.getTurningRadius(self), nil, true)
end

--- Loads the generic settings setup from an xmlFile.
function CpCourseGeneratorSettings.loadSettingsSetup()
    local filePath = Utils.getFilename("config/CourseGeneratorSettingsSetup.xml", g_Courseplay.BASE_DIRECTORY)
    CpSettingsUtil.loadSettingsFromSetup(CpCourseGeneratorSettings,filePath)
    CpCourseGeneratorSettings.vineSettings = {}
    filePath = Utils.getFilename("config/VineCourseGeneratorSettingsSetup.xml", g_Courseplay.BASE_DIRECTORY)
    CpSettingsUtil.loadSettingsFromSetup(CpCourseGeneratorSettings.vineSettings,filePath)
end

function CpCourseGeneratorSettings.getSettingSetup()
    return CpCourseGeneratorSettings.settingsBySubTitle, 
        CpCourseGeneratorSettings.pageTitle
end

function CpCourseGeneratorSettings.getVineSettingSetup(vehicle)
    return CpCourseGeneratorSettings.vineSettings.settingsBySubTitle,
        CpCourseGeneratorSettings.vineSettings.pageTitle
end

function CpCourseGeneratorSettings:loadSettings(savegame)
    if savegame == nil or savegame.resetVehicles then return end
    local spec = CpCourseGeneratorSettings.getSpec(self)  
    --- Old save format
	savegame.xmlFile:iterate(savegame.key..CpCourseGeneratorSettings.KEY, function (ix, key)
		local name = savegame.xmlFile:getValue(key.."#name")
        local setting = spec[name] or spec.vineSettings[name]
        if setting then
            setting:loadFromXMLFile(savegame.xmlFile, key)
            CpUtil.debugVehicle(CpUtil.DBG_HUD,self,"Loaded setting: %s, value:%s, key: %s",setting:getName(),setting:getValue(),key)
        end
    end)

    --- Loads the normal course generator settings.
    CpSettingsUtil.loadFromXmlFile(spec, savegame.xmlFile, 
                        savegame.key .. CpCourseGeneratorSettings.KEY ..  CpCourseGeneratorSettings.SETTINGS_KEY, self)

    --- Loads the vine course generator settings.
    CpSettingsUtil.loadFromXmlFile(spec.vineSettings, savegame.xmlFile, 
                        savegame.key .. CpCourseGeneratorSettings.KEY .. CpCourseGeneratorSettings.VINE_SETTINGS_KEY, self)
end

function CpCourseGeneratorSettings:saveToXMLFile(xmlFile, baseKey, usedModNames)
    local spec = CpCourseGeneratorSettings.getSpec(self)  

    --- Saves the normal course generator settings.
    CpSettingsUtil.saveToXmlFile(spec.settings, xmlFile, 
    baseKey .. CpCourseGeneratorSettings.SETTINGS_KEY, self, nil)

    --- Saves the vine course generator settings.
    CpSettingsUtil.saveToXmlFile(spec.vineSettings.settings, xmlFile, 
    baseKey .. CpCourseGeneratorSettings.VINE_SETTINGS_KEY, self, nil)

end

--- Callback raised by a setting and executed as an vehicle event.
---@param callbackStr string event to be raised
---@param setting AIParameterSettingList setting that raised the callback.
function CpCourseGeneratorSettings:raiseCallback(callbackStr, setting, ...)
    SpecializationUtil.raiseEvent(self, callbackStr, setting, ...)
end

function CpCourseGeneratorSettings:raiseDirtyFlag(setting)
    CourseGeneratorSettingsEvent.sendEvent(self, setting)
end 

function CpCourseGeneratorSettings:validateSettings()
    local spec = CpCourseGeneratorSettings.getSpec(self)  
    for i,setting in ipairs(spec.settings) do 
        setting:refresh()
    end
    for i,setting in ipairs(spec.vineSettings.settings) do 
        setting:refresh()
    end
end

function CpCourseGeneratorSettings:onCpUnitChanged()
    local spec = CpCourseGeneratorSettings.getSpec(self)  
    for i,setting in ipairs(spec.settings) do 
        setting:validateTexts()
    end
    for i,setting in ipairs(spec.vineSettings.settings) do 
        setting:validateTexts()
    end
end

------------------------------------------------------------------------------------------------------------------------
--- Callbacks for the settings to manipulate the gui elements.
------------------------------------------------------------------------------------------------------------------------
function CpCourseGeneratorSettings:hasMoreThenOneVehicle()
    local spec = CpCourseGeneratorSettings.getSpec(self)  
    return spec.multiTools:getValue() > 1
end

function CpCourseGeneratorSettings:hasHeadlandsSelected()
    local spec = CpCourseGeneratorSettings.getSpec(self)  
    return spec.numberOfHeadlands:getValue() > 0
end

function CpCourseGeneratorSettings:isNarrowFieldEnabled()
    -- FieldworkCourseTwoSided does not work with multitools.
    return CpCourseGeneratorSettings.hasHeadlandsSelected(self) and
            not CpCourseGeneratorSettings.hasMoreThenOneVehicle(self)
end

function CpCourseGeneratorSettings:canStartOnRows()
    local spec = CpCourseGeneratorSettings.getSpec(self)  
    -- start on rows does not work for narrow field patterns
    return spec.numberOfHeadlands:getValue() > 0 and not spec.narrowField:getValue()
end

--- Only show the work width, if the bale finder can't be started.
function CpCourseGeneratorSettings:isWorkWidthSettingVisible()
    return not self:getCanStartCpBaleFinder()
end

--- Generates speed setting values up to the max possible speed.
function CpCourseGeneratorSettings:generateWorkWidthSettingValuesAndTexts(setting) 
    --- Disabled for now!!
    local workWidth = WorkWidthUtil.getAutomaticWorkWidthAndOffset(self)
    local maxWorkWidth = math.max(setting.data.max, workWidth + 5)
    local values, texts = {}, {}
    for i = setting.data.min, maxWorkWidth, setting.data.incremental do 
        table.insert(values, i)
        table.insert(texts, i)
    end
    return values, texts
end

---------------------------------------------
--- Console Commands
---------------------------------------------

function CpCourseGeneratorSettings.registerConsoleCommands()
    g_consoleCommands:registerConsoleCommand("cpSettingsPrintGenerator",
        "Prints the course generator settings or a given setting", 
        "consoleCommandPrintSetting", CpCourseGeneratorSettings)
end

--- Either prints all settings or a desired setting by the name or index in the setting table.
---@param name any
function CpCourseGeneratorSettings:consoleCommandPrintSetting(name)
    local vehicle = CpUtil.getCurrentVehicle()
    if not vehicle then 
        CpUtil.info("Not entered a valid vehicle!")
        return
    end
    local spec = CpCourseGeneratorSettings.getSpec(self) 
    if not spec then 
        CpUtil.infoVehicle(vehicle, "has no course generator settings!")
        return
    end
    if name == nil then 
        CpUtil.infoVehicle(vehicle,"%d Course generator settings printed", tostring(spec.settings))
        return
    end
    local num = tonumber(name)
    if num then 
        CpUtil.infoVehicle(vehicle, tostring(spec.settings[num]))
        return
    end
    CpUtil.infoVehicle(vehicle, tostring(spec[name]))
end
