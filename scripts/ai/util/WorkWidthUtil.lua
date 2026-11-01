---@class WorkWidthUtil
WorkWidthUtil = {}

--- Iterator for all work areas of an object
---@param object table
function WorkWidthUtil.workAreaIterator(object)
    local i = 0
    return function()
        i = i + 1
        local wa = WorkWidthUtil.hasValidWorkArea(object) and object:getWorkAreaByIndex(i)
        if wa then
            return i, wa
        end
    end
end

--- Gets work areas if possible.
---@param object table
function WorkWidthUtil.hasWorkAreas(object)
    return WorkWidthUtil.hasValidWorkArea(object) and object:getWorkAreaByIndex(1)
end

function WorkWidthUtil.hasValidWorkArea(object)
    return object and object.getWorkAreaByIndex and object.spec_workArea.workAreas
end

--- Gets the working width and offset calculated from all built-in and attached implements. If an implement has
--- a width or offset configured, it takes precedence over the calculated values.
---
--- Working width can be tricky if there are multiple implements attached. There is no guarantee that all work areas are
--- in the centerline of the vehicle, for instance mowers can be offset on one side. To get the true working width, we must
--- collect distance of the work area edges left and right for all implements and use the maximum left/right values to
--- calculate the width. This also results in an offset, which is the distance between the vehicle's centerline and the
--- middle of the work area.
---
--- Giants has a function ( fieldCourseSettings, implementData = FieldCourseSettings.generate(self.vehicle))
--- which pretty much does what we do here, but it is not able to handle all the implements Courseplay is able to use,
--- like shovels, shields, soil samplers, etc. So first, we check those special ones and then we fall back to the
--- official way of getting the work width using AI markers and side offset provided by the AIImplement functions.
---
---@param object table
---@param referenceNode number the node for calculating the work width, if not supplied, use the object's root node
---@param ignoreObject table ignore this object when calculating the width (as it is being detached, for instance)
---@return number width
---@return number offset
---@return number|nil left
---@return number|nil right
function WorkWidthUtil.getAutomaticWorkWidthAndOffset(object, referenceNode, ignoreObject)
    -- when first called for the vehicle, referenceNode is empty, so use the vehicle root node
    referenceNode = referenceNode or object.rootNode
    WorkWidthUtil.debug(object, 'getting working width...')
    -- check if we have a manually configured working width
    local configuredWidth = g_vehicleConfigurations:get(object, 'workingWidth')
    local configuredOffset = g_vehicleConfigurations:get(object, 'toolOffsetX')

    local left, right

    if object.getVariableWorkWidth and
        (not object.spec_variableWorkWidth or object.spec_variableWorkWidth.isActive ~= false) then
        --- Gets the variable work width to the left + to the right.
        local w1, _, isValid1 = object:getVariableWorkWidth(true)
        local w2, _, isValid2 = object:getVariableWorkWidth()
        if isValid1 and isValid2 then
            -- GIANTS returns absolute half-widths for both sides. CP uses
            -- signed coordinates: left is positive and right is negative.
            left, right = math.abs(w1), -math.abs(w2)
            local width = left - right
            WorkWidthUtil.debug(object, 'left = %.1f, right = %.1f, setting variable work width of %.1f.',
                    w1, w2, width)
        end
    end

    if object.spec_dynamicMountAttacher then 
        --- Enables fetching the work with of cutter, 
        --- which are attached on an separate header trailer 
        --- at the back of the harvester.
        local spec = object.spec_dynamicMountAttacher
        local obj = next(spec.dynamicMountedObjects)
        if obj then 
            if obj.spec_cutter then 
                WorkWidthUtil.debug(obj, 'Using this cutter instead of the header trailer %s attached.',
                    CpUtil.getName(object))
                object = obj
                referenceNode = obj.rootNode
            end
        end
    end

    --- Work width for soil samplers.
    local soilSamplerSpecName = CpUtil.getSoilSamplerSpecName()
    if not left and object[soilSamplerSpecName] then
        if object[soilSamplerSpecName].samplingRadius then
            local width = 2 * object[soilSamplerSpecName].samplingRadius / math.sqrt(2)
            left, right = width / 2, -width / 2
            WorkWidthUtil.debug(object, 'using soil sampler width of %.1f (from sampling radius).', width)
        else
            WorkWidthUtil.debug(object, 'soil sampler has no sampling radius, can\'t calculate width')
        end
    end

    --- Work width levelers
    if not left then 
        local width = WorkWidthUtil.getShieldWorkWidth(object)
        if width then 
            left, right = width / 2, -width / 2
        end
    end

    --- Now that we checked all special cases, and none of them had a hit, we still don't have a left/right
    --- value. We can now finally try the official way of getting the work width.
    if not left then
        -- no manual config, check AI markers
        _, left, right = WorkWidthUtil.getAIMarkerWidth(object)
    end

    if not left then
        if WorkWidthUtil.hasWorkAreas(object) then
            -- no AI markers, check work areas
            left, right = WorkWidthUtil.getWorkAreaWidth(object, referenceNode)
            if not left then
                WorkWidthUtil.debug(object, 'has NO valid work areas')
            end
        else
            WorkWidthUtil.debug(object, 'has NO work areas')
        end
    end

    local implements = object.getAttachedImplements and object:getAttachedImplements()
    if implements then
        -- get width of all implements
        for _, implement in ipairs(implements) do
            if implement.object ~= ignoreObject then
                local _, _, thisLeft, thisRight = WorkWidthUtil.getAutomaticWorkWidthAndOffset(implement.object)
                if thisLeft ~= nil and thisRight ~= nil then
                    left = math.max(thisLeft, left or -math.huge)
                    right = math.min(thisRight, right or math.huge)
                end
            end
        end
    end

    -- left > 0, right < 0. Offset > 0 and offset < 0 when the center line of all work areas are to the left and right,
    -- respectively, of the vehicle.
    local width, offset
    if configuredWidth then
        width = configuredWidth
        -- for now, assuming offset 0
        left = width / 2
        right = - width / 2
        WorkWidthUtil.debug(object, 'using configured working width of %.1f, resulting left/right is %.1f/%.1f.',
                configuredWidth, left, right)
    elseif left and right then
        width = left - right
        WorkWidthUtil.debug(object, 'working width is %.1f, left %.1f, right %.1f.', width, left, right)
    elseif not width then
        width = 0
        left = nil
        right = nil
        WorkWidthUtil.debug(object, 'could not determine working width')
    end

    if configuredOffset then
        offset = configuredOffset
        if width == 0 then
            -- some vine tools have no working width but we do have a configured offset. Make sure that
            -- the vehicle will inherit this offset by returning a left, right pair at offset
            left, right = offset, offset
        else
            left = width / 2 + offset
            right = - width / 2 + offset
        end
        WorkWidthUtil.debug(object, 'using configured tool offset of %.1f, resulting left/right is %.1f/%.1f.',
                configuredOffset, left, right)
    elseif width and left and right then
        offset = left - width / 2
        WorkWidthUtil.debug(object, 'calculated tool offset is %.1f.', offset)
    else
        offset = 0
        WorkWidthUtil.debug(object, 'could not determine offset, using 0')
    end

    return width, offset, left, right
