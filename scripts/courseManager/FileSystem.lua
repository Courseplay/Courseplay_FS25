--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2021 Peter Vaiko

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

--[[
	Generic file system to store xml files and folders, similar to the windows file explorer.
	
]]--

--- An entity (file or directory) in the file system
---@class FileSystemEntity
FileSystemEntity = CpObject()

---@param parentPath string
---@param parent FileSystemEntity
---@param name string
function FileSystemEntity:init(parentPath,name,parent)
	self.parentPath = parentPath
	self.name = name
	self.fullPath = parentPath .. '/' .. name
	self.parent = parent
end

function FileSystemEntity:isDirectory()
	return false
end

function FileSystemEntity:getName()
	return self.name
end

function FileSystemEntity:getFullPath()
	return self.fullPath
end

function FileSystemEntity:getParentPath()
	return self.parentPath
end

function FileSystemEntity:getParent()
	return self.parent
end

function FileSystemEntity.__eq(a, b)
	return a.fullPath == b.fullPath
end

function FileSystemEntity.__lt(a, b)
	return a.name < b.name
end

function FileSystemEntity:__tostring()
	return 'Name: ' .. self.name .. ', Path: ' .. self.fullPath
end

---@class File : FileSystemEntity
File = CpObject(FileSystemEntity)
---@param parentPath string
---@param parent Directory
---@param name string
function File:init(parentPath,name,parent)
	FileSystemEntity.init(self,parentPath,name,parent)
end

function File:__tostring()
	return 'File: ' .. FileSystemEntity.__tostring(self) .. '\n'
end

function File:delete()
	getfenv(0).deleteFile(self:getFullPath())
	CpUtil.debugFormat(CpDebug.DBG_COURSES, 'deleted file %s', self:getFullPath())
	return true
end

--- Saves the xml file.
--- This function acts as an wrapper for saving the xml file.
--- All the values are saved in the lambda function.
---@param xmlRootName string xml root element name
---@param xmlSchema XMLSchema 
---@param xmlBaseKey string 
---@param lambda function
---@param class table
---@return boolean
function File:save(xmlRootName,xmlSchema,xmlBaseKey,lambda,class,...)
	local xmlFile = XMLFile.create("tempXmlFile",self.fullPath,xmlRootName,xmlSchema)
	if xmlFile ~= nil then
		if class then
			lambda(class,xmlFile,xmlBaseKey,...)
		else
			lambda(xmlFile,xmlBaseKey,...)
		end
		local wasSaved = xmlFile:save()
		xmlFile:delete()
		return wasSaved
	end
	CpUtil.debugFormat(CpDebug.DBG_COURSES,"couldn't create xml file: %s",self.fullPath)
	return false
end

--- Loads the xml file.
--- This function acts as an wrapper for loading the xml file.
--- All the values are loaded in the lambda function.
---@param xmlSchema XMLSchema
---@param xmlBaseKey string
---@param lambda function
---@param class table
---@param ... any
---@return boolean
function File:load(xmlSchema, xmlBaseKey, lambda, class,...)
	local xmlFile = XMLFile.load("tempXmlFile", self.fullPath, xmlSchema)
	if xmlFile ~= nil then
		local retValue = false
		if class then
			retValue = lambda(class, xmlFile, xmlBaseKey, ..., self.name)
		else 
			retValue = lambda(xmlFile, xmlBaseKey, ..., self.name)
		end
		xmlFile:delete()
		return retValue
	end
	CpUtil.debugFormat(CpDebug.DBG_COURSES, "couldn't load xml file: %s", self.fullPath)
	return false
end

function File:clone()
	return File(self.parentPath,self.parent,self.name)
end

--- Copies a file to a new directory.
---@param newParent Directory
---@param overwrite boolean is overwriting of existing files allowed ?
---@return boolean
function File:copy(newParent,overwrite)
	if not newParent.entries[self.name] then
		copyFile(self.fullPath,newParent:getFullPath() .. "/" .. self.name,overwrite or false)
		return true
	end
	return false
end

