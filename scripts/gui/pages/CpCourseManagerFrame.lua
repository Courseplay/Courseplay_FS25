

--[[
	This frame is a page for the course manager.
]]--

CpCourseManagerFrame = {}

CpCourseManagerFrame.translations = {
	title = "CP_courseManager_title",

	loadCourse = "CP_courseManager_load_courses",
	saveCourse = "CP_courseManager_save_courses",
	clearCurrentCourse = "CP_courseManager_clear_current_courses",
	editCourse = "CP_courseManager_edit_course",

	changeMode = "CP_courseManager_change_mode",
	activate = "CP_courseManager_activate",

	deleteEntry = "CP_courseManager_delete_entry",
	renameEntry = "CP_courseManager_rename_entry",
	createDirectory = "CP_courseManager_create_directory",
	moveEntry = "CP_courseManager_move_entry",
	copyEntry = "CP_courseManager_copy_entry",
	
	folderDialogTitle = "CP_courseManager_folder_dialog",
	courseDialogTitle = "CP_courseManager_course_dialog",

	deleteWarning = "CP_courseManager_deleteWarning",
	editWarning = "CP_courseManager_editCourseWarning",

	deleteError = "CP_courseManager_deleteError",
	entryExistAlreadyError = "CP_courseManager_entryExistAlreadyError",
	invalidNameError = "CP_courseManager_invalidNameError",
	noAccessError = "CP_courseManager_noAccessError",
	targetIsNoFolder = "CP_courseManager_targetIsNoFolderError",
	targetIsNoCourse = "CP_courseManager_targetIsNoCourseError",

	basicSettings = "CP_courseManager_basicSettings",
	advancedSettings = "CP_courseManager_advancedSettings",
}

CpCourseManagerFrame.minMode = 1
CpCourseManagerFrame.maxMode = 2

CpCourseManagerFrame.actionStates = {
	disabled = 0,
	createDirectory = 1,
	moveEntrySelect = 2,
	moveEntryDestination = 3,
	deleteEntry = 4,
	renameEntry = 5,
	copyEntrySelect = 6,
	copyEntryDestination = 7,
}

CpCourseManagerFrame.colors = {
	move = {0, 0, 0, 0.35},
	default = {0.3140, 0.8069, 1.0000, 0.02}
}

local CpCourseManagerFrame_mt = Class(CpCourseManagerFrame, TabbedMenuFrameElement)

function CpCourseManagerFrame.new(target, custom_mt)
	local self = TabbedMenuFrameElement.new(target, custom_mt or CpCourseManagerFrame_mt)

	return self
end

function CpCourseManagerFrame.createFromExistingGui(gui, guiName)
	local newGui = CpCourseManagerFrame.new(nil, nil)

	g_gui.frames[gui.name].target:delete()
	g_gui.frames[gui.name]:delete()
	g_gui:loadGui(gui.xmlFilename, guiName, newGui, true)

	return newGui
end

function CpCourseManagerFrame.setupGui()
	local courseManagerFrame = CpCourseManagerFrame.new()
	g_gui:loadGui(Utils.getFilename("config/gui/pages/CourseManagerFrame.xml", Courseplay.BASE_DIRECTORY),
	 			 "CpCourseManagerFrame", courseManagerFrame, true)
end

function CpCourseManagerFrame.registerXmlSchema(xmlSchema, xmlKey)
	
end

function CpCourseManagerFrame:loadFromXMLFile(xmlFile, baseKey)
   
end

function CpCourseManagerFrame:saveToXMLFile(xmlFile, baseKey)
   
end

function CpCourseManagerFrame:setCourseStorage(courseStorage)
	self.courseStorage = courseStorage
end

function CpCourseManagerFrame:getCurrentEntry()
	local layout = FocusManager:getFocusedElement()
	if not layout then 
		return
	end
	if layout.getSelectedElement then
		local element = layout:getSelectedElement()
		return element.viewEntry
	end
end

