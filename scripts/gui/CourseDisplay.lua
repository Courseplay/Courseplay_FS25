--- Wrapper for a sign with the attached waypoint line.
---@class SimpleSign
SimpleSign = CpObject()
SimpleSign.TYPES = {
	NORMAL = 0,
	START = 1,
	STOP = 2
}
SimpleSign.COLORS = {
	NORMAL     = { 1.000, 0.212, 0.000, 1.000 }, -- orange
	TURN_START = { 0.200, 0.900, 0.000, 1.000 }, -- green
	TURN_END   = { 0.896, 0.000, 0.000, 1.000 }, -- red
	PATHFINDER = { 0.900, 0.000, 0.900, 1.000 }, -- purple
	HOVERED     = {0, 1, 1, 1.000 }, -- blue green
	SELECTED    = {1, 0, 1, 1.000 },  -- red blue
	NORMAL_LINE = {0, 1, 1, 1.000 },
	HEADLAND_LINE = {1, 0, 1, 1.000 },
	CONNECTING_LINE = {0, 0, 0, 0 } 
}
function SimpleSign:init(type, node, heightOffset, protoTypes)
	self.type = type
	self.node = node
	self.heightOffset = heightOffset
	self.protoTypes = protoTypes
end

--- Creates a new line prototype, which can be cloned.
function SimpleSign.new(type, filename,  heightOffset, protoTypes)
	local i3dNode =  g_i3DManager:loadSharedI3DFile( Courseplay.BASE_DIRECTORY .. 'img/signs/' .. filename .. '.i3d')
	local itemNode = getChildAt(i3dNode, 0)
	link(getRootNode(), itemNode)
	setRigidBodyType(itemNode, RigidBodyType.NONE)
	setTranslation(itemNode, 0, 0, 0)
	setVisibility(itemNode, true)
	delete(i3dNode)
	return SimpleSign(type, itemNode, heightOffset, protoTypes)
end

function SimpleSign:isStartSign()
	return self.type == self.TYPES.START
end

function SimpleSign:isStopSign()
	return self.type == self.TYPES.STOP
end

function SimpleSign:isNormalSign()
	return self.type == self.TYPES.NORMAL
end

function SimpleSign:getNode()
	return self.node	
end

function SimpleSign:getLineNode()
	return getChildAt(self.node, 0)
end

function SimpleSign:getHeight(x, z)
	local terrainHeight = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 300, z)
	return terrainHeight + self.heightOffset
end

function SimpleSign:translate(x, z)
	setTranslation(self.node, x, self:getHeight(x, z), z)
end

function SimpleSign:rotate(xRot, yRot)
	setRotation(self.node, xRot, yRot, 0)
end

function SimpleSign:setVisible(visible)
	setVisibility(self.node, visible)
end

function SimpleSign:clone(heightOffset)
	local newNode = clone(self.node, true)
	return SimpleSign(self.type, newNode, heightOffset or self.heightOffset)
end

function SimpleSign:setParent(newParent)
	unlink(self.node)
	link(newParent, self.node)
end

function SimpleSign:delete()
	CpUtil.destroyNode(self.node)
end

function SimpleSign:scaleLine(dist)
	local line = getChildAt(self.node, 0)
	if line ~= nil and line ~= 0 then
		setScale(line, 1, 1, dist)
	end
end

function SimpleSign:setBottomLineToGroundVisibility(visible)
	local line = getChildAt(self.node, 1)
	if line ~= nil and line ~= 0 then
		setVisibility(line, visible)
		setScale(line, 1, 1, 1.5 * self.heightOffset)
	end
end

function SimpleSign:setColor(color)
	self.color = color
	local x, y, z, w = unpack(color)
	setShaderParameter(self.node, 'shapeColor', x, y, z, w, false)
end

function SimpleSign:setLineColor(color)
	local line = getChildAt(self.node, 0)
	if line ~= nil and line ~= 0 and self.type ~= SimpleSign.TYPES.STOP then
		self:setBottomLineToGroundVisibility(color ~= nil)
		self.lineColor = color
		if color then 
			local x, y, z, w = unpack(color)
			setShaderParameter(line, 'shapeColor', x, y, z, w, false)
		end
	end
