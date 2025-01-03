--- A block is an area in the center of the field which can
--- be covered by one set of alternating up/down rows, simply
--- turning 180 at the row end into the next row.
---
--- Regular rectangular or simple convex fields will always have
--- just one block. More complex shapes may require splitting
--- the area into multiple blocks, depending on the row angle.
---
--- ------------     --------------
--- |    A     |     |    B       |
--- |  .....   |_____|  .....     |
--- |                             |
--- |            C                |
--- ------------------------------
--- For instance, a field like above is split into three blocks,
--- A, B and C, by the peninsula on the top, between A and B, if
--- rows are horizontal. With vertical rows the entire field
--- would be just a single block.

local Block = CpObject()

---@param context CourseGenerator.FieldworkContext
function Block:init(context, id)
    self.id = id or 0
    self.logger = Logger('Block ' .. self.id, nil, CpDebug.DBG_COURSES)
    -- rows in the order they were added, first vertex of each row is on the same side
    self.rows = {}
    -- rows in the order they will be worked on, every second row in this sequence is reversed
    -- so we remain on the same side of the block when switching to the next row
    self.rowsInWorkSequence = {}
    self.rowPattern = context.rowPattern or CourseGenerator.RowPatternAlternating()
    self.context = context
end

function Block:getId()
    return self.id
end

function Block:__tostring()
    return self.id
end

