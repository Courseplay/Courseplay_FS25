CpUtil = {}

---Prints a table to an xml File recursively.
---Basically has the same function as DebugUtil.printTableRecursively() except for saving the prints to an xml file
---@param value table is the last relevant value from parent table
---@param parentName string
---@param depth number is the current depth of the iteration
---@param maxDepth number represent the max iterations 
---@param xmlFile number xmlFile to save in
---@param baseKey string parent key 
function CpUtil.printTableRecursivelyToXML(value, parentName, depth, maxDepth, xmlFile, baseKey)
	depth = depth or 0
	maxDepth = maxDepth or 3
	if depth > maxDepth then
		return
	end
	local key = string.format('%s.depth:%d', baseKey, depth)
	local k = 0
	for i, j in pairs(value) do
		local key = string.format('%s(%d)', key, k)
		local valueType = type(j) 
		setXMLString(xmlFile, key .. '#valueType', tostring(valueType))
		setXMLString(xmlFile, key .. '#index', tostring(i))
		setXMLString(xmlFile, key .. '#value', tostring(j))
		setXMLString(xmlFile, key .. '#parent', tostring(parentName))
		if valueType == "table" then
			CpUtil.printTableRecursivelyToXML(j, parentName.."."..tostring(i), depth+1, maxDepth, xmlFile, key)
		end
		k = k + 1
	end
end

---Prints a global variable to an xml File.
---@param variableName string global variable to print to xmlFile
---@param maxDepth number represent the max iterations 
function CpUtil.printVariableToXML(variableName, maxDepth, printToSeparateXmlFiles)
	local baseKey = 'CpDebugPrint'
	local filePath
	if printToSeparateXmlFiles and tonumber(printToSeparateXmlFiles)>0 then 
		local fileName = string.gsub(variableName, ":", "_")..".xml"
		filePath = string.format("%s/%s", g_Courseplay.debugPrintDir, fileName)
	else 
		filePath = g_Courseplay.defaultDebugPrintPath
	end
	CpUtil.info("Trying to print to xml file: %s", filePath)
	local xmlFile = createXMLFile("xmlFile", filePath, baseKey);
	local xmlFileValid = xmlFile and xmlFile ~= 0 or false
	if not xmlFileValid then
		CpUtil.info("xmlFile(%s) not valid!", filePath)
		return 
	end
	setXMLString(xmlFile, baseKey .. '#maxDepth', tostring(maxDepth))
	local depth = maxDepth and math.max(1, tonumber(maxDepth)) or 1
	local value = CpUtil.getVariable(variableName)
	local valueType = type(value)
	local key = string.format('%s.depth:%d', baseKey, 0)
	if value then
		setXMLString(xmlFile, key .. '#valueType', tostring(valueType))
		setXMLString(xmlFile, key .. '#variableName', tostring(variableName))
		if valueType == 'table' then		
			CpUtil.printTableRecursivelyToXML(value, tostring(variableName), 1, depth, xmlFile, key)
			local mt = getmetatable(value)
			if mt and type(mt) == 'table' then
				CpUtil.printTableRecursivelyToXML(mt, tostring(variableName), 1, depth, xmlFile, key..'-metaTable')
			end
		else 
			setXMLString(xmlFile, key .. '#valueType', tostring(valueType))
			setXMLString(xmlFile, key .. '#value', tostring(value))
		end
	else 
		setXMLString(xmlFile, key .. '#value', tostring(value))
	end
	saveXMLFile(xmlFile)
	delete(xmlFile)
end

---Prints a variable to the console or a xmlFile.
---@param variableName string name of the variable, can be multiple levels
---@param maxDepth number maximum depth, 1 by default
function CpUtil.printVariable(variableName, maxDepth)
	print(string.format('%s - depth: %s', tostring(variableName), tostring(maxDepth)))
	local depth = maxDepth and math.max(1, tonumber(maxDepth)) or 1
	local value = CpUtil.getVariable(variableName)
	local valueType = type(value)
	if value then
		print(string.format('Printing %s (%s), depth %d', variableName, valueType, depth))
		if valueType == 'table' then
			DebugUtil.printTableRecursively(value, '  ', 1, depth)
			local mt = getmetatable(value)
			if mt and type(mt) == 'table' then
				print('-- metatable -->')
				DebugUtil.printTableRecursively(mt, '  ', 1, depth)
			end
		else
			print(variableName .. ': ' .. tostring(value))
		end
	else
		return(variableName .. ' is nil')
	end
	return('Printed variable ' .. variableName)
