CpHelpFrame = {}
local CpHelpFrame_mt = Class(CpHelpFrame, TabbedMenuFrameElement)
function CpHelpFrame.new(target, custom_mt)
	local self = TabbedMenuFrameElement.new(target, custom_mt or CpHelpFrame_mt)

	self.helpLineManager = HelpLineManager.new()
	self.helpLineManager:initDataStructures()
	self.helpLineManager.customEnvironmentNames = {}
	self.helpLineManager.customEnvironmentToCategory = {}
	self.helpLineManager:loadFromXML(Utils.getFilename("config/HelpMenu.xml", g_Courseplay.BASE_DIRECTORY))
	return self
end

function CpHelpFrame.setupGui()
	local frame = CpHelpFrame.new()
	g_gui:loadGui(Utils.getFilename("config/gui/pages/HelpFrame.xml", Courseplay.BASE_DIRECTORY),
	 			 "CpHelpFrame", frame, true)
end

function CpHelpFrame.createFromExistingGui(gui, guiName)
	local newGui = CpHelpFrame.new(nil, nil)

	g_gui.frames[gui.name].target:delete()
	g_gui.frames[gui.name]:delete()
	g_gui:loadGui(gui.xmlFilename, guiName, newGui, true)

	return newGui
end

function CpHelpFrame:initialize(menu)
	self.helpLineDotTemplate:unlinkElement()
	FocusManager:removeElement(self.helpLineDotTemplate)
end

function CpHelpFrame:onFrameOpen()
	CpHelpFrame:superClass().onFrameOpen(self)
	self.customEnvironments = self.helpLineManager:getCustomEnvironmentNames()
	local texts = {}
	for _, env in ipairs(self.customEnvironments) do 
		if string.isNilOrWhitespace(env) then 
			--table.insert(texts, g_i18n:getText("ui_helpLine_baseGame"))
		else 
			local mod = g_modManager:getModByName(env)
			if mod then 
				table.insert(texts, mod.title)
			else 
				table.insert(texts, "Unknown")
			end
		end	
	end
	self.helpLineSelector:setTexts(texts)
	for i = 1, #self.helpLineSelector.texts do
		local dot = self.helpLineDotTemplate:clone(self.helpLineDotBox)
		dot.getIsSelected = function ()
			return self.helpLineSelector:getState() == i
		end
	end
	self.helpLineDotBox:invalidateLayout()
	self.helpLineList:reloadData()
	self:setSoundSuppressed(true)
	FocusManager:setFocus(self.helpLineList)
	self:setSoundSuppressed(false)
	self.helpLineContentBox:registerActionEvents()
end

function CpHelpFrame:onFrameClose()
	CpHelpFrame:superClass().onFrameClose(self)
	self.helpLineContentBox:removeActionEvents()
end

function CpHelpFrame:onClickMultiTextOption(_, guiElement)
	self.helpLineList:reloadData()
end

function CpHelpFrame:onListSelectionChanged(list, section, index) 
	if self.helpLineContentItem ~= nil then
		self:updateContents(self:getPage(section, index))
	end
end

function CpHelpFrame:getNumberOfSections(list) 
	local customEnvironment = self.customEnvironments[self.helpLineSelector:getState()]
	return #self.helpLineManager:getCategories(customEnvironment)
end

function CpHelpFrame:getNumberOfItemsInSection(list, section) 
	local customEnvironment = self.customEnvironments[self.helpLineSelector:getState()]
	local category = self.helpLineManager:getCategory(customEnvironment, section)
	return #category.pages
end

function CpHelpFrame:getTitleForSectionHeader(list, section) 
	local customEnvironment = self.customEnvironments[self.helpLineSelector:getState()]
	local category = self.helpLineManager:getCategory(customEnvironment, section)	
	return self.helpLineManager:convertText(category.title, customEnvironment)
end

function CpHelpFrame:populateCellForItemInSection(list, section, index, cell) 
	local page = self:getPage(section, index)
	if page then
		cell:getAttribute("title"):setText(self.helpLineManager:convertText(page.title, page.customEnvironment))
		local icon = cell:getAttribute("icon")
		if page.iconSliceId ~= nil then
			icon:setVisible(true)
			icon:setImageSlice(nil, page.iconSliceId)
		else
			icon:setVisible(false)
		end
	end
