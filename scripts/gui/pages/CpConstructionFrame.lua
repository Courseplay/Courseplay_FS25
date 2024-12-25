CpConstructionFrame = {
    INPUT_CONTEXT = "CP_CONSTRUCTION_MENU"
}
local CpConstructionFrame_mt = Class(CpConstructionFrame, TabbedMenuFrameElement)

function CpConstructionFrame.new(target, custom_mt)
	local self = TabbedMenuFrameElement.new(target, custom_mt or CpConstructionFrame_mt)
	self.noBackgroundNeeded = true
	self.camera = GuiTopDownCamera.new()
	self.cursor = GuiTopDownCursor.new()
	self.menuEvents = {}

	self.categorySchema = XMLSchema.new("cpConstructionCategories")
	self.categorySchema:register(XMLValueType.STRING, "Category.Tab(?)#name", "Tab name")
	self.categorySchema:register(XMLValueType.STRING, "Category.Tab(?)#iconSliceId", "Tab icon slice id")
	self.categorySchema:register(XMLValueType.STRING, "Category.Tab(?).Brush(?)#name", "Brush name")
	self.categorySchema:register(XMLValueType.STRING, "Category.Tab(?).Brush(?)#class", "Brush class")
	self.categorySchema:register(XMLValueType.STRING, "Category.Tab(?).Brush(?)#iconSliceId", "Brush icon slice id")
	self.categorySchema:register(XMLValueType.BOOL, "Category.Tab(?).Brush(?)#isCourseOnly", "Is course only?", false)

	self:loadBrushCategory()
	return self
end

function CpConstructionFrame.createFromExistingGui(gui, guiName)
	local newGui = CpConstructionFrame.new()

	g_gui.frames[gui.name].target:delete()
	g_gui.frames[gui.name]:delete()
	g_gui:loadGui(gui.xmlFilename, guiName, newGui, true)

	return newGui
end

function CpConstructionFrame.setupGui()
	local frame = CpConstructionFrame.new()
	g_gui:loadGui(Utils.getFilename("config/gui/pages/ConstructionFrame.xml", Courseplay.BASE_DIRECTORY),
	 	"CpConstructionFrame", frame, true)
end

function CpConstructionFrame:delete()
	self.camera:delete()
	self.cursor:delete()
	self.booleanPrefab:delete()
	self.multiTextPrefab:delete()
	self.sectionHeaderPrefab:delete()
	self.selectorPrefab:delete()
	self.containerPrefab:delete()
	self.subCategoryDotPrefab:delete()
	CpConstructionFrame:superClass().delete(self)
end

function CpConstructionFrame:loadBrushCategory()
	self.brushCategory = {}
	local path = Utils.getFilename("config/EditorCategories.xml", g_Courseplay.BASE_DIRECTORY)
	local xmlFile = XMLFile.load("cpConstructionCategories", path, self.categorySchema)
	xmlFile:iterate("Category.Tab", function (_, tabKey)
		local tab = {
			name = xmlFile:getValue(tabKey .. "#name"),
			iconSliceId = xmlFile:getValue(tabKey .. "#iconSliceId"),
			brushes = {}
		}
		xmlFile:iterate(tabKey .. ".Brush", function (_, brushKey)
			local brush = {
				name = xmlFile:getValue(brushKey .. "#name"),
				class = xmlFile:getValue(brushKey .. "#class"),
				iconSliceId = xmlFile:getValue(brushKey .. "#iconSliceId"),
				isCourseOnly = xmlFile:getValue(brushKey .. "#isCourseOnly")
			}
			table.insert(tab.brushes, brush)
		end)
		table.insert(self.brushCategory, tab)
	end)
	xmlFile:delete()
end

function CpConstructionFrame:loadFromXMLFile(xmlFile, baseKey)
	
end

function CpConstructionFrame:saveToXMLFile(xmlFile, baseKey)
	
end

