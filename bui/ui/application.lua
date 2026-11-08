-- Native dispatch and application ownership. User notifications never run on a C stack.
-- The process-global BUI hooks admit one application owner per Lua VM, not one per window.
local ffi = require 'ffi'
local Scope = require 'bui.ui.scope'
local Check = require 'bui.ui.check'
local Queue = require 'bui.ui.queue'
local Clock = require 'bui.ui.clock'
local Widgets = require 'bui.ui.widgets'
local Mount = require 'bui.ui.mount'
if jit then jit.off(true, true) end

local active = false
-- BUI has no window-host shutdown API. Win32 classes/message-only windows retain DLL
-- procedure addresses even after the last visible window closes. Keep one namespace per
-- native code identity for the VM lifetime; UI objects and Lua callbacks are still scoped.
local retained_libraries = {}
local Application = {}
Application.__index = Application
local function pack(...) return { n = select('#', ...), ... } end

function Application:assert_mutation(operation)
    if self.phase ~= 'idle' and self.phase ~= 'notification' then
        error(operation .. ': forbidden during ' .. self.phase .. ' callback', 3)
    end
end

function Application:check_error()
    if self.failed then error(self.failure, 0) end
end

function Application:post(owner, body, ...) self.queue.post(owner, body, ...) end

-- One trampoline per native role, retained until every native user has been destroyed.
function Application:callback(signature, body, fallback, phase)
    local callback = ffi.cast(signature, function(...)
        if self.failed then return fallback end
        local previous = self.phase
        self.phase = phase or 'native'
        local results = pack(pcall(body, ...))
        self.phase = previous
        if not results[1] then
            if not self.failed then self.failed, self.failure = true, results[2] end
            self.native.BK_window_quit()
            return fallback
        end
        return unpack(results, 2, results.n)
    end)
    self.callbacks[#self.callbacks + 1] = callback
    return callback
end

function Application:register(owner, value)
    self.next_token = self.next_token + 1
    local token = self.next_token
    assert(token < 2^53, 'native registration identity exhausted')
    self.registrations[token] = { owner = owner, value = value }
    owner:defer(function() self.registrations[token] = nil end)
    return ffi.cast('void *', token)
end

function Application:resolve(token)
    local registration = self.registrations[tonumber(ffi.cast('uintptr_t', token))]
    if registration and registration.owner:is_alive() then return registration.value end
end

function Application:has_due()
    local now = self.now()
    for timer in pairs(self.timers) do if timer.deadline <= now then return true end end
    return false
end

function Application:poll_timers()
    local now, due = self.now(), {}
    for timer in pairs(self.timers) do
        if timer.deadline <= now then due[#due + 1] = timer
        elseif timer.window.pointer and not timer.native_id then
            timer.native_id = self.native.BK_window_timer(timer.window.pointer,
                math.max(1, math.ceil((timer.deadline - now) * 1000)))
            assert(timer.native_id > 0, 'native timer allocation failed')
            timer.window.wakes[timer.native_id] = timer
        end
    end
    table.sort(due, function(left, right)
        if left.deadline == right.deadline then return left.sequence < right.sequence end
        return left.deadline < right.deadline
    end)
    for _, timer in ipairs(due) do
        self.timers[timer] = nil
        self:post(timer.owner, function()
            timer.owner:close()
            if timer.parent:is_alive() then timer.body() end
        end)
    end
end

-- Deadlines are authoritative; WM_TIMER only wakes an otherwise idle native loop.
function Application:after(owner, window, milliseconds, body)
    Check.integer(milliseconds, 'timer milliseconds', 0, 2147483647)
    Check.callable(body, 'timer body')
    local timer_owner = owner:child('one-shot timer')
    self.next_timer = self.next_timer + 1
    local timer = { owner = timer_owner, parent = owner, window = window, body = body,
        deadline = self.now() + milliseconds / 1000, sequence = self.next_timer }
    self.timers[timer] = true
    timer_owner:defer(function()
        self.timers[timer] = nil
        if timer.native_id then
            window.wakes[timer.native_id] = nil
            if window.pointer then self.native.BK_window_cancel_timer(window.pointer, timer.native_id) end
        end
    end)
    timer_owner:activate()
    self:poll_timers()
    return function() timer_owner:close() end
end

function Application:animate(owner, window, body)
    Check.callable(body, 'animation body')
    assert(window.pointer, 'animation requires a native window')
    local animation_owner = owner:child('animation')
    local animation = { owner = animation_owner, body = body, pending = false }
    window.animations[animation] = true
    animation_owner:defer(function() window.animations[animation] = nil end)
    animation_owner:activate()
    self.native.BK_window_request_frame(window.pointer, 1)
    return function() animation_owner:close() end
end

function Application:turn()
    self:check_error()
    self.woken = false
    self:poll_timers()
    -- Native destruction can happen without an accepted close-request notification.
    local closed = {}
    for window in pairs(self.windows) do
        if window.pointer and self.native.BK_window_is_open(window.pointer) == 0 then
            closed[#closed + 1] = window
        end
    end
    for _, window in ipairs(closed) do window.owner:close() end
    local previous = self.phase
    self.phase = 'notification'
    local ok, problem = pcall(self.queue.drain, 256)
    self.phase = previous
    if not ok then error(problem, 0) end
    self:check_error()
end

function Application:has_windows()
    for window in pairs(self.windows) do if window.pointer then return true end end
    return false
end

function Application:dispatch(blocking)
    self.owner:mutate('dispatch')
    assert(not self.running, 'application dispatch is not reentrant')
    assert(self.assembly_depth == 0, 'cannot dispatch during component assembly')
    self.running = true
    local ok, problem = pcall(function()
        if not blocking then
            self:check_error()
            self.native.BK_window_pump()
            self:turn()
            return
        end
        while true do
            self:turn()
            if self.quitting or not self:has_windows() then break end
            if self.queue.pending() or self:has_due() then self.native.BK_window_pump()
            else self.native.BK_window_run() end
        end
    end)
    self.running = false
    if not ok then error(problem, 0) end
end

local function setup_callbacks(application)
    local native = application.native
    application.emit = application:callback(
        'void (*)(void *, BKNode *, int, void *, double, double)',
        function(_, pointer, kind, reference, first, second)
            local record = application.nodes[tostring(pointer)]
            if record and record.ready and record.owner:is_alive() then
                local name, payload = Widgets.snapshot(record, kind, reference, first, second)
                if name then Mount.notify(record, name, payload) end
            end
        end)
    application.timer_callback = application:callback('void (*)(void *, BKWindow *, int)',
        function(token, _, identifier)
            local window = application:resolve(token)
            if window then
                local timer = window.wakes[identifier]
                if timer then timer.native_id = nil; window.wakes[identifier] = nil end
            end
            application.woken = true
        end)
    application.close_callback = application:callback('int (*)(void *, BKWindow *)',
        function(token)
            local window = application:resolve(token)
            if window then application:post(window.owner, function()
                if window.close_requested then window.close_requested()
                else window.owner:close() end
            end) end
            return 0 -- Keep C's input stack intact; Lua decides after dispatch returns.
        end, 0)
    application.frame_callback = application:callback('void (*)(void *, BKWindow *)',
        function(token)
            local window = application:resolve(token)
            if not window then return end
            for animation in pairs(window.animations) do
                if not animation.pending then
                    animation.pending = true
                    application:post(animation.owner, function()
                        animation.pending = false
                        local again = application.protocols.continue_frame(animation.body())
                        if animation.owner:is_alive() then
                            if again then native.BK_window_request_frame(window.pointer, 1)
                            else animation.owner:close() end
                        end
                    end)
                end
            end
        end)
    application.clipboard_get = application:callback('char *(*)(void *)', function(token)
        local window = application:resolve(token)
        if not window or not window.clipboard_text then return nil end
        local text = window.clipboard_text
        local pointer = native.mua_bui_malloc(#text + 1)
        if pointer == nil then return nil end
        ffi.copy(pointer, text, #text + 1)
        return ffi.cast('char *', pointer)
    end, nil, 'service')
    application.clipboard_set = application:callback('void (*)(void *, const char *)',
        function(token, text)
            local window = application:resolve(token)
            if window then window.clipboard_text = ffi.string(text) end
        end, nil, 'service')
    application.schedule = application:callback('void (*)(void *, int, int)',
        function(token, milliseconds, identifier)
            local window = application:resolve(token)
            if not window then return end
            local request = { deadline = application.now() + milliseconds / 1000 }
            window.toolkit_timers[identifier] = request
            application:post(window.owner, function()
                if window.toolkit_timers[identifier] ~= request then return end
                application:after(window.owner, window,
                    math.max(0, math.ceil((request.deadline - application.now()) * 1000)), function()
                        if window.toolkit_timers[identifier] == request then
                            window.toolkit_timers[identifier] = nil
                            native.BK_timer(window.context, identifier)
                            application:check_error()
                        end
                    end)
            end)
        end)
    local stop = application:callback('int (*)(void)', function()
        return (application.failed or application.quitting or application.woken
            or application.queue.pending() or application:has_due()) and 1 or 0
    end, 1)
    native.BK_window_set_stop_check(stop)
    application.owner:defer(function() native.BK_window_set_stop_check(nil) end)
end

local function surface_capabilities(application, window)
    local native, owner, context = application.native, window.owner, window.context
    local capabilities = {}
    local function content(region, root)
        return function(installer)
            owner:mutate('mount ' .. region)
            Check.callable(installer, 'component installer')
            return function(body)
                owner:mutate('mount ' .. region)
                assert(not window[region], region .. ' is already mounted; use a slot for replacement')
                window[region] = true
                local results = pack(pcall(Mount.with_content, application, window, root, installer, body))
                window[region] = false
                if not results[1] then error(results[2], 0) end
                return unpack(results, 2, results.n)
            end
        end
    end
    capabilities.with_content = content('content', window.root)
    capabilities.with_header = content('header_content', window.header)
    capabilities.after = function(milliseconds)
        owner:mutate('schedule timer')
        return function(body) return application:after(owner, window, milliseconds, body) end
    end
    capabilities.animate = function(body) return application:animate(owner, window, body) end
    capabilities.close = function() owner:close() end
    capabilities.on_close_requested = function(body)
        owner:mutate('connect close request')
        window.close_requested = Check.callable(body, 'close_requested')
    end
    capabilities.render = function()
        owner:mutate('render')
        local rendered
        if window.pointer then native.BK_window_render_now(window.pointer); rendered = true
        else rendered = native.BK_render(context, window.raster, window.width, window.height, 0) ~= 0 end
        application:check_error()
        return rendered
    end
    capabilities.resize = function(width, height)
        owner:mutate('resize')
        Check.integer(width, 'width', 1, 32768); Check.integer(height, 'height', 1, 32768)
        if window.pointer then native.BK_window_set_size(window.pointer, width, height)
        else window.width, window.height = width, height; native.BK_node_relayout(window.root) end
    end
    capabilities.size = function()
        owner:check('size')
        if not window.pointer then return { width = window.width, height = window.height } end
        local width, height = ffi.new('int[1]'), ffi.new('int[1]')
        native.BK_window_get_size(window.pointer, width, height)
        return { width = tonumber(width[0]), height = tonumber(height[0]) }
    end
    capabilities.show = function()
        owner:mutate('show'); assert(window.pointer, 'headless surfaces cannot be shown')
        native.BK_window_show(window.pointer); application:check_error()
    end
    capabilities.title = function(title)
        owner:mutate('set title'); assert(window.pointer, 'headless surfaces have no window title')
        native.BK_window_set_title(window.pointer, Check.string(title, 'title'))
    end
    capabilities.frames = function()
        owner:check('frames'); assert(window.pointer, 'frame statistics require a native window')
        return tonumber(native.BK_window_frames(window.pointer))
    end
    local input = {}
    for name, entry in pairs({
        press = { native.BK_press, 3 }, release = { native.BK_release, 3 },
        motion = { native.BK_motion, 3 }, wheel = { native.BK_wheel, 4 },
        button = { native.BK_button, 5 }, context_menu = { native.BK_context_menu, 3 },
    }) do
        input[name] = function(...)
            owner:mutate(name)
            local arguments = pack(...)
            assert(arguments.n == entry[2], name .. ': wrong number of arguments')
            for index = 1, arguments.n do Check.integer(arguments[index], name) end
            local consumed = entry[1](context, ...)
            application:check_error()
            return consumed ~= 0
        end
    end
    input.key = function(text, keysym, modifiers)
        owner:mutate('key')
        local consumed = native.BK_key(context, Check.string(text, 'key text'),
            Check.string(keysym, 'keysym'), Check.integer(modifiers or 0, 'modifiers', 0))
        application:check_error(); return consumed ~= 0
    end
    input.key_release = function(keysym, modifiers)
        owner:mutate('key_release')
        local consumed = native.BK_key_release(context, Check.string(keysym, 'keysym'),
            Check.integer(modifiers or 0, 'modifiers', 0))
        application:check_error(); return consumed ~= 0
    end
    input.scroll = function(x, y, horizontal, vertical, modifiers)
        owner:mutate('scroll')
        local consumed = native.BK_scroll(context, Check.integer(x, 'x'), Check.integer(y, 'y'),
            Check.number(horizontal, 'horizontal scroll'), Check.number(vertical, 'vertical scroll'),
            Check.integer(modifiers or 0, 'modifiers', 0))
        application:check_error(); return consumed ~= 0
    end
    capabilities.input = input
    capabilities.undo = function()
        owner:mutate('undo'); local changed = native.BK_undo(context) ~= 0
        application:check_error(); return changed
    end
    capabilities.redo = function()
        owner:mutate('redo'); local changed = native.BK_redo(context) ~= 0
        application:check_error(); return changed
    end
    capabilities.undo_depth = function()
        owner:check('undo_depth'); local redo = ffi.new('int[1]')
        local undo = native.BK_undo_depth(context, redo)
        return { undo = tonumber(undo), redo = tonumber(redo[0]) }
    end
    capabilities.close_popups = function() owner:mutate('close popups'); native.BK_close_popups(context) end
    capabilities.clipboard = {
        read = function()
            owner:mutate('read clipboard')
            local pointer = native.BK_clipboard_get(context)
            if pointer == nil then return application.protocols.acquisition.unavailable('clipboard is empty') end
            local ok, text = pcall(ffi.string, pointer)
            native.mua_bui_free(pointer)
            if not ok then error(text, 0) end
            return application.protocols.acquisition.ready(text)
        end,
        write = function(text)
            owner:mutate('write clipboard'); native.BK_clipboard_set(context, Check.string(text, 'clipboard'))
            application:check_error()
        end,
    }
    return capabilities
end

local function with_surface(application, options, native_window, body)
    application.owner:mutate('open surface')
    Check.keys(options, { title = true, width = true, height = true }, 'surface options')
    Check.callable(body, 'surface body')
    local width = Check.integer(options.width or 640, 'width', 1, 32768)
    local height = Check.integer(options.height or 480, 'height', 1, 32768)
    local title = Check.string(options.title or 'Mua', 'title')
    local native, opening = application.native, application.protocols.opening
    if native_window and native.BK_window_supported() == 0 then
        return opening.unavailable('native windows are not supported by this backend')
    end
    local owner = application.owner:child(native_window and 'window' or 'headless surface')
    return Scope.with(owner, function()
        local root = native.BK_node_new('column')
        assert(root ~= nil, 'surface root allocation failed')
        owner:defer(function() native.BK_node_free(root) end)
        local header = native.BK_node_new('column')
        assert(header ~= nil, 'header root allocation failed')
        owner:defer(function() native.BK_node_free(header) end)
        native.BK_set_num(root, 'padding', 0); native.BK_set_num(root, 'spacing', 0)
        native.BK_set_num(header, 'padding', 0); native.BK_set_num(header, 'spacing', 0)
        local context = native.BK_context_new(root)
        assert(context ~= nil, 'context allocation failed')
        owner:defer(function() native.BK_context_free(context) end)
        native.BK_context_set_header(context, header)
        local window = { owner = owner, context = context, root = root, header = header,
            wakes = {}, animations = {}, toolkit_timers = {}, width = width, height = height }
        local token = application:register(owner, window)
        local host = ffi.new('BKHost[1]')
        host[0].data = token
        host[0].emit = application.emit
        host[0].clipboard_get = application.clipboard_get
        host[0].clipboard_set = application.clipboard_set
        host[0].schedule = application.schedule
        native.BK_context_set_host(context, host)
        if native_window then
            local pointer = native.BK_window_new(context, title, width, height)
            if pointer == nil then return opening.unavailable('native window creation failed') end
            window.pointer = pointer
            owner:defer(function() native.BK_window_free(pointer); window.pointer = nil end)
            local callbacks = ffi.new('BKWindowCallbacks[1]')
            callbacks[0].data = token
            callbacks[0].on_timer = application.timer_callback
            callbacks[0].on_close = application.close_callback
            callbacks[0].on_frame = application.frame_callback
            native.BK_window_set_callbacks(pointer, callbacks)
        else
            local raster = native.BUI_raster_create(width, height)
            assert(raster ~= nil, 'headless raster allocation failed')
            window.raster = raster
            owner:defer(function() native.BUI_raster_free(raster) end)
        end
        application.windows[window] = true
        owner:defer(function() application.windows[window] = nil end)
        owner:activate()
        application:check_error()
        return opening.opened(body(surface_capabilities(application, window)))
    end)
end

-- Private clock injection permits deterministic timer tests without changing UI semantics.
local function with_application(native, protocols, body, clock)
    assert(not active, 'BUI already has an application owner in this Lua VM')
    Check.callable(body, 'application body')
    assert(native.mua_bui_binding_version() == 1, 'unsupported BUI binding version')
    assert(native.BK_version() == 500, 'unsupported BUI kit version')
    local code_identity = tostring(ffi.cast('void *', native.mua_bui_binding_version))
    retained_libraries[code_identity] = retained_libraries[code_identity] or native
    active = true
    local owner = Scope.new(nil, 'application')
    local clock_now, previous_time = clock or Clock.now, -math.huge
    local function now()
        local current_time = Check.number(clock_now(), 'monotonic clock')
        assert(current_time >= previous_time, 'monotonic clock moved backwards')
        previous_time = current_time
        return current_time
    end
    local application = setmetatable({ native = native, protocols = protocols, owner = owner,
        now = now, queue = Queue.new(), phase = 'idle', callbacks = {},
        registrations = {}, next_token = 0, next_timer = 0, nodes = {}, windows = {},
        timers = {}, assembly_depth = 0, extensions = {},
    }, Application)
    owner.application = application
    owner:defer(function() active = false end)
    owner:defer(function()
        for _, callback in ipairs(application.callbacks) do callback:free() end
        application.callbacks = {}; application.queue.clear()
    end)
    owner:defer(function() native.BK_image_exit() end)
    return Scope.with(owner, function()
        setup_callbacks(application)
        owner:activate()
        local capabilities = {}
        capabilities.with_window = function(options)
            owner:mutate('open window')
            return function(window_body) return with_surface(application, options, true, window_body) end
        end
        capabilities.with_surface = function(options)
            owner:mutate('open surface')
            return function(surface_body) return with_surface(application, options, false, surface_body) end
        end
        capabilities.statistics = function()
            owner:check('statistics')
            local function count(entries)
                local total = 0
                for _ in pairs(entries) do total = total + 1 end
                return total
            end
            return { surfaces = count(application.windows), registered_nodes = count(application.nodes),
                registrations = count(application.registrations), timers = count(application.timers),
                callbacks = #application.callbacks }
        end
        capabilities.run = function() application:dispatch(true) end
        capabilities.pump = function() application.woken = false; application:dispatch(false) end
        capabilities.quit = function() owner:mutate('quit'); application.quitting = true end
        capabilities.theme = function(name)
            owner:mutate('theme'); Check.string(name, 'theme')
            assert(native.BK_set_theme(name) == 1, 'unknown theme: ' .. name)
        end
        capabilities.scale = function(scale)
            owner:mutate('scale'); native.BK_set_scale(Check.number(scale, 'scale', 0.25, 8))
        end
        capabilities.font = function(family)
            owner:mutate('font'); native.BK_set_font(Check.string(family, 'font family'))
        end
        capabilities.gpu_default = function(enabled)
            owner:mutate('GPU policy'); native.BUI_gpu_set_default(Check.boolean(enabled, 'GPU') and 1 or 0)
        end
        return body(capabilities)
    end)
end

return { with_application = with_application }
