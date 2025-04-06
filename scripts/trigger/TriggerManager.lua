--- Stores all the relevant giants triggers expect bunker silos.
--- For now only unload triggers are supported.
---@class TriggerManager
TriggerManager = CpObject()
TriggerManager.DEBUG = false
function TriggerManager:init()
	---@type table<number,CpTrigger>
	self.unloadTriggers = {}
	---@type table<number,CpTrigger>
	self.dischargeableUnloadTriggers = {}
	---@type table<number,CpTrigger>
	self.loadTriggers = {}
end

--- Adds an unload trigger.
---@param silo table UnloadTrigger
function TriggerManager:addUnloadingSilo(silo)
	if silo.exactFillRootNode ~= nil then 
		self.unloadTriggers[silo.exactFillRootNode] = CpTrigger(silo, silo.exactFillRootNode)
		if silo:getIsToolTypeAllowed(ToolType.DISCHARGEABLE) then 
			self.dischargeableUnloadTriggers[silo.exactFillRootNode] = self.unloadTriggers[silo.exactFillRootNode]
		end
	end
end

--- Removes the unload trigger, as it got removed for example sold.
---@param silo table UnloadTrigger
function TriggerManager:removeUnloadingSilo(silo)
	if silo.exactFillRootNode ~= nil then 
		if self.unloadTriggers[silo.exactFillRootNode] then
			self.unloadTriggers[silo.exactFillRootNode]:delete()
			self.unloadTriggers[silo.exactFillRootNode] = nil
			self.dischargeableUnloadTriggers[silo.exactFillRootNode] = nil
		end
	end
end

--- Adds an load trigger.
---@param silo table LoadTrigger
function TriggerManager:addLoadingSilo(silo)
	if silo.triggerNode ~= nil then 
		self.loadTriggers[silo.triggerNode] = CpTrigger(silo, silo.triggerNode)
	end
end


--- Removes the unload trigger, as it got removed for example sold.
---@param silo table LoadTrigger
function TriggerManager:removeLoadingSilo(silo)
	if silo.triggerNode ~= nil then 
		if self.loadTriggers[silo.triggerNode] then
			self.loadTriggers[silo.triggerNode]:delete()
			self.loadTriggers[silo.triggerNode] = nil
		end
	end
end

---@return table<number, CpTrigger>
function TriggerManager:getLoadTriggers()
	return self.loadTriggers
end

---@return table<number, CpTrigger>
function TriggerManager:getUnloadTriggers()
	return self.unloadTriggers
end

---@return table<number, CpTrigger>
function TriggerManager:getDischargeableUnloadTriggers()
	return self.dischargeableUnloadTriggers
end

--- Gets the unload trigger from the exactFillRootNode.
---@param node number exactFillRootNode
---@return CpTrigger
function TriggerManager:getUnloadTriggerForNode(node)
	return self.unloadTriggers[node]
end

--- Gets the load trigger from the trigger node.
---@param node number trigger node
---@return CpTrigger
function TriggerManager:getLoadTriggerForNode(node)
	return self.loadTriggers[node]
end

--- Gets the first trigger found in the defined area.
---@param triggers table<number,CpTrigger>
---@param x number
---@param z number
---@param dirX number
---@param dirZ number
---@param width number
---@param length number
---@return boolean
---@return CpTrigger|nil
---@return table|nil
function TriggerManager:getTriggerAt(triggers, x, z, dirX, dirZ, width, length)
	local angle = MathUtil.getYRotationFromDirection(dirX, dirZ)
	local dirWX, dirWZ = MathUtil.getDirectionFromYRotation(angle + math.pi/2)
	local sx, sz = x + dirWX * width/2, z + dirWZ * width/2
	
	local area = {
		{
			x = sx,
			z = sz
		},
		{
			x = sx - dirWX * width,
			z = sz - dirWZ * width
		},
		{
			x = sx - dirWX * width + dirX * length,
			z = sz - dirWZ * width + dirZ * length
		},
		{
			x = sx + dirX * length,
			z = sz + dirZ * length
		},
		{
			x = sx,
			z = sz
		},
	}
	local dx, _, dz
	for node, trigger in pairs(triggers) do 
		dx, _, dz  = getWorldTranslation(node)
		if CpMathUtil.isPointInPolygon(area, dx, dz) then 
			return true, trigger, trigger:getTarget()
		end
	end
	return false
