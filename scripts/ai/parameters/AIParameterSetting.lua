--- Basic setting that implements the basic interface functionalities.
---@class AIParameterSetting : AIParameterSettingInterface
AIParameterSetting = CpObject(AIParameterSettingInterface)

function AIParameterSetting:init(data, vehicle, class)	
	AIParameterSettingInterface.init(self)
	self.data = data
	self.vehicle = vehicle
	self.class = class

	self.name = ""
	self.title = ""
	self.tooltip = ""

	self.isValid = true

	self.guiParameterType = nil
	self.parent = nil
end

--- Initialize the setting from config data supplied in CpSettingsUtil
---@param data table
---@param vehicle table
---@param class table
function AIParameterSetting:initFromData(data, vehicle, class)
	self.data = data
	self.vehicle = vehicle
	self.class = class

	self.name = data.name
	self.title = data.title
	self.tooltip = data.tooltip
end

function AIParameterSetting:getName()
	return self.name
end

function AIParameterSetting:getTooltip()
	return g_i18n:getText(self.tooltip)
end

function AIParameterSetting:getTitle()
	return g_i18n:getText(self.title)
end

--- Gets a translation text for texts like these: "CP_fieldWorkJobParameters_startAt_nearest",
--- where "nearest" the sub name is.
---@param subName string
---@return string
function AIParameterSetting:getSubText(subName)
	return g_i18n:getText(self.data.setupName .. "_" .. subName)
end

function AIParameterSetting:getType()
	return self.guiParameterType	
end

function AIParameterSetting:getString()
	return ""	
end

function AIParameterSetting:getIsValid()
	return self.isValid
end

function AIParameterSetting:setIsValid(isValid)
	self.isValid = isValid
end

function AIParameterSetting:setParent(parent)
	self.parent = parent
end

function AIParameterSetting:setClass(class)
	self.class = class
end

function AIParameterSetting:getIsDisabled()
	if self:hasCallback(self.data.isDisabledFunc) then 
		return self:getCallback(self.data.isDisabledFunc)
	end
	if self.parent and self.parent:getIsDisabled() then 
		return true
	end
	return false
end

function AIParameterSetting:getCanBeChanged()
	return not self:getIsDisabled()
end

--- Is the setting visible based on the expert mode setting if necessary and
--- checks if any callbacks are correct.
function AIParameterSetting:getIsVisible()
	if self:getIsExpertModeSetting() and not g_Courseplay.globalSettings.expertModeActive:getValue() then 
		return false
	end
	if self:hasCallback(self.data.isVisibleFunc) then 
		return self:getCallback(self.data.isVisibleFunc)
	end
	if self.parent and not self.parent:getIsVisible() then 
		return false
	end
	return true
end

--- Is the setting specific for a player and is not synchronized?
function AIParameterSetting:getIsUserSetting()
	return self.data.isUserSetting
end

--- Is the setting disabled, when the expert mode is deactivated?
function AIParameterSetting:getIsExpertModeSetting()
	return self.data.isExpertModeOnly
end

--- Raises an event and sends the callback string to the Settings controller class.
function AIParameterSetting:raiseCallback(callbackStr, ...)
	if self.class ~= nil and self.class.raiseCallback and callbackStr then
		self:debug("raised Callback %s", callbackStr)
		--- If the setting is bound to a setting, then call the specialization function with self as vehicle.
		if self.vehicle ~= nil then 
			self.class.raiseCallback(self.vehicle, callbackStr, self, ...)
		else
			self.class:raiseCallback(callbackStr, self, ...)
		end
	end
end

--- If the class has a given callback to call.
function AIParameterSetting:hasCallback(callbackStr)
	if self.class ~= nil and callbackStr then
		if self.class[callbackStr] ~= nil then 
			return true
		end
	end
end

--- Gets the result from a class callback.
function AIParameterSetting:getCallback(callbackStr, ...)
	if self:hasCallback(callbackStr) then
		if self.vehicle ~= nil then 
			return self.class[callbackStr](self.vehicle, self, ...)
		else
			return self.class[callbackStr](self.class, self, ...)
		end
	end
end

--- Make sure the setting value gets synchronized by the class.
function AIParameterSetting:raiseDirtyFlag()
	if not self:getIsUserSetting() then
		if self.class ~= nil and self.class.raiseDirtyFlag ~= nil then
			if self.vehicle ~= nil then 
				self:debug("Raising dirty flag for vehicle", CpUtil.getName(self.vehicle))
				self.class.raiseDirtyFlag(self.vehicle, self)
			else
				self:debug("Raising dirty flag")
				self.class:raiseDirtyFlag(self)
			end
		end
	end
end

function AIParameterSetting:debug(str, ...)
	local name = string.format("%s: ", self.name)
	if self.vehicle == nil then
		CpUtil.debugFormat(CpUtil.DBG_HUD, name..str, ...)
	else 
		CpUtil.debugVehicle(CpUtil.DBG_HUD, self.vehicle, name..str, ...)
	end
end

function AIParameterSetting:info(str, ...)
	local name = string.format("%s: ", self.name)
	if self.vehicle == nil then
		CpUtil.info(name..str, ...)
	else 
		CpUtil.infoVehicle(self.vehicle, name..str, ...)
	end
end

function AIParameterSetting:error(str, ...)
	local name = string.format("%s: ", self.name)
	if self.vehicle == nil then
		CpUtil.error(name..str, ...)
	else 
		CpUtil.errorVehicle(self.vehicle, name..str, ...)
	end
end

function AIParameterSetting:getDebugString()
	return tostring(self)
end