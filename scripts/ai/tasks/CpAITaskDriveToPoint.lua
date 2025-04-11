---@class CpAITaskDriveToPoint : CpAITask
CpAITaskDriveToPoint = CpObject(CpAITask)

function CpAITaskDriveToPoint:reset()
	CpAITask.reset(self)
	self.target = nil
end

---@param target GraphTarget
function CpAITaskDriveToPoint:setTarget(target)
	self.target = target
end

function CpAITaskDriveToPoint:start()
    if self.isServer then
        local strategy = AIDriveStrategyStreetDriveToPoint(self, self.job)
        strategy:setTarget(self.target)
        strategy:setAIVehicle(self.vehicle, self.job:getCpJobParameters())
        self.vehicle:startCpWithStrategy(strategy)
    end
    CpAITask.start(self)
end

function CpAITaskDriveToPoint:stop(wasJobStopped)
    if self.isServer then
        self.vehicle:stopCpDriver(wasJobStopped)
    end
    CpAITask.stop(self)
end

function CpAITaskDriveToPoint:__tostring()
	return "CpAITaskDriveToPoint"
end