function CpConstructionFrame:initialize(menu)
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

	self.subCategoryDotPrefab:unlinkElement()
	FocusManager:removeElement(self.subCategoryDotPrefab)
end

function CpConstructionFrame:onFrameOpen()
	CpConstructionFrame:superClass().onFrameOpen(self)
	if not self.wasOpened then
		local texts = {}
		for _, tab in pairs(self.brushCategory) do 
			table.insert(texts, tab.name)
		end
		self.subCategorySelector:setTexts(texts)
		for i = 1, #self.subCategorySelector.texts do
			local dot = self.subCategoryDotPrefab:clone(self.subCategoryDotBox)
			FocusManager:loadElementFromCustomValues(dot)
			dot.getIsSelected = function ()
				return self.subCategorySelector:getState() == i
			end
		end
		self.subCategoryDotBox:invalidateLayout()
		self.wasOpened = true
	end
	self.categoryHeaderText:setText(g_courseEditor:getTitle())

	-- g_inputBinding:setContext(CpConstructionFrame.INPUT_CONTEXT)
	local lOffset = self.menuBox.absPosition[1] + self.menuBox.size[1]
	local bOffset = self.bottomBackground.absPosition[2] + self.bottomBackground.size[2]
	local rOffset = self.rightBackground.size[1]
	local tOffset = self.topBackground.size[2]
	self.oldGameInfoDisplayPosition = {g_currentMission.hud.gameInfoDisplay:getPosition()}
	g_currentMission.hud.gameInfoDisplay:setPosition(
		self.oldGameInfoDisplayPosition[1] - rOffset, self.oldGameInfoDisplayPosition[2] - tOffset)
	self.oldBlinkingWarningDisplayPosition = {g_currentMission.hud.warningDisplay:getPosition()}
	g_currentMission.hud.warningDisplay:setPosition(
		self.oldBlinkingWarningDisplayPosition[1] - rOffset, self.oldBlinkingWarningDisplayPosition[2] - tOffset)
	self.oldSideNotificationsPosition = {g_currentMission.hud.sideNotifications:getPosition()}
	g_currentMission.hud.sideNotifications:setPosition(
		self.oldSideNotificationsPosition[1] - rOffset, self.oldSideNotificationsPosition[2] - tOffset)

	self.camera:setTerrainRootNode(g_terrainNode)
	self.camera:setEdgeScrollingOffset(lOffset, bOffset, 1 - rOffset, 1 - tOffset)
	self.camera:activate()
	self.cursor:activate()
	self.isMouseMode = g_inputBinding.lastInputMode == GS_INPUT_HELP_MODE_KEYBOARD

	g_messageCenter:subscribe(MessageType.INPUT_MODE_CHANGED, function (self)
			self.isMouseMode = inputMode[1] == GS_INPUT_HELP_MODE_KEYBOARD
		end, self)
	self:updateActionEvents()
	self:onSubCategoryChanged()

	if g_localPlayer ~= nil then
		local isFirstPerson
		if g_localPlayer:getCurrentVehicle() == nil then
			isFirstPerson = g_localPlayer.camera.isFirstPerson
		else
			isFirstPerson = false
		end
		self.wasFirstPerson = isFirstPerson
		if self.wasFirstPerson then
			g_localPlayer.graphicsComponent:setModelVisibility(true)
		end
	end
end

function CpConstructionFrame:onFrameClose()
	if g_localPlayer ~= nil and self.wasFirstPerson then
		g_localPlayer.graphicsComponent:setModelVisibility(false)
		self.wasFirstPerson = nil
	end
	g_currentMission.hud.gameInfoDisplay:setPosition(
		self.oldGameInfoDisplayPosition[1], self.oldGameInfoDisplayPosition[2])
	g_currentMission.hud.warningDisplay:setPosition(
		self.oldBlinkingWarningDisplayPosition[1], self.oldBlinkingWarningDisplayPosition[2])
	g_currentMission.hud.sideNotifications:setPosition(
		self.oldSideNotificationsPosition[1], self.oldSideNotificationsPosition[2])
		
	self.camera:setEdgeScrollingOffset(0, 0, 1, 1)
	self.cursor:deactivate()
	self.camera:deactivate()
	g_inputBinding:setShowMouseCursor(true)
	-- g_inputBinding:revertContext()
	g_messageCenter:unsubscribeAll(self)
	CpConstructionFrame:superClass().onFrameClose(self)
