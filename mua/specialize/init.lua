-- Preparation happens once per declaration. Calls execute the bound operation
-- directly, with no strategy branch and no compiler/cache lookup.
local Plan = require 'mua.plan'
local Generate = require 'mua.specialize.generate'
local Compile = require 'mua.specialize.compile'
local M = {}
function M.new(options)
    options = options or {}
    local mode = options.mode or 'generic'
    assert(mode == 'generic' or mode == 'generated' or mode == 'auto', 'invalid specialization mode')
    local max_fields = options.max_fields or 16
    assert(type(max_fields) == 'number' and max_fields >= 0 and max_fields % 1 == 0)
    local compiler = Compile.new(options)
    local api = { stats = compiler.stats }
    function api.prepare(plan, generic)
        local key = Plan.key(plan)
        -- Auto stays conservative until a strategy has repeatable workload wins.
        if mode ~= 'generated' or plan.fields > max_fields then
            return { strategy = 'generic', bind = generic }
        end
        local source = Generate.struct(plan)
        local factory = compiler.compile('v1:' .. key, source)
        return { strategy = 'generated', bind = factory, source = source }
    end
    return api
end
return M
