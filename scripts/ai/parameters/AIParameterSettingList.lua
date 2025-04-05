--- Selection list with values and texts.
---@class AIParameterSettingList : AIParameterSetting
AIParameterSettingList = CpObject(AIParameterSetting)

function AIParameterSettingList:init(data, vehicle, class)
	AIParameterSetting.init(self)
	if data == nil then 
		CpUtil.error("Data is nil for AIParameterSettingList!")
		return
	end
	self:initFromData(data, vehicle, class)

	self.guiParameterType = AIParameterType.SELECTOR --- For the giants gui element.
	
	if next(data.values) ~=nil then
		--- The setting has values defined in the data, so we copy these here.
		--- This saves the unmodified values in the data table.
		self.values = table.clone(data.values)
		self.texts = table.clone(data.texts)
	elseif data.min ~= nil and data.max ~=nil then
		--- The setting has a min and max value,
		--- so we generate a series of float values and texts here.
		self.data.values = {}
		self.data.texts = {}
		AIParameterSettingList.generateValues(self, self.data.values, self.data.texts,
			data.min, data.max, data.incremental, data.unit, data.precision)
		--- Same as above, make sure the values are copied.
		self.values = table.clone(self.data.values)
		if self.data.texts ~= nil then
			self.texts = table.clone(self.data.texts)
		end
		data.textInputAllowed = true
	elseif data.generateValuesFunction then
		--- A generation function by the parent class is used
		--- to enrich/create the setting values/texts.
		self.data.values, self.data.texts = self:getCallback(data.generateValuesFunction)
		self.values = table.clone(self.data.values)
		self.texts = table.clone(self.data.texts)
		self:validateTexts()
	end
	--- Text input is only allowed, when the settings values are numeric.
	self.textInputAllowed = data.textInputAllowed 

	-- index of the current value/text
	self.current =  1
	-- index of the previous value/text
	self.previous = 1

	if self.texts == nil or next(self.texts) == nil then
		--- Fallback text generation based on the numeric values and a optional given unit.
		self.data.texts = {}
		AIParameterSettingList.enrichTexts(self, self.data.texts, data.unit)
		self.texts = table.clone(self.data.texts)
	end
	--- Lastly apply the default values here.
	if data.default ~=nil then
		AIParameterSettingList.setFloatValue(self, data.default, nil, true)
		self:debug("set to default %s", data.default)
	end
	if data.defaultBool ~= nil then
		AIParameterSettingList.setValue(self, data.defaultBool, true)
		self:debug("set to default %s", tostring(data.defaultBool))
	end

	self.callbacks = data.callbacks
	self.disabledValuesFuncs = data.disabledValuesFuncs

	self.guiElementId = data.uniqueID

	self.guiElement = nil
	self.isLoading = false
	self.setupDone = true
	self.isSynchronized = false

end

function AIParameterSettingList.getSpeedText(value, precision)
	return string.format("%.1f %s", g_i18n:getSpeed(value), g_i18n:getSpeedMeasuringUnit())
end

function AIParameterSettingList.getDistanceText(value, precision)
	precision = precision or 1
	if g_Courseplay.globalSettings and g_Courseplay.globalSettings.distanceUnit:getValue() == g_Courseplay.globalSettings.IMPERIAL_UNIT  then 
		return string.format("%.1f %s", value*AIParameterSettingList.FOOT_FACTOR, g_i18n:getText("CP_unit_foot"))
	end
	return string.format("%.".. tostring(precision) .. "f %s", value, g_i18n:getText("CP_unit_meter"))
end

function AIParameterSettingList.getAreaText(value, precision)
	return g_i18n:formatArea(value, 1, true)
end

AIParameterSettingList.UNITS_TEXTS = {
	AIParameterSettingList.getSpeedText, --- km/h
	AIParameterSettingList.getDistanceText, --- m
	AIParameterSettingList.getAreaText, --- ha/arcs
	function (value, precision) return string.format("%d", value) .. "%" end,			--- percent
	function (value, precision) return string.format("%d", value) .. "°" end			--- degrees
}

