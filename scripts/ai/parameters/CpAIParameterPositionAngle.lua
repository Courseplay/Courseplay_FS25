--- Position in the AI Menu.
---@class CpAIParameterPosition : AIParameterSetting
CpAIParameterPosition = CpObject(AIParameterSetting)
---@param data table
---@param vehicle table
---@param class table
function CpAIParameterPosition:init(data, vehicle, class)
	AIParameterSetting.init(self)
	if data == nil then 
		CpUtil.error("Data is nil for CpAIParameterPositionAngle!")
		return
	end
	self:initFromData(data, vehicle, class)
	self.guiParameterType = AIParameterType.POSITION
	self.positionType = CpAIParameterPositionAngle.POSITION_TYPES[data.positionParameterType]
end

function CpAIParameterPosition:saveToXMLFile(xmlFile, key, usedModNames)
	if self.x ~= nil then
		xmlFile:setFloat(key .. "#x", self.x)
		xmlFile:setFloat(key .. "#z", self.z)
	end
end

function CpAIParameterPosition:loadFromXMLFile(xmlFile, key)
	self.x = xmlFile:getFloat(key .. "#x", self.x)
	self.z = xmlFile:getFloat(key .. "#z", self.z)
end

function CpAIParameterPosition:readStream(streamId, connection)
	if streamReadBool(streamId) then
		local x = streamReadFloat32(streamId)
		local z = streamReadFloat32(streamId)

		self:setPosition(x, z)
	end
end

function CpAIParameterPosition:writeStream(streamId, connection)
	if streamWriteBool(streamId, self.x ~= nil) then
		streamWriteFloat32(streamId, self.x)
		streamWriteFloat32(streamId, self.z)
	end
end

function CpAIParameterPosition:setPosition(x, z)
	self.x = x
	self.z = z
end

function CpAIParameterPosition:getPosition()
	return self.x, self.z
end

function CpAIParameterPosition:getString()
	return string.format("< %.1f , %.1f >", self.x or 0, self.z or 0)
end

function CpAIParameterPosition:validate()
	if self.x == nil or self.z == nil then
		return false, g_i18n:getText("ai_validationErrorNoPosition")
	end

	if not g_currentMission.aiSystem:getIsPositionReachable(self.x, 0, self.z) then
		return false, g_i18n:getText("ai_validationErrorBlockedPosition")
	end

	return true, nil
end

function CpAIParameterPosition:setValue(x, z)
	self:setPosition(x, z)	
end


function CpAIParameterPosition:clone(...)
	return CpAIParameterPosition(self.data,...)
end

function CpAIParameterPosition:copy(setting)
	if self.data.isCopyValueDisabled then 
		return
	end
	self.x = setting.x 
	self.z = setting.z
end

function CpAIParameterPosition:__tostring()
	return string.format("CpAIParameterPosition(name=%s, text=%s)", self.name, self:getString())
end

--- Applies the current position to the map hotspot.
function CpAIParameterPosition:applyToMapHotspot(mapHotspot)
	if not self:getCanBeChanged() then 
		return false
	end
	local x, z = self:getPosition()
	if x ~= nil then
		mapHotspot:setWorldPosition(x, z)
		return true
	end
	return false
end

function CpAIParameterPosition:getPositionType()
	return self.positionType
end

--- Is the Position within 1m distance?
---@param otherPosition CpAIParameterPosition
---@return boolean
function CpAIParameterPosition:isAlmostEqualTo(otherPosition)
	local x, z = otherPosition:getPosition()
	if x ~= nil and self.x ~= nil then
		return MathUtil.vector2Length(self.x - x, self.z - z) <= 1
	end
	return false
end

--- Position with angle in the AI Menu.
---@class CpAIParameterPositionAngle : CpAIParameterPosition
CpAIParameterPositionAngle = CpObject(CpAIParameterPosition)
	--- These are the different ai map hotspots, that can be set in the ai menu.
CpAIParameterPositionAngle.POSITION_TYPES = {
		DRIVE_TO = 0,	--- with angle
		FIELD_OR_SILO = 1, --- without angle
		UNLOAD = 2, --- with angle
		LOAD = 3 --- with angle
	}
---@param data table
---@param vehicle table
---@param class table
function CpAIParameterPositionAngle:init(data, vehicle, class)
	CpAIParameterPosition.init(self, data, vehicle, class)
	self.guiParameterType = AIParameterType.POSITION_ANGLE
	self.snappingAngle = math.rad(0)
