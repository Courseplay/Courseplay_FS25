--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2021 Peter Vaiko

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

--- A container for custom vehicle configurations.
---
--- Allows to customize vehicle data XML file(s). A standard configuration is installed with Courseplay,
--- custom user configs can be placed in <your save game folder>/modsSettings/Courseplay/vehicleConfigurations.xml
---
--- Custom configs are read last and override the standard config when exist.
---
--- You can use the cpReadVehicleConfigurations console command to reload these files in-game.
---
---@class VehicleConfigurations : CpObject
VehicleConfigurations = CpObject()
VehicleConfigurations.BASE_KEY = "VehicleConfigurations"
VehicleConfigurations.XML_KEY = VehicleConfigurations.BASE_KEY .. ".Vehicle"
VehicleConfigurations.XML_CONFIGURATION_KEY = VehicleConfigurations.BASE_KEY .. ".Configurations.Configuration"
VehicleConfigurations.MOD_NAME = g_currentModName

function VehicleConfigurations:init()
    self.vehicleConfigurations = {}
    self.modVehicleConfigurations = {}
    self.attributes = {}
    if g_currentMission then
        self:loadFromXml()
    end
    self:registerConsoleCommands()
end

function VehicleConfigurations:registerXmlSchema()
    self.xmlSchema = XMLSchema.new("vehicleConfigurations")
    self.xmlSchema:register(XMLValueType.STRING,self.XML_KEY.."(?)#name","Configuration name")
    self.xmlSchema:register(XMLValueType.STRING,self.XML_KEY.."(?)#modName","Mod name") --- Optional to avoid conflict for xml files with the same name.
    self.xmlSchema:register(XMLValueType.STRING,self.XML_CONFIGURATION_KEY.."(?)#type","Configuration value type") 
    self.xmlSchema:register(XMLValueType.STRING,self.XML_CONFIGURATION_KEY.."(?)","Configuration name")
end

function VehicleConfigurations:loadFromXml()
    self.vehicleConfigurations = {}
    self.modVehicleConfigurations = {}
    self.attributes = {}
    self.xmlFileName = Utils.getFilename('config/VehicleConfigurations.xml', Courseplay.BASE_DIRECTORY)
    self:registerXmlSchema()
    self.xmlFile = self:loadXmlFile(self.xmlFileName, true)
    self.userXmlFileName = getUserProfileAppPath() .. 'modSettings/'..VehicleConfigurations.MOD_NAME..'/vehicleConfigurations.xml'
    self.userXmlFile = self:loadXmlFile(self.userXmlFileName)
end

--- Saves the xml attributes under the vehicle name.
function VehicleConfigurations:addAttribute(vehicleConfiguration, xmlFile, vehicleElement, attributeName)
    local configValue = xmlFile:getValue(vehicleElement.."#"..attributeName) 
    if configValue then
        vehicleConfiguration[attributeName] = configValue
        local valueAsString = ''
        if type(configValue) == 'number' then
            valueAsString = string.format('%.1f', configValue)
        else
            valueAsString = string.format('%s', tostring(configValue))
        end
        CpUtil.info('\\__ %s = %s', attributeName, valueAsString)
    end
end

--- Reads all vehicle attributes from the xml file.
function VehicleConfigurations:readVehicle(xmlFile, vehicleElement)
    local vehicleConfiguration = {}
    local name = xmlFile:getValue(vehicleElement .. "#name")
    local modName = xmlFile:getValue(vehicleElement .. "#modName")
    CpUtil.info('Reading configuration for %s', name)
    for attributeName, _ in pairs(self.attributes) do
        self:addAttribute(vehicleConfiguration, xmlFile, vehicleElement, attributeName)
    end
    
    if modName then
        if self.modVehicleConfigurations[modName] == nil then 
            self.modVehicleConfigurations[modName] = {}
        end
        self.modVehicleConfigurations[modName][name] = vehicleConfiguration
    else 
        self.vehicleConfigurations[name] = vehicleConfiguration
    end
end


function VehicleConfigurations:loadXmlFile(fileName, loadConfig)
    CpUtil.info('Loading vehicle configuration from %s ...', fileName)
    local xmlFile = XMLFile.loadIfExists("vehicleConfigurationsXmlFile",fileName, self.xmlSchema)
    if xmlFile then 
        if not loadConfig or self:loadConfigurations(xmlFile) then 
            xmlFile:iterate(self.XML_KEY, function (ix, key)
                self:readVehicle(xmlFile, key)
            end)
        end
        xmlFile:delete()
    else 
        CpUtil.info('Vehicle configuration file %s does not exist.', fileName)
    end
