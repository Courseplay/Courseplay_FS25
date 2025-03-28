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
	self.brushCategory = {}
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

---@param editor CourseEditor
function CpConstructionFrame:setData(editor)
	self.editor = editor
	self.brushCategory = editor:getBrushCategory()
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

	self.menuButtonInfo = {
		table.clone(self.cpMenu.backButtonInfo),
		table.clone(self.cpMenu.nextPageButtonInfo),
		table.clone(self.cpMenu.prevPageButtonInfo)}
	self.menuButtonInfoByActions = {
		[InputAction.MENU_BACK] = self.menuButtonInfo[1],
		[InputAction.MENU_PAGE_NEXT] = self.menuButtonInfo[2],
		[InputAction.MENU_PAGE_PREV] = self.menuButtonInfo[3],
	}
end

function CpConstructionFrame:getOffsets()
	local lOffset = self.menuBox.absPosition[1] + self.menuBox.size[1]
	local bOffset = self.bottomBackground.absPosition[2] + self.bottomBackground.size[2]
	local rOffset = 1 - self.rightBackground.absPosition[1]
	local tOffset = self.topBackground.size[2]
	return lOffset, bOffset, rOffset, tOffset
end

function CpConstructionFrame:onFrameOpen()
	CpConstructionFrame:superClass().onFrameOpen(self)
	
	local texts = {}
	for _, tab in pairs(self.brushCategory) do 
		table.insert(texts, g_i18n:convertText(tab.name))
	end
	self.subCategorySelector:setTexts(texts)
	for ix, clone in ipairs(self.subCategoryDotBox.elements) do
		clone:delete()
		self.subCategoryDotBox.elements[ix] = nil
	end
	self.subCategoryDotBox:invalidateLayout()
	for i = 1, #self.subCategorySelector.texts do
		local dot = self.subCategoryDotPrefab:clone(self.subCategoryDotBox)
		FocusManager:loadElementFromCustomValues(dot)
		dot.getIsSelected = function ()
			return self.subCategorySelector:getState() == i
		end
	end
	self.subCategoryDotBox:invalidateLayout()
	self.categoryHeaderText:setText(self.editor:getTitle())

	-- g_inputBinding:setContext(CpConstructionFrame.INPUT_CONTEXT)
	local lOffset, bOffset, rOffset, tOffset = self:getOffsets()
	self.oldGameInfoDisplayPosition = {g_currentMission.hud.gameInfoDisplay:getPosition()}
	g_currentMission.hud.gameInfoDisplay:setPosition(
		self.oldGameInfoDisplayPosition[1] - rOffset, 
		self.oldGameInfoDisplayPosition[2] - tOffset)
	self.oldBlinkingWarningDisplayPosition = {g_currentMission.hud.warningDisplay:getPosition()}
	g_currentMission.hud.warningDisplay:setPosition(
		self.oldBlinkingWarningDisplayPosition[1] - rOffset, 
		self.oldBlinkingWarningDisplayPosition[2] - tOffset)

	local sideNotifications = g_currentMission.hud.sideNotifications
	local sx2 = sideNotifications.progressBarBgBottom:getPosition()
	local sx, sy = sideNotifications:getPosition()
	self.oldSideNotificationsPosition = {
		sx, sy, sx2}
	g_currentMission.hud.sideNotifications:setPosition(
		self.oldSideNotificationsPosition[1] - rOffset, 
		self.oldSideNotificationsPosition[2] - tOffset)
	sideNotifications.progressBarBgBottom:setPosition(
		self.oldSideNotificationsPosition[3] - rOffset, nil)
	sideNotifications.progressBarBgScale:setPosition(
		self.oldSideNotificationsPosition[3] - rOffset, nil)
	sideNotifications.progressBarBgTop:setPosition(
		self.oldSideNotificationsPosition[3] - rOffset, nil)

	self.camera:setTerrainRootNode(g_terrainNode)
	self.camera:setEdgeScrollingOffset(lOffset, bOffset, 1 - rOffset, 1 - tOffset)
	self.camera:activate()
	self.cursor:activate()
	local x, z = self.editor:getStartPosition()
	if x ~= nil and z ~= nil then
		self.camera:setCameraPosition(x, z)
	end
	self.isMouseMode = g_inputBinding.lastInputMode == GS_INPUT_HELP_MODE_KEYBOARD
	self:toggleCustomInputContext(true, self.INPUT_CONTEXT)
	g_messageCenter:subscribe(MessageType.INPUT_MODE_CHANGED, function(self)
		self.isMouseMode = g_inputBinding.lastInputMode == GS_INPUT_HELP_MODE_KEYBOARD
	end, self)
	self.originalInputHelpVisibility = g_currentMission.hud.inputHelp:getVisible()
	g_currentMission.hud:setInputHelpVisible(true, true)
	self.itemList:reloadData()
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
	g_currentMission.hud:setInputHelpVisible(self.originalInputHelpVisibility)
	g_currentMission.hud.gameInfoDisplay:setPosition(
		self.oldGameInfoDisplayPosition[1], self.oldGameInfoDisplayPosition[2])
	g_currentMission.hud.warningDisplay:setPosition(
		self.oldBlinkingWarningDisplayPosition[1], self.oldBlinkingWarningDisplayPosition[2])
	local sideNotifications = g_currentMission.hud.sideNotifications
	sideNotifications:setPosition(
		self.oldSideNotificationsPosition[1], self.oldSideNotificationsPosition[2])
	sideNotifications.progressBarBgBottom:setPosition(
		self.oldSideNotificationsPosition[3], nil)
	sideNotifications.progressBarBgScale:setPosition(
		self.oldSideNotificationsPosition[3], nil)
	sideNotifications.progressBarBgTop:setPosition(
		self.oldSideNotificationsPosition[3], nil)

	self.camera:setEdgeScrollingOffset(0, 0, 1, 1)
	self.cursor:deactivate()
	self.camera:deactivate()
	for _, id in ipairs(self.brushEvents) do
		g_inputBinding:removeActionEvent(id)
	end
	self.brushEvents = {}
	self.brushEventsByType = {}
	self:toggleCustomInputContext(false, self.INPUT_CONTEXT)
	if self.isMouseMode then
		g_inputBinding:setShowMouseCursor(true)
	end
	g_messageCenter:unsubscribeAll(self)
	CpConstructionFrame:superClass().onFrameClose(self)
