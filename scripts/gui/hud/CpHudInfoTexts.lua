
---@class CpHudInfoTexts
CpHudInfoTexts = CpObject()
CpHudInfoTexts.baseSize = {
	x = 350,
    y = 300
}
CpHudInfoTexts.basePosition = {
	x = 1920 - 300,
    y = 1080 - 100
}
CpHudInfoTexts.titleFontSize = 14
CpHudInfoTexts.defaultFontSize = 18
CpHudInfoTexts.maxLines = 10
CpHudInfoTexts.colorCurrentVehicle = {
    0, 1, 1, 1
}
CpHudInfoTexts.colorDefault = {
    1, 1, 1, 1
}

CpHudInfoTexts.colorHeader = {
    0.22323, 0.40724, 0.00368, 1
}

CpHudInfoTexts.uvs = {
    vehicleIcon = {
        {0,37,35,35}
    }
}


CpHudInfoTexts.OFF_COLOR = {0.2, 0.2, 0.2, 0.9}
CpHudInfoTexts.SELECTED_COLOR = {0, 0.6, 0, 0.9}

CpHudInfoTexts.xmlKey = "HudInfoTexts"
function CpHudInfoTexts.registerXmlSchema(xmlSchema, baseKey)
    xmlSchema:register(XMLValueType.FLOAT, baseKey .. CpHudInfoTexts.xmlKey .. "#posX", "Hud position x")
    xmlSchema:register(XMLValueType.FLOAT, baseKey .. CpHudInfoTexts.xmlKey .. "#posY", "Hud position y")
end

function CpHudInfoTexts:init()
	self.uiScale = g_gameSettings:getValue("uiScale")
   
    self.x, self.y = getNormalizedScreenValues(self.basePosition.x, self.basePosition.y)

    self.width, self.height = getNormalizedScreenValues(self.baseSize.x, self.baseSize.y)

    self.lineHeight = self.height/self.maxLines
    self.hMargin = self.lineHeight
    self.wMargin = self.hMargin/6

    local background = Overlay.new(g_baseUIFilename, 0, 0, self.width, self.height)
    background:setUVs(g_colorBgUVs)
    background:setColor(0, 0, 0, 0.7)
    background:setAlignment(Overlay.ALIGN_VERTICAL_TOP, Overlay.ALIGN_HORIZONTAL_LEFT)
    --- Base hud element.
    self.baseHud = CpHudMoveableElement.new(background)
    self.baseHud:setPosition(self.x, self.y)
    self.baseHud:setDimension(self.width, self.height)
    self.baseHud:setCallback("onMove", self, function(self, _, x, y)
        self.x = x
        self.y = y
    end)

    local headerHeight = self.hMargin/2
    local headerBackground = Overlay.new(g_baseUIFilename, 0, 0, self.width, headerHeight)
    headerBackground:setUVs(g_colorBgUVs)
    headerBackground:setColor(unpack(self.colorHeader))
    headerBackground:setAlignment(Overlay.ALIGN_VERTICAL_TOP, Overlay.ALIGN_HORIZONTAL_LEFT)

    local topElement = CpHudElement.new(headerBackground, self.baseHud)
    topElement:setPosition(self.x, self.y)
    topElement:setDimension(self.width, headerHeight)

    local leftTopText = CpTextHudElement.new(self.baseHud, self.x + self.wMargin, self.y - headerHeight + self.hMargin/16, self.titleFontSize)
    leftTopText:setTextDetails("Courseplay")
    local rightTopText = CpTextHudElement.new(self.baseHud, self.x + self.width - self.wMargin, self.y - headerHeight + self.hMargin/16, self.titleFontSize, RenderText.ALIGN_RIGHT)
    rightTopText:setTextDetails(g_Courseplay.currentVersion)

    local width, height = getNormalizedScreenValues(20, 20)

    local x = self.x + self.wMargin
    local dx = x + self.wMargin + width
    local y =  self.y - self.hMargin - headerHeight + self.lineHeight
    self.infoTextsElements = {}
    for i=1, self.maxLines do 
        y = y - self.lineHeight
    
        local vehicleOverlay = CpGuiUtil.createOverlayFromSlice(
            "cpIconSprite.white_vehicle", 
            {width, height},
            CpBaseHud.OFF_COLOR,
            CpBaseHud.alignments.bottomLeft)
     
        local vehicleBtn = CpHudButtonElement.new(vehicleOverlay, self.baseHud)
        vehicleBtn:setPosition(x, y)
    
        local line = {
            text = CpTextHudElement.new(self.baseHud, dx, y, self.defaultFontSize),
            vehicleBtn = vehicleBtn
        }
        table.insert(self.infoTextsElements,line)
    end
    self.baseHud:setScale(self.uiScale, self.uiScale)
    self.activeTexts = 0
