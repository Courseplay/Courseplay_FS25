---@class CpAIParameterGroup
CpAIParameterGroup = CpObject()
function CpAIParameterGroup:init(class, data)
	self.class = class
	self.data = data
	self.parameters = {}
end

---@return string
function CpAIParameterGroup:getTitle()
	return g_i18n:getText(self.data.title)
end

---@param parameter AIParameterSetting
function CpAIParameterGroup:addParameter(parameter)
	table.insert(self.parameters, parameter)
end

---@return AIParameterSetting[]
function CpAIParameterGroup:getParameters()
	return self.parameters
end

function CpAIParameterGroup:getIsDisabled()
	return self:getCallback(self.data.isDisabledFunc)
end

function CpAIParameterGroup:getIsVisible()
	return self.data.isVisibleFunc == nil or self:getCallback(self.data.isVisibleFunc)
end

--- Gets the result from a class callback.
function CpAIParameterGroup:getCallback(callbackStr, ...)
	if callbackStr and self.class and self.class[callbackStr] then
		return self.class[callbackStr](self.class, self, ...)
	end
end