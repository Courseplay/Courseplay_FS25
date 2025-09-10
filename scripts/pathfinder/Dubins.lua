--[[
* Copyright (c) 2008-2018, Andrew Walker
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
* THE SOFTWARE.
*/

This is the lua port of the original C implementation by Peter Vaiko for Courseplay:

@Misc{DubinsCurves,
  author = {Andrew Walker},
  title  = {Dubins-Curves: an open implementation of shortest paths for the forward only car},
  year   = {2008--},
  url    = "https://github.com/AndrewWalker/Dubins-Curves"
}

]]--

local sin, cos, acos, atan2, abs, sqrt, floor = math.sin, math.cos, math.acos,  math.atan2, math.abs, math.sqrt, math.floor

--- Implement interface for the hybrid A* code
---@class DubinsSolution : AnalyticSolution
DubinsSolution = CpObject(AnalyticSolution)

function DubinsSolution:init(pathDescriptor)
    self.pathDescriptor = pathDescriptor
end

function DubinsSolution:getLength(turnRadius)
    return dubins_path_length(self.pathDescriptor)
end

function DubinsSolution:getWaypoints(start, turnRadius)
    -- waypoints are 1 m apart, but make sure there are at least 12 waypoints per half circle
    -- even with very small radii
    return dubins_path_sample_many(self.pathDescriptor, math.min(1, turnRadius * math.pi / 12))
end

local twoPi = 2 * math.pi

local function mod2pi( theta )
    return theta - twoPi * floor(theta / twoPi)
end

function dubins_path(path, q0, q1, rho, pathType)
    local errcode
    local ir = dubins_intermediate_results(q0, q1, rho)
    if ir then
        local params = {}
        errcode = DubinsSolver.PathTypeFunctions[pathType](ir, params)
        if errcode == EDUBOK then
            path.param[1] = params[1]
            path.param[2] = params[2]
            path.param[3] = params[3]
            path.qi.x = q0.x
            path.qi.y = q0.y
            path.qi.t = q0.t
            path.rho = rho
            path.type = pathType
        end
    end
end

function dubins_path_length(path)
    local length = 0
    length = length + path.param[1]
    length = length + path.param[2]
    length = length + path.param[3]
    length = length * path.rho
    return length
end

function dubins_segment_length(path, i)
    if i < 1 or i > 3 then
        return math.huge
    end
    return path.param[i] * path.rho
end

function dubins_segment_length_normalized(path, i)
    if i < 1 or i > 3 then
        return math.huge
    end
    return path.param[i]
end

function dubins_segment(t, qi, qt, type)
    local st = sin(qi.t)
    local ct = cos(qi.t)
    if type == "L" then
        qt.x = sin(qi.t+t) - st
        qt.y = -cos(qi.t+t) + ct
        qt.t = t
    elseif type == "R" then
        qt.x = -sin(qi.t-t) + st
        qt.y = cos(qi.t-t) - ct
        qt.t = -t
    elseif type == "S" then
        qt.x = ct * t
        qt.y = st * t
        qt.t = 0.0
    end
    qt.x = qt.x + qi.x
    qt.y = qt.y + qi.y
    qt.t = qt.t + qi.t
end

-- create once for performance
local dps_qi, dps_q1, dps_q2

function dubins_path_sample(path, t)
    -- tprime is the normalised variant of the parameter t */
    local tprime = t / path.rho
    local p1, p2

    if t < 0 or t > dubins_path_length(path) then return end

    -- initial configuration */
    dps_qi.x, dps_qi.y, dps_qi.t = 0, 0, path.qi.t -- The translated initial configuration */
    dps_q1.x, dps_q1.y, dps_q1.t = 0, 0, 0 -- end-of segment 1 */
    dps_q2.x, dps_q2.y, dps_q2.t = 0, 0, 0 -- end-of segment 2 */
    local q = State3D(0, 0, 0, 0, nil, Gear.Forward)
    -- generate the target configuration */
    p1 = path.param[1]
    p2 = path.param[2]

    dubins_segment( p1,  dps_qi,  dps_q1, path.type1)
    dubins_segment( p2,  dps_q1,  dps_q2, path.type2)

    if tprime < p1 then
        dubins_segment( tprime, dps_qi, q, path.type1)
    elseif tprime < (p1 + p2) then
        dubins_segment(tprime - p1, dps_q1, q, path.type2)
    else
        dubins_segment(tprime - p1 - p2, dps_q2, q, path.type3)
    end

    -- scale the target configuration, translate back to the original starting point */
    q.x = q.x * path.rho + path.qi.x
    q.y = q.y * path.rho + path.qi.y
    q.t = mod2pi(q.t)
    return q
