---@class GraphPlot : CoursePlot
GraphPlot = CpObject(CoursePlot)
function GraphPlot:init(graph)
	CoursePlot.init(self)
	self:setDrawingArrows(true)
	-- use a thicker line
    self.isVisible = true
	---@type Graph
    self.graph = graph
end

--- Draws custom fields.
---@param map table
function GraphPlot:draw(map)
	if not self.isVisible then return end
    local segments = self.graph:getSegments()
    for _, segment in pairs(segments) do 
        local points = segment:getAllChildNodes()
		self.darkColor = segment:getDirectionColor()
		self:setDrawingArrows(not segment:isDual(), segment:isReverse())
        self:drawPoints(map, points, false)
    end
end