end


--- get a reference pointing to the global variable 'variableName'
-- can handle multiple levels (but not arrays, yet) like foo.bar
function CpUtil.getVariable(variableName)
	print(variableName)
	local f = getfenv(0).loadstring('return ' .. variableName)
	return f and f() or nil
end

--- (Safely) get the name of a vehicle or implement.
---@param object table vehicle or implement
function CpUtil.getName(object)
	if object == nil then 
		return 'Unknown'
	end
	if object == CpUtil then
		return 'ERROR, calling CpUtil.getName with : !'
	end
	local helperName = '-'
	if object == object.rootVehicle then
		helperName = object.id
	end
	return object.getName and object:getName() .. '/' .. helperName or 'Unknown'
end

function CpUtil.internalPrint(tag, ...)
	CpUtil.try(
		function (...)
			local updateLoopIndex = g_updateLoopIndex and g_updateLoopIndex or 0
			local timestamp = getDate( ":%S")
			local infoString = string.format('%s [%s lp%d]', timestamp, tag or "---", updateLoopIndex)
			print(string.format('%s %s', infoString, string.format(...)))
		end, ...)
end

function CpUtil.internalPrintVehicle(vehicle, tag, str, ...)
	str = string.format("%s: %s", CpUtil.getName(vehicle), str)
	CpUtil.internalPrint(tag, str, ...)
end

function CpUtil.internalPrintImplement(implement, tag, str, ...)
	str = string.format("%s: %s", CpUtil.getName(implement), str)
	CpUtil.internalPrintVehicle(implement.rootVehicle, tag, str, ...)
end

-- convenience debug function that expects string.format() arguments,
-- CpUtil.debugVehicle( CpDebug.DBG_TURN, "fill level is %.1f, mode = %d", fillLevel, mode )
---@param channel number
function CpUtil.debugFormat(channel, ...)
	if CpDebug and CpDebug:isChannelActive(channel) then
		CpUtil.internalPrint(CpDebug:getText(channel), ...)
	end
end

---@return boolean true if debug is enabled for this vehicle, or vehicle is invalid
function CpUtil.debugEnabledForVehicle(vehicle)
	local rootVehicle = vehicle and vehicle.rootVehicle
	local enabled = rootVehicle == nil or rootVehicle.getCpSettings == nil or CpUtil.isVehicleDebugActive(rootVehicle)
	return enabled
end

-- convenience debug function to show the vehicle name and expects string.format() arguments, 
-- CpUtil.debugVehicle( CpDebug.DBG_TURN, vehicle, "fill level is %.1f, mode = %d", fillLevel, mode )
---@param channel number
---@param vehicle table
function CpUtil.debugVehicle(channel, vehicle, ...)
	if CpDebug and CpDebug:isChannelActive(channel) and CpUtil.debugEnabledForVehicle()  then
		CpUtil.internalPrintVehicle(vehicle, CpDebug:getText(channel), ...)
	end
end

--- Wrapper for callers who want to suppress writing the message to the log based on a condition
---@param enabled boolean only write the debug message if this is true, otherwise do nothing
---@param channel number
---@param vehicle table
function CpUtil.debugVehicleIf(enabled, channel, vehicle, ...)
	if enabled then
		CpUtil.debugVehicle(channel, vehicle, ...)
	end
end

--- Debug function for implements, that calls CpUtil.debugVehicle, with the root vehicle. 
---@param channel number
---@param implement table
function CpUtil.debugImplement(channel, implement, str, ...)
	local rootVehicle = implement and implement.rootVehicle or implement
	CpUtil.debugVehicle(channel, rootVehicle, 
		CpUtil.getName(implement) .. ": " .. str, ...)
end

function CpUtil.isVehicleDebugActive(vehicle)
	return vehicle and vehicle:getCpSettings() and vehicle:getCpSettings().debugActive and vehicle:getCpSettings().debugActive:getValue()
