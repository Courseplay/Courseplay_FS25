
--- Wrapper for the course object, which allows waypoint manipulations.
---@class EditorCourseWrapper
EditorCourseWrapper = CpObject()

function EditorCourseWrapper:init(course)
	self.course = course
	self.selectedWaypoints = {}
	self.hoveredWaypointIx = nil
	self.headlandMode = nil
	self.rowNumberMode = nil
	self.connectingPathActive = false
end

function EditorCourseWrapper:getCourse()
	return self.course	
end

function EditorCourseWrapper:getVisiblePoints()
	return self.course.waypoints	
end

function EditorCourseWrapper:getFirstWaypointPosition()
	return self.course:getWaypointPosition(1)
end

function EditorCourseWrapper:getAllWaypoints()
	return self.course:getAllWaypoints()
end

function EditorCourseWrapper:isWaypointTurn(ix)
	local wp = ix ~=nil and self.course:getWaypoint(ix)
	return wp and (wp:isRowEnd() or wp:isRowStart())
end

------------------------------------
--- Course display interaction.
------------------------------------

--- Is the waypoint hovered by a editor brush?
function EditorCourseWrapper:isHovered(ix)
	return self.hoveredWaypointIx == ix
end

--- Sets the hovered waypoint by the editor brush.
function EditorCourseWrapper:setHovered(ix)
	local lastHovered = self.hoveredWaypointIx
	self.hoveredWaypointIx = ix
	return lastHovered
end

function EditorCourseWrapper:resetHovered()
	local lastHovered = self.hoveredWaypointIx
	self.hoveredWaypointIx = nil
	return lastHovered
end

--- Is the waypoint selected by a editor brush?
function EditorCourseWrapper:isSelected(ix)
	if ix then
		return self.selectedWaypoints[ix]
	end
end

function EditorCourseWrapper:setSelected(ix)
	if ix then
		self.selectedWaypoints[ix] = true
	end
end

function EditorCourseWrapper:resetSelected()
	self.selectedWaypoints = {}
end

--- Sets the selected headland to show, 0 == lanes are visible.
function EditorCourseWrapper:setHeadlandMode(mode)
	self.headlandMode = mode	
end

--- Sets the selected lane to show.
function EditorCourseWrapper:setRowNumberMode(mode)
	self.rowNumberMode = mode	
end

--- Sets the connecting track visible.
function EditorCourseWrapper:setConnectingPathActive(active)
	self.connectingPathActive = active
end

function EditorCourseWrapper:isHeadland(ix)
	local wp = ix ~=nil and self.course:getWaypoint(ix)
	if wp and self.headlandMode ~= nil then
		if self.headlandMode > 0 then
			return self.course:isOnHeadland(ix, self.headlandMode)
		elseif self.headlandMode == 0 then
			return not self.course:isOnHeadland(ix)
		end
	end
end

function EditorCourseWrapper:isOnRowNumber(ix)
	local wp = ix ~=nil and self.course:getWaypoint(ix)
	if wp and wp:getRowNumber() ~= nil and self.rowNumberMode ~= nil then
		return wp:getRowNumber() == self.rowNumberMode
	end
end

function EditorCourseWrapper:isConnectingPath(ix)
	local wp = ix ~=nil and self.course:getWaypoint(ix)
	if wp and self.connectingPathActive then
		return self.course:isOnConnectingPath(ix)
	end
end

------------------------------------
--- Course editor interaction.
------------------------------------

--- Inserts a waypoint ahead of the given waypoint.
--- The inserted waypoint has the same attributes, as the selected one.
function EditorCourseWrapper:insertWaypointAhead(ix)
	local waypoint = self.course:getWaypoint(ix)
	local wp
	if waypoint then 
		if waypoint:isRowStart() then
			return nil, false
		end
		local frontWp = self.course:getWaypoint(ix-1)
		if frontWp and ix > 1 then 
			local x, z = frontWp.x + (waypoint.x - frontWp.x)/2 , frontWp.z + (waypoint.z - frontWp.z)/2
			wp = waypoint:clone()
			wp:resetRowStartEnd()
			wp:setPosition(x, z)
			table.insert(self.course.waypoints, ix, wp)
		else 
			local backWp = self.course:getWaypoint(ix+1)
			if backWp then
				local dx, dz = MathUtil.vector2Normalize(backWp.x - waypoint.x, backWp.z - waypoint.z)
				local x, z = waypoint.x - dx * 3, waypoint.z - dz * 3
				wp = waypoint:clone()
				wp:resetRowStartEnd()
				wp:setPosition(x, z)
				table.insert(self.course.waypoints, 1, wp)
			end
		end
	end
	return wp, true
end

--- Inserts a waypoint behind the given waypoint.
--- The inserted waypoint has the same attributes, as the selected one.
function EditorCourseWrapper:insertWaypointBehind(ix)
	local waypoint = self.course:getWaypoint(ix)
	local wp
	if waypoint then 
		if waypoint:isRowEnd() then
			return nil, false
		end
		local backWp = self.course:getWaypoint(ix+1)
		if backWp and ix < #self.course.waypoints then 
			local x, z = waypoint.x + (backWp.x - waypoint.x)/2 , waypoint.z + (backWp.z - waypoint.z)/2
			wp = waypoint:clone()
			wp:resetRowStartEnd()
			wp:setPosition(x, z)
			table.insert(self.course.waypoints, ix+1, wp)
		else 
			local frontWp = self.course:getWaypoint(ix-1)
			if frontWp then
				local dx, dz = MathUtil.vector2Normalize(waypoint.x - frontWp.x, waypoint.z - frontWp.z)
				local x, z = waypoint.x + dx * 3, waypoint.z + dz * 3
				wp = waypoint:clone()
				wp:resetRowStartEnd()
				wp:setPosition(x, z)
				table.insert(self.course.waypoints, wp)
			end
		end
	end
	return wp, true
