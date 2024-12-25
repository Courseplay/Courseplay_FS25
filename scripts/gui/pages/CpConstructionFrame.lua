CpConstructionFrame = {
    INPUT_CONTEXT = "CP_CONSTRUCTION_MENU",
	BRUSH_EVENT_TYPES = {
		PRIMARY_BUTTON = 1,
		SECONDARY_BUTTON = 2,
		TERTIARY_BUTTON = 3,
		FOURTH_BUTTON = 4,
		AXIS_PRIMARY = 5,
		AXIS_SECONDARY = 6,
		SNAPPING_BUTTON = 7
	}
}
local CpConstructionFrame_mt = Class(CpConstructionFrame, TabbedMenuFrameElement)

function CpConstructionFrame.new(target, custom_mt)
	local self = TabbedMenuFrameElement.new(target, custom_mt or CpConstructionFrame_mt)
	self.noBackgroundNeeded = true
	self.hasCustomMenuButtons = true
	self.camera = GuiTopDownCamera.new()
	self.cursor = GuiTopDownCursor.new()
	self.brush = nil
	self.brushEvents = {}

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
			local name = xmlFile:getValue(brushKey .. "#name")
			local brush = {
				name = name,
				class = xmlFile:getValue(brushKey .. "#class"),
				iconSliceId = xmlFile:getValue(brushKey .. "#iconSliceId"),
				isCourseOnly = xmlFile:getValue(brushKey .. "#isCourseOnly"),
				brushParameters = {
					g_courseEditor,
					CourseEditor.TRANSLATION_PREFIX .. tab.name .. "_" .. name 
				}
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
	self.onClickBackCallback = menu.clickBackCallback

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
		self.oldGameInfoDisplayPosition[1] - rOffset, 
		self.oldGameInfoDisplayPosition[2] - tOffset)
	self.oldBlinkingWarningDisplayPosition = {g_currentMission.hud.warningDisplay:getPosition()}
	g_currentMission.hud.warningDisplay:setPosition(
		self.oldBlinkingWarningDisplayPosition[1] - rOffset, 
		self.oldBlinkingWarningDisplayPosition[2] - tOffset)
	self.oldSideNotificationsPosition = {g_currentMission.hud.sideNotifications:getPosition()}
	g_currentMission.hud.sideNotifications:setPosition(
		self.oldSideNotificationsPosition[1] - rOffset, 
		self.oldSideNotificationsPosition[2] - tOffset)

	self.camera:setTerrainRootNode(g_terrainNode)
	self.camera:setEdgeScrollingOffset(lOffset, bOffset, 1 - rOffset, 1 - tOffset)
	self.camera:activate()
	self.cursor:activate()
	local x, z = g_courseEditor:getStartPosition()
	if x ~= nil and z ~= nil then
		self.camera:setCameraPosition(x, z)
	end
	self.isMouseMode = g_inputBinding.lastInputMode == GS_INPUT_HELP_MODE_KEYBOARD
	self:toggleCustomInputContext(true, self.INPUT_CONTEXT)

	self:onSubCategoryChanged()
	self:setBrush(nil, true)
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
	for _, id in ipairs(self.brushEvents) do
		g_inputBinding:removeActionEvent(id)
	end
	self.brushEvents = {}
	self.brushEventsByType = {}
	self:toggleCustomInputContext(false, self.INPUT_CONTEXT)
	-- g_inputBinding:setShowMouseCursor(true)
	g_messageCenter:unsubscribeAll(self)
	CpConstructionFrame:superClass().onFrameClose(self)
end

function CpConstructionFrame:requestClose(callback)
	g_courseEditor:deactivate()
	return true
end

function CpConstructionFrame:onClickBack()
	if self.brush == nil then 
		return true
	elseif self.brush:canCancel() then 
		self.brush:cancel()
	else 
		self:setBrush(nil)
	end
	return false
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
	if self.brush then
		self.brush:update(dt)
		if self.brush.inputTextDirty then
			self:updateActionEventTexts(self.brush)
			self.brush.inputTextDirty = false
		end
	end
	-- self:updateMarqueeAnimation(dt)
end

function CpConstructionFrame:draw()
	CpConstructionFrame:superClass().draw(self)
	g_currentMission.hud:drawInputHelp(self.helpDisplay.position[1], self.helpDisplay.position[2])
	g_currentMission.hud.gameInfoDisplay:draw()
	g_currentMission.hud:drawSideNotification()
	g_currentMission.hud:drawBlinkingWarning()
	self.cursor:draw()
	if self.brush then 
		self.brush:draw()
	end
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


