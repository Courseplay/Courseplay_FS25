
--- Handles the activation/deactivation of info texts for the vehicle.
---@class CpInfoTexts
CpInfoTexts = {}
CpInfoTexts.MOD_NAME = g_currentModName
CpInfoTexts.NAME = ".cpInfoTexts"
CpInfoTexts.SPEC_NAME = CpInfoTexts.MOD_NAME .. CpInfoTexts.NAME
CpInfoTexts.KEY = "."..CpInfoTexts.SPEC_NAME.."."
function CpInfoTexts.initSpecialization()
	local schema = Vehicle.xmlSchemaSavegame

end

function CpInfoTexts.register(typeManager,typeName,specializations)
	if CpInfoTexts.prerequisitesPresent(specializations) then
		typeManager:addSpecialization(typeName, CpInfoTexts.SPEC_NAME)
	end
end


function CpInfoTexts.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(CpAIWorker, specializations) 
end

function CpInfoTexts.registerEventListeners(vehicleType)	
	SpecializationUtil.registerEventListener(vehicleType, "onLoad", CpInfoTexts)
	SpecializationUtil.registerEventListener(vehicleType, "onPreDelete", CpInfoTexts)
	SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", CpInfoTexts)
	SpecializationUtil.registerEventListener(vehicleType, "onReadStream", CpInfoTexts)
	SpecializationUtil.registerEventListener(vehicleType, "onWriteUpdateStream", CpInfoTexts)
	SpecializationUtil.registerEventListener(vehicleType, "onReadUpdateStream", CpInfoTexts)
	SpecializationUtil.registerEventListener(vehicleType, "onEnterVehicle", CpInfoTexts)
	--- Auto drive start event, so we can reset the info texts on ad take over.
	SpecializationUtil.registerEventListener(vehicleType, "onStartAutoDrive", CpInfoTexts)
end
function CpInfoTexts.registerFunctions(vehicleType)
	SpecializationUtil.registerFunction(vehicleType, 'setCpInfoTextActive', CpInfoTexts.setCpInfoTextActive)
    SpecializationUtil.registerFunction(vehicleType, 'resetCpActiveInfoText', CpInfoTexts.resetCpActiveInfoText)
	SpecializationUtil.registerFunction(vehicleType, 'resetCpAllActiveInfoTexts', CpInfoTexts.resetCpAllActiveInfoTexts)
	SpecializationUtil.registerFunction(vehicleType, 'getCpActiveInfoTexts', CpInfoTexts.getCpActiveInfoTexts)
	SpecializationUtil.registerFunction(vehicleType, 'getIsCpInfoTextActive', CpInfoTexts.getIsCpInfoTextActive)
end

function CpInfoTexts:onLoad(savegame)
	--- Register the spec: spec_CpVehicleSettings
	self.spec_cpInfoTexts = self["spec_" .. CpInfoTexts.SPEC_NAME]
    local spec = self.spec_cpInfoTexts
	spec.activeInfoTexts = {}
	g_infoTextManager:registerVehicle(self, self.id)
	spec.dirtyFlag = self:getNextDirtyFlag()
end

function CpInfoTexts:onPreDelete()
	g_infoTextManager:unregisterVehicle(self.id)
end

function CpInfoTexts:onWriteUpdateStream(streamId, connection, dirtyMask)
	local spec = self.spec_cpInfoTexts
    if not connection:getIsServer() and streamWriteBool(streamId, bitAND(dirtyMask, spec.dirtyFlag) ~= 0) then
		CpInfoTexts.onWriteStream(self, streamId, connection)
	end
end

function CpInfoTexts:onReadUpdateStream(streamId, timestamp, connection)
	if connection:getIsServer() and streamReadBool(streamId) then
		CpInfoTexts.onReadStream(self, streamId, connection)
	end
end

function CpInfoTexts:onReadStream(streamId, connection)
	local mask = streamReadUIntN(streamId, InfoTextManager.NUM_BITS + 1)
	CpInfoTexts.setFromBitMask(self, mask)
end

function CpInfoTexts:onWriteStream(streamId, connection)
	local mask = CpInfoTexts.getBitMask(self)
	streamWriteUIntN(streamId, mask, InfoTextManager.NUM_BITS + 1)
end

function CpInfoTexts:onEnterVehicle(isControlling)
	local spec = self.spec_cpInfoTexts
	if not self:getIsCpActive() and next(spec.activeInfoTexts) ~= nil then
		if self.isServer then
			self:resetCpAllActiveInfoTexts()
		end
	end
