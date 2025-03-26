--- All the cp console commands are here.
---@class CpConsoleCommands
CpConsoleCommands = CpObject()

CpConsoleCommands.commands = {
	--- call name, description, function
	{ 'cpAddMoney', 'adds money', 'addMoney' },
	{ 'cpRestartSaveGame', 'Load and start a savegame', 'restartSaveGame' },
	{ 'cpReturnToSaveGameSelect', 'Returns to the menu', 'returnToSaveGameSelect' },
	{ 'print', 'Print a variable ($vehicle is replaced with CpUtil.getCurrentVehicle())', 'printVariable' },
	{ 'printGlobalCpVariable', 'Print a global cp variable', 'printGlobalCpVariable' },
	{ 'printVehicleVariable', 'Print CpUtil.getCurrentVehicle().variable', 'printVehicleVariable' },
	{ 'printImplementVariable', 'printImplementVariable <implement index> <variable>', 'printImplementVariable' },
	{ 'printStrategyVariable', 'Print a CP drive strategy variable', 'printStrategyVariable' },
	{ 'printAiPageVariable', 'Print a in game menu ai page variable.', 'printAiPageVariable' },
	{ 'cpLoadFile', 'Load a lua file', 'loadFile' },
	{ 'cpToggleDevHelper', 'Toggle development helper visual debug info', 'cpToggleDevHelper' },
	{ 'cpSaveAllFields', 'Save all fields of the map to an XML file for offline debugging', 'cpSaveAllFields' },
	{ 'cpSaveAllVehiclePositions', 'Save the position of all vehicles', 'cpSaveAllVehiclePositions' },
	{ 'cpRestoreAllVehiclePositions', 'Restore the position of all vehicles', 'cpRestoreAllVehiclePositions' },
	{ 'cpSetPathfinderDebug', 'Set pathfinder visual debug level (0-2)', 'cpSetPathfinderDebug' },
	{ 'cpFreeze', 'Freeze the CP driver', 'cpFreeze' },
	{ 'cpUnfreeze', 'Unfreeze the CP driver', 'cpUnfreeze' },
	{ 'cpStopAll', 'Stops all cp drivers', 'cpStopAll' },
	{ 'cpRaiseAIEvent', 'vehicle/fieldworkerEvent AIImplementEvent', 'cpRaiseAIEvent'},
	{ 'cpRaiseStateChange', 'VehicleStateChange.*', 'cpRaiseStateChange'}
}

function CpConsoleCommands:init()
    self:registerConsoleCommands()
	self.additionalCommands = {}
end

function CpConsoleCommands:delete()
    self:unregisterConsoleCommands()
end

function CpConsoleCommands:registerConsoleCommands()
    for _, commandData in ipairs(self.commands) do 
        local name, desc, funcName = unpack(commandData)
        addConsoleCommand( name, desc, funcName, self)
    end
end

function CpConsoleCommands:unregisterConsoleCommands()
    for _, commandData in ipairs(self.commands) do 
        local name = unpack(commandData)
        removeConsoleCommand( name)
    end
	for _, commandData in ipairs(self.additionalCommands) do 
        local name = unpack(commandData)
        removeConsoleCommand( name)
    end
end

--- Registers an command
---@param name string
---@param desc string
---@param funcName string
---@param callbackClass table
function CpConsoleCommands:registerConsoleCommand(name, desc, funcName, callbackClass)
	table.insert(self.additionalCommands, {
		name, desc, funcName
	})
	addConsoleCommand( name, desc, funcName, callbackClass)
end

------------------------------------------------------------------------------------------------------------------------
--- Console commands
------------------------------------------------------------------------------------------------------------------------

---@param saveGameNumber number
function CpConsoleCommands:restartSaveGame(saveGameNumber)
	if g_server then
		if (saveGameNumber == nil or tonumber(saveGameNumber) == nil) and g_currentMission and g_currentMission.missionInfo then 
			saveGameNumber = g_currentMission.missionInfo.savegameIndex 
		end
		doRestart(true, " -autoStartSavegameId " .. saveGameNumber)
		CpUtil.info('Restarting savegame %d', saveGameNumber)
	end
end

function CpConsoleCommands:returnToSaveGameSelect()
	if g_server then
		doRestart(true, "0#" )
		CpUtil.info('Restarting to menu')
	end
