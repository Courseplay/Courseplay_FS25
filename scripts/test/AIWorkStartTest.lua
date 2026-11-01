-- Run from the repository root: lua scripts/test/AIWorkStartTest.lua
-- Standalone regression tests with GIANTS engine stand-ins. No game required.
CpDebug = {DBG_FIELDWORK=1, DBG_IMPLEMENTS=2}
CpUtil = {debugImplement=function() end}
VehicleStateChange = {AI_START_LINE=1}
Utils = {overwrittenFunction=function(original, replacement) return original end}
VariableWorkWidth = {}
AIDriveStrategyFieldCourse = {}
Cutter = {}
dofile("scripts/CpObject.lua")
dofile("scripts/ai/controllers/ImplementController.lua")
dofile("scripts/ai/strategies/AIDriveStrategyCourse.lua")
dofile("scripts/ai/strategies/AIDriveStrategyFieldWorkCourse.lua")
dofile("scripts/ai/strategies/AIDriveStrategyCombineCourse.lua")
dofile("scripts/ai/strategies/AIDriveStrategyPlowCourse.lua")
dofile("scripts/ai/strategies/AIDriveStrategyUnloadCombine.lua")
dofile("scripts/ai/controllers/PipeController.lua")
dofile("scripts/ai/controllers/CutterController.lua")
dofile("scripts/ai/controllers/MotorController.lua")
local tests = 0
local function test(name, f)
    f()
    tests = tests + 1
    print('PASS ' .. name)
end
local function eq(actual, expected)
    assert(actual == expected, tostring(actual) .. ' ~= ' .. tostring(expected))
end
local function strategy(cls)
    g_time, g_updateLoopIndex = 0, 0
    local events = {}
    local vehicle = {
        getChildVehicles=function(self) return {self, self.child} end,
        getAttachedAIImplements=function(self) return {{object=self.child}} end,
        raiseAIEvent=function(self, a, b) table.insert(events, {a, b, g_updateLoopIndex}) end,
        raiseStateChange=function() end,
        child={aiImplementStartLine=function() table.insert(events, {'LOWER', nil, g_updateLoopIndex}) end}
    }
    local s = setmetatable({vehicle=vehicle, controllers={}, events=events,
        debug=function() end,
        ppc={getGoalPointPosition=function() return 10, 0, 20 end, isReversing=function() return false end},
        setMaxSpeed=function(self, speed) self.speed=speed end,
    }, {__index=cls or AIDriveStrategyCourse})
    return s
end
local function tick(s, time, loop)
    g_time, g_updateLoopIndex = time, loop
    return s:updateAIWorkStart()
end

