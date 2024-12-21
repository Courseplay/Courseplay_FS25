--- Reverse the order of elements in an array in place
---@param a []
function CourseGenerator.reverseArray(a)
    for i = 1, #a / 2 do
        a[i], a[#a - i + 1] = a[#a - i + 1], a[i]
    end
end
