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
localDirectionToWorld=function(node,x,y,z)
    local angle=math.rad(node.angle or 0)
    return math.cos(angle)*x+math.sin(angle)*z,y,-math.sin(angle)*x+math.cos(angle)*z
end
localToWorld=function(node,x,y,z)
    local dx,dy,dz=localDirectionToWorld(node,x,y,z)
    return (node.x or 0)+dx,dy,(node.z or 0)+dz
end
worldToLocal=function(node,x,y,z)
    local angle=math.rad(node.angle or 0)
    local dx,dz=x-(node.x or 0),z-(node.z or 0)
    return math.cos(angle)*dx-math.sin(angle)*dz,y,math.sin(angle)*dx+math.cos(angle)*dz
end
localToLocal=function(from,to,x,y,z) return worldToLocal(to,localToWorld(from,x,y,z)) end
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
    harvester.getChildVehicles=function(self) return {self} end
    harvester.rootNode=harvester.node
    harvester.size={width=3,length=8}
    local proxy={vehicle=harvester,left=0,right=0,ready=true}
    proxy.hasAutoAimPipe=function() return false end
    proxy.getMeasuredBackDistance=function() return 4 end
    proxy.getFruitAtSides=function(self) return self.left,self.right end
    proxy.isReversing=function() return harvester.reversing or false end
    proxy.isReadyToUnload=function(self) return self.ready end
    local tractor={width=3,front={x=0,z=-10},node={x=0,z=-12}}
    tractor.getAIDirectionNode=function(self) return self.node end
    tractor.getChildVehicles=function(self) return {self} end
    tractor.rootNode=tractor.node
    tractor.size={width=3,length=4}
    local strategy={vehicle=tractor,maxDistanceWhenMovingOutOfWay=25,frontDistance=math.huge,
        rearDistance=math.huge,proxy=proxy,
        settings={turnSpeed=setting(5),fieldSpeed=setting(15),reverseSpeed=setting(5)},
        ppc={getNormalLookaheadDistance=function() return 5 end}}
    strategy.getAllTrailersFull=function() return false end
    strategy.driveUnloadNowRequested={get=function() return false end}
    strategy.proximityController={checkBlockingVehicleFront=function() return strategy.frontDistance end,
        checkBlockingVehicleBack=function() return strategy.rearDistance end}
    strategy.followModeProximitySensor={getClosestObjectDistanceAndRootVehicle=function()
        return strategy.frontDistance,nil,nil,false
    end}
    strategy.setMaxSpeed=function(self,value) self.speed=value end
    strategy.setInfoText=function(self) self.waiting=true end
    strategy.clearInfoText=function(self) self.waiting=false end
    strategy.getBestTargetNodeDistanceFromPipe=function() return 0 end
    strategy.getBestTargetNode=function() return nil end
    strategy.debugSparse=function() end
    strategy.debug=function() end
    return ManualChopperFollower(strategy,proxy),strategy,proxy
