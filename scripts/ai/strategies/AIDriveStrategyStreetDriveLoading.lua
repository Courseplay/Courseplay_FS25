---@class AIDriveStrategyStreetDriveLoading : AIDriveStrategyStreetDriveToPoint
AIDriveStrategyStreetDriveLoading = CpObject(AIDriveStrategyStreetDriveToPoint)

AIDriveStrategyStreetDriveLoading.myStates = {

}
AIDriveStrategyStreetDriveLoading.COURSE_EXTENSION = 2

function AIDriveStrategyStreetDriveLoading:init(task, job)
    AIDriveStrategyStreetDriveToPoint.init(self, task, job)
    AIDriveStrategyCourse.initStates(self, AIDriveStrategyStreetDriveLoading.myStates)

end

function AIDriveStrategyStreetDriveLoading:setAllStaticParameters()
    AIDriveStrategyStreetDriveToPoint.setAllStaticParameters(self)

    ---@type CpAIParameterFillTypeSetting[]
    self.fillTypeSettings = self.jobParameters:getFillTypeSelectionSettings()
    self.hasCourseEndReached = false
     ---@type table<CpAIParameterFillTypeSetting,boolean>
    self.fillTypeSettingsLoaded = {}

    self.isLoading = false
    self.currentLoadTrigger = nil
end

function AIDriveStrategyStreetDriveLoading:onStartDrivingCourse(course, ix)
    course:extend(self.COURSE_EXTENSION)
    AIDriveStrategyStreetDriveToPoint.onStartDrivingCourse(self, course, ix)
end

function AIDriveStrategyStreetDriveLoading:initializeImplementControllers(vehicle)
    AIDriveStrategyStreetDriveToPoint.initializeImplementControllers(self, vehicle)
    self:addImplementController(vehicle, CoverController, Cover, {})
end

function AIDriveStrategyStreetDriveLoading:isCoverOpeningAllowed()
    local course = self.ppc:getCourse()
    local length = AIUtil.getLength(self.vehicle)
    return course and course:isCloseToLastWaypoint(length * 1.5)
end

function AIDriveStrategyStreetDriveLoading:drivingCourse()
    local course = self.ppc:getCourse()
    local length = AIUtil.getLength(self.vehicle)
    if course:isCloseToLastWaypoint(length * 3 + self.COURSE_EXTENSION) then
        self:setMaxSpeed(self.settings.turnSpeed:getValue())
        self:debugSparse("Slowing down close to the loading point.")
    end
    if course:isCloseToLastWaypoint(length * 1.5 + 2 * self.COURSE_EXTENSION) then 
        self:updateLoading()
    end
    if self.hasCourseEndReached then 
        local missingFillTypes = {}
        local fillLevels = FillLevelUtil.getAllFillLevels(self.vehicle) or {}
        --- Check min fill levels
        for _, fillTypeSetting in pairs(self.fillTypeSettings) do 
            local fillType = fillTypeSetting.fillType:getValue()
            local data = fillLevels[fillType]
            if data ~= nil then 
                if (100 * data.allowedFillLevel / data.allowedCapacity)
                    <= fillTypeSetting.minFillLevel:getValue() then 
                    missingFillTypes[fillType] = true
                end
            end
        end
        if not next(missingFillTypes) then 
            for setting, _ in pairs(self.fillTypeSettingsLoaded) do 
                setting:applyCounter()
            end
            self:debug("No more missing fill types, so continuing ..")
            if not self.isLoading then
                self:setCurrentTaskFinished()
            end
        end
        self:setMaxSpeed(0)
    end
end

function AIDriveStrategyStreetDriveLoading:onCourseEndReached()
    --- TODO 
    self.hasCourseEndReached = true
end

