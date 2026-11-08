-- Validation at the Lua/native edge. No coercion of strings to numbers or truthy values.
local ffi = require 'ffi'
local Check = {}

-- Defaults apply only to absence; false must still fail a numeric/string contract.
function Check.default(value, fallback)
    if value == nil then return fallback end
    return value
end

function Check.number(value, name, minimum, maximum)
    if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge
        or (minimum and value < minimum) or (maximum and value > maximum) then
        error(name .. ': expected a finite number in range', 3)
    end
    return value
end

function Check.integer(value, name, minimum, maximum)
    Check.number(value, name, minimum or -2147483648, maximum or 2147483647)
    if value % 1 ~= 0 then error(name .. ': expected an integer', 3) end
    return value
end

function Check.string(value, name)
    if type(value) ~= 'string' or value:find('\0', 1, true) then
        error(name .. ': expected a string without NUL bytes', 3)
    end
    return value
end

function Check.boolean(value, name)
    if type(value) ~= 'boolean' then error(name .. ': expected a boolean', 3) end
    return value
end

function Check.callable(value, name)
    if type(value) ~= 'function' then error(name .. ': expected a function', 3) end
    return value
end

function Check.table(value, name)
    if type(value) ~= 'table' then error(name .. ': expected a table', 3) end
    return value
end

-- Arrays have no holes or extra keyed fields; counts passed to C are therefore trustworthy.
function Check.array(value, name)
    Check.table(value, name)
    local count = #value
    for key in pairs(value) do
        if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 or key > count then
            error(name .. ': expected a dense array', 3)
        end
    end
    for index = 1, count do
        if rawget(value, index) == nil then error(name .. ': array contains a hole', 3) end
    end
    return value
end

function Check.keys(value, allowed, name)
    Check.table(value, name)
    for key in pairs(value) do
        if not allowed[key] then error(name .. ': unknown field ' .. tostring(key), 3) end
    end
    return value
end

function Check.color(value, name)
    Check.array(value, name)
    if #value ~= 4 then error(name .. ': expected four RGBA channels', 3) end
    local channels = ffi.new('float[4]')
    for index = 1, 4 do channels[index - 1] = Check.number(value[index], name, 0, 1) end
    return channels
end

function Check.strings(value, name)
    Check.array(value, name)
    local pointers, retained = ffi.new('const char *[?]', math.max(1, #value)), {}
    for index, text in ipairs(value) do
        retained[index] = Check.string(text, name)
        pointers[index - 1] = retained[index]
    end
    return pointers, retained
end

return Check
