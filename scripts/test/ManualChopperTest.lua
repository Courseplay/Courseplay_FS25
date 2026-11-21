-- Run from the repository root: lua scripts/test/ManualChopperTest.lua
dofile('scripts/CpObject.lua')
CpDebug={}
CpUtil={debugVehicle=function() end}
MathUtil={vector2Length=function(x,z) return math.sqrt(x*x+z*z) end}
CpMathUtil={clamp=function(value,min,max) return math.max(min,math.min(max,value)) end,
    isSameDirection=function(a,b,limit) return math.abs((a.angle or 0)-(b.angle or 0))<=limit end}
AIUtil={getWidth=function(object) return object.width or 3 end,
    getFirstReversingImplementWithWheels=function(object) return object.trailer end,
    isReversing=function(object) return object.reversing or false end}
ImplementUtil={isChopper=function(object) return object.chopper or false end}
InfoTextManager={MANUAL_CHOPPER_WAITING=1}
PipeController={PIPE_STATE_OPEN=2,PIPE_STATE_CLOSED=1}
Markers={getFrontMarkerNode=function(object) return object.front end}
getWorldTranslation=function(node) return node.x or 0,0,node.z or 0 end
localToWorld=function(node,x,y,z) return (node.x or 0)+x,y,(node.z or 0)+z end
localToLocal=function(from,to,x,y,z) return (from.x or 0)+x-(to.x or 0),y,(from.z or 0)+z-(to.z or 0) end
local crop=function() return false,0 end
local onField=function() return true end
PathfinderUtil={hasFruit=function(...) return crop(...) end}
CpFieldUtil={isOnField=function(...) return onField(...) end}
dofile('scripts/ai/CpManualCombineProxy.lua')
dofile('scripts/ai/ManualChopperFollower.lua')
local tests=0
local function test(name,callback)
    crop=function() return false,0 end
    onField=function() return true end
    g_time=0
    callback()
    tests=tests+1
    print('PASS '..name)
end
local function setting(value) return {getValue=function() return value end} end
local function fixture(side)
    local harvester={width=3,node={x=0,z=0},lastSpeedReal=5/3600}
    harvester.getAIDirectionNode=function(self) return self.node end
    harvester.getCpSettings=function() return {manualChopperSide=setting(side or 0)} end
    local proxy={vehicle=harvester,left=0,right=0,ready=true}
    proxy.getMeasuredBackDistance=function() return 4 end
    proxy.getFruitAtSides=function(self) return self.left,self.right end
    proxy.isReversing=function() return harvester.reversing or false end
    proxy.isReadyToUnload=function(self) return self.ready end
    local tractor={width=3,front={x=0,z=-10},node={x=0,z=-12}}
    tractor.getAIDirectionNode=function(self) return self.node end
    tractor.getChildVehicles=function(self) return {self} end
    local strategy={vehicle=tractor,maxDistanceWhenMovingOutOfWay=25,frontDistance=math.huge,
        rearDistance=math.huge,proxy=proxy,
        settings={turnSpeed=setting(5),fieldSpeed=setting(15),reverseSpeed=setting(5)},
        ppc={getNormalLookaheadDistance=function() return 5 end}}
    strategy.getAllTrailersFull=function() return false end
    strategy.driveUnloadNowRequested={get=function() return false end}
    strategy.proximityController={checkBlockingVehicleFront=function() return strategy.frontDistance end,
        checkBlockingVehicleBack=function() return strategy.rearDistance end}
    strategy.followModeProximitySensor={getClosestObjectDistanceAndRootVehicle=function() return strategy.frontDistance end}
    strategy.setMaxSpeed=function(self,value) self.speed=value end
    strategy.setInfoText=function(self) self.waiting=true end
    strategy.clearInfoText=function(self) self.waiting=false end
    strategy.getBestTargetNodeDistanceFromPipe=function() return 0 end
    return ManualChopperFollower(strategy,proxy),strategy,proxy
