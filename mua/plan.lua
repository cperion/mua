-- Internal operation plans contain structure, never runtime identities or values.
local M = {}
function M.struct(fields, unchecked)
    local count = 0
    for _ in ipairs(fields) do count = count + 1 end
    return { operation = 'struct', fields = count, checked = not unchecked }
end
function M.key(plan)
    assert(plan.operation == 'struct', 'unknown specialization operation')
    assert(type(plan.fields) == 'number' and plan.fields >= 0 and plan.fields % 1 == 0)
    return ('struct:%d:%s'):format(plan.fields, tostring(plan.checked))
end
return M
