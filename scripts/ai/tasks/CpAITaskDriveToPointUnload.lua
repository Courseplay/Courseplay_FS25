---@class CpAITaskDriveToPointUnload : CpAITaskDriveToPoint
CpAITaskDriveToPointUnload = CpObject(CpAITaskDriveToPoint)
function CpAITaskDriveToPointUnload:start()
    if self.isServer then
        self:debug('CP drive to target point task started')
        local strategy = AIDriveStrategyStreetDriveUnloading(self, self.job)
        strategy:setTarget(self.target)
        strategy:setAIVehicle(self.vehicle, self.job:getCpJobParameters())
        self.vehicle:startCpWithStrategy(strategy)
    end
    CpAITask.start(self)
end