AIParameterSettingList.UNITS_CONVERSION = {
	function (value) return g_i18n.useMiles and value/AIParameterSettingList.MILES_FACTOR or value end,
	function (value) return g_Courseplay.globalSettings and g_Courseplay.globalSettings.distanceUnit:getValue() == g_Courseplay.globalSettings.IMPERIAL_UNIT and value/AIParameterSettingList.FOOT_FACTOR or value end,
	function (value) return g_i18n.useAcre and value/AIParameterSettingList.ACRE_FACTOR or value end
}

AIParameterSettingList.MILES_FACTOR = 0.62137
AIParameterSettingList.FOOT_FACTOR = 3.28
AIParameterSettingList.ACRE_FACTOR = 2.4711
AIParameterSettingList.INPUT_VALUE_THRESHOLD = 2
--- Generates numeric values and texts from min to max with incremental of inc or 1.
---@param values table
---@param texts table
---@param min number
---@param max number
---@param inc number
---@param unit number
function AIParameterSettingList:generateValues(values, texts, min, max, inc, unit, precision)
	inc = inc or 1
	precision = precision or 2
	for i=min, max, inc do 
		table.insert(values, i)
		local value = MathUtil.round(i, precision)
		local text = unit and AIParameterSettingList.UNITS_TEXTS[unit] and AIParameterSettingList.UNITS_TEXTS[unit](value, precision - 1) or tostring(value)
		table.insert(texts, text)
	end
end

--- Enriches texts with values of values, if they are not explicit declared. 
function AIParameterSettingList:enrichTexts(texts, unit)
	for i, value in ipairs(self.values) do 
		local text = tostring(value)
		if unit then 
			text = AIParameterSettingList.UNITS_TEXTS[unit](value)
		end
		texts[i] = text
	end
end


-- Is the current value same as the param?
function AIParameterSettingList:is(value)
	return self:getValue() == value
end

function AIParameterSettingList:isAlmostEqualTo(other)
	return self:getValue() == other:getValue()
end

-- Get the current text key (for the logs, for example)
function AIParameterSettingList:__tostring()
	return string.format("AIParameterSettingList(name=%s, value=%s, text=%s)", self.name, tostring(self:getValue()), self:getString())
end

-- private function to set to the value at ix
function AIParameterSettingList:setToIx(ix)
	if ix ~= self.current then
		self.previous = self.current
		self.current = ix
		self:onChange()
		self:validateCurrentValue()
	end
end

function AIParameterSettingList:checkAndSetValidValue(new)
	if new > #self.values then
		return 1
	elseif new < 1 then
		return #self.values
	else
		return new
	end
end

function AIParameterSettingList:onChange()
	if self.setupDone and not self.isLoading then
		self:raiseCallback(self.callbacks.onChangeCallbackStr)
		--- The client user settings are automatically saved on change.
		if g_server == nil and self:getIsUserSetting() and self.isSynchronized then 
			self:raiseCallback("onCpUserSettingChanged")
		end
	end
end

function AIParameterSettingList:isValueDisabled(value)
	local disabledFunc = self.disabledValuesFuncs and self.disabledValuesFuncs[value]
	if disabledFunc ~= nil and self:hasCallback(disabledFunc) then 
		if self:getCallback(disabledFunc) then 
			self:debug("value %s is disabled", tostring(value))
			return true
		end 
	end
--	self:debug("value %s is valid", tostring(value))
end

--- Excludes deactivated values from the current values and texts tables.
---@param includeDisabledValues boolean|nil
function AIParameterSettingList:refresh(includeDisabledValues)
	if self.data.generateValuesFunction then 
		local lastValue = self.values[self.current]
		local newValue
		self.values, self.texts, newValue = self:getCallback(self.data.generateValuesFunction, lastValue)
		if newValue ~= nil then 
			self:setValue(newValue, true)
		else
			self:setValue(lastValue, true)
		end
		self:debug("Refreshed from %s to %s", tostring(lastValue), tostring(self.values[self.current]))
		self:validateTexts()
		return
	end
	self.values = {}
	self.texts = {}
	for ix, v in ipairs(self.data.values) do 
		if includeDisabledValues or not self:isValueDisabled(v) then
			table.insert(self.values, v)
			table.insert(self.texts, self.data.texts[ix])
		end	
	end
	self:validateCurrentValue()
	self:validateTexts()
