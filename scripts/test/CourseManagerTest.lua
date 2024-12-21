lu = require("luaunit")
package.path = package.path .. ";../?.lua;../courseManager/?.lua"
require('mock-GiantsEngine')
require('mock-Courseplay')
require('CpObject')
require('CpUtil')
require('FileSystem')

--- Still WIP

-- clean up
local workingDir = io.popen("pwd"):read'*l'
deleteFolder(workingDir .. '/modSettings')
local coursesDir = 'modSettings/Courseplay_FS22/Courses'
os.execute('mkdir -p ' .. coursesDir)


------------------------------------------------------------------------------------------------------------------------
-- File
------------------------------------------------------------------------------------------------------------------------
local file = File(coursesDir,"testFile")
assert(file.name == "testFile")
assert(file.parentPath == coursesDir)
assert(file.fullPath == coursesDir .. "/" .. "testFile")

file:save("xmlRootName",{},"xmlBaseKey",function () end,{},...)

file:load({},"xmlBaseKey",function () return true end,{},...)

file:delete()
assert(not fileExists(file:getFullPath()))

------------------------------------------------------------------------------------------------------------------------
-- Directory
------------------------------------------------------------------------------------------------------------------------
local dir = Directory(coursesDir,"testDir")
assert(dir:isDirectory() == true)
assert(next(dir:getEntries(true,true)) == nil)
assert(dir:isEmpty() == true)

dir:addFile("testFile")
assert(dir.entries["testFile"] ~=nil)

dir:addDirectory("testDir2")
assert(dir.entries["testDir2"] ~=nil)
assert(dir:isEmpty() == false)

dir:delete(true)

------------------------------------------------------------------------------------------------------------------------
-- FileSystem
------------------------------------------------------------------------------------------------------------------------
local fileSystem = FileSystem(workingDir .. '/' .. coursesDir, g_currentMission.missionInfo.mapId)

local currentView = fileSystem.currentDirectoryView
--assert(currentView.name == "Singleplayer")

--- Creating a new directory

fileSystem:createDirectory("testDir")
fileSystem:refresh()
local entries = currentView:getEntries(true,true)
assert(entries[1].name == "testDir")