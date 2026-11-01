-- Run from the repository root: lua scripts/test/OrchardJobTest.lua
dofile('scripts/CpObject.lua')
CpAIJob={}
dofile('scripts/ai/jobs/CpAIJobFieldWork.lua')
CpDebug={DBG_FIELDWORK=1}
CpUtil={debugVehicle=function() end}
local polygon={{x=0,z=0},{x=10,z=0},{x=10,z=10},{x=0,z=10}}
local detected,scanError=false,nil
local scans=0
g_vineScanner={
    findVineNodesInField=function(_,p,x,z)
        assert(p==polygon and x==1 and z==2)
        scans=scans+1
        return detected
    end,
    getScanError=function() return scanError end,
    getCourseGeneratorVertices=function() return polygon,3,{x=1,z=2},0 end,
    getLines=function() return {} end
}
local vehicle={cpGetFieldPosition=function() return 1,2 end,
    cpGetFieldPolygon=function() return polygon end,
    cpGetIslandPolygons=function() return {} end,
    cpIsFieldBoundaryDetectionRunning=function() return false end,
    getCourseGeneratorSettings=function() return {} end,
    getCpVineSettings=function() return {
        vineCenterOffset={getValue=function() return 0 end},
        vineRowsToSkip={getValue=function() return 0 end}} end}
local callbacks={}
local normal,vines=0,0
local job=setmetatable({
    vehicleParameter={getVehicle=function() return vehicle end},
    getVehicle=function() return vehicle end,
    cpJobParameters={fieldPosition={getPosition=function() return 1,2 end}},
    selectedFieldPlot={setVisible=function() end,setWaypoints=function() end},
    callFieldBoundaryDetectionFinishedCallback=function(_,ok,error)
        table.insert(callbacks,{ok=ok,error=error})
    end,
    courseGeneratorInterface={
        startGeneration=function() normal=normal+1 end,
        generateVineCourse=function() vines=vines+1;return true,'course' end}
},{__index=CpAIJobFieldWork})
job:onFieldBoundaryDetectionFinished(vehicle,nil)
assert(#callbacks==1 and not callbacks[1].ok)
scanError='CP_error_plantation_unsupported'
job:onFieldBoundaryDetectionFinished(vehicle,polygon)
assert(#callbacks==2 and not callbacks[2].ok and not job:getCanGenerateFieldWorkCourse())
local completed=0
assert(not job:onClickGenerateFieldWorkCourse(function(course) assert(course==nil);completed=completed+1 end))
assert(completed==1 and normal==0 and vines==0)
scanError=nil
job:onFieldBoundaryDetectionFinished(vehicle,polygon)
assert(job:getCanGenerateFieldWorkCourse())
job.foundVines=true -- a previous preview must not determine this generation
job:onClickGenerateFieldWorkCourse(function() end)
assert(normal==1 and vines==0)
detected=true
AIUtil={getTurningRadius=function() return 6 end}
job:onClickGenerateFieldWorkCourse(function(course) assert(course=='course');completed=completed+1 end)
assert(vines==1 and completed==2 and scans==5)
print('Orchard job error, callback and shared scanner checks passed')
