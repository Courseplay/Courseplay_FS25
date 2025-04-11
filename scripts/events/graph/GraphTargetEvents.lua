---@class GraphCreateTargetEvent
---@field point GraphPoint
---@field name string
GraphCreateTargetEvent = {}
local GraphCreateTargetEvent_mt = Class(GraphCreateTargetEvent, Event)

InitEventClass(GraphCreateTargetEvent, 'GraphCreateTargetEvent')

function GraphCreateTargetEvent.emptyNew()
    return Event.new(GraphCreateTargetEvent_mt)
end

function GraphCreateTargetEvent.new(point, name)
    local self = GraphCreateTargetEvent.emptyNew()
    self.point = point
    self.name = name
    return self
end

function GraphCreateTargetEvent:readStream(streamId, connection)
    local point = g_graph:getPointByIndex(streamReadString(streamId))
    local name = streamReadString(streamId)
    if point then 
        point:createTarget(name, true)
    end
end

function GraphCreateTargetEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.point:getRelativeID())
    streamWriteString(streamId, self.name)
end

function GraphCreateTargetEvent.sendEvent(point, name)
    if g_server ~= nil then
        g_server:broadcastEvent(GraphCreateTargetEvent.new(point, name), 
            nil, nil, nil)
    else
        g_client:getServerConnection():sendEvent(
            GraphCreateTargetEvent.new(point, name))
    end
end

---@class GraphRenameTargetEvent
---@field point GraphPoint
---@field name string
GraphRenameTargetEvent = {}
local GraphRenameTargetEvent_mt = Class(GraphRenameTargetEvent, Event)

InitEventClass(GraphRenameTargetEvent, 'GraphRenameTargetEvent')

function GraphRenameTargetEvent.emptyNew()
    return Event.new(GraphRenameTargetEvent_mt)
end

function GraphRenameTargetEvent.new(point, name)
    local self = GraphRenameTargetEvent.emptyNew()
    self.point = point
    self.name = name
    return self
end

function GraphRenameTargetEvent:readStream(streamId, connection)
    local point = g_graph:getPointByIndex(streamReadString(streamId))
    local name = streamReadString(streamId)
    if point then 
        local target = point:getTarget()
        target:rename(name, true)
    end
end

function GraphRenameTargetEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.point:getRelativeID())
    streamWriteString(streamId, self.name)
end

function GraphRenameTargetEvent.sendEvent(point, name)
    if g_server ~= nil then
        g_server:broadcastEvent(GraphRenameTargetEvent.new(point, name), 
            nil, nil, nil)
    else
        g_client:getServerConnection():sendEvent(
            GraphRenameTargetEvent.new(point, name))
    end
end

---@class GraphRemoveTargetEvent
GraphRemoveTargetEvent = {}
local GraphRemoveTargetEvent_mt = Class(GraphRemoveTargetEvent, Event)

InitEventClass(GraphRemoveTargetEvent, 'GraphRemoveTargetEvent')

function GraphRemoveTargetEvent.emptyNew()
    return Event.new(GraphRemoveTargetEvent_mt)
end

function GraphRemoveTargetEvent.new(point, name)
    local self = GraphRemoveTargetEvent.emptyNew()
    self.point = point
    self.name = name
    return self
end

function GraphRemoveTargetEvent:readStream(streamId, connection)
    local point = g_graph:getPointByIndex(streamReadString(streamId))
    if point then 
        point:removeTarget(true)
    end
end

function GraphRemoveTargetEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.point:getRelativeID())
end

function GraphRemoveTargetEvent.sendEvent(point)
    if g_server ~= nil then
        g_server:broadcastEvent(GraphRemoveTargetEvent.new(point), 
            nil, nil, nil)
    else
        g_client:getServerConnection():sendEvent(
            GraphRemoveTargetEvent.new(point))
    end
end