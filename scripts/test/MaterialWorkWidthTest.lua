-- Run from the repository root: lua scripts/test/MaterialWorkWidthTest.lua
-- Regression tests for signed variable widths and deferred material updates.
g_currentModName='FS25_Courseplay'
CpDebug={DBG_IMPLEMENTS=1}
CpUtil={debugImplement=function() end,debugVehicle=function() end,
    getSoilSamplerSpecName=function() return 'spec_soilSampler' end}
MathUtil={equalEpsilon=function(a,b,eps) return math.abs(a-b)<eps end}
VehicleStateChange={FILLTYPE_CHANGE=1}
VehiclePropertyState={SHOP_CONFIG=10}
Utils={appendedFunction=function(original,callback)
    return function(...)
        local result=original and original(...)
        callback(...)
        return result
    end
end}
g_vehicleConfigurations={get=function() return nil end}
VariableWorkWidth={updateSections=function() return 'sections' end}
Sprayer={onSprayTypeChange=function(object,mode)
    object.spec_variableWorkWidth.isActive=mode.supportsVariableWorkWidth
    return 'mode'
end}
AIUtil={hasChildVehicleWithSpecialization=function() return true end}
dofile('scripts/ai/util/WorkWidthUtil.lua')
dofile('scripts/specializations/CpVehicleSettings.lua')
dofile('scripts/specializations/CpCourseGeneratorSettings.lua')

local tests=0
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local function test(name,f)
    g_updateLoopIndex=1
    g_vehicleConfigurations.get=function() return nil end
    f(); tests=tests+1; print('PASS '..name)
end
local function setting(value)
    return {value=value,events=0,refreshes=0,getValue=function(self) return self.value end,
        refresh=function(self) self.refreshes=self.refreshes+1 end,
        setFloatValue=function(self,v,epsilon,noEvent)
            self.value=v
            if not noEvent then self.events=self.events+1 end
        end}
end
local function spreader(left,right,active)
    return {rootNode=2,spec_variableWorkWidth={isActive=active~=false},
        getVariableWorkWidth=function(self,isLeft) return isLeft and left or right,99,true end,
        updateAIMarkerWidth=function() end,
        getAIMarkers=function() return 3,4,5,false,12 end,
        getAIImplementSideOffset=function() return 0 end}
end
local function vehicle(implement,width)
    local workWidth=setting(width or 36)
    local offset=setting(0)
    local root={rootNode=1,isServer=true,spec_cpVehicleSettings={finishedFirstUpdate=true},
        getIsSynchronized=function() return true end,
        getCourseGeneratorSettings=function() return {workWidth=workWidth} end,
        getCpSettings=function() return {toolOffsetX=offset} end,
        getAttachedImplements=function() return {{object=implement}} end}
    root.rootVehicle=root; implement.rootVehicle=root
    return root,workWidth,offset
end
local function update(root,loop)
    g_updateLoopIndex=loop
    CpVehicleSettings.updatePendingWorkWidth(root)
end