function CpCourseManagerFrame:initialize(menu)	
	self.cpMenu = menu
	--- Changes the input actions.
	self.modeButton = {
		profile = "buttonActivate",
		inputAction = InputAction.MENU_ACTIVATE,
		text = g_i18n:getText(self.translations.changeMode),
		callback = function ()
			self.onClickChangeMode(self)
			self:updateMenuButtons()
		end,
		callbackDisabled = self.modeDisabled,
	}
	self.activateButton = {
		profile = "buttonSelect",
		inputAction = InputAction.MENU_ACTIVATE,
		text = g_i18n:getText(self.translations.activate),
		callback = function ()
			self.onClickActivate(self)
			self:updateMenuButtons()
		end,
		callbackDisabled = self.activateDisabled,
	}

	self.modes = {
		{
			--- Loads the current course
			{
				profile = "buttonActivate",
				inputAction = InputAction.MENU_EXTRA_1,
				text = g_i18n:getText(self.translations.loadCourse),
				callback = function ()
					local viewEntry = self:getCurrentEntry()
					if viewEntry then
						if not viewEntry:isDirectory() then 
							local vehicle = self.cpMenu:getCurrentVehicle()
							if not vehicle:appendLoadedCpCourse(viewEntry:getEntity()) then 
								--TODO_25 Error message missing!
							end
						else 
							self.showInfoDialog(
								self.translations.targetIsNoCourse, viewEntry)
						end
						self:updateMenuButtons()
					end
				end,
				callbackDisabled = self.loadCourseDisabled,
			},
			---  Clears the current course
			{
				profile = "buttonActivate",
				inputAction = InputAction.MENU_CANCEL,
				text = g_i18n:getText(self.translations.clearCurrentCourse),
				callback = function ()
					self.onClickClearCurrentCourse(self)
					self:updateMenuButtons()
				end,
				callbackDisabled = self.clearCurrentCourseDisabled
			},
			---  Opens the course editor.
			{
				profile = "buttonActivate",
				inputAction = InputAction.MENU_CANCEL,
				text = g_i18n:getText(self.translations.editCourse),
				callback = function ()
					self.onClickOpenEditor(self)
					self:updateMenuButtons()
				end,
				callbackDisabled = self.openEditorDisabled
			},
			--- Saves the current courses.
			{
				profile = "buttonActivate",
				inputAction = InputAction.MENU_EXTRA_1,
				text = g_i18n:getText(self.translations.saveCourse),
				callback = function ()
					local viewEntry = self:getCurrentEntry()
					if viewEntry then
						if viewEntry:isDirectory() then 
							self.showInputTextDialog(
								self, self.translations.courseDialogTitle,
								self.onClickSaveEntryDialog, viewEntry)
						else 
							self.showInfoDialog(
								self.translations.targetIsNoFolder, viewEntry)
						end
						self:updateMenuButtons()
					end
				end,
				callbackDisabled = self.saveCourseDisabled,
			},
			--- Creates a new directory
			{
				profile = "buttonActivate",
				inputAction = InputAction.MENU_EXTRA_2,
				text = g_i18n:getText(self.translations.createDirectory),
				callback = function ()
					local viewEntry = self:getCurrentEntry()
					CpCourseManagerFrame.showInputTextDialog(
						self, self.translations.folderDialogTitle,
						self.onClickCreateDirectoryDialog, viewEntry)
				--	self.actionState = CpCourseManagerFrame.actionStates.createDirectory
					self:updateMenuButtons()
				end,
				callbackDisabled = self.createDirectoryDisabled,
			},
		},
		{
			--- Moves an entry
			{
				profile = "buttonActivate",
				inputAction = InputAction.MENU_CANCEL,
				text = g_i18n:getText(self.translations.moveEntry),
				callback = function ()
					self.actionState = self.actionStates.moveEntrySelect
					self:updateMenuButtons()
				end,
				callbackDisabled = self.moveEntryDisabled
			},
			--- Copy an entry
--			{
--				profile = "buttonActivate",
--				inputAction = InputAction.MENU_ACTIVATE,
--				text = g_i18n:getText(CpCourseManagerFrame.translations.copyEntry),
--				callback = function ()
--					self.actionState = CpCourseManagerFrame.actionStates.copyEntrySelect
--					self:updateMenuButtons()
--				end,
--				callbackDisabled = CpCourseManagerFrame.copyEntryDisabled
--			},
			--- Delete
			{
				profile = "buttonActivate",
				inputAction = InputAction.MENU_EXTRA_1,
				text = g_i18n:getText(self.translations.deleteEntry),
				callback = function ()
					self.actionState = self.actionStates.deleteEntry
					self:updateMenuButtons()
				end,
				callbackDisabled = self.deleteEntryDisabled
			},
			--- Rename
			{
				profile = "buttonActivate",
				inputAction = InputAction.MENU_EXTRA_2,
				text = g_i18n:getText(self.translations.renameEntry),
				callback = function ()
					self.actionState = self.actionStates.renameEntry
					self:updateMenuButtons()
				end,
				callbackDisabled = self.renameEntryDisabled
			}
		},
	}
	self.leftList:setDataSource(self)
	self.rightList:setDataSource(self)