end

function CpAIParameterPositionAngle:clone(...)
	return CpAIParameterPositionAngle(self.data,...)
end

function CpAIParameterPositionAngle:copy(setting)
	if self.data.isCopyValueDisabled then 
		return
	end
	CpAIParameterPosition.copy(self, setting)
	self.angle = setting.angle
	self.snappingAngle = setting.snappingAngle
end

function CpAIParameterPositionAngle:readStream(streamId, connection)
	CpAIParameterPosition.readStream(self, streamId, connection)
	if streamReadBool(streamId) then
		local angle = streamReadUIntN(streamId, 9)
		self:setAngle(math.rad(angle))
	end
	
end

function CpAIParameterPositionAngle:writeStream(streamId, connection)
	CpAIParameterPosition.writeStream(self, streamId, connection)
	if streamWriteBool(streamId, self.angle ~= nil) then
		local angle = math.deg(self.angle)
		streamWriteUIntN(streamId, angle, 9)
	end
end

function CpAIParameterPositionAngle:saveToXMLFile(xmlFile, key, usedModNames)
	CpAIParameterPosition.saveToXMLFile(self, xmlFile, key, usedModNames)
	if self.angle ~= nil then
		xmlFile:setFloat(key .. "#angle", self.angle)
	end
end

function CpAIParameterPositionAngle:loadFromXMLFile(xmlFile, key)
	CpAIParameterPosition.loadFromXMLFile(self, xmlFile, key)
	self.angle = xmlFile:getFloat(key .. "#angle", self.angle)
end

function CpAIParameterPositionAngle:getAngle()
	return self.angle
end

function CpAIParameterPositionAngle:setAngle(angleRad)
	angleRad = angleRad % (2 * math.pi)

	if angleRad < 0 then
		angleRad = angleRad + 2 * math.pi
	end

	if self.snappingAngle > 0 then
		local numSteps = MathUtil.round(angleRad / self.snappingAngle, 0)
		angleRad = numSteps * self.snappingAngle
	end

	self.angle = angleRad
end

function CpAIParameterPositionAngle:getDirection()
	if self.angle == nil then
		return 0, 1
	end

	local xDir, zDir = MathUtil.getDirectionFromYRotation(self.angle)

	return xDir, zDir
end

function CpAIParameterPositionAngle:setSnappingAngle(angle)
	self.snappingAngle = math.abs(angle)
end

function CpAIParameterPositionAngle:getSnappingAngle()
	return self.snappingAngle
end

--- Applies the current position and angle to the map hotspot.
function CpAIParameterPositionAngle:applyToMapHotspot(mapHotspot)
	if not self:getCanBeChanged() then 
		return false
	end
	if self.angle ~=nil and CpAIParameterPosition.applyToMapHotspot(self, mapHotspot) then
		mapHotspot:setWorldRotation(self.angle + math.pi)
		return true
	end
	return false
end

function CpAIParameterPositionAngle:setValue(x, z, angle)
	CpAIParameterPosition.setValue(self, x, z)
	if angle ~= nil then 
		self.angle = angle
	end
end

function CpAIParameterPositionAngle:getValue()
	return self.x, self.z, self.angle
end

--- Is the Position within 1m distance and angle within 1° degree?
---@param otherPosition CpAIParameterPositionAngle
---@return boolean
function CpAIParameterPositionAngle:isAlmostEqualTo(otherPosition)
	local angle = otherPosition.getAngle and otherPosition:getAngle()
	if angle ~= nil and self.angle ~= nil then
		return math.abs(math.deg(MathUtil.getAngleDifference(angle, self.angle))) < 1 
			and CpAIParameterPosition.isAlmostEqualTo(self, otherPosition)
	end
	return false
end

function CpAIParameterPositionAngle:getString()
	return string.format("< %.1f , %.1f | %d° >", self.x or 0, self.z or 0, math.deg(self.angle or 0))
end

function CpAIParameterPositionAngle:validate()
	local isValid, errorMessage = CpAIParameterPosition.validate(self)

	if not isValid then
		return false, errorMessage
	end

	if self.angle == nil then
		return false, g_i18n:getText("ai_validationErrorNoAngle")
	end

	return true, nil
end

function CpAIParameterPositionAngle:__tostring()
	return string.format("CpAIParameterPositionAngle(name=%s, text=%s)", self.name, self:getString())
end