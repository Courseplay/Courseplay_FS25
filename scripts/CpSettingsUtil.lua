CpSettingsUtil = {}

--[[
	All the settings configurations.
	They are divided by sub titles in the gui.
	
	All basic AIParameterSettingList can be initialized with values/texts or as an number sequence: [min:incremental:max]

	Callbacks are passed as an string to to the class:raiseCallback() function.
	If the class is a Specializations for example VehicleSettings, 
	then the callback will be called as an event and must be registered by another specialization. 

	Settings :
		- prefixText (string):  pre fix text used for translations
		- SettingSubTitle(?) :
			- prefix (bool): prefix used yes/no?, default = true
			- title (string): sub title text in the gui menu

			- isDisabled (string): function called from the parent container, to disable all setting under the subtitle.
			- isVisible (string): function called from the parent container, to change the visibility of all setting under the subtitle.

			- isExpertModeOnly(bool): are the setting visible in the expert version?, default = false

			- Setting(?)
				- classType (string): class name
				- name (string): name of the setting 
				- title (string): title text in the gui menu (optional)
				- tooltip (string): tooltip text in the gui menu (optional)
				- default(int) : default value to be set. (optional)
				- defaultBool(bool) : default value to be set. (optional)
				- textInput(bool) : is text input allowed ? (optional), every automatic generated number sequence is automatically allowed.
				- isUserSetting(bool): should the setting be saved in the game settings and not in the savegame dir.
				- isExpertModeOnly(bool): is the setting visible in the expert version?, default = false
				- isCopyValueDisabled(bool): is the setting value being copy by a copy function call?, default false

				- generateValuesFunction(string): dynamically adds value, when the setting is created.
				- min (float): min value
				- max (float): max value
				- incremental (float): increment (optional), default "1"
				- precision (float): optional rounding precision
				- text(string): string to format the setting value with in the gui element.
				- unit (int) : 1 == km/h, 2 == meters, 3 == ha (optional), 4 = percent (%), 5 = degrees (°)

				- vehicleConfiguration(string): vehicle configuration, that will be used for reset to default for example.
				- onChangeCallback(string): callback function raised on setting value changed. 

				- isDisabled (string): function called by the setting from the parent container, to disable the setting.
				- isVisible (string): function called by the setting from the parent container, to change the setting visibility.
				- setDefault (string): function called by the setting from the parent container, to set a default value, for example work width.

				- positionParameterType(string): Position type for the CpAIParameterPositionAngle/CpAIParameterPosition

				- Values : 
					- Value(?) :
						- name (string): Global name, should be unique for all settings in this xml file.
						- value (int): value
						- isDisabled(string): function called by the setting from the parent container, to disable this value.
				- Texts : 
					- Text(?) :
						- prefix (string): prefix used yes/no?, default = true
						- value (string): translation text		
]]--
--- All xml values used by the settings setup xml files.
function CpSettingsUtil.init()
    CpSettingsUtil.setupXmlSchema = XMLSchema.new("SettingsSetup")
    local schema = CpSettingsUtil.setupXmlSchema	
	-- valueTypeId, path, description, defaultValue, isRequired
	schema:register(XMLValueType.STRING, "Settings#title", "Settings prefix text", nil, true)
	schema:register(XMLValueType.STRING, "Settings#prefixText", "Settings prefix text", nil, true)
	
	local key = "Settings.SettingSubTitle(?)"
	schema:register(XMLValueType.STRING, key .."#title", "Setting sub title", nil)
	schema:register(XMLValueType.BOOL, key .."#prefix", "Setting sub title is a prefix", true)
	
	schema:register(XMLValueType.STRING, key.."#isDisabled", "Callback function, if the settings is disabled.") -- optional
	schema:register(XMLValueType.STRING, key.."#isVisible", "Callback function, if the settings is visible.") -- optional
	schema:register(XMLValueType.BOOL, key.."#isExpertModeOnly", "Is enabled in simple mode?", false) -- optional

	key = "Settings.SettingSubTitle(?).Setting(?)"
    schema:register(XMLValueType.STRING, key.."#name", "Setting name", nil, true)
    schema:register(XMLValueType.STRING, key.."#classType", "Setting class type", nil, true)
	schema:register(XMLValueType.STRING, key.."#title", "Setting tile") -- optional
    schema:register(XMLValueType.STRING, key.."#tooltip", "Setting tooltip") -- optional
	schema:register(XMLValueType.INT, key.."#default", "Setting default value") -- optional
	schema:register(XMLValueType.BOOL, key.."#defaultBool", "Setting default bool value") -- optional
	schema:register(XMLValueType.BOOL, key .. "#textInput", "Setting input text allowed.") --optional
	schema:register(XMLValueType.BOOL, key .. "#isUserSetting", "Setting will be saved in the gameSettings file.", false) --optional
	schema:register(XMLValueType.BOOL, key.."#isExpertModeOnly", "Is enabled in simple mode?", false) -- optional
	schema:register(XMLValueType.BOOL, key.."#isCopyValueDisabled", "Is value copied by copy()?", false) -- optional

	schema:register(XMLValueType.STRING, key .. "#generateValuesFunction", "Function to generate values.")
	schema:register(XMLValueType.FLOAT, key.."#min", "Setting min value")
	schema:register(XMLValueType.FLOAT, key.."#max", "Setting max value")
	schema:register(XMLValueType.FLOAT, key.."#incremental", "Setting incremental", 1) -- optional
	schema:register(XMLValueType.FLOAT, key.."#precision", "Setting precision", 2) -- optional
	schema:register(XMLValueType.STRING, key.."#text", "Setting text") -- optional
	schema:register(XMLValueType.INT, key .. "#unit", "Setting value unit (km/h, m ...)") --optional

	schema:register(XMLValueType.STRING, key.."#vehicleConfiguration", "vehicleConfiguration that will be used to reset the setting.") --optional
	--- callbacks:
	schema:register(XMLValueType.STRING, key.."#onChangeCallback", "Setting callback on change") -- optional

	schema:register(XMLValueType.STRING, key.."#isDisabled", "Callback function, if the settings is disabled.") -- optional
	schema:register(XMLValueType.STRING, key.."#isVisible", "Callback function, if the settings is visible.") -- optional
	schema:register(XMLValueType.STRING, key.."#setDefault", "Callback function, to set the default value.") -- optional

	schema:register(XMLValueType.STRING, key .. "#positionParameterType", "Position parameter type for CpAIParameterPositionAngle/CpAIParameterPosition") -- optional

	key = "Settings.SettingSubTitle(?).Setting(?).Values.Value(?)"
	schema:register(XMLValueType.INT, key, "Setting value", nil)
	schema:register(XMLValueType.STRING, key.."#name", "Setting value name", nil)
	schema:register(XMLValueType.STRING, key.."#isDisabled", "Setting value disabled", nil)

	key = "Settings.SettingSubTitle(?).Setting(?).Texts.Text(?)"
	schema:register(XMLValueType.STRING, key, "Setting value text", nil)
	schema:register(XMLValueType.BOOL, key.."#prefix", "Setting value text is a prefix", true)
