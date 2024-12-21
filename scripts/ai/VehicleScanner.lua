--- Determine the exact size of a vehicle
---@class VehicleScanner
VehicleScanner = CpObject()

function VehicleScanner:init(vehicle)
    self.vehicle = vehicle
end

function VehicleScanner:debug(...)
    CpUtil.debugVehicle(CpUtil.DBG_IMPLEMENTS, self.vehicle, ...)
end

--- Determine the exact width of a vehicle. The configured width in vehicle.size.width seems to be very
--- inaccurate, 0.5-0.8 m wider than the actual width of the vehicle. Therefore, we can't use that for instance
--- when targeting a bale for pickup where we want to drive as close to the bale as possible.
---
--- Therefore, we use a raycast to find the side of the vehicle. Note that we raycast at 1 m above ground, so
--- we only know how wide the vehicle is at this level. TODO: improve this and use non-horizontal raycasts.
function VehicleScanner:measureWidth()
    local nx, ny, nz = localDirectionToWorld(self.vehicle.rootNode, 0, 0, 1)
    for d = 0.5, self.vehicle.size.width / 2 + 0.5, 0.1 do
        self.hit = false
        local x, y, z = localToWorld(self.vehicle.rootNode, d, 1, -self.vehicle.size.length / 2 + self.vehicle.size.lengthOffset)
        raycastAll(x, y, z, nx, ny, nz, self.vehicle.size.length, 'raycastBackCallback', self)
        if not self.hit then
            self.width = 2 * d
            self:debug('Found vehicle width %.1f', self.width)
            return self.width
        end
    end
    self:debug('Could not determine width, using configured %.1f', self.vehicle.size.width)
    return self.vehicle.size.width
end

function VehicleScanner:raycastBackCallback(hitObjectId, x, y, z, distance, nx, ny, nz, subShapeIndex)
    if hitObjectId ~= 0 then
        local object = g_currentMission:getNodeObject(hitObjectId)
        if object and object == self.vehicle then
            self.hit = true
        else
            return true
        end
    end
end