end

function VehicleConfigurations:loadConfigurations(xmlFile)
    self.attributes = {}
    xmlFile:iterate(self.XML_CONFIGURATION_KEY, function(ix, key)
        local type = xmlFile:getValue(key .. "#type"):upper()
        local name = xmlFile:getValue(key)
        self.attributes[name] = XMLValueType[type]
        if self.attributes[name] == nil then 
            CpUtil.info("Vehicle configuration %s has no valid type for %s!", name, type)
        end
    end)
    for name, xmlType in pairs(self.attributes) do 
        CpUtil.info("Registered %s", name)
        self.xmlSchema:register(xmlType, self.XML_KEY.."(?)#"..name, "Configuration value")
    end
    return true
end

--- Get a custom configuration value for a single vehicle/implement
--- @param object table vehicle or implement object. This function uses the object's configFileName to uniquely
--- identify the vehicle/implement.
--- @param attribute string configuration attribute to get
--- @return any|nil the value of the configuration attribute or nil if there's no custom config for it
function VehicleConfigurations:get(object, attribute)
    if not self:isValidAttribute(attribute) then 
        CpUtil.infoImplement(object, "The given vehicle config attribute name: %s is not valid!", attribute)
        return 
    end
    local function getConfigName(data)
        if data[object.configFileNameClean] then 
            return data[object.configFileNameClean][attribute]
        elseif data[object.configFileNameClean..".xml"] then 
            return data[object.configFileNameClean..".xml"][attribute]
        end
    end
    if object and object.configFileNameClean then   
        local modName = object.customEnvironment 
        if modName and self.modVehicleConfigurations[modName] then 
            --- If a mod name was given, then also check the xml filename.
            return getConfigName(self.modVehicleConfigurations[modName])
        else
            return getConfigName(self.vehicleConfigurations)
        end
    end
end

--- Get a custom configuration value for an object and its attached implements.
--- First checks the vehicle itself, then all its attached implements until the attribute is found. If the same
--- attribute is defined on multiple implements, only the first is returned
--- @param object table vehicle
--- @param attribute string configuration attribute to get
--- @return any|nil the value of the configuration attribute or nil if there's no custom config for it
function VehicleConfigurations:getRecursively(object, attribute)
    local value
    for _, implement in pairs(object:getChildVehicles()) do
        value = self:get(implement, attribute)
        CpUtil.debugImplement(CpDebug.DBG_IMPLEMENTS, implement, "%s => %s: %s", implement.configFileNameClean, attribute, tostring(value))
        if value ~= nil then
            return value
        end
    end
    return nil
end

--- Checks if the attribute is registered.
---@param attribute string
---@return boolean
function VehicleConfigurations:isValidAttribute(attribute)
    if attribute == nil then 
        return false
    end
    for name, _ in pairs(self.attributes) do 
        if name == attribute then 
            return true
        end
    end
    return false
end

--- Queries through the vehicle and implements and collects all values for the given attribute.
---@param vehicle table
---@param attribute string
---@return table
function VehicleConfigurations:queryAttributeValues(vehicle, attribute)
    local values = {}
    for _, implement in pairs(vehicle:getChildVehicles()) do
        local value = self:get(implement, attribute)
        local data = {
            value = value,
            implement = implement,
            found = value ~= nil
        }
        table.insert(values, data)
    end
    return values
end

-----------------------------------------------
--- Console commands
-----------------------------------------------

