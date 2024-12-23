---@class AIMessageErrorIsFull 
AIMessageErrorIsFull = CpObject(AIMessage, AIMessage.new)
AIMessageErrorIsFull.name = "CP_ERROR_FULL"
function AIMessageErrorIsFull:getI18NText()
	return g_i18n:getText("CP_ai_messageErrorIsFull")
end

---@class AIMessageCpError 
AIMessageCpError = CpObject(AIMessage, AIMessage.new)
AIMessageCpError.name = "CP_ERROR"
function AIMessageCpError:getI18NText()
	return g_i18n:getText("CP_ai_messageError")
end

---@class AIMessageCpErrorNoPathFound 
AIMessageCpErrorNoPathFound = CpObject(AIMessage, AIMessage.new)
AIMessageCpErrorNoPathFound.name = "CP_ERROR_NO_PATH_FOUND"
function AIMessageCpErrorNoPathFound:getI18NText()
	return g_i18n:getText("CP_ai_messageErrorNoPathFound")
end

---@class AIMessageErrorWrongBaleWrapType 
AIMessageErrorWrongBaleWrapType = CpObject(AIMessage, AIMessage.new)
AIMessageErrorWrongBaleWrapType.name = "CP_ERROR_WRONG_WRAP_TYPE"
function AIMessageErrorWrongBaleWrapType:getI18NText()
	return g_i18n:getText("CP_ai_messageErrorWrongBaleWrapType")
end

---@class AIMessageErrorGroundUnloadNotSupported 
AIMessageErrorGroundUnloadNotSupported = CpObject(AIMessage, AIMessage.new)
AIMessageErrorGroundUnloadNotSupported.name = "CP_ERROR_GROUND_UNLOAD_NOT_SUPPORTED"
function AIMessageErrorGroundUnloadNotSupported:getI18NText()
	return g_i18n:getText("CP_ai_messageErrorGroundUnloadNotSupported")
end

---@class AIMessageErrorCutterNotSupported 
AIMessageErrorCutterNotSupported = CpObject(AIMessage, AIMessage.new)
AIMessageErrorCutterNotSupported.name = "CP_ERROR_CUTTER_NOT_SUPPORTED"
function AIMessageErrorCutterNotSupported:getI18NText()
	return g_i18n:getText("CP_ai_messageErrorCutterNotSupported")
end

---@class AIMessageErrorAutomaticCutterAttachNotActive 
AIMessageErrorAutomaticCutterAttachNotActive = CpObject(AIMessage, AIMessage.new)
AIMessageErrorAutomaticCutterAttachNotActive.name = "CP_ERROR_AUTOMATIC_CUTTER_ATTACH_NOT_ACTIVE"
function AIMessageErrorAutomaticCutterAttachNotActive:getI18NText()
	return g_i18n:getText("CP_ai_messageErrorAutomaticCutterAttachNotActive")
end

---@class AIMessageErrorWrongMissionFruitType
AIMessageErrorWrongMissionFruitType = CpObject(AIMessage, AIMessage.new)
AIMessageErrorWrongMissionFruitType.name = "CP_ERROR_WRONG_MISSION_FRUIT_TYPE"
function AIMessageErrorWrongMissionFruitType:getI18NText()
	return g_i18n:getText("CP_ai_messageErrorWrongMissionFruitType")
end

CpAIMessages = {}
function CpAIMessages.register()
	local function register(messageClass)
		g_currentMission.aiMessageManager:registerMessage(messageClass.name, messageClass)
	end
	register(AIMessageErrorIsFull)
	register(AIMessageCpError)
	register(AIMessageCpErrorNoPathFound)
	register(AIMessageErrorWrongBaleWrapType)
	register(AIMessageErrorGroundUnloadNotSupported)
	register(AIMessageErrorCutterNotSupported)
	register(AIMessageErrorAutomaticCutterAttachNotActive)
	register(AIMessageErrorWrongMissionFruitType)
end

--- Another ugly hack, as the giants code to get the message index in mp isn't working ..
local function getMessageIndex(aiMessageManager, superFunc, messageObject, ...)
	local ix = superFunc(aiMessageManager, messageObject, ...)
	if ix == nil then 
		return aiMessageManager.nameToIndex[messageObject.name]
	end
	return ix
end
AIMessageManager.getMessageIndex = Utils.overwrittenFunction(AIMessageManager.getMessageIndex, getMessageIndex)
