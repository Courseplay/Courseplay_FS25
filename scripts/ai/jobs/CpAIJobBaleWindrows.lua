--- Bale windrows job.
---
--- A fieldwork job whose course follows the windrows (straw/hay/grass swaths lying on the ground) instead
--- of generic up/down rows, so an attached baler is driven exactly over the product. Extends the fieldwork
--- job to reuse all of its driving, turning and implement control.
---
--- IMPORTANT: the windrow (ground product) detection is EXPENSIVE (it sweeps the whole field). It must run
--- ONLY on the explicit "generate course" action, never in the menu's validate/boundary-detection loop
--- (which fires every frame) -- otherwise the game scans the field every frame and freezes.
---@class CpAIJobBaleWindrows : CpAIJobFieldWork
CpAIJobBaleWindrows = CpObject(CpAIJobFieldWork)
CpAIJobBaleWindrows.name = "BALE_WINDROWS_CP"
CpAIJobBaleWindrows.jobName = "CP_job_baleWindrows"

--- Only available when a baler is attached (the fieldwork/bale-finder split: the bale finder collects
--- finished bales and explicitly excludes balers, this job makes bales from windrows).
function CpAIJobBaleWindrows:getIsAvailableForVehicle(vehicle, cpJobsAllowed)
    return CpAIJob.getIsAvailableForVehicle(self, vehicle, cpJobsAllowed)
        and vehicle.getCanStartCpBaleWindrows and vehicle:getCanStartCpBaleWindrows()
end

--- Field boundary detection runs on every menu validate, so keep this CHEAP: just show the field plot.
--- No vine scan, no windrow scan here (that is done once in onClickGenerateFieldWorkCourse).
function CpAIJobBaleWindrows:onFieldBoundaryDetectionFinished(vehicle, fieldPolygon, islandPolygons)
    if fieldPolygon then
        self.selectedFieldPlot:setWaypoints(fieldPolygon)
        self.selectedFieldPlot:setVisible(true)
        self:callFieldBoundaryDetectionFinishedCallback(true)
    else
        self.selectedFieldPlot:setVisible(false)
        self:callFieldBoundaryDetectionFinishedCallback(false, 'CP_error_field_detection_failed')
    end
end

--- The "generate course" button: detect the windrows ONCE and map a course tracing them.
function CpAIJobBaleWindrows:onClickGenerateFieldWorkCourse(callback)
    local vehicle = self.vehicleParameter:getVehicle()
    local fieldPolygon = vehicle:cpGetFieldPolygon()
    if not fieldPolygon then
        callback(nil)
        return true
    end

    local detector = WindrowDetector(fieldPolygon)
    local windrows, debugInfo = detector:findWindrows()
    local headlandRings = debugInfo.headlandRingDistances
    if #windrows == 0 and (not headlandRings or #headlandRings == 0) then
        self:debug('No windrows found on the field')
        callback(nil)
        return true
    end

    local _, course = self.courseGeneratorInterface:generateWindrowCourse(
            fieldPolygon, vehicle, windrows, headlandRings)
    self:debug('Mapped a course over %d windrows + %d headland rings',
            #windrows, headlandRings and #headlandRings or 0)
    callback(course)
    return true
end
