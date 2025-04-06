--- Bale finder Hud page
---@class CpSiloLoaderWorkerHudPageElement : CpHudPageElement
CpSiloLoaderWorkerHudPageElement = {}
local CpSiloLoaderWorkerHudPageElement_mt = Class(CpSiloLoaderWorkerHudPageElement, CpHudPageElement)

function CpSiloLoaderWorkerHudPageElement.new(overlay, parentHudElement, customMt)
    ---@class CpSiloLoaderWorkerHudPageElement : CpHudPageElement
    ---@field copyButton CpHudButtonElement
    ---@field pasteButton CpHudButtonElement
    ---@field clearCacheBtn CpHudButtonElement
    ---@field copyCacheText CpTextHudElement
    local self = CpHudPageElement.new(overlay, parentHudElement, customMt or CpSiloLoaderWorkerHudPageElement_mt)
        
    return self
end

function CpSiloLoaderWorkerHudPageElement:setupElements(baseHud, vehicle, lines, wMargin, hMargin)
	
    --- Work width
    self.workWidthBtn = baseHud:addLineTextButtonWithIncrementalButtons(self, CpBaseHud.numLines - 5, CpBaseHud.defaultFontSize, 
                                                vehicle:getCpSettings().bunkerSiloWorkWidth) 


    --- Displays the fill level of current worked on heap.
    local x, y = unpack(lines[CpBaseHud.numLines - 4].left)
    self.fillLevelProgressLabel = CpTextHudElement.new(self , x , y, CpBaseHud.defaultFontSize)
    self.fillLevelProgressLabel:setTextDetails(g_i18n:getText("CP_siloLoader_fillLevelProgress"))
    --- Displays the fill level of current worked on heap.
    local x, y = unpack(lines[CpBaseHud.numLines - 4].right)
    self.fillLevelProgressText = CpTextHudElement.new(self, x, y, CpBaseHud.defaultFontSize, RenderText.ALIGN_RIGHT)
    
    --- Shovel loading height offset.
    self.loadingShovelHeightOffsetBtn = baseHud:addLineTextButtonWithIncrementalButtons(self, CpBaseHud.numLines - 6, CpBaseHud.defaultFontSize, 
        vehicle:getCpSettings().loadingShovelHeightOffset) 

    CpGuiUtil.addCopyAndPasteButtons(self, baseHud, 
    vehicle, lines, wMargin, hMargin, 1)

    self.copyButton:setCallback("onClickPrimary", vehicle, function (vehicle)
        if not CpBaseHud.copyPasteCache.hasVehicle and vehicle.getCpCombineUnloaderJob then 
            CpBaseHud.copyPasteCache.siloLoaderVehicle = vehicle
            CpBaseHud.copyPasteCache.hasVehicle = true
        end
    end)


    self.pasteButton:setCallback("onClickPrimary", vehicle, function (vehicle)
        if CpBaseHud.copyPasteCache.hasVehicle and not vehicle:getIsCpActive() then 
            if CpBaseHud.copyPasteCache.siloLoaderVehicle then 
                vehicle:applyCpSiloLoaderWorkerJobParameters(CpBaseHud.copyPasteCache.siloLoaderVehicle:getCpSiloLoaderWorkerJob())
            else 
                local parameters = CpBaseHud.copyPasteCache.combineUnloaderVehicle:getCpCombineUnloaderJobParameters()
                vehicle:getCpSiloLoaderWorkerJobParameters().loadPosition:copy(parameters.fieldUnloadPosition)
            end
        end
    end)

    self.clearCacheBtn:setCallback("onClickPrimary", vehicle, function (vehicle)
        CpBaseHud.copyPasteCache.hasVehicle = false
        CpBaseHud.copyPasteCache.siloLoaderVehicle = nil 
        CpBaseHud.copyPasteCache.combineUnloaderVehicle = nil
    end)
end

function CpSiloLoaderWorkerHudPageElement:update(dt)
	CpSiloLoaderWorkerHudPageElement:superClass().update(self, dt)
	
end

---@param vehicle table
---@param status CpStatus
function CpSiloLoaderWorkerHudPageElement:updateContent(vehicle, status)
    local workWidth = vehicle:getCpSettings().bunkerSiloWorkWidth
    self.workWidthBtn:setTextDetails(workWidth:getTitle(), workWidth:getString())
    self.workWidthBtn:setVisible(workWidth:getIsVisible())

    local loadingHeightOffset = vehicle:getCpSettings().loadingShovelHeightOffset
    self.loadingShovelHeightOffsetBtn:setTextDetails(loadingHeightOffset:getTitle(), loadingHeightOffset:getString())
    self.loadingShovelHeightOffsetBtn:setVisible(loadingHeightOffset:getIsVisible())
    self.loadingShovelHeightOffsetBtn:setDisabled(loadingHeightOffset:getIsDisabled())

    self.fillLevelProgressText:setTextDetails(status:getSiloFillLevelPercentageLeftOver())

    --- Update copy and paste buttons
    self:updateCopyButtons(vehicle)
end

--- Updates the copy, paste and clear buttons.
function CpSiloLoaderWorkerHudPageElement:updateCopyButtons(vehicle)
    if CpBaseHud.copyPasteCache.hasVehicle then 
        self.clearCacheBtn:setVisible(true)
        self.pasteButton:setVisible(true)
        self.copyButton:setVisible(false)
        local copyCacheVehicle = CpBaseHud.copyPasteCache.siloLoaderVehicle or CpBaseHud.copyPasteCache.combineUnloaderVehicle
        local fieldNum = CpFieldUtil.getFieldNumUnderVehicle(copyCacheVehicle)
        local text = CpUtil.getName(copyCacheVehicle)
        if fieldNum then 
            text = string.format("%s(%s)", text, fieldNum)
        end
        self.copyCacheText:setTextDetails(text)
        self.copyCacheText:setTextColorChannels(unpack(CpBaseHud.OFF_COLOR))
        self.pasteButton:setColor(unpack(CpBaseHud.OFF_COLOR))
        self.pasteButton:setDisabled(true)
        if copyCacheVehicle == vehicle or vehicle:getIsCpActive() then 
            --- Paste disabled
            return
        end

        local arePositionEqual
        if CpBaseHud.copyPasteCache.siloLoaderVehicle then 
            arePositionEqual = self:arePositionEqual(vehicle:getCpSiloLoaderWorkerJobParameters(), 
                copyCacheVehicle:getCpSiloLoaderWorkerJobParameters())
        else
            local unloadPosition = copyCacheVehicle:getCpCombineUnloaderJobParameters().fieldUnloadPosition
            local loadPosition = vehicle:getCpSiloLoaderWorkerJobParameters().loadPosition
            arePositionEqual = unloadPosition:isAlmostEqualTo(loadPosition)

        end
        if arePositionEqual then 
            --- Paste disabled
            return
        end
        self.copyCacheText:setTextColorChannels(unpack(CpBaseHud.WHITE_COLOR))
        self.pasteButton:setColor(unpack(CpBaseHud.ON_COLOR))
        self.pasteButton:setDisabled(false)
    else
        self.copyCacheText:setTextDetails("")
        self.clearCacheBtn:setVisible(false)
        self.pasteButton:setVisible(false)
        self.copyButton:setVisible(true)
    end
end

function CpSiloLoaderWorkerHudPageElement:arePositionEqual(parameters, otherParameters)
    if not parameters.loadPosition:isAlmostEqualTo(otherParameters.loadPosition) then 
        return false
    end 
    if not parameters.startPosition:isAlmostEqualTo(otherParameters.startPosition) then 
        return false
    end
    return true 
end