end
test('both sides clear initially selects rear position',function()
    local follower=fixture()
    assert(follower:getRequestedSide(-6)==0)
end)
test('assignment beside the harvester retains the existing side',function()
    local _,strategy,proxy=fixture()
    strategy.vehicle.front.x=4
    strategy.vehicle.front.z=0
    local follower=ManualChopperFollower(strategy,proxy)
    assert(follower.side==1 and follower:getRequestedSide(-6)==1)
end)
test('automatic side selection avoids crop and preserves the usable side',function()
    local follower,_,proxy=fixture()
    proxy.left=10
    assert(follower:getRequestedSide(-6)==-1)
    follower.side=-1
    proxy.left=0
    assert(follower:getRequestedSide(-6)==-1)
end)
test('unknown crop samples fall back behind',function()
    local follower,_,proxy=fixture()
    proxy.left,proxy.right=nil,nil
    assert(follower:getRequestedSide(-6)==0)
end)
test('manual side choice cannot force entry into standing crop',function()
    local follower,_,proxy=fixture(1)
    proxy.left=20
    assert(follower:getRequestedSide(-6)==0)
end)
test('manual rear setting overrides a free side',function()
    local follower,_,proxy=fixture(2)
    proxy.left=20
    assert(follower:getRequestedSide(-6)==0)
end)
test('corridor check rejects off-field ground and unknown fruit detection',function()
    local follower=fixture()
    onField=function() return false end
    assert(not follower:isCorridorClear(0,-10,4,-6))
    onField=function() return true end
    crop=function() return nil end
    assert(not follower:isCorridorClear(0,-10,4,-6))
end)
test('corridor checks include trailer width',function()
    local follower,strategy=fixture()
    strategy.vehicle.getChildVehicles=function(self) return {self,{width=6}} end
    crop=function(x) return x>2.5,1 end
    assert(not follower:isCorridorClear(0,-10,0,-5))
end)
test('short crop fluctuations do not trigger a side change',function()
    local follower,_,proxy=fixture()
    proxy.left=10
    follower:updateSide(-6)
    g_time=500
    proxy.left=0
    follower:updateSide(-6)
    g_time=2500
    follower:updateSide(-6)
    assert(follower.phase=='FOLLOW' and follower.side==0)
end)
test('side change brakes first while beside the harvester',function()
    local follower,strategy,proxy=fixture(1)
    strategy.vehicle.front.z=0
    follower:getDriveData()
    g_time=2000
    local x=follower:getDriveData()
    assert(follower.phase=='FALL_BACK' and x==0 and strategy.speed==0)
    assert(follower.side==0)
end)
test('crossing behind uses a limited lateral steering target',function()
    local follower,strategy=fixture(1)
    follower:getDriveData()
    g_time=2000
    local x=follower:getDriveData()
    assert(follower.phase=='CROSS_BEHIND' and x>0 and x<=2.5)
    assert(strategy.speed<=5)
end)
test('rear following retains clearance and follows operator speed',function()
    local follower,strategy=fixture(2)
    strategy.vehicle.front.z=-6
    follower:getDriveData()
    assert(math.abs(strategy.speed-5)<0.001)
    strategy.vehicle.front.z=-3
    follower:getDriveData()
    assert(strategy.speed==0)
end)
test('stopped or reversing operator does not draw the unloader forward',function()
    local follower,strategy,proxy=fixture()
    proxy.vehicle.lastSpeedReal=0
    strategy.vehicle.front.z=-6
    follower:getDriveData()
    assert(strategy.speed==0)
    proxy.vehicle.reversing=true
    follower:getDriveData()
    assert(strategy.speed==0 and strategy.waiting)
end)
test('unloader can approach a stopped chopper before harvesting starts',function()
    local follower,strategy,proxy=fixture()
    strategy.vehicle.front.z=-25
    proxy.vehicle.lastSpeedReal=0
    follower:getDriveData()
    assert(strategy.speed>0 and strategy.speed<=3)
end)
test('unexpected heading change and a folded pipe hold the follower',function()
    local follower,strategy,proxy=fixture()
    strategy.vehicle.node.angle=60
    follower:getDriveData()
    assert(strategy.speed==0 and strategy.waiting)
    strategy.vehicle.node.angle=0
    proxy.ready=false
    follower:getDriveData()
    assert(strategy.speed==0)
end)
test('a distant manual turn releases the assignment for a fresh approach',function()
    local follower,strategy=fixture()
    strategy.vehicle.node.angle=60
    strategy.vehicle.front.z=-30
    local released=false
    strategy.startWaitingForSomethingToDo=function() released=true end
    follower:getDriveData()
    g_time=1500
    follower:getDriveData()
    assert(released and strategy.speed==0)
end)
test('rear obstacle and excessive trailer angle prevent reversing',function()
    local follower,strategy=fixture()
    assert(follower:canReverse())
    strategy.rearDistance=2
    assert(not follower:canReverse())
    strategy.rearDistance=math.huge
    strategy.vehicle.trailer={steeringAxleNode={angle=50}}
    assert(not follower:canReverse())
end)
test('reverse distance is bounded',function()
    local follower,strategy=fixture()
    strategy.manualChopperReverseStart={x=0,z=12}
    assert(not follower:canReverse())
end)
test('manual chopper stays ready without a bunker fill level',function()
    local proxy=setmetatable({pipeSpec={numStates=2,currentState=2},pipeImplement={chopper=true}},
        {__index=CpManualCombineProxy})
    assert(proxy:isReadyToUnload())
    assert(proxy:alwaysNeedsUnloader())
    assert(not proxy:isUnloadFinished())
    proxy.pipeSpec.currentState=0
    assert(not proxy:isReadyToUnload())
end)
test('reversing chopper cannot request another approaching unloader',function()
    local proxy=setmetatable({pipeImplement={chopper=true},vehicle={reversing=true}},
        {__index=CpManualCombineProxy})
    proxy:callUnloaderWhenNeeded()
end)
test('live reverse detection and fruit samples are exposed by the proxy',function()
    local proxy=setmetatable({vehicle={reversing=true,getAIDirectionNode=function() return {} end},
        getWorkWidth=function() return 6 end},{__index=CpManualCombineProxy})
    crop=function(x) return x>0,x>0 and 10 or 0 end
    proxy:checkChopperFruit()
    local left,right=proxy:getFruitAtSides()
    assert(left==30 and right==0 and proxy:isReversing())
end)

