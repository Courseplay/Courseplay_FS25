---@class GraphSegmentChangedAttributesEvent
---@field segment GraphSegment
GraphSegmentChangedAttributesEvent = {}
local GraphSegmentChangedAttributesEvent_mt = Class(GraphSegmentChangedAttributesEvent, Event)

InitEventClass(GraphSegmentChangedAttributesEvent, 'GraphSegmentChangedAttributesEvent')

function GraphSegmentChangedAttributesEvent.emptyNew()
    return Event.new(GraphSegmentChangedAttributesEvent_mt)
end

function GraphSegmentChangedAttributesEvent.new(segment)
    local self = GraphSegmentChangedAttributesEvent.emptyNew()
    self.segment = segment
    return self
end

function GraphSegmentChangedAttributesEvent:readStream(streamId, connection)
    ---@type GraphSegment
    local segment = g_graph:getChildNodeByIndex(streamReadUInt32(streamId))
    if segment then 
        segment:readStreamAttributes(streamId, connection)
    end
end

function GraphSegmentChangedAttributesEvent:writeStream(streamId, connection)
    streamWriteUInt32(streamId, self.segment:getID())
    self.segment:writeStreamAttributes(streamId, connection)
end

function GraphSegmentChangedAttributesEvent.sendEvent(segment)
    if g_server ~= nil then
        g_server:broadcastEvent(GraphSegmentChangedAttributesEvent.new(segment), 
            nil, nil, nil)
    else
        g_client:getServerConnection():sendEvent(
            GraphSegmentChangedAttributesEvent.new(segment))
    end
end

---@class GraphCreateSegmentEvent
---@field segment GraphSegment
GraphCreateSegmentEvent = {}
local GraphCreateSegmentEvent_mt = Class(GraphCreateSegmentEvent, Event)

InitEventClass(GraphCreateSegmentEvent, 'GraphCreateSegmentEvent')

function GraphCreateSegmentEvent.emptyNew()
    return Event.new(GraphCreateSegmentEvent_mt)
end

function GraphCreateSegmentEvent.new(segment)
    local self = GraphCreateSegmentEvent.emptyNew()
    self.segment = segment
    return self
end

function GraphCreateSegmentEvent:readStream(streamId, connection)
    ---@type GraphSegment
    local segment = GraphSegment()
    segment:readStream(streamId, connection)
    g_graph:addNewSegment(segment, true)
end

function GraphCreateSegmentEvent:writeStream(streamId, connection)
    self.segment:writeStream(streamId, connection)
end

function GraphCreateSegmentEvent.sendEvent(segment)
    if g_server ~= nil then
        g_server:broadcastEvent(GraphCreateSegmentEvent.new(segment), 
            nil, nil, nil)
    else
        g_client:getServerConnection():sendEvent(
            GraphCreateSegmentEvent.new(segment))
    end
end

---@class GraphRemoveSegmentEvent
---@field segment GraphSegment
GraphRemoveSegmentEvent = {}
local GraphRemoveSegmentEvent_mt = Class(GraphRemoveSegmentEvent, Event)

InitEventClass(GraphRemoveSegmentEvent, 'GraphRemoveSegmentEvent')

function GraphRemoveSegmentEvent.emptyNew()
    return Event.new(GraphRemoveSegmentEvent_mt)
end

function GraphRemoveSegmentEvent.new(segment)
    local self = GraphRemoveSegmentEvent.emptyNew()
    self.segment = segment
    return self
end

function GraphRemoveSegmentEvent:readStream(streamId, connection)
    ---@type GraphSegment
    local segment = g_graph:getChildNodeByIndex(streamReadUInt32(streamId))
    if segment then 
        g_graph:removeSegment(segment, true)
    end
end

function GraphRemoveSegmentEvent:writeStream(streamId, connection)
    streamWriteUInt32(streamId, self.segment:getID())
end

function GraphRemoveSegmentEvent.sendEvent(segment)
    if g_server ~= nil then
        g_server:broadcastEvent(GraphRemoveSegmentEvent.new(segment), 
            nil, nil, nil)
    else
        g_client:getServerConnection():sendEvent(
            GraphRemoveSegmentEvent.new(segment))
    end
end

---@class GraphRebuildSegmentEvent
---@field segment GraphSegment
GraphRebuildSegmentEvent = {}
local GraphRebuildSegmentEvent_mt = Class(GraphRebuildSegmentEvent, Event)

InitEventClass(GraphRebuildSegmentEvent, 'GraphRebuildSegmentEvent')

function GraphRebuildSegmentEvent.emptyNew()
    return Event.new(GraphRebuildSegmentEvent_mt)
end

function GraphRebuildSegmentEvent.new(segment)
    local self = GraphRebuildSegmentEvent.emptyNew()
    self.segment = segment
    return self
end

function GraphRebuildSegmentEvent:readStream(streamId, connection)
    ---@type GraphSegment
    local segment = g_graph:getChildNodeByIndex(streamReadUInt32(streamId))
    if segment then 
        segment:clearChildNodes()
        segment:readStream(streamId, connection)    
    end
end

function GraphRebuildSegmentEvent:writeStream(streamId, connection)
    self.segment:writeStream(streamId, connection)
end

function GraphRebuildSegmentEvent.sendEvent(segment)
    if g_server ~= nil then
        g_server:broadcastEvent(GraphRebuildSegmentEvent.new(segment), 
            nil, nil, nil)
    else
        g_client:getServerConnection():sendEvent(
            GraphRebuildSegmentEvent.new(segment))
    end
end