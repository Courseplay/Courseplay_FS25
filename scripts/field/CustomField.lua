--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2022 Peter Vaiko

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

--[[

	A custom field is what the user created by driving around its edges
	and recording waypoints.

]]--

---@class CustomField
CustomField = CpObject()

CustomField.xmlSchema = XMLSchema.new("customField")
CustomField.xmlSchema:register(XMLValueType.STRING ,"customField#name", "Name") -- for backwards compatibility
CustomField.xmlSchema:register(XMLValueType.STRING ,"customField.vertices", "Vertices of the field polygon")

CustomField.rootXmlKey = "customField"

function CustomField:init()
    
end

function CustomField:setup(name, vertices)

    self.name = name or ""
    self.fieldId = name --- used for external mods
    self.fieldPlot = FieldPlot(true)
    self.fieldPlot:setVisible(true)

    self.vertices = vertices
    self:findFieldCenter()
    self.area = CpMathUtil.getAreaOfPolygon(vertices)
    self.fieldArea = self.area/10000 -- area in ha
    self.fieldPlot:setWaypoints(vertices)
end

function CustomField:debug(str, ...)
    CpUtil.debugFormat(CpDebug.DBG_COURSES, "Custom field" .. self.name .. ": " .. str, ...)
end

function CustomField:setVertices(vertices)
    self.vertices = vertices
end

function CustomField:delete()
    if self.fieldHotspot then
        g_currentMission:removeMapHotspot(self.fieldHotspot)
        self.fieldHotspot:delete()
    end
    self.fieldPlot:delete()
end

function CustomField:addHotspot()
    self.fieldHotspot = CustomFieldHotspot.new()
    self.fieldHotspot:setField(self)
    self.fieldHotspot:setOwnerFarmId(g_currentMission.playerSystem:getLocalPlayer().farmId)
    g_currentMission:addMapHotspot(self.fieldHotspot)
end

function CustomField:isPointOnField(x, z)
    return CpMathUtil.isPointInPolygon(self.vertices, x, z)
end

function CustomField:draw(map)
    if not self.fieldHotspot then
        -- add hotspot when draw first called. Can't create in the constructor as on game load
        -- when the custom fields are loaded there's no player yet
        self:addHotspot()
    end
    self.fieldPlot:draw(map)
end

-- FieldHotspot needs this
function CustomField:getName()
    -- prefix custom field numbers
    return self.name
end

function CustomField:setName(name)
    self.name = name
    self.fieldId = name --- used for external mods
    if self.fieldHotspot then 
        self.fieldHotspot.name = name
    end
end

function CustomField:getAreaInSqMeters()
    return self.area
end

--- If the course was not renamed, then get the field number.
function CustomField:getFieldNumber()
    local s = string.gsub(self.name,"CP--","")
    return s and tonumber(s)
end

function CustomField:getVertices()
    return self.vertices
end

function CustomField:findFieldCenter()
    -- calculating the centroid should be fine as long as the field is more or less concave.
    -- a more sophisticated method would be https://github.com/mapbox/polylabel
    local x, z = 0, 0
    for _, v in ipairs(self.vertices) do
        x = x + v.x
        z = z + v.z
    end
    -- FieldHotspot uses these
    self.posX = x / #self.vertices
    self.posZ = z / #self.vertices
end


function CustomField:saveToXml(xmlFile, baseKey,name)
    xmlFile:setValue(baseKey  .. '#name', name)
    xmlFile:setValue(baseKey  .. '.vertices', self:serializeVertices())
end

function CustomField:loadFromXml(xmlFile,baseKey)
    local vertices = CustomField.deserializeVertices(xmlFile:getValue(baseKey  .. '.vertices'))
    self:setup(nil,vertices)
end

function CustomField:writeStream(streamId, connection)
    streamWriteString(streamId, self.name)
    streamWriteString(streamId, self:serializeVertices())
end

function CustomField:serializeVertices()
    local serializedVertices = '\n' -- (pure cosmetic)
    for _, p in ipairs(self.vertices) do
        local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, p.x, 0, p.z)
        local serializedVertex = string.format('%.2f %.2f %.2f|\n', p.x, y, p.z)
        serializedVertices = serializedVertices .. serializedVertex
    end
    return serializedVertices
end

function CustomField.deserializeVertices(serializedVertices)
    local vertices = {}

    local lines = string.split(serializedVertices, '|')
    for _, line in ipairs(lines) do
        local p = {}
        p.x, p.y, p.z = string.getVector(line)
        -- just skip empty lines
        if p.x then
            table.insert(vertices, p)
        end
    end
    return vertices
end

function CustomField.createFromXmlFile(file)
    local field = CustomField()
    file:load(CustomField.xmlSchema,CustomField.rootXmlKey,
    CustomField.loadFromXml,field)
    field:setName(file:getName())
    return field
end

function CustomField.createFromStream(streamId, connection)
    local name = streamReadString(streamId)
    local serializedVertices = CustomField.readStreamVertices(streamId, connection)
    local customField = CustomField()
    customField:setup(name, CustomField.deserializeVertices(serializedVertices))
    customField:debug("Custom field with %d points loaded from stream.", #serializedVertices)
    return customField
end

function CustomField:writeToStream(streamId, connection)
    streamWriteString(streamId, self.name)
    CustomField.writeStreamVertices(self.vertices, streamId, connection)
end

function CustomField.writeStreamVertices(vertices, streamId, connection)
    streamWriteInt32(streamId, #vertices)
    for _, point in pairs(vertices) do 
        streamWriteFloat32(streamId, point.x)
        streamWriteFloat32(streamId, point.z)
    end
end

function CustomField.readStreamVertices(streamId, connection)
    local numVertices = streamReadInt32(streamId)
    local vertices = {}
    local p = {}
    for _=1, numVertices do 
        p = {
            x = streamReadFloat32(streamId),
            z = streamReadFloat32(streamId)
        }
        table.insert(vertices, p)
    end
    return vertices
end