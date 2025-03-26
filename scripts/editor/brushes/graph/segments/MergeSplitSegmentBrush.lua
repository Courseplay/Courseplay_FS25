--- Creates a new waypoint at the mouse position.
---@class MergeSplitSegmentBrush : GraphBrush
MergeSplitSegmentBrush = CpObject(GraphBrush)

function MergeSplitSegmentBrush:init(...)
	GraphBrush.init(self, ...)
	self.supportsPrimaryButton = true
    self.supportsPrimaryDragging = true
    self.supportsSecondaryButton = true
	return self
end

function MergeSplitSegmentBrush:onButtonPrimary(isDown, isDrag, isUp)
    local nodeId = self:getHoveredNodeId()	
    if isDown and not self.graphWrapper:hasSelectedNode() then
        if nodeId ~= nil then 
            local isNotFirstOrLast, err = self.graphWrapper:isNotFirstOrLastSegmentPoint(nodeId) 
            if isNotFirstOrLast then 
                self:setError(err)
                return
            end
            self.graphWrapper:setSelected(nodeId)
        end
    end
    if isUp and self.graphWrapper:hasSelectedNode() then 
        local selectedId = self.graphWrapper:getFirstSelectedNodeID()
        local success, err = self.graphWrapper:mergeSegments(nodeId, selectedId)
        if not success then 
            self:setError(err)
        end
        self.graphWrapper:resetSelected()
    end
end

function MergeSplitSegmentBrush:onButtonSecondary()
	local nodeId = self:getHoveredNodeId()	
	if nodeId ~= nil then 
        local success, err = self.graphWrapper:splitSegment(nodeId) 
        if not success then 
            self:setError(err)
            return
        end
	end
end

function MergeSplitSegmentBrush:getButtonPrimaryText()
	return self:getTranslation(self.primaryButtonText)
end

function MergeSplitSegmentBrush:getButtonSecondaryText()
	return self:getTranslation(self.secondaryButtonText)
end