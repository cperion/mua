-- Run with the same LuaJIT as make test. No generated program is executed twice
-- against shared mutable inputs: each strategy receives a fresh scenario.
local root = arg[0]:match('^(.*)/tests/[^/]*$') or '.'
package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path
local R = require 'mua.runtime'
local Plan = require 'mua.plan'
local Specialize = require 'mua.specialize'
local Compile = require 'mua.specialize.compile'
local passed = 0
local function check(ok, message)
    assert(ok, message)
    passed = passed + 1
end
local function message(f)
    local ok, err = pcall(f)
    assert(not ok, 'expected a failure')
    return tostring(err):gsub('^.-:%d+: ', '')
end
local reports = {}
for _, mode in ipairs { 'generic', 'generated' } do
    local runtime, engine = R.specialized { mode = mode }
    local P = runtime.struct('Point', { { 'x', R.Number }, { 'y', R.Number } })
    local Q = runtime.struct('Other', { { 'x', R.Number }, { 'y', R.Number } })
    local original = { x = 1, y = 2 }
    local p = P(original)
    check(p == original, mode .. ' preserves identity')
    check(R.check(P, p) and not R.check(Q, p), mode .. ' preserves nominal identity')
    P.sum = function(self) return self.x + self.y end
    check(p:sum() == 3, mode .. ' methods remain dynamic')
    local F = runtime.family('points'); F { P, Q }
    local walk = F.pass('sum') { Point = function(v) return v.x + v.y end, Other = function(v) return v.x end }
    check(walk(p) == 3, mode .. ' interoperates with family dispatch')
    local Parent = runtime.struct('Parent', { { 'child', P } })
    local child = R.with { x = 3, y = 4 }
    check(Parent { child = child }.child == child and R.check(P, child), mode .. ' contextual conversion')
    local U = runtime.struct('Unchecked', { { 'x', R.Number } }, true)
    check(U { x = false, extra = true }.extra, mode .. ' unchecked behavior')
    local Empty = runtime.struct('Empty', {})
    check(R.check(Empty, Empty()), mode .. ' omitted input becomes a table')
    reports[mode] = {
        message(function() P(false) end),
        message(function() P { x = 'wrong', y = 2 } end),
        message(function() P { x = 1, y = 2, extra = true } end),
        message(function() P { x = 1 } end),
        message(function() U(false) end),
    }
    -- Do not freeze mutable field descriptors or predicate behavior.
    local fields = { { 'x', R.Number } }
    local Mutable = runtime.struct('Mutable', fields)
    fields[1][2] = R.String
    check(Mutable { x = 'now a string' }.x == 'now a string', mode .. ' live descriptor')
    fields[2] = { 'y', R.Optional(R.Number) }
    check(Mutable { x = 'extended' }.x == 'extended', mode .. ' descriptor grows')
    fields[1] = nil
    check(Mutable { x = false }.x == false, mode .. ' ipairs hole stops checks')
    -- A check may itself alter the later fields.
    local effects, changing = {}, {}
    changing[1] = { 'x', function(v)
        effects[#effects + 1] = 'x'
        changing[2] = { 'y', function(y) effects[#effects + 1] = 'y'; return y == 2 end }
        return v == 1
    end }
    local Changing = runtime.struct('Changing', changing)
    local err = message(function() Changing { x = 1 } end)
    check(err:find("field 'y'", 1, true) and table.concat(effects) == 'xy', mode .. ' effects during validation')
    if mode == 'generated' then
        check(engine.stats().hits > 0, 'same shapes share unbound code')
    end
end
for i, text in ipairs(reports.generic) do
    check(text == reports.generated[i], 'diagnostic parity: ' .. text .. ' / ' .. reports.generated[i])
end

local compiler = Compile.new { cache_limit = 2 }
local source = 'return function(value) return function() return value end end'
local factory = compiler.compile('a', source)
check(compiler.compile('a', source) == factory, 'cache hit')
local weak = setmetatable({}, { __mode = 'v' })
do
    local identity = {}
    local bound = factory(identity)
    weak[1], weak[2] = identity, bound
    check(bound() == identity, 'bound identity')
end
collectgarbage(); collectgarbage()
check(weak[1] == nil and weak[2] == nil, 'factory cache does not retain bindings')
compiler.compile('b', source); compiler.compile('c', source)
check(compiler.stats().cached == 2, 'bounded cache')
check(not pcall(compiler.compile, 'c', source .. ' '), 'cache collisions are errors')
check(not pcall(compiler.compile, 'broken', 'not Lua'), 'generation bugs are errors')

local engine = Specialize.new { mode = 'generated', max_fields = 1 }
local generic = function() end
local artifact = engine.prepare(Plan.struct({ {}, {} }), generic)
check(artifact.strategy == 'generic' and artifact.bind == generic, 'large plans use compact fallback')
check(Specialize.new { mode = 'auto' }.prepare(Plan.struct({ {} }), generic).strategy == 'generic',
    'auto does not enable an unproven optimization')
local generated = engine.prepare(Plan.struct({ {} }), generic)
check(generated.strategy == 'generated' and generated.source:find('rawget', 1, true), 'source is inspectable')
print(('specialization: %d checks passed'):format(passed))
