--- Fieldwork Hud page
---@class CpStreetWorkerHudPageElement : CpHudElement
CpStreetWorkerHudPageElement = {}
local CpStreetWorkerHudPageElement_mt = Class(CpStreetWorkerHudPageElement, CpHudPageElement)

function CpStreetWorkerHudPageElement.new(overlay, parentHudElement, customMt)
	local self = CpHudPageElement.new(overlay, parentHudElement, customMt or CpStreetWorkerHudPageElement_mt)
	return self
end

function CpStreetWorkerHudPageElement:setupElements(baseHud, vehicle, lines, wMargin, hMargin)

	-- local x, y = unpack(lines[5].left)
	-- self.loadMultipleFillTypesSetting = CpTextHudElement.new(self, 
	-- 	x, y, baseHud.defaultFontSize)
	-- x, y = unpack(lines[4].right)
	-- local max = CpTextHudElement.new(self, 
	-- 	x , y, baseHud.defaultFontSize, RenderText.ALIGN_RIGHT)
	-- max:setDisabled(true)
	-- max:setTextDetails("max")
	-- x = x - max:getTextWidth("100%") - wMargin/2
	-- local min = CpTextHudElement.new(self, 
	-- 	x, y, baseHud.defaultFontSize, RenderText.ALIGN_RIGHT)
	-- min:setDisabled(true)
	-- min:setTextDetails("min")
	-- x = x - min:getTextWidth("100%") - wMargin/2
	-- local counter = CpTextHudElement.new(self, 
	-- 	x, y, baseHud.defaultFontSize, RenderText.ALIGN_RIGHT)
	-- counter:setDisabled(true)
	-- counter:setTextDetails("count")

	-- self.fillTypeSettings = {
	-- 	self:addFillTypeSelection(3, baseHud, vehicle, 
	-- 		lines, wMargin, hMargin),
	-- 	self:addFillTypeSelection(2, baseHud, vehicle, 
	-- 		lines, wMargin, hMargin),
	-- 	self:addFillTypeSelection(1, baseHud, vehicle, 
	-- 		lines, wMargin, hMargin)
	-- }

	-- CpGuiUtil.addCopyAndPasteButtons(self, baseHud, 
	-- 	vehicle, lines, wMargin, hMargin, 1)

	-- self.copyButton:setCallback("onClickPrimary", vehicle, function (vehicle)
	-- 	if not CpBaseHud.copyPasteCache.hasVehicle and vehicle.getCpStreetWorkerJob then 
	-- 		CpBaseHud.copyPasteCache.streetWorkerVehicle = vehicle
	-- 		CpBaseHud.copyPasteCache.hasVehicle = true
	-- 	end
	-- end)


	-- self.pasteButton:setCallback("onClickPrimary", vehicle, function (vehicle)
	-- 	if CpBaseHud.copyPasteCache.hasVehicle and not vehicle:getIsCpActive() then 
	-- 		if CpBaseHud.copyPasteCache.streetWorkerVehicle then 
	-- 			vehicle:applyCpStreetWorkerJobParameters(CpBaseHud.copyPasteCache.streetWorkerVehicle:getCpStreetWorkerJob())
	-- 		end
	-- 	end
	-- end)

	-- self.clearCacheBtn:setCallback("onClickPrimary", vehicle, function (vehicle)
	-- 	CpBaseHud.copyPasteCache.hasVehicle = false
	-- 	CpBaseHud.copyPasteCache.streetWorkerVehicle = nil 
	-- end)
end

function CpStreetWorkerHudPageElement:addFillTypeSelection(line, baseHud, vehicle, lines, wMargin, hMargin)
	--- Fill type
	local x, y = unpack(lines[line].left)
	local fillType = CpTextHudElement.new(self, 
		x , y, baseHud.defaultFontSize)
	fillType:setDisabled(true)
	x, y = unpack(lines[line].right)
	local max = CpTextHudElement.new(self, 
		x , y, baseHud.defaultFontSize, RenderText.ALIGN_RIGHT)
	max:setDisabled(true)
	x = x - max:getTextWidth("100%") - wMargin/2
	local min = CpTextHudElement.new(self, 
		x , y, baseHud.defaultFontSize, RenderText.ALIGN_RIGHT)
	min:setDisabled(true)
	x = x - min:getTextWidth("100%") - wMargin/2
	local counter = CpTextHudElement.new(self, 
		x , y, baseHud.defaultFontSize, RenderText.ALIGN_RIGHT)
	counter:setDisabled(true)
	return {
		fillType = fillType,
		min = min,
		max = max, 
		counter = counter
	}
end

function CpStreetWorkerHudPageElement:update(dt)
	CpStreetWorkerHudPageElement:superClass().update(self, dt)

end

---@param vehicle table
---@param status CpStatus
function CpStreetWorkerHudPageElement:updateContent(vehicle, status)
    -- local workWidth = vehicle:getCpSettings().bunkerSiloWorkWidth
    -- self.workWidthBtn:setTextDetails(workWidth:getTitle(), workWidth:getString())
    -- self.workWidthBtn:setVisible(workWidth:getIsVisible())

    -- local loadingHeightOffset = vehicle:getCpSettings().loadingShovelHeightOffset
    -- self.loadingShovelHeightOffsetBtn:setTextDetails(loadingHeightOffset:getTitle(), loadingHeightOffset:getString())
    -- self.loadingShovelHeightOffsetBtn:setVisible(loadingHeightOffset:getIsVisible())
    -- self.loadingShovelHeightOffsetBtn:setDisabled(loadingHeightOffset:getIsDisabled())

    -- self.fillLevelProgressText:setTextDetails(status:getSiloFillLevelPercentageLeftOver())
	-- local jobParameters = vehicle:getCpStreetWorkerJob():getCpJobParameters()
	-- --self.loadMultipleFillTypesSetting:setTextDetails(jobParameters.loadingMultipleFruitTypesAllowed:getString())
	-- for i, setting in ipairs(jobParameters:getFillTypeSelectionSettings()) do 
	-- 	if self.fillTypeSettings[i] and setting.fillType:getValue() > FillType.UNKNOWN then 
	-- 		self.fillTypeSettings[i].fillType:setTextDetails(setting.fillType:getString())
	-- 		self.fillTypeSettings[i].min:setTextDetails(setting.minFillLevel:getString())
	-- 		self.fillTypeSettings[i].max:setTextDetails(setting.maxFillLevel:getString())
	-- 		local counter = string.format("%d/%d", 
	-- 			setting:getCounter(), setting.counter:getValue())
	-- 		self.fillTypeSettings[i].counter:setTextDetails(counter)
	-- 	end
	-- end

    --- Update copy and paste buttons
	-- self:updateCopyButtons(vehicle)
end


--- Updates the copy, paste and clear buttons.
function CpStreetWorkerHudPageElement:updateCopyButtons(vehicle)
    if CpBaseHud.copyPasteCache.hasVehicle then 
        self.clearCacheBtn:setVisible(true)
        self.pasteButton:setVisible(true)
        self.copyButton:setVisible(false)
        local copyCacheVehicle = CpBaseHud.copyPasteCache.streetWorkerVehicle
        local text = CpUtil.getName(copyCacheVehicle)
        self.copyCacheText:setTextDetails(text)
        self.copyCacheText:setTextColorChannels(unpack(CpBaseHud.OFF_COLOR))
        self.pasteButton:setColor(unpack(CpBaseHud.OFF_COLOR))
        self.pasteButton:setDisabled(true)
        if copyCacheVehicle == vehicle or vehicle:getIsCpActive() then 
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