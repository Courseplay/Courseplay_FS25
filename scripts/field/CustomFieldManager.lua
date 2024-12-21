--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2022 Peter Vaiko

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

    Keeping track and persisting all custom fields

]]--

---@class CustomFieldManager
CustomFieldManager = CpObject()
CustomFieldManager.namePrefix = "CP-"

---@param fileSystem FileSystem
function CustomFieldManager:init(fileSystem)
    ---@type FileSystem
    self.fileSystem = fileSystem
    self.currentView = fileSystem.currentDirectoryView
    self.rootDir = fileSystem.rootDirectory
    self:load()
end

function CustomFieldManager:load()
    self.fields = {}
    self.fileSystem:refresh()
    local entries = self.rootDir:getEntries(false, true)
    for i, entry in pairs(entries) do
        local field = CustomField.createFromXmlFile(entry)
        if field == nil then 
            CpUtil.info("Failed to load custom field: %s", tostring(entry))
        else 
            table.insert(self.fields, CustomField.createFromXmlFile(entry))
        end
    end
    --- Adds reference to the custom fields, for extern mod support.
	g_fieldManager.cpCustomFields = self.fields
end

--- New fields are created with a prefix and the next available number.
---@return number
function CustomFieldManager:getNewFieldNumber()
    local numbers = {}
    for i, entry in pairs(self.fields) do 
        local name = entry:getName()
        if name:startsWith("CP-") then 
            local n = entry:getFieldNumber()
            numbers[n] = true
        end
    end
    local ix = 1
    while self.currentView:hasEntryWithName(self.namePrefix..tostring(ix)) or numbers[ix] do 
        ix = ix + 1
    end
    return ix
end

--- Creates a new custom field from a given vertices table.
---@param waypoints table
function CustomFieldManager:addField(waypoints)
    if #waypoints < 10 then
        CpUtil.info('Recorded course has less than 10 waypoints, ignoring.')
        return
    end
    ---@type CustomField
    local newField = CustomField()
    newField:setup(self.namePrefix..self:getNewFieldNumber(), waypoints)
    YesNoDialog.show(
        CustomFieldManager.onClickSaveDialog, self,
        string.format(g_i18n:getText("CP_customFieldManager_confirm_save"), newField:getName()),
        nil, nil, nil, nil, nil, nil, newField)
end

--- Tries to delete a given custom field.
---@param fieldToDelete CustomField
function CustomFieldManager:deleteField(fieldToDelete)
    YesNoDialog.show(
        CustomFieldManager.onClickDeleteDialog, self,
        string.format(g_i18n:getText("CP_customFieldManager_confirm_delete"), fieldToDelete:getName()),
        nil, nil, nil, nil, nil, nil, fieldToDelete)
end

--- Tries renames a given custom field 
---@param field CustomField
function CustomFieldManager:renameField(field)
    TextInputDialog.show(
		CustomFieldManager.onClickRenameDialog, self,
		field:getName() or "",
		g_i18n:getText("CP_customFieldManager_rename"),
        nil, 30, g_i18n:getText("button_ok"), field)
end

--- Tries to edit a given custom field, with the course editor.
---@param fieldToEdit CustomField
function CustomFieldManager:editField(fieldToEdit)
    for i, field in pairs(self.fields) do
        if field == fieldToEdit then
            local file = self.currentView:getEntryByName(fieldToEdit:getName())
            if file then 
                g_courseEditor:activateCustomField(file:getEntity(), fieldToEdit)
            end
        end
    end
end

--- Saves the given custom field
---@param file File
---@param field CustomField
---@param forceReload boolean|nil
function CustomFieldManager:saveField(file, field, forceReload)
    file:save(CustomField.rootXmlKey, 
        CustomField.xmlSchema,
        CustomField.rootXmlKey, 
        CustomField.saveToXml, 
        field,
        field:getName())
    if forceReload then
        self:delete()
        self:load()
    end
end