AIDriveStrategyCourse=CpObject()
dofile('scripts/ai/strategies/AIDriveStrategyUnloadCombine.lua')
test('manual chopper dispatch preserves the existing CP chopper path',function()
    local _,strategy,proxy=fixture()
    setmetatable(strategy,{__index=AIDriveStrategyUnloadCombine})
    strategy.isManualChopper=function() return true end
    strategy.changeToUnloadWhenTrailerFull=function() return false end
    strategy.getCombineStrategy=function() return proxy end
    proxy.isManualChopper=function() return true end
    strategy:unloadMovingChopper()
    assert(strategy.manualChopperFollower and strategy.speed>0)
    strategy.manualChopperFollower=nil
    strategy.isManualChopper=function() return false end
    strategy.getFollowingCourseOffset=function() return 0 end
    strategy.followCourse={setOffset=function() end}
    strategy.isInDeadlock=function() return false end
    strategy.followChopper=function() return 10,20 end
    proxy.isTurning=function() return false end
    local x,z=strategy:unloadMovingChopper()
    assert(x==10 and z==20 and not strategy.manualChopperFollower)
end)
test('manual reverse request only starts with clear ground behind',function()
    local _,strategy,proxy=fixture()
    setmetatable(strategy,{__index=AIDriveStrategyUnloadCombine})
    strategy.combineToUnload=proxy.vehicle
    strategy.states={UNLOADING_MOVING_COMBINE=1,UNLOADING_STOPPED_COMBINE=2,BACKING_UP_FOR_REVERSING_COMBINE=3}
    strategy.state=1
    strategy.isManualChopper=function() return true end
    strategy.getCombineStrategy=function() return proxy end
    strategy.getPipeOffsetReferenceNode=function() return proxy.vehicle.node end
    local requested=0
    strategy.requestToBackupForReversingCombine=function(self) requested=requested+1;self.state=3 end
    proxy.vehicle.reversing=true
    strategy.rearDistance=2
    strategy:updateManualChopperReverse()
    assert(requested==0 and strategy.waiting)
    strategy.rearDistance=math.huge
    strategy:updateManualChopperReverse()
    assert(requested==1 and strategy.manualChopperReverseStart)
end)
test('full trailer waits before reversing out into a blocked area',function()
    local _,strategy,proxy=fixture()
    setmetatable(strategy,{__index=AIDriveStrategyUnloadCombine})
    strategy.isManualChopper=function() return true end
    strategy.getCombineStrategy=function() return proxy end
    strategy.getAllTrailersFull=function() return true end
    local departures=0
    strategy.changeToUnloadWhenTrailerFull=function() departures=departures+1;return true end
    strategy.rearDistance=2
    strategy:unloadMovingChopper()
    assert(departures==0 and strategy.speed==0 and strategy.waiting)
    strategy.rearDistance=math.huge
    strategy:unloadMovingChopper()
    assert(departures==1)
end)
print('Manual chopper regression tests: '..tests..' passed')
