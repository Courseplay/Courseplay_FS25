---@class CpAITaskDriveToPointLoad : CpAITaskDriveToPoint
CpAITaskDriveToPointLoad = CpObject(CpAITaskDriveToPoint)
function CpAITaskDriveToPointLoad:start()
    if self.isServer then
        local strategy = AIDriveStrategyStreetDriveLoading(self, self.job)
        strategy:setTarget(self.target)
        strategy:setAIVehicle(self.vehicle, self.job:getCpJobParameters())
        self.vehicle:startCpWithStrategy(strategy)
    end
    CpAITask.start(self)
end

function CpAITaskDriveToPointLoad:__tostring()
	return "CpAITaskDriveToPointLoad"
end