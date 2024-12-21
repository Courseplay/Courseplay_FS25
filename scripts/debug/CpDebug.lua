
---	Cp debug channels.
---
---	The debug channel menu can be activated/deactivated with "shift left and key 4"
---
---	With the menu active:
---		- toggle the current channel in the brackets "[[..]]" with "shift left and key 2"
---		- select the next channel with "shift left and key 3"
---		- select the previous channel with "shift left and key 1"

--- TODO: Add input help text and figure out a good way to enable it, maybe a setting in the inGame menu.


---@class CpDebug
CpDebug = CpObject()

function CpDebug:init()
	self:loadFromXMLFile()
	self.currentIx = 1
	self.isEnabled = true
	--- Is the debug channel menu active ?
	self.menuVisible = false
	self.activatedColor = {1, 0.5, 0, 1.0}
	self.disabledColor = {1, 1, 1, 1}
end

--- Loads the debug channel configurations.
function CpDebug:loadFromXMLFile()
	self.xmlSchema = XMLSchema.new("DebugChannels")
	local schema = self.xmlSchema
	--- 			valueTypeId, 			path, 				description, defaultValue, isRequired
	schema:register(XMLValueType.STRING, "DebugChannels.DebugChannel(?)#name", "Debug channel name")
	schema:register(XMLValueType.STRING, "DebugChannels.DebugChannel(?)#text", "Debug channel tooltip")
	schema:register(XMLValueType.BOOL, "DebugChannels.DebugChannel(?)#active", "Debug channel active at start", false)

	local xmlFilePath = Utils.getFilename('config/DebugChannels.xml', g_Courseplay.BASE_DIRECTORY)
	local xmlFile = XMLFile.load("debugChannelsXml", xmlFilePath, self.xmlSchema)
	self.numChannels = 0
	self.channels = {}
	xmlFile:iterate("DebugChannels.DebugChannel", function (i, key)
		local name = xmlFile:getValue( key.."#name")
		local text = xmlFile:getValue( key.."#text")
		local active = xmlFile:getValue( key.."#active", false)
		self.channels[i] = {}
		self.channels[i].text = text
		self.channels[i].active = active
		--- TODO: consolidate these two.
		self[name] = i
		CpUtil[name] = i 
		self.numChannels = self.numChannels+1
	end)
	xmlFile:delete()
end

---Is a given channel active ?
---@param ix number
---@param vehicle table an optional vehicle, if supplied, checks if the debug on the vehicle is enabled
---@return boolean
function CpDebug:isChannelActive(ix, vehicle)
	local vehicleDebugEnabled = vehicle == nil or vehicle.getCpSettings == nil or CpUtil.isVehicleDebugActive(vehicle)
	if self.channels[ix] then
		return self.channels[ix].active and vehicleDebugEnabled
	else
		CpUtil.error('Error: debug channel %s not found!', tostring(ix))
	end
end

function CpDebug:getText(ix)
	if not self.channels[ix] then 
		return "---"
	end
	return self.channels[ix].text
end

function CpDebug:setChannelActive(ix, active)
	self.channels[ix].active = active
end

---Sets the next select channel.
function CpDebug:setNext()
	if not self:isMenuVisible() then return end
	self.currentIx = self.currentIx + 1
	if self.currentIx > self.numChannels then 
		self.currentIx = 1
	end
end

---Sets the previous select channel.
function CpDebug:setPrevious()
	if not self:isMenuVisible() then return end
	self.currentIx = self.currentIx - 1
	if self.currentIx < 1 then 
		self.currentIx = self.numChannels
	end
end

---Activates/deactivates the current select channel.
function CpDebug:toggleCurrentChannel()
	if not self:isMenuVisible() then return end
	self.channels[self.currentIx].active = not self.channels[self.currentIx].active
	DebugChannelEvent.sendEvent(self.currentIx, self.channels[self.currentIx].active)
end