end

--- Gets the texts for the given values.
---@param values table
---@return table
function AIParameterSettingList:getTextsForValues(values)
	local texts = {}
	for _, v in ipairs(values) do 
		local ix = self:getClosestIx(v)
		table.insert(texts, self.data.texts[ix])
	end
	return texts
end

---@return number
function AIParameterSettingList:getNumberOfElements()
	return #self.values
end

---@param index number
---@return any|nil
function AIParameterSettingList:getValueByIndex(index)
	return self.values[index]
end

---@param index number
---@return string|nil
function AIParameterSettingList:getTextByIndex(index)
	return self.texts[index]
end

function AIParameterSettingList:validateCurrentValue()
	local new = self:checkAndSetValidValue(self.current)
	if new ~= self.current then
		self:debug("validate setting to %s from %s", self.values[new], tostring(self:getString()))
		self:setToIx(new)
	end
end

--- Refresh the texts, if it depends on a changeable measurement unit.
--- For all units that are not an SI unit ...
function AIParameterSettingList:validateTexts()
	local unit = self.data.unit
	local precision = self.data.precision or 2
	if unit then 
		local unitStrFunc = AIParameterSettingList.UNITS_TEXTS[unit]
		local fixedTexts = {}
		for ix, value in ipairs(self.values) do 
			local value = MathUtil.round(value, precision)
			local text = unitStrFunc(value, precision - 1)
			fixedTexts[ix] = text
		end
		self.texts = fixedTexts
	end
end

function AIParameterSettingList:saveToXMLFile(xmlFile, key, usedModNames)
	xmlFile:setString(key .. "#currentValue", tostring(self.values[self.current]))
end

--- Old load function.
function AIParameterSettingList:loadFromXMLFileLegacy(xmlFile, key)
	self:setToIx(xmlFile:getInt(key .. "#value", self.current))
end

function AIParameterSettingList:loadFromXMLFile(xmlFile, key)
	--- We need this flag, so we now if a value change was during the loading.
	self.isLoading = true
	local rawValue = xmlFile:getString(key .. "#currentValue")
	local value = rawValue and tonumber(rawValue) 
	if value then 
		self:debug("loaded value: %.2f", value)
		self.loadedValue = value
		--- Applies a small epsilon, as otherwise floating point problems might happen.
		self:setFloatValue(value, 0.001, true)
	else 
		self:loadFromXMLFileLegacy(xmlFile, key)
	end
	self.isLoading = false
end

function AIParameterSettingList:readStreamInternal(streamId, connection)
	local setupIx = streamReadInt32(streamId)
	self.loadedValue = self.data.values[setupIx]
	self:setToIx(self:getClosestIxFromSetup(setupIx))
	self:debug("set to %s(ix: %d) from stream.", tostring(self:getString()), setupIx)
end

function AIParameterSettingList:readStream(streamId, connection)
	if not self:getIsUserSetting() then
		self:readStreamInternal(streamId, connection)
	else 
		if streamReadBool(streamId) then
			self:debug("Trying to read user setting.") 
			self:readStreamInternal(streamId, connection)
		else 
			self:debug("is user setting, skip stream.")
		end
	end
	self.isSynchronized = true
end

function AIParameterSettingList:writeStreamInternal(streamId, connection)
	streamWriteInt32(streamId, self:getClosestSetupIx())
	self:debug("send %s to stream.", tostring(self:getString()))
end

function AIParameterSettingList:writeStream(streamId, connection)
	if not self:getIsUserSetting() then
		self:writeStreamInternal(streamId, connection)
	else 
		local userSettingValue = self:getCallback("getCpSavedUserSettingValue", connection)
		if userSettingValue ~= nil then 
			streamWriteBool(streamId, true)
			streamWriteInt32(streamId, userSettingValue)
			self:debug("send user setting value %s to stream.", tostring(self:getString()))
		else
			streamWriteBool(streamId, false)
			self:debug("is user setting, skip stream.")
		end
	end
