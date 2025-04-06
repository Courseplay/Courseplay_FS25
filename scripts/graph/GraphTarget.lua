---@class GraphTarget
GraphTarget = CpObject()
GraphTarget.uniqueID = 0
function GraphTarget.getNextUniqueID()
    GraphTarget.uniqueID = GraphTarget.uniqueID + 1
    return GraphTarget.uniqueID
end

function GraphTarget:init(point, name)
    ---@type GraphPoint
    self._point = point
    self._name = name or "???"
    self._uniqueID = GraphTarget.getNextUniqueID()
    g_graph:onTargetCreated(self)
end

function GraphTarget:delete()
    g_graph:onTargetDeleted(self)
end

function GraphTarget.registerXmlSchema(xmlSchema, baseKey)
    xmlSchema:register(XMLValueType.STRING, baseKey .. "#name", "Target name")
end

function GraphTarget:loadFromXMLFile(xmlFile, baseKey)
    self._name = xmlFile:getValue(baseKey .. "#name", "")
end

function GraphTarget:saveToXMLFile(xmlFile, baseKey)
    xmlFile:setValue(baseKey .. "#name", self._name)
end

---@param otherTarget GraphTarget
function GraphTarget:copyTo(otherTarget)
    otherTarget._name = self._name
end

function GraphTarget:getUniqueID()
    return self._uniqueID
end

---@return string
function GraphTarget:getName()
    return self._name
end

---@param name string
function GraphTarget:setName(name)
    self._name = name
end

---@return Vector
function GraphTarget:toVector()
    local x, z = self._point:getPosition2D()
    return Vector(x, -z)
end

---@return GraphPoint
function GraphTarget:getPoint()
    return self._point
end