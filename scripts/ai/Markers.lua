
--[[
    These markers can be added to a vehicle:
        - front marker node:
            - moved all the way to the front of the vehicle or the front most attached implement.
        - back marker node:
            - moved all the way to the back of the vehicle or the rear most attached implement.

        - front marker offset:
            - distance between the vehicle direction node and the front maker node (positive)
        - back marker offset:
            - distance between the vehicle direction node and the back maker node (negative)

]]

Markers = {}

function Markers.registerConsoleCommands()
    g_devHelper.consoleCommands:registerConsoleCommand("cpFrontAndBackerMarkerCalculate", 
        "Calculates the front and back markers", "consoleCommandReload", Markers)
    g_devHelper.consoleCommands:registerConsoleCommand("cpFrontAndBackerMarkerPrintDebug", 
        "Print Marker data", "consoleCommandPrintDebug", Markers)
end
Markers.registerConsoleCommands()
-- a global table with the vehicle as the key to persist the marker nodes we don't want to leak through jobs
-- and also don't want to deal with keeping track when to delete them
g_vehicleMarkers = {}

local function createMarkerIfDoesNotExist(vehicle, name, referenceNode)
    if not g_vehicleMarkers[vehicle] then
        g_vehicleMarkers[vehicle] = {}
    end
    if not g_vehicleMarkers[vehicle][name] then
        g_vehicleMarkers[vehicle][name] = CpUtil.createNode(name, 0, 0, 0, referenceNode)
    end
end

