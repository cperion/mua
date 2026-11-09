-- Optional experiment. LUA_PATH='/path/to/luafun/?.lua;;' luajit bench/luafun_compiler.lua [iterations]
-- Isolated trace: ... bench/luafun_compiler.lua --trace staged /tmp/mua-fun.trace
-- Trace choices: staged, assembled, interpreted, handwritten. Compare traces, not
-- just timings: a fast result alone does not prove fusion or zero allocations.
local root = arg[0]:match('^(.*)/bench/[^/]*$') or '.'
package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path
local Compiler = assert(require('mua.init').loadfile(root .. '/examples/luafun/compiler.mua'))('library')
local function even(value) return value % 2 == 0 end
local function square(value) return value * value end
local source = {}
for index = 1, 4096 do source[index] = index end
local function cases_for(limit, filtering)
    if filtering == nil then filtering = limit ~= nil end
    local plan = Compiler.describe(function(verbs)
        if filtering then verbs.filter(even) end
        verbs.map(square)
        if limit ~= nil then verbs.take(limit) end
    end)
    local staged = Compiler.compile(plan)
    local function handwritten(values)
        if limit == nil and not filtering then
            local total = 0
            for index = 1, #values do total = total + values[index] * values[index] end
            return total
        end
        if limit == 0 then return 0 end
        local total, taken = 0, 0
        for index = 1, #values do
            local value = values[index]
            if not filtering or value % 2 == 0 then
                total = total + value * value
                taken = taken + 1
                if taken == limit then break end
            end
        end
        return total
    end
    local cases = {
        { name = 'handwritten', run = handwritten },
        { name = 'interpreted', run = function(values) return Compiler.interpret(plan, values) end },
        { name = 'assembled', run = function(values) return Compiler.assemble_and_run(plan, values) end },
        { name = 'staged', run = staged },
    }
    local expected = handwritten(source)
    for _, case in ipairs(cases) do
        assert(case.run(source) == expected, case.name)
        -- Per-case driver keeps the operation out of a per-item strategy dispatch.
        local run = case.run
        case.repeat_run = function(iterations)
            local checksum = 0
            for _ = 1, iterations do checksum = checksum + run(source) end
            return checksum
        end
    end
    return cases, expected, plan
end

if arg[1] == '--trace' then
    local limit = 128
    if arg[4] == 'map' then limit = nil end
    local filtering
    if arg[4] == 'map-take' then filtering = false end
    if arg[4] == 'filter-map' then limit, filtering = nil, true end
    local cases, expected = cases_for(limit, filtering)
    local selected
    for _, case in ipairs(cases) do if case.name == arg[2] then selected = case end end
    assert(selected, 'trace needs staged, assembled, interpreted or handwritten')
    assert(arg[3], 'trace needs an output path')
    jit.flush()
    local dump = require 'jit.dump'
    dump.start('im', arg[3])
    local checksum = selected.repeat_run(1000)
    dump.off()
    assert(checksum == expected * 1000)
    print(('trace %s -> %s; checksum %.0f'):format(selected.name, arg[3], checksum))
    return
end

local iterations = tonumber(arg[1]) or 1000
assert(iterations > 0 and iterations % 1 == 0)
local function median(values)
    table.sort(values)
    return values[math.floor(#values / 2) + 1]
end
local function heap_per_call(case, expected)
    collectgarbage(); collectgarbage()
    collectgarbage('stop')
    local before = collectgarbage('count')
    local ok, checksum = pcall(case.repeat_run, 100)
    local bytes = (collectgarbage('count') - before) * 1024 / 100
    collectgarbage('restart')
    assert(ok and checksum == expected * 100, checksum)
    return bytes
end
print(('LuaJIT %s; JIT %s; seven alternating samples, %d invocations each'):format(
    jit.version, tostring(jit.status()), iterations))
print('Dense source: 4096 numbers; map-only positive control, then filter even -> square -> take N -> sum.')
print('Times include invocation setup and normal GC; compile-once setup is excluded.')
print('Heap column: GC-stopped Lua heap growth per invocation, NOT allocation counts or RSS.')
for _, workload in ipairs { { name = 'map only' },
        { name = 'map -> take 128', limit = 128, filtering = false },
        { name = 'filter -> map', filtering = true }, { name = 'take 0', limit = 0 },
        { name = 'take 8', limit = 8 }, { name = 'take 128', limit = 128 },
        { name = 'take 1024', limit = 1024 } } do
    local cases, expected, plan = cases_for(workload.limit, workload.filtering)
    for _, case in ipairs(cases) do
        assert(case.repeat_run(500) == expected * 500)
        case.samples = {}
    end
    for sample = 1, 7 do
        for offset = 1, #cases do
            local index = sample % 2 == 0 and offset or #cases - offset + 1
            local case = cases[index]
            collectgarbage(); collectgarbage()
            local start = os.clock()
            local checksum = case.repeat_run(iterations)
            local elapsed = (os.clock() - start) * 1e9 / iterations
            assert(checksum == expected * iterations)
            case.samples[#case.samples + 1] = elapsed
        end
    end
    print(('\n%s; result %.0f'):format(workload.name, expected))
    print(('  %-15s %12s %12s %14s'):format('engine', 'ns/run', 'vs manual', 'heap bytes/run'))
    local baseline = median(cases[1].samples)
    for _, case in ipairs(cases) do
        local elapsed = median(case.samples)
        local memories = {}
        for index = 1, 5 do memories[index] = heap_per_call(case, expected) end
        print(('  %-15s %12.1f %11.2fx %14.1f'):format(case.name, elapsed,
            elapsed / baseline, median(memories)))
    end
    -- Report the work moved to preparation, too. Retain closures in a small ring.
    local retained = {}
    local start = os.clock()
    for index = 1, 1000 do retained[index % 64 + 1] = Compiler.compile(plan) end
    print(('  compile once: %.2f us/program (single batch, not a median)'):format((os.clock() - start) * 1000))
end
