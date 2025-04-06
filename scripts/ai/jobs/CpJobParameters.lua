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


--- Parameters of a Courseplay job
---@class CpJobParameters
---@field settings AIParameterSetting[]
CpJobParameters = CpObject()
CpJobParameters.xmlKey = ".cpJobParameters"
CpJobParameters.baseFilePath = "config/jobParameters/"

function CpJobParameters:init(job, class, configPath)
    if not class.settings then
        -- initialize the class members first so the class can be used to access constants, etc.
        local filePath = Utils.getFilename(self.baseFilePath .. configPath, g_Courseplay.BASE_DIRECTORY)
        CpSettingsUtil.loadSettingsFromSetup(class, filePath)
    end
    CpSettingsUtil.cloneSettingsTable(self, class.settings, nil, self)
    self.job = job
end

function CpJobParameters.registerXmlSchema(schema, baseKey)
    CpSettingsUtil.registerXmlSchema(schema, baseKey .. CpJobParameters.xmlKey.."(?)")
end

function CpJobParameters:validateSettings(includeDisabledValues)
    for i, setting in ipairs(self.settings) do 
        setting:refresh(includeDisabledValues)
    end
end

function CpJobParameters:resetToLoadedValue(includeDisabledValues)
    for i, setting in ipairs(self.settings) do 
        setting:resetToLoadedValue()
    end
end

function CpJobParameters:writeStream(streamId, connection)
    for i, setting in ipairs(self.settings) do 
        setting:writeStream(streamId, connection)
    end
end

function CpJobParameters:readStream(streamId, connection)
    for i, setting in ipairs(self.settings) do 
        setting:readStream(streamId, connection)
    end
end

function CpJobParameters:saveToXMLFile(xmlFile, baseKey, usedModNames)
    CpSettingsUtil.saveToXmlFile(self.settings, xmlFile, 
        baseKey ..self.xmlKey, self.job:getVehicle(), nil)
end

function CpJobParameters:loadFromXMLFile(xmlFile, baseKey)
    CpSettingsUtil.loadFromXmlFile(self, xmlFile, baseKey .. self.xmlKey, self.job:getVehicle())
end

function CpJobParameters:copyFrom(jobParameters)
    for i, setting in ipairs(self.settings) do
        setting:copy(jobParameters[setting.name])
    end
end

--- Crawls through the parameters and collects all CpAIParameterPositionAngle settings.
---@return table settings all CpAIParameterPositionAngle and CpAIParameterPosition settings found.
function CpJobParameters:getAiTargetMapHotspotParameters()
    local parameters = {}
    for i, setting in ipairs(self.settings) do
        if setting:is_a(CpAIParameterPosition) then
            table.insert(parameters, setting)
        end
    end
    return parameters
end

function CpJobParameters:isAIMenuJob()
    return not self.job:getIsHudJob()
end

function CpJobParameters:isBunkerSiloHudModeDisabled()
    local vehicle = self.job:getVehicle()
    if vehicle then 
        if not vehicle:getCanStartCpBunkerSiloWorker() then 
            return true
        end
    end
    return self:isAIMenuJob()
end

function CpJobParameters:isSiloLoadingHudModeDisabled()
    local vehicle = self.job:getVehicle()
    if vehicle then 
        if not vehicle:getCanStartCpSiloLoaderWorker() then 
            return true
        end
    end
    return self:isAIMenuJob()
end

function CpJobParameters:isFieldWorkHudModeDisabled()
    local vehicle = self.job:getVehicle()
    if vehicle then 
        if (AIUtil.hasChildVehicleWithSpecialization(vehicle, Leveler) and 
            not AIUtil.hasChildVehicleWithSpecialization(vehicle, Shovel)) or 
            AIUtil.hasChildVehicleWithSpecialization(vehicle, ConveyorBelt) then 
            return true
        end
    end
    return false
end

function CpJobParameters:isStreetModeActive()
    return true
end

function CpJobParameters:isGiantsForStreetActive()
    return false
end

--- Callback raised by a setting and executed as an vehicle event.
---@param callbackStr string event to be raised
---@param setting AIParameterSettingList setting that raised the callback.
function CpJobParameters:raiseCallback(callbackStr, setting, ...)
    if self[callbackStr] then 
        self[callbackStr](self, setting, ...)
        return
    end
    local vehicle = self.job:getVehicle()
    if vehicle then 
        SpecializationUtil.raiseEvent(vehicle, callbackStr, setting, ...)
    end