end

function CpUtil.info(...)
	CpUtil.internalPrint("info", ...)
end

function CpUtil.infoVehicle(vehicle, ...)
	CpUtil.internalPrintVehicle(vehicle, "info", ...)
end

function CpUtil.infoImplement(implement, ...)
	CpUtil.internalPrintImplement(implement, "info", ...)
end

--- The same as CpUtil.info(), but also uses printCallstack()
function CpUtil.error(...)
	printCallstack()
	CpUtil.internalPrint("error", ...)
end

function CpUtil.errorVehicle(vehicle, ...)
	printCallstack()
	CpUtil.internalPrintVehicle( vehicle, "error", ...)
end

function CpUtil.errorImplement(implement, ...)
	printCallstack()
	CpUtil.internalPrintImplement(implement, "error", ...)
end

--- Create a node at x, z, direction according to yRotation.
--- If rootNode is given, make that the parent node, otherwise the parent is the terrain root node
---@param name string
---@param x number
---@param z number
---@param yRotation number
---@param rootNode number|nil
function CpUtil.createNode(name, x, z, yRotation, rootNode)
	local node = createTransformGroup(name)
	link(rootNode or g_currentMission.terrainRootNode, node)
	-- y is zero when we link to an existing node
	local y = rootNode and 0 or getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z);
	setTranslation( node, x, y, z );
	setRotation( node, 0, yRotation, 0);
	return node
end

--- Safely destroy a node
function CpUtil.destroyNode(node)
	if node and entityExists(node) then
		unlink(node)
		delete(node)
	end
end

---@param node number
---@param alignToGround boolean|nil
---@param yOffset number|nil
---@param text string|nil
function CpUtil.drawDebugNode(node, alignToGround, yOffset, text)
	if node and entityExists(node) then
		DebugUtil.drawDebugNode(node, text or getName(node), alignToGround, yOffset)
	end
end

--- Executes a function and throws a callstack, when an error appeared.
--- Additionally the first return value is a status, if the function was executed correctly.
---@param func function function to be executed.
---@param ... any parameters for the function, for class function the first parameter needs to be self.
---@return boolean was the code execution successfully and no error appeared.
---@return any returnValues if the code was successfully run, then all return values will be normally returned, else only a error message is returned.
function CpUtil.try(func, ...)
	local data = {xpcall(func, function(err) printCallstack(); return err end, ...)}
	local status = data[1]
	if not status then
		CpUtil.info(data[2])
		return status, tostring(data[2])
	end
	return unpack(data)
end

--- Same as the Giants xmlFile:setValue() function, but won't crash if it gets a nil value,
--- instead just silently ignores it
---@param xmlFile
---@param key string
---@param value any|nil
function CpUtil.setXmlValue(xmlFile, key, value)
	if value ~= nil then
		xmlFile:setValue(key, value)
	end
end

--- Gets the saved values from an xml string.
function CpUtil.getXmlVectorValues(str)
	if str == nil then
		printCallstack()
		return nil
	end

	local values = str:trim():split(" ")

	if values == nil or #values <= 0 then 
		printCallstack()
		return 
	end

	local results = {}
	local v 
	for i = 1, #values do
		v = tonumber(values[i])
		if not v then 
			if values[i] == "true" then 
				v = true
			elseif values[i] == "false" then 
				v = false
			else
				v = nil
			end
		end
		results[i] = v
	end

	return results
end

--- Adds all values to a string, separated by " ".
--- Converts boolean values to "true" or "false" and nil to "-".
function CpUtil.getXmlVectorString(data)
	local values = {}
	for i, k in ipairs(data) do 
		table.insert(values, k ~= nil and tostring(k) or "-")
	end
	return table.concat(values, " ")
end

--- Helper functions to write and read optional values to the stream (until Giants implements a proper serialization/
--- deserialization API), written by GitHub Copilot
function CpUtil.streamWriteBool(streamId, value)
	if value == nil then
		streamWriteBool(streamId, false)
	else
		streamWriteBool(streamId, true)
		streamWriteBool(streamId, value)
	end
end

function CpUtil.streamReadBool(streamId)
	if streamReadBool(streamId) then
		return streamReadBool(streamId)
	end
	return nil
