-- Run from scripts/courseGenerator/test: lua OrchardCourseTest.lua
require('include')
require('CenterPredefinedRows')
require('FieldworkCourseVine')
-- Suppress diagnostics; standalone Lua 5.1 does not stringify %s arguments as GIANTS does.
Logger.log=function() end
local format=string.format
string.format=function(pattern,...)
    local args={...}
    for i=1,select('#',...) do
        if type(args[i])~='number' and type(args[i])~='string' then args[i]=tostring(args[i]) end
    end
    return format(pattern,unpack(args))
end
CpDebug={DBG_COURSES=1}
dofile('../../field/VineScanner.lua')

local lines={{x1=0,z1=0,x2=0,z2=100},{x1=3,z1=20,x2=3,z2=60},preserveEndpoints=true}
local rows=CourseGenerator.FieldworkCourseVine.generateRows(3,lines,true)
assert(#rows==1 and rows[1][1].y==-20 and rows[1][2].y==-60)
local headland={getBoundaryId=function() return 1 end}
local sections=rows[1]:split(headland,{},false,false)
assert(#sections==1)
sections[1]:adjustLength({})
assert(sections[1][1].y==-20 and sections[1][2].y==-60)
sections[1]:setAllAttributes()
local cloned=sections[1]:clone()
cloned:adjustLength({})
assert(cloned[1].y==-20 and cloned[2].y==-60)
local field=CourseGenerator.Field('orchard-test',0,{{x=-2,y=1},{x=5,y=1},{x=5,y=-101},{x=-2,y=-101}})
local context=CourseGenerator.FieldworkContext(field,3,6,0)
context:setAutoRowAngle(false)
context:setRowAngle(math.pi/2)
context:setStartLocation(0,0)
context:setBypassIslands(false)
local course=CourseGenerator.FieldworkCourseVine(context,CourseGenerator.FieldworkCourseVine.generateRows(3,lines,false))
local blocks=course.center:getBlocks()
local count=0
for _,block in ipairs(blocks) do
    for _,row in ipairs(block:getRows()) do
        local first,last=row[1],row[#row]
        local lo,hi=math.min(first.y,last.y),math.max(first.y,last.y)
        assert((math.abs(lo+100)<0.01 and math.abs(hi)<0.01) or (math.abs(lo+60)<0.01 and math.abs(hi+20)<0.01))
        count=count+1
    end
end
assert(count==2)

print('Orchard full generator regression passed')
