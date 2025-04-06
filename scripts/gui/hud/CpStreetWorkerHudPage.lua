--- Fieldwork Hud page
---@class CpStreetWorkerHudPageElement : CpHudElement
CpStreetWorkerHudPageElement = {}
local CpStreetWorkerHudPageElement_mt = Class(CpStreetWorkerHudPageElement, CpHudPageElement)

function CpStreetWorkerHudPageElement.new(overlay, parentHudElement, customMt)
	local self = CpHudPageElement.new(overlay, parentHudElement, customMt or CpStreetWorkerHudPageElement_mt)
	return self
end

function CpStreetWorkerHudPageElement:setupElements(baseHud, vehicle, lines, wMargin, hMargin)

    self.loadUnloadTargetModeBtn = baseHud:addLeftLineTextButton(self, CpBaseHud.numLines - 3, CpBaseHud.defaultFontSize, 
        function (vehicle)
            vehicle:getCpStreetWorkerJobParameters().loadUnloadTargetMode:setNextItem()
        end, vehicle)

    self.unloadTargetPointBtn = baseHud:addLineTextButton(self, CpBaseHud.numLines - 4, 
		CpBaseHud.defaultFontSize, vehicle:getCpStreetWorkerJobParameters().unloadTargetPoint,
        function()
            TargetPointSelectionDialog.show(
				{vehicle:getCpStreetWorkerJobParameters().unloadTargetPoint,
				vehicle:getCpStreetWorkerJobParameters().loadTargetPoint})
        end)

	self.loadTargetPointBtn = baseHud:addLineTextButton(self, CpBaseHud.numLines - 5, 
	CpBaseHud.defaultFontSize, vehicle:getCpStreetWorkerJobParameters().loadTargetPoint,
	function()
		TargetPointSelectionDialog.show(
			{vehicle:getCpStreetWorkerJobParameters().unloadTargetPoint,
			vehicle:getCpStreetWorkerJobParameters().loadTargetPoint})
	end)

    self.fillTypeButtons = {
		baseHud:addLineTextButton(self, CpBaseHud.numLines - 6, 
			CpBaseHud.defaultFontSize, vehicle:getCpStreetWorkerJobParameters().loadTargetPoint,
			function()
				FilltypeSelectionDialog.show(
					vehicle:getCpStreetWorkerJobParameters().fillTypeSelection1)
			end),
		baseHud:addLineTextButton(self, CpBaseHud.numLines - 7, 
			CpBaseHud.defaultFontSize, vehicle:getCpStreetWorkerJobParameters().loadTargetPoint,
			function()
				FilltypeSelectionDialog.show(
					vehicle:getCpStreetWorkerJobParameters().fillTypeSelection2)
			end),
		baseHud:addLineTextButton(self, CpBaseHud.numLines - 8, 
			CpBaseHud.defaultFontSize, vehicle:getCpStreetWorkerJobParameters().loadTargetPoint,
			function()
				FilltypeSelectionDialog.show(
					vehicle:getCpStreetWorkerJobParameters().fillTypeSelection3)
			end)}


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

	CpGuiUtil.addCopyAndPasteButtons(self, baseHud, 
		vehicle, lines, wMargin, hMargin, 1)

	self.copyButton:setCallback("onClickPrimary", vehicle, function (vehicle)
		if not CpBaseHud.copyPasteCache.hasVehicle and vehicle.getCpStreetWorkerJob then 
			CpBaseHud.copyPasteCache.streetWorkerVehicle = vehicle
			CpBaseHud.copyPasteCache.hasVehicle = true
		end
	end)


	self.pasteButton:setCallback("onClickPrimary", vehicle, function (vehicle)
		if CpBaseHud.copyPasteCache.hasVehicle and not vehicle:getIsCpActive() then 
			if CpBaseHud.copyPasteCache.streetWorkerVehicle then 
				vehicle:applyCpStreetWorkerJobParameters(CpBaseHud.copyPasteCache.streetWorkerVehicle:getCpStreetWorkerJob())
			end
		end
	end)

	self.clearCacheBtn:setCallback("onClickPrimary", vehicle, function (vehicle)
		CpBaseHud.copyPasteCache.hasVehicle = false
		CpBaseHud.copyPasteCache.streetWorkerVehicle = nil 
	end)
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
	
    local jobParameters = vehicle:getCpStreetWorkerJobParameters()
    self.loadUnloadTargetModeBtn:setTextDetails(jobParameters.loadUnloadTargetMode:getString())
    self.unloadTargetPointBtn:setTextDetails(
		jobParameters.unloadTargetPoint:getTitle(),
		jobParameters.unloadTargetPoint:getString())
	self.unloadTargetPointBtn:setDisabled(jobParameters.unloadTargetPoint:getIsDisabled())
	self.loadTargetPointBtn:setTextDetails(
		jobParameters.loadTargetPoint:getTitle(),
		jobParameters.loadTargetPoint:getString())
	self.loadTargetPointBtn:setVisible(not jobParameters.loadTargetPoint:getIsDisabled())
	local fillTypeSettings = jobParameters:getFillTypeSelectionSettings()
	for ix, fillTypeBtn in ipairs(self.fillTypeButtons) do 
		fillTypeBtn:setDisabled(fillTypeSettings[ix]:getIsDisabled())
		fillTypeBtn:setTextDetails(fillTypeSettings[ix]:getTitle(), fillTypeSettings[ix]:getString())
		fillTypeBtn:setVisible(not jobParameters.loadTargetPoint:getIsDisabled())
	end
	self:updateCopyButtons(vehicle)
end

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