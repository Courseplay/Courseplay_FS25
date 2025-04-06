--- Interface that shows all functions, that need to be implemented for settings!
---@class AIParameterSettingInterface
AIParameterSettingInterface = CpObject()

function AIParameterSettingInterface:init()
	
end

-------------------------------------------------
--- Giants functions form AIParameter
-------------------------------------------------

function AIParameterSettingInterface:readStream(streamId, connection)

end

function AIParameterSettingInterface:writeStream(streamId, connection)

end

function AIParameterSettingInterface:saveToXMLFile(xmlFile, key, usedModNames)
	
end

function AIParameterSettingInterface:loadFromXMLFile(xmlFile, key)
	
end

function AIParameterSettingInterface:getType()

end

function AIParameterSettingInterface:getIsValid()

end

function AIParameterSettingInterface:setIsValid(isValid)
	
end

function AIParameterSettingInterface:getCanBeChanged()

end

function AIParameterSettingInterface:getString()

end

-------------------------------------------------
--- Settings implementation function needed
-------------------------------------------------

--- Reference setting name.
function AIParameterSettingInterface:getName()
	
end

--- Gets the setting title translation.
function AIParameterSettingInterface:getTitle()
	
end

--- Gets the setting tooltip translation.
function AIParameterSettingInterface:getTooltip()
	
end

function AIParameterSettingInterface:getIsDisabled()
	
end

function AIParameterSettingInterface:getIsVisible()
	
end

function AIParameterSettingInterface:getIsUserSetting()
	
end

function AIParameterSettingInterface:getIsExpertModeSetting()
	
end

-- Is the current value same as the param?
function AIParameterSettingInterface:is(value)
	
end

-- Get the current text key (for the logs, for example)
function AIParameterSettingInterface:__tostring()
	
end

--- Callback called on value change.
function AIParameterSettingInterface:onChange()
	
end


--- Called form extern to update the setting value and validate it.
function AIParameterSettingInterface:refresh()
	
end

function AIParameterSettingInterface:resetToLoadedValue()
	
end

--- Sets a float value relative to the incremental.
function AIParameterSettingInterface:setFloatValue(value, epsilon, noEventSend)
	
end

--- Sets a value.
function AIParameterSettingInterface:setValue(value, noEventSend)
	
end

function AIParameterSettingInterface:setDefault(noEventSend)
	
end

--- Gets a specific value.
function AIParameterSettingInterface:getValue()
	
end

--- Clones the setting, for creating dynamic setting table in each vehicle!
function AIParameterSettingInterface:clone(...)
	--return AIParameterSettingInterface.new(self.data, ...)
end

--- Copies the value to another setting after cloning!
function AIParameterSettingInterface:copy(setting)

end

function AIParameterSettingInterface:isAlmostEqualTo(other)
	
end

--- GuiElement was clicked
function AIParameterSettingInterface:onClickCenter(guiElement)
	
end

--- Raises an event and sends the callback string to the Settings controller class.
function AIParameterSettingInterface:raiseCallback(callbackStr, ...)
	
end

function AIParameterSettingInterface:hasCallback(callbackStr)
	
end

function AIParameterSettingInterface:getCallback(callbackStr, ...)
	
end

function AIParameterSettingInterface:raiseDirtyFlag()
	
end

function AIParameterSettingInterface:debug(str, ...)
	
end

function AIParameterSettingInterface:getDebugString()
	
end