end

function CpConstructionFrame:requestClose(callback)
	g_courseEditor:deactivate()
	return true
end

function CpConstructionFrame:onClickBack()
	
	return true
end

function CpConstructionFrame:update(dt)
	CpConstructionFrame:superClass().update(self, dt)
	g_currentMission.hud:updateBlinkingWarning(self)
	g_currentMission.hud.sideNotifications:update(self)
	self.camera:setCursorLocked(self.cursor.isCatchingCursor)
	self.camera:update(dt)
	if self.isMouseMode and self.isMouseInMenu then
		self.cursor:setCameraRay(nil)
	else
		self.cursor:setCameraRay(self.camera:getPickRay())
	end
	self.cursor:update(dt)
	-- self:updateMarqueeAnimation(dt)
end

function CpConstructionFrame:draw()
	CpConstructionFrame:superClass().draw(self)
	-- g_currentMission.hud:drawInputHelp(p39.helpDisplay.position[1], p39.helpDisplay.position[2])
	g_currentMission.hud.gameInfoDisplay:draw()
	g_currentMission.hud:drawSideNotification()
	g_currentMission.hud:drawBlinkingWarning()
	self.cursor:draw()
end

function CpConstructionFrame:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
	self.isMouseInMenu = posX < (self.menuBox.absPosition[1] + self.menuBox.size[1]) or
		posY < (self.cpMenu.buttonsPanel.absPosition[2] + self.cpMenu.buttonsPanel.size[2])
	self.camera.mouseDisabled = self.isMouseInMenu
	self.cursor.mouseDisabled = self.isMouseInMenu
	self.camera:setMouseEdgeScrollingActive(true)
	self.camera:mouseEvent(posX, posY, isDown, isUp, button)
	self.cursor:mouseEvent(posX, posY, isDown, isUp, button)
	return CpConstructionFrame:superClass().mouseEvent(self, posX, posY, isDown, isUp, button, eventUsed)
end

function CpConstructionFrame:registerMenuActionEvents(active)
	-- self.menuEvents = {}
	-- local _, id = g_inputBinding:registerActionEvent(InputAction.MENU_ACCEPT, self, function (self)
	-- 		if self.isMouseMode then
	-- 			self.dragIsLocked = true
	-- 			g_gui:notifyControls("MENU_ACCEPT")
	-- 		else
	-- 			-- p70:onButtonPrimary()
	-- 		end
	-- 	end, false, true, false, true)
	-- g_inputBinding:setActionEventTextPriority(id, GS_PRIO_VERY_LOW)
	-- g_inputBinding:setActionEventTextVisibility(id, false)
	-- self.acceptButtonEvent = id
	-- table.insert(self.menuEvents, id)
	-- local _, id = g_inputBinding:registerActionEvent(InputAction.MENU_BACK, self, function ()
	-- 		self:changeScreen(nil)
	-- 		-- if p71.brush:canCancel() then
	-- 		-- 	p71.brush:cancel()
	-- 		-- 	return
	-- 		-- elseif p71.brush == p71.destructBrush then
	-- 		-- 	p71.destructMode = false
	-- 		-- 	p71:setBrush(p71.previousBrush)
	-- 		-- 	return
	-- 		-- elseif p71.configurations == nil then
	-- 		-- 	if p71.brush.isSelector then
	-- 		-- 		p71:changeScreen(nil)
	-- 		-- 	else
	-- 		-- 		p71:setBrush(p71.selectorBrush)
	-- 		-- 	end
	-- 		-- else
	-- 		-- 	p71:onShowConfigs()
	-- 		-- 	return
	-- 		-- end
	-- 	end, false, true, false, true)
	-- g_inputBinding:setActionEventTextPriority(id, GS_PRIO_VERY_LOW)
	-- self.backButtonEvent = id
	-- table.insert(self.menuEvents, id)
	-- if active then
	-- 	local _, id = g_inputBinding:registerActionEvent(InputAction.MENU_PAGE_PREV, self, function (self)
			
	-- 		end, false, true, false, true)
	-- 	g_inputBinding:setActionEventTextVisibility(id, false)
	-- 	table.insert(self.menuEvents, id)
	-- 	local _, id = g_inputBinding:registerActionEvent(InputAction.MENU_PAGE_NEXT, self, function (self)
			
	-- 		end, false, true, false, true)
	-- 	g_inputBinding:setActionEventTextVisibility(id, false)
	-- 	table.insert(self.menuEvents, id)
	-- end
