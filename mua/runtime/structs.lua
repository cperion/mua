-- Struct declaration owns identity; specialization owns only constructor shape.
local Plan = require 'mua.plan'
local M = {}
local function generic(fields, index, meta, name, contract, describe,
        type, pairs, rawget, setmetatable, error, tostring)
    return function(_, t)
        if t == nil then t = {} end
        if type(t) ~= 'table' then error(('%s takes a table of fields, got %s'):format(name, describe(t)), 2) end
        for k in pairs(t) do
            if not index[k] then error(("%s has no field '%s'"):format(name, tostring(k)), 2) end
        end
        for _, f in ipairs(fields) do
            local v = contract(f[2], t[f[1]], 3, "the field '%s' of %s", f[1], name)
            if v ~= t[f[1]] then t[f[1]] = v end
        end
        return setmetatable(t, meta)
    end
end
local function unchecked(fields, index, meta, name, contract, describe,
        type, pairs, rawget, setmetatable, error, tostring)
    return function(_, t)
        if t == nil then t = {} end
        if type(t) ~= 'table' then error(('%s takes a table of fields, got %s'):format(name, describe(t)), 2) end
        return setmetatable(t, meta)
    end
end
function M.new(structs, instance_of, contract, describe, specialize)
    return function(name, fields, is_unchecked)
        local S = {}
        local info = { name = name, fields = fields, index = {}, meta = { __index = S, __name = name, __label = name } }
        for _, f in ipairs(fields) do info.index[f[1]] = f[2] end
        structs[S] = info
        instance_of[info.meta] = S
        local artifact = specialize.prepare(Plan.struct(fields, is_unchecked), is_unchecked and unchecked or generic)
        local construct = artifact.bind(fields, info.index, info.meta, name, contract, describe,
            type, pairs, rawget, setmetatable, error, tostring)
        setmetatable(S, {
            __label = name,
            __tostring = function() return name end,
            __call = construct,
        })
        return S
    end
end
return M
