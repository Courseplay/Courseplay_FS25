
---@class CpAITaskBunkerSilo : CpAITask
CpAITaskBunkerSilo = CpObject(CpAITask)

function CpAITaskBunkerSilo:reset()
	self.silo = nil
	CpAITask.reset(self)
end

function CpAITaskBunkerSilo:setSilo(silo)
	self.silo = silo	
end

function CpAITaskBunkerSilo:start()
	if self.isServer then
		self.vehicle:resetCpCoursesFromGui()
		local strategy = AIDriveStrategyBunkerSilo(self, self.job)
		strategy:setSilo(self.silo)
		strategy:setAIVehicle(self.vehicle, self.job:getCpJobParameters())
		self.vehicle:startCpWithStrategy(strategy)
	end
	CpAITask.start(self)
end

function CpAITaskBunkerSilo:stop(wasJobStopped)
	if self.isServer then
		self.vehicle:stopCpDriver(wasJobStopped)
	end
	CpAITask.stop(self)
end

function CpAITaskBunkerSilo:__tostring()
	return "CpAITaskBunkerSilo"
end