end

---@param object table
function WorkWidthUtil.getWorkAreaWidth(object, referenceNode)
    -- TODO: check if there's a better way to find out if the implement has a work area
    local hasValidWorkArea, maxLeft, minRight = false, -math.huge, math.huge
    for i, wa in WorkWidthUtil.workAreaIterator(object) do
        if WorkWidthUtil.isValidWorkArea(wa) then
            hasValidWorkArea = true
            -- work areas are defined by three nodes: start, width and height. These nodes
            -- define a rectangular work area which you can make visible with the
            -- gsVehicleDebugAttributes console command and then pressing F5
            local left, _, _ = localToLocal(wa.start, referenceNode, 0, 0, 0)
            local right, _, _ = localToLocal(wa.width, referenceNode, 0, 0, 0)
            maxLeft = math.max(maxLeft, left)
            minRight = math.min(minRight, right)
            WorkWidthUtil.debug(object, 'work area %d is %s, left = %.1f, right %.1f m',
                    i, g_workAreaTypeManager.workAreaTypes[wa.type].name, left, right)
        end
    end
    if hasValidWorkArea then
        return maxLeft, minRight
    else
        return nil, nil
    end
end

---@param object table
function WorkWidthUtil.getAIMarkerWidth(object)
    if object.getAIMarkers then
        object:updateAIMarkerWidth()
        local aiLeftMarker, aiRightMarker, aiBackMarker, inverted, aiMarkerWidth = object:getAIMarkers()
        -- Giants sideOffset is negative for left, positive for right, the opposite of what we have
        local sideOffset = -object:getAIImplementSideOffset()
        if aiLeftMarker and aiRightMarker and aiMarkerWidth then
            local left = aiMarkerWidth * 0.5 + sideOffset
            local right = -aiMarkerWidth * 0.5 + sideOffset
            WorkWidthUtil.debug(object, 'aiMarkers: left=%.2f, right=%.2f (width %.2f, sideOffset %.2f)',
                    left, right, aiMarkerWidth, sideOffset)
            return aiMarkerWidth, left, right
        end
    end
end

--- Gets ai markers for an object.
---@param object table
function WorkWidthUtil.getAIMarkers(object, suppressLog)
    local aiLeftMarker, aiRightMarker, aiBackMarker = object:getAIMarkers()
    if not aiLeftMarker or not aiRightMarker or not aiBackMarker then
        -- use the root node if there are no AI markers
        if not suppressLog then
            WorkWidthUtil.debug(object, 'has no AI markers, try work areas')
        end
        aiLeftMarker, aiRightMarker, aiBackMarker = WorkWidthUtil.getAIMarkersFromWorkAreas(object, suppressLog)
        if not aiLeftMarker or not aiRightMarker or not aiLeftMarker then
            if g_vehicleConfigurations:get(object, 'useVehicleSizeForMarkers') or object.spec_leveler then
                if not suppressLog then
                    WorkWidthUtil.debug(object, 'has no work areas, configured to use front/back markers')
                end
                return Markers.getFrontMarkerNode(object), Markers.getFrontMarkerNode(object), Markers.getBackMarkerNode(object)
            else
                if not suppressLog then
                    WorkWidthUtil.debug(object, 'has no work areas, giving up')
                end
                return nil, nil, nil
            end
        else
            if not suppressLog then
                WorkWidthUtil.debug(object, 'AI markers from work area set')
            end
            return aiLeftMarker, aiRightMarker, aiBackMarker
        end
    else
        if not suppressLog then
            WorkWidthUtil.debug(object, 'AI markers set')
        end
        return aiLeftMarker, aiRightMarker, aiBackMarker
    end