end

--- Applies the waypoint rotation and length to the next waypoint.
function SimpleSign:setWaypointData(wp, np)
	if wp ~=nil and np ~= nil then
		local y = self:getHeight(wp.x, wp.z)
		local ny = self:getHeight(np.x, np.z)
		local yRot, xRot, dist = 0, 0, 0
		dist = MathUtil.vector3Length(np.x - wp.x, ny - y, np.z - wp.z)
		if dist > 0 then
			local dx, dy, dz = MathUtil.vector3Normalize(np.x - wp.x, ny - y, np.z - wp.z)
			xRot = -math.sin((ny-y)/dist)
			yRot = MathUtil.getYRotationFromDirection(dx, dz)
		end	
		self:rotate(xRot, yRot)
		self:scaleLine(dist)
	end
end

--- Sign Prototyps, which can be cloned
SignPrototypes = CpObject()
SignPrototypes.HEIGHT_OFFSET = 4.5
function SignPrototypes:init(heightOffset)
	heightOffset = heightOffset or SignPrototypes.HEIGHT_OFFSET

	self.protoTypes = {
		NORMAL = SimpleSign.new(SimpleSign.TYPES.NORMAL, "normal", heightOffset, self),
		START = SimpleSign.new(SimpleSign.TYPES.START, "start", heightOffset, self),
		STOP = SimpleSign.new(SimpleSign.TYPES.STOP, "stop", heightOffset, self)
	}
	self.signs = {}
end

function SignPrototypes:getPrototypes()
	return self.protoTypes
end

function SignPrototypes:delete()
	for i, prototype in pairs(self.protoTypes) do 
		prototype:delete()
	end
end

g_signPrototypes = SignPrototypes()

--- Data Wrapper to display a course.
---@class CourseDataSourceDisplay
CourseDataSourceDisplay = CpObject()
CourseDataSourceDisplay.WAYPOINT_LOWER_LIMIT = 5 -- waypoints in front of the current
CourseDataSourceDisplay.WAYPOINT_UPPER_LIMIT = 20 -- waypoints after the current
function CourseDataSourceDisplay:init(course, wrapper)
	---@type Course
	self.course = course
	---@type EditorCourseWrapper
	self.courseWrapper = wrapper
end

function CourseDataSourceDisplay:getPoint(ix)
	return self.course:getWaypoint(ix)
end

function CourseDataSourceDisplay:getNumberOfPoints()
	return self.course:getNumberOfWaypoints()
end

function CourseDataSourceDisplay:getSignColors(i)
	local color, lineColor = SimpleSign.COLORS.NORMAL, nil
	if self.course:isTurnStartAtIx(i) then
		color = SimpleSign.COLORS.TURN_START
	elseif self.course:isTurnEndAtIx(i) then
		color = SimpleSign.COLORS.TURN_END
	elseif self.course:shouldUsePathfinderToNextWaypoint(i) or self.course:shouldUsePathfinderToThisWaypoint(i) then
		color = SimpleSign.COLORS.PATHFINDER
	end
	if self.courseWrapper then
		if self.courseWrapper:isSelected(i) then 
			color = SimpleSign.COLORS.SELECTED
		end
		if self.courseWrapper:isHovered(i) then 
			color = SimpleSign.COLORS.HOVERED 
		end
		lineColor = SimpleSign.COLORS.NORMAL_LINE 
		if self.courseWrapper:isHeadland(i) or self.courseWrapper:isOnRowNumber(i) then 
			lineColor = SimpleSign.COLORS.HEADLAND_LINE
		end
		if self.courseWrapper:isConnectingPath(i) then
			lineColor = SimpleSign.COLORS.CONNECTING_LINE
		end
	end
	return color, lineColor
end