end

--- Moves the waypoint to a given world position.
function EditorCourseWrapper:setWaypointPosition(ix, x, z)
	local waypoint = self.course:getWaypoint(ix)
	if waypoint then 
		waypoint:setPosition(x, z)
	end
end

--- Moves the waypoint by a given difference.
function EditorCourseWrapper:moveMultipleWaypoints(firstIx, lastIx, dx, dz)
	for i=firstIx,lastIx do
		local wp = self.course:getWaypoint(i)
		if wp then 
			wp:translate(dx, dz)
		end
	end
end

--- Deletes a given waypoint.
function EditorCourseWrapper:deleteWaypoint(ix)
	local wp = self.course:getWaypoint(ix)
	if wp and self.course:getNumberOfWaypoints() > 5 then 
		if wp:isRowEnd() then
			if self.course.waypoints[ix+1] then
				self.course:getWaypoint(ix+1):resetRowStartEnd()
			end
		elseif wp:isRowStart() then
			if self.course.waypoints[ix-1] then
				self.course:getWaypoint(ix-1):resetRowStartEnd()
			end
		end
		table.remove(self.course.waypoints, ix)
		return true
	end
end

--- Deletes waypoints in between.
function EditorCourseWrapper:deleteWaypointsBetween(firstIx, lastIx)
	for ix=lastIx-1, firstIx + 1, -1 do
		local wp = self.course:getWaypoint(ix)
		if wp then
			table.remove(self.course.waypoints, ix)
		end
	end
end

--- Deletes from waypoint to the last waypoint.
function EditorCourseWrapper:deleteToLastWaypoint(firstIx)
	if firstIx > 5 then
		for ix=self.course:getNumberOfWaypoints(), firstIx, -1 do
			local wp = self.course:getWaypoint(ix)
			if wp then
				table.remove(self.course.waypoints, ix)
			end
		end
		return true
	end
end

--- Changes the waypoint type between normal, turn start and turn end.
function EditorCourseWrapper:changeWaypointTurnType(ix)
	local wp = self.course:getWaypoint(ix)
	local np = self.course.waypoints[ix+1]
	local pp = self.course.waypoints[ix-1]
	if wp then 
		if wp:isRowEnd() then
			wp:resetRowStartEnd()
			if np then 
				np:resetRowStartEnd()
			end
		elseif wp:isRowStart() then
			wp:resetRowStartEnd()
			if pp then 
				pp:resetRowStartEnd()
			end
		elseif np and not np:isRowEnd() then
			wp:setRowEnd(true)
			np:setRowStart(true)
		else 
			return false
		end
	end
	return true
end

--- Gets the waypoint type (normal, turn start and turn end)
function EditorCourseWrapper:getWaypointType(ix)
	local wp = ix ~=nil and self.course:getWaypoint(ix)
	if wp then
		if wp:isRowEnd() then
			return CpBrushChangeTurnWP.TYPES.TURN_START
		elseif wp:isRowStart() then
			return CpBrushChangeTurnWP.TYPES.TURN_END
		else
			return CpBrushChangeTurnWP.TYPES.NORMAL
		end
	end
end

--- Changes the headland of a given waypoint.
function EditorCourseWrapper:changeHeadland(ix, n)
	local wp = ix ~=nil and self.course:getWaypoint(ix)
	if wp then
		if n == 0 then 
			wp:setHeadlandNumber(nil)
		else
			wp:setHeadlandNumber(n)
		end
	end
end

--- Sets the connecting track of a waypoint.
function EditorCourseWrapper:setConnectingPath(ix, set)
	local wp = ix ~=nil and self.course:getWaypoint(ix)
	if wp then
		wp:setOnConnectingPath(set)
	end
end

--- Set the row number.
function EditorCourseWrapper:getMaxRowNumber()
	local max = 0
	for i=1, self.course:getNumberOfWaypoints() do 
		local wp = self.course:getWaypoint(i)
		if wp and wp:getRowNumber() ~= nil then
			max = math.max(max, wp:getRowNumber())
		end
	end
	return max
end

--- Changes the row number of a given waypoint.
function EditorCourseWrapper:changeRowNumber(ix, n)
	local wp = ix ~=nil and self.course:getWaypoint(ix)
	if wp then
		if n == 0 then 
			wp:setRowNumber(nil)
		else 
			wp:setRowNumber(n)
		end
	end
end

--- Creates dynamic waypoint curves.
function EditorCourseWrapper:updateCurve(firstIx, lastIx, x, z)
	
	local wp = self.course:getWaypoint(firstIx)
	local np = self.course:getWaypoint(lastIx)

	if wp and np then 
		local dist = (MathUtil.vector2Length(np.x - x,np.z - z) + MathUtil.vector2Length(wp.x - x,wp.z - z))/2					 
		local dt = 1/(1.5*dist)	
		local points = {
			{
				wp.x,
				wp.z
			},
			{
				x,
				z
			},
			{
				np.x,
				np.z
			}
		}
		self:deleteWaypointsBetween(firstIx, lastIx)
		local i = firstIx
		for t=dt , 1, dt do 
			local dx, dz = CpMathUtil.de_casteljau(t, points)
			local p = self:insertWaypointBehind(i)
			p:setPosition(dx, dz)
			i = i + 1
		end
		return i + 1
	end
end