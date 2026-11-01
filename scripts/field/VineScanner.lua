--- This scanner is used to detect continues orchard fields.
--- Every line has to have the same direction.
--- This means all vine placements need to be placed with the a snapping angle.
--- The output is a field boundary of the vine nodes for the course generator.
---@class VineScanner 
VineScanner = CpObject()
function VineScanner:init(maxStartDistance)
	self.maxStartDistance = maxStartDistance or 10
	self.debugChannel = CpDebug.DBG_COURSES
end

function VineScanner:setup()
	self.vineSystem = g_currentMission.vineSystem
	self.orchardRows = {}
end

function VineScanner:foundVines()
	return self.lines and next(self.lines) ~= nil
end

--- Is there a vine node close to point?
function VineScanner:hasVineNodesCloseBy(tx, tz)
	local x, _, z
	local closestDist, dist = math.huge, 0
	--- Finds the closest vine node on a field to the start point.
	for node, _ in pairs(self.vineSystem.nodes) do 
		x, _, z = getWorldTranslation(node)
		dist = MathUtil.vector2Length(x-tx, z-tz)
		if dist < closestDist then 
			closestDist = dist
		end
	end
	return closestDist <= self.maxStartDistance
end

--- Checks if any vine nodes are close to the first waypoint.
---@param vertices table
---@param tx number
---@param tz number
---@param isCustomField boolean
---@return boolean found vine nodes
---@return table|nil all vine segments
---@return table|nil closest segment
---@return table|nil closest vine node
---@return Placeable|nil closest placeable
function VineScanner:getVineNodesOnField(vertices, tx, tz, isCustomField)
	self.orchardRows = {}
	if vertices == nil or next(vertices) == nil or tx == nil or tz == nil then 
		self.lines = nil
		self.width = nil
		return false
	end
	--- Makes sure the custom field border is a closed polygon.
	--- Not sure if that is needed.
	if isCustomField then 
		table.insert(vertices, vertices[1])
	end
	local vineSegments = {}
	local x, _, z
	local closestSegment, closestDist, dist = nil, math.huge, 0
	local segment, closestNode, closestPlaceable
	--- Finds the closest vine node on a field to the start point.
	for node, placeable in pairs(self.vineSystem.nodes) do 
		x, _, z = getWorldTranslation(node)
		if CpMathUtil.isPointInPolygon(vertices, x, z) then 
			local placeableSegments = self:getVineSegmentsAndWidth(placeable)
			segment = placeableSegments and self:getVineSegmentIxForNode(node, placeableSegments)
			if segment then
				table.insert(vineSegments, segment)
				dist = MathUtil.vector2Length(x-tx, z-tz)
				if dist < closestDist then
					closestSegment = segment
					closestPlaceable = placeable
					closestNode = node
					closestDist = dist
				end
			end
		end
	end
	if not closestSegment then 
		self.lines = nil
		self.width = nil
		self:debug("No vine node found nearby!")
		return false
	end
	self:debug("Found a vine node within %.2fm", closestDist)
	return true, vineSegments, closestSegment, closestNode, closestPlaceable
end