end
function CpCourseManagerFrame:onFrameOpen()
	self:superClass().onFrameOpen(self)
	self.curMode = self.minMode
	self.actionState = self.actionStates.disabled
	self.selectedEntry = nil
	self:setSoundSuppressed(true)
	FocusManager:loadElementFromCustomValues(self.leftList)
	FocusManager:loadElementFromCustomValues(self.rightList)
	FocusManager:linkElements(self.leftList, FocusManager.RIGHT, self.rightList)
	FocusManager:linkElements(self.rightList, FocusManager.LEFT, self.leftList)
	self:updateLists()
	FocusManager:setFocus(self.leftList)
	self:setSoundSuppressed(false)
	self.initialized = true
end
	
function CpCourseManagerFrame:onFrameClose()
	self:superClass().onFrameClose(self)
	if self.moveElementSelected then
		self.moveElementSelected.element:setAlternating(false)
	end
	self.initialized = false
end

function CpCourseManagerFrame:updateLists()
	self.courseStorage:refresh()
	self.leftColumnHeader:setText(self.courseStorage:getCurrentDirectoryViewPath())
	self.leftList:reloadData()
	self.rightList:reloadData()
	self:updateMenuButtons()
end

function CpCourseManagerFrame:getNumberOfItemsInSection(list, section)
	local numOfDirs = self.courseStorage:getNumberOfEntries()
	
	if list == self.leftList then
		return numOfDirs
	else
		if numOfDirs <=0 then 
			return 0
		end
		local ix = self.leftList:getSelectedIndexInSection()
		return self.courseStorage:getNumberOfEntriesForIndex(ix) or 0
	end
end

function CpCourseManagerFrame.setFolderIcon(element)
	element.iconImageSize = {32, 32}
	element:setImageSlice(nil, "cpIconSprite.folder")
	element:setImageColor(nil, 0, 0, 0, 0.5)
end

function CpCourseManagerFrame.setCourseIcon(element)
	element.iconImageSize = {32, 32}
	element:setImageSlice(nil, "cpIconSprite.white_fieldworkCourse")
	element:setImageColor(nil, 0, 0, 0, 0.5)
end


function CpCourseManagerFrame:populateCellForItemInSection(list, section, index, cell)
	if list == self.leftList then
		local entry =  self.courseStorage:getEntryByIndex(index)
		cell.viewEntry = entry
		if entry:isDirectory() then
			self.setFolderIcon(cell:getAttribute("icon"))
		else 
			self.setCourseIcon(cell:getAttribute("icon"))
		end
		cell:getAttribute("icon"):setVisible(true)
		cell:getAttribute("title"):setText(entry and entry:getName() or "unknown: "..index)
		cell.target = self
		cell:setCallback("onClickCallback", "onClickLeftItem")
	else
	--	cell.alternateBackgroundColor =  CpCourseManagerFrame.colors.move
		local ix = self.leftList:getSelectedIndexInSection()
		local entry = self.courseStorage:getSubEntryByIndex(ix, index)
		cell.viewEntry = entry
		if entry:isDirectory() then
			self.setFolderIcon(cell:getAttribute("icon"))
		else 
			self.setCourseIcon(cell:getAttribute("icon"))
		end
		cell:getAttribute("icon"):setVisible(true)

		cell:getAttribute("title"):setText(entry and entry:getName() or "unknown: "..index)
		cell.target = self
		cell:setCallback("onClickCallback", "onClickRightItem")
		
	end
end


function CpCourseManagerFrame:onClickLeftItem(element)
	self:onClickItem(self.leftList, element)
end


function CpCourseManagerFrame:onClickRightItem(element)
	self:onClickItem(self.rightList, element)
end

