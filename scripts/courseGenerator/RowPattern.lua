--- Given a number of rows (1-nRows), and a pattern, in what
--- sequence should these rows to be worked on.
---@class RowPattern
local RowPattern = CpObject()

-- these must match the ROW_PATTERN_* values in CourseGeneratorSettingsSetup.xml
RowPattern.ALTERNATING = 1
RowPattern.SKIP = 2
RowPattern.SPIRAL = 3
RowPattern.LANDS = 4
RowPattern.RACETRACK = 5

function RowPattern.create(pattern, ...)
    if pattern == CourseGenerator.RowPattern.ALTERNATING then
        return CourseGenerator.RowPatternAlternating(...)
    elseif pattern == CourseGenerator.RowPattern.SKIP then
        return CourseGenerator.RowPatternSkip(...)
    elseif pattern == CourseGenerator.RowPattern.SPIRAL then
        return CourseGenerator.RowPatternSpiral(...)
    elseif pattern == CourseGenerator.RowPattern.LANDS then
        return CourseGenerator.RowPatternLands(...)
    elseif pattern == CourseGenerator.RowPattern.RACETRACK then
        return CourseGenerator.RowPatternRacetrack(...)
    end
end

function RowPattern:init(logPrefix)
    self.logger = Logger(logPrefix or 'RowPattern')
    self.sequence = {}
end

--- For a given number of rows, the same pattern always result in the same sequence. Therefore,
--- before calling _generateSequence() we always check if we have already generated it for this number of rows.
function RowPattern:getSequence(nRows)
    if #self.sequence == nRows  then
        return self.sequence
    else
        self.sequence = {}
        return self:_generateSequence(nRows)
    end
end

--- Generate a sequence in which the rows must be worked on. It is just an array
--- with the original row numbers, first element of the array is the index of the
--- row the work starts with, last element is the index of the row to finish the
--- work with.
--- We assume that in iterator() we receive a contiguous list of rows.
--- this default implementation leaves them in the original order (which is what
--- the alternating pattern uses)
function RowPattern:_generateSequence(nRows)
    for i = 1, nRows do
        table.insert(self.sequence, i)
    end
    return self.sequence
end

