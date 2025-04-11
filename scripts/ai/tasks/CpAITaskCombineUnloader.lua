
---@class CpAITaskCombineUnloader : CpAITask
CpAITaskCombineUnloader = CpObject(CpAITask)

function CpAITaskCombineUnloader:start()
	if self.isServer then
		local strategy = AIDriveStrategyUnloadCombine(self, self.job)
		strategy:setAIVehicle(self.vehicle, self.job:getCpJobParameters())
		self.vehicle:startCpWithStrategy(strategy)
	end
	CpAITask.start(self)
end

function CpAITaskCombineUnloader:stop(wasJobStopped)
	if self.isServer then
		self.vehicle:stopCpDriver(wasJobStopped)
	end
	CpAITask.stop(self)
end

function CpAITaskCombineUnloader:__tostring()
	return "CpAITaskCombineUnloader"
end