test('GIANTS absolute half-widths become the full CP width',function()
    local width,offset,left,right=WorkWidthUtil.getAutomaticWorkWidthAndOffset(spreader(18,18))
    eq(width,36); eq(offset,0); eq(left,18); eq(right,-18)
end)
test('asymmetric sections produce width and lateral offset',function()
    local width,offset,left,right=WorkWidthUtil.getAutomaticWorkWidthAndOffset(spreader(18,12))
    eq(width,30); eq(offset,3); eq(left,18); eq(right,-12)
end)
test('one disabled half remains a valid half-width',function()
    local width,offset=WorkWidthUtil.getAutomaticWorkWidthAndOffset(spreader(0,12))
    eq(width,12); eq(offset,-6)
end)
test('fully disabled sections do not fall back to the wide markers',function()
    local width=WorkWidthUtil.getAutomaticWorkWidthAndOffset(spreader(0,0))
    eq(width,0)
end)
test('inactive variable width uses the current lime AI marker width',function()
    local width,offset=WorkWidthUtil.getAutomaticWorkWidthAndOffset(spreader(18,18,false))
    eq(width,12); eq(offset,0)
end)
test('invalid variable sections still fall back to AI markers',function()
    local i=spreader(18,18)
    i.getVariableWorkWidth=function() return 1,1,false end
    eq(WorkWidthUtil.getAutomaticWorkWidthAndOffset(i),12)
end)
test('tractor inherits attached spreader full width',function()
    local root=vehicle(spreader(18,18))
    eq(WorkWidthUtil.getAutomaticWorkWidthAndOffset(root),36)
end)
test('explicit vehicle width configuration retains priority',function()
    local i=spreader(18,18)
    g_vehicleConfigurations.get=function(self,object,name) if object==i and name=='workingWidth' then return 24 end end
    eq(WorkWidthUtil.getAutomaticWorkWidthAndOffset(i),24)
end)
test('explicit lateral configuration remains effective',function()
    local i=spreader(18,18)
    g_vehicleConfigurations.get=function(self,object,name) if name=='toolOffsetX' then return 2 end end
    local width,offset,left,right=WorkWidthUtil.getAutomaticWorkWidthAndOffset(i)
    eq(width,36); eq(offset,2); eq(left,20); eq(right,-16)
end)
test('fill type event defers calculation to a later update',function()
    local i=spreader(18,18); local root,width=vehicle(i)
    CpVehicleSettings.onStateChange(root,VehicleStateChange.FILLTYPE_CHANGE,{})
    eq(width.value,36); eq(width.events,0)
    update(root,1); eq(width.events,0)
    i.spec_variableWorkWidth.isActive=false
    update(root,2); eq(width.value,12); eq(width.events,1); eq(width.refreshes,1)
end)
test('fertilizer to lime to fertilizer updates HUD/generator setting',function()
    local i=spreader(18,18); local root,width=vehicle(i)
    eq(Sprayer.onSprayTypeChange(i,{supportsVariableWorkWidth=false}),'mode')
    eq(width.value,36)
    update(root,2); eq(width.value,12)
    Sprayer.onSprayTypeChange(i,{supportsVariableWorkWidth=true})
    update(root,3); eq(width.value,36); eq(width.events,2)
end)
test('section event sees final geometry and updates automatic offset',function()
    local i=spreader(18,12); local root,width,offset=vehicle(i)
    eq(VariableWorkWidth.updateSections(i),'sections')
    update(root,2); eq(width.value,30); eq(offset.value,3); eq(offset.events,1)
end)
test('material-only update preserves manually entered tool offset',function()
    local i=spreader(18,18,false); local root,width,offset=vehicle(i)
    offset.value=1.2
    CpVehicleSettings.requestWorkWidthUpdate(i,false)
    update(root,2); eq(width.value,12); eq(offset.value,1.2); eq(offset.events,0)
end)
test('repeated section/material events coalesce without losing offset request',function()
    local i=spreader(18,12); local root,width,offset=vehicle(i)
    CpVehicleSettings.requestWorkWidthUpdate(i,true)
    CpVehicleSettings.requestWorkWidthUpdate(i,false)
    update(root,2); eq(width.events,1); eq(offset.events,1)
    update(root,3); eq(width.events,1); eq(offset.events,1)
end)
test('change below one meter is not silently ignored',function()
    local i=spreader(6.2,6.2); local root,width=vehicle(i,12)
    CpVehicleSettings.requestWorkWidthUpdate(i,false)
    update(root,2); eq(width.value,12.4); eq(width.events,1)
end)
test('zero unresolved width does not overwrite a usable setting',function()
    local i=spreader(0,0); local root,width=vehicle(i,12)
    CpVehicleSettings.requestWorkWidthUpdate(i,false)
    update(root,2); eq(width.value,12); eq(width.events,0)
end)
test('identical width sends no redundant setting event',function()
    local i=spreader(18,18); local root,width=vehicle(i,36)
    CpVehicleSettings.requestWorkWidthUpdate(i,false)
    update(root,2); eq(width.value,36); eq(width.events,0)
end)
test('unsynchronized vehicle waits before applying setting',function()
    local i=spreader(18,18,false); local root,width=vehicle(i)
    local synced=false; root.getIsSynchronized=function() return synced end
    CpVehicleSettings.requestWorkWidthUpdate(i,false)
    update(root,2); eq(width.value,36); assert(root.spec_cpVehicleSettings.workWidthUpdate)
    synced=true; update(root,3); eq(width.value,12)
end)
test('clients leave authoritative width changes to the server',function()
    local i=spreader(18,18,false); local root,width=vehicle(i)
    root.isServer=false
    CpVehicleSettings.requestWorkWidthUpdate(i,false)
    update(root,2); eq(width.value,36); eq(width.events,0); eq(root.spec_cpVehicleSettings.workWidthUpdate,nil)
end)
test('non-CP root is ignored by the engine callback',function()
    local i=spreader(18,18); i.rootVehicle={isServer=true}
    CpCourseGeneratorSettings.onVariableWorkWidthSectionChanged(i)
end)
test('normal vehicle update processes pending width',function()
    local i=spreader(18,18,false); local root,width=vehicle(i)
    CpVehicleSettings.requestWorkWidthUpdate(i,false)
    g_updateLoopIndex=2
    CpVehicleSettings.onUpdate(root)
    eq(width.value,12)
end)
print('Material work width regression tests: '..tests..' passed')
