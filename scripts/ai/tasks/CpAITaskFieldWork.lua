
---@class CpAITaskFieldWork : CpAITask
CpAITaskFieldWork = CpObject(CpAITask)

function CpAITaskFieldWork:reset()
	self.startPosition = nil
	self.waitingForRefillingActive = false
	CpAITask.reset(self)
end

function CpAITaskFieldWork:setStartPosition(startPosition)
	self.startPosition = startPosition
end

function CpAITaskFieldWork:setWaitingForRefillingActive()
	local cpSpec = self.vehicle.spec_cpAIFieldWorker
	if not self.waitingForRefillingActive and cpSpec.driveStrategy then
		self.waitingForRefillingActive = true
		cpSpec.driveStrategy:raiseControllerEvent(
			AIDriveStrategyCourse.onStartRefillingEvent)
	end
end

function CpAITaskFieldWork:update(dt)
	-- Hack to reevaluate the refill condition for the new setting state after it changed.
	local settingWasChanged = false
	if self.lastSettingValues then 
		if self.lastSettingValues.optionalFertilizer ~= self.vehicle:getCpSettings().sowingMachineFertilizerEnabled:getValue() then
			settingWasChanged = true
		end
		if self.lastSettingValues.optionalSowing ~= self.vehicle:getCpSettings().optionalSowingMachineEnabled:getValue() then
			settingWasChanged = true
		end
	end

	if self.waitingForRefillingActive then 
		self.vehicle:cpHold(1500, true)
		local cpSpec = self.vehicle.spec_cpAIFieldWorker
		self.vehicle:setCpInfoTextActive(InfoTextManager.NEEDS_FILLING)

		local readyToContinue, fillLevelHasChanged = true, false
		cpSpec.driveStrategy:raiseControllerEventWithLambda(
			AIDriveStrategyCourse.onUpdateRefillingEvent,
			function(timerHasFinished, hasChanged)
				readyToContinue = readyToContinue and timerHasFinished
				fillLevelHasChanged = fillLevelHasChanged or hasChanged
			end)
		if readyToContinue and fillLevelHasChanged or settingWasChanged then
			cpSpec.driveStrategy:raiseControllerEvent(
				AIDriveStrategyCourse.onStopRefillingEvent)
			self.waitingForRefillingActive = false
			self.vehicle:resetCpActiveInfoText(InfoTextManager.NEEDS_FILLING)
		end
	end
	self.lastSettingValues = {
		optionalFertilizer = self.vehicle:getCpSettings().sowingMachineFertilizerEnabled:getValue(),
		optionalSowing = self.vehicle:getCpSettings().optionalSowingMachineEnabled:getValue()
	}

end

--- This function can be used to trace the triggering of AI events. The timing of these is critical for multiplayer
--- to work properly, these traces help to determine if this timing is correct. Bad timing will result in implements
--- not lowering or not turning on in multiplayer, while there are no symptoms in single player.
---
--- The game engine needs a separate phase for preparing to make sure that the
---   * onAIFieldWorkerStart,
---   * onAIFieldWorkerPrepareForWork,
---   * onAIImplementStartLine
--- events are generated one by one, one in each update loop so that at the end of the loop,
--- AIFieldWorker:updateAIFieldWorker() triggers a onAIFieldWorkerActive event.
---
function CpAITaskFieldWork:turnOnAIEventTrace()
	self.vehicle.raiseAIEvent = function(vehicle, event1, event2, ...)
		if vehicle.cpLastRaiseAIEvent ~= event1 and vehicle.cpLastRaiseAIEvent2 ~= event2 then
			CpUtil.infoVehicle(vehicle, "raiseAIEvent %s %s", event1, event2)
		end
		vehicle.cpLastRaiseAIEvent1 = event1
		vehicle.cpLastRaiseAIEvent2 = event2
		AIVehicle.raiseAIEvent(vehicle, event1, event2, ...)
	end

	if self.vehicle.actionController ~= nil then
		self.vehicle.actionController.onAIEvent = function(actionController, sourceVehicle, eventName)
			if eventName ~= 'onAIFieldWorkerActive' and eventName ~= 'onAIImplementActive' then
				CpUtil.infoVehicle(self.vehicle, "   onAIEvent %s, source %s", eventName, CpUtil.getName(sourceVehicle))
			end
			VehicleActionController.onAIEvent(actionController, sourceVehicle, eventName)
		end
	end
