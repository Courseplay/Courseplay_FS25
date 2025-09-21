--[[
    Profiler class to measure execution time of code blocks.
    Usage:
        local profiler = Profiler:new(vehicle, 100) -- 100 optional, the size of the moving average window
        profiler:start()
        -- code to be profiled
        profiler:stop()
        profiler:log() -- log the profiling results when DBG_PERF is enabled
        profiler:render() -- render the profiling results on screen when DBG_PERF is enabled
]]
Profiler = CpObject()

function Profiler:init(vehicle, n)
    self.logger = Logger('Profiler', Logger.level.debug, CpUtil.DBG_PERF)
    self.movingAverage = MovingAverage(n or 100)
    self.elapsed = 0
    self.max = 0
    self.min = math.huge
    self.vehicle = vehicle
end

function Profiler:start()
    self.startSec = getTimeSec()
end

function Profiler:stop()
    self.elapsed = getTimeSec() - self.startSec
    self.movingAverage:update(self.elapsed)
    if self.elapsed > self.max then
        self.max = self.elapsed
    end
    if self.elapsed < self.min then
        self.min = self.elapsed
    end
end

function Profiler:getAverageMs()
    return self.movingAverage:get() * 1000
end

function Profiler:getMaxMs()
    return self.max * 1000
end

function Profiler:getMinMs()
    return self.min * 1000
end

function Profiler:log()
    self.logger:debug(self.vehicle, "avg: %.3f ms, min: %.3f ms, max: %.3f ms",
            self:getAverageMs(), self:getMinMs(), self:getMaxMs())
end

function Profiler:render()
    if not CpUtil.isVehicleDebugActive(self.vehicle) or not CpDebug:isChannelActive(CpDebug.DBG_PERF) then
        return
    end
    renderText(0.8, 0.9, 0.018, string.format('current: %.1f ms, average: %.1f ms',
            self.elapsed * 1000, self:getAverageMs()))
end