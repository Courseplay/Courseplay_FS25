--- Raises/lowers the additional cutters, like the straw/grass pickup for harvesters.
--- Also disables the cutter, while it's waiting for unloading.
---@class CutterController : ImplementController
CutterController = CpObject(ImplementController)

function CutterController:init(vehicle, implement)
    ImplementController.init(self, vehicle, implement)
    self.cutterSpec = self.implement.spec_cutter
end

function CutterController:cancelDelayedTurnOff()
    if self.delayedTurnOff then
        self.delayedTurnOff:delete()
        self.delayedTurnOff = nil
    end
end

function CutterController:delete()
    self:cancelDelayedTurnOff()
end

function CutterController:onFinished()
    self:cancelDelayedTurnOff()
end

function CutterController:getDriveData()
    --- Turns off the cutter, while the driver is waiting for unloading.
    if self.driveStrategy.getCanCutterBeTurnedOff and self.driveStrategy:getCanCutterBeTurnedOff() then
        if self.implement:getIsTurnedOn() then
            -- Do not immediately turn off the cutter. This is just a safety measure for the case when
            -- the combine forgets to check if it is stopped before getCanCutterBeTurnedOff() returns true
            -- also, a little bit of hysteresis won't hurt...
            if not self.delayedTurnOff then
                self:debug('Cutter can be turned off, wait a little bit before turning off...')
                local timer
                timer = Timer.createOneshot(2000, function()
                    -- Ignore callbacks belonging to a cancelled or replaced timer.
                    if self.delayedTurnOff ~= timer then
                        return
                    end
                    self.delayedTurnOff = nil
                    if self.driveStrategy.getCanCutterBeTurnedOff and
                        self.driveStrategy:getCanCutterBeTurnedOff() and self.implement:getIsTurnedOn() then
                        self:debug('Turning off cutter now')
                        self.implement:setIsTurnedOn(false)
                    end
                end)
                self.delayedTurnOff = timer
            end
        end
    else
        self:cancelDelayedTurnOff()
        --- Turns it back on, when the unloading finished and the cutter is lowered.
        if not self.implement:getIsTurnedOn() and self.implement:getIsLowered() then
            self.implement:setIsTurnedOn(true)
        end
    end
    return nil, nil, nil, nil
end

function CutterController:onLowering()
    self.implement:aiImplementStartLine()
end

function CutterController:onRaising()
    self.implement:aiImplementEndLine()
end

--- Makes sure every cutter/pickup headers dont't use the fruit requirements while CP is driving.
local disableAIFruitRequirements = function (implement, superFunc)
    if implement.rootVehicle and implement.rootVehicle.getIsCpActive and implement.rootVehicle:getIsCpActive() then 
        return false
    end
    return superFunc(implement)
end
Cutter.getAllowCutterAIFruitRequirements = Utils.overwrittenFunction(
    Cutter.getAllowCutterAIFruitRequirements, 
    disableAIFruitRequirements)