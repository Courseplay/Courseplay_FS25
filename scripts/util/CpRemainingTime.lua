
--[[
	Simple calculation of the remaining time for the course.

	- The optimal time is calculated by the course length divided by the max of the work speed or field work speed setting.
	- Every turn adds a flat turn penalty to the course length. Reduced by the course progress with a logarithm. (0 <-> ln(3)[~1.098..] )
	- Global exponential factor applied to the course, depending on the progress left. (1 <-> e[~2.718..])

	- Values measured with a simple course with one headland and 5m working width.
	- small course with 136 wp is displayed with about 4min, but it takes about 6min.
	- bigger course with 2766 wp is displayed with arround 1hour 29min, but takes about 1hour 15min.
	- Conclusion: A rather small course have to too less displayed time, but thats just a few min off and not too bad.
	- A bigger course will have more time displayed, but this is better then have a too less calculated time and have to wait for too long.

]]--
---@class CpRemainingTime
CpRemainingTime = CpObject()
CpRemainingTime.DISABLED_TEXT = ""
CpRemainingTime.TURN_PENALTY = 30 -- Flat turn penalty in seconds.
CpRemainingTime.EXP_PENALTY_REDUCTION = 0.2 -- Reduces the impact of the exponential penalty.
CpRemainingTime.DEBUG_ACTIVE = true

function CpRemainingTime:init(vehicle, course, startIx)
	self.vehicle = vehicle
	self.debugChannel = CpDebug.DBG_FIELDWORK
	self.course = course
	self.startIx = startIx
	self.timeActiveMs = 0
	self.startTimeMs = 0
	self.time = 0
	self:setText(self.DISABLED_TEXT)
	self:start()
end

function CpRemainingTime:reset()
	self:info("The driver stopped after: %s, time passed without standing still: %s, first prediction was: %s",
		CpGuiUtil.getFormatTimeText((g_time - self.startTimeMs)/1000),
		CpGuiUtil.getFormatTimeText(self.timeActiveMs/1000),
		CpGuiUtil.getFormatTimeText(self.firstTimePrediction or 0))
	self.time = 0
	self.timeActiveMs = 0
	self.startTimeMs = 0
	self:setText(self.DISABLED_TEXT)
	self.course = nil 
	self.lastIx = nil
	self.firstTimePrediction = nil
end

function CpRemainingTime:start()
	self.startTimeMs = g_time
end

function CpRemainingTime:update(dt)
	if CpUtil.getCurrentVehicle() == self.vehicle and self.DEBUG_ACTIVE and CpDebug:isChannelActive(self.debugChannel, self.vehicle) then
		DebugUtil.renderTable(0.2, 0.2, 0.018, {
			{name = "time", value = CpGuiUtil.getFormatTimeText(self.time)},
			{name = "optimal speed", value = MathUtil.mpsToKmh(self:getOptimalSpeed())},
			{name = "optimal time", value = CpGuiUtil.getFormatTimeText(self:getOptimalCourseTime(self.course, self.lastIx))},
			{name = "correction factor", value = self:getCorrectionFactor(self.course, self.lastIx)},
			{name = "turn offset", value = CpGuiUtil.getFormatTimeText(self:getTurnPenalty(self.course, self.lastIx))},
			{name = "first time prediction", value = CpGuiUtil.getFormatTimeText(self.firstTimePrediction and self.firstTimePrediction or 0)},
			{name = "time without standing still", value = CpGuiUtil.getFormatTimeText(self.timeActiveMs/1000)}
			
		}, 0)
	end
	if not AIUtil.isStopped(self.vehicle) then 
		self.timeActiveMs = self.timeActiveMs + dt
		if self.course ~= nil then
			self:calculate()
		end
	end
end

function CpRemainingTime:calculate()
	local time = self:getRemainingCourseTime(self.course, self.course:getCurrentWaypointIx())
	self:applyTime(time)
end

--- Get the max speed for the field work. Depending on the max work speed and the field work speed.
function CpRemainingTime:getOptimalSpeed() -- in m/s
	local fieldSettingSpeed = self.vehicle:getCpSettings().fieldWorkSpeed:getValue()
	local speedLimit = self.vehicle:getSpeedLimit(true)
	if speedLimit == math.huge then -- Giants ..., happens when for example the work tool is raised ..
		return 0
	end
	return MathUtil.kmhToMps(CpMathUtil.clamp(speedLimit, 0, fieldSettingSpeed))
end 

--- Estimate of the course time left with penalties increased.
function CpRemainingTime:getRemainingCourseTime(course, ix) -- in seconds 
	return math.max(0, self:getCorrectionFactor(course, ix) * self:getOptimalCourseTime(course, ix) + self:getTurnPenalty(course, ix))
end

function CpRemainingTime:getCorrectionFactor(course, ix)
	return course ~= nil and ix ~=nil and math.max(math.exp(1-course:getProgress(ix)) * self.EXP_PENALTY_REDUCTION, 1) or 0
end

--- Optimal course time, where no additional turn times are included.
function CpRemainingTime:getOptimalCourseTime(course, ix)
	if course == nil or ix == nil then 
		return 0
	end
	local dist = course:getRemainingDistanceAndTurnsFrom(ix)
	local speed = self:getOptimalSpeed()
	if speed == 0 then 
		return 0
	end
	return dist / speed
end

function CpRemainingTime:getTurnPenalty(course, ix)
	if course == nil or ix == nil then 
		return 0
	end
	local dist, numTurns = course:getRemainingDistanceAndTurnsFrom(ix)
	return numTurns * self.TURN_PENALTY
end

function CpRemainingTime:getText()
	return self.text
end

function CpRemainingTime:setText(text)
	self.text = text
end

function CpRemainingTime:applyTime(time)
	if self:getOptimalSpeed() == 0 then 
		return 
	end
	if self.time == 0 and not self.firstTimePrediction then 
		self.firstTimePrediction = time
	end
	self.text = CpGuiUtil.getFormatTimeText(time or 0)
	self.time = time
end

function CpRemainingTime:debug(...)
	CpUtil.debugVehicle(self.debugChannel, self.vehicle, ...)
end


function CpRemainingTime:info(...)
	CpUtil.infoVehicle(self.vehicle, ...)
end