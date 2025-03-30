---@class CpAIParameterFillTypeSetting : AIParameterSetting
CpAIParameterFillTypeSetting = CpObject(AIParameterSetting)

function CpAIParameterFillTypeSetting:init(data, vehicle, class)
	AIParameterSetting.init(self, data, vehicle, class)
	self.guiParameterType = AIParameterType.TEXT --- For the giants gui element.
	self:initFromData(data, vehicle, class)
	--- Use this hack to load the setting without the need for changing every setting behavior.
	local filePath = Utils.getFilename("config/jobParameters/FillTypeSelectionParameterSetup.xml", 
		g_Courseplay.BASE_DIRECTORY)
	local childrenData = {
		generateFillTypes = class.generateFillTypes
	}
	CpSettingsUtil.loadSettingsFromSetup(childrenData, filePath)

	--- Child parameters
	---@type AIParameterSettingList
	self.fillType = childrenData.fillType:clone(vehicle, class)
	self.fillType:setParent(self)
	---@type AIParameterSettingList
	self.maxFillLevel = childrenData.maxFillLevel:clone(vehicle, class)
	self.maxFillLevel:setParent(self)
	---@type AIParameterSettingList
	self.minFillLevel = childrenData.minFillLevel:clone(vehicle, class)
	self.minFillLevel:setParent(self)
	---@type AIParameterSettingList
	self.counter = childrenData.counter:clone(vehicle, class)
	self.counter:setParent(self)

	self.currentCounterValue = 0
end

function CpAIParameterFillTypeSetting:saveToXMLFile(xmlFile, key, usedModNames)
	self.fillType:saveToXMLFile(xmlFile, key..".fillType", usedModNames)
	self.maxFillLevel:saveToXMLFile(xmlFile, key..".maxFillLevel", usedModNames)
	self.minFillLevel:saveToXMLFile(xmlFile, key..".minFillLevel", usedModNames)
	self.counter:saveToXMLFile(xmlFile, key..".counter", usedModNames)
end

function CpAIParameterFillTypeSetting:loadFromXMLFile(xmlFile, key)
	self.fillType:loadFromXMLFile(xmlFile, key..".fillType")
	self.maxFillLevel:loadFromXMLFile(xmlFile, key..".maxFillLevel")
	self.minFillLevel:loadFromXMLFile(xmlFile, key..".minFillLevel")
	self.counter:loadFromXMLFile(xmlFile, key..".counter")
end

function CpAIParameterFillTypeSetting:readStream(streamId, connection)
	self.fillType:readStream(streamId, connection)
	self.maxFillLevel:readStream(streamId, connection)
	self.minFillLevel:readStream(streamId, connection)
	self.counter:readStream(streamId, connection)
	self.isSynchronized = true
end

function CpAIParameterFillTypeSetting:writeStream(streamId, connection)
	self.fillType:writeStream(streamId, connection)
	self.maxFillLevel:writeStream(streamId, connection)
	self.minFillLevel:writeStream(streamId, connection)
	self.counter:writeStream(streamId, connection)
end

function CpAIParameterFillTypeSetting:refresh()
	self.fillType:refresh()
	self.maxFillLevel:refresh()
	self.minFillLevel:refresh()
	self.counter:refresh()
end

function CpAIParameterFillTypeSetting:clone(...)
	return CpAIParameterFillTypeSetting(self.data,...)
end

function CpAIParameterFillTypeSetting:copy(otherSetting)
	self.fillType:copy(otherSetting.fillType)
	self.maxFillLevel:copy(otherSetting.maxFillLevel)
	self.minFillLevel:copy(otherSetting.minFillLevel)
	self.counter:copy(otherSetting.counter)
end

function CpAIParameterFillTypeSetting:resetToLoadedValue()
	self.fillType:resetToLoadedValue()
	self.maxFillLevel:resetToLoadedValue()
	self.minFillLevel:resetToLoadedValue()
	self.counter:resetToLoadedValue()
end

function CpAIParameterFillTypeSetting:bindSettingsToGui(lambda, ...)
	lambda(self, self.fillType, self.maxFillLevel, self.minFillLevel, self.counter, ...)
end

function CpAIParameterFillTypeSetting:getNumberOfItemsInSection(list, section)
	return self.fillType:getNumberOfElements()
end

function CpAIParameterFillTypeSetting:getTitleForSectionHeader(list, section)
	return nil
end

function CpAIParameterFillTypeSetting:populateCellForItemInSection(list, section, index, cell)
	cell:getAttribute("name"):setText(self.fillType:getTextByIndex(index))
	-- if g_Courseplay.globalSettings:isAutoDriveForStreetActive() then
	-- 	if g_Courseplay.adSortedGroups then 
	-- 		cell:getAttribute("name"):setText(g_Courseplay.adSortedGroups[section + g_Courseplay.adOffsetIndex][index].name)
	-- 		cell.target = self.aiFrame
	-- 		cell:setCallback("onClickCallback", "onClickStreetTargetList")
	-- 	else 
	-- 		cell:getAttribute("name"):setText("---")
	-- 		cell.target = self.aiFrame
	-- 		cell:setCallback("onClickCallback", "onClickStreetTargetList")
	-- 	end
	-- else 
	-- 	if self.aiFrame.streetTargetPointParameter then
	-- 		cell:getAttribute("name"):setText(self.aiFrame.streetTargetPointParameter:getTextByIndex(index))
	-- 		cell.target = self.aiFrame
	-- 		cell:setCallback("onClickCallback", "onClickStreetTargetList")
	-- 	end
	-- end
end

function CpAIParameterFillTypeSetting:onListSelectionChanged(list, section, index)
	self.fillType:setValue(self.fillType:getValueByIndex(index))
end

function CpAIParameterFillTypeSetting:getString()
	return self.fillType:getString()
end

function CpAIParameterFillTypeSetting:__tostring()
	return string.format("CpAIParameterFillTypeSetting(fillType: %s, maxFillLevel: %s, minFillLevel: %s, counter: %s)", 
		tostring(self.fillType), tostring(self.maxFillLevel), tostring(self.minFillLevel), tostring(self.counter))
end

function CpAIParameterFillTypeSetting:getIsValid()
	return self.isValid
end

function CpAIParameterFillTypeSetting:applyCounter(reset)
	self.currentCounterValue = self.currentCounterValue + 1
	if reset then 
		self.currentCounterValue = 0
	end
end

function CpAIParameterFillTypeSetting:getCounter()
	return self.currentCounterValue
end

function CpAIParameterFillTypeSetting:getIsCounterValid()
	return self.currentCounterValue <= self.counter:getValue()
end