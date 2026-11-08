-- One live assembly engine for native windows and headless surfaces.
-- Installers run against detached roots; publication never exposes a partial component.
local ffi = require 'ffi'
local Scope = require 'bui.ui.scope'
local Check = require 'bui.ui.check'
local Widgets = require 'bui.ui.widgets'
local Editors = require 'bui.ui.editors'
local Canvas = require 'bui.ui.canvas'
local Media = require 'bui.ui.media'
local Handles = require 'bui.ui.handles'
if jit then jit.off(true, true) end

local placement, mount

local function checked_vocabulary(owner, capabilities)
    if capabilities == nil then return {} end
    Check.table(capabilities, 'installer result')
    local public = {}
    for name, capability in pairs(capabilities) do
        if type(capability) == 'function' then
            public[name] = function(...)
                owner:check(tostring(name))
                return capability(...)
            end
        else public[name] = capability end
    end
    if Handles.kind(capabilities) then return Handles.alias(capabilities, public, owner) end
    return public
end

local function notify(record, name, payload)
    local connection = record.connection
    if connection and connection.handlers[name] then
        record.application:post(connection.owner, connection.handlers[name], payload)
    end
end

local function node(application, window, parent_owner, parent_node, descriptor, options)
    parent_owner:mutate('assemble ' .. descriptor.kind)
    local prepared = Widgets.prepare(descriptor, options)
    local owner = parent_owner:child(descriptor.kind)
    local record
    local ok, problem = pcall(function()
        local native = application.native
        local pointer = native.BK_node_new(descriptor.kind)
        assert(pointer ~= nil, 'native widget unavailable: ' .. descriptor.kind)
        owner:defer(function() native.BK_node_free(pointer) end)
        record = { application = application, native = native, owner = owner, node = pointer,
            kind = descriptor.kind, descriptor = descriptor, window = window, ready = false }
        local address = tostring(pointer)
        assert(not application.nodes[address], 'native node registered twice')
        application.nodes[address] = record
        owner:defer(function() application.nodes[address] = nil end)
        Widgets.apply(record, prepared)
        assert(native.BK_node_add(parent_node, pointer, -1) == 1, 'cannot attach widget')
        local capabilities = {}
        capabilities.configure = function(properties)
            owner:mutate('configure ' .. descriptor.kind)
            Widgets.apply(record, Widgets.prepare(descriptor, properties))
            application:check_error()
        end
        capabilities.display = function(caption) capabilities.configure({ caption = caption }) end
        capabilities.caption = function()
            owner:check('caption')
            return ffi.string(native.BK_get_str(pointer, descriptor.caption))
        end
        capabilities.rectangle = function()
            owner:check('rectangle')
            local rectangle = ffi.new('int[4]')
            native.BK_node_rect(pointer, rectangle)
            return { x = tonumber(rectangle[0]), y = tonumber(rectangle[1]),
                width = tonumber(rectangle[2]), height = tonumber(rectangle[3]) }
        end
        capabilities.natural_size = function()
            owner:check('natural_size')
            local size = ffi.new('int[2]'); native.BK_node_natural(pointer, size)
            return { width = tonumber(size[0]), height = tonumber(size[1]) }
        end
        capabilities.focus = function()
            owner:mutate('focus')
            if native.BK_node_context(pointer) ~= window.context then
                -- A textarea can otherwise put a detached staging node into context->focus.
                -- If installation then fails, BUI cannot discover that borrowed pointer to clear it.
                assert(application.assembly_depth > 0, 'focus target is not mounted in this surface')
                application:post(owner, capabilities.focus)
                return
            end
            native.BK_focus_node(window.context, pointer)
            application:check_error()
        end
        capabilities.invalidate = function()
            owner:mutate('invalidate'); native.BK_node_invalidate(pointer)
        end
        capabilities.connect = function(handlers)
            owner:mutate('connect')
            Check.keys(handlers, Widgets.notifications, 'notifications')
            local copied = {}
            for name, handler in pairs(handlers) do copied[name] = Check.callable(handler, name) end
            if record.connection then record.connection.owner:close() end
            local connection_owner = owner:child('connection')
            record.connection = { owner = connection_owner, handlers = copied }
            connection_owner:activate()
            native.BK_set_num(pointer, 'events', 1)
            if copied.view_changed then native.BK_set_num(pointer, 'viewevents', 1) end
            return function() connection_owner:close() end
        end
        if descriptor.value_type then
            capabilities.current = function() owner:check('current'); return Widgets.current(record) end
            capabilities.set = function(value) capabilities.configure({ value = value }) end
            -- Uniform notification semantics, including native kinds without a notifying setter.
            -- This is a programmatic command; native input continues to own UI undo recording.
            capabilities.change = function(value)
                capabilities.set(value)
                notify(record, 'changed', Widgets.current(record))
            end
        end
        record.capabilities = capabilities
        Editors.extend(record)
        Canvas.extend(record)
        Media.extend(record)
        record.ready = true
        owner:activate()
        application:check_error()
    end)
    if not ok then pcall(owner.close, owner); error(problem, 0) end
    return record