test('minimum delay, event order and repeated calls in same update', function()
    local s = strategy()
    s:beginAIWorkStart()
    eq(tick(s, 0, 0), false)
    eq(tick(s, 49, 1), false)
    eq(#s.events, 0)
    eq(tick(s, 50, 2), false)
    eq(s.events[1][1], 'onAIFieldWorkerStart')
    eq(tick(s, 50, 2), false)
    eq(#s.events, 1)
    eq(tick(s, 60, 3), false)
    eq(s.events[2][1], 'onAIFieldWorkerPrepareForWork')
    eq(tick(s, 60, 3), false)
    eq(tick(s, 70, 4), true)
    eq(tick(s, 70, 4), true)
    eq(#s.events, 2)
end)

test('pending measurement on root blocks startup, including settling interval', function()
    local s = strategy()
    s:beginAIWorkStart()
    s.vehicle.cpPipeMeasurementRestore = function() end
    eq(tick(s, 100, 1), false)
    eq(#s.events, 0)
    s.vehicle.cpPipeMeasurementRestore = nil
    s.vehicle.cpPipeMeasurementFinishedAt = 110
    eq(tick(s, 159, 2), false)
    eq(tick(s, 160, 3), false)
    eq(#s.events, 1)
end)

test('pending measurement on attached implement blocks startup', function()
    local s = strategy()
    s:beginAIWorkStart()
    s.vehicle.child.cpPipeMeasurementRestore = function() end
    eq(tick(s, 100, 1), false)
    eq(#s.events, 0)
end)

test('waits for preparation animation before releasing work', function()
    local s = strategy()
    s:beginAIWorkStart()
    tick(s, 50, 1)
    tick(s, 60, 2)
    s.vehicle.child.getIsAIPreparingToDrive = function() return true end
    eq(tick(s, 70, 3), false)
    eq(tick(s, 1000, 4), false)
    s.vehicle.child.getIsAIPreparingToDrive = function() return false end
    eq(tick(s, 1010, 5), true)
end)

test('rejected preparation retries GIANTS action with its requested direction', function()
    local s = strategy()
    local permitted, finished, calls = false, false, 0
    local action = {name='fold', aiEventListener={{eventName='onAIImplementPrepareForWork',direction=1}},
        getIsFinished=function(self,direction) eq(direction,1); return finished end,
        doAction=function(self,direction,isAI)
            eq(direction,1); eq(isAI,true); calls=calls+1
            if permitted then finished=true end
        end}
    s.vehicle.actionController={actions={action}}
    s:beginAIWorkStart()
    tick(s,50,1); tick(s,60,2)
    eq(tick(s,70,3),false); eq(calls,0)
    eq(tick(s,560,4),false); eq(calls,1)
    eq(tick(s,570,5),false); eq(calls,1)
    permitted=true
    eq(tick(s,1060,6),false); eq(calls,2)
    eq(tick(s,1060,6),false)
    eq(tick(s,1070,7),true)
end)

test('unrelated and already completed actions are not retried', function()
    local s = strategy()
    local calls=0
    s.vehicle.actionController={actions={
        {aiEventListener={{eventName='onAIImplementStart',direction=-1}},
            getIsFinished=function() error('unrelated action queried') end},
        {aiEventListener={{eventName='onAIImplementPrepareForWork',direction=1}},
            getIsFinished=function() return true end,doAction=function() calls=calls+1 end}}}
    s:beginAIWorkStart(); tick(s,50,1); tick(s,60,2)
    eq(tick(s,1000,3),true); eq(calls,0)
end)

for _, phase in ipairs({'before start', 'after start', 'after prepare'}) do
    test('stop cancels startup ' .. phase, function()
        local s = strategy()
        s:beginAIWorkStart()
        if phase ~= 'before start' then tick(s, 50, 1) end
        if phase == 'after prepare' then tick(s, 60, 2) end
        local count = #s.events
        s:cancelAIWorkStart()
        eq(tick(s, 5000, 100), false)
        eq(#s.events, count)
        s:lowerImplements()
        eq(#s.events, count)
    end)
end

test('restart begins a fresh sequence without old actions', function()
    local s = strategy()
    s:beginAIWorkStart()
    tick(s, 50, 1)
    s:lowerImplements()
    s:cancelAIWorkStart()
    s:beginAIWorkStart()
    eq(tick(s, 99, 2), false)
    tick(s, 100, 3)
    tick(s, 110, 4)
    eq(tick(s, 120, 5), true)
    eq(#s.events, 3)
end)

test('waypoint lowering is deferred until after preparation', function()
    local s = strategy()
    s:beginAIWorkStart()
    s:lowerImplements()
    s:lowerImplements()
    eq(#s.events, 0)
    tick(s, 50, 1)
    tick(s, 60, 2)
    eq(tick(s, 70, 3), true)
    eq(#s.events, 3)
    eq(s.events[3][1], 'LOWER')
    assert(s.events[3][3] > s.events[2][3])
end)

test('alignment setup cannot prepare before start', function()
    local s = strategy(AIDriveStrategyFieldWorkCourse)
    s:beginAIWorkStart()
    s:prepareForFieldWork()
    eq(#s.events, 0)
    tick(s, 50, 1)
    tick(s, 60, 2)
    tick(s, 70, 3)
    s:prepareForFieldWork()
    eq(#s.events, 3) -- Later preparation requests must still work.
end)

test('field worker lowers once after shared startup without duplicate preparation', function()
    local s=strategy(AIDriveStrategyFieldWorkCourse)
    s.states=AIDriveStrategyFieldWorkCourse.myStates
    s.states.INITIAL={}
    s.state=s.states.INITIAL
    s.updateFieldworkOffset=function() end
    s.setAITarget=function() end; s.limitSpeed=function() end
    s.checkProximitySensors=function() end; s.checkDistanceToOtherFieldWorkers=function() end
    s.getCanContinueWork=function() return true end
    Markers={refreshMarkerNodes=function() end}
    s:beginAIWorkStart()
    s:getDriveData(16,0,0,0)
    g_time,g_updateLoopIndex=50,1; s:getDriveData(16,0,0,0)
    g_time,g_updateLoopIndex=60,2; s:getDriveData(16,0,0,0)
    g_time,g_updateLoopIndex=70,3; s:getDriveData(16,0,0,0)
    eq(s.state,s.states.PREPARING)
    g_time,g_updateLoopIndex=80,4; s:getDriveData(16,0,0,0)
    eq(s.state,s.states.WAITING_FOR_LOWER_DELAYED)
    eq(#s.events,3); eq(s.events[3][1],'LOWER')
    g_time,g_updateLoopIndex=90,5; s:getDriveData(16,0,0,0)
    eq(s.state,s.states.WAITING_FOR_LOWER)
    g_time,g_updateLoopIndex=100,6; s:getDriveData(16,0,0,0)
    eq(s.state,s.states.WORKING)
    eq(#s.events,3)
end)

for name, cls in pairs({field=AIDriveStrategyFieldWorkCourse, combine=AIDriveStrategyCombineCourse,
    plow=AIDriveStrategyPlowCourse, unloader=AIDriveStrategyUnloadCombine}) do
    test(name .. ' drive data blocks before pipe/controller/state work', function()
        local s = strategy(cls)
        s:beginAIWorkStart()
        local x,z,forward,speed = s:getDriveData(16, 0,0,0)
        eq(x,10); eq(z,20); eq(forward,true); eq(speed,0)
        eq(#s.events,0)
    end)
end

test('periodic controller work suppressed during startup and after cancel', function()
    local s = strategy()
    local calls = 0
    s.controllers={{isEnabled=function() return true end, getDriveData=function() calls=calls+1 end,
        update=function() calls=calls+1 end}}
    s:beginAIWorkStart()
    s:updateImplementControllers(16)
    s:updateLowFrequencyImplementControllers()
    eq(calls,0)
    s:cancelAIWorkStart()
    s:updateImplementControllers(16)
    s:updateLowFrequencyImplementControllers()
    eq(calls,0)
end)

-- Run real resetFold/measurePipeProperties against stateful engine stand-ins.
local timers
local function pipe(folded, current, target, anim, foldDirection)
    timers = {}
    Timer = {createOneshot=function(ms, f)
        local timer={callback=f, delete=function(self) self.deleted=true end}
        table.insert(timers,timer)
        return timer
    end}
    Foldable={setAnimTime=function(implement,t) implement.spec_foldable.foldAnimTime=t end}
    AnimatedVehicle={updateAnimations=function() end}
    local spec={currentState=current, targetState=target, animation={name='pipe'}}
    local impl={spec_pipe=spec, anim=anim, turnedOn=true,
        spec_foldable={turnOnFoldDirection=1, foldAnimTime=folded and 0 or 1, foldMoveDirection=foldDirection or 0},
        setAnimationTime=function(self,name,time) self.anim=time end,
        getAnimationTime=function(self,name) assert(name); return self.anim end,
        setPipeState=function(self,state,noEventSend)
            eq(noEventSend,true)
            self.spec_pipe.targetState=state
            self.spec_pipe.currentState=state
            self.turnedOn=false -- Simulate the measurement side effect.
        end,
        updatePipeNodes=function() end,
        setFoldDirection=function(self,direction,noEventSend) eq(noEventSend,true); self.direction=direction end,
        getIsTurnedOn=function(self) return self.turnedOn end,
        setIsTurnedOn=function(self,on,noEventSend) eq(noEventSend,true); self.turnedOn=on end,
        getAIDirectionNode=function() return 1 end,
    }
    local c=setmetatable({implement=impl, vehicle=impl, pipeSpec=spec,foldableSpec=impl.spec_foldable,
        debug=function() end, printFoldableDebug=function() end,printPipeDebug=function() end,
        getDischargeNode=function() return {node=2} end,
    },{__index=PipeController})
    localToLocal=function() return 5,0,-2 end
    g_vehicleConfigurations={get=function() return nil end}
    return c,impl
end

test('folded measurement restores original pipe, direction and turn-on after controller deletion',function()
    g_time=100
    local c,i=pipe(true,1,1,0,0)
    c:measurePipeProperties()
    assert(i.cpPipeMeasurementRestore)
    c=nil -- Temporary measurement controllers do not own restoration.
    g_time=101
    timers[1].callback()
    eq(i.cpPipeMeasurementRestore,nil)
    eq(i.direction,0); eq(i.anim,0); eq(i.spec_pipe.targetState,1); eq(i.turnedOn,true)
    eq(i.cpPipeMeasurementFinishedAt,101)
end)

test('overlapping measurements flush old restoration and ignore stale callbacks',function()
    local c,i=pipe(true,1,1,0,0)
    c:measurePipeProperties()
    local old=timers[1]
    c:measurePipeProperties()
    assert(old.deleted)
    local latest=i.cpPipeMeasurementRestore
    old.callback()
    eq(i.cpPipeMeasurementRestore,latest)
    timers[2].callback()
    eq(i.cpPipeMeasurementRestore,nil)
    eq(i.anim,0); eq(i.direction,0); eq(i.turnedOn,true)
end)

test('folded measurement preserves opening target and original animation',function()
    local c,i=pipe(true,0,2,0.3,1)
    c:measurePipeProperties()
    timers[1].callback()
    eq(i.spec_pipe.targetState,2); eq(i.anim,0.3); eq(i.direction,1)
end)

test('unfolded measurement restores closed pipe without deferred work',function()
    local c,i=pipe(false,1,1,0,0)
    c:measurePipeProperties()
    eq(i.cpPipeMeasurementRestore,nil)
    eq(i.spec_pipe.targetState,1); eq(i.anim,0); eq(i.turnedOn,true)
end)

test('already open pipe is not folded or closed by measurement',function()
    local c,i=pipe(false,2,2,1,0)
    c:measurePipeProperties()
    eq(#timers,0); eq(i.spec_pipe.targetState,2); eq(i.anim,1); eq(i.turnedOn,true)
end)

test('pipe without animation or foldable specialization can be measured',function()
    local c,i=pipe(false,1,1,0,0)
    c.foldableSpec=nil; i.spec_foldable=nil; i.spec_pipe.animation.name=nil
    c:measurePipeProperties()
    eq(i.spec_pipe.targetState,1); eq(i.turnedOn,true)
end)

test('configured offset also updates pipe side',function()
    local c,i=pipe(false,2,2,1,0)
    g_vehicleConfigurations.get=function() return -3 end
    c:measurePipeProperties()
    eq(c.pipeOffsetX,-3); eq(c.pipeOnLeftSide,false)
end)

test('pipe controller refreshes offsets measured after construction',function()
    local c,i=pipe(false,2,2,1,0)
    i.getCpSettings=function() return {pipeOffsetX={getValue=function() return -4 end},
        pipeOffsetZ={getValue=function() return 2 end}} end
    c.pipeOffsetX,c.pipeOffsetZ=0,0
    c:onStart()
    eq(c.pipeOffsetX,-4); eq(c.pipeOffsetZ,2); eq(c.pipeOnLeftSide,false)
end)

test('motor starts through startup lifecycle before preparation',function()
    local started,calls=false,0
    local c=setmetatable({getIsStarted=function() return started end,
        startMotor=function() started=true; calls=calls+1 end},{__index=MotorController})
    c:onStart(); eq(started,true); eq(calls,1)
    c:onStart(); eq(calls,1)
end)

test('cutter waits for GIANTS turn-on permission',function()
    local allowed=false
    local i={getIsTurnedOn=function() return false end, getIsLowered=function() return true end,
        getCanBeTurnedOn=function() return allowed end, setIsTurnedOn=function(self,on) self.on=on end}
    local c=setmetatable({implement=i,driveStrategy={}}, {__index=CutterController})
    c:getDriveData(); eq(i.on,nil)
    allowed=true
    c:getDriveData(); eq(i.on,true)
end)

print('Startup/measurement regression tests: ' .. tests .. ' passed')
