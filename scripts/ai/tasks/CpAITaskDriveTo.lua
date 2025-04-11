
---@class CpAITaskDriveTo : CpAITask
CpAITaskDriveTo = CpObject(CpAITask)

function CpAITaskDriveTo:start()
    if self.isServer then
        local strategy = AIDriveStrategyDriveToFieldWorkStart(self, self.job)
        strategy:setAIVehicle(self.vehicle, self.job:getCpJobParameters())
        self.vehicle:startCpWithStrategy(strategy)
    end
    CpAITask.start(self)
end

function CpAITaskDriveTo:stop(wasJobStopped)
    if self.isServer then
        self.vehicle:stopCpDriver(wasJobStopped)
    end
    CpAITask.stop(self)
end

function CpAITaskDriveTo:__tostring()
	return "CpAITaskDriveTo"
end