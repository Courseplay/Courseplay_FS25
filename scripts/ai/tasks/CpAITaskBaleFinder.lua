
---@class CpAITaskBaleFinder : CpAITask
CpAITaskBaleFinder = CpObject(CpAITask)

function CpAITaskBaleFinder:start()	
	if self.isServer then
		local strategy = AIDriveStrategyFindBales(self, self.job)
		strategy:setAIVehicle(self.vehicle, self.job:getCpJobParameters())
		self.vehicle:startCpWithStrategy(strategy)
	end
	CpAITask.start(self)
end

function CpAITaskBaleFinder:stop(wasJobStopped)
	if self.isServer then
		self.vehicle:stopCpDriver(wasJobStopped)
	end
	CpAITask.stop(self)
end
function CpAITaskBaleFinder:__tostring()
	return "CpAITaskBaleFinder"
end