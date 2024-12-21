--- Small gui window to display workWidth, tool offset.
---@class CpGamePadHudScreen
CpGamePadHudScreen = {
	CONTROLS = {
		BUTTON_BACK = "backButton",
		BUTTON_START = "startButton",
		BUTTON_RECORD= "recordButton",
		BUTTON_CLEAR = "clearButton",
		BUTTON_LAYOUT = "bottomButtons",
		SETTING_TEMPLATE = "settingTemplate",
		LAYOUT = "layout"
	},
}
CpGamePadHudScreen.texts = {
	startRecording = g_i18n:getText("CP_controllerGui_startRecording"),
	stopRecording = g_i18n:getText("CP_controllerGui_stopRecording"),
	pauseRecording = g_i18n:getText("CP_controllerGui_pauseRecording"),
	unpauseRecording = g_i18n:getText("CP_controllerGui_unpauseRecording")
}

local CpGamePadHudScreen_mt = Class(CpGamePadHudScreen, ScreenElement)

function CpGamePadHudScreen.new(settings, target, custom_mt)
	local self = ScreenElement.new(target, custom_mt or CpGamePadHudScreen_mt)
	self:exposeControlsAsFields(CpGamePadHudScreen.CONTROLS)
	self.settings = settings
	return self
end

function CpGamePadHudScreen:onGuiSetupFinished()
	self.settingTemplate:unlinkElement()
	FocusManager:removeElement(self.settingTemplate)

	self.startButton:unlinkElement()
	FocusManager:removeElement(self.startButton)

	self.recordButton:unlinkElement()
	FocusManager:removeElement(self.recordButton)

	self.clearButton:unlinkElement()
	FocusManager:removeElement(self.clearButton)
	-- TODO 25 (didn't we just remove this button above?) self.clearButton:setText(g_i18n:getText("CP_courseManager_clear_current_courses"))

	self.backButton:unlinkElement()
	FocusManager:removeElement(self.backButton)

	CpGamePadHudScreen:superClass().onGuiSetupFinished(self)
end

--- Links gui elements with the settings.
function CpGamePadHudScreen:setData(vehicle, settings) 
	self.vehicle = vehicle
	self.settings = settings
end

function CpGamePadHudScreen:onClickCpMultiTextOption(v, guiElement)
	CpSettingsUtil.updateGuiElementsBoundToSettings(self.layout, self.vehicle)
	if guiElement.aiParameter and guiElement.aiParameter:getName() == "selectedJob" then 
		self.vehicle:reopenCpGamePadHud()
	end
end

function CpGamePadHudScreen:onOpen(element)
	CpGamePadHudScreen:superClass().onOpen(self)

	for i = #self.layout.elements, 1, -1 do
		self.layout.elements[i]:delete()
	end
	CpSettingsUtil.generateGuiElementsFromSettingsTableAlternating({self.vehicle:cpGetHudSelectedJobSetting()}, self.layout,
		self.settingTemplate:getDescendantByName("title"), 
		self.settingTemplate:getDescendantByName("element"))
		


	CpSettingsUtil.generateGuiElementsFromSettingsTableAlternating(self.settings, self.layout,
		self.settingTemplate:getDescendantByName("title"), 
		self.settingTemplate:getDescendantByName("element"))

	CpSettingsUtil.updateGuiElementsBoundToSettings(self.layout, self.vehicle)

	self.layout:addElement(self.startButton)
	self.layout:addElement(self.recordButton)
	self.layout:addElement(self.clearButton)
	self.layout:addElement(self.backButton)
	self.layout:invalidateLayout()

	self:setSoundSuppressed(true)
	FocusManager:setFocus(self.layout)
	self:setSoundSuppressed(false)

	local text = self.vehicle.spec_aiJobVehicle.texts.hireEmployee
	if self.vehicle:getIsAIActive() then 
		text = self.vehicle.spec_aiJobVehicle.texts.dismissEmployee
	end
	if self.vehicle:getIsCpCourseRecorderActive() then
		if self.vehicle:getIsCpCourseRecorderPaused() then 
			self.startButton:setText(self.texts.unpauseRecording)
		else
			self.startButton:setText(self.texts.pauseRecording)
		end
	else
		self.startButton:setText(text)
	end
	local _, eventId = g_inputBinding:registerActionEvent(InputAction.CP_OPEN_CLOSE_VEHICLE_SETTING_DISPLAY, self, self.onClickBack, false, true, false, true)
end

function CpGamePadHudScreen:onClose(element)
	CpGamePadHudScreen:superClass().onClose(self)
	
	g_inputBinding:removeActionEventsByTarget(self)
	self.vehicle:closeCpGamePadHud()
end

function CpGamePadHudScreen:onClickBack()
	g_gui:showGui("")
end

function CpGamePadHudScreen:onClickOk()
	if self.vehicle then
		if self.vehicle:getIsCpCourseRecorderActive() then 
			self.vehicle:toggleCpCourseRecorderPause()
		else
			self.vehicle:cpStartStopDriver(true)
		end
	end
end

function CpGamePadHudScreen:update(dt, ...)
	CpGamePadHudScreen:superClass().update(self, dt, ...)
	if not self.vehicle then
		return
	end
	if self.vehicle:getIsCpCourseRecorderActive() then 
		self.recordButton:setVisible(true)
		self.recordButton:setText(self.texts.stopRecording)
	elseif self.vehicle:getCanStartCpCourseRecorder() then 
		self.recordButton:setVisible(true)
		self.recordButton:setText(self.texts.startRecording)
	else 
		self.recordButton:setVisible(false)
	end
	self.startButton:setVisible(self.vehicle:getCanStartCp() or self.vehicle:getIsCpActive() or self.vehicle:getIsCpCourseRecorderActive())
	self.clearButton:setVisible(self.vehicle:hasCpCourse() and not self.vehicle:getIsCpActive())

	local text = self.vehicle.spec_aiJobVehicle.texts.hireEmployee
	if self.vehicle:getIsAIActive() then 
		text = self.vehicle.spec_aiJobVehicle.texts.dismissEmployee
	end

	if self.vehicle:getIsCpCourseRecorderActive() then
		if self.vehicle:getIsCpCourseRecorderPaused() then 
			self.startButton:setText(self.texts.unpauseRecording)
		else
			self.startButton:setText(self.texts.pauseRecording)
		end
	else
		self.startButton:setText(text)
	end

	g_currentMission.hud:updateBlinkingWarning(dt)
end

function CpGamePadHudScreen:onClickRecord()
	if not self.vehicle then
		return
	end
	if self.vehicle:getIsCpCourseRecorderActive() then 
		self.vehicle:cpStopCourseRecorder()
	elseif self.vehicle:getCanStartCpCourseRecorder() then 
		self.vehicle:cpStartCourseRecorder()
	end
end

function CpGamePadHudScreen:onClickClearCourse()
	if not self.vehicle then
		return
	end
	if self.vehicle:hasCpCourse() and not self.vehicle:getIsCpActive() then 
		self.vehicle:resetCpCoursesFromGui()
	end
end

function CpGamePadHudScreen:draw(...)
	CpGamePadHudScreen:superClass().draw(self, ...)
	self:drawWorkWidth()
	g_currentMission.hud:drawBlinkingWarning()
end

function CpGamePadHudScreen:drawWorkWidth()
	-- Override
end

---@class CpGamePadHudFieldWorkScreen : CpGamePadHudScreen
CpGamePadHudFieldWorkScreen = {}
local CpGamePadHudFieldWorkScreen_mt = Class(CpGamePadHudFieldWorkScreen, CpGamePadHudScreen)

function CpGamePadHudFieldWorkScreen.new(settings, target, custom_mt)
	local self = CpGamePadHudScreen.new(settings, target, custom_mt or CpGamePadHudFieldWorkScreen_mt)

	return self
end

function CpGamePadHudFieldWorkScreen:drawWorkWidth()
	self.vehicle:showCpCourseWorkWidth()
end

---@class CpGamePadHudBaleLoaderScreen : CpGamePadHudScreen
CpGamePadHudBaleLoaderScreen = {}
local CpGamePadHudBaleLoaderScreen_mt = Class(CpGamePadHudBaleLoaderScreen, CpGamePadHudScreen)

function CpGamePadHudBaleLoaderScreen.new(settings, target, custom_mt)
	local self = CpGamePadHudScreen.new(settings, target, custom_mt or CpGamePadHudBaleLoaderScreen_mt)

	return self
end

function CpGamePadHudBaleLoaderScreen:drawWorkWidth()
	self.vehicle:showCpCourseWorkWidth()
end

---@class CpGamePadHudUnloaderScreen : CpGamePadHudScreen
CpGamePadHudUnloaderScreen = {}
local CpGamePadHudUnloaderScreen_mt = Class(CpGamePadHudUnloaderScreen, CpGamePadHudScreen)

function CpGamePadHudUnloaderScreen.new(settings, target, custom_mt)
	local self = CpGamePadHudScreen.new(settings, target, custom_mt or CpGamePadHudUnloaderScreen_mt)

	return self
end

function CpGamePadHudUnloaderScreen:drawWorkWidth()
	self.vehicle:showCpCombineUnloaderWorkWidth()
end

---@class CpGamePadHudBunkerSiloScreen : CpGamePadHudScreen
CpGamePadHudBunkerSiloScreen = {}
local CpGamePadHudBunkerSiloScreen_mt = Class(CpGamePadHudBunkerSiloScreen, CpGamePadHudScreen)

function CpGamePadHudBunkerSiloScreen.new(settings, target, custom_mt)
	local self = CpGamePadHudScreen.new(settings, target, custom_mt or CpGamePadHudBunkerSiloScreen_mt)

	return self
end

function CpGamePadHudBunkerSiloScreen:drawWorkWidth()
	self.vehicle:showCpBunkerSiloWorkWidth()
end

---@class CpGamePadHudSiloLoaderScreen : CpGamePadHudScreen
CpGamePadHudSiloLoaderScreen = {}
local CpGamePadHudSiloLoaderScreen_mt = Class(CpGamePadHudSiloLoaderScreen, CpGamePadHudScreen)

function CpGamePadHudSiloLoaderScreen.new(settings, target, custom_mt)
	local self = CpGamePadHudScreen.new(settings, target, custom_mt or CpGamePadHudSiloLoaderScreen_mt)

	return self
end

function CpGamePadHudSiloLoaderScreen:drawWorkWidth()
	self.vehicle:showCpBunkerSiloWorkWidth()
end