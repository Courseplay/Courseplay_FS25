---@class FilltypeSelectionDialog
FilltypeSelectionDialog = {} 
local FilltypeSelectionDialog_mt = Class(FilltypeSelectionDialog, MessageDialog)
function FilltypeSelectionDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or FilltypeSelectionDialog_mt)
    self.setting = nil
    self.callbackFunc = nil
    return self
end

function FilltypeSelectionDialog.register()
    FilltypeSelectionDialog.INSTANCE = FilltypeSelectionDialog.new()
    g_gui:loadGui(Utils.getFilename("config/gui/dialog/FilltypeSelectionDialog.xml", 
        g_Courseplay.BASE_DIRECTORY), "FilltypeSelectionDialog", FilltypeSelectionDialog.INSTANCE)
end

function FilltypeSelectionDialog.show(setting, callbackFunc)
    if FilltypeSelectionDialog.INSTANCE == nil then
		return
	end
    local dialog = FilltypeSelectionDialog.INSTANCE
    dialog:setSetting(setting)
    dialog:setCallback(callbackFunc)
    g_gui:showDialog("FilltypeSelectionDialog")
    return dialog
end

function FilltypeSelectionDialog:createFromExistingGui(_)
    local settings = self.setting
    local callbackFunc = self.callbackFunc
	FilltypeSelectionDialog.register()
	FilltypeSelectionDialog.show(settings, callbackFunc)
end

function FilltypeSelectionDialog:onCreate()
    self.fillTypeList:setDataSource(self)
end

function FilltypeSelectionDialog:onOpen()
    FilltypeSelectionDialog:superClass().onOpen(self)
    self.setting:bindSettingsToGui(function(fillTypeSetting, fillType, maxFillLevel, minFillLevel, counter)
        self.fillTypeList:reloadData()
        self.fillTypeList:setSelectedIndex(fillType:getCurrentIndex())
        local function link(element, setting)
            setting:refresh()
            local option = element:getDescendantByName("option")
            option:setDataSource(setting)
            option.aiParameter = setting
            option:setDisabled(not setting:getCanBeChanged())
            local title = element:getDescendantByName("title")
            title:setText(setting:getTitle())
        end
        link(self.maxFillLevel, maxFillLevel)
        link(self.minFillLevel, minFillLevel)
        link(self.counter, counter)
    end)
end

function FilltypeSelectionDialog:onClickOk()
    if self.callbackFunc then 
        self.callbackFunc()
    end
    self:close()
end

function FilltypeSelectionDialog:onClickDiscard()
    if self.callbackFunc then 
        self.callbackFunc()
    end
    self:close()
end

function FilltypeSelectionDialog:onClickCpMultiTextOption(_, guiElement)
	-- CpSettingsUtil.updateGuiElementsBoundToSettings(guiElement.parent.parent, self.cpMenu:getCurrentVehicle())
end

---@param setting CpAIParameterFillTypeSetting
function FilltypeSelectionDialog:setSetting(setting)
    self.setting = setting
end

function FilltypeSelectionDialog:setCallback(callbackFunc)
    self.callbackFunc = callbackFunc
end

function FilltypeSelectionDialog:getNumberOfSections(list)
    return 1
end

function FilltypeSelectionDialog:getTitleForSectionHeader(list, section)

end

function FilltypeSelectionDialog:getNumberOfItemsInSection(list, section) 
	return self.setting:getNumberOfItemsInSection(list, section)
end

function FilltypeSelectionDialog:populateCellForItemInSection(list, section, index, cell)
    self.setting:populateCellForItemInSection(list, section, index, cell)
end

function FilltypeSelectionDialog:onClickList(list, section, index, listElement)
    listElement.onClickCallback(self)
end

function FilltypeSelectionDialog:onListSelectionChanged(list, section, index)
    self.setting:onListSelectionChanged(list, section, index)
end

