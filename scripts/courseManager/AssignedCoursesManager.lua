
--- Saves/loads the assigned courses for each vehicle in a separate xml file.
---@class AssignedCoursesManager
AssignedCoursesManager = CpObject()
AssignedCoursesManager.rootXmlKey = "AssignedCourses"
AssignedCoursesManager.vehicleXmlKey = AssignedCoursesManager.rootXmlKey..".Vehicle"
AssignedCoursesManager.courseXmlKey = AssignedCoursesManager.vehicleXmlKey .."(?).Course(?)"
AssignedCoursesManager.fileName = "CpAssignedCourses.xml"
function AssignedCoursesManager:init()
	self.vehicles = {}
end

function AssignedCoursesManager:registerXmlSchema()
	g_messageCenter:subscribe(MessageType.LOADED_ALL_SAVEGAME_VEHICLES, self.finishedLoading, self)
	self.xmlSchema = XMLSchema.new("AssignedCourses")
	self.xmlSchema:register(XMLValueType.STRING, self.vehicleXmlKey.."(?)" .. "#name", "Vehicle name")
	CpCourseManager.registerXmlSchemaValues(self.xmlSchema, self.courseXmlKey)
end

--- Every valid vehicle will be added here, the id is needed to delete a sold vehicle form the table.
function AssignedCoursesManager:registerVehicle(vehicle, id)
	self.vehicles[id] = vehicle
end

--- Removes a sold vehicle from the table.
function AssignedCoursesManager:unregisterVehicle(vehicle, id)
	self.vehicles[id] = nil
end

function AssignedCoursesManager:getRegisteredVehicles()
	return self.vehicles
end

--- Saves all assigned vehicle courses in a single xml file under the savegame folder.
function AssignedCoursesManager:saveAssignedCourses(savegameDir)

	local xmlFile = XMLFile.create("assignedCoursesXmlFile", savegameDir..self.fileName,
								self.rootXmlKey, self.xmlSchema)
	local ix = 0
	for _,vehicle in pairs(self.vehicles) do
		--- Checks if the vehicle has courses.
		if vehicle:hasCpCourse() then
			local courses = vehicle:getCpCourses()
			--- Safety check, as it might happen,
			--- that a vehicle has a course without waypoints for some reason.
			if courses[1] and courses[1].waypoints and #courses[1].waypoints > 0 then
				local key = string.format("%s(%d)", self.vehicleXmlKey, ix)
				xmlFile:setValue(key.."#name", vehicle:getName())
				vehicle:saveAssignedCpCourses(xmlFile, key..".Course")
				--- Sets a unique ID to the vehicle, so the assigned courses can be loaded correctly into the vehicle.
				--- This ID is saved in the CpCourseManager Spec.
				vehicle:setCpAssignedCoursesID(ix)
				ix = ix + 1
			end
		end
	end
	xmlFile:save()
	xmlFile:delete()
end

--- Makes sure the xml file handle gets delete after the courses are loaded into the vehicles.
function AssignedCoursesManager:finishedLoading()
	if self.xmlFile then
		self.xmlFile:delete()
	end
end

--- Loads courses by the id in which they were saved into the vehicle.
function AssignedCoursesManager:loadAssignedCoursesByVehicle(vehicle, id)
	if id then
		CpUtil.debugVehicle(CpDebug.DBG_COURSES, vehicle, "Loading assigned courses, id: %d", id)
		if self.xmlFile == nil then
			-- if not yet open, do it now. We want to avoid closing/opening the file for each vehicle.
			self.filePath = g_currentMission.missionInfo.savegameDirectory .."/" .. self.fileName
			self.xmlFile = XMLFile.loadIfExists("assignedCoursesXmlFile", self.filePath, self.xmlSchema)
		end
		if self.xmlFile ~= nil then
			local key = string.format("%s(%d).Course", self.vehicleXmlKey, id)
			vehicle:loadAssignedCpCourses(self.xmlFile, key, true)
		end
	else
		CpUtil.debugVehicle(CpDebug.DBG_COURSES, vehicle, "Has no assigned courses.")
	end
end


g_assignedCoursesManager = AssignedCoursesManager()