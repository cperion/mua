-- A bounded cache of UNBOUND factories. Neither bindings nor user descriptors
-- enter this module. Each compiler owns its cache; no process-global retention.
local M = {}
function M.new(options)
    options = options or {}
    local limit = options.cache_limit or 64
    assert(type(limit) == 'number' and limit >= 0 and limit % 1 == 0)
    local cache, order = {}, {}
    local hits, compilations = 0, 0
    local api = {}
    function api.compile(key, source)
        local entry = cache[key]
        if entry then
            assert(entry.source == source, 'specialization cache key collision')
            hits = hits + 1
            return entry.factory
        end
        local chunk, err = loadstring(source, '=mua.specialize.' .. key)
        if not chunk then error('specialization generation failed: ' .. err, 0) end
        setfenv(chunk, {}) -- generated code receives all dependencies as arguments
        local factory = chunk()
        assert(type(factory) == 'function', 'specialization did not produce a factory')
        compilations = compilations + 1
        if limit > 0 then
            if #order == limit then cache[table.remove(order, 1)] = nil end
            order[#order + 1] = key
            cache[key] = { factory = factory, source = source }
        end
        return factory
    end
    function api.stats()
        return { cached = #order, hits = hits, compilations = compilations }
    end
    return api
end
return M