function VehicleConfigurations:registerConsoleCommands()
    g_consoleCommands:registerConsoleCommand("cpVehicleConfigurationsReload",
        "Read custom vehicle configurations", 
        "consoleCommandReload", self)
    g_consoleCommands:registerConsoleCommand("cpVehicleConfigurationsPrintConfigFileNames",
        "Prints the config filename of the entered vehicle and implements", 
        "consoleCommandPrintConfigFileNames", self)
    g_consoleCommands:registerConsoleCommand("cpVehicleConfigurationsQuerySingleAttribute",
        "Prints the given attribute value for current vehicle and implements", 
        "consoleCommandPrintSingleAttributeValuesForVehicleAndImplements", self)
    g_consoleCommands:registerConsoleCommand("cpVehicleConfigurationsQueryForAllAttributes",
        "Prints all attribute values found for vehicle and it's implements", 
        "consoleCommandPrintAllAttributeValuesForVehicleAndImplements", self)
    g_consoleCommands:registerConsoleCommand("cpVehicleConfigurationsListAttributes",
        "Prints all valid attribute names", 
        "consoleCommandPrintAttributeNames", self)
    g_consoleCommands:registerConsoleCommand("cpVehicleConfigurationsPrintAttributes",
        "Prints all normal attributes", 
        "consoleCommandPrintAllNormalVehicleConfigurations", self)
    g_consoleCommands:registerConsoleCommand("cpVehicleConfigurationsPrintModAttributes",
        "Prints all mod name attributes", 
        "consoleCommandPrintAllModNameVehicleConfigurations", self)
end

function VehicleConfigurations:consoleCommandReload()
    self:loadFromXml()
end

function VehicleConfigurations:consoleCommandPrintConfigFileNames()
    local vehicle = CpUtil.getCurrentVehicle()
	if not vehicle then 
		CpUtil.info("No vehicle entered!")
		return
	end
	for i, v in pairs(vehicle:getChildVehicles()) do 
		CpUtil.infoVehicle(v, ": %s(Mod: %s)", tostring(v.configFileNameClean), 
			tostring(v.customEnvironment ~= nil and v.customEnvironment or false))
	end
end

function VehicleConfigurations:consoleCommandPrintSingleAttributeValuesForVehicleAndImplements(attribute)
    local vehicle = CpUtil.getCurrentVehicle()
	if not vehicle then 
		CpUtil.info("No vehicle entered!")
		return
	end
    if not self:isValidAttribute(attribute) then 
        CpUtil.info("Attribute(%s) not found!", attribute)
        return 
    end
    CpUtil.info("Found the following for %s: ....", attribute)
    local values = self:queryAttributeValues(vehicle, attribute)
    for _, data in pairs(values) do
        if data.found then 
            CpUtil.infoVehicle(data.implement, "(%s => Mod: %s) %s", 
                tostring(data.implement.configFileNameClean), 
                tostring(data.implement.customEnvironment ~= nil and data.implement.customEnvironment or false),
                tostring(data.value))
        else 
            CpUtil.infoVehicle(data.implement, "not found")
        end
    end
end

function VehicleConfigurations:consoleCommandPrintAllAttributeValuesForVehicleAndImplements()
    local vehicle = CpUtil.getCurrentVehicle()
	if not vehicle then 
		CpUtil.info("No vehicle entered!")
		return
	end
    for attribute, _ in pairs(self.attributes) do 
        local values = self:queryAttributeValues(vehicle, attribute)
        if #values > 0 then 
            CpUtil.info("Found the following for %s: ....", attribute)
            for _, data in pairs(values) do
                if data.found then 
                    CpUtil.infoVehicle(data.implement, "(%s => Mod: %s) %s",
                        tostring(data.implement.configFileNameClean), 
                        tostring(data.implement.customEnvironment ~= nil and data.implement.customEnvironment or false),
                        tostring(data.value))
                end
            end
        end
    end
end

function VehicleConfigurations:consoleCommandPrintAllModNameVehicleConfigurations()
    for modName, configurations in pairs(self.modVehicleConfigurations) do 
        for name, configs in pairs(configurations) do
            for n, v in pairs(configs) do 
                CpUtil.info("(%s => Mod: %s) %s => %s",
                    name, modName, n, v)
            end
        end
    end
end

function VehicleConfigurations:consoleCommandPrintAllNormalVehicleConfigurations()
    for name, configs in pairs(self.vehicleConfigurations) do 
        for n, v in pairs(configs) do 
            CpUtil.info("(%s) %s => %s",
                name, n, v)
        end
    end
end

function VehicleConfigurations:consoleCommandPrintAttributeNames()
    for attribute, xmlValueType in pairs(self.attributes) do 
        CpUtil.info("Attribute: %s => %s",
            attribute, XMLValueType.TYPES[xmlValueType].name)
    end
end

g_vehicleConfigurations = VehicleConfigurations()