end

--- Calculate the front and back marker nodes of a work area
---@param object table
function WorkWidthUtil.getAIMarkersFromWorkAreas(object, suppressLog)
    -- work areas are defined by three nodes: start, width and height. These nodes
    -- define a rectangular work area which you can make visible with the
    -- gsVehicleDebugAttributes console command and then pressing F5
    for _, area in WorkWidthUtil.workAreaIterator(object) do
        if WorkWidthUtil.isValidWorkArea(area) then
            -- for now, just use the first valid work area we find
            if not suppressLog then
                WorkWidthUtil.debug(object, 'Using %s work area markers as AIMarkers',
                        g_workAreaTypeManager.workAreaTypes[area.type].name)
            end
            return area.start, area.width, area.height
        end
    end
end

---@param area table
function WorkWidthUtil.isValidWorkArea(area)
    return area.start and area.height and area.width and
            area.type ~= WorkAreaType.RIDGEMARKER and
            area.type ~= WorkAreaType.COMBINESWATH and
            area.type ~= WorkAreaType.COMBINECHOPPER
end

---@param object table
function WorkWidthUtil.getShieldWorkWidth(object)
    if object.spec_leveler and object.spec_leveler.nodes and object.spec_leveler.nodes[1] then
        local width = object.spec_leveler.nodes[1].width
        WorkWidthUtil.debug(object, 'is a shield with width: %.1f', width)
        return width
    end
end

---@param object table
function WorkWidthUtil.getShovelWorkWidth(object)
    if object.spec_shovel and object.spec_shovel.shovelNodes and object.spec_shovel.shovelNodes[1] then
        local width = object.spec_shovel.shovelNodes[1].width
        WorkWidthUtil.debug(object, 'is a shovel with width: %.1f', width)
        return width
    end
end

--- Shows the current work width selected with the tool offsets applied.
---@param vehicle table
---@param workWidth number
---@param offsX number
---@param offsZ number
function WorkWidthUtil.showWorkWidth(vehicle, workWidth, offsX, offsZ)
    local firstObject = AIUtil.getFirstAttachedImplement(vehicle, true)
    local lastObject = AIUtil.getLastAttachedImplement(vehicle, true)

    local function show(object, workWidth, offsX, offsZ)
        if object == nil then
            return
        end
        local f, b = 0, 0
        local aiLeftMarker, _, aiBackMarker = object:getAIMarkers()
        if aiLeftMarker and aiBackMarker then
            _, _, b = localToLocal(aiBackMarker, object.rootNode, 0, 0, 0)
            _, _, f = localToLocal(aiLeftMarker, object.rootNode, 0, 0, 0)
        end

        local left = (workWidth * 0.5) + offsX
        local right = (workWidth * -0.5) + offsX

        local p1x, p1y, p1z = localToWorld(object.rootNode, left, 1.6, b - offsZ)
        local p2x, p2y, p2z = localToWorld(object.rootNode, right, 1.6, b - offsZ)
        local p3x, p3y, p3z = localToWorld(object.rootNode, right, 1.6, f - offsZ)
        local p4x, p4y, p4z = localToWorld(object.rootNode, left, 1.6, f - offsZ)

        --   cpDebug:drawPoint(p1x, p1y, p1z, 1, 1, 0)
        -- cpDebug:drawPoint(p2x, p2y, p2z, 1, 1, 0)
        -- cpDebug:drawPoint(p3x, p3y, p3z, 1, 1, 0)
        -- cpDebug:drawPoint(p4x, p4y, p4z, 1, 1, 0)


        DebugUtil.drawDebugLine(p1x, p1y, p1z, p2x, p2y, p2z, 1, 0, 0)
        DebugUtil.drawDebugLine(p2x, p2y, p2z, p3x, p3y, p3z, 1, 0, 0)
        DebugUtil.drawDebugLine(p3x, p3y, p3z, p4x, p4y, p4z, 1, 0, 0)
        DebugUtil.drawDebugLine(p4x, p4y, p4z, p1x, p1y, p1z, 1, 0, 0)
    end
    show(firstObject, workWidth, offsX, offsZ)
    if firstObject ~= lastObject then
        show(lastObject, workWidth, offsX, offsZ)
    end
end

---@param implement table
function WorkWidthUtil.debug(implement, ...)
    CpUtil.debugImplement(CpDebug.DBG_IMPLEMENTS, implement, ...)
end
