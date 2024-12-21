--- Adds additional setting features to the OptionToggleElement Gui element.
--- Mainly a direct button/key press for text input or similar actions.
CpOptionToggleElement = {}
local CpOptionToggleElement_mt = Class(CpOptionToggleElement, OptionToggleElement)

function CpOptionToggleElement.new(target, custom_mt)
	local self = OptionToggleElement.new(target, custom_mt or CpOptionToggleElement_mt)
	self.toolTipElement = nil
	return self
end

function CpOptionToggleElement:loadFromXML(xmlFile, key)
	CpOptionToggleElement:superClass().loadFromXML(self, xmlFile, key)
	self:addCallback(xmlFile, key .. "#onClickCenter", "onClickCenterCallback")
end

function CpOptionToggleElement:copyAttributes(src)
	CpOptionToggleElement:superClass().copyAttributes(self, src)
	self.onClickCenterCallback = src.onClickCenterCallback
end

function CpOptionToggleElement:onCenterButtonClicked()
	self:raiseCallback("onClickCenterCallback", self)
	if self.dataSource ~= nil then
		self.dataSource:onClickCenter(self)
	end
	self:setSoundSuppressed(true)
	FocusManager:setFocus(self)
	self:setSoundSuppressed(false)
end

function CpOptionToggleElement:addElement(element, ...)
	CpOptionToggleElement:superClass().addElement(self, element, ...)
	if self.textElement then
		self.textElement.forceHighlight = true
		self.textElement:setHandleFocus(false)
		self.textElement.target = self
		self.textElement:setCallback("onClickCallback", "onCenterButtonClicked")
	end
end

function CpOptionToggleElement:updateTitle()
	if not self.dataSource then 
		return
	end
	CpOptionToggleElement:superClass().updateTitle(self)
	if self.labelElement and self.labelElement.setText then 
		self.labelElement:setText(self.dataSource:getTitle())
	end
	self.toolTipElement = self:getDescendantByName("tooltip")
	if self.toolTipElement then 
		self.toolTipText = self.dataSource:getTooltip()
	end
end

function CpOptionToggleElement:setLabelElement(element)
	self.labelElement = element
	self:updateTitle()
end

function CpOptionToggleElement:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
	if self.parent then 
		-- Fixes giants bug, where the scrolling layout is not disabling the mouse event for invisible child elements.
		local _, clipY1 , _, clipY2 = self.parent:getClipArea(0,0,1,1)
		if (clipY1 - self.absPosition[2] * 0.02) > (self.absPosition[2]) or 
			(clipY2 + self.absPosition[2] * 0.02) < ( self.absPosition[2] + self.absSize[2]) then 
			return eventUsed
		end
	end
	return CpOptionToggleElement:superClass().mouseEvent(self, posX, posY, isDown, isUp, button, eventUsed)
end

function CpOptionToggleElement:inputEvent(action, value, eventUsed)
	if self:getIsActive() then
		eventUsed = CpOptionToggleElement:superClass().inputEvent(self, action, value, eventUsed)
		if not eventUsed then
			if action == InputAction.MENU_ACCEPT then
				if self.focusActive then
					self:onCenterButtonClicked()
					eventUsed = true
				end
			end
		end
	end
	return eventUsed
end
function CpOptionToggleElement:raiseClickCallback(...)
	CpOptionToggleElement:superClass().raiseClickCallback(self, ...)
	--- Magic gui fix, no idea why this is needed ...
	FocusManager:unsetFocus(self)
end
Gui.registerGuiElement("CpOptionToggle", CpOptionToggleElement)
