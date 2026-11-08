-- FIFO delivery in bounded, non-reentrant batches. Appended work waits for the next batch.
local function new()
    local entries, first, last, delivering = {}, 1, 0, false
    return {
        post = function(owner, body, ...)
            if not owner:is_alive() then return end
            last = last + 1
            entries[last] = { owner = owner, body = body, arguments = { n = select('#', ...), ... } }
        end,
        pending = function() return first <= last end,
        drain = function(budget)
            assert(not delivering, 'notification delivery is not reentrant')
            delivering = true
            local stop = math.min(last, first + (budget or 256) - 1)
            local ok, problem = pcall(function()
                while first <= stop do
                    local entry = entries[first]
                    entries[first], first = nil, first + 1
                    if entry.owner:is_alive() then
                        entry.body(unpack(entry.arguments, 1, entry.arguments.n))
                    end
                end
            end)
            delivering = false
            if first > last then entries, first, last = {}, 1, 0 end
            if not ok then error(problem, 0) end
        end,
        clear = function() entries, first, last = {}, 1, 0 end,
    }
end
return { new = new }