---Draws the channels at the bottom if it's enabled.
function CpDebug:draw()
	if not self:isMenuVisible() then return end

	setTextAlignment(RenderText.ALIGN_CENTER)
	local maxLineSize = 6
	for i = 0, self.numChannels-1 do
		local channelIx = i+1
		local partSize = 1 / (maxLineSize+1)
		local x = partSize * (channelIx-maxLineSize*math.floor(i/maxLineSize))
		local y = math.ceil(channelIx/maxLineSize)*0.02
		if self.channels[channelIx].active then
			local r, g, b, a = unpack(self.activatedColor)
			setTextColor(r, g, b, a)
		else
			local r, g, b, a = unpack(self.disabledColor)
			setTextColor(r, g, b, a)
		end
		local text = string.format("%s", self.channels[channelIx].text)
		if channelIx == self.currentIx then 
			text = "[["..text.."]]"
		end
		renderText(x, y, 0.015, text)

	end

	setTextAlignment(RenderText.ALIGN_LEFT)
end

function CpDebug:activateEvents()
	for _, id in pairs(CpDebug.eventIds) do 
		g_currentMission.inputManager:setActionEventActive(id, true)
	end
end

function CpDebug:deactivateEvents()
	for _, id in pairs(CpDebug.eventIds) do 
		g_currentMission.inputManager:setActionEventActive(id, false)
	end
end

function CpDebug:updateActionEventTextVisibility()
	if CpDebug.eventIds then
		local textVisible = g_Courseplay.globalSettings.showActionEventHelp:getValue()
		for _, id in pairs(CpDebug.eventIds) do 
			g_inputBinding:setActionEventTextVisibility(id, textVisible)
		end
		g_inputBinding:setActionEventTextVisibility(CpDebug.menuEventId, textVisible)
	end
end

function CpDebug:toggleMenuVisibility()
	if self.menuVisible then 
		self:deactivateEvents()
		self.menuVisible = false
	elseif self.isEnabled then
		self:activateEvents()
		self.menuVisible = true
	end
end

function CpDebug:isMenuVisible()
	return self.menuVisible and self.isEnabled
end

function CpDebug:drawVehicleDebugTable(vehicle, info, height, size)
	
	local d = DebugInfoTable.new()
	-- TODO 25
	--d:createWithNodeToCamera(vehicle.rootNode, height or 4, info, size or 0.05)
	--g_debugManager:addFrameElement(d)

end


CpDebug = CpDebug()

--- Registers the action events: 
--- - toggle current channel
--- - next channel 
--- - previous channel 
function CpDebug.addEvents(mission)
	--- actionName, targetObject, eventCallback, triggerUp, triggerDown, triggerAlways, startActive, callbackState, disableConflictingBindings, reportAnyDeviceCollision
	CpDebug.eventIds = {}
	local _, eventId = mission.inputManager:registerActionEvent(InputAction.CP_DBG_CHANNEL_SELECT_PREVIOUS, CpDebug, CpDebug.setPrevious, false, true, false, CpDebug:isMenuVisible())
	table.insert(CpDebug.eventIds, eventId)
	local _, eventId = mission.inputManager:registerActionEvent(InputAction.CP_DBG_CHANNEL_SELECT_NEXT, CpDebug, CpDebug.setNext, false, true, false, CpDebug:isMenuVisible())
	table.insert(CpDebug.eventIds, eventId)
	local _, eventId = mission.inputManager:registerActionEvent(InputAction.CP_DBG_CHANNEL_TOGGLE_CURRENT, CpDebug, CpDebug.toggleCurrentChannel, false, true, false, CpDebug:isMenuVisible())
	table.insert(CpDebug.eventIds, eventId)
	local _, eventId = mission.inputManager:registerActionEvent(InputAction.CP_DBG_CHANNEL_MENU_VISIBILITY, CpDebug, CpDebug.toggleMenuVisibility, false, true, false, CpDebug.isEnabled)
	CpDebug.menuEventId = eventId
end
FSBaseMission.registerActionEvents = Utils.appendedFunction(FSBaseMission.registerActionEvents, CpDebug.addEvents)