--- Moves a file to a new directory.
--- This is done by coping it to the new directory 
--- and then deleting the original file.
---@param newParent Directory
---@param overwrite boolean is overwriting of existing files allowed ?
---@return boolean
function File:move(newParent,overwrite)
	local wasMoved = self:copy(newParent,overwrite)
	if wasMoved then	
		self:delete()
	end
	return wasMoved
end

--- Renames a file.
--- This is done by coping it under the new name in the same directory 
--- and then deleting the original file.
---@param newName string
---@param overwrite boolean is overwriting of existing files allowed ?
---@return boolean
function File:rename(newName,overwrite)
	if not self.parent:hasEntry(newName) then
		copyFile(self.fullPath,self.parent:getFullPath() .. "/" .. newName,overwrite or false)
		self:delete()
		return true
	end
	return false
end


--- A directory on the file system. This can recursively be traversed to all subdirectories.
---@class Directory : FileSystemEntity
Directory = CpObject(FileSystemEntity)

function Directory:init(parentPath, name, parent)
	FileSystemEntity.init(self, parentPath,name,parent)
	self.entries = {}
	CpUtil.debugFormat(CpDebug.DBG_COURSES,"Created directory at %s",self.fullPath)
	createFolder(self.fullPath)
	self.numEntries = 0
	self.numFiles = 0
	self.numDirectories = 0
	self:refresh()
end

function Directory:isDirectory()
	return true
end

function Directory:getFullPathForFile(fileName)
	return self:getFullPath() .. '/' .. fileName
end

function Directory:getEntries(directories, files)
	local entries = {}
	for _, entry in pairs(self.entries) do
		if directories and entry:isDirectory() then
			table.insert(entries, entry)
		end
		if files and not entry:isDirectory() then
			table.insert(entries, entry)
		end
	end
	table.sort(entries)
	return entries
end

function Directory:getDirectories()
	return self:getEntries(true, false)
end

function Directory:getFiles()
	return self:getEntries(false, true)
end

function Directory:hasEntry(name)
	return self.entries[name] ~=nil	
end

--- Refresh from disk
function Directory:refresh()
	self.numEntries = 0
	self.numFiles = 0
	self.numDirectories = 0
	self.entriesToRemove = {}
	for key, _ in pairs(self.entries) do
		self.entriesToRemove[key] = true
	end
	getFiles(self.fullPath, 'fileCallback', self)
	for key, _ in pairs(self.entriesToRemove) do
		self.entries[key] = nil
	end
end

--- FileSystemEntity found in the directory.
---@param name string
---@param isDirectory boolean
function Directory:fileCallback(name, isDirectory)
	if isDirectory then
		if self.entries[name] then
			self.entries[name]:refresh()
		else
			self.numDirectories = self.numDirectories + 1
			self.entries[name] = Directory(self.fullPath, name, self)
			self.numEntries = self.numEntries + 1
		end
	elseif not self.entries[name] then
		self.entries[name] = File(self.fullPath, name, self)
		self.numEntries = self.numEntries + 1
		self.numFiles = self.numFiles + 1
	end
	if self.entriesToRemove[name] then
		self.entriesToRemove[name] = nil
	end
end

function Directory:deleteFile(name)
	self:refresh()
	if self.entries[name] then 
		self.entries[name]:delete()
	end
end

---@param forceDelete boolean If it's true, then all sub entities will also be deleted.
---@return boolean
function Directory:delete(forceDelete)
	self:refresh()
	if forceDelete then 
		local entries = self:getEntries(true,true)
		for _,entry in ipairs(entries) do 
			entry:delete(true)
		end
	end
	self:refresh()
	if self:isEmpty() then
		getfenv(0).deleteFolder(self.fullPath)
		CpUtil.debugFormat(CpDebug.DBG_COURSES,"deleted folder: %s",self.fullPath)
		return true
	else
		CpUtil.debugFormat(CpDebug.DBG_COURSES,"folder %s is not empty, cannot delete",self.fullPath)
		return false
	end
end

function Directory:isEmpty()
	return next(self.entries) == nil
end

--- Adds a sub directory with a given name.
---@param name string
---@return boolean
function Directory:addDirectory(name)
	self:refresh()
	if not self.entries[name] then
		self.entries[name] = Directory(self.fullPath, name, self)
		return true
	end
	return false
