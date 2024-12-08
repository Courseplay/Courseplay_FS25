--[[
	This frame is a page for all global settings in the in game menu.
	All the layout, gui elements are cloned from the general settings page of the in game menu.
]]--

CpVehicleSettingsFrame = {
	CATEGRORIES = {
		BASIC_SETTINGS = 1
	},
	CATEGRORY_TEXTS = {
		"CP_vehicle_setting_subTitle_vehicle",
	}
}
CpVehicleSettingsFrame.NUM_CATEGORIES = #CpVehicleSettingsFrame.CATEGRORY_TEXTS

local CpVehicleSettingsFrame_mt = Class(CpVehicleSettingsFrame, TabbedMenuFrameElement)

function CpVehicleSettingsFrame.new(target, custom_mt)
	local self = TabbedMenuFrameElement.new(target, custom_mt or CpVehicleSettingsFrame_mt)
	self.subCategoryPages = {}
	self.subCategoryTabs = {}
	return self
end

function CpVehicleSettingsFrame.setupGui()
	local vehicleSettingsFrame = CpVehicleSettingsFrame.new()
	g_gui:loadGui(Utils.getFilename("config/gui/pages/VehicleSettingsFrame.xml", Courseplay.BASE_DIRECTORY),
		"CpVehicleSettingsFrame", vehicleSettingsFrame, true)
end

function CpVehicleSettingsFrame.createFromExistingGui(gui, guiName)
	local newGui = CpVehicleSettingsFrame.new(nil, nil)

	g_gui.frames[gui.name].target:delete()
	g_gui.frames[gui.name]:delete()
	g_gui:loadGui(gui.xmlFilename, guiName, newGui, true)

	return newGui
end

function CpVehicleSettingsFrame:initialize(menu)
	self.cpMenu = menu
	self.booleanPrefab:unlinkElement()
	FocusManager:removeElement(self.booleanPrefab)
	self.multiTextPrefab:unlinkElement()
	FocusManager:removeElement(self.multiTextPrefab)
	self.sectionHeaderPrefab:unlinkElement()
	FocusManager:removeElement(self.sectionHeaderPrefab)
	self.selectorPrefab:unlinkElement()
	FocusManager:removeElement(self.selectorPrefab)
	self.containerPrefab:unlinkElement()
	FocusManager:removeElement(self.containerPrefab)

	for key = 1, CpVehicleSettingsFrame.NUM_CATEGORIES do 
		self.subCategoryPaging:addText(tostring(key))
		self.subCategoryPages[key] = self.containerPrefab:clone(self)
		self.subCategoryPages[key]:getDescendantByName("layout").scrollDirection = "vertical"
		FocusManager:loadElementFromCustomValues(self.subCategoryPages[key])
		self.subCategoryTabs[key] = self.selectorPrefab:clone(self.subCategoryBox)
		FocusManager:loadElementFromCustomValues(self.subCategoryTabs[key])
		self.subCategoryBox:invalidateLayout()
	
		self.subCategoryTabs[key]:setText(g_i18n:getText(self.CATEGRORY_TEXTS[key]))
		self.subCategoryTabs[key]:getDescendantByName("background"):setSize(
			self.subCategoryTabs[key].size[1], self.subCategoryTabs[key].size[2])
		self.subCategoryTabs[key].onClickCallback = function ()
			self:updateSubCategoryPages(key)
		end
	end
end

function CpVehicleSettingsFrame:onFrameOpen()
	CpVehicleSettingsFrame:superClass().onFrameOpen(self)
	local vehicle = self.cpMenu:getCurrentVehicle()
	local settings = vehicle:getCpSettings()
	local settingsBySubTitle, pageTitle = CpVehicleSettings.getSettingSetup()
	local title = string.format(g_i18n:getText(pageTitle), vehicle:getName())
	self.categoryHeaderText:setText(title)

	local layout = self.subCategoryPages[1]:getDescendantByName("layout")
	for i = #layout.elements, 1, -1 do
		layout.elements[i]:delete()
	end
	CpSettingsUtil.generateAndBindGuiElementsToSettings(settingsBySubTitle,
		layout, self.multiTextPrefab, self.booleanPrefab, 
		self.sectionHeaderPrefab, settings)
	CpSettingsUtil.updateGuiElementsBoundToSettings(layout, vehicle)
	
	self:updateSubCategoryPages(self.CATEGRORIES.BASIC_SETTINGS)
	FocusManager:setFocus(self.subCategoryPages[self.CATEGRORIES.BASIC_SETTINGS]:getDescendantByName("layout"))
end

function CpVehicleSettingsFrame:onClickCpMultiTextOption(_, guiElement)
	CpSettingsUtil.updateGuiElementsBoundToSettings(guiElement.parent.parent, self.cpMenu:getCurrentVehicle())
end

function CpVehicleSettingsFrame:updateSubCategoryPages(state)
	for i, _ in ipairs(self.subCategoryPages) do
		self.subCategoryPages[i]:setVisible(false)
		self.subCategoryTabs[i]:setSelected(false)
	end
	self.subCategoryPages[state]:setVisible(true)
	self.subCategoryTabs[state]:setSelected(true)
	self.settingsSlider:setDataElement(self.subCategoryPages[state]:getDescendantByName("layout"))
end