---@param ix number
---@param onlyStartStopVisible boolean|nil only display the first and last point?
---@param onlyAroundCurrentWaypointVisible boolean|nil display waypoints around the current highlighted point?
---@return boolean visible
function CourseDataSourceDisplay:getIsPointVisible(ix, onlyStartStopVisible, onlyAroundCurrentWaypointVisible)
	local showWaypoint = true
	local currentWaypointIx = self.course:getCurrentWaypointIx()
	if onlyAroundCurrentWaypointVisible then
		--- Shows a few waypoints in front or after the last passed waypoint in between the lower and upper limit.
		local lowerBound = currentWaypointIx - self.WAYPOINT_LOWER_LIMIT
		local upperBound = currentWaypointIx + self.WAYPOINT_UPPER_LIMIT
		showWaypoint = lowerBound <= ix and ix <= upperBound
	end
	if onlyStartStopVisible then 
		showWaypoint =  ix == 1 or (ix <= self.course:getNumberOfWaypoints() and ix >= self.course:getNumberOfWaypoints())
	end
	return showWaypoint
end


--- A simple 3D course display without a buffer for a single course.
---@class SimpleCourseDisplay
SimpleCourseDisplay = CpObject()

SimpleCourseDisplay.HEIGHT_OFFSET = 4.5

function SimpleCourseDisplay:init()
	self.protoTypes = g_signPrototypes:getPrototypes()
	self.signs = {}
	self.rootNode = CpUtil.createNode("SimpleCourseDisplay rootNode", 0, 0, 0, getRootNode())
	self.dataSource = nil
	self:setVisible(false)
end

---@param courseWrapper EditorCourseWrapper
function SimpleCourseDisplay:setCourseWrapper(courseWrapper)
	self:setDataSource(CourseDataSourceDisplay(courseWrapper:getCourse(), courseWrapper))
end

---@param course Course
function SimpleCourseDisplay:setCourse(course)
	self:setDataSource(CourseDataSourceDisplay(course, nil))
end

function SimpleCourseDisplay:setVisible(visible)
	setVisibility(self.rootNode, visible)
end

function SimpleCourseDisplay:cloneSign(protoType)
	local sign = protoType:clone(self.HEIGHT_OFFSET)
	sign:setParent(self.rootNode)
	return sign
end

function SimpleCourseDisplay:setNormalSign(i)
	--- Selects the stop waypoint sign.
	if self.signs[i] == nil then
		self.signs[i] = self:cloneSign(self.protoTypes.NORMAL)
	elseif not self.signs[i]:isNormalSign() then 
		self:deleteSign(self.signs[i])
		self.signs[i] = self:cloneSign(self.protoTypes.NORMAL)
	end
end

--- Applies the waypoint data and the correct sign type.
function SimpleCourseDisplay:updateWaypoint(i)
	local wp = self.dataSource:getPoint(i)
	local np = self.dataSource:getPoint(i + 1)
	local pp = self.dataSource:getPoint(i - 1)
	if i == 1 then 
		--- Selects the start sign.
		if self.signs[i] == nil then
			self.signs[i] = self:cloneSign(self.protoTypes.START)
		elseif not self.signs[i]:isStartSign() then 
			self:deleteSign(self.signs[i])
			self.signs[i] = self:cloneSign(self.protoTypes.START)
		end
		self.signs[i]:setWaypointData(wp, np)
	elseif i == self.dataSource:getNumberOfPoints() then
		--- Selects the stop waypoint sign.
		if self.signs[i] == nil then
			self.signs[i] = self:cloneSign(self.protoTypes.STOP)
		elseif not self.signs[i]:isStopSign() then 
			self:deleteSign(self.signs[i])
			self.signs[i] = self:cloneSign(self.protoTypes.STOP)
		end
		self.signs[i]:setWaypointData(pp, wp)
	else 
		--- Selects the normal waypoint sign.
		self:setNormalSign(i)
		self.signs[i]:setWaypointData(wp, np)
	end
	self.signs[i]:translate(wp.x, wp.z)
	--- Changes the sign colors.
	local color, lineColor = self.dataSource:getSignColors(i)
	self.signs[i]:setColor(color)
	self.signs[i]:setLineColor(lineColor)
end

