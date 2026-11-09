local R = require 'mua.runtime'
local outline = require 'mua.outline'
local function render(value, opts) return outline.render({ n = 1, value }, opts) end
local called = false
local save = R.label('Save')(function() called = true end)
local root = R.label('Editor')({ save = save, hidden = 3 })
assert(render(root, { locations = false }) == 'Editor  #1\n└─ save  Save  ƒ  #2\n\n2 labeled values · 1 callable\n')
local info = debug.getinfo(save, 'S')
assert(render(root):find(info.source:sub(2) .. ':' .. info.linedefined, 1, true))
local from_mua = assert(require('mua.init').load('\n\nreturn label "Located" do() return 1 end', '@located.mua'))()
assert(render(from_mua):find('located.mua:3', 1, true))
local native = R.label('native')(print)
assert(not render(native):find(':%d+'))
local stripped = assert(loadstring(string.dump(function() return 1 end, true)))
assert(render(R.label('stripped')(stripped)):find('stripped', 1, true))
local saved_debug = debug
_G.debug = nil
assert(render(root):find('Save', 1, true))
_G.debug = saved_debug
assert(not called)
root.again = save
root.self = root
local output = render(root)
assert(output:find('↩ #', 1, true))
assert(output:find('2 labeled values · 1 callable', 1, true))
assert(not output:find('hidden', 1, true))
local cycle = {}; cycle.self = cycle; cycle.child = root
assert(render(cycle):find('Editor', 1, true))
local opaque = setmetatable({}, {
    __index = function() error('index invoked') end,
    __pairs = function() error('pairs invoked') end,
    __tostring = function() error('tostring invoked') end,
})
assert(render(opaque) == 'No labeled values returned.\n')
root[opaque] = R.label('opaque key')({})
assert(render(root):find('<table key>', 1, true))
local escaped = R.label('a\nb\27')({})
assert(render(escaped):find('a\\nb\\x1b', 1, true))
assert(outline.render({ n = 3, [2] = save }):find('Save', 1, true))
assert(render(cycle, { max_depth = 0 }):find('depth limit', 1, true))
assert(not pcall(render, root, { max_entries = 1 }))
assert(render({ a = { b = R.label('leaf')({}) } }):find('leaf', 1, true))
local empty = {}; empty.self = empty
assert(render(empty) == 'No labeled values returned.\n')
print('outline: passed')
