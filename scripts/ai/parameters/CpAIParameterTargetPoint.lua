--- Parameter to selected an unloading station.
---@class CpAIParameterTargetPoint : AIParameterSetting
CpAIParameterTargetPoint = CpObject(AIParameterSetting)

function CpAIParameterTargetPoint:init(data, vehicle, class)
	AIParameterSetting.init(self, data, vehicle, class)
	self:initFromData(data, vehicle, class)
	self.guiParameterType = AIParameterType.TEXT_BUTTON
	self.uniqueID = -1
	return self
end

function CpAIParameterTargetPoint:clone(...)
	return CpAIParameterTargetPoint(self.data,...)
end

function CpAIParameterTargetPoint:saveToXMLFile(xmlFile, key, usedModNames)
	xmlFile:setInt(key .. "#currentValue", self.uniqueID)
end

function CpAIParameterTargetPoint:loadFromXMLFile(xmlFile, key)
	self.uniqueID = xmlFile:getInt(key .. "#currentValue", self.uniqueID)
end

function CpAIParameterTargetPoint:getString()
	local target = g_graph:getTargetByUniqueID(self.uniqueID) 
	return target and target:getName() or "???"
end

function CpAIParameterTargetPoint:getValue()
	return self.uniqueID
end

-- function CpAIParameterTargetPoint:getIsDisabled()
-- 	return AIParameterSetting.getIsDisabled(self) or 
-- 		g_graph:getTargetByUniqueID(self.uniqueID) == nil
-- end

function CpAIParameterTargetPoint:setValue(uniqueID, noEventSend)
	self.uniqueID = uniqueID
	if uniqueID ~= self.uniqueID then
		self:onChange()
	end
end

function CpAIParameterTargetPoint:copy(setting)
	if self.data.isCopyValueDisabled then 
		return
	end
	self:setValue(setting:getValue())
end

function CpAIParameterTargetPoint:onChange()
	self:raiseCallback(self.data.callbacks.onChangeCallbackStr)
end

function CpAIParameterTargetPoint:refresh()
	local target = g_graph:getTargetByUniqueID(self.uniqueID) 
	if not target then 
		self:setValue(-1)
	end
end

function CpAIParameterTargetPoint:__tostring()
	return string.format("CpAIParameterTargetPoint(name=%s, value=%s, text=%s)", 
		self.name, tostring(self:getValue()), self:getString())
end