function AIDriveStrategyStreetDriveLoading:updateLoading()
    local missingFillTypes = {}
    local fillLevels = FillLevelUtil.getAllFillLevels(self.vehicle) or {}
    --- Check min fill levels
    for _, fillTypeSetting in pairs(self.fillTypeSettings) do 
        local fillType = fillTypeSetting.fillType:getValue()
        local data = fillLevels[fillType]
        if fillType > FillType.UNKNOWN and data ~= nil then 
            if (100 * data.allowedFillLevel / data.allowedCapacity)
                <= fillTypeSetting.minFillLevel:getValue() then 
                missingFillTypes[fillType] = true
            end
        end
    end

    local validTriggers, isLoading = {}, false
    if not self.isLoading then
        for _, loadTrigger in pairs(g_triggerManager:getLoadTriggers()) do 
            --- Gathering all possible triggers
            local trigger = loadTrigger:getTrigger()
            if trigger:getIsFillableObjectAvailable() and not trigger.isLoading then                  
                if trigger.validFillableObject and trigger.validFillableObject.rootVehicle == self.vehicle then 
                    table.insert(validTriggers, {
                        cpTrigger = loadTrigger,
                        trigger = trigger,
                        object = trigger.validFillableObject,
                        fillUnitIndex = trigger.validFillableFillUnitIndex,
                        fillLevels = trigger.source:getAllFillLevels(g_currentMission:getFarmId()),
                        fillTypes = trigger.fillTypes
                    })
                end
            end
        end
         --- Checks if starting is possible?
        for _, triggerData in ipairs(validTriggers) do 
            for _, fillTypeSetting in pairs(self.fillTypeSettings) do 
                local fillType = fillTypeSetting.fillType:getValue()
                local fillLevel = triggerData.fillLevels[fillType]
                if fillType > FillType.UNKNOWN and (triggerData.fillTypes == nil or triggerData.fillTypes[fillType]) and fillLevel then 
                    --- Fill level was found for given fill type.
                    if triggerData.object:getFillUnitAllowsFillType(triggerData.fillUnitIndex, fillType) then 
                        if fillTypeSetting.maxFillLevel:getValue() > 
                            triggerData.object:getFillUnitFillLevelPercentage(triggerData.fillUnitIndex) * 100 then
                            --- Loading is allowed
                            self:setMaxSpeed(0)
                            triggerData.trigger:onFillTypeSelection(fillType)
                            self.fillTypeSettingsLoaded[fillTypeSetting] = true
                            self.isLoading = true
                            self.currentLoadTrigger = triggerData.cpTrigger
                            self:debug("Starting to load %s", 
                                g_fillTypeManager:getFillTypeNameByIndex(fillType))
                            return
                        end
                    end
                    if missingFillTypes[fillType] then 
                        self:setMaxSpeed(0)
                        self:debugSparse("Waiting at trigger for fill type: %s", 
                            g_fillTypeManager:getFillTypeNameByIndex(fillType))
                    end
                end
            end
        end
    else 
        local trigger = self.currentLoadTrigger:getTrigger()
        local fillType = trigger.selectedFillType
        local object = trigger.currentFillableObject
        local fillUnitIndex = trigger.fillUnitIndex
         --- Checks if stopping is necessary?
         for _, fillTypeSetting in pairs(self.fillTypeSettings) do 
            if fillTypeSetting.fillType:getValue() == fillType then
                if fillTypeSetting.maxFillLevel:getValue() <
                    object:getFillUnitFillLevelPercentage(fillUnitIndex) * 100 then
                    --- Stops the loading
                    self:debug("Finished loading of %s", 
                            g_fillTypeManager:getFillTypeNameByIndex(fillType))
                    self:setMaxSpeed(0)
                    trigger:setIsLoading(false)
                    self.isLoading = false
                    self.currentLoadTrigger = nil
                    return
                end
            end
        end
        self:setMaxSpeed(0)
        self:debugSparse("Currently loading %s", 
            g_fillTypeManager:getFillTypeNameByIndex(trigger.currentFillType))
        return
    end
end

function AIDriveStrategyStreetDriveLoading:onLoadingFinished(trigger)
    self.isLoading = false
    self.currentLoadTrigger = nil
end

local function loadingAtLoadTriggerHasStopped(trigger)
    if trigger.isLoading then 
        if trigger.currentFillableObject 
            and trigger.currentFillableObject.rootVehicle.getIsCpActive 
            and trigger.currentFillableObject.rootVehicle:getIsCpActive() then 
            local strategy = trigger.currentFillableObject.rootVehicle:getCpDriveStrategy()
            if strategy and strategy.onLoadingFinished then 
                strategy:onLoadingFinished(trigger)
            end
        end
    end
end
LoadTrigger.stopLoading = Utils.prependedFunction(LoadTrigger.stopLoading, loadingAtLoadTriggerHasStopped)

local function enableLoadingAtLoadTriggers(trigger, superFunc, fillableObject)
    if fillableObject and fillableObject.rootVehicle:getIsAIActive() then 
        return true
    end
    superFunc(trigger, fillableObject)
end
LoadTrigger.getAllowsActivation = Utils.overwrittenFunction(LoadTrigger.getAllowsActivation, enableLoadingAtLoadTriggers)