end

function dubins_path_sample_many(path, stepSize)
    local result = {}
    local length = dubins_path_length(path)
    dps_qi = State3D(0, 0, 0) -- The translated initial configuration */
    dps_q1 = State3D(0, 0, 0) -- end-of segment 1 */
    dps_q2 = State3D(0, 0, 0) -- end-of segment 2 */

    local series = CpMathUtil.getSeries(0, length, stepSize)

    for _, x in ipairs(series) do
        local q = dubins_path_sample(path, x)
        table.insert(result, q)
        x = x + stepSize
    end
    return result
end

function dubins_intermediate_results(q0, q1, rho)
    local ir = {}
    local dx, dy, D, d, theta, alpha, beta
    if rho <= 0.0 then
        return
    end
    dx = q1.x - q0.x
    dy = q1.y - q0.y
    D = sqrt( dx * dx + dy * dy )
    d = D / rho
    theta = 0

    -- test required to prevent domain errors if dx=0 and dy=0 */
    if d > 0 then
        theta = mod2pi(atan2(dy, dx))
    end
    alpha = mod2pi(q0.t - theta)
    beta  = mod2pi(q1.t - theta)

    ir.alpha = alpha
    ir.beta  = beta
    ir.d     = d
    ir.sa    = sin(alpha)
    ir.sb    = sin(beta)
    ir.ca    = cos(alpha)
    ir.cb    = cos(beta)
    ir.c_ab  = cos(alpha - beta)
    ir.two_c_ab = 2 * ir.c_ab
    ir.d_sq  = d * d

    return ir
end

function dubins_LSL(ir)
    local tmp0, tmp1, p_sq

    tmp0 = ir.d + ir.sa - ir.sb
    p_sq = 2 + ir.d_sq - (ir.two_c_ab) + (2 * ir.d * (ir.sa - ir.sb))

    if p_sq >= 0 then
        tmp1 = atan2( (ir.cb - ir.ca), tmp0 )
        return mod2pi(tmp1 - ir.alpha), sqrt(p_sq), mod2pi(ir.beta - tmp1), "LSL"
    end
end


function dubins_RSR(ir)
    local tmp0 = ir.d - ir.sa + ir.sb
    local p_sq = 2 + ir.d_sq - (ir.two_c_ab) + (2 * ir.d * (ir.sb - ir.sa))
    if p_sq >= 0 then
        local tmp1 = atan2( (ir.ca - ir.cb), tmp0 )
        return mod2pi(ir.alpha - tmp1), sqrt(p_sq), mod2pi(tmp1 -ir.beta), "RSR"
    end
end

function dubins_LSR(ir)
    local p_sq = -2 + (ir.d_sq) + (ir.two_c_ab) + (2 * ir.d * (ir.sa + ir.sb))
    if p_sq >= 0 then
        local p = sqrt(p_sq)
        local tmp0 = atan2( (-ir.ca - ir.cb), (ir.d + ir.sa + ir.sb) ) - atan2(-2.0, p)
        return mod2pi(tmp0 - ir.alpha), p, mod2pi(tmp0 - mod2pi(ir.beta)), "LSR"
    end
end