end

--- Gets the first unload trigger found in the defined area.
---@param x number
---@param z number
---@param dirX number
---@param dirZ number
---@param width number
---@param length number
---@return boolean
---@return CpTrigger|nil
---@return table|nil
function TriggerManager:getUnloadTriggerAt(x, z, dirX, dirZ, width, length)
	return self:getTriggerAt(self.unloadTriggers, x, z, dirX, dirZ, width, length)
end

--- Gets the first load trigger found in the defined area.
---@param x number
---@param z number
---@param dirX number
---@param dirZ number
---@param width number
---@param length number
---@return boolean found?
---@return CpTrigger|nil load trigger 
---@return table|nil load station/placeable
function TriggerManager:getLoadTriggerAt(x, z, dirX, dirZ, width, length)
	return self:getTriggerAt(self.loadTriggers, x, z, dirX, dirZ, width, length)
end

--- Gets the first dischargeable unload trigger found in the defined area.
---@param x number
---@param z number
---@param dirX number
---@param dirZ number
---@param width number
---@param length number
---@return boolean found?
---@return CpTrigger|nil unload trigger 
---@return table|nil unload station/placeable
function TriggerManager:getDischargeableUnloadTriggerAt(x, z, dirX, dirZ, width, length)
	return self:getTriggerAt(self.dischargeableUnloadTriggers, x, z, dirX, dirZ, width, length)
end

function TriggerManager:update(dt)
	
end

--- Draws all bunker silos onto the ai map.
---@param map table map to draw to.
---@param selected CpTrigger silo that gets highlighted.
function TriggerManager:drawUnloadTriggers(map, selected)
	for _, trigger in pairs(self.unloadTriggers) do 
		trigger:drawPlot(map, selected)
	end
end

--- Draws all bunker silos onto the ai map.
---@param map table map to draw to.
---@param selected CpTrigger silo that gets highlighted.
---@param fillTypes table|nil fill type that needs to be supported.
function TriggerManager:drawDischargeableTriggers(map, selected, fillTypes)
	for _, trigger in pairs(self.dischargeableUnloadTriggers) do 
		trigger:drawPlot(map, selected, fillTypes)
	end
end

function TriggerManager:draw()
	for node, trigger in pairs(self.unloadTriggers) do 
		if self.DEBUG then
			local text = string.format("%s:\n %d", getName(node), node )
			CpUtil.drawDebugNode(node, false, 2, text)
		end
	end
end

g_triggerManager = TriggerManager()

local function addUnloadingSilo(silo, superFunc, ...)
	local ret = superFunc(silo, ...)
	g_triggerManager:addUnloadingSilo(silo)
	return ret
end
UnloadTrigger.load = Utils.overwrittenFunction(UnloadTrigger.load, addUnloadingSilo)


local function removeUnloadingSilo(silo, ...)
	g_triggerManager:removeUnloadingSilo(silo)
end
UnloadTrigger.delete = Utils.prependedFunction(UnloadTrigger.delete, removeUnloadingSilo)

local function addLoadingSilo(silo, superFunc, ...)
	local ret = superFunc(silo, ...)
	g_triggerManager:addLoadingSilo(silo)
	return ret
end
LoadTrigger.load = Utils.overwrittenFunction(LoadTrigger.load, addLoadingSilo)


local function removeLoadingSilo(silo, ...)
	g_triggerManager:removeLoadingSilo(silo)
end
LoadTrigger.delete = Utils.prependedFunction(LoadTrigger.delete, removeLoadingSilo)