end

--- Adds a new file with a given name.
---@param name string
---@return boolean
function Directory:addFile(name)
	self:refresh()
	if not self.entries[name] then
		self.entries[name] = File(self.fullPath,name, self)
		return self.entries[name],true
	end
	return self.entries[name],false
end

function Directory:__tostring()
	local str = 'Directory: ' .. FileSystemEntity.__tostring(self) .. '\n'
	for _, entry in pairs(self.entries) do
		str = str .. tostring(entry)
	end
	return str
end

function Directory:clone()
	self:refresh()
	local clonedDir = Directory(self.parentPath,self.name,self.parent)
	for i,entry in ipairs(self:getEntries(true,true)) do 
		entry:clone(self.parentPath,self.name,self.parent)
	end
	clonedDir:refresh()
	return clonedDir	
end

--- Copies the directory and it's sub entities recursively.
---@param newParent Directory
---@param overwrite boolean is overwriting of existing files allowed ?
---@return boolean
function Directory:copy(newParent,overwrite)
	newParent:refresh()
	CpUtil.debugFormat(CpDebug.DBG_COURSES,"Attempt to copy(%s) to %s",self.name,newParent:getFullPath())
	if newParent.entries[self.name] then
		CpUtil.debugFormat(CpDebug.DBG_COURSES,"entry %s, already exists in %s",self.name,newParent:getFullPath())
		return false
	else
		local dir = Directory(newParent:getFullPath() ,self.name,self)
		local entries = self:getEntries(true,true)
		for i,entry in ipairs(entries) do 
			entry:copy(dir,overwrite)
		end
	end
	return true
end

--- Moves the directory and it's sub entries to a new directory recursively.
--- This is done by coping it and it's sub entries to the new directory recursively
--- and then deleting the original entries recursively.
---@param newParent Directory
---@param overwrite boolean is overwriting of existing files allowed ?
---@return boolean
function Directory:move(newParent,overwrite)
	newParent:refresh()
	local canBeMoved = self:copy(newParent,overwrite)
	if canBeMoved then
		self:delete(true)
	end 
	return canBeMoved
end

--- Renames a directory.
--- This is done by coping it under the new name in the same directory recursively with all it's sub entries 
--- and then deleting the original entries recursively.
---@param newName string
---@param overwrite boolean is overwriting of existing files allowed ?
---@return boolean
function Directory:rename(newName,overwrite)
	self:refresh()
	if self.entries[newName] then
		CpUtil.debugFormat(CpDebug.DBG_COURSES,"entry %s, already exists in %s",newName,self:getFullPath())
		return false
	else
		local dir = Directory(self.parentPath ,newName,self:getParent())
		local entries = self:getEntries(true,true)
		for i,entry in ipairs(entries) do 
			entry:copy(dir,overwrite)
		end
		self:delete(true)
	end 
	return true
end

--- A view representing a file system entity (file or directory). The view knows how to display an entity on the UI.
---@class FileSystemEntityView
FileSystemEntityView = CpObject()
FileSystemEntityView.indentString = '  '

function FileSystemEntityView:init(entity,parent, level)
	self.name = entity:getName()
	self.parent = parent
	self.level = level or 0
	self.entity = entity
	self.indent = ''
	-- indent only from level 2. level 0 is never shown, as it is the root directory, level 1
	-- has no indent.
	for i = 2, self.level do
		self.indent = self.indent .. FileSystemEntityView.indentString
	end
end

function FileSystemEntityView:getEntity()
	return self.entity
end

function FileSystemEntityView:getName()
	return self.name
end

function FileSystemEntityView:getParent()
	return self.parent
end

function FileSystemEntityView:getFullPath()
	return self.entity:getFullPath()
end

function FileSystemEntityView:getParentPath()
	return self.entity:getParentPath()
end

function FileSystemEntityView:getLevel()
	return self.level
end

function FileSystemEntityView:__tostring()
	return self.indent .. self.name .. '\n'
end

function FileSystemEntityView.__lt(a, b)
	return a.name < b.name
end

function FileSystemEntityView:isDirectory()
	return self.entity:isDirectory()
end

function FileSystemEntityView:delete()
	return self.entity:delete()
