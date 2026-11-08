-- Private identities for owned native resources. Public vocabularies contain no pointers.
-- A retained borrow requires an ancestor owner; an immediate call only requires a live owner.
local registrations = setmetatable({}, { __mode = 'k' })

local function register(capabilities, owner, kind, pointer)
    assert(not registrations[capabilities], 'resource registered twice')
    registrations[capabilities] = { owner = owner, kind = kind, pointer = pointer }
    return capabilities
end

local function lookup(capabilities, kind)
    local resource = registrations[capabilities]
    assert(resource and resource.kind == kind, 'expected an owned ' .. kind .. ' capability')
    resource.owner:check('use ' .. kind)
    return resource
end

local function get(capabilities, kind, borrower)
    local resource = lookup(capabilities, kind)
    if borrower then
        borrower:check('borrow ' .. kind)
        assert(resource.owner.application == borrower.application, 'resource belongs to another application')
        assert(resource.owner:contains(borrower), 'resource owner must outlive its retained borrower')
    end
    if type(resource.pointer) == 'function' then return resource.pointer() end
    return resource.pointer
end

local function owner(capabilities, kind) return lookup(capabilities, kind).owner end
local function kind(capabilities)
    local resource = registrations[capabilities]
    return resource and resource.kind
end

-- A component may narrow an existing resource loan, but never extend its owning lifetime.
local function alias(original, capabilities, borrower)
    local resource_kind = assert(kind(original), 'expected a resource capability')
    get(original, resource_kind, borrower)
    return register(capabilities, borrower, resource_kind, function() return get(original, resource_kind) end)
end
return { register = register, get = get, owner = owner, kind = kind, alias = alias }
