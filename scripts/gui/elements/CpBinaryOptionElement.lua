CpBinaryOptionElement = {}
local CpBinaryOptionElement_mt = Class(CpBinaryOptionElement, BinaryOptionElement)

function CpBinaryOptionElement.new(target, custom_mt)
	local self = BinaryOptionElement.new(target, custom_mt or CpBinaryOptionElement_mt)
	self.dataSource = nil
	self.toolTipElement = nil
	return self
end

-- Lines 19-23
function CpBinaryOptionElement:delete()
	self.dataSource = nil

	CpBinaryOptionElement:superClass().delete(self)
end

-- Lines 25-28
function CpBinaryOptionElement:setDataSource(dataSource)
	self.dataSource = dataSource

	self:updateTitle()
end


function CpBinaryOptionElement:addElement(element, ...)
	CpBinaryOptionElement:superClass().addElement(self, element, ...)
	-- if self.textElement then
	-- 	self.textElement.forceHighlight = true
	-- 	self.textElement:setHandleFocus(false)
	-- 	self.textElement.target = self
	-- 	self.textElement:setCallback("onClickCallback", "onCenterButtonClicked")
	-- end
	if element.name == "tooltip" then
		self.toolTipElement = element
	end
end

-- Lines 30-33
function CpBinaryOptionElement:updateTitle()
	if self.dataSource:getValue() then 
		self:setState(2)
	else
		self:setState(1)
	end
	if self.labelElement then 
		self.labelElement:setText(self.dataSource:getTitle())
	end
	if self.toolTipElement then
		self.toolTipElement:setText(self.dataSource:getTooltip())
	end
	-- self:setState(1)
end

-- Lines 35-42
function CpBinaryOptionElement:onRightButtonClicked(steps, noFocus)
	if self.dataSource ~= nil then
		self.dataSource:setNextItem()

		-- self.texts[1] = self.dataSource:getString()
	end

	CpBinaryOptionElement:superClass().onRightButtonClicked(self, steps, noFocus)
end

-- Lines 44-51
function CpBinaryOptionElement:onLeftButtonClicked(steps, noFocus)
	if self.dataSource ~= nil then
		self.dataSource:setPreviousItem()

		-- self.texts[1] = self.dataSource:getString()
	end

	CpBinaryOptionElement:superClass().onLeftButtonClicked(self, steps, noFocus)
end
Gui.registerGuiElement("CpBinaryyOption", CpBinaryOptionElement)