function dubins_RSL(ir)
    local p_sq = -2 + ir.d_sq + (ir.two_c_ab) - (2 * ir.d * (ir.sa + ir.sb))
    if p_sq >= 0 then
        local p = sqrt(p_sq)
        local tmp0 = atan2( (ir.ca + ir.cb), (ir.d - ir.sa - ir.sb) ) - atan2(2.0, p)
        return mod2pi(ir.alpha - tmp0), p, mod2pi(ir.beta - tmp0), 'RSL'
    end
end

function dubins_RLR(ir)
    local tmp0 = (6. - ir.d_sq + ir.two_c_ab + 2 * ir.d * (ir.sa - ir.sb)) / 8.
    local phi  = atan2( ir.ca - ir.cb, ir.d - ir.sa + ir.sb )
    if abs(tmp0) <= 1 then
        local p = mod2pi(twoPi - acos(tmp0) )
        local t = mod2pi(ir.alpha - phi + mod2pi(p/2.))
        return t, p, mod2pi(ir.alpha - ir.beta - t + mod2pi(p)), "RLR"
    end
end

function dubins_LRL(ir)
    local tmp0 = (6. - ir.d_sq + ir.two_c_ab + 2 * ir.d * (ir.sb - ir.sa)) / 8.
    local phi = atan2( ir.ca - ir.cb, ir.d + ir.sa - ir.sb )
    if abs(tmp0) <= 1 then
        local p = mod2pi( twoPi - acos( tmp0) )
        local t = mod2pi(-ir.alpha - phi + p/2.)
        return t, p, mod2pi(mod2pi(ir.beta) - ir.alpha -t + mod2pi(p)), "LRL"
    end
end

---@class DubinsSolver : AnalyticSolver
DubinsSolver = CpObject(AnalyticSolver)

DubinsSolver.PathTypeFunctions = {
    dubins_LSL,
    dubins_LSR,
    dubins_RSL,
    dubins_RSR,
    dubins_RLR,
    dubins_LRL
}

-- Dubins words (path types, Left/Straight/Right
DubinsSolver.PathType = {}
DubinsSolver.PathType.LSL = 1
DubinsSolver.PathType.LSR = 2
DubinsSolver.PathType.RSL = 3
DubinsSolver.PathType.RSR = 4
DubinsSolver.PathType.RLR = 5
DubinsSolver.PathType.LRL = 6

---@param enabledPathTypes number[] list of DubinsSolver.PathTypes we want to restrict the solution to
function DubinsSolver:init(enabledPathTypes)
    if enabledPathTypes then
        self.enabledPathTypeFunctions = {}
        for _, type in pairs(enabledPathTypes) do
            if DubinsSolver.PathTypeFunctions[type] then
                table.insert(self.enabledPathTypeFunctions, DubinsSolver.PathTypeFunctions[type])
            end
        end
    else
        -- try all types if not restricted
        self.enabledPathTypeFunctions = DubinsSolver.PathTypeFunctions
    end
end

---@param q0 State3D start
---@param q1 State3D goal
---@param rho number turning radius
function DubinsSolver:solve(q0, q1, rho)
    local path = {}
    local ir = {}
    local params = {}
    local cost
    local best_cost = math.huge
    local best_word = -1
    ir = dubins_intermediate_results(q0, q1, rho)
    if not ir then
        return
    end

    path.qi = {}
    path.qi.x = q0.x
    path.qi.y = q0.y
    path.qi.t = q0.t
    path.rho = rho
    path.param = {}

    local pathType

    for _, dubins_path_type_function in pairs(self.enabledPathTypeFunctions) do
        params[1], params[2], params[3], pathType = dubins_path_type_function(ir, params)
        if params[1] then
            cost = params[1] + params[2] + params[3]
            if cost < best_cost then
                best_word = pathType
                best_cost = cost
                path.param[1] = params[1]
                path.param[2] = params[2]
                path.param[3] = params[3]
                path.type = pathType
                path.type1 = string.sub(path.type, 1, 1)
                path.type2 = string.sub(path.type, 2, 2)
                path.type3 = string.sub(path.type, 3, 3)
            end
        end
    end
    if best_word == -1 then
        return nil
    end
    return DubinsSolution(path), path.type
end