function CpConstructionFrame:updateActionEvents(brush)
	for _, id in ipairs(self.brushEvents) do
		g_inputBinding:removeActionEvent(id)
	end
	self.brushEvents = {}
	self.brushEventsByType = {}
	g_inputBinding:setContextEventsActive(self.INPUT_CONTEXT_NAME, InputAction.MENU_ACCEPT, self.brush == nil)
	g_inputBinding:setContextEventsActive(self.INPUT_CONTEXT_NAME, InputAction.MENU_AXIS_UP_DOWN, self.brush == nil)
	g_inputBinding:setContextEventsActive(self.INPUT_CONTEXT_NAME, InputAction.MENU_AXIS_LEFT_RIGHT, self.brush == nil)
	g_inputBinding:setContextEventsActive(self.INPUT_CONTEXT_NAME, InputAction.MENU_PAGE_PREV, self.brush == nil)
	g_inputBinding:setContextEventsActive(self.INPUT_CONTEXT_NAME, InputAction.MENU_PAGE_NEXT, self.brush == nil)
	if brush then
		if brush.supportsPrimaryButton then
			local _, id
			if brush.supportsPrimaryDragging then
				_, id = g_inputBinding:registerActionEvent(InputAction.CONSTRUCTION_ACTION_PRIMARY, self, function(self, action, inputValue)
						if not self.isMouseInMenu and self.brush then 
							local isDown = inputValue == 1 and self.previousPrimaryDragValue ~= 1
							local isDrag = inputValue == 1 and self.previousPrimaryDragValue == 1
							local isUp = inputValue == 0
							self.previousPrimaryDragValue = inputValue
							if self.dragIsLocked then
								if isUp then
									self.dragIsLocked = false
								end
							else
								self.brush:onButtonPrimary(isDown, isDrag, isUp)
							end
						end
					end, true, true, true, true)
			else
				_, id = g_inputBinding:registerActionEvent(InputAction.CONSTRUCTION_ACTION_PRIMARY, self, function(self, action, inputValue)
						if not self.isMouseInMenu and self.brush then 
							self.brush:onButtonPrimary()
						end
					end, false, true, false, true)
			end
			table.insert(self.brushEvents, id)
			self.brushEventsByType[self.BRUSH_EVENT_TYPES.PRIMARY_BUTTON] = id
			g_inputBinding:setActionEventTextPriority(id, GS_PRIO_VERY_HIGH)
		end
		if brush.supportsSecondaryButton then
			local _, id
			if brush.supportsSecondaryDragging then
				_, id = g_inputBinding:registerActionEvent(InputAction.CONSTRUCTION_ACTION_SECONDARY, self, function(self, action, inputValue)
					if not self.isMouseInMenu and self.brush then 
						local isDown = inputValue == 1 and self.previousSecondaryDragValue ~= 1
						local isDrag = inputValue == 1 and self.previousSecondaryDragValue == 1
						local isUp = inputValue == 0
						self.previousSecondaryDragValue = inputValue
						if self.dragIsLocked then
							if isUp then
								self.dragIsLocked = false
							end
						else
							self.brush:onButtonSecondary(isDown, isDrag, isUp)
						end
					end
				end, true, true, true, true)
			else
				_, id = g_inputBinding:registerActionEvent(InputAction.CONSTRUCTION_ACTION_SECONDARY, self, function(self, action, inputValue)
					if not self.isMouseInMenu and self.brush then 
						self.brush:onButtonSecondary()
					end
				end, false, true, false, true)
			end
			table.insert(self.brushEvents, id)
			self.brushEventsByType[self.BRUSH_EVENT_TYPES.SECONDARY_BUTTON] = id
			g_inputBinding:setActionEventTextPriority(v86, GS_PRIO_VERY_HIGH)
		end
		if brush.supportsTertiaryButton then
			local _, id = g_inputBinding:registerActionEvent(InputAction.CONSTRUCTION_ACTION_TERTIARY, self, function(self, action, inputValue)
					if self.brush then 
						self.brush:onButtonTertiary()
					end
				end, false, true, false, true)
			table.insert(self.brushEvents, id)
			self.brushEventsByType[self.BRUSH_EVENT_TYPES.TERTIARY_BUTTON] = id
			g_inputBinding:setActionEventTextPriority(id, GS_PRIO_HIGH)
		end
		if brush.supportsFourthButton then
			local _, id = g_inputBinding:registerActionEvent(InputAction.CONSTRUCTION_ACTION_FOURTH, self, function (self, action, inputValue)
					if self.brush then 
						self.brush:onButtonFourth()
					end
				end, false, true, false, true)
			table.insert(self.brushEvents, id)
			self.brushEventsByType[self.BRUSH_EVENT_TYPES.FOURTH_BUTTON] = id
			g_inputBinding:setActionEventTextPriority(id, GS_PRIO_HIGH)
		end
		if brush.supportsPrimaryAxis then
			local _, id = g_inputBinding:registerActionEvent(InputAction.AXIS_CONSTRUCTION_ACTION_PRIMARY, self, function (self, action, inputValue)
				if self.brush then 
					self.brush:onAxisPrimary(inputValue)
				end
			end, false, not brush.primaryAxisIsContinuous, brush.primaryAxisIsContinuous, true)
			table.insert(self.brushEvents, id)
			self.brushEventsByType[self.BRUSH_EVENT_TYPES.AXIS_PRIMARY] = id
			g_inputBinding:setActionEventTextPriority(id, GS_PRIO_HIGH)
		end
		if brush.supportsSecondaryAxis then
			local _, id = g_inputBinding:registerActionEvent(InputAction.AXIS_CONSTRUCTION_ACTION_SECONDARY, self, function (self, action, inputValue)
				if self.brush then 
					self.brush:onAxisSecondary(inputValue)
				end
			end, false, not brush.secondaryAxisIsContinuous, brush.secondaryAxisIsContinuous, true)
			table.insert(self.brushEvents, id)
			self.brushEventsByType[self.BRUSH_EVENT_TYPES.AXIS_SECONDARY] = id
			g_inputBinding:setActionEventTextPriority(id, GS_PRIO_HIGH)
		end
		if brush.supportsSnapping then
			local _, id = g_inputBinding:registerActionEvent(InputAction.CONSTRUCTION_ACTION_SNAPPING, self, function (self, action, inputValue)
				if self.brush then 
					self.brush:onButtonSnapping()
				end
			end, false, true, false, true)
			table.insert(self.brushEvents, id)
			self.brushEventsByType[self.BRUSH_EVENT_TYPES.SNAPPING_BUTTON] = id
			g_inputBinding:setActionEventTextPriority(id, GS_PRIO_HIGH)
		end
	end	
