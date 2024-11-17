--[[
	This frame is a page for all global settings in the in game menu.
	All the layout, gui elements are cloned from the general settings page of the in game menu.
]]--

CpCourseGeneratorFrame = {
	CATEGRORIES = {
		BASIC_SETTINGS = 1,
		DEBUG_SETTINGS = 2
	},
	CATEGRORY_TEXTS = {
		"CP_global_setting_subTitle_general",
		"TODO: Debug"
	}
}
CpCourseGeneratorFrame.NUM_CATEGORIES = #CpCourseGeneratorFrame.CATEGRORY_TEXTS

local CpCourseGeneratorFrame_mt = Class(CpCourseGeneratorFrame, TabbedMenuFrameElement)

function CpCourseGeneratorFrame.new(target, custom_mt)
	local self = TabbedMenuFrameElement.new(target, custom_mt or CpCourseGeneratorFrame_mt)
	self.subCategoryPages = {}
	self.subCategoryTabs = {}
	return self
end

function CpCourseGeneratorFrame.setupGui()
	local courseGeneratorFrame = CpCourseGeneratorFrame.new()
	g_gui:loadGui(Utils.getFilename("config/gui/pages/CourseGeneratorFrame.xml", Courseplay.BASE_DIRECTORY),
	 			 "CpCourseGeneratorFrame", courseGeneratorFrame, true)
end

function CpCourseGeneratorFrame.createFromExistingGui(gui, guiName)
	local newGui = CpCourseGeneratorFrame.new(nil, nil)

	g_gui.frames[gui.name].target:delete()
	g_gui.frames[gui.name]:delete()
	g_gui:loadGui(gui.xmlFilename, guiName, newGui, true)

	return newGui
end

function CpCourseGeneratorFrame:initialize()
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

	for key = 1, CpCourseGeneratorFrame.NUM_CATEGORIES do 
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

function CpCourseGeneratorFrame:onFrameOpen()
	local vehicle = CpUtil.getCurrentVehicle()
	if not vehicle then 
		return
	end
	local settings = vehicle:getCourseGeneratorSettings()
	local settingsBySubTitle, pageTitle = CpCourseGeneratorSettings.getSettingSetup()
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

function CpCourseGeneratorFrame:onClickCpMultiTextOption(_, guiElement)
	local vehicle = CpUtil.getCurrentVehicle()
	CpSettingsUtil.updateGuiElementsBoundToSettings(
		self.subCategoryPages[self.subCategoryPaging:getState()]:getDescendantByName("layout"), vehicle)
end

function CpCourseGeneratorFrame:updateSubCategoryPages(state)
	for i, _ in ipairs(self.subCategoryPages) do
		self.subCategoryPages[i]:setVisible(false)
		self.subCategoryTabs[i]:setSelected(false)
	end
	self.subCategoryPages[state]:setVisible(true)
	self.subCategoryTabs[state]:setSelected(true)
	self.subCategoryPages[state]:getDescendantByName("layout"):invalidateLayout()
	self.settingsSlider:setDataElement(self.subCategoryPages[state]:getDescendantByName("layout"))
end

function CpCourseGeneratorFrame:onDrawPostIngameMapHotspots()
	
end