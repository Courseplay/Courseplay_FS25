--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2018 Peter Vajko

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

-- Class implementation stolen from http://lua-users.org/wiki/SimpleLuaClasses
---@generic K : CpObject
---@param base `K`|nil Optional base class
---@param baseClassInit function|nil Optional giants constructor function for the base class
---@return K
function CpObject(base, baseClassInit)
	---@class CpObject
	local c = {}    -- a new class instance
	if type(base) == 'table' then
		-- our new class is a shallow copy of the base class!
		for i, v in pairs(base) do
			c[i] = v
		end
		c._base = base
	end
	-- the class will be the metatable for all its objects,
	-- and they will look up their methods in it.
	c.__index = c

	-- expose a constructor which can be called by <classname>(<args>)
	local mt = {}
	mt.__call = function(class_tbl, ...)
		local obj
		if base and base.baseClassInit then 
			--- A custom init function from a giants class
			obj = base.baseClassInit(..., c)
		end
		if obj == nil then
			obj = {}
			setmetatable(obj, c)
		end
		if class_tbl.init then
			class_tbl.init(obj,...)
		else
			-- make sure that any stuff from the base class is initialized!
			if base and base.init then
				base.init(obj, ...)
			end
		end
		return obj
	end
	c.baseClassInit = baseClassInit
	c.is_a = function(self, klass)
		local m = getmetatable(self)
		while m do
			if m == klass then return true end
			m = m._base
		end
		return false
	end
	-- TODO 25 deactivated (no leading __) as the for loop, probably pairs() sometimes leads to a stack overflow
	c.tostring = function (self)
		-- Default tostring function for printing all attributes and assigned functions.
		local str = '[ '
		for attribute, value in pairs(self) do
			str = str .. string.format('%s: %s ', attribute, value)
		end
		str = str .. ']'
		return str
	end
	--- For use in a __tostring to show attribute values of an object
	---@param str string|nil  string to append the result to
	---@param attributeList table<string, any>|nil a table with keys to list, default is self
	---@param prefix string|nil prefix to use to build the variable name from the keys in attributeList. For builder API
	--- object, this would be '_'
	---@return string str with the attribute values appended
	c.attributesToString = function(self, str, attributeList, prefix)
		str = str or ''
		for attributeName, _ in pairs(attributeList or self) do
			local variableName = (prefix or '') .. attributeName
			str = str .. string.format('%s: %s ', variableName, tostring(self[variableName]))
		end
		return str
	end
	c.new = function(...)
		return c(...)
	end
	c.superClass = function ()
		return c._base
	end
	setmetatable(c, mt)
	return c
end

---@class CpObjectUtil
CpObjectUtil = {
	BUILDER_API_NIL = "nil"
}

--- Registers a builder api for a class.
--- The attributes are set as private variables with "_" before the variable name 
--- and the builder functions are named like the attribute.
--- Nil values have to be replaced with CpObjectUtil.BUILDER_API_NIL !!
---@param class table
---@param attributesToDefault table<attributeName, any>
function CpObjectUtil.registerBuilderAPI(class, attributesToDefault)
	for attributeName, default in pairs(attributesToDefault) do 
		if default == CpObjectUtil.BUILDER_API_NIL then 
			default = nil
		end
		--- Applies the default value to the private variable
		class["_" .. attributeName] = default
		--- Creates the builder functions/ setters with the public variable name
		class[attributeName] = function(self, value)
			self["_" .. attributeName] = value	
			return self		
		end
	end
end

--- Object that holds a value temporarily. You can tell when to set the value and how long it should keep that
--- value, in milliseconds. Great for timers.
---@class CpTemporaryObject
CpTemporaryObject = CpObject()

function CpTemporaryObject:init(valueWhenExpired)
	self.valueWhenExpired = valueWhenExpired
	self:reset()
end

--- Set temporary value for object
---@param value any the temporary value
---@param expiryMs number|nil for expiryMs milliseconds after startMs, the object will return the value set above,
--- valueWhenExpired otherwise. When nil, it'll remain value forever
---@param startMs number|nil after starMs milliseconds from now, the object will return the value set above
--- (for expiryMs milliseconds). When nil, the value is set immediately.
function CpTemporaryObject:set(value, expiryMs, startMs)
	self.value = value
	self.startTime = startMs and g_time + startMs or g_time
	self.expiryTime = expiryMs and self.startTime + expiryMs or math.huge
end

--- Keeps the expiring timer going and doesn't update the start time.
function CpTemporaryObject:setAndProlong(value, expiryMs, startMs)
	if not self:isExpired() then 
		self.expiryTime = math.max(self.startTime, g_time) + expiryMs
	else 
		self:set(value, expiryMs, startMs)
	end
end


--- Get the value of the temporary object
--- Returns the value set if the current time is between the start time end expiry time, otherwise the default value
function CpTemporaryObject:get()
	if g_time < self.startTime or g_time > self.expiryTime then
		-- value not yet due or already expired
		return self.valueWhenExpired
	else
		return self.value
	end
end

--- Is the object waiting for the startTime (set() has been called, but value not set yet)
function CpTemporaryObject:isPending()
	return g_time < self.startTime
end

function CpTemporaryObject:isExpired()
	return g_time > self.expiryTime
end

--- Resets the object.
function CpTemporaryObject:reset()
	self.expiryTime = g_time
	self.value = self.valueWhenExpired
	self.expiryTime = g_time
	self.startTime = g_time
end

---@class CpDelayedBoolean : CpTemporaryObject
CpDelayedBoolean = CpObject(CpTemporaryObject)

function CpDelayedBoolean:get(condition, delay)
	if condition then
		if not self:isPending() and not CpTemporaryObject.get(self) then
			-- set only if not yet set, to not extend the start time
			self:set(true, nil, delay)
		end
	else
		self:reset()
	end
	return CpTemporaryObject.get(self)
end

--- Object slowly adjusting its value
---@class CpSlowChangingObject
CpSlowChangingObject = CpObject()

function CpSlowChangingObject:init(targetValue, timeToReachTargetMs)
	self.value = targetValue
	self:set(targetValue, timeToReachTargetMs)
end

function CpSlowChangingObject:set(targetValue, timeToReachTargetMs)
	self.previousValue = self.value
	self.targetValue = targetValue
	self.targetValueMs = g_time
	self.timeToReachTargetMs = timeToReachTargetMs or 1
end

--- Confirm an already set target, or, if the difference between the current and the new target value is
--- greater than delta, set a new target and target time.
--- This is to make sure that the target is reached in the required time, even if it is set by confirm()
--- repeatedly before reached.
---@param targetValue number
---@param timeToReachTargetMs number
---@param delta number
function CpSlowChangingObject:confirm(targetValue, timeToReachTargetMs, delta)
	if not self.targetValue or math.abs(targetValue - self.targetValue) > delta then
		self:set(targetValue, timeToReachTargetMs)
	else
		-- still update the target value to anticipate small changes, but not the time so the
		-- target will be reached about the same time as it first was set
		self.targetValue = targetValue
	end
end

function CpSlowChangingObject:get()
	local age = g_time - self.targetValueMs
	if age < self.timeToReachTargetMs then
		-- not reaped yet, return a value proportional to the time until ripe
		self.value = self.previousValue + (self.targetValue - self.previousValue) * age / self.timeToReachTargetMs
	else
		self.value = self.targetValue
	end
	return self.value
end