--- Sets a new course for the display.
---@param dataSource CourseDataSourceDisplay
function SimpleCourseDisplay:setDataSource(dataSource)
	self.dataSource = dataSource
	--- Removes signs that are not needed.
	for i = #self.signs, dataSource:getNumberOfPoints() + 1, -1 do 
		self.signs[i]:delete()
		table.remove(self.signs, i)
	end
	for i = 1, dataSource:getNumberOfPoints() do
		self:updateWaypoint(i)
	end
end

function SimpleCourseDisplay:clear()
	self.dataSource = nil
	self:deleteSigns()
end

--- Updates changes from ix or ix-1 onwards.
function SimpleCourseDisplay:updateChanges(ix)
	if not self.dataSource then 
		return
	end
	for i = #self.signs, self.dataSource:getNumberOfPoints() + 1, -1 do 
		self.signs[i]:delete()
		table.remove(self.signs, i)
	end
	ix = ix or 1
	if ix - 1 > 0 then 
		ix = ix - 1
	end
	for j = ix, self.dataSource:getNumberOfPoints() do
		self:updateWaypoint(j)
	end
end

--- Updates changes between waypoints.
---@param firstIx number
---@param secondIx number
function SimpleCourseDisplay:updateChangesBetween(firstIx, secondIx)
	for i = #self.signs, self.dataSource:getNumberOfPoints() + 1, -1 do 
		self.signs[i]:delete()
		table.remove(self.signs, i)
	end

	for j = math.max(1, firstIx-1), math.min(self.dataSource:getNumberOfPoints(), secondIx + 1) do
		self:updateWaypoint(j)
	end
end

--- Changes the visibility of the course.
---@param visible boolean|nil all points are visible
---@param onlyStartStopVisible boolean|nil only display the first and last point
---@param onlyAroundCurrentWaypointVisible boolean|nil display points around the current waypoint
function SimpleCourseDisplay:updateVisibility(visible, onlyStartStopVisible, onlyAroundCurrentWaypointVisible)
	if self.dataSource then
		local numWp = self.dataSource:getNumberOfPoints()
		for j = 1, numWp do
			if self.signs[j] then
				local isVisible = self.dataSource:getIsPointVisible(j, 
					onlyStartStopVisible, onlyAroundCurrentWaypointVisible)
				self.signs[j]:setVisible(visible or isVisible)
			end
		end
	end
end

function SimpleCourseDisplay:deleteSigns()
	for i, sign in pairs(self.signs) do 
		self:deleteSign(sign)
	end
	self.signs = {}
end

function SimpleCourseDisplay:deleteSign(sign)
	sign:delete()
end

function SimpleCourseDisplay:delete()
	self:deleteSigns()
	CpUtil.destroyNode(self.rootNode)
end

--- 3D course display with buffer
---@class BufferedCourseDisplay : SimpleCourseDisplay
BufferedCourseDisplay = CpObject(SimpleCourseDisplay)
BufferedCourseDisplay.buffer = {}
BufferedCourseDisplay.bufferMax = 10000

function BufferedCourseDisplay:setNormalSign(i)
	local function getNewSign()
		local sign
		if #BufferedCourseDisplay.buffer > 0 then 
			sign = BufferedCourseDisplay.buffer[1] 
			table.remove(BufferedCourseDisplay.buffer, 1)
			sign:setVisible(true)
			sign:setParent(self.rootNode)
		else
			sign = self:cloneSign(self.protoTypes.NORMAL)
		end
		return sign
	end
	if self.signs[i] == nil then
		self.signs[i] = getNewSign()
	elseif not self.signs[i]:isNormalSign() then 
		self.signs[i]:delete()
		self.signs[i] = getNewSign()
	end
end

function BufferedCourseDisplay:deleteSign(sign)
	if sign:isNormalSign() and #BufferedCourseDisplay.buffer < self.bufferMax then 
		sign:setVisible(false)
		sign:setParent(getRootNode())
		table.insert(BufferedCourseDisplay.buffer, sign)
	else 
		sign:delete()
	end
end

function BufferedCourseDisplay.deleteBuffer()
	for i, sign in pairs(BufferedCourseDisplay.buffer) do 
		sign:delete()
	end
end