-- Deterministic ownership for UI activities; independent of FFI and the event loop.
-- Children retire before their parent's resources. Cleanup continues after a failure.
local Scope = {}
Scope.__index = Scope

local function pack(...) return { n = select('#', ...), ... } end

-- Create an acquiring owner. Its parent holds it until completion, not until GC.
local function new(parent, label)
    if parent then parent:mutate('acquire ' .. label) end
    local owner = setmetatable({
        parent = parent, label = label, state = 'acquiring', children = {}, cleanups = {},
        application = parent and parent.application,
    }, Scope)
    if parent then parent.children[#parent.children + 1] = owner end
    return owner
end

function Scope:is_alive()
    return (self.state == 'acquiring' or self.state == 'live')
        and (not self.parent or self.parent:is_alive())
end

function Scope:check(operation)
    if not self:is_alive() then
        error((operation or 'use') .. ': ' .. self.label .. ' activity has ended', 3)
    end
    if self.application and self.application.failed then error(self.application.failure, 0) end
end

function Scope:mutate(operation)
    self:check(operation)
    if self.application then self.application:assert_mutation(operation) end
end

function Scope:activate()
    self:check('publish')
    self.state = 'live'
end

function Scope:child(label) return new(self, label) end

function Scope:contains(other)
    while other do
        if self == other then return true end
        other = other.parent
    end
    return false
end

-- Register immediately after acquisition; disarming never runs the cleanup.
function Scope:defer(cleanup)
    self:check('register cleanup')
    assert(type(cleanup) == 'function', 'cleanup expects a function')
    local entry = { cleanup = cleanup }
    self.cleanups[#self.cleanups + 1] = entry
    return function() entry.cleanup = nil end
end

local function revoke(owner)
    owner.state = 'closing'
    for _, child in ipairs(owner.children) do revoke(child) end
end

local function release(owner, failures)
    while #owner.children > 0 do release(owner.children[#owner.children], failures) end
    for index = #owner.cleanups, 1, -1 do
        local cleanup = owner.cleanups[index].cleanup
        owner.cleanups[index] = nil
        if cleanup then
            local ok, problem = pcall(cleanup)
            if not ok and not failures.present then
                failures.present, failures.problem = true, problem
            end
        end
    end
    owner.state = 'closed'
    if owner.parent then
        local siblings = owner.parent.children
        for index = #siblings, 1, -1 do
            if siblings[index] == owner then table.remove(siblings, index); break end
        end
    end
end

-- Revoke the entire subtree before any destructor can call back into it.
function Scope:close()
    if self.state == 'closed' or self.state == 'closing' then return end
    if self.application then self.application:assert_mutation('complete ' .. self.label) end
    revoke(self)
    local failures = {}
    release(self, failures)
    if failures.present then error(failures.problem, 0) end
end

-- Preserve nil/multiple results and the original body error across deterministic cleanup.
local function with(owner, body)
    local results = pack(pcall(body, owner))
    local cleaned, problem = pcall(owner.close, owner)
    if not results[1] then error(results[2], 0) end
    if not cleaned then error(problem, 0) end
    return unpack(results, 2, results.n)
end

-- Adopt successful acquisitions into an existing owner; roll back only new ledger entries
-- on preparation errors. This does not roll back arbitrary Lua state or external I/O.
local function prepare(owner, body)
    owner:mutate('prepare owned resources')
    local child_count, cleanup_count = #owner.children, #owner.cleanups
    local results = pack(pcall(body))
    if not results[1] then
        while #owner.children > child_count do
            local child = owner.children[#owner.children]
            pcall(child.close, child)
        end
        for index = #owner.cleanups, cleanup_count + 1, -1 do
            local cleanup = owner.cleanups[index].cleanup
            owner.cleanups[index] = nil
            if cleanup then pcall(cleanup) end
        end
        error(results[2], 0)
    end
    return unpack(results, 2, results.n)
end

return { new = new, with = with, prepare = prepare }
