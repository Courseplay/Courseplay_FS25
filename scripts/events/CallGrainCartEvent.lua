---@class CallGrainCartEvent
CallGrainCartEvent = {}
local CallGrainCartEvent_mt = Class(CallGrainCartEvent, Event)

InitEventClass(CallGrainCartEvent, "CallGrainCartEvent")

function CallGrainCartEvent.emptyNew()
	local self = Event.new(CallGrainCartEvent_mt)
	return self
end

function CallGrainCartEvent.new(vehicle)
	local self = CallGrainCartEvent.emptyNew()
	self.vehicle = vehicle
	return self
end

function CallGrainCartEvent:readStream(streamId, connection)
	self.vehicle = NetworkUtil.readNodeObject(streamId)
	self:run(connection)
end

function CallGrainCartEvent:writeStream(streamId, connection)
	NetworkUtil.writeNodeObject(streamId, self.vehicle)
end

function CallGrainCartEvent:run(connection)
	if self.vehicle and self.vehicle.cpToggleCallGrainCart then
		self.vehicle:cpToggleCallGrainCart()
	end
	if not connection:getIsServer() then
		g_server:broadcastEvent(CallGrainCartEvent.new(self.vehicle), nil, connection, self.vehicle)
	end
end

function CallGrainCartEvent.sendEvent(vehicle)
	if g_server ~= nil then
		g_server:broadcastEvent(CallGrainCartEvent.new(vehicle), nil, nil, vehicle)
	else
		g_client:getServerConnection():sendEvent(CallGrainCartEvent.new(vehicle))
	end
end
