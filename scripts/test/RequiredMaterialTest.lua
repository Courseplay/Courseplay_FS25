-- Run from the repository root: lua scripts/test/RequiredMaterialTest.lua
-- Executes the real CP controllers/task against small GIANTS interface stand-ins.
dofile('scripts/CpObject.lua')
CpDebug = {DBG_FIELDWORK=1, DBG_IMPLEMENTS=2}
CpUtil = {debugVehicle=function() end, debugImplement=function() end}
g_currentModName = 'FS25_Courseplay'
Utils = {overwrittenFunction=function(superFunc, callback)
    return function(self, ...) return callback(self, superFunc, ...) end
end}
Sprayer = {onStartWorkAreaProcessing=function() end, processSprayerArea=function() return 'sprayer' end}
FertilizingSowingMachine = {processSowingMachineArea=function() return 'sowing' end}
FertilizingCultivator = {processCultivatorArea=function() return 'cultivator' end}
VariableWorkWidth = {}
AIDriveStrategyFieldCourse = {}
AIMessageErrorOutOfFill = {new=function() return 'OUT_OF_FILL' end}
InfoTextManager = {NEEDS_FILLING='NEEDS_FILLING'}
CpTemporaryObject = function()
    return {set=function() end, get=function() return true end}
end
dofile('scripts/ai/util/ImplementUtil.lua')
dofile('scripts/ai/controllers/ImplementController.lua')
dofile('scripts/ai/controllers/SowingMachineController.lua')
dofile('scripts/ai/controllers/SprayerController.lua')
dofile('scripts/ai/controllers/FertilizingSowingMachineController.lua')
dofile('scripts/ai/controllers/FertilizingCultivatorController.lua')
dofile('scripts/ai/strategies/AIDriveStrategyCourse.lua')
dofile('scripts/ai/strategies/AIDriveStrategyFieldWorkCourse.lua')
dofile('scripts/ai/tasks/CpAITask.lua')
dofile('scripts/ai/tasks/CpAITaskFieldWork.lua')
dofile('scripts/specializations/CpVehicleSettings.lua')

local tests=0
local function test(name,f)
    g_currentMission={missionInfo={helperBuySeeds=false,helperBuyFertilizer=false,
        helperSlurrySource=1,helperManureSource=1}}
    f()
    tests=tests+1
    print('PASS '..name)
end
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local function settings(seed,fertilizer)
    return {optionalSowingMachineEnabled={getValue=function() return seed end,
        getIsDisabled=function() return false end},
        sowingMachineFertilizerEnabled={getValue=function() return fertilizer end}}
end
local function tank(amount,fillType)
    return {amount=amount,fillType=fillType,capacity=100,
        getFillUnitFillLevel=function(self) return self.amount end,
        getFillUnitFillType=function(self) return self.fillType end,
        getFillUnitCapacity=function(self) return self.capacity end}
end
local function seeder(optional,amount)
    local i=tank(amount,1)
    i.spec_sowingMachine={fillUnitIndex=1,seedFillType=1,fillTypeSources={},workAreaParameters={}}
    i.getAIRequiresTurnOn=function() return not optional end
    i.getIsTurnedOn=function(self) return self.on end
    i.setIsTurnedOn=function(self,on) self.on=on end
    i.getCanBeTurnedOn=function() return true end
    i.getCanPlantOutsideSeason=function() return true end
    return i
end
local function sprayer(amount,combination)
    local i=tank(amount,2)
    i.spec_sprayer={supportedSprayTypes={2,3},fillTypeSources={},allowsSpraying=true,
        workAreaParameters={sprayFillLevel=0,lastAIHasSprayed=true}}
    if combination then i.spec_fertilizingSowingMachine={} end
    i.getSprayerFillUnitIndex=function() return 1 end
    i.getIsSprayerExternallyFilled=function(self)
        local info=g_currentMission.missionInfo
        return self.external or (self.spec_sprayer.isFertilizerSprayer and info.helperBuyFertilizer) or
            (self.spec_sprayer.isSlurryTanker and info.helperSlurrySource>1) or
            (self.spec_sprayer.isManureSpreader and info.helperManureSource>1) or false
    end
    return i
end
local function rootVehicle(cpSettings)
    return {getCpSettings=function() return cpSettings end}
end
local function sController(i,cpSettings)
    return SowingMachineController(rootVehicle(cpSettings),i)
end
local function pController(i,cpSettings)
    return SprayerController(rootVehicle(cpSettings),i)
