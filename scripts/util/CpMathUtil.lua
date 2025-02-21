CpMathUtil = {}
function CpMathUtil.getIntersectionPoint(A1x, A1y, A2x, A2y, B1x, B1y, B2x, B2y) --@src: http://stackoverflow.com/questions/563198/how-do-you-detect-where-two-line-segments-intersect#comment19248344_1968345
	local s1_x, s1_y, s2_x, s2_y
	s1_x = A2x - A1x
	s1_y = A2y - A1y
	s2_x = B2x - B1x
	s2_y = B2y - B1y

	local s, t
	s = CpMathUtil.divide(-s1_y * (A1x - B1x) + s1_x * (A1y - B1y), -s2_x * s1_y + s1_x * s2_y)
	t = CpMathUtil.divide( s2_x * (A1y - B1y) - s2_y * (A1x - B1x), -s2_x * s1_y + s1_x * s2_y)

	if (s >= 0 and s <= 1 and t >= 0 and t <= 1) then
		--Collision detected
		local x = A1x + (t * s1_x)
		local z = A1y + (t * s1_y)
		return { x = x, z = z }
	end

	--No collision
	return nil
end

function CpMathUtil.getPointDirection(cp, np)
	local dx, dz = np.x - cp.x, np.z - cp.z
	local vl = MathUtil.vector2Length(dx, dz)
	if vl and vl > 0.0001 then
		dx = dx / vl
		dz = dz / vl
	end
	return dx, dz, vl
end

function CpMathUtil.getNodeDirection(node)
	local lx, _, lz = localDirectionToWorld(node, 0, 0, 1)
	return math.atan2( lx, lz )
end

--- Returns true if node1 is pointing approximately in node2's direction
---@param thresholdDeg number defines what 'approximately' means, by default if the difference is less than 5 degrees
function CpMathUtil.isSameDirection(node1, node2, thresholdDeg)
	local lx, _, lz = localDirectionToLocal(node1, node2, 0, 0, 1)
	-- TODO: double check this abs, this may return true also when the difference is around 180
	return math.abs(math.atan2(lx, lz)) < math.rad(thresholdDeg or 5)
end

--- Returns true if node1 is pointing approximately in opposite of node2's direction
---@param thresholdDeg number defines what 'approximately' means, by default if the difference is less than 5 degrees
function CpMathUtil.isOppositeDirection(node1, node2, thresholdDeg)
	local lx, _, lz = localDirectionToLocal(node1, node2, 0, 0, -1)
	-- TODO: double check this abs, this may return true also when the difference is around 180
	return math.abs(math.atan2(lx, lz)) < math.rad(thresholdDeg or 5)
end

--- Get a series of values, the first value is 'from', the last is 'to', and as many values as needed between the
--- two with a maximum of 'step' difference.
--- Always returns at least from and to
function CpMathUtil.getSeries(from, to, step)
	local nValues = math.max(1, math.floor(math.abs((from - to) / step)))
	local delta = (to - from) / nValues
	local value = from
	local series = {}
	for i = 0, nValues do
		table.insert(series, value + i * delta)
	end
	return series
end

