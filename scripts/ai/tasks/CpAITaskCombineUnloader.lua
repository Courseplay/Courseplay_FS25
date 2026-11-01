
---@class CpAITaskCombineUnloader : CpAITask
CpAITaskCombineUnloader = CpObject(CpAITask)

function CpAITaskCombineUnloader:start()
	if self.isServer then
		self:debug("CP combine unloader task started.")
		local strategy = AIDriveStrategyUnloadCombine(self, self.job)
		strategy:beginAIWorkStart()
		strategy:setAIVehicle(self.vehicle, self.job:getCpJobParameters())
		self.vehicle:startCpWithStrategy(strategy)
	end
	CpAITask.start(self)
end

function CpAITaskCombineUnloader:stop(wasJobStopped)
	if self.isServer then
		self:debug("CP combine unloader task stopped.")
		self.vehicle:stopCpDriver(wasJobStopped)
	end
	CpAITask.stop(self)
end