--- Finds vine nodes on a field and creates lines of them.
---@param vertices table
---@param tx number start point
---@param tz number start point
---@param isCustomField boolean
---@return boolean vine nodes found
function VineScanner:findVineNodesInField(vertices, tx, tz, isCustomField)

	local isValid, vineSegments, closestSegment, closestNode, closestPlaceable = self:getVineNodesOnField(vertices, tx, tz, isCustomField)

	if not isValid then 
		return false
	end
	--- Only use vine segments with the same directions, as the closest segment found.
	local dirX, dirZ = MathUtil.vector2Normalize(closestSegment.x2 - closestSegment.x1, closestSegment.z2 - closestSegment.z1)
	local xa, za, xb, zb, dx, dz
	local segments = {}
	for _, segment in pairs(vineSegments) do 
		xa, za = segment.x1, segment.z1
		xb, zb = segment.x2, segment.z2
		dx, dz = MathUtil.vector2Normalize(xb - xa, zb - za)
		if self:equalDirection(dx, dirX, dz, dirZ) then 
			table.insert(segments, segment)
		end
	end
	--- Separate the segments into lines.
	local left, right = self:separateIntoColumns(segments, closestNode)

	local lines = {}
	--- Combine the found lines to the left and right into one table.
	for i = #left, 1, -1 do 
		table.insert(lines, left[i])
	end

	for _, s in ipairs(right) do 
		table.insert(lines, s)
	end

	if #lines <= 0 then 
		self:debug("No lines could ne found!")
		return false
	end
 
	local newLines = {}
	for i, l in ipairs(lines) do
		table.insert(newLines, self:getStartEndPointForLine(l))
	end

	--- Makes sure the closest line is near the starting point, which should be lines[1].x1/z1
	local dist1 = MathUtil.vector2Length(newLines[1].x1-tx, newLines[1].z1-tz)
	local dist2 = MathUtil.vector2Length(newLines[1].x2-tx, newLines[1].z2-tz)
	local dist3 = MathUtil.vector2Length(newLines[#newLines].x1-tx, newLines[#newLines].z1-tz)
	local dist4 = MathUtil.vector2Length(newLines[#newLines].x2-tx, newLines[#newLines].z2-tz)

	if dist2 < dist1 and dist2 < dist3 and dist2 < dist4 then 
		newLines = self:invertLinesStartAndEnd(newLines)
	elseif dist3 < dist1 and dist3 < dist2 and dist3 < dist4 then
		newLines = self:invertLinesTable(newLines)
	elseif dist4 < dist1 and dist4 < dist2 and dist4 < dist3 then
		newLines = self:invertLinesTable(newLines)
		newLines = self:invertLinesStartAndEnd(newLines)
	end


	self.lines = newLines
	local _, width = self:getVineSegmentsAndWidth(closestPlaceable)
	self.width = width

	self:debug("Found %d number of lines for a width of %.2f", #self.lines, self.width)

	return true
end

--- Invert's the lines from end(lines.x2/z2) -> start(lines.x1/z1)
---@param lines table
---@return table
function VineScanner:invertLinesStartAndEnd(lines)
	local newLines = {}
	for i, l in ipairs(lines) do 
		table.insert(newLines, {
			x1 = l.x2,
			z1 = l.z2,
			x2 = l.x1,
			z2 = l.z1,
		})
	end
	return newLines
end

--- Invert's the lines from right(#lines) -> left(lines[1])
---@param lines table
---@return table
function VineScanner:invertLinesTable(lines)
	local newLines = {}
	for i = #lines, 1, -1 do 
		table.insert(newLines, lines[i])
	end
	return newLines
end


--- Separate segments relative to the closest segment into left columns(0->x) and right columns(1->-x).
---@param lines table
---@param closestNode node
---@return table left lines 
---@return table right lines
function VineScanner:separateIntoColumns(lines, closestNode)
	local placeable = self.vineSystem.nodes[closestNode]
	local _, width = self:getVineSegmentsAndWidth(placeable)
	local columnsLeft = {}
	local columnsRight = {}
	--- Left columns 
	local ix = 1
	local maxIterations = 500
	while ix < maxIterations do
		local nx = (ix-1)*width
		local x, _, z = localToWorld(closestNode, nx, 0, 0) 
		local foundVine = false
		for i, line in pairs(lines) do 
			if MathUtil.getCircleLineIntersection(x, z, 0.1,  line.x1, line.z1, line.x2, line.z2) then
				if columnsLeft[ix] == nil then 
					columnsLeft[ix] = {}
				end
				table.insert(columnsLeft[ix], line)
				foundVine = true
			end
		end
		if not foundVine then 
			break
		end
		ix = ix + 1
	end
	self:debug("Found %d columns to the left.", #columnsLeft)
	--- Right columns 
	ix = 1
	local maxIterations = 500
	while ix < maxIterations do
		local nx = ix*(-width)
		local x, _, z = localToWorld(closestNode, nx, 0, 0) 	
		local foundVine = false
		for i, line in pairs(lines) do 
			if MathUtil.getCircleLineIntersection(x, z, 0.1,  line.x1, line.z1, line.x2, line.z2) then
				if columnsRight[ix] == nil then 
					columnsRight[ix] = {}
				end
				table.insert(columnsRight[ix], line)
				foundVine = true
			end
		end
		if not foundVine then 
			break
		end
		ix = ix + 1
	end
	self:debug("Found %d columns to the right.", #columnsRight)
	return columnsLeft, columnsRight
end



--- Are the directions equal ?
function VineScanner:equalDirection(dx, nx, dz, nz)
	return MathUtil.equalEpsilon(nx, dx, 0.01) and MathUtil.equalEpsilon(nz, dz, 0.01) or
		   MathUtil.equalEpsilon(nx, -dx, 0.01) and MathUtil.equalEpsilon(nz, -dz, 0.01)
end

--- Combines the segments on the same line and return a combined segment.
--- TODO: Is not working for field like these: 
--[[
	| | | |     | | | |
	| |		=>  | | | |
	| |			| | | |
	| |	|		| | | |
	| | | |		| | | |
]]			
---@param segments table all the line segments sorted into columns form left -> right.
---@return table lines from left -> right, but only complete lines.
function VineScanner:getStartEndPointForLine(segments)
	local points = {}
	local xa, za, xb, zb
	for _, segment in pairs(segments) do 
		xa, za = segment.x1, segment.z1
		xb, zb = segment.x2, segment.z2	
		table.insert(points, {x = xa, z = za})
		table.insert(points, {x = xb, z = zb})
	end
	if #points > 0 then 
		table.sort(points, function (a, b)
			if a.x ~= b.x then 
				return a.x < b.x
			else 
				return a.z < b.z
			end
		end)
		return {x1 = points[1].x, 
				x2 = points[#points].x, 
				z1 = points[1].z, 
				z2 = points[#points].z, 
				}
	end
end

--- Debug function to draw the vine segments.
function VineScanner:drawSegments(segments)
	if segments then 
		local blueScale = 1/#segments
		for i, segment in ipairs(segments) do 
			local x1, x2, z1, z2 = segment.x1, segment.x2, segment.z1, segment.z2
			local y1, y2 = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x1, 0, z1), getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x2, 0, z2)
			drawDebugLine(x1, y1 + 2, z1, 1, 0, i*blueScale, x2, y2 + 2, z2, 0, 1, i*blueScale)
		end
	end
end

--- Creates a field boundary relative to the size of the vine field,
--- so the course generator can generate courses for these.
---@param vineOffset number should the driver driver beside or over the vines. (-1/0/1)
---@param tx number field position x
---@param tz number field position z
---@return table|nil field boundary
---@return number|nil width between the vine nodes.
---@return table|nil starting point for the generator
---@return number|nil angle of the vine rows(degree)
function VineScanner:getCourseGeneratorVertices(vineOffset, tx, tz)
	if not self.lines then 
		return 
	end
	vineOffset = -vineOffset * self.width/2
	self:debug("vineOffset: %f", vineOffset)
	local dirX, dirZ, _ = CpMathUtil.getPointDirection({x = self.lines[1].x1, z = self.lines[1].z1}, {x = self.lines[1].x2, z = self.lines[1].z2})
	local yRot = 0	
	if dirX == dirX or dirZ == dirZ then
		yRot = MathUtil.getYRotationFromDirection(dirX, dirZ)
	end
	local node = createTransformGroup("temp")

	setRotation(node, 0, yRot, 0)

	local x1, z1 = self.lines[1].x1, self.lines[1].z1
	local dirX1, dirZ1 = self.lines[1].x1-self.lines[1].x2, self.lines[1].z1-self.lines[1].z2
	local dirX2, dirZ2 = self.lines[1].x1-self.lines[#self.lines].x1, self.lines[1].z1-self.lines[#self.lines].z1
	setTranslation(node, self.lines[1].x1, 0,  self.lines[1].z1)
	local x, _, z = localToWorld(node, - self.width/2, 0, 0)
	setTranslation(node, self.lines[1].x2, 0,  self.lines[1].z2)
	local dx, _, dz = localToWorld(node, - self.width/2, 0, 0)
	local inverted = 1
	--- Makes sure the the outer offset is correct and not inverse. 
	if MathUtil.hasRectangleLineIntersection2D(x1, z1, dirX1, dirZ1, dirX2, dirZ2, x, z, x-dx, z-dz) then 
		inverted = -1
	end

	local lines = {}
	local x, _, z = localToWorld(node, - self.width/2, 0, 0)
	--- Applies offset for vehicles, that need to be driving next to the vine rows.
	for i=#self.lines, 1, -1 do 
		setTranslation(node, self.lines[i].x1, 0,  self.lines[i].z1)
		if i == 1 then 
			x, _, z = localToWorld(node, vineOffset + inverted * self.width/2, 0, 0)
			table.insert(lines, {
				x = x,
				z = z,
			})
			--- Inserts a few point in between the long edge for the course generator.
			local dx, dz, length = CpMathUtil.getPointDirection({x = self.lines[i].x1, z = self.lines[i].z1}, {x = self.lines[i].x2, z = self.lines[i].z2})
			for j=2, length-2 do 
				table.insert(lines, {
					x = x + dx * j,
					z = z + dz * j,
				})
			end

		elseif i == #self.lines then 
			x, _, z = localToWorld(node, vineOffset - inverted * self.width/2, 0, 0)
			table.insert(lines, {
				x = x,
				z = z,
			})
		else	
			x, _, z = localToWorld(node, vineOffset, 0, 0)
			table.insert(lines, {
				x = x,
				z = z,
			})
		end
	end
	for i=1, #self.lines do 
		setTranslation(node, self.lines[i].x2, 0,  self.lines[i].z2)
		if i == 1 then 
			x, _, z = localToWorld(node, vineOffset + inverted * self.width/2, 0, 0)
			table.insert(lines, {
				x = x,
				z = z,
			})
		elseif i == #self.lines then 
			x, _, z = localToWorld(node, vineOffset - inverted * self.width/2, 0, 0)
			table.insert(lines, {
				x = x,
				z = z,
			})
			--- Inserts a few point in between the long edge for the course generator.
			local dx, dz, length = CpMathUtil.getPointDirection({x = self.lines[i].x2, z = self.lines[i].z2}, {x = self.lines[i].x1, z = self.lines[i].z1})
			for j=2, length-2 do 
				table.insert(lines, {
					x = x + dx * j,
					z = z + dz * j,
				})
			end
		else	
			x, _, z = localToWorld(node, vineOffset, 0, 0)
			table.insert(lines, {
				x = x,
				z = z,
			})
		end
	end
	table.insert(lines, lines[1])
	CpUtil.destroyNode(node)
	--- For debugging
	self.fieldBorder = lines
	return lines, self.width, lines[1], -math.deg(yRot)
end

function VineScanner:getLines()
	return self.lines
end

--- Gets the vine segments and the row spacing of a placeable in the vine system.
--- The coffee plantation of the Beans & Alpacas DLC has no spec_vine, its fence segments
--- hold the vine nodes and the spacing comes from getOrchardRowSpacing().
--- These are converted into the spec_vine layout once per scan.
---@param placeable table
---@return table|nil vine segments
---@return number|nil row spacing
function VineScanner:getVineSegmentsAndWidth(placeable)
	if placeable.spec_vine then
		return placeable.spec_vine.vineSegments, placeable.spec_vine.width
	end
	self.orchardRows = self.orchardRows or {}
	local rows = self.orchardRows[placeable]
	if rows == nil then
		rows = {}
		self.orchardRows[placeable] = rows
		local fence = placeable.getFence and placeable:getFence()
		local width = placeable.getOrchardRowSpacing and placeable:getOrchardRowSpacing()
		if fence == nil or type(fence.segments) ~= "table" or type(width) ~= "number" or width <= 0 then
			self:debug("Placeable of type %s in the vine system has no vine rows, ignoring it.", tostring(placeable.typeName))
			return
		end
		local vineSegments = {}
		for _, fenceSegment in ipairs(fence.segments) do
			if fenceSegment.vineNodes and fenceSegment.getStartPos and fenceSegment.getEndPos then
				local x1, _, z1 = fenceSegment:getStartPos()
				local x2, _, z2 = fenceSegment:getEndPos()
				if x1 and z1 and x2 and z2 then
					local nodes = {}
					for node, _ in pairs(fenceSegment.vineNodes) do
						table.insert(nodes, {node = node})
					end
					vineSegments[{x1 = x1, z1 = z1, x2 = x2, z2 = z2}] = nodes
				end
			end
		end
		rows.vineSegments = vineSegments
		rows.width = width
	end
	return rows.vineSegments, rows.width
end

--- Gets a segment for a vine node.
function VineScanner:getVineSegmentIxForNode(node, vineSegments)
	for segment, nodes in pairs(vineSegments) do 
		for i, data in pairs(nodes) do 
			if data.node == node then 
				return segment
			end
		end
	end
end

function VineScanner:debug(...)
	CpUtil.debugVehicle(CpDebug.DBG_COURSES, CpUtil.getCurrentVehicle(), 'VineScanner: ' .. string.format(...))
end

function VineScanner:debugSparse(...)
	if g_updateLoopIndex % 100 == 0 then
        self:debug(...)
    end
end

function VineScanner:draw()
	if CpUtil.getCurrentVehicle() and CpDebug:isChannelActive(CpDebug.DBG_COURSES, CpUtil.getCurrentVehicle()) and self:foundVines() then
		self:drawSegments(self.lines)
		self:drawFieldBorder()
	end
end

function VineScanner:drawFieldBorder()
	if self.fieldBorder then 
		local step = 1/(#self.fieldBorder -1)
		for i = 1, #self.fieldBorder-1 do 
			local x1, z1 = self.fieldBorder[i].x,  self.fieldBorder[i].z
			local x2, z2 = self.fieldBorder[i+1].x, self.fieldBorder[i+1].z
			local y1, y2 = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x1, 0, z1), getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x2, 0, z2)
			drawDebugLine(x1, y1 + 2, z1, 1, 1, (i-1)*step, x2, y2 + 2, z2, 1, 1, i*step)
		end
	end
end

g_vineScanner = VineScanner()