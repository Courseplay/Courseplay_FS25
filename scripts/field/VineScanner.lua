--- Detect physical orchard rows independently of plant node orientation.
VineScanner = CpObject()
local function finite(n) return type(n) == 'number' and n == n and math.abs(n) < math.huge end
local function valid(l)
    return type(l) == 'table' and finite(l.x1) and finite(l.z1) and finite(l.x2) and finite(l.z2)
        and (l.x2-l.x1)^2 + (l.z2-l.z1)^2 > 0.0001
end
local function distance(l,x,z)
    local dx,dz=l.x2-l.x1,l.z2-l.z1
    local t=math.max(0,math.min(1,((x-l.x1)*dx+(z-l.z1)*dz)/(dx*dx+dz*dz)))
    return ((l.x1+t*dx-x)^2+(l.z1+t*dz-z)^2)^0.5
end
local function cross(x,z,a,b) return x*b-z*a end
-- Clip to the actual selection, including concave custom fields. Never modify its vertices.
local function clip(l,polygon)
    local dx,dz=l.x2-l.x1,l.z2-l.z1
    local ts={0,1}
    for i,a in ipairs(polygon) do
        local b=polygon[i % #polygon+1]
        local ex,ez=b.x-a.x,b.z-a.z
        local den=cross(dx,dz,ex,ez)
        if math.abs(den)>1e-8 then
            local t=cross(a.x-l.x1,a.z-l.z1,ex,ez)/den
            local u=cross(a.x-l.x1,a.z-l.z1,dx,dz)/den
            if t>0 and t<1 and u>=0 and u<=1 then table.insert(ts,t) end
        end
    end
    table.sort(ts)
    local result={}
    for i=1,#ts-1 do
        local a,b=ts[i],ts[i+1]
        local t=(a+b)/2
        if b-a>1e-7 and CpMathUtil.isPointInPolygon(polygon,l.x1+t*dx,l.z1+t*dz) then
            table.insert(result,{x1=l.x1+a*dx,z1=l.z1+a*dz,x2=l.x1+b*dx,z2=l.z1+b*dz})
        end
    end
    return result
end
function VineScanner:init(maxStartDistance)
    self.maxStartDistance=maxStartDistance or 10
    self.debugChannel=CpDebug.DBG_COURSES
end
function VineScanner:setup() self.vineSystem=g_currentMission.vineSystem end
function VineScanner:foundVines() return self.lines ~= nil and #self.lines>0 end
function VineScanner:getScanError() return self.scanError end
-- Coffee fence adapter based on HLLMR's PR #1352. Feature detection also permits
-- other orchards exposing the same physical-row interface, without guessing crop layouts.
function VineScanner:getVineSegmentsAndWidth(placeable)
    if placeable.spec_vine then
        return placeable.spec_vine.vineSegments,placeable.spec_vine.width
    end
    if type(placeable.getOrchardRowSpacing)~='function' or type(placeable.getFence)~='function' then return end
    local fence=placeable:getFence()
    local width=placeable:getOrchardRowSpacing()
    if type(fence)~='table' or type(fence.segments)~='table' then return end
    local rows={}
    for _,s in pairs(fence.segments) do
        if type(s.vineNodes)=='table' and next(s.vineNodes) and type(s.getStartPos)=='function' and type(s.getEndPos)=='function' then
            local x1,_,z1=s:getStartPos()
            local x2,_,z2=s:getEndPos()
            rows[{x1=x1,z1=z1,x2=x2,z2=z2}]=s.vineNodes
        end
    end
    return rows,width
end
function VineScanner:getPlaceables()
    local result={}
    for _,p in pairs(self.vineSystem and self.vineSystem.nodes or {}) do result[p]=true end
    for _,p in pairs(g_currentMission.placeableSystem and g_currentMission.placeableSystem.placeables or {}) do
        if p.spec_vine or p.getOrchardRowSpacing then result[p]=true end
    end
    return result
end
function VineScanner:hasVineNodesCloseBy(x,z)
    for p in pairs(self:getPlaceables()) do
        local rows,width=self:getVineSegmentsAndWidth(p)
        if rows and finite(width) and width>0 then
            for l in pairs(rows) do
                if valid(l) and distance(l,x,z)<=self.maxStartDistance then return true end
            end
        end
    end
    return false
end
local function crop(p)
    if type(p.getVineFruitType)=='function' then
        local fruit=p:getVineFruitType()
        if fruit~=nil then return fruit end
    end
    local s=p.spec_vine
    return s and (s.fruitTypeIndex or s.fruitType or p.typeName or 'vine') or p.typeName or p
end
function VineScanner:findVineNodesInField(vertices,tx,tz,isCustomField)
    self.lines,self.width,self.fieldBorder,self.scanError=nil,nil,nil,nil
    if not vertices or #vertices<3 or not finite(tx) or not finite(tz) then return false end
    local candidates,nearest,nearestDistance={},nil,math.huge
    local unsupportedDistance=math.huge
    for p in pairs(self:getPlaceables()) do
        local rows,width=self:getVineSegmentsAndWidth(p)
        local usable=false
        if type(rows)=='table' and finite(width) and width>0 then
            for l in pairs(rows) do
                if valid(l) then
                    usable=true
                    for _,part in ipairs(clip(l,vertices)) do
                        local item={line=part,width=width,crop=crop(p)}
                        table.insert(candidates,item)
                        local d=distance(part,tx,tz)
                        if d<nearestDistance then nearest,nearestDistance=item,d end
                    end
                end
            end
        end
        if not usable then
            for node,owner in pairs(self.vineSystem and self.vineSystem.nodes or {}) do
                if owner==p then
                    local x,_,z=getWorldTranslation(node)
                    if CpMathUtil.isPointInPolygon(vertices,x,z) then
                        unsupportedDistance=math.min(unsupportedDistance,((x-tx)^2+(z-tz)^2)^0.5)
                    end
                end
            end
        end
    end
    if unsupportedDistance<math.huge and unsupportedDistance<=nearestDistance then
        self.scanError='CP_error_plantation_unsupported'; return false
    end
    if not nearest then return false end
    local ref,width=nearest.line,nearest.width
    local length=((ref.x2-ref.x1)^2+(ref.z2-ref.z1)^2)^0.5
    local dx,dz=(ref.x2-ref.x1)/length,(ref.z2-ref.z1)/length
    local nx,nz=dz,-dx
    local groups={}
    local tolerance=math.max(0.05,width*0.02)
    for _,item in ipairs(candidates) do
        local l=item.line
        local len=((l.x2-l.x1)^2+(l.z2-l.z1)^2)^0.5
        if item.crop==nearest.crop and math.abs(item.width-width)<=tolerance
            and math.abs((l.x2-l.x1)*dx+(l.z2-l.z1)*dz)/len>0.99995 then
            local lateral=((l.x1+l.x2)*nx+(l.z1+l.z2)*nz)/2
            local a,b=l.x1*dx+l.z1*dz,l.x2*dx+l.z2*dz
            if a>b then a,b=b,a end
            local group
            for _,g in ipairs(groups) do if math.abs(g.lateral-lateral)<=tolerance then group=g; break end end
            if not group then group={lateral=lateral,intervals={}};table.insert(groups,group) end
            table.insert(group.intervals,{a=a,b=b})
        end
    end
    table.sort(groups,function(a,b) return a.lateral<b.lateral end)
    local lines={}
    for i,g in ipairs(groups) do
        table.sort(g.intervals,function(a,b) return a.a<b.a end)
        local a,b=g.intervals[1].a,g.intervals[1].b
        for j=2,#g.intervals do
            if g.intervals[j].a>b+0.1 then self.scanError='CP_error_plantation_layout';return false end
            b=math.max(b,g.intervals[j].b)
        end
        if i>1 and math.abs(g.lateral-groups[i-1].lateral-width)>tolerance then
            self.scanError='CP_error_plantation_layout';return false
        end
        table.insert(lines,{x1=dx*a+nx*g.lateral,z1=dz*a+nz*g.lateral,x2=dx*b+nx*g.lateral,z2=dz*b+nz*g.lateral})
    end
    local best,bestDistance=1,math.huge
    for i=1,4 do
        local l=lines[i<=2 and 1 or #lines]
        local x,z=l.x1,l.z1
        if i%2==0 then x,z=l.x2,l.z2 end
        local d=(x-tx)^2+(z-tz)^2
        if d<bestDistance then best,bestDistance=i,d end
    end
    if best>=3 then local reversed={};for i=#lines,1,-1 do table.insert(reversed,lines[i]) end;lines=reversed end
    if best%2==0 then for _,l in ipairs(lines) do l.x1,l.x2,l.z1,l.z2=l.x2,l.x1,l.z2,l.z1 end end
    lines.preserveEndpoints=true
    lines.selection=vertices
    self.lines,self.width,self.selection=lines,width,vertices
    return true
end
-- Adjacent rows may have different lengths: only work between them over their overlap.
function VineScanner.createDrivingLines(lines,width,between)
    if not between then return lines end
    local result={preserveEndpoints=lines.preserveEndpoints}
    for i=1,#lines-1 do
        local a,b=lines[i],lines[i+1]
        local len=((a.x2-a.x1)^2+(a.z2-a.z1)^2)^0.5
        local dx,dz=(a.x2-a.x1)/len,(a.z2-a.z1)/len
        local start=math.max(0,(b.x1-a.x1)*dx+(b.z1-a.z1)*dz)
        local finish=math.min(len,(b.x2-a.x1)*dx+(b.z2-a.z1)*dz)
        if finish-start>0.01 then
            local normal=((b.x1-a.x1)*dz-(b.z1-a.z1)*dx)/2
            local lane={x1=a.x1+dx*start+dz*normal,z1=a.z1+dz*start-dx*normal,
                x2=a.x1+dx*finish+dz*normal,z2=a.z1+dz*finish-dx*normal}
            local parts=lines.selection and clip(lane,lines.selection) or {lane}
            if #parts~=1 then return {} end
            table.insert(result,parts[1])
        else
            return {}
        end
    end
    return result
end
function VineScanner:getCourseGeneratorVertices(offset,tx,tz)
    local lines=self.lines and VineScanner.createDrivingLines(self.lines,self.width,offset~=0)
    if not lines or #lines==0 then self.scanError='CP_error_plantation_no_rows';return end
    local first=lines[1]
    local len=((first.x2-first.x1)^2+(first.z2-first.z1)^2)^0.5
    local dx,dz=(first.x2-first.x1)/len,(first.z2-first.z1)/len
    local points={}
    for _,l in ipairs(lines) do
        for _,v in ipairs({{x=l.x1,z=l.z1},{x=l.x2,z=l.z2}}) do
            for _,side in ipairs({-1,1}) do
                table.insert(points,{x=v.x+side*dz*self.width/2,z=v.z-side*dx*self.width/2})
            end
        end
    end
    table.sort(points,function(a,b) return a.x<b.x or a.x==b.x and a.z<b.z end)
    local function turn(a,b,c) return cross(b.x-a.x,b.z-a.z,c.x-b.x,c.z-b.z) end
    local hull={}
    for _,v in ipairs(points) do
        while #hull>=2 and turn(hull[#hull-1],hull[#hull],v)<=0 do table.remove(hull) end
        table.insert(hull,v)
    end
    local lower=#hull
    for i=#points-1,1,-1 do
        local v=points[i]
        while #hull>lower and turn(hull[#hull-1],hull[#hull],v)<=0 do table.remove(hull) end
        table.insert(hull,v)
    end
    self.fieldBorder=hull
    return hull,self.width,{x=first.x1,z=first.z1},-math.deg(MathUtil.getYRotationFromDirection(dx,dz))
end
function VineScanner:getLines() return self.lines end
function VineScanner:drawSegments(lines)
    for _,l in ipairs(lines) do
        local y1=getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode,l.x1,0,l.z1)
        local y2=getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode,l.x2,0,l.z2)
        drawDebugLine(l.x1,y1+2,l.z1,1,0,0,l.x2,y2+2,l.z2,0,1,0)
    end
