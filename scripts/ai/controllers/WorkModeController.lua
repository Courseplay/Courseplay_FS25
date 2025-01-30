
---@class WorkModeController : ImplementController
WorkModeController = CpObject(ImplementController)
function WorkModeController:init(vehicle, implement)
    ImplementController.init(self, vehicle, implement) 
    self.workModeSpec = implement.spec_workMode
    self.userValue = implement.spec_workMode.state
end

function WorkModeController:update(dt)
    ImplementController.update(self, dt)
    if self.implement.spec_workMode.state ~= nil then
        --- Überschreibt den normalen vom Benutzer ausgewählten Arbeitsmodus.
        local newValue = self.settings.workMode:getValue()
        if self.workModeSpec.state ~= newValue and newValue >= 0 then 
            self.implement:setWorkMode(newValue)
        end
    end
end

function WorkModeController:delete()
    ImplementController.delete(self)
    if self.userValue ~= nil then 
        self.implement:setWorkMode(self.userValue)
    end
end