function Block:addRow(row)
    row:setOriginalSequenceNumber(#self.rows + 1)
    row:setBlockNumber(self.id)
    table.insert(self.rows, row)
end

function Block:addRows(rows)
    for _, row in ipairs(rows) do
        self:addRow(row)
    end
end

---@return number of rows in this block
function Block:getNumberOfRows()
    -- we may not have them sequenced when this is called, so can't use self.rowsInWorkSequence
    return #self.rows
end

--- Does this row overlap with this block, that is, with the last row of this block.
---@param row CourseGenerator.Row
---@return boolean true if row overlaps this block or if the block has no rows
function Block:overlaps(row)
    return #self.rows == 0 or self.rows[#self.rows]:overlaps(row)
end

function Block:getPolygon()
    if not self.polygon then
        -- assuming the first and last row in the array are also the first and last geographically (all other
        -- rows are between these two) and both have the same direction
        local firstRow, lastRow = self.rows[1], self.rows[#self.rows]
        self.polygon = Polygon({ firstRow[1], firstRow[#firstRow], lastRow[#lastRow], lastRow[1] })
    end
    return self.polygon
end

---@return CourseGenerator.Row[] rows in the order they should be worked on. Every other row is reversed, so it starts at the
--- end where the previous one ends.
function Block:getRows()
    return self.rowsInWorkSequence
end

---@return CourseGenerator.Row[] rows in the order they were created, same direction as they were created
function Block:getUnsequencedRows()
    return self.rows
end

---@return CourseGenerator.Row first row of the block in the work sequence
function Block:getFirstRow()
    return self.rowsInWorkSequence[1]
end

---@return CourseGenerator.Row last row of the block in the work sequence
function Block:getLastRow()
    return self.rowsInWorkSequence[#self.rowsInWorkSequence]
end

---@return CourseGenerator.RowPattern.Entry[]
function Block:getPossibleEntries()
    if not self.possibleEntries then
        -- cache this as the genetic algorithm needs it frequently, also, this way
        -- a block always returns the same Entry instances so they key be used as keys in further caching
        self.possibleEntries = self.rowPattern:getPossibleEntries(self.rows)
    end
    return self.possibleEntries
end

--- Finalize this block, set the entry we will be using, rearrange rows accordingly, set all row attributes and create
--- a sequence in which the rows must be worked on
---@param entry CourseGenerator.RowPattern.Entry the entry to be used for this block
---@return Vertex the last vertex of the last row, the exit point from this block (to be used to find the entry
--- to the next one.
function Block:finalize(entry)
    self.logger:debug('Finalizing, entry %s', entry)
    self.logger:debug('Generating row sequence for %d rows, pattern: %s', #self.rows, self.rowPattern)
    local sequence, exit = self.rowPattern:getWorkSequenceAndExit(self.rows, entry)
    self.rowsInWorkSequence = {}
    for i, rowInfo in ipairs(sequence) do
        local row = self.rows[rowInfo.rowIx]:clone()
        if rowInfo.reverse then
            row:reverse()
        end
        -- this assumes row has not been manipulated other than reversed
        local rowOnLeftWorked, rowOnRightWorked, leftSideBlockBoundary, rightSideBlockBoundary =
            self:_getAdjacentRowInfo(rowInfo.rowIx, rowInfo.reverse, self.rows, self.rowsInWorkSequence)
        row:setAdjacentRowInfo(rowOnLeftWorked, rowOnRightWorked, leftSideBlockBoundary, rightSideBlockBoundary)
        self.logger:debug('row %d is now at position %d, left/right worked %s/%s, headland %s/%s',
                row:getOriginalSequenceNumber(), i, rowOnLeftWorked, rowOnRightWorked, leftSideBlockBoundary, rightSideBlockBoundary)
        row:adjustLength(self.context)
        -- need vertices close enough so the smoothing in goAround() only starts close to the island
        row:splitEdges(self.context.rowWaypointDistance or CourseGenerator.cRowWaypointDistance)
        row:setRowNumber(i)
        row:setAllAttributes()
        table.insert(self.rowsInWorkSequence, row)
    end
    return exit
end

---@return Vertex
function Block:getExit(entry)
    local _, exit = self.rowPattern:getWorkSequenceAndExit(self.rows, entry)
    return exit
end

function Block:getPath()
    if self.path == nil then
        self.path = Polyline()
        for _, row in ipairs(self.rowsInWorkSequence) do
            self.path:appendMany(row)
        end
    end
    return self.path
end

---@param circle boolean when true, make a full circle on the other polygon, else just go around and continue
function Block:bypassSmallIsland(islandHeadlandPolygon, circle)
    local thisIslandCircled = not circle
    for _, row in ipairs(self.rowsInWorkSequence) do
        thisIslandCircled = row:bypassSmallIsland(self.context, islandHeadlandPolygon, 1, not thisIslandCircled) or thisIslandCircled
        -- make sure all new bypass waypoints have the proper attributes
        row:setAllAttributes()
    end
    return thisIslandCircled
end

function Block:getEntryVertex()
    return self.rowsInWorkSequence[1][1]
end

function Block:getExitVertex()
    local lastRow = self.rowsInWorkSequence[#self.rowsInWorkSequence]
    return lastRow[#lastRow]
end

--- For a given row, find out if the rows on the left and right have been already worked on when we get
--- to this row in the working sequence and set the waypoint attributes on the row.
--- This can be used to figure out if there is fruit under the combine's pipe at any position, or which side
--- to open the ridge marker.
---@param originalIx number index of row in rows (the original index)
---@param reversed boolean true if the row in the work sequence had to be reversed
---@param rows Row[] in the order there where generated
---@param previousRowsInWorkSequence Row[] rows already worked, in the order they should be worked on
---@return boolean, boolean, boolean, boolean rows on the left worked, rows on the right worked, left side is headland
--- or field boundary, right side is headland or field boundary
function Block:_getAdjacentRowInfo(originalIx, reversed, rows, previousRowsInWorkSequence)
    local originalRow = rows[originalIx]
    -- assume -1 is on left, + 1 is on right from row
    local rowLeftIx = originalIx - 1
    local rowRightIx = originalIx + 1
    -- now check if our assumption was correct, remembering that the current row may be the first or last and
    -- has one neighbor only
    if (rows[rowRightIx] and originalRow[1]:getExitEdge():isPointOnLeft(rows[rowRightIx][1])) or
            (rows[rowLeftIx] and not originalRow[1]:getExitEdge():isPointOnLeft(rows[rowLeftIx][1])) then
        -- first point of the rowRight is left of the original row's first point, so
        -- rowRight is really on the left, our assumption was incorrect, so reverse them
        rowLeftIx, rowRightIx = rowRightIx, rowLeftIx
    end
    if reversed then
        -- the original row has been reversed, so sides must flip again
        rowLeftIx, rowRightIx = rowRightIx, rowLeftIx
    end
    -- We can be sure that in the final direction row is pointing, rowLeft and rowRight are the left and
    -- right side, respectively. Now, let's check if those rows are earlier in the sequence as the current one.
    -- If a row is earlier in the sequence, it means that side of our current row has already been worked on, which
    -- may be interesting for harvesting, as there would be no fruit on the worked side, or, when working with
    -- an implement with ridge markers, you wouldn't want to activate them on the side you already worked on.
    local rowOnLeftWorked, rowOnRightWorked = false, false
    for _, r in ipairs(previousRowsInWorkSequence) do
        if r:getOriginalSequenceNumber() == rowRightIx then
            rowOnRightWorked = true
        end
        if r:getOriginalSequenceNumber() == rowLeftIx then
            rowOnLeftWorked = true
        end
    end
    return rowOnLeftWorked, rowOnRightWorked, rowLeftIx == 0 or rowLeftIx > #rows, rowRightIx == 0 or rowRightIx > #rows
end

---@class CourseGenerator.Block
CourseGenerator.Block = Block