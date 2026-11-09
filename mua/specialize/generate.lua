-- Trusted templates only. Names, contracts and metatables are factory bindings,
-- not interpolated code. Unroll descriptor traversal, not mutable contract values.
local M = {}
function M.struct(plan)
    local out = {
        'return function(fields, index, meta, name, contract, describe, type, pairs, rawget, setmetatable, error, tostring)',
        'return function(_, t)',
        'if t == nil then t = {} end',
        [[if type(t) ~= 'table' then error(('%s takes a table of fields, got %s'):format(name, describe(t)), 2) end]],
    }
    local function put(s) out[#out + 1] = s end
    local function check()
        put([=[local v = contract(f[2], t[f[1]], 3, "the field '%s' of %s", f[1], name)]=])
        put('if v ~= t[f[1]] then t[f[1]] = v end')
    end
    if plan.checked then
        put([[for k in pairs(t) do if not index[k] then error(("%s has no field '%s'"):format(name, tostring(k)), 2) end end]])
        for i = 1, plan.fields do
            put('do local f = rawget(fields, ' .. i .. ')')
            -- ipairs stops at a hole; contracts may mutate later descriptors.
            put('if f == nil then return setmetatable(t, meta) end')
            check()
            put('end')
        end
        -- Runtime callers can mutate the original field list, even during a check.
        -- Preserve that behavior rather than silently treating the list as frozen.
        put('local i = ' .. (plan.fields + 1))
        put('while true do local f = rawget(fields, i); if f == nil then break end')
        check()
        put('i = i + 1 end')
    end
    put('return setmetatable(t, meta) end end')
    return table.concat(out, '\n')
end
return M