end

function CpConstructionFrame:removeMenuActionEvents()
	for _, id in ipairs(self.menuEvents) do
		g_inputBinding:removeActionEvent(id)
	end
end

function CpConstructionFrame:updateActionEvents()
	self:removeMenuActionEvents()
	-- self:removeBrushActionEvents()
	self.camera:removeActionEvents()
	self.cursor:removeActionEvents()
	self.camera:registerActionEvents()
	self.cursor:registerActionEvents()
end

function CpConstructionFrame:onSubCategoryChanged()
	self.itemList:reloadData()
end

function CpConstructionFrame:getNumberOfItemsInSection(list, section)
	local elements = self.brushCategory[self.subCategorySelector:getState()]
	return elements == nil and 0 or #elements.brushes
end

function CpConstructionFrame:populateCellForItemInSection(list, section, index, cell)
	local item = self.brushCategory[self.subCategorySelector:getState()].brushes[index]
	-- cell:getAttribute("price"):setValue(g_i18n:formatMoney(item.price, 0, true, true))
	cell:getAttribute("terrainLayer"):setVisible(false)
	cell:getAttribute("icon"):setVisible(item.iconSliceId ~= nil)
	cell:getAttribute("icon"):setImageSlice(nil, item.iconSliceId)
end

function CpConstructionFrame:onListSelectionChanged(list, section, index)
	-- if not g_gui.currentlyReloading then
	-- 	if p172 == self.itemList then
	-- 		local v174 = self.items[self.currentCategory][self.currentTab][p173]
	-- 		if v174 == nil then
	-- 			self:assignItemAttributeData(nil)
	-- 			return
	-- 		end
	-- 		self.lastSelectionIndex = p173
	-- 		self:assignItemAttributeData(v174)
	-- 	end
	-- end
end

function CpConstructionFrame:onListHighlightChanged(list, section, index)
	-- if not g_gui.currentlyReloading then
	-- 	if p176 == p175.itemList then
	-- 		local v178 = p177 or p175.lastSelectionIndex
	-- 		local v179 = p175.items[p175.currentCategory][p175.currentTab][v178]
	-- 		if v179 == nil then
	-- 			p175:assignItemAttributeData(nil)
	-- 			return
	-- 		end
	-- 		p175:assignItemAttributeData(v179)
	-- 	end
	-- end
end

function CpConstructionFrame:onClickItem(list, section, index, cell)
	-- local v181 = self.items[self.currentCategory][self.currentTab][self.itemList.selectedIndex]
	-- local v182 = v181.brushClass.new(nil, self.cursor)
	-- if v181.brushParameters ~= nil then
	-- 	v182:setStoreItem(v181.storeItem)
	-- 	local v183 = v181.brushParameters
	-- 	v182:setParameters(unpack(v183))
	-- 	v182.uniqueIndex = v181.uniqueIndex
	-- end
	-- self.destructMode = false
	-- self:setBrush(v182, true)
end