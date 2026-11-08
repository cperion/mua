-- Native BUI FFI contract tests. Run through bui/native's CTest target.
-- The interpreter may be stock LuaJIT: this boundary contains no Mua-only syntax.
local root = arg[0]:match('^(.*)/tests/[^/]*$') or '.'
package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path
local ffi = require 'ffi'
local binding = require 'bui.ffi'
local library_path = assert(arg[1], 'provide libmua_bui.so and bui_abi_probe paths')
local probe_path = assert(arg[2], 'provide bui_abi_probe path')
local library = binding.load(library_path)
-- Lua -> C -> Lua cannot enter a Lua callback from a compiled FFI call.
-- The raw binding does not silently change the application's JIT policy.
jit.off()

local checks = 0
local function check(condition, message)
    checks = checks + 1
    assert(condition, message)
end

check(require('bui.ffi') == binding, 'require is idempotent')
check(not pcall(binding.load), 'load requires a path')
check(not pcall(binding.load, ''), 'load rejects an empty path')
check(not pcall(binding.load, library_path .. '.missing'), 'missing library is not ignored')
check(library.BK_version() == 500, 'kit version')
check(ffi.string(library.BK_version_string()) == binding.BUI_KIT_VERSION_STRING, 'kit version string')
-- The legacy sink API reports its own older version. It is not the kit ABI check.
local version = ffi.new('int[3]')
library.bui_get_version(version, version + 1, version + 2)
check(version[0] == 0 and version[1] == 1 and version[2] == 0, 'sink version')

-- Exercise both loader mismatch refusals without loading an incompatible native ABI.
do
    local original_load = ffi.load
    local ok, problem = pcall(function()
        ffi.load = function()
            return { mua_bui_binding_version = function() return 2 end }
        end
        local loaded, message = pcall(binding.load, 'wrong-binding')
        check(not loaded and message:find('binding version', 1, true), 'binding version refusal')
        ffi.load = function()
            return { mua_bui_binding_version = function() return 1 end,
                BK_version = function() return 499 end }
        end
        loaded, message = pcall(binding.load, 'wrong-kit')
        check(not loaded and message:find('kit version', 1, true), 'kit version refusal')
    end)
    ffi.load = original_load
    assert(ok, problem)
end

local public_symbols, seen = 0, {}
for name in (require 'bui.cdef'):gmatch('([%a_][%w_]*)%s*%(') do
    if name:match('^BK_') or name:match('^BUI_') or name:match('^GPU_') or name:match('^bui_') then
        check(not seen[name], 'duplicate declaration: ' .. name)
        seen[name] = true
        check(type(library[name]) == 'cdata', 'missing native symbol: ' .. name)
        public_symbols = public_symbols + 1
    end
end
check(public_symbols == 296, 'complete public function inventory')

