--- Bale windrows job.
---
--- Detects the field and the windrows (straw/hay/grass swaths lying on the ground) on it, then generates a
--- fieldwork course whose rows follow those windrows, so an attached baler is driven exactly over the
--- product. Extends the fieldwork job to reuse all of its driving, turning and implement control; the only
--- new behaviour is that the course is generated automatically from the detected windrows (instead of the
--- generic up/down rows) as soon as the field boundary is known.
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

--- Once the field boundary is detected, detect the windrows and build a course following them.
--- Replaces the fieldwork/vine handling with windrow handling.
function CpAIJobBaleWindrows:onFieldBoundaryDetectionFinished(vehicle, fieldPolygon, islandPolygons)
    if not fieldPolygon then
        self.selectedFieldPlot:setVisible(false)
        self:callFieldBoundaryDetectionFinishedCallback(false, 'CP_error_field_detection_failed')
        return
    end
    self.selectedFieldPlot:setWaypoints(fieldPolygon)
    self.selectedFieldPlot:setVisible(true)
    local ok, errorMessage = self:generateWindrowCourse(vehicle, fieldPolygon)
    if ok then
        self:callFieldBoundaryDetectionFinishedCallback(true)
    else
        self:callFieldBoundaryDetectionFinishedCallback(false, errorMessage)
    end
end

--- Detect the windrows in the field and generate a course following them.
---@return boolean ok
---@return string errorMessage i18n key, set when ok is false
function CpAIJobBaleWindrows:generateWindrowCourse(vehicle, fieldPolygon)
    local settings = vehicle:getCourseGeneratorSettings()
    local workWidth = settings.workWidth:getValue()

    local detector = WindrowDetector(fieldPolygon)
    local windrows = detector:findWindrows()
    if #windrows == 0 then
        self:debug('No windrows found on the field')
        return false, 'CP_error_no_windrows'
    end

    local lines = {}
    for _, w in ipairs(windrows) do
        lines[#lines + 1] = { x1 = w.x1, z1 = w.z1, x2 = w.x2, z2 = w.z2 }
    end

    local tx, tz = self.cpJobParameters.fieldPosition:getPosition()
    local ok = self.courseGeneratorInterface:generateWindrowCourse(
            fieldPolygon, { x = tx, z = tz }, vehicle, workWidth, AIUtil.getTurningRadius(vehicle), lines, 1)
    if not ok then
        self:debug('Windrow course generation failed for %d windrows', #windrows)
        return false, 'CP_error_no_windrows'
    end
    self:debug('Generated a bale-windrow course over %d windrows', #windrows)
    return true, ''
end