end

function CpConstructionFrame:requestClose(callback)
	CpConstructionFrame:superClass().requestClose(self, callback)
	self.editor:onClickExit(function ()
		self.requestCloseCallback()
		self.requestCloseCallback = function () end
		self.cpMenu:updatePages()
	end)
	return not self.editor:getIsActive()
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
	g_currentMission.hud:updateBlinkingWarning(dt)
	g_currentMission.hud.sideNotifications:update(dt)
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

function CpConstructionFrame:drawInGame()
	local x, y, z = self.cursor:getPosition()
	self.editor:draw(x, y, z)
end

function CpConstructionFrame:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
	local lOffset, bOffset, rOffset, tOffset = self:getOffsets()

	self.isMouseInMenu = posX < lOffset or posX > (1 - rOffset) or
						 posY < bOffset or posY > (1 - tOffset)

	self.camera.mouseDisabled = self.isMouseInMenu
	self.cursor.mouseDisabled = self.isMouseInMenu
	self.camera:setMouseEdgeScrollingActive(not self.isMouseInMenu)
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
	g_inputBinding:setContextEventsActive(self.INPUT_CONTEXT, InputAction.MENU_ACCEPT, self.brush == nil)
	g_inputBinding:setContextEventsActive(self.INPUT_CONTEXT, InputAction.MENU_AXIS_UP_DOWN, self.brush == nil)
	g_inputBinding:setContextEventsActive(self.INPUT_CONTEXT, InputAction.MENU_AXIS_LEFT_RIGHT, self.brush == nil)
	g_inputBinding:setContextEventsActive(self.INPUT_CONTEXT, InputAction.MENU_PAGE_PREV, self.brush == nil)
	g_inputBinding:setContextEventsActive(self.INPUT_CONTEXT, InputAction.MENU_PAGE_NEXT, self.brush == nil)

	self.menuButtonInfoByActions[InputAction.MENU_PAGE_PREV].disabled = self.brush ~= nil
	self.menuButtonInfoByActions[InputAction.MENU_PAGE_NEXT].disabled = self.brush ~= nil
	self:setMenuButtonInfoDirty()
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
				g_inputBinding.events[id]:setIgnoreComboMask(true)
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
				g_inputBinding.events[id]:setIgnoreComboMask(true)
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
	if self.editor.registerActionEvents then 
		self.editor:registerActionEvents(self, self.brushEvents)
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
		updateText(self.brushEventsByType[self.BRUSH_EVENT_TYPES.PRIMARY_BUTTON], brush.getButtonPrimaryText)
		updateText(self.brushEventsByType[self.BRUSH_EVENT_TYPES.SECONDARY_BUTTON], brush.getButtonSecondaryText)
		updateText(self.brushEventsByType[self.BRUSH_EVENT_TYPES.TERTIARY_BUTTON], brush.getButtonTertiaryText)
		updateText(self.brushEventsByType[self.BRUSH_EVENT_TYPES.FOURTH_BUTTON], brush.getButtonFourthText)
		updateText(self.brushEventsByType[self.BRUSH_EVENT_TYPES.AXIS_PRIMARY], brush.getAxisPrimaryText)
		updateText(self.brushEventsByType[self.BRUSH_EVENT_TYPES.AXIS_SECONDARY], brush.getAxisSecondaryText)
		updateText(self.brushEventsByType[self.BRUSH_EVENT_TYPES.SNAPPING_BUTTON], brush.getButtonSnappingText)
	else 

	end
end

function CpConstructionFrame:onSubCategoryChanged()
	self.itemList:reloadData()
	self:setBrush(nil)
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
	local class = self.editor:getBrushClass(item.class)
	local brush = class(self.cursor, self.camera, self.editor)
	brush.item = item
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
		local icon = self.currentSelectedBrushTitle:getDescendantByName("icon")
		icon:setVisible(self.brush~=nil and self.brush.item.iconSliceId ~= nil)
		local text = self.currentSelectedBrushTitle:getDescendantByName("text")
		if self.brush then 
			self.brush:activate()
			text:setText(self.brush:getTitle())
			icon:setImageSlice(nil, self.brush.item.iconSliceId)
			--- TODO Copy/restore old state here ..
		else
			text:setText("---")
		end
		self:updateActionEvents(self.brush)
		self:updateActionEventTexts(self.brush)
		self.camera:setMovementDisabledForGamepad(self.brush == nil)
	end
end