function CpCourseManagerFrame:onClickItem(layout, element)
	local viewEntry = element.viewEntry
	if viewEntry == nil then 
		return 
	end
	if self.actionState == self.actionStates.disabled then
		--- If no action is taking place, then allow traversing the file system in the left layout.
		if viewEntry:isDirectory() and layout == self.leftList and layout:getSelectedElement() == element then 
			self.courseStorage:iterateForwards(element.viewEntry)
		end
	elseif self.actionState == self.actionStates.createDirectory then
		--- Creates a new sub directory under a selected directory.
		if viewEntry:isDirectory() then 
			self.showInputTextDialog(
				self, self.translations.folderDialogTitle,
				self.onClickCreateDirectoryDialog, viewEntry)
		else 
			self.showInfoDialog(
				self.translations.targetIsNoFolder, viewEntry)
		end
		self.actionState = self.actionStates.disabled
	elseif self.actionState == self.actionStates.moveEntrySelect then
		--- Selected a entity to move.
		if viewEntry:hasAccess() and not viewEntry:isDirectory() then
			self.selectedEntry = viewEntry 
			self.actionState = self.actionStates.moveEntryDestination
		else 
			self.showInfoDialog(
				self.translations.noAccessError, viewEntry)
			self.actionState = self.actionStates.disabled
		end
	elseif self.actionState == self.actionStates.moveEntryDestination then
		--- Moves the previous selected entity to a given directory.
		if self.selectedEntry ~= viewEntry then
			if viewEntry:isDirectory() then 
				self.courseStorage:validate(viewEntry)
				local wasMoved = self.selectedEntry:move(viewEntry)
				if not wasMoved then
					self.showInfoDialog(
						self.translations.entryExistAlreadyError, viewEntry)
				end
			else
				self.showInfoDialog(
					self.translations.targetIsNoFolder, viewEntry)
			end
			self.selectedEntry = nil
			self.actionState = self.actionStates.disabled
		end
	elseif self.actionState == self.actionStates.deleteEntry then
		--- Deletes a selected entity.
		if viewEntry:isDeleteAllowed() then 
			self.showYesNoDialog(
				self, self.translations.deleteWarning,
				self.onClickDeleteEntryDialog, viewEntry)
		else 
			self.showInfoDialog(
				self.translations.noAccessError, viewEntry)
		end
		self.actionState = self.actionStates.disabled
	elseif self.actionState == self.actionStates.renameEntry then 
		--- Renames a selected entity.
		if viewEntry:isRenameAllowed() then
			self.showInputTextDialog(
						self, self.translations.renameEntry,
						self.onClickRenameEntryDialog, viewEntry, viewEntry:getName())
		else 
			self.showInfoDialog(
				self.translations.noAccessError, viewEntry)
		end
		self.actionState = self.actionStates.disabled
	elseif self.actionState == self.actionStates.copyEntrySelect then 
		--- Selected a entity to copy.
		if viewEntry:hasAccess() then
			self.selectedEntry = viewEntry 
			self.actionState = self.actionStates.copyEntryDestination
		else
			self.showInfoDialog(
				self.translations.noAccessError, viewEntry)
			self.actionState = self.actionStates.disabled
		end
	elseif self.actionState == self.actionStates.copyEntryDestination then 
		--- Copies the previous selected entity to a given directory.
		if viewEntry:isDirectory() then 
			local wasCopied = self.selectedEntry:copy(viewEntry)
			if not wasCopied then 
				self.showInfoDialog(
					self.translations.entryExistAlreadyError, viewEntry)
			end
		else
			self.showInfoDialog(
				self.translations.targetIsNoFolder, viewEntry)
		end
		self.selectedEntry = nil
		self.actionState = self.actionStates.disabled
	end
	self:updateLists()
	CpUtil.debugFormat(CpUtil.DBG_HUD, "actionState -> %d", self.actionState)
end

function CpCourseManagerFrame:onListSelectionChanged(list, section, index)
	if list == self.leftList then 
		self.rightList:reloadData()
--		CpUtil.debugFormat(CpUtil.DBG_HUD, "leftList -> onListSelectionChanged")
	else
--		CpUtil.debugFormat(CpUtil.DBG_HUD, "rightList -> onListSelectionChanged")
	end
	self:updateMenuButtons()
end

