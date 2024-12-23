--- Draws an unloading triggers as a X Symbol on the in game menu map.
---@class UnloadingTriggerPlot 
UnloadingTriggerPlot = CpObject()

function UnloadingTriggerPlot:init(node)
	self.courseOverlayId = createImageOverlay('dataS/menu/base/graph_pixel.dds')
	self.isVisible = false
	-- the normal FS22 blue -- 0.9900 0.4640 0.0010 1
	--self.color = {CpGuiUtil.getNormalizedRgb(42, 193, 237)}
	self.color = {CpGuiUtil.getNormalizedRgb(255, 128, 0)}
	-- a lighter shade of the same color
	self.lightColor = {CpGuiUtil.getNormalizedRgb(213, 255, 0)}
	-- a darker shade of the same color
	self.darkColor = {CpGuiUtil.getNormalizedRgb(19, 87, 107)}
	self.lineThickness = 4 / g_screenHeight -- 4 pixels
	self.isHighlighted = false
	local _
	self.x, _, self.z = getWorldTranslation(node)
end

function UnloadingTriggerPlot:draw(map)
	local r, g, b = unpack(self.color)
	if self.isHighlighted then 
		r, g, b = unpack(self.lightColor)
	end
	setOverlayColor( self.courseOverlayId, r, g, b, 0.8 )
	-- local x, y = CpGuiUtil.worldToScreen(map, self.x, self.z, false)

	local s1x, s1y = CpGuiUtil.worldToScreen(map, self.x - 5, self.z - 5, false)
	local e1x, e1y = CpGuiUtil.worldToScreen(map, self.x + 5, self.z + 5, false)
	local s2x, s2y = CpGuiUtil.worldToScreen(map, self.x + 5, self.z - 5, false)
	local e2x, e2y = CpGuiUtil.worldToScreen(map, self.x - 5, self.z + 5, false)

	--- Create a coss through the node position
	local mapRotation = map.layout:getMapRotation()
	local dx2D = e1x - s1x
	local dy2D = ( e1y - s1y ) / g_screenAspectRatio
	local width = MathUtil.vector2Length(dx2D, dy2D)
	local rotation = MathUtil.getYRotationFromDirection(10, 10) - math.pi * 0.5 + mapRotation
	setOverlayRotation( self.courseOverlayId, rotation, 0, 0 )
	renderOverlay( self.courseOverlayId, s1x, s1y, width, self.lineThickness )

	dx2D = e2x - s2x
	dy2D = ( e2y - s2y ) / g_screenAspectRatio
	width = MathUtil.vector2Length(dx2D, dy2D)
	rotation = MathUtil.getYRotationFromDirection(-10, 10) - math.pi * 0.5 + mapRotation
	setOverlayRotation( self.courseOverlayId, rotation, 0, 0 )
	renderOverlay( self.courseOverlayId, s2x, s2y, width, self.lineThickness )
end

function UnloadingTriggerPlot:setHighlighted(highlighted)
	self.isHighlighted = highlighted
end