end

function CpJobParameters:debug(...)
    self.job:debug(...)
end

function CpJobParameters:isCpActive()
    return self.job:getVehicle() and self.job:getVehicle():getIsCpActive()
end

--- Crawls through the parameters and collects all CpAIParameterFillTypeSetting settings.
---@return table
function CpJobParameters:getFillTypeSelectionSettings()
    local parameters = {}
    for i, setting in ipairs(self.settings) do
        if setting:is_a(CpAIParameterFillTypeSetting) then
            table.insert(parameters, setting)
        end
    end
    return parameters
end

--- Crawls through the parameters and collects all CpAITargetPointSetting settings.
---@return table
function CpJobParameters:getTargetPointSettings()
    local parameters = {}
    for i, setting in ipairs(self.settings) do
        if setting:is_a(CpAIParameterTargetPoint) then
            table.insert(parameters, setting)
        end
    end
    return parameters
end


--- Are the setting values roughly equal.
---@param otherParameters CpJobParameters
---@return boolean
function CpJobParameters:areAlmostEqualTo(otherParameters)
    for i, param in pairs(self.settings) do 
        if not param:isAlmostEqualTo(otherParameters[param:getName()]) then 
            CpUtil.debugFormat(CpDebug.DBG_HUD, "Parameter: %s not equal!", param:getName())
            return false
        end
    end
    return true
end

---@class CpFieldWorkJobParameters : CpJobParameters
CpFieldWorkJobParameters = CpObject(CpJobParameters)
function CpFieldWorkJobParameters:init(job)
    CpJobParameters.init(self, job, 
        CpFieldWorkJobParameters, "FieldWorkJobParameterSetup.xml")
end

function CpFieldWorkJobParameters.getSettings(vehicle)
    return vehicle.spec_cpAIFieldWorker.cpJob:getCpJobParameters()
end

---@return number
---@return Course.MultiVehicleData|nil
function CpFieldWorkJobParameters:getMultiTools()
    local vehicle = self.job and self.job:getVehicle()
    if vehicle then 
        local course = vehicle:getFieldWorkCourse()
        if course then 
            return course:getMultiTools(), course.multiVehicleData
        else 
            return 1
        end
    end
    --- This needs to be 5, as the server otherwise has problems.
    return 5
end

function CpFieldWorkJobParameters:generateMultiToolLaneOffset(setting, oldIx)
    local ntools, toolData = self:getMultiTools()
    local values, texts = {}, {}
    if ntools > 3 then 
        table.insert(values, -2)
        table.insert(texts, setting:getSubText("left_2"))
    end
    if ntools > 1 then 
        table.insert(values, -1)
        table.insert(texts, setting:getSubText("left"))
    end
    if ntools % 2 > 0 then 
        table.insert(values, 0)
        table.insert(texts, setting:getSubText("center"))
    end
    if ntools > 1 then 
        table.insert(values, 1)
        table.insert(texts, setting:getSubText("right"))
    end
    if ntools > 3 then 
        table.insert(values, 2)
        table.insert(texts, setting:getSubText("right_2"))
    end
    return values, texts, toolData and toolData.position or oldIx
end

function CpFieldWorkJobParameters:noMultiToolsCourseSelected()
    return self:getMultiTools() <= 1
end

function CpFieldWorkJobParameters:evenNumberOfMultiTools()
    return self:getMultiTools() %2 == 0
end

function CpFieldWorkJobParameters:lessThanThreeMultiTools()
    return self:getMultiTools() < 4
end

function CpFieldWorkJobParameters:onLaneOffsetChanged(setting)
    local vehicle = self.job:getVehicle()
    if vehicle then
        local course = vehicle:getFieldWorkCourse()
        if course and course:getMultiTools() > 1 then
            vehicle:getFieldWorkCourse():setPosition(setting:getValue())
            SpecializationUtil.raiseEvent(vehicle, "onCpCourseChange", vehicle:getFieldWorkCourse(), true)
        end
    end
end

