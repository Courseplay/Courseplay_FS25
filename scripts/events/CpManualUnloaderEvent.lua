---@class CpManualUnloaderEvent
CpManualUnloaderEvent = {}
local CpManualUnloaderEvent_mt = Class(CpManualUnloaderEvent, Event)

InitEventClass(CpManualUnloaderEvent, "CpManualUnloaderEvent")

function CpManualUnloaderEvent.emptyNew()
	local self = Event.new(CpManualUnloaderEvent_mt)
	return self
end

function CpManualUnloaderEvent.new(vehicle)
	local self = CpManualUnloaderEvent.emptyNew()
	self.vehicle = vehicle
	return self
end

function CpManualUnloaderEvent:readStream(streamId, connection)
	self.vehicle = NetworkUtil.readNodeObject(streamId)
	self:run(connection)
end

function CpManualUnloaderEvent:writeStream(streamId, connection)
	NetworkUtil.writeNodeObject(streamId, self.vehicle)
end

function CpManualUnloaderEvent:run(connection)
	if self.vehicle and self.vehicle.cpToggleManualUnloader then
		self.vehicle:cpToggleManualUnloader()
	end
	if not connection:getIsServer() then
		g_server:broadcastEvent(CpManualUnloaderEvent.new(self.vehicle), nil, connection, self.vehicle)
	end
end

function CpManualUnloaderEvent.sendEvent(vehicle)
	if g_server ~= nil then
		g_server:broadcastEvent(CpManualUnloaderEvent.new(vehicle), nil, nil, vehicle)
	else
		g_client:getServerConnection():sendEvent(CpManualUnloaderEvent.new(vehicle))
	end
end