end

---@param amount number
function CpConsoleCommands:addMoney(amount)
	g_currentMission:addMoney(amount ~= nil and tonumber(amount) or 0, g_currentMission.playerSystem:getLocalPlayer().farmId, MoneyType.OTHER)	
end

---Prints a variable to the console or a xmlFile.
---@param variableName string name of the variable, can be multiple levels
---@param maxDepth number maximum depth, 1 by default
---@param printToXML number should the variable be printed to an xml file ? (optional)
---@param printToSeparateXmlFiles number should the variable be printed to an xml file named after the variable ? (optional)
function CpConsoleCommands:printVariable(variableName, maxDepth, printToXML, printToSeparateXmlFiles)
	variableName = variableName:gsub('$vehicle', 'CpUtil.getCurrentVehicle()')
	if printToXML and tonumber(printToXML) and tonumber(printToXML)>0 then
		CpUtil.printVariableToXML(variableName, maxDepth, printToSeparateXmlFiles)
		return
	end
	CpUtil.printVariable(variableName, maxDepth)
end

function CpConsoleCommands:printVariableInternal(prefix, variableName, maxDepth, printToXML, printToSeparateXmlFiles)
	if not string.startsWith(variableName, ':') and not string.startsWith(variableName, '.') then
		-- allow to omit the . at the beginning of the variable name.
		prefix = prefix .. '.'
	end
	self:printVariable(prefix .. variableName, maxDepth, printToXML, printToSeparateXmlFiles)
end

-- make sure variableName is syntactically correct (can be appended to another variable)
function CpConsoleCommands:ensureVariableNameSyntax(variableName)
	if not variableName then
		return ''
	elseif not string.startsWith(variableName, ':') and not string.startsWith(variableName, '.') then
		return '.' .. variableName
	else
		return variableName
	end
end

--- Print the variable in the selected vehicle's namespace
-- You can omit the dot for data members but if you want to call a function, you must start the variable name with a colon
function CpConsoleCommands:printVehicleVariable(variableName, maxDepth, printToXML, printToSeparateXmlFiles)
	local prefix = variableName and 'CpUtil.getCurrentVehicle()' or 'CpUtil'
	-- if no variable name given, print the whole vehicle
	variableName = variableName or '.getCurrentVehicle()'
	self:printVariableInternal( prefix, variableName, maxDepth, printToXML, printToSeparateXmlFiles)
end

--- Print an implement variable. If implement.object.variable exists, print that, otherwise implement.variable
---@param implementIndex number index in getAttachedImplements()
function CpConsoleCommands:printImplementVariable(implementIndex, variableName, maxDepth, printToXML, printToSeparateXmlFiles)
	local prefix = string.format('CpUtil.getCurrentVehicle():getAttachedImplements()[%d]', implementIndex)
	local objectVariableName = string.format('%s.object%s', prefix, self:ensureVariableNameSyntax(variableName))
	local var = CpUtil.getVariable(objectVariableName)
	if var then
		self:printVariable(objectVariableName, maxDepth, printToXML, printToSeparateXmlFiles)
	else
		local implementVariableName = string.format('%s%s', prefix, self:ensureVariableNameSyntax(variableName))
		self:printVariable(implementVariableName, maxDepth, printToXML, printToSeparateXmlFiles)
	end
end

function CpConsoleCommands:printStrategyVariable(variableName, maxDepth, printToXML, printToSeparateXmlFiles)
	local prefix = 'CpUtil.getCurrentVehicle():getCpDriveStrategy()'
	self:printVariableInternal( prefix, variableName, maxDepth, printToXML, printToSeparateXmlFiles)
end

function CpConsoleCommands:printGlobalCpVariable(variableName, maxDepth, printToXML, printToSeparateXmlFiles)
	if variableName then 
		self:printVariableInternal( 'g_Courseplay', variableName, maxDepth, printToXML, printToSeparateXmlFiles)
	else 
		self:printVariable('g_Courseplay', maxDepth, printToXML, printToSeparateXmlFiles)
	end
end

function CpConsoleCommands:printAiPageVariable(variableName, maxDepth, printToXML, printToSeparateXmlFiles)
	local prefix = 'g_currentMission.inGameMenu.pageAI'
	self:printVariableInternal( prefix, variableName, maxDepth, printToXML, printToSeparateXmlFiles)
