---@class TargetPointSelectionDialog
TargetPointSelectionDialog = {} 
local TargetPointSelectionDialog_mt = Class(TargetPointSelectionDialog, MessageDialog)
function TargetPointSelectionDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or TargetPointSelectionDialog_mt)
    ---@type CpAIParameterTargetPoint[]
    self.settings = {}
    self.callbackFunc = nil
    return self
end

function TargetPointSelectionDialog.register()
    TargetPointSelectionDialog.INSTANCE = TargetPointSelectionDialog.new()
    g_gui:loadGui(Utils.getFilename("config/gui/dialog/TargetPointSelectionDialog.xml", 
        g_Courseplay.BASE_DIRECTORY), "TargetPointSelectionDialog", TargetPointSelectionDialog.INSTANCE)
end

function TargetPointSelectionDialog.show(settings, callbackFunc)
    if TargetPointSelectionDialog.INSTANCE == nil then
		return
	end
    local dialog = TargetPointSelectionDialog.INSTANCE
    -- dialog:setCallback(p9, p10)
    dialog:setTargetPoints(settings)
    dialog:setCallback(callbackFunc)
    g_gui:showDialog("TargetPointSelectionDialog")
    return dialog
end

function TargetPointSelectionDialog:createFromExistingGui(_)
    local settings = self.settings
    local callbackFunc = self.callbackFunc
	TargetPointSelectionDialog.register()
	TargetPointSelectionDialog.show(settings, callbackFunc)
end

function TargetPointSelectionDialog:onCreate()
    for i=1, 3 do 
        self.lists[i]:setDataSource(self)
    end 
end

function TargetPointSelectionDialog:onOpen()
    local onOpenList = function (list, setting, header)
        list:reloadData(self)
        list:setVisible(setting ~= nil and not setting:getIsDisabled())
        local ix = setting and g_graph:getTargetIndexByUniqueId(setting:getValue()) or 1
        list:setSelected(ix > -1 and ix or 1)
        header:setVisible(setting~=nil)
        header:setText(setting and setting:getTitle() or "??")
    end
    for i=1, 3 do 
        onOpenList(self.lists[i], self.settings[i], self.listHeaders[i])
    end 
end

function TargetPointSelectionDialog:onClickOk()
    if self.callbackFunc then 
        self.callbackFunc()
    end
    self:close()
	return false
end

function TargetPointSelectionDialog:onClickBack()
    local ret = TargetPointSelectionDialog:superClass().onClickBack(self)
    if not ret then
        if self.callbackFunc then 
            self.callbackFunc()
        end
    end
    return ret
end

function TargetPointSelectionDialog:setTargetPoints(settings)
    self.settings = settings or {}
end

function TargetPointSelectionDialog:setCallback(callbackFunc)
    self.callbackFunc = callbackFunc
end

function TargetPointSelectionDialog:getNumberOfSections(list)
    return 1
end

function TargetPointSelectionDialog:getTitleForSectionHeader(list, section)

end

function TargetPointSelectionDialog:getNumberOfItemsInSection(list, section) 
	return g_graph:getNumTargets()
end

function TargetPointSelectionDialog:applySettingValue(setting, target)
    if setting and not setting:getIsDisabled() and target then 
        setting:setValue(target:getUniqueID())
    end
end

function TargetPointSelectionDialog:populateCellForItemInSection(list, section, index, cell)
    local target = g_graph:getTargetByIndex(index)
    cell:getAttribute("title"):setText(target and target:getName() or "????")
    cell.onClickCallback = function ()
        for i=1, 3 do 
            if list == self.lists[i] then
                self:applySettingValue(self.settings[i], target) 
            end
        end 
    end
end

function TargetPointSelectionDialog:onClickList(list, section, index, listElement)
    listElement.onClickCallback(self)
end

function TargetPointSelectionDialog:onListSelectionChanged(list, section, index)
    local target = g_graph:getTargetByIndex(index)
	for i=1, 3 do 
        if list == self.lists[i] then 
            self:applySettingValue(self.settings[i], target)
        end
    end 
end