end

test('required seeder empty is detected even when hidden optional switch is off',function()
    eq(sController(seeder(false,0),settings(false,false)):getIsRequiredMaterialMissing(),true)
end)
test('required seeder with seed is ready',function()
    eq(sController(seeder(false,1),settings(false,false)):getIsRequiredMaterialMissing(),false)
end)
test('base-game seed purchase satisfies seed supply',function()
    g_currentMission.missionInfo.helperBuySeeds=true
    eq(sController(seeder(false,0),settings(false,false)):getIsRequiredMaterialMissing(),false)
end)
test('disabled optional seeding needs no seed',function()
    local c=sController(seeder(true,0),settings(false,true))
    eq(c:getIsRequiredMaterialMissing(),false); eq(c:isRefillingEnabled(),false)
end)
test('enabled optional seeding requires seed',function()
    eq(sController(seeder(true,0),settings(true,true)):getIsRequiredMaterialMissing(),true)
end)
test('seeder uses seed from compatible attached tank',function()
    local i=seeder(false,0); local source=tank(15,1)
    i.spec_sowingMachine.fillTypeSources[1]={{vehicle=source,fillUnitIndex=2},{vehicle=tank(0,1),fillUnitIndex=1}}
    local c=sController(i,settings(false,true))
    eq(c:getIsRequiredMaterialMissing(),false)
    assert(c.refillData.lastFillLevels[source][2]~=nil)
end)
test('wrong material in seed source does not satisfy seed supply',function()
    local i=seeder(false,0)
    i.spec_sowingMachine.fillTypeSources[1]={{vehicle=tank(20,2),fillUnitIndex=1}}
    eq(sController(i,settings(false,true)):getIsRequiredMaterialMissing(),true)
end)
test('zero-capacity seed tank is not offered for refill',function()
    local i=seeder(false,0); i.capacity=0
    local c=sController(i,settings(false,true))
    eq(next(c.refillData.lastFillLevels),nil)
    eq(c:getIsRequiredMaterialMissing(),true)
end)
test('consumable-based seeder uses GIANTS consumable availability',function()
    local i=seeder(false,0); i.spec_sowingMachine.consumableName='seeds'; i.spec_sowingMachine.fillUnitIndex=nil
    i.getConsumableIsAvailable=function() return true end
    local c=sController(i,settings(false,true)); eq(c:needsRefilling(),false)
    i.getConsumableIsAvailable=function() return false end; eq(c:needsRefilling(),true)
end)
test('required seeder is not switched off because another seeder is optional',function()
    local i=seeder(false,10); i.on=true
    sController(i,settings(false,true)):update()
    eq(i.on,true)
end)
test('optional seeder is controlled per implement instead of GUI disabled state',function()
    local cp=settings(false,true); cp.optionalSowingMachineEnabled.getIsDisabled=function() return true end
    local i=seeder(true,10); i.on=true
    sController(i,cp):update(); eq(i.on,false)
end)
test('optional seeder still respects turn-on permissions',function()
    local i=seeder(true,10); i.on=false; i.getCanBeTurnedOn=function() return false end
    sController(i,settings(true,true)):update(); eq(i.on,false)
end)
test('disabled optional seeder skips irrelevant crop warning',function()
    local i=seeder(true,0); i.spec_sowingMachine.showWrongFruitForMissionWarning=true
    sController(i,settings(false,true)):update()
end)
test('optional menu scans all seeders rather than only the first',function()
    AIUtil={getAllChildVehiclesWithSpecialization=function() return {seeder(false,1),seeder(true,1)},true end}
    eq(CpVehicleSettings.isOptionalSowingMachineSettingVisible({}),true)
    eq(CpVehicleSettings.isOptionalSowingMachineSettingDisabled({}),false)
end)
test('pure required seeder has no optional-seeding menu entry',function()
    AIUtil={getAllChildVehiclesWithSpecialization=function() return {seeder(false,1)},true end}
    eq(CpVehicleSettings.isOptionalSowingMachineSettingVisible({}),false)
    eq(CpVehicleSettings.isOptionalSowingMachineSettingDisabled({}),true)
end)
test('no seeders hides the optional-seeding menu',function()
    AIUtil={getAllChildVehiclesWithSpecialization=function() return {},false end}
    eq(CpVehicleSettings.isOptionalSowingMachineSettingVisible({}),false)
end)
test('combined seeder checks fertilizer when enabled',function()
    eq(pController(sprayer(0,true),settings(true,true)):getIsRequiredMaterialMissing(),true)
end)
test('combined seeder ignores fertilizer when disabled',function()
    local c=pController(sprayer(0,true),settings(true,false))
    eq(c:getIsRequiredMaterialMissing(),false); eq(c:isRefillingEnabled(),false)
end)
test('fertilizing cultivator honors optional fertilizer setting',function()
    local i=sprayer(0); i.spec_fertilizingCultivator={}
    eq(pController(i,settings(true,false)):getIsRequiredMaterialMissing(),false)
    eq(pController(i,settings(true,true)):getIsRequiredMaterialMissing(),true)
end)
test('standalone spreader cannot be disabled by hidden combination-tool setting',function()
    eq(pController(sprayer(0),settings(false,false)):getIsRequiredMaterialMissing(),true)
end)
test('lime is still required when fertilizer purchase does not supply this sprayer',function()
    g_currentMission.missionInfo.helperBuyFertilizer=true
    eq(pController(sprayer(0),settings(false,false)):getIsRequiredMaterialMissing(),true)
end)
test('base-game fertilizer supply is respected',function()
    local i=sprayer(0); i.spec_sprayer.isFertilizerSprayer=true
    g_currentMission.missionInfo.helperBuyFertilizer=true
    eq(pController(i,settings(false,false)):getIsRequiredMaterialMissing(),false)
end)
test('base-game slurry and manure sources are respected',function()
    local i=sprayer(0); i.spec_sprayer.isSlurryTanker=true
    g_currentMission.missionInfo.helperSlurrySource=2
    eq(pController(i,settings(false,false)):getIsRequiredMaterialMissing(),false)
    i.spec_sprayer.isSlurryTanker=false; i.spec_sprayer.isManureSpreader=true
    g_currentMission.missionInfo.helperManureSource=2
    eq(pController(i,settings(false,false)):getIsRequiredMaterialMissing(),false)
end)
test('nonempty sprayer is not empty when stopped work-area rate is zero',function()
    eq(pController(sprayer(10,true),settings(true,true)):getIsRequiredMaterialMissing(),false)
end)
test('one empty fertilizer source does not invalidate a full compatible source',function()
    local i=sprayer(0); local source=tank(40,2); source.spec_sprayer={}
    i.spec_sprayer.fillTypeSources[2]={{vehicle=tank(0,2),fillUnitIndex=1},{vehicle=source,fillUnitIndex=3}}
    local c=pController(i,settings(false,false))
    eq(c:getIsRequiredMaterialMissing(),false)
    assert(c.refillData.lastFillLevels[source][3]~=nil)
end)
test('inactive source with material is not misreported as empty',function()
    local i=sprayer(0); local source=tank(10,2); source.getIsFillUnitActive=function() return false end
    i.spec_sprayer.fillTypeSources[2]={{vehicle=source,fillUnitIndex=1}}
    eq(pController(i,settings(false,false)):getIsRequiredMaterialMissing(),false)
end)
test('empty passive fertilizer tank is not itself an applicator',function()
    local i=sprayer(0); i.spec_sprayer.allowsSpraying=false
    eq(pController(i,settings(false,false)):getIsRequiredMaterialMissing(),false)
end)
test('wrong material in spray source does not satisfy supply',function()
    local i=sprayer(0); i.spec_sprayer.fillTypeSources[2]={{vehicle=tank(20,1),fillUnitIndex=1}}
    eq(pController(i,settings(false,false)):getIsRequiredMaterialMissing(),true)
end)
test('refill source refresh removes detached tanks and retains history',function()
    local i=sprayer(0); local source=tank(10,2)
    i.spec_sprayer.fillTypeSources[2]={{vehicle=source,fillUnitIndex=2}}
    local c=pController(i,settings(false,false)); c.refillData.lastFillLevels[i][1]=5
    i.spec_sprayer.fillTypeSources[2]={}
    eq(c:needsRefilling(),true)
    eq(c.refillData.lastFillLevels[source],nil); eq(c.refillData.lastFillLevels[i][1],5)
end)
test('base refill capability is not treated as an empty additive tank',function()
    local c=ImplementController(rootVehicle(settings(false,false)),tank(10,3))
    c:addRefillImplementAndFillUnit(c.implement,1)
    eq(c:needsRefilling(),true); eq(c:getIsRequiredMaterialMissing(),false)
end)
test('disabled fertilizer does not auto-refill during field waiting',function()
    local i=sprayer(0,true); local c=pController(i,settings(true,false))
    i.spec_fillUnit=nil -- Would fail if refill triggers were accessed.
    local ready,changed=c:onUpdateRefilling(); eq(ready,true); eq(changed,false)
end)

