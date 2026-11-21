-- Run from the repository root: lua scripts/test/ManualUnloaderIntegrationTest.lua
dofile('scripts/CpObject.lua')
g_currentModName='FS25_Courseplay'
CpDebug={DBG_FIELDWORK=1,DBG_UNLOAD=2}
CpUtil={debugVehicle=function() end}
ImplementUtil={isChopper=function(object) return object.chopper end}
AIFieldWorker={}
Utils={overwrittenFunction=function(original) return original end}
dofile('scripts/specializations/CpAIFieldWorker.lua')
local tests=0
local function test(name,callback)
    callback()
    tests=tests+1
    print('PASS '..name)
end
local constructions,deletions,requests=0,0,0
CpManualCombineProxy=function()
    constructions=constructions+1
    return {delete=function() deletions=deletions+1 end,update=function() end}
end
CpManualUnloaderEvent={sendEvent=function() requests=requests+1 end}
local function vehicle(server)
    local object={isServer=server,spec_combine={},spec_pipe={},cpActive=false}
    object['spec_'..CpAIFieldWorker.SPEC_NAME]={}
    object.getChildVehicles=function(self) return {self} end
    object.getIsCpActive=function(self) return self.cpActive end
    return setmetatable(object,{__index=CpAIFieldWorker})
end
test('server creates one proxy for repeated activation',function()
    local object=vehicle(true)
    object:cpSetManualUnloaderActive(true)
    object:cpSetManualUnloaderActive(true)
    assert(constructions==1 and requests==1 and object:cpGetManualCombineProxy())
end)
test('client requests activation without running proxy AI',function()
    local object=vehicle(false)
    object:cpSetManualUnloaderActive(true)
    assert(constructions==1 and requests==2 and not object:cpGetManualCombineProxy())
    assert(not object:cpIsManualCombineCallingUnloader())
    object:cpSetManualUnloaderActive(true,true)
    assert(object:cpIsManualCombineCallingUnloader() and not object:cpGetManualCombineProxy())
end)
test('CP takeover deletes the manual proxy once',function()
    local object=vehicle(true)
    object:cpSetManualUnloaderActive(true,true)
    object.cpActive=true
    object:onUpdate(16)
    assert(not object:cpIsManualCombineCallingUnloader() and deletions==1)
    object:onDelete()
    assert(deletions==1)
end)
test('unsupported equipment is rejected and choppers can activate',function()
    local object=vehicle(true)
    object.spec_combine=nil
    assert(not object:cpCanCallManualUnloader())
    object:cpSetManualUnloaderActive(true,true)
    assert(not object:cpGetManualCombineProxy())
    object.spec_combine={}
    object.chopper=true
    assert(not object:cpCanCallManualUnloader())
    object.spec_pipe.numAutoAimingStates=1
    assert(object:cpCanCallManualUnloader())
end)
test('late joining client receives active state without a proxy',function()
    local written
    streamWriteBool=function(_,value) written=value end
    local server=vehicle(true)
    server:cpSetManualUnloaderActive(true,true)
    server:onWriteStream(1,{getIsServer=function() return false end})
    streamReadBool=function() return written end
    local client=vehicle(false)
    client:onReadStream(1,{getIsServer=function() return true end})
    assert(client:cpIsManualCombineCallingUnloader() and not client:cpGetManualCombineProxy())
end)

Class=function(class,base) return {__index=class} end
Event={new=function(mt) return setmetatable({},mt) end}
InitEventClass=function() end
dofile('scripts/events/CpManualUnloaderEvent.lua')
test('server broadcasts accepted state after rejecting activation',function()
    local object=vehicle(true)
    object.cpActive=true
    local result
    g_server={broadcastEvent=function(_,event) result=event.active end}
    CpManualUnloaderEvent.new(object,true):run({getIsServer=function() return false end})
    assert(result==false and not object:cpIsManualCombineCallingUnloader())
end)

dofile('scripts/ai/CpManualCombineProxy.lua')
PipeController={PIPE_STATE_CLOSED=1,PIPE_STATE_OPEN=2}
Dischargeable={DISCHARGE_STATE_OFF=0}
test('temporary loss of discharge does not finish a loaded combine',function()
    local active,fill=true,20
    local proxy=setmetatable({pipeSpec={numStates=2,currentState=2},pipeImplement={
        getDischargeNodeByIndex=function() return {fillUnitIndex=1} end,
        getPipeDischargeNodeIndex=function() return 1 end,
        getDischargeState=function() return active and 1 or 0 end,
        getFillUnitFillLevel=function() return fill end}}, {__index=CpManualCombineProxy})
    g_time=0
    assert(not proxy:isUnloadFinished())
    active=false
    g_time=5000
    assert(not proxy:isUnloadFinished())
    fill=0
    assert(not proxy:isUnloadFinished())
    g_time=7000
    assert(proxy:isUnloadFinished())
end)
test('closing the pipe finishes a partial unload after settling',function()
    local proxy=setmetatable({pipeSpec={numStates=2,currentState=1},pipeImplement={
        getDischargeNodeByIndex=function() return {fillUnitIndex=1} end,
        getPipeDischargeNodeIndex=function() return 1 end,
        getDischargeState=function() return 0 end,
        getFillUnitFillLevel=function() return 20 end}}, {__index=CpManualCombineProxy})
    g_time=0
    assert(not proxy:isUnloadFinished())
    g_time=2000
    assert(proxy:isUnloadFinished())
end)
test('releasing an old unloader preserves the current assignment',function()
    local assigned={}
    local proxy=setmetatable({unloader={get=function() return assigned end,
        reset=function() assigned=nil end}}, {__index=CpManualCombineProxy})
    proxy:deregisterUnloader({})
    assert(assigned)
    proxy:deregisterUnloader(assigned)
    assert(not assigned)
end)
test('empty or closed manual combine does not repeatedly recall an unloader',function()
    local fill=0
    local proxy=setmetatable({pipeSpec={numStates=2,currentState=2},pipeImplement={
        getDischargeNodeByIndex=function() return {fillUnitIndex=1} end,
        getPipeDischargeNodeIndex=function() return 1 end,
        getFillUnitFillLevel=function() return fill end}}, {__index=CpManualCombineProxy})
    assert(not proxy:isReadyToUnload())
    fill=20
    assert(proxy:isReadyToUnload())
    proxy.pipeSpec.currentState=1
    assert(not proxy:isReadyToUnload())
end)
test('deleting the proxy releases its assigned driver',function()
    local object={}
    local released=false
    local proxy=setmetatable({vehicle=object,unloader={get=function() return {
        combineToUnload=object,startWaitingForSomethingToDo=function() released=true end} end}},
        {__index=CpManualCombineProxy})
    proxy:delete()
    assert(released)
end)
AIDriveStrategyCourse=CpObject()
AIDriveStrategyCourse.myStates={}
dofile('scripts/ai/strategies/AIDriveStrategyUnloadCombine.lua')
test('CP combine with the manual API remains a CP combine',function()
    local strategy=setmetatable({combineToUnload={cpGetManualCombineProxy=function() return nil end,
        getCpDriveStrategy=function() return {} end}}, {__index=AIDriveStrategyUnloadCombine})
    assert(not strategy:isManualCombine())
    strategy.combineToUnload.cpGetManualCombineProxy=function() return {isManualProxy=function() return true end} end
    assert(strategy:isManualCombine())
end)
print('Manual unloader integration tests: '..tests..' passed')
