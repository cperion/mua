-- Optional integration test: LUA_PATH='/path/to/luafun/?.lua;;' make test-luafun
local root = arg[0]:match('^(.*)/tests/[^/]*$') or '.'
package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path
local available, problem = pcall(require, 'fun')
assert(available, 'Lua Fun is optional; put luafun/?.lua on LUA_PATH first:\n' .. tostring(problem))
for _, name in ipairs { 'idioms', 'compiler' } do
    local path = root .. '/examples/luafun/' .. name .. '.mua'
    local file = assert(io.open(path, 'rb'))
    local source = file:read('*a'); file:close()
    local expected = assert(source:match('\n%-%-%[=%[ output\n(.*)%]=%]\n?$'))
    local chunk = assert(require('mua.init').load(source, '@' .. path))
    local output = {}
    local environment = setmetatable({ print = function(...)
        local values = {}
        for index = 1, select('#', ...) do values[index] = tostring(select(index, ...)) end
        output[#output + 1] = table.concat(values, '\t') .. '\n'
    end }, { __index = _G })
    setfenv(chunk, environment)
    chunk()
    assert(table.concat(output) == expected, name .. ': example output changed')
    local formatted = require('mua.fmt').format(source, nil, path)
    assert(formatted == source, name .. ': example needs formatting')
    assert(require('mua.fmt').format(formatted, nil, path) == formatted, name .. ': formatting is not idempotent')
    print('Lua Fun: ' .. name .. ' assertions, output and formatting passed')
end