--- Updates the button at the bottom, which depends on the current select mode.
function CpCourseManagerFrame:updateMenuButtons()
	local vehicle = self.cpMenu:getCurrentVehicle()
	local courseName = vehicle:getCurrentCpCourseName()
	local title = string.format(g_i18n:getText(self.translations.title), vehicle:getName(), courseName)
	
	self.categoryHeaderText:setText(title)
	self.menuButtonInfo = table.clone(self.cpMenu.defaultMenuButtonInfo) 
	if self.activateButton.callbackDisabled == nil or not self.activateButton.callbackDisabled(self) then
		table.insert(self.menuButtonInfo, self.activateButton)
	end
	if self.modeButton.callbackDisabled == nil or not self.modeButton.callbackDisabled(self) then
		table.insert(self.menuButtonInfo, self.modeButton)
	end
	for i, data in pairs(self.modes[self.curMode]) do 
		if data.callbackDisabled == nil or not data.callbackDisabled(self) then
			table.insert(self.menuButtonInfo, data)
		end
	end	
	self:setMenuButtonInfoDirty()
	local text = self.curMode == self.minMode and g_i18n:getText(self.translations.basicSettings)
					or  g_i18n:getText(self.translations.advancedSettings)
	self.rightColumnHeader:setText(text)
	--self.rightToggleBtn:setText(text)
end

function CpCourseManagerFrame:onClickBack()
	if self.courseStorage:getCanIterateBackwards() then
		-- self:onClickIterateBack()
		-- return false
	end
	return true
end

---------------------------------------------------
--- Menu button click callbacks
---------------------------------------------------

--- Traverse back a directory.
function CpCourseManagerFrame:onClickIterateBack()
	self.courseStorage:iterateBackwards()
	self:updateLists()
end

--- Changes the current possible actions.
function CpCourseManagerFrame:onClickChangeMode()
	self.curMode = self.curMode + 1
	if self.curMode > self.maxMode then 
		self.curMode = self.minMode
	end
	CpUtil.debugFormat(CpUtil.DBG_HUD, "onClickChangeMode")
	self.actionState = self.actionStates.disabled
	self.selectedEntry = nil
	--- CpCourseManagerFrame.updateLists(self)
end

--- Clears the current courses.
function CpCourseManagerFrame:onClickClearCurrentCourse()
	CpUtil.debugFormat(CpUtil.DBG_HUD, "onClickClearCurrentCourse")
	local vehicle = self.cpMenu:getCurrentVehicle()
	local hasCourse = vehicle:hasCpCourse()
	if hasCourse then 
		vehicle:resetCpCoursesFromGui()
	end
	self:updateLists()
end

--- Saves the current vehicle courses with a given name.
function CpCourseManagerFrame:onClickSaveEntryDialog(text, clickOk, viewEntry)
	if clickOk then 
		CpUtil.debugFormat(CpUtil.DBG_HUD, "onClickSaveEntryDialog - > %s", text)

		local file, fileCreated = viewEntry:addFile(text)
		if not fileCreated then 
			self.showInfoDialog(
				self.translations.entryExistAlreadyError, viewEntry)
			return 
		end
		local vehicle = self.cpMenu:getCurrentVehicle()
		if not vehicle:saveCpCourses(file, text) then 
			InfoDialog.show(
				string.format(g_i18n:getText(self.translations.invalidNameError), text))
		end
	end
end

--- Creates a new directory with a given name.
function CpCourseManagerFrame:onClickCreateDirectoryDialog(text, clickOk, viewEntry)
	if clickOk then 
		CpUtil.debugFormat(CpUtil.DBG_HUD, "onClickCreateDirectoryDialog - > %s", text)
		local wasAdded = self.courseStorage:createDirectory(text)
		if not wasAdded then 
			self.showInfoDialog(
				self.translations.entryExistAlreadyError, viewEntry)
		end
	end
end

--- Creates a new directory with a given name.
function CpCourseManagerFrame:onClickDeleteEntryDialog(clickOk, viewEntry)
	if clickOk then 
		CpUtil.debugFormat(CpUtil.DBG_HUD, "onClickDeleteEntryDialog")
		self.courseStorage:validate(viewEntry)
		local wasDeleted = viewEntry:delete()
		if not wasDeleted then 
			self.showInfoDialog(
				self.translations.deleteError, viewEntry)
		end
	end
end

function CpCourseManagerFrame:onClickRenameEntryDialog(text, clickOk, viewEntry)
	if clickOk then 
		CpUtil.debugFormat(CpUtil.DBG_HUD, "onClickRenameEntryDialog - > %s", text)
		self.courseStorage:validate(viewEntry)
		local wasRenamed = viewEntry:rename(text)
		if not wasRenamed then 
			self.showInfoDialog(
				self.translations.entryExistAlreadyError, viewEntry)
		end
	end