function CpFieldWorkJobParameters:isLaneOffsetVisible()
    return not self:noMultiToolsCourseSelected()
end

function CpFieldWorkJobParameters:isLaneOffsetDisabled()
    local vehicle = self.job:getVehicle()
    return self:noMultiToolsCourseSelected() or vehicle and vehicle:getIsCpActive()
end

function CpFieldWorkJobParameters:isUnloadRefillTargetDisabled()
    return false --- TODO: Added check for refill/unload possibilities ...
end


function CpFieldWorkJobParameters:generateFillTypes()
    local fillTypes = {}
    local texts = {}
    local vehicle = self.job and self.job:getVehicle()
    if vehicle then
        fillTypes = FillLevelUtil.getAllValidFillTypes(vehicle, function()
            return true
        end)
        for _, f in pairs(fillTypes) do 
            table.insert(texts, g_fillTypeManager:getFillTypeTitleByIndex(f))
        end
    else 
        for ix, _ in pairs(g_fillTypeManager:getFillTypes()) do 
            if ix ~= FillType.UNKNOWN then
                table.insert(fillTypes, ix)
                table.insert(texts, g_fillTypeManager:getFillTypeTitleByIndex(f))
            end
        end
    end
    table.insert(fillTypes, 1, -1)
    table.insert(texts, 1, "---")
    return fillTypes, texts
end

function CpFieldWorkJobParameters:isLoadingDisabled()
    if self:isUnloadRefillTargetDisabled() then 
        return true
    end

    local vehicle = self.job:getVehicle()
    if not vehicle then 
        return false
    end
    return not AIUtil.hasChildVehicleWithSpecialization(vehicle, Sprayer) and not 
        AIUtil.hasChildVehicleWithSpecialization(vehicle, SowingMachine)
end

function CpFieldWorkJobParameters:isUnloadingDisabled()
    if self:isUnloadRefillTargetDisabled() then 
        return true
    end
    local vehicle = self.job:getVehicle()
    if not vehicle then 
        return false
    end
    return not AIUtil.hasChildVehicleWithSpecialization(vehicle, ForageWagon)
end

function CpFieldWorkJobParameters:isRunCounterDisabled()
    return true
end

function CpFieldWorkJobParameters:isUnloadRefillDisabled()

    local vehicle = self.job:getVehicle()
    if not vehicle then 
        return false
    end
    if self:isLoadingDisabled() and self:isUnloadingDisabled() then 
        return true
    end
    return not self.unloadRefillActivated:getValue()
end

function CpFieldWorkJobParameters:isUnloadRefillFillTypeDisabled()
    return self:isUnloadRefillDisabled() or self:isLoadingDisabled()
end

function CpFieldWorkJobParameters:isUnloadRefillExtraDisabled()
    local vehicle = self.job:getVehicle()
    if not vehicle then 
        return false
    end
    return self:isUnloadRefillDisabled() or 
        not (AIUtil.hasChildVehicleWithSpecialization(vehicle, Sprayer) and 
        AIUtil.hasChildVehicleWithSpecialization(vehicle, SowingMachine))
end

function CpFieldWorkJobParameters:onChangeStartUnloadRefillTargetPoint(setting)
    
end

--- AI parameters for the bale finder job.
---@class CpBaleFinderJobParameters : CpJobParameters
CpBaleFinderJobParameters = CpObject(CpJobParameters)

function CpBaleFinderJobParameters:init(job)
    CpJobParameters.init(self, job, 
        CpBaleFinderJobParameters, "BaleFinderJobParameterSetup.xml")
end

function CpBaleFinderJobParameters.getSettings(vehicle)
    return vehicle.spec_cpAIBaleFinder.cpJob:getCpJobParameters()
end

function CpBaleFinderJobParameters:hasBaleLoader()
    local vehicle = self.job:getVehicle()
    if vehicle then 
        return AIUtil.hasChildVehicleWithSpecialization(vehicle, BaleLoader)
    end
    return true
end

function CpBaleFinderJobParameters:isUnloadTargetPointDisabled()
    return not self:hasBaleLoader()
end

function CpBaleFinderJobParameters:isBaleWrapSettingVisible()
   return self:hasBaleLoader()
end

