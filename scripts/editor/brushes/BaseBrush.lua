--[[
	Basic brush, that manipulates waypoints.
]]
---@class CpBrush
---@field setInputTextDirty function
CpBrush = CpObject(ConstructionBrush)
CpBrush.TRANSLATION_PREFIX = "CP_editor_"
CpBrush.radius = 2
CpBrush.primaryButtonText = "primary_text"
CpBrush.primaryAxisText = "primary_axis_text"
CpBrush.secondaryButtonText = "secondary_text"
CpBrush.secondaryAxisText = "secondary_axis_text"
CpBrush.tertiaryButtonText = "tertiary_text"
CpBrush.inputTitle = "input_title"
CpBrush.yesNoTitle = "yesNo_title"
CpBrush.defaultErrorMessage = "err"
CpBrush.ERR_MESSAGE_DURATION = 15 * 1000 -- 15 sec
function CpBrush:init(cursor, camera, editor)
	self.isActive = false
	self.cursor = cursor
	self.camera = camera
	self.supportsPrimaryButton = false
	self.supportsPrimaryDragging = false
	self.supportsSecondaryButton = false
	self.supportsSecondaryDragging = false
	self.supportsTertiaryButton = false
	self.supportsPrimaryAxis = false
	self.supportsSecondaryAxis = false
	self.primaryAxisIsContinuous = false
	self.secondaryAxisIsContinuous = false
	self.inputTextDirty = true
	self.activeSoundId = ConstructionSound.ID.NONE
	self.activeSoundPitchModifier = nil
	self.cursor:setShapeSize(self.radius)
	self.cursor:setShape(GuiTopDownCursor.SHAPES.CIRCLE)
	self.lastHoveredIx = nil
	self.errorMsgTimer = CpTemporaryObject(false)
	self.errorMsgText = nil
	self.editor = editor
	self.courseWrapper = editor:getCourseWrapper()
end

function CpBrush:isAtPos(position, x, y, z)
	return MathUtil.getPointPointDistance(position.x, position.z, x, z) < self.radius 
end

--- Gets the hovered waypoint ix.
function CpBrush:getHoveredWaypointIx()
	local x, y, z = self.cursor:getPosition()
	if x == nil or z == nil then 
		return
	end
	-- try to get a waypoint in mouse range
	for ix, point in ipairs(self.courseWrapper:getVisiblePoints()) do
		if self:isAtPos(point, x, y, z) then
			return ix
		end
	end
end

function CpBrush:setParameters(translation)
	self.translation = translation
end

function CpBrush:update(dt)
	local ix = self:getHoveredWaypointIx()
	local lastIx = self.courseWrapper:setHovered(ix)
	if lastIx ~= nil then 
		self.editor:updateChangeSingle(lastIx)
	end
	if self.errorMsgTimer:get() then
		self.cursor:setErrorMessage(self:getErrorMessage())
	else 
		self.errorMsgText = nil
	end
end

function CpBrush:openTextInput(callback, title, args)
	TextInputDialog.show(
		callback, self, "",
		title, title, 50,
		g_i18n:getText("button_ok"), args)
end

function CpBrush:showYesNoDialog(callback, title, args)
	YesNoDialog.show(
		callback, self, title,
		nil, nil, nil, nil, nil, nil, args)
end

--- Gets the translation with the translation prefix.
function CpBrush:getTranslation(translation, ...)
	return string.format(g_i18n:getText(self.translation .. "_" .. translation), ...)
end

function CpBrush:getErrorMessage()
	if self.errorMsgText then 
		return self.editor.TRANSLATION_PREFIX .. self.errorMsgText
	end
	return self:getTranslation(self.defaultErrorMessage)
end

---@param errMsg string|nil
function CpBrush:setError(errMsg)
	self.errorMsgTimer:set(true, self.ERR_MESSAGE_DURATION)
	self.errorMsgText = errMsg
	self:debug("setting error: %s", tostring(errMsg))
end

function CpBrush:resetError()
	self.errorMsgTimer:reset()
	self.errorMsgText = nil
end

function CpBrush:getTitle()
	return self:getTranslation("title")
end

function CpBrush:debug(...)
	CpUtil.info(...)
end