end

--- Makes sure the info texts are reset, when auto drive takes over.
function CpInfoTexts:onStartAutoDrive()
	if self.isServer then
		local spec = self.spec_cpInfoTexts
		if next(spec.activeInfoTexts) ~= nil then
			self:resetCpAllActiveInfoTexts()
		end
	end
end

function CpInfoTexts:raiseDirtyFlag()
	if self.isServer then
		local spec = self.spec_cpInfoTexts
		self:raiseDirtyFlags(spec.dirtyFlag)
	end
end

--- Activates a given info text.
---@param infoText CpInfoTextElement
function CpInfoTexts:setCpInfoTextActive(infoText)
	if self.isServer then
		if infoText and infoText.id then 
			local spec = self.spec_cpInfoTexts
			if spec.activeInfoTexts[infoText.id] == nil then 
				spec.activeInfoTexts[infoText.id] = infoText
				CpInfoTexts.raiseDirtyFlag(self)
			end
		end
	end
end

--- Resets a given info text.
---@param infoText CpInfoTextElement
function CpInfoTexts:resetCpActiveInfoText(infoText)
	if self.isServer then
		if infoText and infoText.id then 
			local spec = self.spec_cpInfoTexts
			if spec.activeInfoTexts[infoText.id] then 
				spec.activeInfoTexts[infoText.id] = nil
				CpInfoTexts.raiseDirtyFlag(self)
			end
		end
	end
end

--- Clears all active info texts.
function CpInfoTexts:resetCpAllActiveInfoTexts()
	if self.isServer then
		local spec = self.spec_cpInfoTexts
		spec.activeInfoTexts = {}
		CpInfoTexts.raiseDirtyFlag(self)
		CpUtil.debugVehicle(CpDebug.DBG_HUD, self, "All info texts were cleared.")
	end
end

function CpInfoTexts:getCpActiveInfoTexts()
	local spec = self.spec_cpInfoTexts
	return spec.activeInfoTexts
end

function CpInfoTexts:getIsCpInfoTextActive(infoText)
	if infoText and infoText.id then
		local spec = self.spec_cpInfoTexts
		return spec.activeInfoTexts[infoText.id] ~= nil
	end
end

--- Every info text has a unique binary id, so it can be synchronized as a bit sequence.
function CpInfoTexts:getBitMask()
	local mask = 0
	local spec = self.spec_cpInfoTexts
	for id, _ in pairs(spec.activeInfoTexts) do 
		mask = mask + id
	end
	CpUtil.debugVehicle(CpDebug.DBG_HUD, self, "server bit mask: %d", mask)
	return mask
end

--- Every info text has a unique binary id, so it can be synchronized as a bit sequence.
function CpInfoTexts:setFromBitMask(bitMask)
	CpUtil.debugVehicle(CpDebug.DBG_HUD, self, "client bit mask: %d", bitMask)
	local spec = self.spec_cpInfoTexts
	local bits = MathUtil.getBinary(bitMask)
	local id
	spec.activeInfoTexts = {}
	for ix, bit in ipairs(bits) do 
		id = bitShiftLeft(1, ix-1)
		if bit == 1 then
			spec.activeInfoTexts[id] = g_infoTextManager:getInfoTextById(id)
		end
	end
end

--- Debug test function
---@param ix number|nil optional bit mask to set.
function CpInfoTexts.debug(ix)
	local vehicle = CpUtil.getCurrentVehicle()
	if vehicle and vehicle.spec_cpInfoTexts then 
		local spec = vehicle.spec_cpInfoTexts
		CpUtil.infoVehicle(vehicle, "Current bit mask: %s", CpInfoTexts.getBitMask(vehicle))
		for i, activeInfoText in pairs(spec.activeInfoTexts) do 
			CpUtil.infoVehicle(vehicle, "%s", tostring(activeInfoText))
		end
		if ix and tonumber(ix) ~= nil then 
			CpUtil.infoVehicle(vehicle, "-----------------------------------------------------------------------------------------")
			CpUtil.infoVehicle(vehicle, "Set to bit mask: %s", ix)
			CpInfoTexts.setFromBitMask(vehicle, ix)
			for i, activeInfoText in pairs(spec.activeInfoTexts) do 
				CpUtil.infoVehicle(vehicle, "%s", tostring(activeInfoText))
			end
		end
	else 
		CpUtil.info("No valid vehicle is entered!")
	end
end