--- AI parameters for the bale finder job.
---@class CpCombineUnloaderJobParameters : CpJobParameters
---@field useGiantsUnload AIParameterBooleanSetting
---@field useFieldUnload AIParameterBooleanSetting
CpCombineUnloaderJobParameters = CpObject(CpJobParameters)

function CpCombineUnloaderJobParameters:init(job)
    CpJobParameters.init(self, job, 
        CpCombineUnloaderJobParameters, "CombineUnloaderJobParameterSetup.xml")
end

function CpCombineUnloaderJobParameters:isGiantsUnloadDisabled()
    return self:hasPipe() or 
        self.unloadWith:getValue() ~= CpCombineUnloaderJobParameters.UNLOAD_WITH_GIANTS
end

function CpCombineUnloaderJobParameters:isUnloadWithStreetModeDisabled()
    return self:hasPipe() or 
        self.unloadWith:getValue() ~= CpCombineUnloaderJobParameters.UNLOAD_WITH_STREET_MODE
end

function CpCombineUnloaderJobParameters:isFieldUnloadDisabled()
    return self.unloadWith:getValue() ~= CpCombineUnloaderJobParameters.UNLOAD_ON_FIELD
end
function CpCombineUnloaderJobParameters:isFieldUnloadTipSideDisabled()
    return self:isFieldUnloadDisabled() or self:hasPipe() 
end

function CpCombineUnloaderJobParameters:hasPipe()
    local vehicle = self.job:getVehicle()
    if vehicle then
        return AIUtil.hasChildVehicleWithSpecialization(vehicle, Pipe)
    end
    return false
end

--- Inserts the current available unloading stations into the setting values/texts.
function CpCombineUnloaderJobParameters:generateUnloadingStations(setting)
    local unloadingStationIds = {}
    local texts = {}
    if self.job then
        for i, unloadingStation in ipairs(self.job:getUnloadingStations()) do 
            local id = NetworkUtil.getObjectId(unloadingStation)
            table.insert(unloadingStationIds, id)
            table.insert(texts,  unloadingStation:getName() or "")
        end
    end
    if #unloadingStationIds <=0 then 
        table.insert(unloadingStationIds, -1)
        table.insert(texts, "---")
    end
    return unloadingStationIds, texts
end

--- Adds all tipSides of the attached trailer into setting for selection.
---@param setting table
---@return table tipSideIds all tip side by their id.
---@return table texts all tip side translations.
function CpCombineUnloaderJobParameters:generateTipSides(setting)
    local tipSideIds = {}
    local texts = {}
    if self.job and self.job:getVehicle() then
        local trailer = AIUtil.getImplementWithSpecialization(self.job:getVehicle(), Trailer)
        if trailer then 
            for i, tipSide in pairs(trailer.spec_trailer.tipSides) do 
                --- TODO: Side unloading disabled for now!!
                local dischargeNodeIndex = tipSide.dischargeNodeIndex
                local dischargeNode = trailer:getDischargeNodeByIndex(dischargeNodeIndex)
                if dischargeNode then
                    local xOffset, _ ,_ = localToLocal(dischargeNode.node, trailer.rootNode, 0, 0, 0)
                    if math.abs(xOffset) <= 1 then
                        table.insert(tipSideIds, tipSide.index)
                        table.insert(texts, tipSide.name)
                    end
                end
            end
        end
    end
    if #tipSideIds <=0 then 
        table.insert(tipSideIds, -1)
        table.insert(texts, "---")
    end
    return tipSideIds, texts
end

function CpCombineUnloaderJobParameters.getSettings(vehicle)
    return vehicle.spec_cpAICombineUnloader.cpJob:getCpJobParameters()
end
--- AI parameters for the bunker silo job.
---@class CpBunkerSiloJobParameters : CpJobParameters
CpBunkerSiloJobParameters = CpObject(CpJobParameters)

function CpBunkerSiloJobParameters:init(job)
    CpJobParameters.init(self, job, 
        CpBunkerSiloJobParameters, "BunkerSiloJobParameterSetup.xml")
end

function CpBunkerSiloJobParameters.getSettings(vehicle)
    return vehicle.spec_cpAIBunkerSiloWorker.cpJob:getCpJobParameters()
end