--- Creates a new file with a given name.
function CustomFieldManager:onClickSaveDialog(clickOk, field)
    local fieldValid = false
    if clickOk then
        CpUtil.debugFormat(CpDebug.DBG_COURSES, 'Saving custom field %s', field:getName())
        local file, fileCreated = self.currentView:addFile(field:getName())
        if fileCreated then 
            self:saveField(file, field)
            fieldValid = true
            table.insert(self.fields, field)
            self.fileSystem:refresh()
        else 
            CpUtil.info("Failed to create custom Field: %s", field:getName())
        end
    end
    if not fieldValid then 
        field:delete()
    end
end

function CustomFieldManager:onClickDeleteDialog(clickOk, fieldToDelete)
    if clickOk then
        CpUtil.debugFormat(CpDebug.DBG_COURSES, 'Deleting custom field %s', fieldToDelete:getName())
        for i, field in pairs(self.fields) do
            if field == fieldToDelete then
                local file = self.currentView:getEntryByName(fieldToDelete:getName())
                if file then 
                    file:delete()
                    field:delete()
                    table.remove(self.fields, i)
                    self.fileSystem:refresh()
                else 
                    CpUtil.debugFormat(CpDebug.DBG_COURSES, 'Custom field %s was found, but the file not.', fieldToDelete:getName())
                end
                return
            end
        end
        CpUtil.debugFormat(CpDebug.DBG_COURSES, 'Custom field %s not found, not deleted', fieldToDelete:getName())
    end
end

function CustomFieldManager:onClickRenameDialog(newName, clickOk, fieldToRename)
    newName = CpUtil.cleanFilePath(newName)
    if clickOk then
        CpUtil.debugFormat(CpDebug.DBG_COURSES, 'Trying to rename custom field from %s to %s.', fieldToRename:getName(), newName)
        for i, field in pairs(self.fields) do
            if field == fieldToRename then
                local file = self.currentView:getEntryByName(fieldToRename.name)
                if file then 
                    if file:rename(newName) then 
                        CpUtil.debugFormat(CpDebug.DBG_COURSES, 'Renamed custom field from %s to %s.', fieldToRename:getName(), newName)
                        fieldToRename:setName(newName)
                        self.fileSystem:refresh()
                    else 
                        CpUtil.debugFormat(CpDebug.DBG_COURSES, 'Could not rename custom field from %s to %s.', fieldToRename:getName(), newName)
                        --- New field name already in use.
                        InfoDialog.show(string.format(g_i18n:getText("CP_customFieldManager_rename_error"), newName))
                    end
                    return
                end
            end
        end
    end
end

function CustomFieldManager:getCustomField(x, z)
    for _, field in pairs(self.fields) do
        if field:isPointOnField(x, z) then
            return field
        end
    end
    return nil
end

function CustomFieldManager:draw(map)
    for _, field in pairs(self.fields) do
        field:draw(map)
    end
end

function CustomFieldManager:delete()
    for _, field in pairs(self.fields) do 
        field:delete()
    end
end
FieldManager.unloadMapData = Utils.appendedFunction(FieldManager.unloadMapData, CustomFieldManager.delete)

--- Makes sure all custom fields are valid and in the filesystem.
--- Gets refresh on opening of the ai page in the in game menu.
function CustomFieldManager:refresh()
    self.fileSystem:refresh()
    local entries = self.rootDir:getEntries(false, true)
    for i = #self.fields, 1, -1 do 
        local foundIx = nil
        for j = #entries, 1, -1 do 
            if self.fields[i] and entries[j] and self.fields[i]:getName() == entries[j]:getName() then 
                foundIx = j 
                break
            end
        end
        if foundIx then 
            table.remove(entries, foundIx)
        else 
            CpUtil.debugFormat(CpDebug.DBG_COURSES, "Removed not saved hotspot %s.", self.fields[i]:getName())
            self.fields[i]:delete()
            table.remove(self.fields, i)
        end
    end
    for i, entry in pairs(entries) do
        CpUtil.debugFormat(CpDebug.DBG_COURSES, "Added new hotspot %s from filesystem.", entry:getName())
        table.insert(self.fields, CustomField.createFromXmlFile(entry))
    end
end

-- for reload only:
if g_customFieldManager then
    g_customFieldManager = CustomFieldManager(FileSystem(g_Courseplay.customFieldDir, g_currentMission.missionInfo.mapId))
end