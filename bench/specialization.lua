-- Paired medians, escaping allocations, and declaration cost. Run separately
-- from micro.lua: these cases compare runtime strategies, not surface syntax.
local root = arg[0]:match('^(.*)/bench/[^/]*$') or '.'
package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path
local R = require 'mua.runtime'
local iterations = tonumber(arg[1]) or 200000
local function median(values)
    table.sort(values)
    return values[math.floor(#values / 2) + 1]
end
local function time(f, n)
    collectgarbage(); collectgarbage()
    local start = os.clock()
    f(n)
    return (os.clock() - start) * 1e9 / n
end
print('fields  generic ns/op  generated ns/op  ratio  declare generic/generated us')
for _, count in ipairs { 0, 2, 8, 16, 32 } do
    local cases = {}
    for _, mode in ipairs { 'generic', 'generated' } do
        local runtime = R.specialized { mode = mode }
        local fields = {}
        for i = 1, count do fields[i] = { 'x' .. i, R.Number } end
        local S = runtime.struct('Bench', fields)
        local ring = {}
        local function run(n)
            for i = 1, n do
                local value = {}
                for k = 1, count do value['x' .. k] = i end
                ring[i % 64 + 1] = S(value)
            end
        end
        run(10000)
        cases[mode] = { run = run, samples = {}, declare = function(n)
            for i = 1, n do ring[i % 64 + 1] = runtime.struct('Bench', fields) end
        end }
    end
    -- Alternate order to reduce systematic thermal/order bias.
    for repetition = 1, 7 do
        local order = repetition % 2 == 0 and { 'generic', 'generated' } or { 'generated', 'generic' }
        for _, mode in ipairs(order) do
            local c = cases[mode]
            c.samples[#c.samples + 1] = time(c.run, iterations)
        end
    end
    local a, b = median(cases.generic.samples), median(cases.generated.samples)
    local da, db = time(cases.generic.declare, 1000), time(cases.generated.declare, 1000)
    print(('%6d %14.1f %16.1f %6.2f %12.2f / %.2f'):format(count, a, b, b / a, da / 1000, db / 1000))
end
print('32 fields uses the size-limited generic fallback; declaration timings use a warm factory cache.')
