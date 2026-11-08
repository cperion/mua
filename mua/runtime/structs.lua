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
-- the metamethods a struct's methods of those names become for its instances
local instance_metamethods = {
    __call = true, __tostring = true, __eq = true, __lt = true, __le = true, __len = true, __concat = true,
    __add = true, __sub = true, __mul = true, __div = true, __mod = true, __pow = true, __unm = true,
}
-- A method defined on a struct under a hook's name changes its instances: `__index` answers the
-- members its fields and methods do not, `__newindex` receives the members it lacks, and the
-- other metamethods become the instances' own.
local function hook(S, info, contract, describe, key, value)
    rawset(S, key, value)
    local name = info.name
    if key == '__index' then
        if type(value) ~= 'function' then
            error(("%s's __index answers the members it lacks: it is a method, got %s"):format(name, describe(value)), 3)
        end
        info.meta.__index = function(instance, member)
            local method = S[member]
            if method ~= nil then return method end
            return value(instance, member)
        end
    elseif key == '__newindex' then
        if type(value) ~= 'function' then
            error(("%s's __newindex receives the members it lacks: it is a method, got %s"):format(name, describe(value)), 3)
        end
        info.meta.__newindex = function(instance, member, assigned)
            local declared = info.index[member]
            if declared then
                rawset(instance, member, contract(declared, assigned, 2, "the field '%s' of %s", member, name))
                return
            end
            value(instance, member, assigned)
        end
    elseif instance_metamethods[key] then
        if type(value) ~= 'function' then
            error(("%s's %s is its instances' metamethod: it is a method, got %s"):format(name, key, describe(value)), 3)
        end
        info.meta[key] = value
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
            __newindex = function(_, key, value) hook(S, info, contract, describe, key, value) end,
            __call = construct,
        })
        return S
    end
end
return M
