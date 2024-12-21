--- Custom field hotspot that can be clicked for deleting of the field course.
CustomFieldHotspot = {}
CustomFieldHotspot.CATEGORY = 200
CustomFieldHotspot.SLICE_ID = "gui.ingameMap_other"
CustomFieldHotspot.NAME = "CP_customFieldManager_hotspotName"
CustomFieldHotspot.COLOR = {0.61049, 0.56471, 0.00303, 1}
local CustomFieldHotspot_mt = Class(CustomFieldHotspot, FarmlandHotspot)

function CustomFieldHotspot.new(customMt)
	local self = FarmlandHotspot.new(customMt or CustomFieldHotspot_mt)
	self.lastName = ""
	return self
end

function CustomFieldHotspot:render(x, y, rotation, small)
	local name = self:getName()
	if name ~= self.lastName then
		setTextBold(true)
		local width = getTextWidth(self.textSize * 1/(self.scale * 0.75), self.field:getName())
		setTextBold(false)
		self.icon:setDimension(width + self.width)
	end
	self.lastName = name
	CustomFieldHotspot:superClass().render(self, x, y, rotation, small)
end

function CustomFieldHotspot:setScale(scale)
	self.scale = scale
end

function CustomFieldHotspot:getCategory()
	return CustomFieldHotspot.CATEGORY 
end

---@param field CustomField
function CustomFieldHotspot:setField(field)
	self.field = field
	local worldX, worldZ = field:getCenter()
	self:setWorldPosition(worldX, worldZ)
	self.clickArea = MapHotspot.getClickArea(
		{
			0,
			0,
			1,
			1
		},
		{
			1,1,
		},
		0
	)	
end

function CustomFieldHotspot:getName()
	return self.field:getName()
end

function CustomFieldHotspot:onClickDelete()
	CpUtil.debugFormat(CpDebug.DBG_HUD,"Delete custom field %s.", self.name)
	g_customFieldManager:deleteField(self.field)
end

function CustomFieldHotspot:onClickRename()
	CpUtil.debugFormat(CpDebug.DBG_HUD,"Rename custom field %s.", self.name)
	g_customFieldManager:renameField(self.field, self)
end

function CustomFieldHotspot:onClickEdit()
	CpUtil.debugFormat(CpDebug.DBG_HUD,"Edit custom field %s.", self.name)
	g_customFieldManager:editField(self.field, self)
end

function CustomFieldHotspot:getAreaText()
    --- Needs to be converted to ha.
    return g_i18n:formatArea(self.field:getAreaInSqMeters()/10000 , 2)
end