end
test('both sides clear initially selects a side instead of rear',function()
    local follower=fixture()
    assert(follower:getRequestedSide(-6)==1)
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
    g_time=1000
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
test('sensor metadata is excluded from numeric distance comparison',function()
    local follower,strategy=fixture()
    strategy.vehicle.front.z=-6
    strategy.followModeProximitySensor.getClosestObjectDistanceAndRootVehicle=function()
        return 20,nil,nil,false,0
    end
    follower:getDriveData()
    assert(math.abs(strategy.speed-5)<0.001)
    strategy.followModeProximitySensor.getClosestObjectDistanceAndRootVehicle=function()
        return 2,{},123,true,1
    end
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
    assert(strategy.speed>3 and strategy.speed<=8)
end)
test('unexpected heading change and a folded pipe hold the follower',function()
    local follower,strategy,proxy=fixture()
    strategy.vehicle.node.angle=120
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
    g_time=3000
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
local function curvedFixture(direction,side)
    side=side or 1
    local follower,strategy,proxy=fixture(side)
    for i=0,20 do
        local angle=i*0.05
        proxy.vehicle.node.x=direction*20*(1-math.cos(angle))
        proxy.vehicle.node.z=20*math.sin(angle)
        proxy.vehicle.node.angle=direction*math.deg(angle)
        ManualChopperFollower.recordPosition(proxy)
    end
    local x,z,dx,dz=follower:getGuidePosition(5,4*side)
    strategy.vehicle.front.x,strategy.vehicle.front.z=x,z
    strategy.vehicle.front.angle=math.deg(math.atan2(dx,dz))
    strategy.vehicle.node.x,strategy.vehicle.node.z=x-2*dx,z-2*dz
    strategy.vehicle.node.angle=strategy.vehicle.front.angle
    follower.side=side
    return follower,strategy,proxy
end
test('left-side unloader follows the recorded left-hand curve',function()
    local follower,strategy=curvedFixture(1)
    local x,z=follower:getDriveData()
    local steering=worldToLocal(strategy.vehicle.node,x,0,z)
    assert(strategy.speed>0 and steering>0 and not strategy.waiting)
end)
test('left-side unloader follows the recorded right-hand curve',function()
    local follower,strategy=curvedFixture(-1)
    local x,z=follower:getDriveData()
    local steering=worldToLocal(strategy.vehicle.node,x,0,z)
    assert(strategy.speed>0 and steering<0 and not strategy.waiting)
end)
test('right-side unloader follows the recorded left-hand curve',function()
    local follower,strategy=curvedFixture(1,-1)
    local x,z=follower:getDriveData()
    local steering=worldToLocal(strategy.vehicle.node,x,0,z)
    assert(strategy.speed>0 and steering>0 and not strategy.waiting)
end)
test('right-side unloader follows the recorded right-hand curve',function()
    local follower,strategy=curvedFixture(-1,-1)
    local x,z=follower:getDriveData()
    local steering=worldToLocal(strategy.vehicle.node,x,0,z)
    assert(strategy.speed>0 and steering<0 and not strategy.waiting)
end)
test('side following closes the trailer fill-node gap while lateral alignment is incomplete',function()
    local follower,strategy,proxy=fixture(1)
    follower.side=1
    strategy.vehicle.front.x=6
    strategy.getBestTargetNode=function() return {node={x=6,z=-20}} end
    strategy.getPipeOffset=function() return 4,0 end
    follower:getDriveData()
    assert(strategy.speed>5)
end)
test('assigned harvester beside the tractor does not falsely stop an inside curve',function()
    local follower,strategy,proxy=curvedFixture(1)
    strategy.followModeProximitySensor.getClosestObjectDistanceAndRootVehicle=function()
        return 1,proxy.vehicle,nil,false
    end
    assert(follower:hasHarvesterClearance())
    follower:getDriveData()
    assert(strategy.speed>0)
end)
test('overlapping vehicle footprints retain the harvester sensor stop',function()
    local follower,strategy,proxy=fixture(1)
    follower.side=1
    strategy.vehicle.node.x,strategy.vehicle.node.z=0,0
    strategy.followModeProximitySensor.getClosestObjectDistanceAndRootVehicle=function()
        return 1,proxy.vehicle,nil,false
    end
    assert(not follower:hasHarvesterClearance())
    follower:getDriveData()
    assert(strategy.speed==0)
end)
test('other vehicles remain obstacles during side following',function()
    local follower,strategy=curvedFixture(1)
    strategy.followModeProximitySensor.getClosestObjectDistanceAndRootVehicle=function()
        return 1,{},nil,false
    end
    follower:getDriveData()
    assert(strategy.speed==0)
end)
test('inside offset below the tractor turning radius selects the rear fallback',function()
    local follower,strategy,proxy=curvedFixture(1)
    strategy.turningRadius=18
    assert(follower:isInsideTightTurn(1))
    assert(follower:getRequestedSide(-6)==0)
end)
test('header width and footprint are included in side clearance',function()
    local follower,strategy,proxy=fixture(1)
    local header={width=9,rootNode={x=0,z=6},size={width=9,length=2}}
    proxy.vehicle.getChildVehicles=function(self) return {self,header} end
    strategy.vehicle.node.x,strategy.vehicle.node.z=4,6
    assert(follower:getSideOffset(1)==7)
    assert(not follower:hasHarvesterClearance())
end)
-- Simple planar pursuit model. It verifies continuous steering, not GIANTS trailer physics.
for _,autoAim in ipairs({false,true}) do
for _,direction in ipairs({1,-1}) do
    test('continuous side-following through curve direction '..direction..' autoAim='..tostring(autoAim),function()
        local follower,strategy,proxy=fixture(1)
        follower.side=1
        proxy.hasAutoAimPipe=function() return autoAim end
        strategy.turningRadius=6
        strategy.vehicle.node.x,strategy.vehicle.node.z,strategy.vehicle.node.angle=4,1,0
        local fill={}
        strategy.getBestTargetNode=function() return {node=fill} end
        strategy.getPipeOffset=function() return 4,-3 end
        local stops=0
        for i=0,399 do
            g_time=i*100
            local angle=direction*(5/3.6)*i*0.1/20
            proxy.vehicle.node.x=direction*20*(1-math.cos(angle))
            proxy.vehicle.node.z=direction*20*math.sin(angle)
            proxy.vehicle.node.angle=math.deg(angle)
            local x,_,z=localToWorld(strategy.vehicle.node,0,0,2)
            strategy.vehicle.front.x,strategy.vehicle.front.z=x,z
            strategy.vehicle.front.angle=strategy.vehicle.node.angle
            fill.x,_,fill.z=localToWorld(strategy.vehicle.node,0,0,-8)
            local gx,gz=follower:getDriveData()
            if strategy.speed==0 then stops=stops+1 end
            assert(gx and gz)
            local lx,_,lz=worldToLocal(strategy.vehicle.node,gx,0,gz)
            local curvature=2*lx/math.max(1,lx*lx+lz*lz)
            local speed=strategy.speed/3.6
            local heading=math.rad(strategy.vehicle.node.angle)+speed*curvature*0.1
            strategy.vehicle.node.angle=math.deg(heading)
            strategy.vehicle.node.x=strategy.vehicle.node.x+math.sin(heading)*speed*0.1
            strategy.vehicle.node.z=strategy.vehicle.node.z+math.cos(heading)*speed*0.1
        end
        assert(stops<5 and follower.phase=='FOLLOW')
        local x,_,z=localToLocal(fill,proxy.vehicle.node,0,0,0)
        local _, fillOffset=follower:projectOnGuide(fill)
        assert(math.abs(fillOffset-4)<1 and z < -3)
        local _,_,frontZ=localToLocal(strategy.vehicle.front,proxy.vehicle.node,0,0,0)
        assert(frontZ <= follower:getSideFrontLimit()+1)
    end)
end
end

test('rear follower closes a small gap more promptly without changing clearance',function()
    local follower,strategy=fixture(2)
    strategy.vehicle.front.z=-8
    follower:getDriveData()
    assert(math.abs(strategy.speed-10)<0.001)
end)

test('blocked corridor requests a new approach after persistent waiting',function()
    local follower,strategy=fixture()
    strategy.vehicle.front.z=-30
    crop=function() return true,1 end
    local calls=0
    strategy.startWaitingForSomethingToDo=function() calls=calls+1 end
    follower:getDriveData()
    g_time=2999
    follower:getDriveData()
    assert(calls==0)
    g_time=3000
    follower:getDriveData()
    assert(calls==1 and strategy.speed==0)
    g_time=7000
    follower:getDriveData()
    assert(calls==1)
end)

test('nearby or reversing choppers cannot trigger a fresh approach',function()
    local follower,strategy,proxy=fixture()
    local calls=0
    strategy.startWaitingForSomethingToDo=function() calls=calls+1 end
    follower:hold(true)
    g_time=4000
    follower:hold(true)
    assert(calls==0)
    strategy.vehicle.front.z=-30
    proxy.vehicle.reversing=true
    follower:hold(true)
    g_time=8000
    follower:hold(true)
    assert(calls==0 and follower.waitingSince==nil)
end)

test('resuming normal travel clears the waiting timer',function()
    local follower,strategy=fixture()
    follower:hold(true)
    g_time=2000
    follower:getDriveData()
    assert(strategy.speed>0 and follower.waitingSince==nil)
end)

test('cutter attachment limits tractor front independently of pipe target',function()
    local follower,strategy,proxy=fixture(1)
    local header={spec_cutter={},width=9}
    header.getActiveInputAttacherJoint=function() return {node={x=0,z=4}} end
    proxy.vehicle.getChildVehicles=function(self) return {self,header} end
    assert(follower:getSideFrontLimit()==3 and follower:getSideOffset(1)==7)
    follower.side=1
    strategy.vehicle.node.x,strategy.vehicle.front.x=7,7
    strategy.vehicle.node.z,strategy.vehicle.front.z=5,7
    strategy.getBestTargetNode=function() return {node={x=7,z=-3}} end
    strategy.getPipeOffset=function() return 7,-3 end
    follower:getDriveData()
    assert(strategy.speed==0)
    strategy.vehicle.node.z,strategy.vehicle.front.z=1,3
    follower:getDriveData()
    assert(math.abs(strategy.speed-5)<0.001)
end)

test('missing cutter joint uses the body front with a one metre margin',function()
    local follower=fixture()
    assert(follower:getSideFrontLimit()==3)
end)

test('auto aiming spout never controls longitudinal following via pipe position',function()
    local follower,strategy,proxy=fixture(1)
    follower.side=1
    proxy.hasAutoAimPipe=function() return true end
    strategy.vehicle.node.x,strategy.vehicle.front.x=4,4
    strategy.vehicle.node.z,strategy.vehicle.front.z=1,3
    strategy.getBestTargetNode=function() return {node={x=4,z=-20}} end
    strategy.getPipeOffset=function() error('auto aim must not read pipe position') end
    strategy.getBestTargetNodeDistanceFromPipe=function() error('auto aim must not chase pipe') end
    follower:getDriveData()
    assert(math.abs(strategy.speed-5)<0.001)
    strategy.getBestTargetNode=function() return nil end
    follower:getDriveData()
    assert(math.abs(strategy.speed-5)<0.001)
    strategy.vehicle.front.z=5
    follower:getDriveData()
    assert(strategy.speed==0)
end)

test('fixed pipe retains longitudinal trailer alignment behind the header limit',function()
    local follower,strategy,proxy=fixture(1)
    follower.side=1
    strategy.vehicle.node.x,strategy.vehicle.front.x=4,4
    strategy.vehicle.node.z,strategy.vehicle.front.z=-2,0
    local fill={x=4,z=-5}
    strategy.getBestTargetNode=function() return {node=fill} end
    strategy.getPipeOffset=function() return 4,-7 end
    follower:getDriveData()
    assert(strategy.speed==0)
    fill.z=-7
    follower:getDriveData()
    assert(math.abs(strategy.speed-5)<0.001)
end)

test('manual proxy identifies auto aim using the existing pipe state metadata',function()
    local proxy=setmetatable({pipeSpec={numAutoAimingStates=2}},{__index=CpManualCombineProxy})
    assert(proxy:hasAutoAimPipe())
    proxy.pipeSpec.numAutoAimingStates=0
    assert(not proxy:hasAutoAimPipe())
    proxy.pipeSpec={}
    assert(not proxy:hasAutoAimPipe())
    proxy.pipeSpec=nil
    assert(not proxy:hasAutoAimPipe())
end)

test('lateral manual offset works on both sides and behind with safety limits',function()
    local follower,strategy=fixture()
    strategy.settings.combineOffsetX=setting(2)
    assert(follower:getSideOffset(1)==3.5)
    assert(follower:getSideOffset(-1)==-6)
    assert(follower:getSideOffset(0)==-2)
    strategy.settings.combineOffsetX=setting(-2)
    assert(follower:getSideOffset(1)==6)
    assert(follower:getSideOffset(-1)==-3.5)
    assert(follower:getSideOffset(0)==2)
end)

test('auto aim longitudinal offset shifts the target without reading the pipe',function()
    local follower,strategy,proxy=fixture(1)
    follower.side=1
    proxy.hasAutoAimPipe=function() return true end
    strategy.vehicle.node.x,strategy.vehicle.front.x=4,4
    strategy.vehicle.node.z,strategy.vehicle.front.z=-2,0
    strategy.getPipeOffset=function() error('auto aim must not read pipe position') end
    strategy.settings.combineOffsetZ=setting(-3)
    follower:getDriveData()
    assert(math.abs(strategy.speed-5)<0.001)
    strategy.settings.combineOffsetZ=setting(-5)
    follower:getDriveData()
    assert(strategy.speed==0)
    strategy.settings.combineOffsetZ=setting(5)
    strategy.vehicle.front.z=5
    follower:getDriveData()
    assert(strategy.speed==0)
end)

test('rear longitudinal offset increases distance and cannot defeat rear clearance',function()
    local follower,strategy=fixture(2)
    strategy.settings.combineOffsetZ=setting(-3)
    strategy.vehicle.front.z=-9
    follower:getDriveData()
    assert(math.abs(strategy.speed-5)<0.001)
    strategy.settings.combineOffsetZ=setting(10)
    strategy.vehicle.front.z=-3
    follower:getDriveData()
    assert(strategy.speed==0)
end)

test('fixed pipe uses configured longitudinal offset once through existing strategy',function()
    local follower,strategy=fixture(1)
    follower.side=1
    strategy.vehicle.node.x,strategy.vehicle.front.x=4,4
    strategy.vehicle.node.z,strategy.vehicle.front.z=-2,0
    strategy.settings.combineOffsetZ=setting(-2)
    strategy.getBestTargetNode=function() return {node={x=4,z=-7}} end
    strategy.getPipeOffset=function(self) return 4,-5+self.settings.combineOffsetZ:getValue() end
    follower:getDriveData()
    assert(math.abs(strategy.speed-5)<0.001)
end)

test('diagonal corridor width is perpendicular to the checked path',function()
    local follower=fixture()
    local samples={}
    crop=function(x,z) table.insert(samples,{x=x,z=z}); return false end
    assert(follower:isCorridorClear(0,0,4,4))
    local a,b=samples[1],samples[3]
    assert(math.abs((b.x-a.x)*4+(b.z-a.z)*4)<0.001)
    assert(math.abs(MathUtil.vector2Length(b.x-a.x,b.z-a.z)-3.5)<0.001)
end)

test('cached corridor failures preserve the exact rejection point and cause',function()
    local follower=fixture()
    onField=function() return false end
    assert(not follower:isCorridorClear(0,-10,0,-5))
    local failure=follower.lastCorridorBlock
    assert(failure.reason=='off-field' and failure.x and failure.z)
    follower.lastCorridorBlock=nil
    assert(not follower:isCorridorClear(0,-10,0,-5))
    assert(follower.lastCorridorBlock==failure)
end)

test('alignment holds report measured angle and actual readiness',function()
    local follower,strategy=fixture()
    local message
    strategy.debug=function(self,format,...) message=string.format(format,...) end
    strategy.vehicle.node.angle=120
    follower:getDriveData()
    assert(message:find('reason=alignment',1,true) and message:find('angle=120.0',1,true))
end)

test('direct rear following can cross a crop-free field edge without replanning',function()
    local follower,strategy=fixture(2)
    onField=function() return false end
    strategy.startWaitingForSomethingToDo=function() error('near follower must not replan') end
    follower:getDriveData()
    assert(strategy.speed>0 and not strategy.waiting)
    g_time=5000
    follower:getDriveData()
    assert(strategy.speed>0 and not strategy.waiting)
end)

test('relaxed field membership does not bypass crop or unknown samples',function()
    local follower=fixture()
    onField=function() return false end
    crop=function() return true,50 end
    assert(not follower:isCorridorClear(0,-10,0,-5,true))
    assert(follower.lastCorridorBlock.reason=='fruit')
    g_time=300
    crop=function() return nil end
    assert(not follower:isCorridorClear(0,-10,0,-5,true))
    assert(follower.lastCorridorBlock.reason=='unknown-fruit')
end)

test('off-field policy has separate cache entries for side and direct corridors',function()
    local follower=fixture()
    onField=function() return false end
    assert(follower:isCorridorClear(0,-10,0,-5,true))
    assert(not follower:isCorridorClear(0,-10,0,-5))
    assert(follower:isCorridorClear(0,-10,0,-5,true))
end)

test('field-edge following still stops for a blocking vehicle',function()
    local follower,strategy=fixture(2)
    onField=function() return false end
    strategy.frontDistance=1
    follower:getDriveData()
    assert(strategy.speed==0)
end)

local function alignmentFixture()
    local follower,strategy,proxy=fixture(2)
    strategy.vehicle.node.x,strategy.vehicle.node.z,strategy.vehicle.node.angle=-10,-12,56.6
    local x,_,z=localToWorld(strategy.vehicle.node,0,0,2)
    strategy.vehicle.front.x,strategy.vehicle.front.z=x,z
    return follower,strategy,proxy
end

test('nearby tractor resumes normal following after reversing when a forward gap opens',function()
    local follower,strategy,proxy=alignmentFixture()
    proxy.vehicle.reversing=true
    follower:getDriveData()
    assert(strategy.speed==0 and proxy.chopperTrail==nil)
    proxy.vehicle.reversing=false
    local gx,gz=follower:getDriveData()
    assert(gx and gz and strategy.speed>3 and strategy.speed<=15 and not strategy.waiting)
    local _,_,forward=worldToLocal(strategy.vehicle.node,gx,0,gz)
    local _,_,goalZ=worldToLocal(proxy.vehicle.node,gx,0,gz)
    assert(forward>1)
end)

test('normal catch-up after reversing retains crop and vehicle checks',function()
    local follower,strategy=alignmentFixture()
    crop=function() return true,100 end
    follower:getDriveData()
    assert(strategy.speed==0 and strategy.waiting)
    g_time=300
    crop=function() return false end
    strategy.frontDistance=1
    follower:getDriveData()
    assert(strategy.speed==0 and strategy.waiting)
end)

test('normal catch-up still waits when too close or facing the opposite way',function()
    local follower,strategy=alignmentFixture()
    strategy.vehicle.front.z=-2
    follower:getDriveData()
    assert(strategy.speed==0)
    strategy.vehicle.front.z=-10
    strategy.vehicle.node.angle=100
    follower:getDriveData()
    assert(strategy.speed==0)
end)

test('distant alignment waits for the existing reassignment flow',function()
    local follower,strategy=alignmentFixture()
    strategy.vehicle.node.z,strategy.vehicle.front.z=-35,-33
    local calls=0
    strategy.startWaitingForSomethingToDo=function() calls=calls+1 end
    follower:getDriveData()
    assert(strategy.speed==0 and calls==0)
    g_time=3000
    follower:getDriveData()
    assert(calls==1)
end)

for _,sign in ipairs({1,-1}) do
    test('continuous recovery restores rear following from a diagonal position '..sign,function()
        local follower,strategy,proxy=alignmentFixture()
        strategy.vehicle.node.x=-10*sign
        strategy.vehicle.node.angle=56.6*sign
        proxy.vehicle.lastSpeedReal=5/3600
        for i=0,799 do
            proxy.vehicle.node.z=(5/3.6)*i*0.1
            g_time=i*100
            local x,_,z=localToWorld(strategy.vehicle.node,0,0,2)
            strategy.vehicle.front.x,strategy.vehicle.front.z=x,z
            local gx,gz=follower:getDriveData()
            assert(gx and gz)
            local lx,_,lz=worldToLocal(strategy.vehicle.node,gx,0,gz)
            local curvature=2*lx/math.max(1,lx*lx+lz*lz)
            local speed=strategy.speed/3.6
            local angle=math.rad(strategy.vehicle.node.angle)+speed*curvature*0.1
            strategy.vehicle.node.angle=math.deg(angle)
            strategy.vehicle.node.x=strategy.vehicle.node.x+math.sin(angle)*speed*0.1
            strategy.vehicle.node.z=strategy.vehicle.node.z+math.cos(angle)*speed*0.1
        end
        assert(follower.alignmentAngle<10 and math.abs(strategy.vehicle.node.x)<1, string.format('angle=%.2f x=%.2f z=%.2f front=%.2f reason=%s',follower.alignmentAngle,strategy.vehicle.node.x,strategy.vehicle.node.z,strategy.vehicle.front.z,tostring(follower.lastWaitReason)))
        local _,_,frontZ=worldToLocal(proxy.vehicle.node,strategy.vehicle.front.x,0,strategy.vehicle.front.z)
        assert(frontZ<=-5.5 and frontZ>-8)
    end)
end

test('misaligned follower waits for forward movement and the normal rear gap',function()
    local follower,strategy,proxy=alignmentFixture()
    proxy.vehicle.lastSpeedReal=0
    follower:getDriveData()
    assert(strategy.speed==0 and strategy.waiting)
    proxy.vehicle.lastSpeedReal=5/3600
    strategy.vehicle.front.z=-7
    follower:getDriveData()
    assert(strategy.speed==0 and strategy.waiting)
    strategy.vehicle.front.z=-10
    follower:getDriveData()
    assert(strategy.speed>3 and not strategy.waiting)
end)

test('automatic rear follower selects the nearer free side in either direction',function()
    local follower,strategy=fixture()
    strategy.vehicle.front.x=-1
    assert(follower:getRequestedSide(-6)==-1)
    strategy.vehicle.front.x=1
    assert(follower:getRequestedSide(-6)==1)
end)

test('free side takes priority after the normal confirmation delay',function()
    local follower=fixture()
    follower:updateSide(-6)
    g_time=1500
    follower:updateSide(-6)
    assert(follower.phase=='FOLLOW')
    g_time=2000
    follower:updateSide(-6)
    assert(follower.phase=='FALL_BACK' and follower.targetSide==1)
end)

test('automatic side selection permits a crop-free verge but still rejects fruit',function()
    local follower,_,proxy=fixture()
    onField=function() return false end
    assert(follower:getRequestedSide(-6)==1)
    proxy.left=10
    assert(follower:getRequestedSide(-6)==-1)
    proxy.right=10
    assert(follower:getRequestedSide(-6)==0)
end)

test('side selection checks the whole corridor even when side samples are clear',function()
    local follower=fixture()
    crop=function(x) return x>0,100 end
    assert(follower:getRequestedSide(-6)==-1)
end)

test('automatic follower leaves rear position and reaches a free side during travel',function()
    local follower,strategy,proxy=fixture()
    proxy.hasAutoAimPipe=function() return true end
    local fill={}
    strategy.getBestTargetNode=function() return {node=fill} end
    for i=0,999 do
        g_time=i*100
        proxy.vehicle.node.z=(5/3.6)*i*0.1
        local x,_,z=localToWorld(strategy.vehicle.node,0,0,2)
        strategy.vehicle.front.x,strategy.vehicle.front.z=x,z
        fill.x,_,fill.z=localToWorld(strategy.vehicle.node,0,0,-8)
        local gx,gz=follower:getDriveData()
        assert(gx and gz)
        local lx,_,lz=worldToLocal(strategy.vehicle.node,gx,0,gz)
        local curvature=2*lx/math.max(1,lx*lx+lz*lz)
        local speed=strategy.speed/3.6
        local angle=math.rad(strategy.vehicle.node.angle or 0)+speed*curvature*0.1
        strategy.vehicle.node.angle=math.deg(angle)
        strategy.vehicle.node.x=strategy.vehicle.node.x+math.sin(angle)*speed*0.1
        strategy.vehicle.node.z=strategy.vehicle.node.z+math.cos(angle)*speed*0.1
    end
    assert(follower.side==1 and follower.phase=='FOLLOW')
    local _,offset=follower:projectOnGuide(fill)
    assert(math.abs(offset-4)<1)
end)

print('Manual chopper regression tests: '..tests..' passed')
