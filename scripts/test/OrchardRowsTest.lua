-- Run from the repository root: lua scripts/test/OrchardRowsTest.lua
-- Physical row detection regressions; no game installation needed.
dofile('scripts/CpObject.lua')
dofile('scripts/util/CpMathUtil.lua')
MathUtil={getYRotationFromDirection=function(x,z) return math.atan2(x,z) end}
CpDebug={DBG_COURSES=1}
dofile('scripts/field/VineScanner.lua')

CpDebug={DBG_COURSES=1}
CpUtil={debugVehicle=function() end,getCurrentVehicle=function() end,error=function() end}
getWorldTranslation=function(n) return n.x,0,n.z end
localToWorld=function(n,x,y,z)
    local yaw=n.yaw or 0
    return n.x+math.cos(yaw)*x+math.sin(yaw)*z,y,n.z-math.sin(yaw)*x+math.cos(yaw)*z
end
local function node(x,z,yaw) return {x=x,z=z,yaw=yaw or 0} end
local function row(x,z1,z2) return {x1=x,z1=z1,x2=x,z2=z2} end
local function addVines(system,x,z1,z2,spacing,crop,yaw)
    local n=node(x,z1+5,yaw)
    local segment=row(x,z1,z2)
    local p={spec_vine={width=spacing,vineSegments={[segment]={{node=n}}}},crop=crop}
    system.nodes[n]=p
    return p,n
end
local function addOrchard(system,x,z1,z2,spacing,crop,yaw)
    local n=node(x,z1+5,yaw)
    local segment={vineNodes={[n]=true},getStartPos=function() return x,0,z1 end,
        getEndPos=function() return x,0,z2 end}
    local p={typeName=crop, getOrchardRowSpacing=function() return spacing end,
        getFence=function() return {segments={segment}} end,crop=crop}
    system.nodes[n]=p
    return p,n
end
local function setup()
    g_currentMission={vineSystem={nodes={}}}
    local s=VineScanner()
    s:setup()
    s.debug=function() end
    return s,g_currentMission.vineSystem
end
local polygon={{x=-100,z=-100},{x=100,z=-100},{x=100,z=200},{x=-100,z=200}}
local result={}
local function run(name,build,expected)
    local s,system=setup()
    build(system)
    local ok,found=pcall(s.findVineNodesInField,s,polygon,0,5,false)
    local count=s.lines and #s.lines or 0
    result[#result+1]={name=name,ok=ok,found=ok and found or false,
        rows=count,expected=expected,error=not ok and tostring(found) or nil}