end

function CpHelpFrame:getPage(categoryIndex, pageIndex) 
	local customEnvironment = self.customEnvironments[self.helpLineSelector:getState()]
	local category = self.helpLineManager:getCategory(customEnvironment, categoryIndex)
	return category.pages[pageIndex]
end

function CpHelpFrame:openPage(categoryIndex, pageIndex) 
	self:setSoundSuppressed(true)
	self.helpLineList:setSelectedItem(categoryIndex, pageIndex, true, 1)
	self:setSoundSuppressed(false)
end

function CpHelpFrame:updateContents(page)
	self.helpLineContentItem:unlinkElement()
	self.helpLineContentItemTitle:unlinkElement()
	for i = #self.helpLineContentBox.elements, 1, -1 do
		self.helpLineContentBox.elements[i]:delete()
	end
	if page == nil then
		return
	end
	self.helpLineTitleElement:setText(self.helpLineManager:convertText(page.title, page.customEnvironment))
	for _,paragraph in ipairs(page.paragraphs) do
		if paragraph.title ~= nil then
			local titleElement = self.helpLineContentItemTitle:clone(self.helpLineContentBox)
			titleElement:setText(self.helpLineManager:convertText(paragraph.title, page.customEnvironment))
		end
		local row = self.helpLineContentItem:clone(self.helpLineContentBox)
		local textElement = row:getDescendantByName("text")
		local textFullElement = row:getDescendantByName("textFullWidth")
		local imageElement = row:getDescendantByName("image")
		local textHeightFullHeight, textHeight = 0, 0
		if paragraph.noSpacing then
			row.margin = {0, 0, 0, 0}
		end
		if paragraph.image ~= nil then
			textFullElement:setVisible(false)
			if paragraph.text ~= nil then
				textElement:setText(self.helpLineManager:convertText(paragraph.text, page.customEnvironment))
				textHeight = textElement:getTextHeight(true)
				textElement:setSize(nil, textHeight)
			end
			local filename = Utils.getFilename(paragraph.image.filename, page.baseDirectory)
			imageElement:setImageFilename(filename)
			imageElement:setImageUVs(nil, unpack(paragraph.image.uvs))
			if imageElement.originalWidth == nil then
				imageElement.originalWidth = imageElement.absSize[1]
			end
			if paragraph.image.displaySize ~= nil then
				imageElement:setSize(paragraph.image.displaySize[1], paragraph.image.displaySize[2])
			else 
				if paragraph.text == nil then
					imageElement:setSize(row.absSize[1], row.absSize[1] * paragraph.image.aspectRatio * g_screenAspectRatio)
				else 
					imageElement:setSize(imageElement.originalWidth, nil)
				end
			end
			if paragraph.text ~= nil and paragraph.alignToImage then
				textElement:setSize(nil, imageElement.size[2])
				textElement.textVerticalAlignment = TextElement.VERTICAL_ALIGNMENT.MIDDLE
			end 
		else
			textElement:setVisible(false)
			imageElement:setVisible(false)
			if paragraph.text ~= nil then
				textFullElement:setText(self.helpLineManager:convertText(paragraph.text, paragraph.customEnvironment))
			end
			textHeightFullHeight = textFullElement:getTextHeight(true)
			textFullElement:setSize(nil, textHeightFullHeight)
		end
		local imageHeight = 0
		if paragraph.image then 
			imageHeight = imageElement.absSize[2] or 0
		end
		row:setSize(nil, math.max(textHeight, textHeightFullHeight, imageHeight))
		row:invalidateLayout()
	end
	self.helpLineContentBox:invalidateLayout()
end

function CpHelpFrame:delete()
	self.helpLineContentItem:delete()
	self.helpLineContentItemTitle:delete()
	for ix, clone in ipairs(self.helpLineDotBox.elements) do
		clone:delete()
		self.helpLineDotBox.elements[ix] = nil
	end
	self.helpLineDotTemplate:delete()

	CpHelpFrame:superClass().delete(self)
end