end

local function assembling(application, body)
    application.assembly_depth = application.assembly_depth + 1
    local ok, result = pcall(body)
    application.assembly_depth = application.assembly_depth - 1
    if not ok then error(result, 0) end
    return result
end

-- A mounting owner owns its detached root and every component-specific child scope.
mount = function(application, window, parent_owner, parent_node, installer)
    Check.callable(installer, 'component installer')
    local owner = parent_owner:child('mounted component')
    local installed
    local ok, problem = pcall(function()
        installed = assembling(application, function()
            local native = application.native
            local root = native.BK_node_new('column')
            assert(root ~= nil, 'component root allocation failed')
            owner:defer(function() native.BK_node_free(root) end)
            native.BK_set_num(root, 'padding', 0)
            native.BK_set_num(root, 'spacing', 0)
            native.BK_set_num(root, 'fill', 1)
            local capabilities = checked_vocabulary(owner,
                installer(placement(application, window, owner, root)))
            owner:check('publish component')
            application:check_error()
            assert(native.BK_node_add(parent_node, root, -1) == 1, 'cannot publish component')
            owner:activate()
            return { owner = owner, root = root, capabilities = capabilities }
        end)
    end)
    if not ok then pcall(owner.close, owner); error(problem, 0) end
    return installed
end

placement = function(application, window, owner, parent_node)
    local words = { resources = Media.resources(application, owner) }
    for name, descriptor in pairs(Widgets.catalog) do
        if descriptor.container then
            words[name] = function(options)
                owner:mutate('assemble ' .. name)
                return function(body)
                    Check.callable(body, name .. ' body')
                    return assembling(application, function()
                        local container = node(application, window, owner, parent_node, descriptor, options)
                        local ok, problem = pcall(body,
                            placement(application, window, container.owner, container.node))
                        if not ok then pcall(container.owner.close, container.owner); error(problem, 0) end
                        return container.capabilities
                    end)
                end
            end
        elseif name == 'button' then
            words[name] = function(options)
                owner:mutate('assemble button')
                return function(activated)
                    Check.callable(activated, 'button activation')
                    local button = node(application, window, owner, parent_node, descriptor, options)
                    button.capabilities.connect({ activated = activated })
                    return button.capabilities
                end
            end
        else
            words[name] = function(options)
                return node(application, window, owner, parent_node, descriptor, options).capabilities
            end
        end
    end
    words.include = function(installer)
        return mount(application, window, owner, parent_node, installer).capabilities
    end
    words.slot = function(options)
        local container = node(application, window, owner, parent_node, Widgets.catalog.column, options)
        local installed
        return {
            replace = function(installer)
                container.owner:mutate('replace slot')
                local replacement = mount(application, window, container.owner, container.node, installer)
                local previous = installed
                installed = replacement
                if previous then previous.owner:close() end
                return replacement.capabilities
            end,
            clear = function()
                container.owner:mutate('clear slot')
                if installed then installed.owner:close(); installed = nil end
            end,
        }
    end
    words.after = function(milliseconds)
        owner:mutate('schedule timer')
        return function(body) return application:after(owner, window, milliseconds, body) end
    end
    words.animate = function(body) return application:animate(owner, window, body) end
    return words
end

-- Mount for exactly the body lifetime; window closure may revoke it earlier.
local function with_content(application, window, parent_node, installer, body)
    Check.callable(body, 'content body')
    local installed = mount(application, window, window.owner, parent_node, installer)
    return Scope.with(installed.owner, function() return body(installed.capabilities) end)
end

return { with_content = with_content, notify = notify }
