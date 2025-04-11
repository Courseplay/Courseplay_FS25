
---@class CpAITaskAttachHeader : CpAITask
CpAITaskAttachHeader = CpObject(CpAITask)

function CpAITaskAttachHeader:start()
    if self.isServer then
        local strategy = AIDriveStrategyAttachHeader(self, self.job)
        strategy:setAIVehicle(self.vehicle, self.job:getCpJobParameters())
        self.vehicle:startCpWithStrategy(strategy)
    end
	CpAITask.start(self)
end

function CpAITaskAttachHeader:stop(wasJobStopped)
    if self.isServer then
        self.vehicle:stopCpDriver(wasJobStopped)
    end
    CpAITask.stop(self)
end

function CpAITaskAttachHeader:__tostring()
	return "CpAITaskBaleFinder"
end