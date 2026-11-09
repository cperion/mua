-- Equivalent-work comparison, with isolated traversal changes and demand tests.
-- The rewriting rows compare a list per answer with a shared iterator per answer.
-- Run from repository root using the patched LuaJIT: luajit bench/lisp_pull.lua [iterations]
local root = arg[0]:match('^(.*)/bench/[^/]*$') or '.'
package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path
local mua = require 'mua.init'
local eager = assert(mua.loadfile(root .. '/examples/lisp.mua'))('library')
local pull = assert(mua.loadfile(root .. '/examples/lisp_pull.mua'))('library', eager)
local iterations = tonumber(arg[1]) or 10
assert(iterations >= 1 and iterations % 1 == 0)
local samples = 7
local ring = {}
local function median(values)
    table.sort(values)
    return values[math.floor(#values / 2) + 1]
end
local function timed(operation, count)
    collectgarbage(); collectgarbage()
    local start = os.clock()
    for index = 1, count do ring[index % 8 + 1] = operation() end
    return (os.clock() - start) * 1e6 / count
end
local function heap_growth(operation)
    -- Warm first, then measure heap growth while GC cannot reclaim intermediates.
    -- This is NOT RSS, peak resident memory, or an allocation count.
    ring = {}; collectgarbage(); collectgarbage()
    collectgarbage('stop')
    local before = collectgarbage('count')
    local ok, result = pcall(operation)
    local growth = collectgarbage('count') - before
    collectgarbage('restart')
    assert(ok, result)
    ring[1] = result
    return growth
end
local function compare(title, cases, count)
    for _, case in ipairs(cases) do
        case.times = {}
        for _ = 1, 20 do ring[1] = case.run() end
    end
    for round = 1, samples do
        for offset = 1, #cases do
            local index = round % 2 == 0 and offset or #cases - offset + 1
            local case = cases[index]
            case.times[#case.times + 1] = timed(case.run, count)
        end
    end
    print('\n' .. title)
    print(('  %-24s %12s %12s %12s'):format('strategy', 'median us', 'relative', 'heap KiB'))
    local base = median(cases[1].times)
    for _, case in ipairs(cases) do
        local elapsed = median(case.times)
        local memory = {}
        for index = 1, 5 do memory[index] = heap_growth(case.run) end
        print(('  %-24s %12.1f %11.2fx %12.1f'):format(case.name, elapsed, elapsed / base, median(memory)))
    end
end

-- Multiple functions keep each Lua function below the emitter's 200-local limit.
-- All are reachable through calls, so sweeping cannot just delete the workload.
local definitions = {}
for index = 1, 16 do
    local body = index == 1 and 'n' or ('(f%d n)'):format(index - 1)
    for term = 1, 10 do body = ('(+ %s %d)'):format(body, term) end
    definitions[#definitions + 1] = ('(define f%d (lambda (n) %s))'):format(index, body)
end
local program = table.concat(definitions, '\n') .. '\n(f16 7)'
local baseline = eager.compile(program)
local other = pull.compile(program)
assert(eager.same(baseline.tree, other.tree))
assert(eager.same(baseline.instructions, other.instructions))
assert(eager.same(baseline.optimized, other.optimized))
assert(baseline.lua == other.lua)
local expected = 7 + 16 * 55
assert(assert(loadstring(baseline.lua))() == expected)
assert(eager.evaluate(baseline.tree, {}) == expected)
print(('LuaJIT: %s; JIT %s; contracts on; %d samples, %d iterations'):format(
    jit.version, tostring(jit.status()), samples, iterations))
print(('Equivalent workload: %d source bytes, %d instructions, result %d'):format(
    #program, eager.instruction_count(baseline.instructions), expected))
print('Timing includes normal GC; heap is median GC-stopped growth for ONE operation after warm-up.')

local reader_only = eager.make_compiler(pull.read, eager.optimize)
local rewrites_only = eager.make_compiler(eager.read, pull.optimizer.optimize)
compare('Full compilation (not execution; shared language and passes)', {
    { name = 'eager', run = function() return eager.compile(program) end },
    { name = 'pull reader only', run = function() return reader_only(program) end },
    { name = 'triple rewrites only', run = function() return rewrites_only(program) end },
    { name = 'both', run = function() return pull.compile(program) end },
}, iterations)
compare('Reader: complete input, identical datum lists', {
    { name = 'eager', run = function() return eager.read(program) end },
    { name = 'pull then collect', run = function() return pull.read(program) end },
}, iterations * 10)
compare('Optimizer: same already-lowered input, identical output', {
    { name = 'replacement lists', run = function() return eager.optimize(baseline.instructions) end },
    { name = 'replacement triples', run = function() return pull.optimizer.optimize(baseline.instructions) end },
}, iterations)

-- These are deliberately demand comparisons, NOT claims of faster full compilation.
local prefix_source = '(+ 20 22) ' .. program:rep(20)
compare('Demand: first datum only (eager reads the unused tail)', {
    { name = 'eager then first', run = function() return eager.read(prefix_source)[1] end },
    { name = 'pull one form', run = function()
        local cursor = pull.forms(prefix_source)
        return cursor()
    end },
}, iterations)
local batch = {}
for index = 1, 8 do batch[index] = program end
compare('Demand: first complete program in an eight-program batch', {
    { name = 'eager batch then first', run = function()
        local compiled = {}
        for index, source in ipairs(batch) do compiled[index] = eager.compile(source) end
        return compiled[1]
    end },
    { name = 'pull one program', run = function()
        local cursor = pull.compiled_programs(batch)
        return cursor()
    end },
}, math.max(1, math.floor(iterations / 4)))
print('\nNo throughput claim follows from the demand rows: they perform intentionally different amounts of work.')