end

function FileSystemEntityView:rename(name)
	return self.entity:rename(name)
end

function FileSystemEntityView:move(newParent)
	return self.entity:move(newParent:getEntity())
end

function FileSystemEntityView:copy(newParent)
	return self.entity:copy(newParent:getEntity())
end

function FileSystemEntityView:isDeleteAllowed()
	return true
end

function FileSystemEntityView:hasAccess()
	return true
end

function FileSystemEntityView:isRenameAllowed()
	return true
end

function FileSystemEntityView.__eq(a, b)
	return a.entity == b.entity
end

--- View of a regular file (XML with a saved course
---@class FileView : FileSystemEntityView
FileView = CpObject(FileSystemEntityView)
function FileView:init(file,parent, level)
	FileSystemEntityView.init(self, file,parent, level)
end

--- View of a directory of saved courses
---@class DirectoryView : FileSystemEntityView
DirectoryView = CpObject(FileSystemEntityView)

DirectoryView.deleteAllowed = 2 -- every level entry >= x can be deleted
DirectoryView.renameAllowed = 2 -- every level entry >= x can be renamed
DirectoryView.accessLevel = 2 -- every level entry >= x can be access and modified
DirectoryView.entriesVisible = 1 -- every level entry >= x are visible
DirectoryView.canBeOpened = 1 -- every directory entry <= x can be opened

---@param directory Directory
function DirectoryView:init(directory,parent, level)
	FileSystemEntityView.init(self, directory,parent, level)
	self.directory = directory
	self:refresh()
end

function DirectoryView:refresh()
	self.directoryViews = {}
	self.fileViews = {}
	for _, entry in pairs(self.directory:getEntries(true,true)) do
		if entry:isDirectory() then
			table.insert(self.directoryViews, DirectoryView(entry,self, self.level + 1))
		else
			table.insert(self.fileViews, FileView(entry,self, self.level + 1))
		end
	end

	table.sort(self.directoryViews)
	table.sort(self.fileViews)
end

function DirectoryView:__tostring()
	local str = ''
	if self.level > 0 then
		str = str .. self.indent .. self.name .. '\n'
	end
	for _, dv in ipairs(self.directoryViews) do
		str = str .. tostring(dv)
	end
	for _, fv in ipairs(self.fileViews) do
		str = str .. tostring(fv)
	end

	return str
end

function DirectoryView:collectEntries(t)
	self:refresh()
	for _, dv in ipairs(self.directoryViews) do
		table.insert(t, dv)
	end
	for _, fv in ipairs(self.fileViews) do
		table.insert(t, fv)
	end
end

--- Entries according to the current folded/unfolded state of the directories.
function DirectoryView:getEntries()
	local entries = {}
	self:collectEntries(entries)
	return entries
end

function DirectoryView:getFileViews()
	self:refresh()
	return self.fileViews
end

--- Entries with parent added.
function DirectoryView:getEntriesWithParent()
	local entries = {}
	if self.level > self.entriesVisible then
		table.insert(entries, self.parent)
	end
	self:collectEntries(entries)
	return entries
end


function DirectoryView:getSubEntryByIndex(parentIx,childIx)
	local entry = self:getEntries()[parentIx]
	if entry then 
		return entry:getEntries()[childIx]
	end
	CpUtil.debugFormat(CpDebug.DBG_COURSES,"Sub entry not found for (%d,%d)",parentIx,childIx)
end

function DirectoryView:getNumberOfEntriesForIndex(ix)
	if not self:areEntriesVisible() then 
		return 0
	end
	local entries = self:getEntries()
	if entries and entries[ix] and entries[ix]:isDirectory() then
		return #(entries[ix]:getEntries())
	end
	return 0
end

function DirectoryView:getNumberOfEntries()
	return #self:getEntries()
end

function DirectoryView:getEntryByIndex(ix)
	local entries = self:getEntries()
	return entries[ix]
end

function DirectoryView:isDeleteAllowed()
	return self.level >= self.deleteAllowed
end

function DirectoryView:isRenameAllowed()
	return self.level >= self.renameAllowed
end

function DirectoryView:hasAccess()
	return self.level >= self.accessLevel
end

function DirectoryView:areEntriesVisible()
	return self.level >=self.entriesVisible
end

function DirectoryView:addDirectory(name)
	return self.directory:addDirectory(name)
end

function DirectoryView:addFile(name)
	return self.directory:addFile(name)
end

function DirectoryView:canOpen()
	return self.level <= self.canBeOpened
end

function DirectoryView:getEntryByName(name)
	for i,entry in pairs(self:getEntries()) do 
		if entry:getName() == name then 
			return entry
		end
	end
end

function DirectoryView:hasEntryWithName(name)
	return self:getEntryByName(name) ~= nil
end

--- File system to handle multiple files/directions.
---@class FileSystem 
FileSystem = CpObject()
FileSystem.debugChannel = CpDebug.DBG_COURSES
---@param baseDir string base path of this file system, baseDir/name will be the full path
---@param name string name of the directory containing this file system
function FileSystem:init(baseDir, name)
	self.baseDir = baseDir
	self.rootDirectory = Directory(baseDir, name)
	self.rootDirectoryView = DirectoryView(self.rootDirectory,nil,0)
	self:refresh()
	self.currentDirectoryView = self.rootDirectoryView
end

--- Refresh everything from disk
function FileSystem:refresh()
	self.rootDirectory:refresh()
	self.rootDirectoryView:refresh()
end

--- Gets the shorted file path of the current selected directory
--- with the parent directory name and the current name. 
---@return string
function FileSystem:getCurrentDirectoryViewPath()
	local parentName = self.currentDirectoryView:getParent() and "../"..self.currentDirectoryView:getParent():getName() or ".."
	return string.format("%s/%s/",parentName,self.currentDirectoryView:getName())
end

--- Is moving backwards in the current file system tree allowed ?
---@return boolean
function FileSystem:getCanIterateBackwards()
	return false
end

--- Moves to the parent element of the current directory.
function FileSystem:iterateBackwards()
	if self:getCanIterateBackwards() then 
		self.currentDirectoryView = self.currentDirectoryView:getParent()
	end
end

--- Makes sure the current directory view is valid, for deleting/renaming/moving.
---@param entryView FileSystemEntityView
function FileSystem:validate(entryView)
--	if self.currentDirectoryView == entryView or self.currentDirectoryView == entryView:getParent() then 
--		self:iterateBackwards()
--	end
end

--- Opens a directory and changes the view.
---@param entryView DirectoryView
function FileSystem:iterateForwards(entryView)
	if entryView:isDirectory() then
		if entryView:canOpen() then
			if entryView ~= self.rootDirectoryView then
				self.currentDirectoryView = entryView	
			end
			self:refresh()
		end
	end
end

--- Gets the number of entries for the current selected directory.
---@return number
function FileSystem:getNumberOfEntries()
	return self.currentDirectoryView:getNumberOfEntries()
end

--- Gets the number of entries for a sub directory of the current selected directory.
---@param ix number
---@return number
function FileSystem:getNumberOfEntriesForIndex(ix)
	return self.currentDirectoryView:getNumberOfEntriesForIndex(ix)
end

--- Gets a sub entry of the current selected directory.
---@param ix number
---@return FileSystemEntityView
function FileSystem:getEntryByIndex(ix)
	return self.currentDirectoryView:getEntryByIndex(ix)
end

--- Gets a sub entry of a sub directory of the current selected directory.
---@param parentIx number
---@param childIx number
---@return FileSystemEntityView
function FileSystem:getSubEntryByIndex(parentIx,childIx)
	return self.currentDirectoryView:getSubEntryByIndex(parentIx,childIx)
end

function FileSystem:createDirectory(name)
	return self.currentDirectoryView:addDirectory(name)
end

function FileSystem:getRootDirectory()
	return self.rootDirectory
end

function FileSystem:debug(...)
	return CpUtil.debugFormat(FileSystem.debugChannel,...)	
end

--- TODO: figure out a better solution for this!
function FileSystem:fixCourseStorageRoot()
	self.rootDirectoryView:addDirectory("Singleplayer")
	local entries = self.currentDirectoryView:getEntries()
	self.currentDirectoryView = entries[1]
end