end
CpSettingsUtil.init()

--- Generates a setting from the string class type.
function CpSettingsUtil.getSettingFromParameters(parameters, ...)
	local valid, classObject = CpUtil.try(
		CpUtil.getClassObject,
		parameters.classType
	)
	if not valid then 
		CpUtil.info("Setting class %s not found!!", parameters.classType)
		return
	end
	if classObject.new then 
		return classObject.new(parameters, ...)
	else 
		return classObject(parameters, ...)
	end
end

--- Loads the settings setup config file.
---@param class table class to save the data
---@param filePath string
function CpSettingsUtil.loadSettingsFromSetup(class, filePath)
	local xmlFile = XMLFile.load("settingSetupXml", filePath, CpSettingsUtil.setupXmlSchema)
	class.settings = {}
	setmetatable(class.settings, { __tostring = function(self)
		--- Adds tostring function to print all settings
		for i, s in ipairs(self) do 
			CpUtil.info("%2d: %s", i, tostring(s))
		end
		return tostring(#self)
	end})
	class.settingsBySubTitle = {}
	local uniqueID = 0
	local setupKey = xmlFile:getValue("Settings#prefixText")
	local pageTitle = xmlFile:getValue("Settings#title")
	if pageTitle then
		class.pageTitle =  xmlFile:getValue("Settings#title")
	else 
		class.pageTitle = setupKey .. "title"
	end
	xmlFile:iterate("Settings.SettingSubTitle", function (i, masterKey)
		local subTitle = xmlFile:getValue(masterKey.."#title", "...")
		--- This flag can by used to simplify the translation text. 
		local pre = xmlFile:getValue(masterKey.."#prefix", true)	
		if pre then 
			subTitle = setupKey.."subTitle_"..subTitle
		else 
			subTitle = subTitle
		end

		local isDisabledFunc = xmlFile:getValue(masterKey.."#isDisabled")
		local isVisibleFunc = xmlFile:getValue(masterKey.."#isVisible")
		local isExpertModeOnly = xmlFile:getValue(masterKey.."#isExpertModeOnly", false)

		local subTitleSettings = {
			title = subTitle,
			elements = {},
			isDisabledFunc = isDisabledFunc,
			isVisibleFunc = isVisibleFunc,
			isExpertModeOnly = isExpertModeOnly,
			class = class
		}
		xmlFile:iterate(masterKey..".Setting", function (i, baseKey)
			local settingParameters = {}
			settingParameters.classType = xmlFile:getValue(baseKey.."#classType")
			settingParameters.name = xmlFile:getValue(baseKey.."#name")
			settingParameters.setupName = setupKey..settingParameters.name
			local title = xmlFile:getValue(baseKey.."#title")
			if title then
				settingParameters.title = title
			else 
				settingParameters.title = setupKey..settingParameters.name.."_title"
			end
			local tooltip = xmlFile:getValue(baseKey.."#tooltip")
			if tooltip then
				settingParameters.tooltip = tooltip
			else 
				settingParameters.tooltip = setupKey..settingParameters.name.."_tooltip"
			end
			settingParameters.default = xmlFile:getValue(baseKey.."#default")
			settingParameters.defaultBool = xmlFile:getValue(baseKey.."#defaultBool")
			settingParameters.textInputAllowed = xmlFile:getValue(baseKey.."#textInput", false)
			settingParameters.isUserSetting = xmlFile:getValue(baseKey.."#isUserSetting", false)
			settingParameters.isExpertModeOnly = xmlFile:getValue(baseKey.."#isExpertModeOnly", false)
			settingParameters.isCopyValueDisabled = xmlFile:getValue(baseKey.."#isCopyValueDisabled", false)

			settingParameters.generateValuesFunction = xmlFile:getValue(baseKey.."#generateValuesFunction")
			settingParameters.min = xmlFile:getValue(baseKey.."#min")
			settingParameters.max = xmlFile:getValue(baseKey.."#max")
			settingParameters.incremental = MathUtil.round(xmlFile:getValue(baseKey.."#incremental"), 3)
			settingParameters.precision = xmlFile:getValue(baseKey.."#precision", 2)
			settingParameters.textStr = xmlFile:getValue(baseKey.."#text")
			settingParameters.unit = xmlFile:getValue(baseKey.."#unit")

			settingParameters.vehicleConfiguration = xmlFile:getValue(baseKey.."#vehicleConfiguration")

			settingParameters.callbacks = {}
			settingParameters.callbacks.onChangeCallbackStr = xmlFile:getValue(baseKey.."#onChangeCallback")

			settingParameters.isDisabledFunc = xmlFile:getValue(baseKey.."#isDisabled")
			settingParameters.isVisibleFunc = xmlFile:getValue(baseKey.."#isVisible")
			settingParameters.setDefaultFunc = xmlFile:getValue(baseKey.."#setDefault")

			settingParameters.positionParameterType = xmlFile:getValue(baseKey .. "#positionParameterType")

			settingParameters.values = {}
			settingParameters.disabledValuesFuncs = {}
			xmlFile:iterate(baseKey..".Values.Value", function (i, key)
				local name = xmlFile:getValue(key.."#name")
				local value = xmlFile:getValue(key)
				table.insert(settingParameters.values, value)
				if name ~= nil and name ~= "" then
					class[name] = value
				end
				local isDisabled = xmlFile:getValue(key.."#isDisabled")
				settingParameters.disabledValuesFuncs[value] = isDisabled
			end)

			settingParameters.texts = {}
			xmlFile:iterate(baseKey..".Texts.Text", function (i, key)
				--- This flag can by used to simplify the translation text. 
				local prefix = xmlFile:getValue(key.."#prefix", true)
				local text = xmlFile:getValue(key)
				if prefix then
					text = g_i18n:getText(setupKey..settingParameters.name.."_"..text)
					table.insert(settingParameters.texts, text)
				else 
					table.insert(settingParameters.texts, g_i18n:getText(text))
				end
			end)

			settingParameters.uniqueID = uniqueID

			local setting = CpSettingsUtil.getSettingFromParameters(settingParameters, nil, class)
			class[settingParameters.name] = setting
			table.insert(class.settings, setting)
			table.insert(subTitleSettings.elements, setting)

			uniqueID = uniqueID + 1
		end)
		table.insert(class.settingsBySubTitle, subTitleSettings)
	end)
	xmlFile:delete()
end

--- Clones a settings table.
---@param class table 
---@param settings table
function CpSettingsUtil.cloneSettingsTable(class, settings, ...)
	local mt = getmetatable(settings)
	class.settings = {}
	setmetatable(class.settings, mt)
	for _, setting in ipairs(settings) do 
		local settingClone = setting:clone(...)
		table.insert(class.settings, settingClone)
		class[settingClone:getName()] = settingClone
	end
end

--- Copies settings values from a settings tables to another.
function CpSettingsUtil.copySettingsValues(settingsTable, settingsTableToCopy)
    for i, p in ipairs(settingsTable.settings) do 
        p:copy(settingsTableToCopy.settings[i])
    end
end

function CpSettingsUtil.generateAndBindGuiElements(settingsData, parentGuiElement, 
	genericMultiSettingElement, genericBooleanSettingElement, settings)
	local alternate = false
	for _, raw_setting in ipairs(settingsData.elements) do 
		local clonedSettingElement
		if raw_setting:is_a(AIParameterBooleanSetting) then
			clonedSettingElement = genericBooleanSettingElement:clone(parentGuiElement)
		else
			clonedSettingElement = genericMultiSettingElement:clone(parentGuiElement)
		end
		if alternate then 
			clonedSettingElement:setImageColor(1, unpack(GuiUtils.getColorArray(g_gui.presets["fs25_colorGreyDark"])))
		else
			clonedSettingElement:setImageColor(1, unpack(GuiUtils.getColorArray(g_gui.presets["fs25_colorGreyDark_50"])))
		end
		alternate = not alternate
		local setting = settings[raw_setting:getName()]
		if setting then
			--- TODO_25
			clonedSettingElement:getDescendantByName("setting"):setDataSource(setting)
			clonedSettingElement.aiParameter = setting
			-- clonedSettingElement:applyScreenAlignment()
			FocusManager:loadElementFromCustomValues(clonedSettingElement:getDescendantByName("setting"))
		end
	end
	parentGuiElement:invalidateLayout()
end

function CpSettingsUtil.generateAndBindGuiElementsToSettings(settingsBySubTitle, parentGuiElement, 
	genericMultiSettingElement, genericBooleanSettingElement, genericSubTitleElement, settings)
	for _, data in ipairs(settingsBySubTitle) do 
		local clonedSubTitleElement = genericSubTitleElement:clone(parentGuiElement)
		clonedSubTitleElement:setText(g_i18n:getText(data.title))
		clonedSubTitleElement.subTitleConfigData = data
		FocusManager:loadElementFromCustomValues(clonedSubTitleElement)
		CpSettingsUtil.generateAndBindGuiElements(data,
			parentGuiElement, genericMultiSettingElement, 
			genericBooleanSettingElement, settings)
	end
end

function CpSettingsUtil.updateGuiElementsBoundToSettings(layout, vehicle)
	local subTitleVisible = true
	for i, element in pairs(layout.elements) do 
		---@type AIParameterSetting
		local setting = element.aiParameter
		if setting then 
			element:getDescendantByName("setting"):setDisabled(setting:getIsDisabled())
			element:setVisible(subTitleVisible and setting:getIsVisible())
			element:getDescendantByName("setting"):updateTitle()
		else
			if element.subTitleConfigData then
				local isVisible = true
				--- Is subtitle 
				local isDisabledFunc =  element.subTitleConfigData.isDisabledFunc
				local isVisibleFunc =  element.subTitleConfigData.isVisibleFunc
				local isVisibleExpertMode =  element.subTitleConfigData.isExpertModeOnly
				if isVisibleExpertMode and not g_Courseplay.globalSettings.expertModeActive:getValue() then 
					isVisible = false
				end
				local class =  element.subTitleConfigData.class
				if vehicle then 
					if class[isVisibleFunc] then 
						isVisible = class[isVisibleFunc](vehicle)
					end
					if class[isDisabledFunc] then 
						element:getDescendantByName("setting"):setDisabled(class[isDisabledFunc](vehicle))
					end
				else 
					if class[isVisibleFunc] then 
						isVisible = class[isVisibleFunc](class)
					end
					if class[isDisabledFunc] then 
						element:getDescendantByName("setting"):setDisabled(class[isDisabledFunc](vehicle))
					end
				end
				subTitleVisible = isVisible
				element:setVisible(isVisible)
			end
		end
	end
	layout:invalidateLayout()
end

--- Clones for each setting gui elements and applies basic setups.
---@param settings table
---@param parentGuiElement GuiElement
---@param genericSettingElement GuiElement
function CpSettingsUtil.generateGuiElementsFromSettingsTableAlternating(settings, parentGuiElement, genericSettingElementTitle, genericSettingElement)
	for _, setting in ipairs(settings) do 
		local titleElement = genericSettingElementTitle:clone(parentGuiElement)
		FocusManager:loadElementFromCustomValues(titleElement)
		CpUtil.debugFormat(CpDebug.DBG_HUD, "Bound setting %s", setting:getName())
		local clonedSettingElement = genericSettingElement:clone(parentGuiElement)
		clonedSettingElement.aiParameter = setting
		clonedSettingElement:setDataSource(setting)
		clonedSettingElement:setLabelElement(titleElement)
		FocusManager:loadElementFromCustomValues(clonedSettingElement)
	end
end

--- Generates Gui button in the ai job menu from settings.
---@param settingsBySubTitle table
---@param class table
function CpSettingsUtil.generateAiJobGuiElementsFromSettingsTable(settingsBySubTitle, class, settings)
	for _, data in ipairs(settingsBySubTitle) do 
		local parameterGroup = CpAIParameterGroup(settings, data)
		for _, setting in ipairs(data.elements) do 
			local s = settings[setting:getName()]
			parameterGroup:addParameter(s)
		end
		table.insert(class.groupedParameters, parameterGroup)
	end
end

--- Raises an event for all settings.
---@param settings table
---@param eventName string
function CpSettingsUtil.raiseEventForSettings(settings, eventName, ...)
	for _, setting in ipairs(settings) do 
		if setting[eventName] then 
			setting[eventName](setting, ...)
		end
	end
end

function CpSettingsUtil.registerXmlSchema(schema, key)
	schema:register(XMLValueType.INT, key.."#value", "Old setting save format.")
    schema:register(XMLValueType.STRING, key.."#currentValue", "Setting value")
    schema:register(XMLValueType.STRING, key.."#name", "Setting name")
end

--- Loads setting values from an xml file.
---@param dataTable table
---@param xmlFile table
---@param baseKey string
---@param vehicle table optional for debug
function CpSettingsUtil.loadFromXmlFile(dataTable, xmlFile, baseKey, vehicle)
	xmlFile:iterate(baseKey, function (ix, key)
		local name = xmlFile:getValue(key.."#name")
		local setting = dataTable[name]
		if setting then
			setting:loadFromXMLFile(xmlFile, key)
			if vehicle then
				CpUtil.debugVehicle(CpUtil.DBG_HUD, vehicle, "Loaded setting: %s, value:%s, key: %s", 
									setting:getName(), setting:getValue(), key)
			else 
				CpUtil.debugFormat(CpUtil.DBG_HUD, "Loaded setting: %s, value:%s, key: %s", 
									setting:getName(), setting:getValue(), key)
			end
		end
		dataTable.wasLoaded = true
	end)
end

--- Saves setting values to an xml file.
---@param settingsTable table
---@param xmlFile table
---@param baseKey string
---@param vehicle table
---@param lambda function optional to disable the saving of specific settings.
function CpSettingsUtil.saveToXmlFile(settingsTable, xmlFile, baseKey, vehicle, lambda)
	local ix = 0
	for i, setting in ipairs(settingsTable) do 
		if lambda == nil or lambda(setting) then
			local key = string.format("%s(%d)", baseKey, ix)
			setting:saveToXMLFile(xmlFile, key)
			xmlFile:setValue(key.."#name", setting:getName())
			if vehicle then
				CpUtil.debugVehicle(CpUtil.DBG_HUD, vehicle, "Saved setting: %s, value:%s, key: %s", 
									setting:getName(), setting:getValue(), key)
			else 
				CpUtil.debugFormat(CpUtil.DBG_HUD, "Saved setting: %s, value:%s, key: %s", 
									setting:getName(), setting:getValue(), key)
			end		
			ix = ix + 1
		end
    end
end