--- Iterate through rows in the order they need to be worked on.
---@param rows CourseGenerator.Row[] rows to work on
function RowPattern:iterator(rows)
    local i = 0
    local sequence = self:getSequence(#rows)
    return function()
        i = i + 1
        if i <= #sequence then
            return i, rows[sequence[i]]
        else
            return nil, nil
        end
    end
end

--- Iterate through rows in the sequence according to the generated sequence,
---@param rows CourseGenerator.Row[]
function RowPattern:__tostring()
    return 'default'
end

--- Get the possible entries to this pattern. If we have block with up/down rows, in theory, we can use any end of
--- the first or last row to enter the pattern, work through the pattern, and exit at the opposite end.
--- Which of the four possible ends are valid, and, if a given entry is selected, which will be the exit, depends
--- on the pattern and the number of rows.
---@param rows CourseGenerator.Row[]
---@return CourseGenerator.RowPattern.Entry[] list of entries that can be used to enter this pattern
function RowPattern:getPossibleEntries(rows)
    -- by default, return both ends of the first row only
    if #rows > 0 then
        return {
            CourseGenerator.RowPattern.Entry(rows[1][1], false, false, false),
            CourseGenerator.RowPattern.Entry(rows[1][#rows[1]], false, false, true)
        }
    else
        return {}
    end
end

--- In what sequence the rows should be worked on when entering this pattern at entry? Use the returned array
--- to build a sequence, and to reverse rows when needed.
---@return [{number, boolean|nil}], Vertex  array of tables {index of row in rows, reverse}, the exit vertex
---   The array defines the order the rows should be worked on, first element of the array points to the index of the
---     first row to be worked on in rows[], and if the boolean is true, that row should be reversed.
---   The exit vertex is the position where the vehicle exits this pattern when using the entry passed in.
function RowPattern:getWorkSequenceAndExit(rows, entry)
    -- each entry of the rowInfos array is a table:
    --  rowIx: index of the row in rows
    --  reverse: should this row be reversed?
    local rowInfos = {}
    if entry.reverseRowOrderBefore then
        for i = #rows, 1, -1 do
            table.insert(rowInfos, { rowIx = i })
        end
    else
        for i = 1, #rows, 1 do
            table.insert(rowInfos, { rowIx = i })
        end
    end
    local rowInfosInWorkSequence = {}
    local reverseOddRows = entry.reverseRowOrderAfter and not entry.reverseOddRows or entry.reverseOddRows
    for i, rowInfo in self:iterator(rowInfos) do
        if i % 2 == (reverseOddRows and 1 or 0) then
            rowInfo.reverse = true
        else
            rowInfo.reverse = false
        end
        table.insert(rowInfosInWorkSequence, rowInfo)
    end
    if entry.reverseRowOrderAfter then
        CourseGenerator.reverseArray(rowInfosInWorkSequence)
    end
    -- rowInfosInWorkSequence now contains the row indices in the order they should be worked on
    -- and if they should be reversed
    local lastRowInfo = rowInfosInWorkSequence[#rowInfosInWorkSequence]
    local lastRow = rows[lastRowInfo.rowIx]
    return rowInfosInWorkSequence, lastRow[lastRowInfo.reverse and 1 or #lastRow]
end

---@class CourseGenerator.RowPattern
CourseGenerator.RowPattern = RowPattern

--- An entry point into the pattern. The entry has a position and instructions to sequence the rows in
--- case this entry is selected.
--- Entries are always generated from a list of rows, the same list of rows what RowPattern:getPossibleEntries() or
--- RowPattern:iterator() expects.
---@class RowPattern.Entry
RowPattern.Entry = CpObject()

---@param position Vector the position of this entry point
---@param reverseRowOrderBefore boolean this entry is on the last row (of the rows passed in to getPossibleEntries(),
--- so when using this entry, the order of the rows should be reversed _before_ calling any RowPattern:iterator()
---@param reverseRowOrderAfter boolean this entry would be on the last row after the rows passed in to getPossibleEntries()
--- are reordered, so when using this entry, the order of the rows must be reversed _after_ calling any RowPattern:iterator()
---@param reverseOddRows boolean this entry uses the last vertex of the row, so when iterating over the rows
--- with RowPattern:iterator, reverse the direction of the first and every odd row (otherwise the second and every
--- even row)
function RowPattern.Entry:init(position, reverseRowOrderBefore, reverseRowOrderAfter, reverseOddRows)
    self.position = position
    self.reverseRowOrderBefore = reverseRowOrderBefore
    self.reverseRowOrderAfter = reverseRowOrderAfter
    self.reverseOddRows = reverseOddRows
end

function RowPattern.Entry:__tostring()
    return string.format('[%s] reverseRowOrderBefore/After:%s/%s reverseOddRows %s',
            self.position, self.reverseRowOrderBefore, self.reverseRowOrderAfter, self.reverseOddRows)
end

---@class CourseGenerator.RowPattern.Entry
CourseGenerator.RowPattern.Entry = RowPattern.Entry

--- Alternating pattern, entry only possible at the first row
---@class RowPatternAlternatingFirstRowEntryOnly : RowPattern
local RowPatternAlternatingFirstRowEntryOnly = CpObject(RowPattern)
---@class CourseGenerator.RowPatternAlternatingFirstRowEntryOnly : CourseGenerator.RowPattern
CourseGenerator.RowPatternAlternatingFirstRowEntryOnly = RowPatternAlternatingFirstRowEntryOnly

--- Alternating pattern, entry only possible at the last row
---@class RowPatternAlternatingLastRowEntryOnly : RowPattern
local RowPatternAlternatingLastRowEntryOnly = CpObject(RowPattern)
---@param rows CourseGenerator.Row[]
---@return CourseGenerator.RowPattern.Entry[] list of entries usable for this pattern
function RowPatternAlternatingLastRowEntryOnly:getPossibleEntries(rows)
    local lastRow = rows[#rows]
    local entries = {
        CourseGenerator.RowPattern.Entry(lastRow[1], true, false, false),
        CourseGenerator.RowPattern.Entry(lastRow[#lastRow], true, false, true),
    }
    return entries
end

---@class CourseGenerator.RowPatternAlternatingLastRowEntryOnly : CourseGenerator.RowPattern
CourseGenerator.RowPatternAlternatingLastRowEntryOnly = RowPatternAlternatingLastRowEntryOnly

--- Default alternating pattern, entry at either end
---@class RowPatternAlternating : RowPattern
local RowPatternAlternating = CpObject(RowPattern)
---@class CourseGenerator.RowPatternAlternating : CourseGenerator.RowPattern
CourseGenerator.RowPatternAlternating = RowPatternAlternating

--- An alternating pattern can be started at either end of the first or last row
---@param rows CourseGenerator.Row[]
---@return CourseGenerator.RowPattern.Entry[] list of entries usable for this pattern
function RowPatternAlternating:getPossibleEntries(rows)
    local firstRow, lastRow = rows[1], rows[#rows]
    local entries = {
        CourseGenerator.RowPattern.Entry(firstRow[1], false, false, false),
        CourseGenerator.RowPattern.Entry(firstRow[#firstRow], false, false, true),
        CourseGenerator.RowPattern.Entry(lastRow[1], true, false, false),
        CourseGenerator.RowPattern.Entry(lastRow[#lastRow], true, false, true),
    }
    return entries
end

function RowPatternAlternating:__tostring()
    return 'alternating'
end

--- Skipping one or more rows
---@class RowPatternSkip : RowPattern
local RowPatternSkip = CpObject(RowPattern)

---@param nRowsToSkip number number of rows to skip
---@param leaveSkippedRowsUnworked boolean if true, sequence will finish after it reaches the last row, leaving
--- the skipped rows unworked. Otherwise, it will work on the skipped rows backwards to the beginning, and then
--- back and forth until all rows are covered.
function RowPatternSkip:init(nRowsToSkip, leaveSkippedRowsUnworked)
    CourseGenerator.RowPattern.init(self, 'RowPatternSkip')
    self.nRowsToSkip = nRowsToSkip
    self.leaveSkippedRowsUnworked = leaveSkippedRowsUnworked
end

---@param rows CourseGenerator.Row[]
---@return CourseGenerator.RowPattern.Entry[] list of entries usable for this pattern
function RowPatternSkip:getPossibleEntries(rows)
    local sequence = self:getSequence(#rows)
    self.logger:debug('%d rows, first row is %d, last %d', #rows, sequence[1], sequence[#sequence])
    local firstRowBefore, lastRowBefore = rows[1], rows[#rows]
    -- last row when we start at either end of rows[1]
    local lastRowAfter = rows[sequence[#sequence]]
    -- last row when we start at either end of rows[#rows]
    local lastRowAfterReversed = rows[#rows - sequence[#sequence] + 1]
    local entries = {
        -- we can start at either end of the first or the last row
        CourseGenerator.RowPattern.Entry(firstRowBefore[1], false, false, false),
        CourseGenerator.RowPattern.Entry(firstRowBefore[#firstRowBefore], false, false, true),
        CourseGenerator.RowPattern.Entry(lastRowBefore[1], true, false, false),
        CourseGenerator.RowPattern.Entry(lastRowBefore[#lastRowBefore], true, false, true)
    }
    return entries
end

function RowPatternSkip:__tostring()
    return 'skip'
end

function RowPatternSkip:_generateSequence(nRows)
    local workedRows = {}
    local lastWorkedRow
    local done = false
    -- need to work on this until all rows are covered
    while (#self.sequence < nRows) and not done do
        -- find first non-worked row
        local start = 1
        while workedRows[start] do
            start = start + 1
        end
        for i = start, nRows, self.nRowsToSkip + 1 do
            table.insert(self.sequence, i)
            workedRows[i] = true
            lastWorkedRow = i
        end
        -- if we don't want to work on the skipped rows, we are done here
        if self.leaveSkippedRowsUnworked then
            done = true
        else
            -- now work on the skipped rows if that is desired
            -- we reached the last Row, now turn back and work on the
            -- rest, find the last unworked Row first
            for i = lastWorkedRow + 1, 1, -(self.nRowsToSkip + 1) do
                if (i <= nRows) and not workedRows[i] then
                    table.insert(self.sequence, i)
                    workedRows[i] = true
                end
            end
        end
    end
    return self.sequence
end

---@class CourseGenerator.RowPatternSkip : CourseGenerator.RowPattern
CourseGenerator.RowPatternSkip = RowPatternSkip

--- A spiral pattern, clockwise or not, starting from inside or outside
---@class RowPatternSpiral : RowPattern
local RowPatternSpiral = CpObject(RowPattern)

---@param clockwise boolean direction to travel the spiral
---@param fromInside boolean if true, start in the middle and continue outwards. If false,
--- start from one of the outermost rows and continue inwards
function RowPatternSpiral:init(clockwise, fromInside)
    CourseGenerator.RowPattern.init(self, 'RowPatternSpiral')
    self.clockwise = clockwise
    self.fromInside = fromInside
end

function RowPatternSpiral:__tostring()
    return 'spiral'
end

function RowPatternSpiral:_generateSequence(nRows)
    -- sequence from outside
    for i = 1, math.floor(nRows / 2) do
        table.insert(self.sequence, i)
        table.insert(self.sequence, nRows - i + 1)
    end
    if nRows % 2 ~= 0 then
        table.insert(self.sequence, math.ceil(nRows / 2))
    end
    if self.fromInside then
        -- flip if starting from the inside
        CourseGenerator.reverseArray(self.sequence)
    end
    return self.sequence
end

---@param rows CourseGenerator.Row[]
---@return CourseGenerator.RowPattern.Entry[] list of entries usable for this pattern
function RowPatternSpiral:getPossibleEntries(rows)
    if #rows < 2 then
        return RowPattern.getPossibleEntries(self, rows)
    end
    -- normalize rows, making sure the second (and all other) row are on the
    -- right side of the first row when looking into the row's direction
    -- this makes life easier later as reduces the number of combinations we need to think about.
    if rows[1][1]:getExitEdge():isPointOnLeft(rows[#rows][1]) then
        self.logger:debug('normalizing rows')
        for _, row in ipairs(rows) do
            row:reverse()
        end
    end
    local sequence = self:getSequence(#rows)
    local odd = #rows % 2 ~= 0
    local firstRow = rows[sequence[1]]
    local secondRow = rows[sequence[2]]
    self.logger:debug('from inside %s, clockwise %s, odd %s', self.fromInside, self.clockwise, odd)
    if self.fromInside then
        if self.clockwise then
            -- from inside, clockwise
            if odd then
                return {
                    CourseGenerator.RowPattern.Entry(firstRow[1], false, false, false),
                    CourseGenerator.RowPattern.Entry(firstRow[#firstRow], true, false, true),
                }
            else
                return {
                    CourseGenerator.RowPattern.Entry(firstRow[#firstRow], false, false, true),
                    secondRow and CourseGenerator.RowPattern.Entry(secondRow[1], true, false, false),
                }
            end
        else
            -- from inside, counterclockwise
            if odd then
                return {
                    CourseGenerator.RowPattern.Entry(firstRow[1], true, false, false),
                    CourseGenerator.RowPattern.Entry(firstRow[#firstRow], false, false, true),
                }
            else
                return {
                    CourseGenerator.RowPattern.Entry(firstRow[1], false, false, false),
                    secondRow and CourseGenerator.RowPattern.Entry(secondRow[#secondRow], true, false, true)
                }
            end

        end
    else
        if self.clockwise then
            -- from outside, clockwise
            return {
                CourseGenerator.RowPattern.Entry(firstRow[1], false, false, false),
                -- if there is only one row we can enter either end of it
                secondRow and CourseGenerator.RowPattern.Entry(secondRow[#secondRow], true, false, true) or
                        CourseGenerator.RowPattern.Entry(firstRow[#firstRow], false, false, true),

            }
        else
            -- from outside, counterclockwise
            return {
                CourseGenerator.RowPattern.Entry(firstRow[#firstRow], false, false, true),
                -- if there is only one row we can enter either end of it
                secondRow and CourseGenerator.RowPattern.Entry(secondRow[1], true, false, false) or
                        CourseGenerator.RowPattern.Entry(firstRow[1], false, false, false),
            }
        end
    end
    -- phuu. that was a long one ...
end

---@class CourseGenerator.RowPatternSpiral : RowPattern
CourseGenerator.RowPatternSpiral = RowPatternSpiral

--- A lands pattern, clockwise or not, dividing the field into "lands" which are
--- individually being worked on in a fashion that the pipe of a combine is over
--- harvested land most of the time
---@class RowPatternLands : RowPattern
local RowPatternLands = CpObject(RowPattern)

---@param clockwise boolean direction to travel the lands, clockwise will keep a pipe on the
--- left side out of the fruit, counterclockwise is for pipe on the right size
---@param nRowsInLands boolean number of rows in each "land"
function RowPatternLands:init(clockwise, nRowsInLands)
    CourseGenerator.RowPattern.init(self)
    self.clockwise = clockwise
    self.nRowsInLands = nRowsInLands
end

function RowPatternLands:__tostring()
    return 'lands'
end

function RowPatternLands:_generateSequence(nRows)
    -- I know this could be generated but it is more readable and easy to visualize this way.
    local rowOrderInLandsCounterclockwise = {
        { 1 },
        { 2, 1 },
        { 2, 3, 1 },
        { 2, 3, 1, 4 },
        { 3, 4, 2, 5, 1 },
        { 3, 4, 2, 5, 1, 6 },
        { 4, 5, 3, 6, 2, 7, 1 },
        { 4, 5, 3, 6, 2, 7, 1, 8 },
        { 5, 6, 4, 7, 3, 8, 2, 9, 1 },
        { 5, 6, 4, 7, 3, 8, 2, 9, 1, 10 },
        { 6, 7, 5, 8, 4, 9, 3, 10, 2, 11, 1 },
        { 6, 7, 5, 8, 4, 9, 3, 10, 2, 11, 1, 12 },
        { 7, 8, 6, 9, 5, 10, 4, 11, 3, 12, 2, 13, 1 },
        { 7, 8, 6, 9, 5, 10, 4, 11, 3, 12, 2, 13, 1, 14 },
        { 8, 9, 7, 10, 6, 11, 5, 12, 4, 13, 3, 14, 2, 15, 1 },
        { 8, 9, 7, 10, 6, 11, 5, 12, 4, 13, 3, 14, 2, 15, 1, 16 },
        { 9, 10, 8, 11, 7, 12, 6, 13, 5, 14, 4, 15, 3, 16, 2, 17, 1 },
        { 9, 10, 8, 11, 7, 12, 6, 13, 5, 14, 4, 15, 3, 16, 2, 17, 1, 18 },
        { 10, 11, 9, 12, 8, 13, 7, 14, 6, 15, 5, 16, 4, 17, 3, 18, 2, 19, 1 },
        { 10, 11, 9, 12, 8, 13, 7, 14, 6, 15, 5, 16, 4, 17, 3, 18, 2, 19, 1, 20 },
        { 11, 12, 10, 13, 9, 14, 8, 15, 7, 16, 6, 17, 5, 18, 4, 19, 3, 20, 2, 21, 1 },
        { 11, 12, 10, 13, 9, 14, 8, 15, 7, 16, 6, 17, 5, 18, 4, 19, 3, 20, 2, 21, 1, 22 },
        { 12, 13, 11, 14, 10, 15, 9, 16, 8, 17, 7, 18, 6, 19, 5, 20, 4, 21, 3, 22, 2, 23, 1 },
        { 12, 13, 11, 14, 10, 15, 9, 16, 8, 17, 7, 18, 6, 19, 5, 20, 4, 21, 3, 22, 2, 23, 1, 24 }
    }
    local rowOrderInLandsClockwise = {
        { 1 },
        { 1, 2 },
        { 2, 1, 3 },
        { 3, 2, 4, 1 },
        { 3, 2, 4, 1, 5 },
        { 4, 3, 5, 2, 6, 1 },
        { 4, 3, 5, 2, 6, 1, 7 },
        { 5, 4, 6, 3, 7, 2, 8, 1 },
        { 5, 4, 6, 3, 7, 2, 8, 1, 9 },
        { 6, 5, 7, 4, 8, 3, 9, 2, 10, 1 },
        { 6, 5, 7, 4, 8, 3, 9, 2, 10, 1, 11 },
        { 7, 6, 8, 5, 9, 4, 10, 3, 11, 2, 12, 1 },
        { 7, 6, 8, 5, 9, 4, 10, 3, 11, 2, 12, 1, 13 },
        { 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1 },
        { 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 },
        { 9, 8, 10, 7, 11, 6, 12, 5, 13, 4, 14, 3, 15, 2, 16, 1 },
        { 9, 8, 10, 7, 11, 6, 12, 5, 13, 4, 14, 3, 15, 2, 16, 1, 17 },
        { 10, 9, 11, 8, 12, 7, 13, 6, 14, 5, 15, 4, 16, 3, 17, 2, 18, 1 },
        { 10, 9, 11, 8, 12, 7, 13, 6, 14, 5, 15, 4, 16, 3, 17, 2, 18, 1, 19 },
        { 11, 10, 12, 9, 13, 8, 14, 7, 15, 6, 16, 5, 17, 4, 18, 3, 19, 2, 20, 1 },
        { 11, 10, 12, 9, 13, 8, 14, 7, 15, 6, 16, 5, 17, 4, 18, 3, 19, 2, 20, 1, 21 },
        { 12, 11, 13, 10, 14, 9, 15, 8, 16, 7, 17, 6, 18, 5, 19, 4, 20, 3, 21, 2, 22, 1 },
        { 12, 11, 13, 10, 14, 9, 15, 8, 16, 7, 17, 6, 18, 5, 19, 4, 20, 3, 21, 2, 22, 1, 23 },
        { 13, 12, 14, 11, 15, 10, 16, 9, 17, 8, 18, 7, 19, 6, 20, 5, 21, 4, 22, 3, 23, 2, 24, 1 }
    }

    -- if we have an even number of rows per land, then we'll finish the land on the same side where we
    -- started it and can work on the subsequent land in the same order
    local rowOrderInLands = self.clockwise and rowOrderInLandsClockwise or rowOrderInLandsCounterclockwise
    -- if we have an odd number of rows per land, we'll end up on the other side and need to use an alternate
    -- order to keep the pipe out of the fruit
    local rowOrderInLandsAlternate = self.clockwise and rowOrderInLandsCounterclockwise or rowOrderInLandsClockwise

    for i = 0, math.floor(nRows / self.nRowsInLands) - 1 do
        for _, j in ipairs(rowOrderInLands[self.nRowsInLands]) do
            table.insert(self.sequence, i * self.nRowsInLands + j)
        end
        if self.nRowsInLands % 2 ~= 0 then
            -- flip the pattern for the next block if we have an odd number of rows per land
            rowOrderInLandsAlternate, rowOrderInLands = rowOrderInLands, rowOrderInLandsAlternate
        end
    end

    local lastRow = self.nRowsInLands * math.floor(nRows / self.nRowsInLands)
    local nRowsLeft = nRows % self.nRowsInLands

    if nRowsLeft > 0 then
        for _, j in ipairs(rowOrderInLands[nRowsLeft]) do
            table.insert(self.sequence, lastRow + j)
        end
    end
    return self.sequence
end

---@param rows CourseGenerator.Row[]
---@return CourseGenerator.RowPattern.Entry[] list of entries usable for this pattern
function RowPatternLands:getPossibleEntries(rows)
    local sequence = self:getSequence(#rows)
    local firstRow = rows[sequence[1]]
    local lastRow = rows[#rows - sequence[1] + 1]
    if not firstRow or not lastRow then
        return RowPattern.getPossibleEntries(self, rows)
    end
    return {
        -- reverseRowOrderBefore, reverseRowOrderAfter, reverseOddRows
        CourseGenerator.RowPattern.Entry(firstRow[1], false, false, false),
        CourseGenerator.RowPattern.Entry(firstRow[#firstRow], false, false, true),
        CourseGenerator.RowPattern.Entry(lastRow[1], true, false, false),
        CourseGenerator.RowPattern.Entry(lastRow[#lastRow], true, false, true)
    }
end

---@class CourseGenerator.RowPatternLands : RowPattern
CourseGenerator.RowPatternLands = RowPatternLands

--- A racetrack (circular) pattern
-- Circular mode: the area is split into multiple blocks which are then worked one by one. Work in each
-- block starts around the middle, skipping a maximum of four rows to avoid 180 turns and working the block in
-- a circular, racetrack like pattern.
-- Depending on the number of rows, there may be a few of them left at the end which will need to be worked in a
-- regular up/down pattern
--  ----- 2 ---- > -------     \
--  ----- 4 ---- > -------     |
--  ----- 6 ---- > -------     |
--  ----- 8 ---- > -------     | Block 1
--  ----- 1 ---- < -------     |
--  ----- 3 ---- < -------     |
--  ----- 5 ---- < ------      |
--  ----- 7 ---- < -------     /
--  -----10 ---- > -------    \
--  -----12 ---- > -------     |
--  ----- 9 ---- < -------     | Block 2
--  -----11 ---- < -------     /
---@class RowPatternRacetrack
local RowPatternRacetrack = CpObject(RowPattern)

---@param nSkip number the number of rows to skip when beginning work. This determines the size of the block, which
--- will be 2 * nSkip rows
function RowPatternRacetrack:init(nSkip)
    CourseGenerator.RowPattern.init(self, 'RowPatternRaceTrack')
    -- by default we skip the first four rows when starting
    self.nSkip = nSkip or 4
end

function RowPatternRacetrack:__tostring()
    return 'Racetrack'
end

function RowPatternRacetrack:_generateSequence(nRows)
    local SKIP_FWD = {} -- skipping rows towards the end of field
    local SKIP_BACK = {} -- skipping rows towards the beginning of the field
    local FILL_IN = {} -- filling in whatever is left after skipping
    -- not that the result would be useful when we have just a handful of rows....
    local nSkip = math.min(self.nSkip, nRows - 1)
    local rowsDone = {}
    -- start in the middle
    local i = nSkip + 1
    table.insert(self.sequence, i)
    rowsDone[i] = true
    local nDone = 1
    local mode = SKIP_BACK
    -- start circling
    while nDone < nRows do
        local nextI
        if mode == SKIP_FWD then
            nextI = i + nSkip + 1
            mode = SKIP_BACK
        elseif mode == SKIP_BACK then
            nextI = i - nSkip
            mode = SKIP_FWD
        elseif mode == FILL_IN then
            nextI = i + 1
        end
        if rowsDone[nextI] then
            -- this has been done already, so skip forward to the next block
            nextI = i + nSkip + 1
            mode = SKIP_BACK
        end
        if nextI > nRows then
            -- reached the end of the field with the current skip, start skipping less, but keep skipping rows
            -- as long as we can to prevent backing up in turn maneuvers
            nSkip = math.floor((nRows - nDone) / 2)
            if nSkip > 0 then
                nextI = i + nSkip + 1
                mode = SKIP_BACK
            else
                -- no room to skip anymore
                mode = FILL_IN
                nextI = i + 1
            end
        end
        i = nextI
        rowsDone[i] = true
        table.insert(self.sequence, i)
        nDone = nDone + 1
    end
    return self.sequence
end

--- We start the racetrack by skipping nSkip rows from either the first or the last row. Each of these two rows can
--- be started at either end.
---@param rows CourseGenerator.Row[]
---@return CourseGenerator.RowPattern.Entry[] list of entries usable for this pattern
function RowPatternRacetrack:getPossibleEntries(rows)
    local firstRow, lastRow = rows[self.nSkip + 1], rows[#rows - (self.nSkip + 1)]

    if not firstRow or not lastRow then
        return RowPattern.getPossibleEntries(self, rows)
    end

    local entries = {
        -- reverseRowOrderBefore, reverseRowOrderAfter, reverseOddRows
        CourseGenerator.RowPattern.Entry(firstRow[1], false, false, false),
        CourseGenerator.RowPattern.Entry(firstRow[#firstRow], false, false, true),
        CourseGenerator.RowPattern.Entry(lastRow[1], true, false, false),
        CourseGenerator.RowPattern.Entry(lastRow[#lastRow], true, false, true),
    }
    return entries
end

---@class CourseGenerator.RowPatternRacetrack : CourseGenerator.RowPattern
CourseGenerator.RowPatternRacetrack = RowPatternRacetrack