function CpBunkerSiloJobParameters:isDrivingForwardsIntoSiloSettingVisible()
    local vehicle = self.job:getVehicle()
    if vehicle then
        return not AIUtil.hasChildVehicleWithSpecialization(vehicle, Leveler)
    end
    return true
end

--- AI parameters for the bunker silo job.
---@class CpSiloLoaderJobParameters : CpJobParameters
---@field unloadAt AIParameterSettingList
---@field UNLOAD_TRAILER number
---@field UNLOAD_TRIGGER number
CpSiloLoaderJobParameters = CpObject(CpJobParameters)

function CpSiloLoaderJobParameters:init(job)
    CpJobParameters.init(self, job, 
        CpSiloLoaderJobParameters, "SiloLoaderJobParameterSetup.xml")
end

function CpSiloLoaderJobParameters.getSettings(vehicle)
    return vehicle.spec_cpAISiloLoaderWorker.cpJob:getCpJobParameters()
end

function CpSiloLoaderJobParameters:isShovelSiloLoadDisabled()
    local vehicle = self.job:getVehicle()
    if vehicle then 
        return AIUtil.hasChildVehicleWithSpecialization(vehicle, ConveyorBelt)
    end
    return false
end

function CpSiloLoaderJobParameters:isUnloadPositionDisabled()
    return self:isShovelSiloLoadDisabled() or self.unloadAt:getValue() == CpSiloLoaderJobParameters.UNLOAD_TRAILER
end

function CpSiloLoaderJobParameters:isUnloadStationDisabled()
    return true
end

function CpSiloLoaderJobParameters:generateUnloadingStations(setting, oldIx)
    local unloadingStationIds = {}
    local texts = {}
    table.insert(unloadingStationIds, -1)
    table.insert(texts, "---")
    if self.job then
        for i, unloadingStation in ipairs(self.job:getUnloadingStations()) do 
            local id = NetworkUtil.getObjectId(unloadingStation)
            table.insert(unloadingStationIds, id)
            table.insert(texts,  unloadingStation:getName() or "")
        end
    end
    return unloadingStationIds, texts, oldIx
end

--- AI parameters for the street driving job.
---@class CpStreetJobParameters : CpJobParameters
CpStreetJobParameters = CpObject(CpJobParameters)

function CpStreetJobParameters:init(job)
    CpJobParameters.init(self, job, 
        CpStreetJobParameters, "StreetJobParameterSetup.xml")
end

function CpStreetJobParameters:hasNoValidTrailerAttached()
    local vehicle = self.job:getVehicle()
    if vehicle then
        return not AIUtil.hasChildVehicleWithSpecialization(vehicle, Dischargeable) 
            or not AIUtil.hasChildVehicleWithSpecialization(vehicle, Trailer) 
    end
    return false
end


function CpStreetJobParameters:isUnloadTargetPointDisabled()
    return false
end

function CpStreetJobParameters:isLoadTargetPointDisabled()
    return self.loadUnloadTargetMode:getValue() ~= CpStreetJobParameters.LOAD_AND_UNLOAD
end

function CpStreetJobParameters:isUnloadAtTargetDisabled()
    return self:hasNoValidTrailerAttached()
end

function CpStreetJobParameters:isLoadAtTargetDisabled()
    return self:hasNoValidTrailerAttached()
end

function CpStreetJobParameters:isRunCounterDisabled()
    return false
end

function CpStreetJobParameters:generateFillTypes()
    local fillTypes = {}
    local texts = {}
    local vehicle = self.job and self.job:getVehicle()
    if vehicle then
        fillTypes = FillLevelUtil.getAllValidFillTypes(vehicle, function()
            return true
        end)
        for _, f in pairs(fillTypes) do 
            table.insert(texts, g_fillTypeManager:getFillTypeTitleByIndex(f))
        end
    else 
        for ix, _ in pairs(g_fillTypeManager:getFillTypes()) do 
            if ix ~= FillType.UNKNOWN then
                table.insert(fillTypes, ix)
                table.insert(texts, g_fillTypeManager:getFillTypeTitleByIndex(ix))
            end
        end
    end
    table.insert(fillTypes, 1, -1)
    table.insert(texts, 1, "---")
    return fillTypes, texts
end

---@param setting CpAIParameterTargetPoint
function CpStreetJobParameters:onChangeTargetPoints(setting)
    
end