--- Event called on joining a multiplayer from the server to the joining player.
--- Used for synchronizing global value.
---@class CpJoinEvent
local CpJoinEvent = {}
local CpJoinEvent_mt = Class(CpJoinEvent, Event)

InitEventClass(CpJoinEvent, "CpJoinEvent")

function CpJoinEvent.emptyNew()
	return Event.new(CpJoinEvent_mt)
end

--- Creates a new Event
function CpJoinEvent.new()
	local self = CpJoinEvent.emptyNew()
	
	return self
end

--- Reads the serialized data on the receiving end of the event.
function CpJoinEvent:readStream(streamId, connection) 
	CpJoinEvent.debug("readStream")
	local settings = g_Courseplay.globalSettings:getSettingsTable()
	for i = 1, #settings do 
		settings[i]:readStream(streamId, connection)
	end

	for i = 1, #CpDebug.channels do 
		CpDebug:setChannelActive(i, streamReadBool(streamId))
	end
	g_graph:readStream(streamId, connection)

	self:run(connection);
end

--- Writes the serialized data from the sender.
function CpJoinEvent:writeStream(streamId, connection) 
	CpJoinEvent.debug("writeStream")
	local settings = g_Courseplay.globalSettings:getSettingsTable()
	for i = 1, #settings do 
		settings[i]:writeStream(streamId, connection)
	end

	for i = 1, #CpDebug.channels do 
		streamWriteBool(streamId, CpDebug:isChannelActive(i))
	end
	g_graph:writeStream(streamId, connection)
end

--- Runs the event on the receiving end of the event.
function CpJoinEvent:run(connection) 

end

function CpJoinEvent.debug(str, ...)
	CpUtil.debugFormat(CpDebug.DBG_MULTIPLAYER, "CpJoinEvent: "..str,...)
end

local function sendEvent(baseMission,connection, x, y, z, viewDistanceCoeff)
	-- body
	if connection ~= nil then 
		CpJoinEvent.debug("send Event")
		connection:sendEvent(CpJoinEvent.new())
	end
end

FSBaseMission.onConnectionFinishedLoading = Utils.appendedFunction(FSBaseMission.onConnectionFinishedLoading,sendEvent)