-- POINT IN POLYGON (Jordan method) -- @src: http://de.wikipedia.org/wiki/Punkt-in-Polygon-Test_nach_Jordan
-- returns:
--	 1	point is inside of polygon
--	-1	point is outside of polygon
--	 0	point is directly on polygon
function CpMathUtil.isPointInPolygon(polygon, x, z)
	if polygon == nil or #polygon <= 2 then 
		CpUtil.error("CpMathUtil.isPointInPolygon(): polygon is too small or nil!")
		return false
	end
	if x == nil or z == nil then 
		CpUtil.error("CpMathUtil.isPointInPolygon(): x or z are nil!")
		return false
	end

	local function crossProductQuery(a, b, c)
		-- returns:
		--	-1	vector from A to right intersects BC (except at the bottom end point)
		--	 0	A is directly on BC
		--	 1	all else

		if a.z == b.z and b.z == c.z then
			if (b.x <= a.x and a.x <= c.x) or (c.x <= a.x and a.x <= b.x) then
				return 0
			else
				return 1
			end
		end

		if b.z > c.z then b, c = c, b end
		if a.z == b.z and a.x == b.x then return 0 end
		if a.z <= b.z or a.z > c.z then return 1 end

		local delta = (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x)

		if delta > 0 then return -1 end
		if delta < 0 then return 1 end
		return 0
	end

	local cp, np, pp
	local pointInPolygon = -1

	for i = 1, #polygon do
		cp = polygon[i]
		np = i < #polygon and polygon[i + 1] or polygon[1]
		pp = i > 1 and polygon[i - 1] or polygon[#polygon]

		pointInPolygon = pointInPolygon * crossProductQuery({ x = x, z = z }, cp, np)
		if pointInPolygon == 0 then
			-- point directly on the edge is considered being in the polygon
			return true
		end
	end

	return pointInPolygon ~= -1
end

--- Is a point within a certain distance to any of the edges of a polygon. Note that this is not accurate
--- around the vertices for performance reasons. If scalar projection of the point is outside of the segment,
--- but the scalar projection is within the limit, it is still considered within the distance. The accurate
--- version would be checking if the point is within the half circle around the end vertices.
---@param polygon [{x, z}]
---@param x number x coordinate of the point
---@param z number z coordinate of the point
---@param distance number distance in meters
---@return boolean true if the point is within the distance to any of the edges
---@return number the distance to the closest edge
function CpMathUtil.isWithinDistanceToPolygon(polygon, x, z, distance)
	if polygon == nil or #polygon <= 2 then 
		CpUtil.error("CpMathUtil.isWithinDistanceToPolygon(): polygon is too small or nil!")
		return false, math.huge
	end
	local closestDistance = math.huge
	local point = Vector(x, -z)
	for i = 1, #polygon do
		local s, e = polygon[i], polygon[i + 1] or polygon[1]
		local edge = CourseGenerator.LineSegment(s.x, -s.z, e.x, -e.z)
		local d = edge:getDistanceFrom(point)
		-- d is distance from the line defined by the line segment, could be anywhere from -infinity to +infinity
		local scalarProjection = edge:getScalarProjection(point)
		-- so make sure it is around the segment
		if scalarProjection >= -distance and scalarProjection <= edge:getLength() + distance then
			closestDistance = d < closestDistance and d or closestDistance
			if closestDistance <= distance then
				return true, closestDistance
			end
		end
	end
	return false, closestDistance
end


--- Get the area of polygon in square meters
---@param polygon [] array elements can be {x, z}, {x, y, z} or {x, y}
function CpMathUtil.getAreaOfPolygon(polygon)
	local area = 0
	for i = 1, #polygon - 1 do
		local x1, y1 = polygon[i].x, polygon[i].z and -polygon[i].z or polygon[i].y
		local x2, y2 = polygon[i + 1].x, polygon[i + 1].z and -polygon[i + 1].z or polygon[i + 1].y
		area = area + (x2 - x1) * (y1 + y2) / 2
	end
	return math.abs(area)
end

--- Get the circumference of a polygon in meters (the class Polygon has its own calculation, this is to be
--- used for a very generic case with polygons in game or normal coordinate systems)
---@param polygon [] array elements can be {x, z}, {x, y, z} or {x, y}
function CpMathUtil.getCircumferenceOfPolygon(polygon)
	local circumference = 0
	for i = 1, #polygon - 1 do
		local x1, y1 = polygon[i].x, polygon[i].z and -polygon[i].z or polygon[i].y
		local x2, y2 = polygon[i + 1].x, polygon[i + 1].z and -polygon[i + 1].z or polygon[i + 1].y
		local dx, dy  = x2 - x1, y2 - y1
		circumference = circumference + math.sqrt(dx * dx + dy * dy)
	end
	return circumference
end


--- De-Casteljau algorithm for bezier curves.
--- https://en.wikipedia.org/wiki/De_Casteljau%27s_algorithm
function CpMathUtil.de_casteljau(t, points)
--[[
	for i = 1, #points do
		for j = 1, #points-i do
			points[j] = {
				points[j][1] * (1-t) + points[j+1][1] * t,
				points[j][2] * (1-t) + points[j+1][2] * t,
			}
		end
	end
	return points[1][1], points[1][2]
	]]
	local q0_x, q0_y = (1-t) * points[1][1] + t * points[2][1],
					(1-t) * points[1][2] + t * points[2][2]
	local q1_x, q1_y = (1-t) * points[2][1] + t * points[3][1],
					(1-t) * points[2][2] + t * points[3][2]
	
	return (1-t)*q0_x + t*q1_x, (1-t)*q0_y + t*q1_y
end


local function normalizeAngle( a )
	return a >= 0 and a or 2 * math.pi + a
end

function CpMathUtil.getDeltaAngle(a, b)
	-- convert the 0 - -180 range into 180 - 360
	if math.abs( a - b ) > math.pi then
		a = normalizeAngle( a )
		b = normalizeAngle( b )
	end
	-- calculate difference in this range
	return b - a
end

--- Get the average of two angles.
-- Works fine even for the transition from -pi/2 to +pi/2
function CpMathUtil.getAverageAngle( a1, a2 )
	-- convert the 0 - -180 range into 180 - 360
	if math.abs( a1 - a2 ) > math.pi then
		a1 = normalizeAngle( a1 )
		a2 = normalizeAngle( a2 )
	end
	-- calculate average in this range
	local avg = ( a1 + a2 ) / 2
	-- convert back to 0 - -180 if necessary
	if avg > math.pi then avg = avg - 2 * math.pi end
	return avg
end


------------------------------------------------------------------------------------------------------------------------
--- Transform coordinates between the game and the coordinate system used by the
--- course generator and the pathfinder.
---
--- The course generator and the pathfinder work in the X/Y plane of a left-handed coordinate system as known
--- from the school. This is because both can be developed and tested in a standalone configuration, without
--- the game running, and it is just easier to think in the familiar left-handed X/Y system.
---
--- The game's ground plane (where the courses are generated and the path must be found) is the X/Z plane of a
--- right-handed coordinate system. The price to be paid for the convenience of the familiar left-handed X/Y
--- system is that we need to transform between the two systems.
---
--- One could implement the transformation as part of the geometry class constructors and the Course class
--- so they accept vertices in both systems, but I think it is much cleaner to make these transformations
--- explicit.
------------------------------------------------------------------------------------------------------------------------
function CpMathUtil.pointsFromGame(points)
	local result = {}
	for _, point in ipairs(points) do
		table.insert(result, { x = point.x, y = -point.z })
	end
	return result
end

function CpMathUtil.pointsToGame(points)
	local result = {}
	for _, point in ipairs(points) do
		table.insert(result, { x = point.x, z = -point.y })
	end
	return result
end

--- Convert an array of points from x/y to x/z in place (also keeping other attributes)
function CpMathUtil.pointsToGameInPlace(points)
	for _, point in ipairs(points) do
		point.z = -point.y
		-- wipe y as it is a different coordinate in this system
		point.y = nil
	end
	return points
end

--- Convert an array of points from x/z to x/y in place (also keeping other attributes)
function CpMathUtil.pointsFromGameInPlace(points)
	for _, point in ipairs(points) do
		point.y = -point.z
		point.z = nil
	end
	return points
end

function CpMathUtil.pointFromGame(point)
	return ({ x = point.x or point.cx, y = -(point.z or point.cz) })
end

function CpMathUtil.pointToGame(point)
	return ({ x = point.x, z = -point.y })
end

--- Convert the game angle in the RH X/Z plane (measured from the x axis up in radians)
--- to the LH X/Y plane
function CpMathUtil.angleToGameDeg(angle)
	local a = math.deg(angle) + 90
	if a > 180 then
		a = a - 360
	end
	return a
end

function CpMathUtil.angleToGame(angle)
	local a = angle + math.pi / 2
	if a > math.pi then
		a = a - 2 * math.pi
	end
	return a
end

--- Convert the game angle in the LH X/Y plane
--- to the RH X/Z plane
function CpMathUtil.angleFromGameDeg(angleDeg)
	local a = angleDeg - 90
	if a < 0 then
		a = 360 + a
	end
	return math.rad(a)
end

function CpMathUtil.angleFromGame(angle)
	local a = angle - math.pi / 2
	if a < 0 then
		a = 2 * math.pi + a
	end
	return a
end

-- TODO: consider math.clamp instead, that is part of Luau
function CpMathUtil.clamp(val, min, max)
	return math.min(math.max(val, min), max)
end

--- Divide a by b, but instead of throwing an error when b is 0, return math.huge
function CpMathUtil.divide(a, b)
	return b == 0 and math.huge or a / b
end

--- Legancy function form LS22
function CpMathUtil.getCircleLineIntersection(circleX, circleZ, radius, lineStartX, lineStartZ, lineEndX, lineEndZ)
	local p3x = lineStartX - circleX
	local p3z = lineStartZ - circleZ
	local p4x = lineEndX - circleX
	local p4z = lineEndZ - circleZ
	local m = (p4z - p3z) / (p4x - p3x)
	local b = p3z - m * p3x
	local dis = math.pow(radius, 2) * math.pow(m, 2) + math.pow(radius, 2) - math.pow(b, 2)

	if dis < 0 then
		return false
	else
		local t1 = (-m * b + math.sqrt(dis)) / (math.pow(m, 2) + 1)
		local t2 = (-m * b - math.sqrt(dis)) / (math.pow(m, 2) + 1)
		local intersect1X = t1 + circleX
		local intersect1Z = m * t1 + b + circleZ
		local intersect2X = t2 + circleX
		local intersect2Z = m * t2 + b + circleZ

		return true, intersect1X, intersect1Z, intersect2X, intersect2Z
	end
end