end

--- Gets the closest ix relative to the setup ix.
---@param ix number
---@return number
function AIParameterSettingList:getClosestIxFromSetup(ix)
	local value = self.data.values[ix]
	if value == nil then 
		self:error("Setting value bugged, ix: %s", tostring(ix))
		return 1
	end
	-- find the value requested
	local closestIx = 1
	local closestDifference = math.huge
	for i = 1, #self.values do
		local v = self.values[i]
		local d = math.abs(v-value)
		if d < closestDifference then
			closestIx = i
			closestDifference = d
		end
	end
	return closestIx
end

--- Gets the closest setup ix relative to the current ix.
---@return number
function AIParameterSettingList:getClosestSetupIx()
	local value = self.values[self.current]
	if value == nil then 
		CpUtil.error("SettingList: %s value is nil for %s!", self.name, self.current)
		return 1
	end
	-- find the value requested
	local closestIx = 1
	local closestDifference = math.huge
	for i = 1, #self.data.values do
		local v = self.data.values[i]
		local d = math.abs(v-value)
		if d < closestDifference then
			closestIx = i
			closestDifference = d
		end
	end
	return closestIx
end

--- Sets the value.
---@param self AIParameterSettingList
---@param value number
---@param comparisonFunc function
---@return boolean value is not valid and could not be set.
local function setValueInternal(self, value, comparisonFunc)
	local new
	-- find the value requested
	for i = 1, #self.values do
		if comparisonFunc(self.values[i], value) then
			new = self:checkAndSetValidValue(i)
			self:setToIx(new)
			return false
		end
	end
	return value ~= new
end

--- Sets a float value relative to the incremental.
---@param value number
---@param epsilon number|nil optional
---@return boolean value is not valid and could not be set.
function AIParameterSettingList:setFloatValue(value, epsilon, noEventSend)
	local failed = setValueInternal(self, value, function(a, b)
		local epsilon = epsilon or self.data.incremental or 0.1
		if a == nil or b == nil then return false end
		return a > b - epsilon / 2 and a <= b + epsilon / 2 end)
	if not failed and not noEventSend then
		self:raiseDirtyFlag()
	end
	return failed
end

--- Gets the closest value ix and absolute difference, relative to the value searched for.
---@param value number
---@return number closest ix
---@return number difference
function AIParameterSettingList:getClosestIx(value)
	-- find the value requested
	local closestIx = 0
	local closestDifference = math.huge
	for i = 1, #self.values do
		local v = self.values[i]
		local d = math.abs(v-value)
		if d < closestDifference then
			closestIx = i
			closestDifference = d
		end
	end
	return closestIx, closestDifference
end

--- Sets a value.
---@param value number
---@param noEventSend boolean|nil
---@return boolean value is not valid and could not be set.
function AIParameterSettingList:setValue(value, noEventSend)
	local failed = setValueInternal(self, value, function(a, b)  return a == b end)
	if not failed and not noEventSend then 
		self:raiseDirtyFlag()
	end
	return failed
end

function AIParameterSettingList:setDefault(noEventSend)
	local current = self.current
	--- If the setting has a function to set the default value, then call it.
	if self:hasCallback(self.data.setDefaultFunc) then 
		self:getCallback(self.data.setDefaultFunc, noEventSend)
		self:debug("set to default by extern function.")
		return
	end
	--- If the setting is linked to a vehicle configuration and a implement value was found, then reset it to this value.
	local configName =  self.data.vehicleConfiguration
	if configName then 
		if self.vehicle then 
			for i, object in ipairs(self.vehicle:getChildVehicles()) do 
				local value = g_vehicleConfigurations:get(object, configName)
				if value then 
					if tonumber(value) then 
						self:setFloatValue(value, noEventSend)
					else
						self:setValue(value, noEventSend)
					end
					self:debug("set to default: %s from vehicle configuration: (%s|%s)", value, CpUtil.getName(object), configName)
					return
				end
			end
		end
	end
	--- If default values were setup use these.
	if self.data.default ~=nil then
		AIParameterSettingList.setFloatValue(self, self.data.default, noEventSend)
		self:debug("set to default %s", self.data.default)
		return
	end
	if self.data.defaultBool ~= nil then
		AIParameterSettingList.setValue(self, self.data.defaultBool, noEventSend)
		self:debug("set to default %s", tostring(self.data.defaultBool))
		return
	end
	self:setToIx(1)
	if (noEventSend == nil or noEventSend==false) and current ~= self.current then
		self:raiseDirtyFlag()
	end
