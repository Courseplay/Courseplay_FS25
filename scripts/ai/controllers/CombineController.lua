--- For now only handles possible silage additives, if needed.
--- TODO: Straw swath handling should be moved here.
---@class CombineController : ImplementController
CombineController = CpObject(ImplementController)
function CombineController:init(vehicle, combine)
    ImplementController.init(self, vehicle, combine)
    self.combineSpec = combine.spec_combine
    self.settings = vehicle:getCpSettings()
    self.beaconLightsActive = false
    self.hasPipe = SpecializationUtil.hasSpecialization(Pipe, combine.specializations)
    self.isWheeledImplement = ImplementUtil.isWheeledImplement(combine)
    local additives = self.combineSpec.additives
    if additives.available then
        self:addRefillImplementAndFillUnit(self.implement, additives.fillUnitIndex)
    end
end

function CombineController:update()
	self:updateAdditiveFillUnitEmpty(self.combineSpec.additives)
end

function CombineController:getDriveData()
    local maxSpeed = nil
    maxSpeed = self:updateThreshingDuringRain()
    self:updateBeaconLightsAndFullMessage()
    return nil, nil, nil, maxSpeed
end

function CombineController:getFillLevel()
    local fillLevel = self.implement:getFillUnitFillLevel(self.combineSpec.fillUnitIndex)

    if(self:isSugarcaneHarvesterWithBunker()) then

        local freeCapacity = self.implement:getFillUnitFreeCapacity(self.combineSpec.fillUnitIndex)
        local capacity = self.implement:getFillUnitCapacity(self.combineSpec.fillUnitIndex)

        local fillLevelSelfCalc = capacity - freeCapacity

        self:debug("capacity: %s", capacity)
        self:debug("freeCapacity: %s", freeCapacity)
        self:debug("fillLevel: %s", fillLevel)
        self:debug("fillLevelSelfCalc: %s", fillLevelSelfCalc)

        return fillLevelSelfCalc
    end

    if self.combineSpec.loadingDelay > 0 then
        for i=1, #self.combineSpec.loadingDelaySlots do
            local slot = self.combineSpec.loadingDelaySlots[i]
            if slot.valid then
                fillLevel = fillLevel + slot.fillLevelDelta
            end
        end
    end
    return fillLevel
end

function CombineController:getFillLevelPercentage()
    return 100 * self:getFillLevel() / self:getCapacity()
end

function CombineController:getCapacity()
    return self.implement:getFillUnitCapacity(self.combineSpec.fillUnitIndex)
end

function CombineController:getFillUnitIndex()
    return self.combineSpec.fillUnitIndex
end

-------------------------------------------------------------
--- Combine
-------------------------------------------------------------

function CombineController:updateThreshingDuringRain()
    local maxSpeed = nil
    if self.implement:getIsThreshingDuringRain() and g_Courseplay.globalSettings.stopThreshingDuringRain:getValue() then
        maxSpeed = 0
        self:setInfoText(InfoTextManager.WAITING_FOR_RAIN_TO_FINISH)
    else
        self:clearInfoText(InfoTextManager.WAITING_FOR_RAIN_TO_FINISH)
    end
    return maxSpeed
end

function CombineController:updateBeaconLightsAndFullMessage()
    if self.hasPipe then
        --- Updates the beacon lights and the blinking hotspot.
        local dischargeNode = self.implement:getCurrentDischargeNode()
        if dischargeNode ~= nil then
            local fillLevel = self.implement:getFillUnitFillLevel(dischargeNode.fillUnitIndex)
            local capacity = self.implement:getFillUnitCapacity(dischargeNode.fillUnitIndex)
            if fillLevel ~= nil and fillLevel ~= math.huge then
                if fillLevel > 0.8 * capacity then
                    if not self.beaconLightsActive then
                        self.vehicle:setAIMapHotspotBlinking(true)
                        self.vehicle:setBeaconLightsVisibility(true)
                        self.beaconLightsActive = true
                    end
                else
                    if self.beaconLightsActive then
                        self.vehicle:setAIMapHotspotBlinking(false)
                        self.vehicle:setBeaconLightsVisibility(false)
                        self.beaconLightsActive = false
                    end
                end
            end
        end
    end
end


function CombineController:updateStrawSwath(isOnHeadland)
    local strawMode = self.settings.strawSwath:getValue()
    if self.combineSpec.isSwathActive then
        if strawMode == CpVehicleSettings.STRAW_SWATH_OFF or isOnHeadland and strawMode == CpVehicleSettings.STRAW_SWATH_ONLY_CENTER then
            self:setStrawSwath(false)
            self:debug('straw swath should be off!')
        end
    else
        if strawMode ~= CpVehicleSettings.STRAW_SWATH_OFF then
            if isOnHeadland and strawMode == CpVehicleSettings.STRAW_SWATH_ONLY_CENTER then
                return
            end
            self:debug('straw swath should be on!')
            self:setStrawSwath(true)
        end
    end
end