end

function VineScanner:debug(...)
	CpUtil.debugVehicle(CpDebug.DBG_COURSES, CpUtil.getCurrentVehicle(), 'VineScanner: ' .. string.format(...))
end

function VineScanner:debugSparse(...)
	if g_updateLoopIndex % 100 == 0 then
        self:debug(...)
    end
end

function VineScanner:draw()
	if CpUtil.getCurrentVehicle() and CpDebug:isChannelActive(CpDebug.DBG_COURSES, CpUtil.getCurrentVehicle()) and self:foundVines() then
		self:drawSegments(self.lines)
		self:drawFieldBorder()
	end
end

function VineScanner:drawFieldBorder()
	if self.fieldBorder then 
		local step = 1/(#self.fieldBorder -1)
		for i = 1, #self.fieldBorder-1 do 
			local x1, z1 = self.fieldBorder[i].x,  self.fieldBorder[i].z
			local x2, z2 = self.fieldBorder[i+1].x, self.fieldBorder[i+1].z
			local y1, y2 = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x1, 0, z1), getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x2, 0, z2)
			drawDebugLine(x1, y1 + 2, z1, 1, 1, (i-1)*step, x2, y2 + 2, z2, 1, 1, i*step)
		end
	end
end

g_vineScanner = VineScanner()