end

function CpCourseManagerFrame:onClickActivate()
	local layout = FocusManager:getFocusedElement()
	if layout then  
		local element = layout:getSelectedElement()
		self:onClickItem(layout, element)
	end
end

function CpCourseManagerFrame:onClickOpenEditor()
	local layout = FocusManager:getFocusedElement()
	if layout then  
		local element = layout:getSelectedElement()
		local viewEntry = element.viewEntry
		if viewEntry == nil then 
			return 
		end
		if not viewEntry:isDirectory() then 
			g_courseEditor:activate(viewEntry:getEntity())
			self.showInfoDialog(
				self.translations.editWarning, viewEntry)
		else 
			self.showInfoDialog(
				self.translations.targetIsNoCourse, viewEntry)
		end
	end
end

---------------------------------------------------
--- Gui dialogs
---------------------------------------------------


function CpCourseManagerFrame:showInputTextDialog(title, callbackFunc, viewEntry, defaultText)
	TextInputDialog.show(
		function (self, text, clickOk, viewEntry)
			text = CpUtil.cleanFilePath(text)
			callbackFunc(self, text, clickOk, viewEntry)
			self:updateLists()
		end,
		self, defaultText or "",  
		string.format(g_i18n:getText(title), viewEntry and viewEntry:getName()),
		g_i18n:getText(title), 50, g_i18n:getText("button_ok"), viewEntry)
end

function CpCourseManagerFrame:showYesNoDialog(title, callbackFunc, viewEntry)
	YesNoDialog.show(
		function (self, clickOk, viewEntry)
			callbackFunc(self, clickOk, viewEntry)
			self:updateLists()
		end,
		self, string.format(g_i18n:getText(title), viewEntry:getName()),
		nil, nil, nil, nil,
		nil, nil, viewEntry)
end

function CpCourseManagerFrame.showInfoDialog(title, viewEntry)
	InfoDialog.show(string.format(g_i18n:getText(title), viewEntry:getName()))
end

---------------------------------------------------
--- Menu button disabled callbacks
---------------------------------------------------

function CpCourseManagerFrame:clearCurrentCourseDisabled()
	local vehicle = self.cpMenu:getCurrentVehicle()
	return not vehicle:hasCpCourse() or self.actionState ~= self.actionStates.disabled
end

function CpCourseManagerFrame:loadCourseDisabled()
	local vehicle = self.cpMenu:getCurrentVehicle()
	return vehicle:hasCpCourse() or self.actionState ~= self.actionStates.disabled or not self.courseStorage.currentDirectoryView:areEntriesVisible()
end

function CpCourseManagerFrame:saveCourseDisabled()
	local vehicle = self.cpMenu:getCurrentVehicle()
	return not vehicle:hasCpCourse() or self.actionState ~= self.actionStates.disabled or not self.courseStorage.currentDirectoryView:areEntriesVisible()
end

function CpCourseManagerFrame:createDirectoryDisabled()
	return self.actionState ~= self.actionStates.disabled or not self.courseStorage.currentDirectoryView:areEntriesVisible()
end

function CpCourseManagerFrame:moveEntryDisabled()
	return self.actionState ~= self.actionStates.disabled or not self.courseStorage.currentDirectoryView:areEntriesVisible()
end

function CpCourseManagerFrame:copyEntryDisabled()
	return self.actionState ~= self.actionStates.disabled or not self.courseStorage.currentDirectoryView:areEntriesVisible()
end

function CpCourseManagerFrame:deleteEntryDisabled()
	return self.actionState ~= self.actionStates.disabled or not self.courseStorage.currentDirectoryView:areEntriesVisible()
end

function CpCourseManagerFrame:renameEntryDisabled()
	return self.actionState ~= self.actionStates.disabled or not self.courseStorage.currentDirectoryView:areEntriesVisible()
end

function CpCourseManagerFrame:activateDisabled()
	return self.actionState == self.actionStates.disabled
end

function CpCourseManagerFrame:modeDisabled()
	return self.actionState ~= self.actionStates.disabled
end

function CpCourseManagerFrame:openEditorDisabled()
	return not self:clearCurrentCourseDisabled() or self.actionState ~= self.actionStates.disabled
end