-- Put a node on the back of the vehicle for easy distance checks use this instead of the root/direction node
local function setBackMarkerNode(vehicle, measuredBackDistance)
    local backMarkerOffset = 0
    local referenceNode
    local reverserNode, debugText = AIUtil.getReverserNode(vehicle)
    if AIUtil.hasImplementsOnTheBack(vehicle) then
        local lastImplement
        lastImplement, backMarkerOffset = AIUtil.getLastAttachedImplement(vehicle)
        referenceNode = AIUtil.getDirectionNode(vehicle)
        CpUtil.debugVehicle(CpDebug.DBG_IMPLEMENTS, vehicle, 'Using the last implement\'s rear distance for the back marker node, %d m from root node', backMarkerOffset)
    elseif measuredBackDistance then
        referenceNode = AIUtil.getDirectionNode(vehicle)
        backMarkerOffset = -measuredBackDistance
        CpUtil.debugVehicle(CpDebug.DBG_IMPLEMENTS, vehicle, 'back marker node on measured back distance %.1f', measuredBackDistance)
    elseif reverserNode then
        -- if there is a reverser node, use that, mainly because that most likely will turn with an implement
        -- or with the back component of an articulated vehicle. Just need to find out the distance correctly
        local dx, _, dz = localToLocal(reverserNode, AIUtil.getDirectionNode(vehicle), 0, 0, 0)
        local dBetweenRootAndReverserNode = MathUtil.vector2Length(dx, dz)
        backMarkerOffset = dBetweenRootAndReverserNode - vehicle.size.length / 2 - vehicle.size.lengthOffset
        referenceNode = reverserNode
        CpUtil.debugVehicle(CpDebug.DBG_IMPLEMENTS, vehicle, 'Using the %s node for the back marker node %d m from root node (%d m between root and reverser)',
                debugText, backMarkerOffset, dBetweenRootAndReverserNode)
    else
        referenceNode = AIUtil.getDirectionNode(vehicle)
        backMarkerOffset = - vehicle.size.length / 2 + vehicle.size.lengthOffset
        CpUtil.debugVehicle(CpDebug.DBG_IMPLEMENTS, vehicle, 'Using the vehicle\'s root node for the back marker node, %d m from root node', backMarkerOffset)
    end

    createMarkerIfDoesNotExist(vehicle, 'backMarkerNode', referenceNode)
    -- relink to current reference node (in case of implement change for example
    unlink(g_vehicleMarkers[vehicle].backMarkerNode)
    link(referenceNode, g_vehicleMarkers[vehicle].backMarkerNode)
    setTranslation(g_vehicleMarkers[vehicle].backMarkerNode, 0, 0, backMarkerOffset)
    g_vehicleMarkers[vehicle].backMarkerOffset = backMarkerOffset
end

-- Put a node on the front of the vehicle for easy distance checks use this instead of the root/direction node
local function setFrontMarkerNode(vehicle)
    local firstImplement, frontMarkerOffset = AIUtil.getFirstAttachedImplement(vehicle)
    CpUtil.debugVehicle(CpDebug.DBG_IMPLEMENTS, vehicle, 'Using the %s\'s direction node for the front marker node, %d m from direction node',
            CpUtil.getName(firstImplement), frontMarkerOffset)

    createMarkerIfDoesNotExist(vehicle, 'frontMarkerNode',  AIUtil.getDirectionNode(vehicle))
    -- relink to current reference node (in case of implement change for example
    unlink(g_vehicleMarkers[vehicle].frontMarkerNode)
    link( AIUtil.getDirectionNode(vehicle), g_vehicleMarkers[vehicle].frontMarkerNode)
    setTranslation(g_vehicleMarkers[vehicle].frontMarkerNode, 0, 0, frontMarkerOffset)
    g_vehicleMarkers[vehicle].frontMarkerOffset = frontMarkerOffset
end

--- Create two nodes, one on the front and one on the back of the vehicle (including implements). The front node
--- is just in front of any attached implements, the back node is just behind all attached implements.
--- These nodes can be used for distance measurements or to link proximity sensors to them
---@param vehicle table
---@param measuredBackDistance number|nil optional distance between the root node of the vehicle and the back of the vehicle if known
function Markers.setMarkerNodes(vehicle, measuredBackDistance)
    setBackMarkerNode(vehicle, measuredBackDistance)
    setFrontMarkerNode(vehicle)
end

--- Get the front marker node and offset
---@param vehicle table
---@return number, number the front marker node, distance of front marker node from the vehicle's root node
function Markers.getFrontMarkerNode(vehicle)
    if not g_vehicleMarkers[vehicle] or not g_vehicleMarkers[vehicle].frontMarkerNode then
        setFrontMarkerNode(vehicle)
    end
    return g_vehicleMarkers[vehicle].frontMarkerNode, g_vehicleMarkers[vehicle].frontMarkerOffset
end

--- Get the back marker node and offset
---@param vehicle table
---@return number, number the back marker node, distance of back marker node from the vehicle's root node, most likely
--- negative, as it will be behind the root node...
function Markers.getBackMarkerNode(vehicle)
    if not g_vehicleMarkers[vehicle] or not g_vehicleMarkers[vehicle].backMarkerNode then
        setBackMarkerNode(vehicle)
    end
    return g_vehicleMarkers[vehicle].backMarkerNode, g_vehicleMarkers[vehicle].backMarkerOffset
end

--- Gets the front/back markers. This is relative to the AI direction, so even with
--- reverse driving vehicles (with cabin reversed) front should always be in right direction.
---@param vehicle table
---@return number front marker
---@return number back marker
function Markers.getMarkerNodes(vehicle)
    local frontMarker = Markers.getFrontMarkerNode(vehicle)
    local backMarker = Markers.getBackMarkerNode(vehicle)
    return frontMarker, backMarker, g_vehicleMarkers[vehicle].frontMarkerOffset, g_vehicleMarkers[vehicle].backMarkerOffset
end

--------------------------------------------
--- Console Commands
--------------------------------------------

function Markers:consoleCommandReload(backDistance)
    local vehicle = CpUtil.getCurrentVehicle()
    if not vehicle then 
        CpUtil.info("No valid vehicle entered!")
        return     
    end
    if backDistance then 
        backDistance = tonumber(backDistance)
    end
    Markers.setMarkerNodes(vehicle, backDistance)
    Markers:consoleCommandPrintDebug()
end

function Markers:consoleCommandPrintDebug()
    local vehicle = CpUtil.getCurrentVehicle()
    if not vehicle then 
        CpUtil.info("No valid vehicle entered!")
        return     
    end
    local _, frontMarkerDistance = Markers.getFrontMarkerNode(vehicle)
    local _, backMarkerDistance = Markers.getBackMarkerNode(vehicle)
    CpUtil.infoVehicle(vehicle, "Front distance: %.2f, back distance: %.2f", frontMarkerDistance, backMarkerDistance)
end
