-- Run from the repository root: lua scripts/test/HudEntryTest.lua
g_currentModName='FS25_Courseplay'
Enterable={}
Utils={overwrittenFunction=function(base,overwrite) return overwrite end}
CpDebug={DBG_HUD=1}
local current,cursor,cameras,opens
CpUtil={getCurrentVehicle=function() return current end,debugVehicle=function() end}
CpGuiUtil={setCameraRotation=function(vehicle,enabled) cameras=cameras+1;vehicle.cameraEnabled=enabled end}
g_inputBinding={getShowMouseCursor=function() return cursor end,setShowMouseCursor=function(value) cursor=value end}
g_Courseplay={}
local function hud()
    return {visible=false,openClose=function(self,value) self.visible=value;opens=opens+1 end,
        getIsOpen=function(self) return self.visible end,getIsHovered=function() return false end}
end
CpBaseHud=function() return hud() end
dofile('scripts/specializations/CpHud.lua')
local function vehicle()
    local v={isClient=true,isServer=false,spec_cpHud={hud=hud(),status={update=function() end}}}
    v.resetCpHud=CpHud.resetCpHud
    v.getCpDriveStrategy=function() return nil end
    v.getIsCpActive=function() return false end
    return v
end
local count=0
local function test(name,fn)
    current,cursor,cameras,opens=nil,false,0,0
    g_localPlayer={};g_Courseplay={};CpHud.isHudActive=true
    fn()
    count=count+1;print('PASS '..name)
end

test('immediate local entry restores the remembered open state once',function()
    local v=vehicle();current=v
    CpHud.onEnterVehicle(v,true)
    assert(v.spec_cpHud.hud.visible and opens==1 and cameras==1)
    assert(not v.spec_cpHud.pendingEnterRestore)
    CpHud.onUpdate(v,16)
    assert(opens==1 and cameras==1)
end)

test('late vehicle assignment restores on update without re-entering',function()
    local v=vehicle()
    CpHud.onEnterVehicle(v,true)
    CpHud.onUpdate(v,16)
    assert(opens==0 and cameras==0 and v.spec_cpHud.pendingEnterRestore)
    current=v
    CpHud.onUpdate(v,16)
    assert(v.spec_cpHud.hud.visible and opens==1)
end)

test('previous vehicle can remain current until the new entry is assigned',function()
    local v=vehicle();current=vehicle()
    CpHud.onEnterVehicle(v,true)
    assert(opens==0)
    current=v;CpHud.onUpdate(v,16)
    assert(v.spec_cpHud.hud.visible and opens==1)
end)

test('late HUD creation is handled by the same one-shot restore',function()
    local v=vehicle();v.spec_cpHud.hud=nil;current=v
    CpHud.onEnterVehicle(v,true)
    assert(v.spec_cpHud.pendingEnterRestore and opens==0)
    CpHud.onPostLoad(v)
    CpHud.onUpdate(v,16)
    assert(v.spec_cpHud.hud.visible and opens==1)
end)

test('late local player creation does not lose the restore request',function()
    local v=vehicle();current=v;g_localPlayer=nil
    CpHud.onEnterVehicle(v,true)
    assert(opens==0)
    g_localPlayer={};CpHud.onUpdate(v,16)
    assert(v.spec_cpHud.hud.visible and opens==1)
end)

test('a deliberately closed HUD stays closed after entry',function()
    local v=vehicle();CpHud.isHudActive=false
    CpHud.onEnterVehicle(v,true)
    current=v;CpHud.onUpdate(v,16)
    assert(not v.spec_cpHud.hud.visible and opens==1)
    CpHud.onUpdate(v,16)
    assert(opens==1)
end)

test('manual close cancels a pending restore',function()
    local v=vehicle();CpHud.onEnterVehicle(v,true)
    current=v;CpHud.closeCpHud(v)
    CpHud.onUpdate(v,16)
    assert(not v.spec_cpHud.hud.visible and not v.spec_cpHud.pendingEnterRestore and not CpHud.isHudActive)
end)

test('keyboard toggle overrides a pending restore',function()
    local v=vehicle();v.spec_cpHud.hud.visible=true
    CpHud.onEnterVehicle(v,true)
    current=v;CpHud.openClose(v);CpHud.onUpdate(v,16)
    assert(not v.spec_cpHud.hud.visible and not CpHud.isHudActive and opens==1)
end)

test('mouse opening cancels pending work and updates camera only once',function()
    local v=vehicle();CpHud.isHudActive=false
    CpHud.onEnterVehicle(v,true)
    current=v;CpHud.actionEventMouse(v)
    assert(cursor and v.spec_cpHud.hud.visible and not v.spec_cpHud.pendingEnterRestore)
    CpHud.onUpdate(v,16)
    assert(opens==1 and cameras==1 and v.cameraEnabled==false)
end)

test('leaving before assignment cancels the pending restore',function()
    local v=vehicle();CpHud.onEnterVehicle(v,true)
    CpHud.onLeaveVehicle(v,true)
    current=v;CpHud.onUpdate(v,16)
    assert(not v.spec_cpHud.hud.visible and opens==0 and not v.spec_cpHud.pendingEnterRestore)
end)

test('remote entry and dedicated server do not queue local HUD work',function()
    local remote=vehicle();CpHud.onEnterVehicle(remote,false)
    local server=vehicle();server.isClient=false;current=server
    CpHud.onEnterVehicle(server,true);CpHud.onUpdate(server,16)
    assert(not remote.spec_cpHud.pendingEnterRestore and not server.spec_cpHud.pendingEnterRestore and opens==0 and cameras==0)
end)

test('rapid switch does not restore the previous vehicle later',function()
    local a,b=vehicle(),vehicle()
    CpHud.onEnterVehicle(a,true);CpHud.onLeaveVehicle(a,true)
    CpHud.onEnterVehicle(b,true);current=b
    CpHud.onUpdate(a,16);CpHud.onUpdate(b,16)
    assert(not a.spec_cpHud.hud.visible and b.spec_cpHud.hud.visible and opens==1)
end)

test('cursor and camera state are restored without toggling the cursor',function()
    local v=vehicle();cursor=true;current=v
    CpHud.onEnterVehicle(v,true)
    assert(cursor and v.cameraEnabled==false and cameras==1)
end)

test('AutoDrive editor protection still preserves its mouse cursor',function()
    local v=vehicle();cursor=true
    CpHud.onEnterVehicle(v,true)
    g_Courseplay.autoDrive={isEditorModeEnabled=function() return true end}
    CpHud.onLeaveVehicle(v,true)
    assert(cursor and cameras==0 and not v.spec_cpHud.pendingEnterRestore)
end)
print('HUD entry regression tests: '..count..' passed')