end

--- Load a Lua file
--- This is to reload scripts without restarting the game.
function CpConsoleCommands:loadFile(fileName)
	fileName = fileName or 'reload.xml'
	local path = Courseplay.BASE_DIRECTORY .. '/' .. fileName
	if fileExists(path) then
		g_xmlFile = loadXMLFile('loadFile', path)
	end
	if not g_xmlFile then
		return 'Could not load ' .. path
	else
		local code = getXMLString(g_xmlFile, 'code')
		local f = getfenv(0).loadstring('setfenv(1, '.. Courseplay.MOD_NAME .. '); ' .. code)
		if f then
			f()
			return 'OK: ' .. path .. ' loaded.'
		else
			return 'ERROR: ' .. path .. ' could not be compiled.'
		end
	end
end

function CpConsoleCommands.saveVehiclePosition(vehicle, vehiclePositionData)
    local savePosition = function(object)
        local savedPosition = {}
        savedPosition.x, savedPosition.y, savedPosition.z = getWorldTranslation(object.rootNode)
        savedPosition.xRot, savedPosition.yRot, savedPosition.zRot = getWorldRotation(object.rootNode)
        return savedPosition
    end
    if not vehicle.getAttachedImplements then return end
    table.insert(vehiclePositionData, {vehicle, savePosition(vehicle)})
    for _,impl in pairs(vehicle:getAttachedImplements()) do
        CpConsoleCommands.saveVehiclePosition(impl.object, vehiclePositionData)
    end
    CpUtil.info('Saved position of %s', vehicle:getName())
end

function CpConsoleCommands.restoreVehiclePosition(vehicle)
    if vehicle.vehiclePositionData then
        for _, savedPosition in pairs(vehicle.vehiclePositionData) do
            savedPosition[1]:setAbsolutePosition(savedPosition[2].x, savedPosition[2].y, savedPosition[2].z,
                    savedPosition[2].xRot, savedPosition[2].yRot, savedPosition[2].zRot)
            CpUtil.info('Restored position of %s', savedPosition[1]:getName())
        end
    end
end

function CpConsoleCommands:cpToggleDevHelper()
    g_devHelper:toggle()
end

function CpConsoleCommands:cpSaveAllFields()
	CpFieldUtil.saveAllFields()
end

function CpConsoleCommands:cpSaveAllVehiclePositions()
    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
		if SpecializationUtil.hasSpecialization(CpAIWorker, vehicle.specializations) then
			vehicle.vehiclePositionData = {}
			CpConsoleCommands.saveVehiclePosition(vehicle, vehicle.vehiclePositionData)
		end
    end
end

function CpConsoleCommands:cpRestoreAllVehiclePositions()
    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if vehicle.vehiclePositionData then
            CpConsoleCommands.restoreVehiclePosition(vehicle)
        end
    end
end

function CpConsoleCommands:cpSetPathfinderDebug(d)
	PathfinderUtil.setVisualDebug(tonumber(d))
end

function CpConsoleCommands:cpFreeze()
	CpUtil.getCurrentVehicle():freezeCp()
end

function CpConsoleCommands:cpUnfreeze()
	CpUtil.getCurrentVehicle():unfreezeCp()
end

function CpConsoleCommands:cpStopAll()
	for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
		if vehicle.getIsAIActive and vehicle:getIsAIActive() then 
			vehicle:stopCurrentAIJob(AIMessageErrorUnknown.new())
		end
	end
end

function CpConsoleCommands:cpRaiseAIEvent(vehicleEvent, implementEvent)
	local vehicle = CpUtil.getCurrentVehicle()
	if vehicle then
		vehicle:raiseAIEvent(vehicleEvent, implementEvent)
	end
end

function CpConsoleCommands:cpRaiseStateChange(state)
	local vehicle = CpUtil.getCurrentVehicle()
	if vehicle then
		vehicle:raiseStateChange(VehicleStateChange[state])
	end
end

-- when reloading, clean up before re-instantiation
if g_consoleCommands then
	g_consoleCommands:delete()
end

---@type CpConsoleCommands
g_consoleCommands = CpConsoleCommands()