local function fieldTask(missing, waiting, server)
    local cp=settings(true,true)
    local strategy=setmetatable({controllers={},state={}},AIDriveStrategyFieldWorkCourse)
    strategy.states={INITIAL=strategy.state}
    strategy.controllers={{getIsRequiredMaterialMissing=function() return missing.value end}}
    strategy.raiseControllerEvent=function() end
    strategy.raiseControllerEventWithLambda=function(self,event,f) f(true,true) end
    local v=rootVehicle(cp); v.spec_cpAIFieldWorker={driveStrategy=strategy}; v.calls={}
    v.cpHold=function(self) table.insert(self.calls,'HOLD') end
    v.stopCurrentAIJob=function(self,msg) eq(msg,'OUT_OF_FILL'); table.insert(self.calls,'STOP') end
    v.setCpInfoTextActive=function() end; v.resetCpActiveInfoText=function() end
    local t=setmetatable({isServer=server~=false,vehicle=v,waitingForRefillingActive=waiting},CpAITaskFieldWork)
    return t,v,strategy,cp
end
test('task proactively holds and reports missing material before startup/work',function()
    local t,v=fieldTask({value=true},false)
    t:update(16); eq(v.calls[1],'HOLD'); eq(v.calls[2],'STOP')
end)
test('startup does not activate an initially empty tool while waiting for refill',function()
    g_time,g_updateLoopIndex=0,0
    local s=setmetatable({currentTask={waitingForRefillingActive=true},
        vehicle={getChildVehicles=function() return {} end},
        raiseControllerEvent=function() end,debug=function() end},AIDriveStrategyCourse)
    local count=0; s.vehicle.raiseAIEvent=function() count=count+1 end
    s:beginAIWorkStart()
    g_time,g_updateLoopIndex=1000,1
    eq(s:updateAIWorkStart(),false); eq(count,0)
    s.currentTask.waitingForRefillingActive=false
    eq(s:updateAIWorkStart(),false); eq(count,1)
end)
test('client task never independently stops the job for missing material',function()
    local t,v=fieldTask({value=true},false,false)
    t:update(16); eq(#v.calls,0)
end)
test('finished or transport phase does not trigger a resource stop',function()
    local t,v,s=fieldTask({value=true},false)
    s.state={}; t:update(16); eq(#v.calls,0)
end)
test('cancelled startup does not trigger resource stop',function()
    local t,v,s=fieldTask({value=true},false)
    s.aiWorkStartCancelled=true; t:update(16); eq(#v.calls,0)
end)
test('refill cannot resume while another required material remains empty',function()
    local t,v=fieldTask({value=true},true)
    t.lastSettingValues={optionalFertilizer=false,optionalSowing=true}
    t:update(16); eq(t.waitingForRefillingActive,true)
end)
test('refill resumes once all required materials are available',function()
    local t,v=fieldTask({value=false},true)
    t:update(16); eq(t.waitingForRefillingActive,false)
end)
test('refill completion also works after a purchase/option change without fill delta',function()
    local t,v,s=fieldTask({value=false},true)
    s.raiseControllerEventWithLambda=function(self,event,f) f(true,false) end
    t:update(16); eq(t.waitingForRefillingActive,false)
end)

test('fertilizing-seeder work callback uses actual supply, not zero work rate',function()
    local cp=settings(true,true); local i=sprayer(10,true)
    i.rootVehicle=rootVehicle(cp); i.rootVehicle.getIsCpActive=function() return true end
    i.rootVehicle.stopCurrentAIJob=function() error('full tank misreported as empty') end
    eq(FertilizingSowingMachine.processSowingMachineArea(i),'sowing')
end)
test('disabled fertilizer clears GIANTS previous-use marker in work parameters',function()
    local cp=settings(true,false); local i=sprayer(0,true)
    i.rootVehicle=rootVehicle(cp); i.rootVehicle.getIsCpActive=function() return true end
    Sprayer.onStartWorkAreaProcessing(i)
    eq(i.spec_sprayer.workAreaParameters.lastAIHasSprayed,nil)
    eq(i.spec_sprayer.workAreaParameters.sprayFillLevel,0)
end)
print('Required material regression tests: '..tests..' passed')
