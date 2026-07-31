---@class CpManualUnloaderEvent
CpManualUnloaderEvent = {}
local CpManualUnloaderEvent_mt = Class(CpManualUnloaderEvent, Event)

InitEventClass(CpManualUnloaderEvent, "CpManualUnloaderEvent")

function CpManualUnloaderEvent.emptyNew()
	local self = Event.new(CpManualUnloaderEvent_mt)
	return self
end

function CpManualUnloaderEvent.new(vehicle, active)
	local self = CpManualUnloaderEvent.emptyNew()
	self.vehicle = vehicle
	self.active = active
	return self
end

function CpManualUnloaderEvent:readStream(streamId, connection)
	self.vehicle = NetworkUtil.readNodeObject(streamId)
	self.active = streamReadBool(streamId)
	self:run(connection)
end

function CpManualUnloaderEvent:writeStream(streamId, connection)
	NetworkUtil.writeNodeObject(streamId, self.vehicle)
	streamWriteBool(streamId, self.active)
end

function CpManualUnloaderEvent:run(connection)
	if self.vehicle and self.vehicle.cpSetManualUnloaderActive then
		-- Apply the explicit desired state. noEventSend=true prevents the setter from
		-- re-broadcasting, which would echo indefinitely between server and clients.
		self.vehicle:cpSetManualUnloaderActive(self.active, true)
	end
	if not connection:getIsServer() then
		g_server:broadcastEvent(CpManualUnloaderEvent.new(self.vehicle, self.active), nil, connection, self.vehicle)
	end
end

function CpManualUnloaderEvent.sendEvent(vehicle, active)
	if g_server ~= nil then
		g_server:broadcastEvent(CpManualUnloaderEvent.new(vehicle, active), nil, nil, vehicle)
	else
		g_client:getServerConnection():sendEvent(CpManualUnloaderEvent.new(vehicle, active))
	end
end