end

function CpUtil.streamWriteString(streamId, value)
	if value == nil then
		streamWriteBool(streamId, false)
	else
		streamWriteBool(streamId, true)
		streamWriteString(streamId, value)
	end
end

function CpUtil.streamReadString(streamId)
	if streamReadBool(streamId) then
		return streamReadString(streamId)
	end
	return nil
end

function CpUtil.streamWriteInt32(streamId, value)
	if value == nil then
		streamWriteBool(streamId, false)
	else
		streamWriteBool(streamId, true)
		streamWriteInt32(streamId, value)
	end
end

function CpUtil.streamReadInt32(streamId)
	if streamReadBool(streamId) then
		return streamReadInt32(streamId)
	end
	return nil
end


--- Gets a class from a global class name.
---@param className string
---@return table classObject that was found.
function CpUtil.getClassObject(className)
	local parts = string.split(className, ".")
	local currentTable = _G[parts[1]]

	if type(currentTable) ~= "table" then
		return nil
	end

	for i = 2, #parts do
		currentTable = currentTable[parts[i]]

		if type(currentTable) ~= "table" then
			return nil
		end
	end

	return currentTable
end

--- Converts all invalid filename characters to '_' for now. 
function CpUtil.cleanFilePath(name)
	name = string.gsub(name, "<", "_")
	name = string.gsub(name, ">", "_")
	name = string.gsub(name, ":", "_")
	name = string.gsub(name, '"', "_")
	name = string.gsub(name, "/", "_")
	name = string.gsub(name, '\\', "_")
	name = string.gsub(name, "|", "_")
	name = string.gsub(name, '?', "_")
	name = string.gsub(name, "*", "_")
	return name
end

--- Adds new states.
---@param states table|nil current states
---@param newStates table new states to be added
---@return table combined states
function CpUtil.initStates(states, newStates)
    if states == nil then
        states = {}
    end
    for key, state in pairs(newStates) do
        states[key] = { name = tostring(key), properties = state }
    end
	return states
end

--- Copies the states.
---@param states table current states
---@param newStates table new states to add
---@return table combined states
function CpUtil.copyStates(states, newStates)
	if states == nil then
        states = {}
    end
	for key, state in pairs(newStates) do
        states[key] = state
    end
	return states
end

--- Is the state part of the given states?
---@param myState table current state
---@param states table states table
---@return boolean
function CpUtil.isStateOneOf(myState, states)
    for _, state in pairs(states) do
        if myState == state then
            return true
        end
    end
    return false
end

-- Return all fruitTypeIndexes where a fruitType needs preparation. 
--
-- Preparation marks an root vegetable since this is the only factor that diversifies them from normal fruit types
-- SUGARCANE is an exception and ignored
function CpUtil.getAllRootVegetables()
    local rootVegetables = {}
    for _, fruitTypeData in pairs(g_fruitTypeManager.fruitTypes) do
        local minPreparingGrowthState = fruitTypeData.minPreparingGrowthState
        local preparedGrowthState = fruitTypeData.preparedGrowthState
        local name = fruitTypeData.name

        -- check if fruit is needs herb removement to be harvested
        if minPreparingGrowthState ~= -1 and preparedGrowthState ~= -1 and name ~= "SUGARCANE" then
			local fruitType = g_fruitTypeManager:getFruitTypeByName(name)
            if fruitType ~= nil then
				table.insert(rootVegetables, fruitType.index)
            end
        end
    end

    return rootVegetables
end

---@return table|nil the currently selected/controlled vehicle, formerly known as g_currentMission.controlledVehicle
function CpUtil.getCurrentVehicle()
	if g_localPlayer == nil then 
		CpUtil.error("Failed to get current vehicle, as the local player is nil!")
		return nil
	end
	return g_localPlayer:getCurrentVehicle()
end

function CpUtil.getDefaultCollisionFlags()
	return CollisionFlag.DEFAULT + CollisionFlag.TREE + CollisionFlag.DYNAMIC_OBJECT + 
		CollisionFlag.VEHICLE + CollisionFlag.BUILDING + CollisionFlag.STATIC_OBJECT
end