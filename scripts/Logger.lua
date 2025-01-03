--- A simple logger that works outside or inside the game.
--- It always writes to the game or command line console. You can also send logs to a file.

---@class Logger
Logger = CpObject()

Logger.level = {
    error = 1,
    warning = 2,
    debug = 3,
    trace = 4
}

Logger.logfile = nil

--- Write log messages to a file (additionally to the console). Note that this affects
--- all logger instances created!
---@param filename string|nil log file name path, or nil to turn of logging to file
function Logger.setLogfile(filename)
    if Logger.logfile then
        Logger.logfile:close()
        Logger.logfile = nil
    end
    if filename ~= nil then
        Logger.logfile = io.open(filename, 'a')
    end
end

---@param debugPrefix string|nil to prefix each debug line with, default empty
---@param level number|nil one of Logger.levels, default Logger.level.debug.
---@param channel number|nil the CP debug channel as defined in DebugChannels.xml to use, optional
function Logger:init(debugPrefix, level, channel)
    self.debugPrefix = debugPrefix or ''
    self.logLevel = level or Logger.level.debug
    self.channel = channel
end

---@param level number one of Logger.levels
function Logger:setLevel(level)
    self.logLevel = math.max(Logger.level.error, math.min(Logger.level.trace, level))
end

function Logger:error(...)
    if self.logLevel >= Logger.level.error then
        self:log('ERROR', ...)
    end
end

function Logger:warning(...)
    if self.logLevel >= Logger.level.warning then
        self:log('WARNING', ...)
    end
end

function Logger:debug(...)
    if self.logLevel >= Logger.level.debug then
        self:log('DEBUG', ...)
    end
end

function Logger:trace(...)
    if self.logLevel >= Logger.level.trace then
        self:log('TRACE', ...)
    end
end

function Logger:info(...)
    self:log('INFO', ...)
end

---@return boolean logging is enabled for the vehicle, or the parameter isn't a vehicle
---@return boolean true if the parameter is a vehicle
function Logger:isEnabled(vehicle)
    if self.channel then
        -- channel set, then likely running in the game, and probably there's a vehicle too as the first parameter
        if type(vehicle) == 'table' then
            -- first parameter is a table, assume it is a vehicle (not a string)
            if CpDebug and CpDebug:isChannelActive(self.channel) and CpUtil.debugEnabledForVehicle() then
                -- debug channel for vehicle active
                return true, true
            else
                -- debug channel for vehicle not active
                return false
            end
        else
            -- first parameter is not a table, assume it is a string, enable logging
            return true
        end
    else
        -- no channel set, likely running outside of the game, always log
        return true
    end
end

--- Debug print, will either just call print when running standalone
--  or use the CP debug channel when running in the game.
function Logger:log(levelPrefix, maybeVehicle, ...)
    if CourseGenerator.isRunningInGame() then
        local enabled, isVehicle = self:isEnabled(maybeVehicle)
        if enabled then
            if isVehicle then
                self:_writeGameLog(levelPrefix, maybeVehicle, ...)
            else
                self:_writeGameLog(levelPrefix, nil, maybeVehicle, ...)
            end
        end
    else
        local message = self:_getCurrentTimeStr() .. ' [' .. levelPrefix .. '] ' .. self.debugPrefix .. ': ' .. string.format(...)
        print(message)
        io.stdout:flush()
        if Logger.logfile then
            Logger.logfile:write(message, '\n')
            Logger.logfile:flush()
        end
    end
end

function Logger:_writeGameLog(levelPrefix, vehicle, ...)
    CpUtil.try(
            function(...)
                local timestamp = getTimeSec()
                local updateLoopIndex = g_updateLoopIndex and (g_updateLoopIndex % 100) or 0
                local prefix = string.format('%.3f [%s %02d] [%s]',
                        timestamp, CpDebug:getText(self.channel), updateLoopIndex, levelPrefix)
                if vehicle then
                    prefix = prefix .. ' [' .. CpUtil.getName(vehicle) .. ']'
                end
                print(string.format('%s %s: %s', prefix, self.debugPrefix, string.format(...)))
            end, ...)
end

function Logger:_getCurrentTimeStr()
    if CourseGenerator.isRunningInGame() then
        -- the game logs hour minute, just add the seconds
        return getDate(':%S')
    else
        return os.date('%Y-%m-%dT%H:%M:%S')
    end
end
