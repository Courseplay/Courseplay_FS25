--- Controller for sprayers and fertilizer spreaders
--- Main motivation as of now is to turn the sprayer off while the vehicle is not moving
--- for whatever reason, for instance in a convoy waiting to start.
---@class SprayerController : ImplementController
SprayerController = CpObject(ImplementController)

--- Dummy placeholder for now
function SprayerController:init(vehicle, sprayer)
    self.sprayer = sprayer
    self.sprayerSpec = sprayer.spec_sprayer
    ImplementController.init(self, vehicle, self.sprayer)
    self:updateRefillSources()
end

-------------------------
--- Refill handling
-------------------------

function SprayerController:updateRefillSources()
    local spec = self.sprayerSpec
    self:updateRefillFillTypeSources(spec.fillTypeSources or {}, spec.supportedSprayTypes or {},
        self.implement:getSprayerFillUnitIndex())
end

function SprayerController:isRefillingEnabled()
    return ImplementUtil.isSprayerRefillingEnabled(self.implement, self.settings)
end

function SprayerController:needsRefilling()
    self:updateRefillSources()
    return ImplementUtil.isSprayerEmpty(self.implement, self.settings)
end

function SprayerController:getIsRequiredMaterialMissing()
    return self:needsRefilling()
end

local function processSprayerArea(sprayer, superFunc, ...)
    local rootVehicle = sprayer.rootVehicle
    if rootVehicle.getIsCpActive and rootVehicle:getIsCpActive() then
        local specSpray = sprayer.spec_sprayer
        local sprayerParams = specSpray.workAreaParameters
        --- If the vehicle is standing, them disable the sprayer.
        if rootVehicle:getLastSpeed() < 0.1 then
            sprayerParams.sprayFillLevel = 0
            if sprayer:getFillUnitCapacity(sprayer.spec_sprayer.fillUnitIndex) <= 0 then 
                --- Needs to be set, as otherwise the sprayer will endlessly stop the fieldworker ...
                sprayerParams.sprayFillType = FillType.LIQUIDMANURE
            end
        end
    end
    return superFunc(sprayer, ...)
end
Sprayer.processSprayerArea = Utils.overwrittenFunction(Sprayer.processSprayerArea, processSprayerArea)