function CombineController:setStrawSwath(enable)
    local strawSwathCanBeEnabled = false
    local fruitType = g_fruitTypeManager:getFruitTypeIndexByFillTypeIndex(self.implement:getFillUnitFillType(self:getFillUnitIndex()))
    if fruitType ~= nil and fruitType ~= FruitType.UNKNOWN then
        local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(fruitType)
        if fruitDesc.hasWindrow then
            strawSwathCanBeEnabled = true
        end
        self.implement:setIsSwathActive(enable and strawSwathCanBeEnabled)
    end
end

--- Is the combine currently dropping straw swath?
function CombineController:isDroppingStrawSwath()
    return self.combineSpec.strawPSenabled
end

function CombineController:isRootVegetableHarvester()
    for _, fruitTypeIndex in pairs(CpUtil.getAllRootVegetables()) do
        local fillUnitIndex = g_fruitTypeManager:getFillTypeIndexByFruitTypeIndex(fruitTypeIndex)
        self:debug("check if fruitType %s is supported", g_fillTypeManager:getFillTypeNameByIndex(fillUnitIndex))
        for i, _ in ipairs(self.implement:getFillUnits()) do
            if self.implement:getFillUnitSupportsFillType(i, fillUnitIndex) then
                self:debug('This is a root vegetable harvester.')
                return true
            end
        end
    end
    return false
end

--- Is this a towed harvester? We don't want these to make combine headland turns (or make pockets?)
function CombineController:isTowed()
    return self.isWheeledImplement
end

--- This harvester always needs an unloader to work, such as a chopper or some ground vegetable harvesters. They
--- don't have a tank, so whatever they harvest, must unload immediately.
function CombineController:alwaysNeedsUnloader()
    return self:getCapacity() > 10000000 or self:isSugarcaneHarvester()
end

--- The fruit harvested takes some time to be processed, like some root vegetable harvesters where the way from
--- the pickup to the conveyor belt/pipe take many seconds.
---@return boolean true if there is still some fruit somewhere being processed, meaning we can expect the pipe to
--- discharge some more
function CombineController:isProcessingFruit()
    if self.combineSpec.loadingDelay > 0 then
        for i = 1, #self.combineSpec.loadingDelaySlots do
            if self.combineSpec.loadingDelaySlots[i].valid then
                return true
            end
        end
        return false
    else
        return false
    end
end
-------------------------------------------------------------
--- Chopper
-------------------------------------------------------------

--- Make life easier for unloaders, increase chopper discharge distance
-- TODO: this is not used as everything seems to work fine with the default throw distances, leaving in for now
-- in case it turns out later we need it
function CombineController:fixDischargeDistanceForChopper()
    local dischargeNode = self.implement:getCurrentDischargeNode()
    if self:isChopper() and dischargeNode and dischargeNode.maxDistance then
        local safeDischargeNodeMaxDistance = 40
        if dischargeNode.maxDistance < safeDischargeNodeMaxDistance then
            self:debug('Chopper maximum throw distance is %.1f, increasing to %.1f', dischargeNode.maxDistance, safeDischargeNodeMaxDistance)
            dischargeNode.maxDistance = safeDischargeNodeMaxDistance
        end
    end
end

function CombineController:isChopper()
    -- TODO: not just choppers have infinite capacity, see alwaysNeedsUnloader()
    return self:getCapacity() > 10000000 or self:isSugarcaneHarvester()
end

function CombineController:isSugarcaneHarvester()
    local isSugarcaneType = self.vehicle.typeName ~= nil and string.find(self.vehicle.typeName, "combineCutterFruitPreparer", 1, true) ~= nil

    return isSugarcaneType;
end

function CombineController:isSugarcaneHarvesterWithBunker()

    local hasCapacity = self:getCapacity() ~= math.huge

    return self:isSugarcaneHarvester() and hasCapacity;
end

function CombineController:updateChopperFillType()
    --- Not exactly sure what this does, but without this the chopper just won't move.
    --- Copied from AIDriveStrategyCombine:update()
    -- no pipe, no discharge node
    local capacity = 0
    local dischargeNode = self.implement:getCurrentDischargeNode()

    if dischargeNode ~= nil then
        capacity = self.implement:getFillUnitCapacity(dischargeNode.fillUnitIndex)
    end

    if capacity == math.huge then
        local rootVehicle = self.implement.rootVehicle

        if rootVehicle.getAIFieldWorkerIsTurning ~= nil and not rootVehicle:getAIFieldWorkerIsTurning() then
            local trailer = NetworkUtil.getObject(self.implement.spec_pipe.nearestObjectInTriggers.objectId)

            if trailer ~= nil then
                local trailerFillUnitIndex = self.implement.spec_pipe.nearestObjectInTriggers.fillUnitIndex
                local fillType = self.implement:getDischargeFillType(dischargeNode)

                if fillType == FillType.UNKNOWN then
                    fillType = trailer:getFillUnitFillType(trailerFillUnitIndex)

                    if fillType == FillType.UNKNOWN then
                        fillType = trailer:getFillUnitFirstSupportedFillType(trailerFillUnitIndex)
                    end

                    self.implement:setForcedFillTypeIndex(fillType)
                else
                    self.implement:setForcedFillTypeIndex(nil)
                end
            end
        end
    end
end
