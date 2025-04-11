

---@class CpAITaskSiloLoader : CpAITask
---@field job CpAIJobSiloLoader
CpAITaskSiloLoader = CpObject(CpAITask)

function CpAITaskSiloLoader:reset()
	self.silo = nil
	self.heap = nil
	CpAITask.reset(self)
end

function CpAITaskSiloLoader:setSiloAndHeap(silo, heap)
	self.silo = silo
	self.heap = heap	
end

function CpAITaskSiloLoader:start()
	if self.isServer then
		local strategy
        if SpecializationUtil.hasSpecialization(ConveyorBelt, self.vehicle.specializations) then 
            self:debug("Starting a silo loader strategy.")
            strategy = AIDriveStrategySiloLoader(self, self.job)
        else 
            self:debug("Starting a shovel silo loader strategy.")
            strategy = AIDriveStrategyShovelSiloLoader(self, self.job)
			local _, unloadTrigger, unloadStation = self.job:getUnloadTriggerAt(self.job:getCpJobParameters().unloadPosition)
            strategy:setUnloadTriggerAndStation(unloadTrigger, unloadStation)
        end
        strategy:setSiloAndHeap(self.silo, self.heap)
        strategy:setAIVehicle(self.vehicle, self.job:getCpJobParameters())
        self.vehicle:startCpWithStrategy(strategy)
	end
	CpAITask.start(self)
end

function CpAITaskSiloLoader:stop(wasJobStopped)
	if self.isServer then
		self.vehicle:stopCpDriver(wasJobStopped)
	end
	CpAITask.stop(self)
end

function CpAITaskSiloLoader:__tostring()
	return "CpAITaskSiloLoader"
end