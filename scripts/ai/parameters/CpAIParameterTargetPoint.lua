--- Parameter to selected an unloading station.
---@class CpAIParameterTargetPoint : AIParameterSettingList
CpAIParameterTargetPoint = CpObject(AIParameterSettingList)

function CpAIParameterTargetPoint:init(data, vehicle, class)
	AIParameterSettingList.init(self, data, vehicle, class)
	return self
end

function CpAIParameterTargetPoint:clone(...)
	return CpAIParameterTargetPoint(self.data,...)
end

function CpAIParameterTargetPoint:__tostring()
	return string.format("CpAIParameterTargetPoint(name=%s, value=%s, text=%s)", self.name, tostring(self:getValue()), self:getString())
end