-- Compare every public record and field with the compiler's actual ABI measurements.
local quoted_probe = "'" .. probe_path:gsub("'", "'\\''") .. "'"
local probe = assert(io.popen('exec ' .. quoted_probe, 'r'))
local records, fields, constants, strings = 0, 0, 0, 0
for line in probe:lines() do
    local columns = {}
    for column in line:gmatch('[^\t]+') do columns[#columns + 1] = column end
    local kind, name = columns[1], columns[2]
    if kind == 'type' then
        check(ffi.sizeof(name) == tonumber(columns[3]), name .. ' size')
        check(ffi.alignof(name) == tonumber(columns[4]), name .. ' alignment')
        records = records + 1
    elseif kind == 'field' then
        local member = columns[3]
        check(ffi.offsetof(name, member) == tonumber(columns[4]), name .. '.' .. member .. ' offset')
        -- FFI reads scalar fields as Lua numbers; arrays and pointers retain their C type.
        local value = ffi.new(name)[member]
        if type(value) == 'cdata' then
            check(ffi.sizeof(value) == tonumber(columns[5]), name .. '.' .. member .. ' size')
        end
        fields = fields + 1
    elseif kind == 'constant' then
        check(tonumber(library[name]) == tonumber(columns[3]), name .. ' value')
        constants = constants + 1
    elseif kind == 'string' then
        check(binding[name] == columns[3], name .. ' value')
        strings = strings + 1
    else
        error('unexpected ABI probe output: ' .. line)
    end
end
check(probe:close(), 'ABI probe completed')
check(records == 17 and fields == 136 and constants == 141 and strings == 1, 'ABI probe coverage')

-- Keep explicit owners, with callbacks alive until the native host is disconnected.
local tree, context, raster, emit, clipboard_get, ramp
local function cleanup()
    if context ~= nil then
        library.BK_context_set_host(context, ffi.new('BKHost[1]'))
        library.BK_context_free(context)
    end
    if tree ~= nil then library.BK_node_free(tree) end
    if ramp ~= nil then library.BK_node_free(ramp) end
    if raster ~= nil then library.BUI_raster_free(raster) end
    if emit then emit:free() end
    if clipboard_get then clipboard_get:free() end
    library.BK_image_exit()
end
local function exercise()
    library.BUI_gpu_set_default(0)
    library.BK_set_animations(0)
    check(library.BK_node_new('not-a-widget') == nil, 'unknown node returns NULL')
    tree = library.BK_node_new('column')
    check(tree ~= nil, 'create root')
    local button = library.BK_node_new('button')
    check(button ~= nil, 'create button')
    check(library.BK_node_add(tree, button, -1) == 1, 'attach button')
    local number = library.BK_node_new('number')
    check(number ~= nil, 'create number')
    check(library.BK_node_add(tree, number, -1) == 1, 'attach number')
    check(library.BK_set_str(button, 'text', 'FFI button') == 1, 'set text')
    check(ffi.string(library.BK_get_str(button, 'text')) == 'FFI button', 'read copied text')
    check(library.BK_set_num(number, 'unknown_property', 1) == 0, 'unknown property remains a C refusal')
    check(library.BK_node_parent(button) == tree and library.BK_node_child_count(tree) == 2,
        'tree inspection')
    context = library.BK_context_new(tree)
    check(context ~= nil, 'create context')
    raster = library.BUI_raster_create(320, 120)
    check(raster ~= nil, 'create raster')

    local token = ffi.new('int[1]', 73)
    local events = {}
    emit = ffi.cast('void (*)(void *, BKNode *, int, void *, double, double)',
        function(data, node, kind, reference, first, second)
            -- No throwing, mutation or destruction while BUI's input stack is active.
            events[#events + 1] = { data = data, node = node, kind = kind,
                reference = reference, first = first, second = second }
        end)
    clipboard_get = ffi.cast('char *(*)(void *)', function()
        local text = 'native clipboard'
        local memory = library.mua_bui_malloc(#text + 1)
        if memory == nil then return nil end
        ffi.copy(memory, text, #text + 1)
        return ffi.cast('char *', memory)
    end)
    local host = ffi.new('BKHost[1]')
    host[0].data = token
    host[0].emit = emit
    host[0].clipboard_get = clipboard_get
    library.BK_context_set_host(context, host)
    collectgarbage('collect')
    check(library.BK_set_num(number, 'value', 1.5) == 1 and #events == 0, 'silent value setter')
    check(library.BK_set_num(number, 'set_value', 4.25) == 1, 'notifying value setter')
    check(#events == 1 and events[1].kind == library.BK_EV_CHANGE, 'change callback')
    check(events[1].node == number and events[1].data == ffi.cast('void *', token), 'callback pointers')
    check(events[1].first == 4.25 and events[1].second == 0, 'callback double arguments')
    check(library.BK_get_num(number, 'value') == 4.25, 'changed value')

    local clipboard = library.BK_clipboard_get(context)
    check(clipboard ~= nil, 'clipboard allocation')
    local clipboard_text = ffi.string(clipboard)
    library.mua_bui_free(clipboard)
    check(clipboard_text == 'native clipboard', 'clipboard allocator round trip')

    check(library.BK_render(context, raster, 320, 120, 1) > 0, 'headless render')
    check(library.BUI_raster_width(raster) == 320 and library.BUI_raster_height(raster) == 120,
        'raster dimensions')
    check(library.BUI_raster_pixels(raster) ~= nil, 'pixel buffer')
    local rectangles = ffi.new('const int (*[1])[4]')
    check(library.BUI_raster_damage(raster, rectangles) > 0 and rectangles[0] ~= nil,
        'pointer-to-array output')
    check(rectangles[0][0][2] > 0, 'damage rectangle width')
    check(library.BK_render(context, raster, 320, 120, 0) == 0, 'unchanged UI does not redraw')

    local rectangle = ffi.new('int[4]')
    library.BK_node_rect(button, rectangle)
    local x = rectangle[0] + math.floor(rectangle[2] / 2)
    local y = rectangle[1] + math.floor(rectangle[3] / 2)
    library.BK_press(context, x, y, 0)
    library.BK_release(context, x, y, 0)
    check(events[#events].kind == library.BK_EV_CLICK and events[#events].node == button,
        'headless input reaches callback')

    -- Removing a child detaches it; it does not free it when host refs are absent.
    library.BK_node_remove(tree, button)
    check(library.BK_node_parent(button) == nil, 'remove detaches')
    check(library.BK_node_add(tree, button, -1) == 1, 'reattach detached child')

    ramp = library.BK_node_new('ramp')
    check(ramp ~= nil, 'create ramp')
    local positions = ffi.new('float[2]', { 0, 1 })
    local colors = ffi.new('float[2][4]', { { 1, 0, 0, 1 }, { 0, 0, 1, 1 } })
    library.BK_ramp_set(ramp, positions, ffi.cast('const float (*)[4]', colors), 2)
    check(library.BK_ramp_count(ramp) == 2, 'pointer-to-array input')
    local position, color = ffi.new('float[1]'), ffi.new('float[4]')
    library.BK_ramp_get(ramp, 1, position, color)
    check(position[0] == 1 and color[2] == 1 and color[3] == 1, 'ramp output arrays')
    local result = ffi.new('double[1]')
    check(library.BK_eval_number('1/4', result) == 1 and result[0] == 0.25, 'double output pointer')
    check(library.BK_eval_number('not valid!', result) == 0, 'native expression rejection')

    library.bui_set_viewport(320, 120)
    library.bui_set_render_sink(library.BUI_raster_sink(raster))
    check(library.bui_get_render_sink() ~= nil, 'sink seam')
    library.bui_set_render_sink(nil)
end
local ok, problem = xpcall(exercise, debug.traceback)
-- Clear the global sink before its borrowed raster can disappear, including on failure.
library.bui_set_render_sink(nil)
cleanup()
assert(ok, problem)
print(('BUI FFI: %d checks; %d symbols, %d records, %d fields, %d numeric constants')
    :format(checks, public_symbols, records, fields, constants))