end

--- Makes sure the cp fieldworker gets started.
function CpAITaskFieldWork:start()
	self:debug("Field work task started.")
	local spec = self.vehicle.spec_aiFieldWorker
	spec.isActive = true
	if self.isServer then
		self.vehicle:updateAIFieldWorkerImplementData()
		self.vehicle:raiseAIEvent("onAIFieldWorkerStart", "onAIImplementStart")
		if self.vehicle:getAINeedsTrafficCollisionBox() and (AIFieldWorker.TRAFFIC_COLLISION ~= nil and
			(AIFieldWorker.TRAFFIC_COLLISION ~= 0 and spec.aiTrafficCollision == nil)) then

			spec.aiTrafficCollision = clone(AIFieldWorker.TRAFFIC_COLLISION, true, false, true)
		end
		local cpSpec = self.vehicle.spec_cpAIFieldWorker
		--- Remembers the last lane offset setting value that was used.
        cpSpec.cpJobStartAtLastWp:getCpJobParameters().laneOffset:setValue(self.job:getCpJobParameters().laneOffset:getValue())
		if spec.driveStrategies ~= nil then
			-- This deletion code could be removed, but just to be sure we let it stay here for now.
			for i = #spec.driveStrategies, 1, -1 do
				spec.driveStrategies[i]:delete()
				table.remove(spec.driveStrategies, i)
			end
			spec.driveStrategies = {}
		end
		local cpDriveStrategy
		if self.startPosition and g_vineScanner:hasVineNodesCloseBy(self.startPosition.x, self.startPosition.z) then
			--- Checks if there are any vine nodes close to the starting point.
			self:debug('Found a vine course, install CP vine fieldwork drive strategy for it')
			cpDriveStrategy = AIDriveStrategyVineFieldWorkCourse(self, self.job)
		elseif AIUtil.hasChildVehicleWithSpecialization(self.vehicle, Plow) then
			self:debug('Found a plow, install CP plow drive strategy for it')
			cpDriveStrategy = AIDriveStrategyPlowCourse(self, self.job)
		else
			local combine = AIUtil.getImplementOrVehicleWithSpecialization(self.vehicle, Combine)
			local pipe = combine and SpecializationUtil.hasSpecialization(Pipe, combine.specializations)
			if combine and pipe then
				-- Default harvesters with a pipe.
				self:debug('Found a combine with pipe, install CP combine drive strategy for it')
				cpDriveStrategy = AIDriveStrategyCombineCourse(self, self.job)
				cpSpec.combineDriveStrategy = cpDriveStrategy
			end
			if not cpDriveStrategy then
				self:debug('Installing default CP fieldwork drive strategy')
				cpDriveStrategy = AIDriveStrategyFieldWorkCourse(self, self.job)
			end
		end
		cpDriveStrategy:setAIVehicle(self.vehicle, self.job:getCpJobParameters())
		cpSpec.driveStrategy = cpDriveStrategy
		--- Only the last driving strategy can stop the helper, while it is running.
		table.insert(spec.driveStrategies, cpDriveStrategy)
	else
		self.vehicle:raiseAIEvent("onAIFieldWorkerStart", "onAIImplementStart")
	end
	CpAITask.start(self)
end

function CpAITaskFieldWork:stop(wasJobStopped)
	if self.waitingForRefillingActive then
		local cpSpec = self.vehicle.spec_cpAIFieldWorker
		cpSpec.driveStrategy:raiseControllerEvent(
				AIDriveStrategyCourse.onStopRefillingEvent)
	end
	self.vehicle:stopFieldWorker()
	if self.isServer then 
		self:debug("Field work task stopped.")
		self.vehicle:cpBrakeToStop()
	end
	CpAITask.stop(self, wasJobStopped)
end
