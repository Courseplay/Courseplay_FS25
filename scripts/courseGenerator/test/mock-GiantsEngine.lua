-- Mock the Giants engine functions for unit tests
local MathUtil = {}

function CpMathUtil.clamp(val, min, max)
    return math.min(math.max(val, min), max)
end