end

--- Resets the setting value back to the loaded value, if it's possible.
function AIParameterSettingList:resetToLoadedValue()
	if self.loadedValue ~= nil then 
		self:setFloatValue(self.loadedValue)
		self:debug("Resetting value to loaded value: %s", tostring(self:getValue()))
	end
end

--- Resets the disabled values back to the orignal value table
function AIParameterSettingList:resetValuesBackToSetupValues()
	self.values = table.clone(self.data.values)
	self.texts = table.clone(self.data.texts)
end

--- Gets a specific value.
function AIParameterSettingList:getValue()
	--- In the simple mode, the default value will be returned, but only in singleplayer.
	if g_currentMission and not g_currentMission.missionDynamicInfo.isMultiplayer and self:getIsExpertModeSetting()
		and not g_Courseplay.globalSettings.expertModeActive:getValue() then 
		
		if self.data.default then 
			return self.data.default
		end
		if self.data.defaultBool then 
			return self.data.defaultBool
		end
		return self.values[1]
	end
	return self.values[self.current]
end

function AIParameterSettingList:getString()
	return self.texts[self.current] or ""
end

--- Set the next value
function AIParameterSettingList:setNextItem()
	local new = self:checkAndSetValidValue(self.current + 1)
	self:setToIx(new)
	if new ~= self.previous then
		self:raiseDirtyFlag()
	end
end

--- Set the previous value
function AIParameterSettingList:setPreviousItem()
	local new = self:checkAndSetValidValue(self.current - 1)
	self:setToIx(new)
	if new ~= self.previous then
		self:raiseDirtyFlag()
	end
end

function AIParameterSettingList:clone(...)
	return AIParameterSettingList(self.data, ...)
end

--- Copy the value to another setting.
function AIParameterSettingList:copy(setting)
	if self.data.incremental and self.data.incremental ~= 1 then 
		self:setFloatValue(setting.values[setting.current], nil, true)
	else 
		self:setValue(setting.values[setting.current], true)
	end
end

function AIParameterSettingList:onClickCenter(guiElement)
	if self.textInputAllowed then
		self:showInputTextDialog(guiElement)
	end
end

--- Used for text input settings.
function AIParameterSettingList:showInputTextDialog(guiElement)
	TextInputDialog.show(
		function (self, value, clickOk)
			if clickOk and value ~= nil then
				local v = value:match("-%d[%d., ]*")
				v = v or value:match("%d[%d., ]*")
				v = v and tonumber(v)
				if v then
					local unit = self.data.unit
					if unit then 
						local unitStrFunc = AIParameterSettingList.UNITS_CONVERSION[unit]
						if unitStrFunc then
							v = unitStrFunc(v)
						end
					end
					local ix, diff = self:getClosestIx(v)
					if diff < self.INPUT_VALUE_THRESHOLD then
						self:setToIx(ix)
						self:raiseDirtyFlag()
					else 
						self:setDefault()
					end
				else 
					self:setDefault()
				end
			end
			if guiElement and guiElement.updateTitle then
				guiElement:updateTitle()
				FocusManager:setFocus(guiElement)
			end
		end,
		self, nil, self:getTitle(), nil, 7,
		g_i18n:getText("button_ok"), nil, nil, false)
end

function AIParameterSettingList:resetGuiElement()
	if self.guiElement then
		if self.oldMouseEvent then
			self.guiElement.mouseEvent = self.oldMouseEvent
			self.oldMouseEvent = nil
		end
	end

	self.guiElement = nil
end

function AIParameterSettingList:onClick(state)
	local new = self:checkAndSetValidValue(state)
	self:setToIx(new)
	if new ~= self.previous then
		self:raiseDirtyFlag()
	end
end