end

function CpHudInfoTexts:mouseEvent(posX, posY, isDown, isUp, button)
	if not self:isVisible() or self:isDisabled() then return end
	local wasUsed = self.baseHud:mouseEvent(posX, posY, isDown, isUp, button)
    if wasUsed then 
        return
    end
end

function CpHudInfoTexts:moveToPosition(x, y)
    self.baseHud:moveTo(x, y)
end

function CpHudInfoTexts:draw()
    self:update()
	if self:isVisible() then
        self.baseHud:draw()
    end
end

function CpHudInfoTexts:update()
    self.activeTexts = 0 
    local infoTexts = g_infoTextManager:getActiveInfoTexts()
    local elements, info, ix, lastInfo
    for i = 1, #self.infoTextsElements do
        ix = i
        elements = self.infoTextsElements[i]
        info = infoTexts[ix]
        --- Info text for this element was found.
        if info then 
            lastInfo = elements.lastInfo
            --- Only update the hud button, when the info has changed.
            if lastInfo == nil or info.vehicle ~= lastInfo.vehicle or info.text ~= lastInfo.text then 
                --- Update the text button
                elements.text:setVisible(true)
                local text = string.format("%s", info.text)
                elements.text:setTextDetails(text)
                elements.text:setCallback("onClickPrimary", info.vehicle, function (v)
                    self:debug("trying to enter vehicle: %s", v:getName())
                    self:enterVehicle(v) 
                    elements.text:setHovered(false)
                end,elements.text)
                elements.text:setHoveredText(CpUtil.getName(info.vehicle))
                --- Update the vehicle button
                elements.vehicleBtn:setVisible(true)
                elements.vehicleBtn:setCallback("onClickPrimary", info.vehicle, function (v)
                    self:debug("trying to enter vehicle: %s", v:getName())
                    self:enterVehicle(v) 
                    elements.text:setHovered(false)
                end,elements.text)
                elements.lastInfo = info
            end
            --- Makes sure the current entered vehicle is highlighted.
            if info.vehicle == CpUtil.getCurrentVehicle() then
                elements.vehicleBtn:setColor(unpack(self.SELECTED_COLOR))
            else 
                elements.vehicleBtn:setColor(unpack(self.OFF_COLOR))
            end
            self.activeTexts = self.activeTexts + 1
        else 
            --- Not enough active info text, so disable these buttons.
            elements.vehicleBtn:setVisible(false)
            elements.text:setVisible(false)
            self.infoTextsElements[i].lastInfo = nil
        end
    end
    --- Update the background height and shortens it, 
    --- when the number of info texts is below the number of 
    --- info texts, that can be shown simultaneously.
    if self.activeTexts > 0 then
        local _, y = self.baseHud:getPosition()
        local _, dy = self.infoTextsElements[self.activeTexts].text:getPosition()
        local width = self.baseHud:getWidth()
        self.baseHud:setDimension(width, y - dy + self.hMargin/2)
    else 
        local width = self.baseHud:getWidth()
        self.baseHud:setDimension(width, self.hMargin/2)
    end
end

function CpHudInfoTexts:enterVehicle(vehicle)
    g_localPlayer:requestToEnterVehicle(vehicle)
end

function CpHudInfoTexts:isVisible()
    if g_Courseplay.globalSettings.infoTextHudActive:getValue() == g_Courseplay.globalSettings.ACTIVE_HIDE_HUD_WITHOUT_MESSAGE then 
        return self.activeTexts > 0
    end
	return g_Courseplay.globalSettings.infoTextHudActive:getValue() ~= g_Courseplay.globalSettings.DISABLED
end

function CpHudInfoTexts:isDisabled()
	return false
end

function CpHudInfoTexts:delete()
	self.baseHud:delete()
end

function CpHudInfoTexts:debug(str,...)
    CpUtil.debugFormat(CpDebug.DBG_HUD, "Info text hud " .. str, ...)   
end

--- Saves hud position.
function CpHudInfoTexts:saveToXmlFile(xmlFile, baseKey)
    if self.x ~= nil and self.y ~= nil then
        xmlFile:setValue(baseKey .. self.xmlKey .. "#posX", self.x)
        xmlFile:setValue(baseKey .. self.xmlKey .. "#posY", self.y)
    end
end

--- Loads hud position.
function CpHudInfoTexts:loadFromXmlFile(xmlFile, baseKey)
    local posX = xmlFile:getValue(baseKey .. self.xmlKey .. "#posX")
    local posY = xmlFile:getValue(baseKey .. self.xmlKey .. "#posY")
    if posX ~= nil and posY ~= nil then 
        self:moveToPosition(posX, posY)
    end
end

function CpHudInfoTexts.reload()
    g_Courseplay.infoTextsHud = CpHudInfoTexts()
end