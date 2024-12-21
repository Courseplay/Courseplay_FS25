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
function Logger:init(debugPrefix, level)
    self.debugPrefix = debugPrefix or ''
    self.logLevel = level or Logger.level.debug
end

---@param level number one of Logger.levels
function Logger:setLevel(level)
    self.logLevel = math.max(Logger.level.error, math.min(Logger.level.trace, level))
end

function Logger:error(...)
    if self.logLevel >= Logger.level.error then
        self:log('[ERROR] ' .. self.debugPrefix .. ': ' .. string.format(...))
    end
end

function Logger:warning(...)
    if self.logLevel >= Logger.level.warning then
        self:log('[WARNING] ' .. self.debugPrefix .. ': ' .. string.format(...))
    end
end

function Logger:debug(...)
    if self.logLevel >= Logger.level.debug then
        self:log('[DEBUG] ' .. self.debugPrefix .. ': ' .. string.format(...))
    end
end

function Logger:trace(...)
    if self.logLevel >= Logger.level.trace then
        self:log('[TRACE] ' .. self.debugPrefix .. ': ' .. string.format(...))
    end
end

--- Debug print, will either just call print when running standalone
--  or use the CP debug channel when running in the game.
function Logger:log(...)
    if CourseGenerator.isRunningInGame() then
        CpUtil.debugVehicle(CpDebug.DBG_COURSES, CpUtil.getCurrentVehicle(), ...)
    else
        local message = self:_getCurrentTimeStr() .. ' ' .. string.format(...)
        print(message)
        io.stdout:flush()
        if Logger.logfile then
            Logger.logfile:write(message, '\n')
            Logger.logfile:flush()
        end
    end
end

function Logger:_getCurrentTimeStr()
    if CourseGenerator.isRunningInGame() then
        -- the game logs hour minute, just add the seconds
        return getDate(':%S')
    else
        return os.date('%Y-%m-%dT%H:%M:%S')
    end
end