end
run('legacy grapes: five complete parallel rows',function(system)
    for j=0,4 do addVines(system,j*3,0,100,3,'grapes') end
end,5)
run('coffee adapter: five complete parallel rows',function(system)
    for j=0,4 do addOrchard(system,j*3.5,0,100,3.5,'coffee') end
end,5)
run('legacy grapes: shortened fifth row',function(system)
    for j=0,3 do addVines(system,j*3,0,100,3,'grapes') end
    addVines(system,12,20,100,3,'grapes')
end,5)
run('coffee adapter: shortened fifth row',function(system)
    for j=0,3 do addOrchard(system,j*3.5,0,100,3.5,'coffee') end
    addOrchard(system,14,20,100,3.5,'coffee')
end,5)
run('coffee adapter: plant nodes rotated relative to straight rows',function(system)
    for j=0,4 do addOrchard(system,j*3.5,0,100,3.5,'coffee',math.pi/2) end
end,5)
run('unsupported registered placeable',function(system)
    system.nodes[node(0,5)]={typeName='unsupported'}
end,0)
run('same spacing and direction, different crops',function(system)
    addVines(system,0,0,100,3,'grapes')
    addOrchard(system,3,0,100,3,'coffee')
end,1)
-- Failed scans must not leave geometry from a previous field available.
do
    local s,system=setup()
    for j=0,4 do addVines(system,j*3,0,100,3,'grapes') end
    assert(s:findVineNodesInField(polygon,0,5,false))
    local old=s.lines
    local n=node(0,5)
    local segment=row(0.5,0,100)
    system.nodes={[n]={spec_vine={width=3,vineSegments={[segment]={{node=n}}}}}}
    local ok,found=pcall(s.findVineNodesInField,s,polygon,0,5,false)
    result[#result+1]={name='failed scan after previous success',ok=ok,found=ok and found or false,
        staleGeometry=s.lines==old,rows=s.lines and #s.lines or 0,error=not ok and tostring(found) or nil}
end
-- Caller-owned custom-field polygons should stay unchanged between scans.
do
    local s,system=setup()
    addVines(system,0,0,100,3,'grapes')
    local poly={{x=-1,z=-1},{x=2,z=-1},{x=2,z=101},{x=-1,z=101}}
    s:findVineNodesInField(poly,0,5,true)
    s:findVineNodesInField(poly,0,5,true)
    result[#result+1]={name='two scans of the same custom polygon',vertices=#poly,expected=4}
end
-- Full segment geometry must not run outside a deliberately selected subarea.
do
    local s,system=setup()
    addOrchard(system,0,0,100,3.5,'coffee')
    local poly={{x=-1,z=0},{x=1,z=0},{x=1,z=10},{x=-1,z=10}}
    local ok,found=pcall(s.findVineNodesInField,s,poly,0,5,false)
    local l=s.lines and s.lines[1]
    result[#result+1]={name='selected custom area contains first ten meters of one long row',ok=ok,
        found=ok and found or false,endZ=l and math.max(l.z1,l.z2),expectedMaxZ=10,
        error=not ok and tostring(found) or nil}
end
for _,r in ipairs(result) do
    assert(r.ok~=false,r.name)
    if r.expected then assert((r.rows or r.vertices)==r.expected,r.name) end
    assert(not r.staleGeometry,r.name)
    if r.expectedMaxZ then assert(r.endZ==r.expectedMaxZ,r.name) end
end
print('Orchard row regression fixtures: '..#result..' passed')


CpDebug={DBG_COURSES=1}
CpUtil={debugVehicle=function() end,getCurrentVehicle=function() end,error=function() end}
getWorldTranslation=function(n) return n.x,0,n.z end
localToWorld=function(n,x,y,z)
    local yaw=n.yaw or 0
    return n.x+math.cos(yaw)*x+math.sin(yaw)*z,y,n.z-math.sin(yaw)*x+math.cos(yaw)*z
end
local function node(x,z,yaw) return {x=x,z=z,yaw=yaw or 0} end
local function row(x,z1,z2) return {x1=x,z1=z1,x2=x,z2=z2} end
local function addVines(system,x,z1,z2,spacing,crop,yaw)
    local n=node(x,z1+5,yaw)
    local segment=row(x,z1,z2)
    local p={spec_vine={width=spacing,vineSegments={[segment]={{node=n}}}},crop=crop}
    system.nodes[n]=p
    return p,n
end
local function addOrchard(system,x,z1,z2,spacing,crop,yaw)
    local n=node(x,z1+5,yaw)
    local segment={vineNodes={[n]=true},getStartPos=function() return x,0,z1 end,
        getEndPos=function() return x,0,z2 end}
    local p={typeName=crop, getOrchardRowSpacing=function() return spacing end,
        getFence=function() return {segments={segment}} end,crop=crop}
    system.nodes[n]=p
    return p,n
end
local function setup()
    g_currentMission={vineSystem={nodes={}}}
    local s=VineScanner()
    s:setup()
    s.debug=function() end
    return s,g_currentMission.vineSystem
end
local polygon={{x=-100,z=-100},{x=100,z=-100},{x=100,z=200},{x=-100,z=200}}

local s,system=setup()
for j=0,4 do addOrchard(system,j*3.5,0,j==4 and 50 or 100,3.5,'coffee') end
assert(s:findVineNodesInField(polygon,0,5,false))
assert(s.lines[5].z2==50)
local driving=VineScanner.createDrivingLines(s.lines,3.5,true)
assert(#driving==4 and driving[4].z2==50)
assert(s:getCourseGeneratorVertices(1,0,5))
assert(s:hasVineNodesCloseBy(14,49))
system.nodes={}
assert(not s:findVineNodesInField(polygon,0,5,false) and not s.lines)
local n=node(0,5)
system.nodes[n]={typeName='unknown'}
assert(not s:findVineNodesInField(polygon,0,5,false))
assert(s:getScanError()=='CP_error_plantation_unsupported')
system.nodes={}
addVines(system,0,0,10,3,'grapes')
addVines(system,0,20,100,3,'grapes')
assert(not s:findVineNodesInField(polygon,0,5,false))
assert(s:getScanError()=='CP_error_plantation_layout')
print('Orchard overlap and error checks passed')
