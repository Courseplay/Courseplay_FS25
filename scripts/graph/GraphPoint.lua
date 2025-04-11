---@class GraphPoint : GraphNode
---@field _parentNode GraphSegment
GraphPoint = CpObject(GraphNode)
GraphPoint.XML_KEY = "Point"
function GraphPoint:init()
    GraphNode.init(self)
    self._x = 0
    self._y = 0
    self._z = 0
    ---@type GraphTarget|nil
    self._target = nil
end

function GraphPoint.registerXmlSchema(xmlSchema, baseKey)
    local key = baseKey .. GraphPoint.XML_KEY .. "(?)"
    GraphTarget.registerXmlSchema(xmlSchema, key)
    xmlSchema:register(XMLValueType.VECTOR_3, 
        key .. "#pos", 
        "Position", {0,0,0})
    xmlSchema:register(XMLValueType.BOOL, 
        key .. "#hasTarget", 
        "Has associated Target?", false)
end

function GraphPoint:loadFromXMLFile(xmlFile, key)
    local pos = xmlFile:getValue(key .. "#pos", 
        self._x ,self._y, self._z)
    if pos then 
        self._x, self._y, self._z = unpack(pos)
    end
    if xmlFile:getValue(key .. "#hasTarget", false) then 
        self._target = GraphTarget(self)
        self._target:loadFromXMLFile(xmlFile, key)
    end
end

function GraphPoint:saveToXMLFile(xmlFile, key)
    xmlFile:setValue(key .. "#pos", self._x, self._y, self._z)
    if self._target then 
        xmlFile:setValue(key .. "#hasTarget", true)
        self._target:saveToXMLFile(xmlFile, key)
    end
end

function GraphPoint:writeStream(streamId, connection)
    streamWriteFloat32(streamId, self._x)
    streamWriteFloat32(streamId, self._y)
    streamWriteFloat32(streamId, self._z)
    streamWriteBool(streamId, self._target ~= nil)
    if self._target then 
        self._target:writeStream(streamId, connection)
    end
end

function GraphPoint:readStream(streamId, connection)
    self._x = streamReadFloat32(streamId)
    self._y = streamReadFloat32(streamId)
    self._z = streamReadFloat32(streamId)
    if streamReadBool(streamId) then 
        local target = GraphTarget(self)
        target:readStream(streamId, connection)
    end
end

---@param newNode GraphPoint
---@param unlink boolean|nil
function GraphPoint:copyTo(newNode, unlink)
    GraphNode.copyTo(self, newNode, unlink)
    if self._target then
        if unlink then
            newNode._target = GraphTarget()
            self._target:copyTo(newNode._target)
        else 
            newNode._target = self._target
        end
    end
    newNode._x = self._x
    newNode._y = self._y
    newNode._z = self._z
end

---@return GraphPoint
function GraphPoint:clone(unlink)
    local newPoint = GraphPoint()
    self:copyTo(newPoint, unlink)
    return newPoint
end

---@param hoveredNodeID string|nil
---@param selectedNodeIDs table<string, boolean>|nil
---@param isTemporary boolean|nil
function GraphPoint:draw(hoveredNodeID, selectedNodeIDs, isTemporary)
    local color = Color.new(0, 0, 1)
    if hoveredNodeID == self:getRelativeID() then 
        color = Color.new(1, 1, 1)
    elseif selectedNodeIDs ~= nil and selectedNodeIDs[self:getRelativeID()] ~= nil then
        color = Color.new(1, 1, 0)
    elseif isTemporary then
        color = Color.new(0, 1, 0)
    end
    DebugUtil.drawDebugSphere(self._x, self._y + 0.5, self._z, 
        1, 6, 6, color, false, false)
    local data = self:getDebugInfos()
    local yOffset = 0
    for _, line in ipairs(data) do 
        Utils.renderTextAtWorldPosition(self._x, self._y + 1, self._z, 
            line, getCorrectTextSize(0.012), yOffset)
        yOffset = yOffset + getCorrectTextSize(0.012)
    end
end

function GraphPoint:getDebugInfos()
    local data = GraphNode.getDebugInfos(self)
    if self._target then 
        data[#data + 1] = string.format("Target: %s", self._target:getName())
    end
    return data
end

---@param x number
---@param y number
---@param z number
function GraphPoint:setPosition(x, y, z)
    self._x = x
    self._y = y 
    self._z = z
end

---@param x number
---@param z number
function GraphPoint:setPosition2D(x, z)
    self._x = x
    if getTerrainHeightAtWorldPos then 
        self._y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z)
    else
        self._y = 0
    end
    self._z = z
end

---@return number, number, number
function GraphPoint:getPosition()
    return self._x, self._y, self._z
end

---@return number, number
function GraphPoint:getPosition2D()
    return self._x, self._z
end

---@param dx number
---@param dy number
---@param dz number
function GraphPoint:move(dx, dy, dz)
    if dx == nil or dy == nil or dz == nil then 
        return
    end
    self._x = self._x + dx
    self._y = self._y + dy
    self._z = self._z + dz
end

---@param dx number
---@param dz number
function GraphPoint:move2D(dx, dz)
    if dx == nil or dz == nil then 
        return
    end
    self._x = self._x + dx
    self._z = self._z + dz
end

---@param dx number
---@param dy number
---@param dz number
function GraphPoint:moveTo(dx, dy, dz)
    if dx == nil or dy == nil or dz == nil then 
        return
    end
    self._x = dx
    self._y = dy
    self._z = dz
end

---@param dx number
---@param dz number
function GraphPoint:moveTo2D(dx, dz)
    if dx == nil or dz == nil then 
        return
    end
    self._x = dx
    self._z = dz
end

---@param other GraphPoint
---@return number
function GraphPoint:getDistance2DToPoint(other)
    local dx, dz = other:getPosition2D()
    return MathUtil.vector2Length(self._x - dx, self._z - dz)
end

---@param dx number
---@param dz number
---@return number
function GraphPoint:getDistance2DTo(dx, dz)
    return MathUtil.vector2Length(self._x - dx, self._z - dz)
end

function GraphPoint:toVector()
    return Vector(self._x, -self._z)
end

-----------------------------
--- Target
-----------------------------

---@return boolean
function GraphPoint:hasTarget()
    return self._target ~= nil
end

---@return GraphTarget|nil
function GraphPoint:getTarget()
    return self._target
end

---@param name string
---@param noEventSend boolean|nil
---@return boolean
function GraphPoint:createTarget(name, noEventSend)
    if self:hasTarget() then 
        return false
    end
    if not noEventSend then 
        GraphCreateTargetEvent.sendEvent(self, name)
    end
    self._target = GraphTarget(self, name)
    return true
end

---@param noEventSend boolean|nil
---@return boolean
function GraphPoint:removeTarget(noEventSend)
    if not self:hasTarget() then 
        return false
    end
    if not noEventSend then 
        GraphRemoveTargetEvent.sendEvent(self)
    end
    self._target:delete()
    self._target = nil
    return true
end