end

function CpConstructionFrame:updateActionEventTexts(brush)
	if brush then 
		local updateText = function (event, getText)
			if event then 
				local text = getText(brush)
				if text ~= nil then
					g_inputBinding:setActionEventText(event, g_i18n:convertText(text))
				end
				g_inputBinding:setActionEventTextVisibility(event, text ~= nil)
			end
		end
		updateText(brush.primaryBrushEvent, brush.getButtonPrimaryText)
		updateText(brush.secondaryBrushEvent, brush.getButtonSecondaryText)
		updateText(brush.tertiaryBrushEvent, brush.getButtonTertiaryText)
		updateText(brush.fourthBrushEvent, brush.getButtonFourthText)
		updateText(brush.primaryBrushAxisEvent, brush.getAxisPrimaryText)
		updateText(brush.secondaryBrushAxisEvent, brush.getAxisSecondaryText)
		updateText(brush.snappingBrushEvent, brush.getButtonSnappingText)
	else 

	end
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
	local item = self.brushCategory[self.subCategorySelector:getState()].brushes[index]
	local class = CpUtil.getClassObject(item.class)
	local brush = class.new(nil, self.cursor)
	if item.brushParameters ~= nil then
		brush:setStoreItem(item.storeItem)
		brush:setParameters(unpack(item.brushParameters))
		brush.uniqueIndex = item.uniqueIndex
	end
	self:setBrush(brush)
end

function CpConstructionFrame:setBrush(brush, force)
	if brush ~= self.brush or force then
		if self.brush ~= nil then
			self.brush:deactivate()
			self.brush:delete()
		end
		self.brush = brush
		self.camera:removeActionEvents()
		self.cursor:removeActionEvents()
		self.camera:registerActionEvents()
		self.cursor:registerActionEvents()
		if self.brush then 
			self.brush:activate()
			--- TODO Copy/restore old state here ..
		end
		self:updateActionEvents(self.brush)
		self:updateActionEventTexts(self.brush)
		self.camera:setMovementDisabledForGamepad(self.brush == nil)
	end
end