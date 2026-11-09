-- Managed BUI activities. Default is headless; --window also exercises the native driver.
local ffi = require 'ffi'
local mua = require 'mua.init'
table.insert(package.loaders, 2, mua.searcher())
local Ui = require 'bui.ui'
local Scope = require 'bui.ui.scope'
local Queue = require 'bui.ui.queue'
local Native = require('bui.ffi').load(assert(arg[1], 'native library path required'))
local checks = 0
local function check(condition, message)
    checks = checks + 1
    assert(condition, message or ('check ' .. checks))
end
local function refuses(body, fragment)
    local ok, problem = pcall(body)
    check(not ok and tostring(problem):find(fragment, 1, true), tostring(problem))
end
local function opened(result)
    return result { opened = function(value) return value end, unavailable = function(reason) error(reason) end }
end
local function ready(result)
    return result { ready = function(value) return value end, unavailable = function(reason) error(reason) end }
end

-- Completion revokes the whole subtree before destructors run, and preserves the first error.
do
    local root, order = Scope.new(nil, 'test'), {}
    local child = root.child('child')
    root.defer(function() order[#order + 1] = 'root' end)
    child.defer(function() check(not root.is_alive()); order[#order + 1] = 'child' end)
    child.defer(function() error('cleanup problem', 0) end)
    refuses(function() root.close() end, 'cleanup problem')
    check(table.concat(order, ',') == 'child,root')
    root.close()
    refuses(function() child.check('read') end, 'activity has ended')
    local scope = Scope.new(nil, 'body')
    scope.defer(function() error('secondary cleanup', 0) end)
    refuses(function() Scope.with_owner(scope)(function() error('original body', 0) end) end, 'original body')
    local first, absent, third = Scope.with_owner(Scope.new(nil, 'results'))(function() return 1, nil, 3 end)
    check(first == 1 and absent == nil and third == 3)
end

-- Delivery snapshots the batch, rejects recursion, and discards retired generations.
do
    local queue, owner, log = Queue.new(), Scope.new(nil, 'queue'), {}
    queue.post(owner, function()
        log[#log + 1] = 1
        queue.post(owner, function() log[#log + 1] = 3 end)
        refuses(function() queue.drain() end, 'not reentrant')
    end)
    queue.post(owner, function() log[#log + 1] = 2 end)
    queue.drain()
    check(#log == 2 and queue.pending())
    queue.drain(); check(table.concat(log, ',') == '1,2,3')
    queue.post(owner, function() error('stale delivery') end)
    owner.close(); queue.drain(); check(not queue.pending())
end

local now = 10
local Activities = Ui.using_clock(function() return now end)
local escaped_application, escaped_surface, escaped_control, escaped_component
Activities.with_application(Native)(function(application)
    escaped_application = application
    application.gpu_default(false)
    refuses(function() Ui.with_application(Native)(function() end) end, 'already has an application')
    refuses(function() application.with_surface{ width = -1 }(function() end) end, 'range')
    local baseline = application.statistics()
    opened(application.with_surface{ width = 400, height = 300 }(function(surface)
        escaped_surface = surface
        check(application.statistics().surfaces == 1)
        surface.clipboard.write('owned UTF-8: café')
        check(ready(surface.clipboard.read()) == 'owned UTF-8: café')
        local events, control, text, button, slot, cancel, timer_calls = {}, nil, nil, nil, nil, nil, 0
        local function panel(place)
            control = place.slider{ minimum = 0, maximum = 20, value = 12, caption = 'Level' }
            escaped_control = control
            control.connect{ changed = function(value) events[#events + 1] = value end }
            text = place.text{ value = 'initial', live = true }
            text.connect{ changed = function(value) events[#events + 1] = value end }
            button = place.button('Advance')(function() control.change(control.current() + 1) end)
            slot = place.slot{ fill = true }
            return { current = control.current, advance = function() control.change(16) end }
        end
        surface.with_content(panel)(function(component)
            escaped_component = component
            check(component.current() == 12, 'limits precede value regardless of hash order')
            check(surface.render(), 'first headless render')
            check(not surface.render(), 'idle render must have no damage')
            control.set(14); check(#events == 0 and control.current() == 14)
            control.change(15); control.change(16)
            check(#events == 0, 'no immediate notification delivery')
            application.pump(); check(events[1] == 15 and events[2] == 16)
            text.change('copied text'); text.set('newer state'); collectgarbage()
            application.pump(); check(events[3] == 'copied text' and text.current() == 'newer state')
            surface.render()
            local rectangle = button.rectangle()
            surface.input.press { x = rectangle.x + 3, y = rectangle.y + 3 }
            surface.input.release { x = rectangle.x + 3, y = rectangle.y + 3 }
            check(#events == 3, 'native activation is deferred')
            application.pump(); check(control.current() == 17 and #events == 3)
            application.pump(); check(events[4] == 17, 'notifications appended by handlers wait a batch')
            refuses(function() control.configure{ minimum = 9, maximum = 2 } end, 'minimum exceeds')
            refuses(function() control.configure{ minimum = 21 } end, 'minimum exceeds')
            refuses(function() control.configure{ maximum = '20' } end, 'number')
            refuses(function() control.configure{ visible = 1 } end, 'boolean')
            refuses(function() control.configure{ align = 'right' } end, 'boolean')
            refuses(function() control.configure{ unknown = 2 } end, 'unknown property')
            refuses(function() text.set('has\0NUL') end, 'NUL')
            refuses(function() control.connect{ typo = function() end } end, 'unknown field')
            refuses(function() surface.with_content(panel)(function() end) end, 'already mounted')
            local old = slot.replace(function(place)
                local label = place.label('old')
                return { caption = label.caption }
            end)
            local before = application.statistics().registered_nodes
            refuses(function() slot.replace(function(place)
                place.column{}(function(children)
                    children.label('partial')
                    children.textarea{ value = 'detached' }.focus()
                    error('installation failure', 0)
                end)
            end) end, 'installation failure')
            application.pump() -- The failed mount's queued focus must not escape into the context.
            surface.input.key { text = 'x', keysym = 'x' }
            check(old.caption() == 'old' and application.statistics().registered_nodes == before)
            local replaced = slot.replace(function(place)
                local label = place.label('new')
                return { caption = label.caption }
            end)
            refuses(old.caption, 'activity has ended')
            check(replaced.caption() == 'new')
            slot.clear(); refuses(replaced.caption, 'activity has ended')
            cancel = surface.after(100)(function() timer_calls = timer_calls + 1 end)
            now = 10.099; application.pump(); check(timer_calls == 0)
            now = 10.1; application.pump(); check(timer_calls == 1)
            application.pump(); cancel(); check(timer_calls == 1)
            local cancelled = surface.after(50)(function() error('cancelled timer ran') end)
            cancelled(); now = 11; application.pump()
            check(application.statistics().timers == 0)
            -- Retired connections cannot deliver queued notifications to their replacements.
            control.change(18)
            control.connect{ changed = function() error('old notification reached new connection') end }
            application.pump()
            check(#events == 4)
        end)
        refuses(escaped_control.current, 'activity has ended')
        refuses(escaped_component.current, 'activity has ended')
        check(application.statistics().registered_nodes == 0)
        -- Repeated mounts do not consume native callback slots or retain node registrations.
        for iteration = 1, 50 do
            surface.with_content(function(place)
                local toggle = place.checkbox{ caption = 'Independent', value = false }
                check(not toggle.current())
                return { toggle = function() toggle.change(true) end }
            end)(function(component) component.toggle() end)
        end
        application.pump()
        check(application.statistics().callbacks == baseline.callbacks)
        check(application.statistics().registered_nodes == 0)
    end))
    check(application.statistics().surfaces == 0 and application.statistics().registrations == 0)
    refuses(escaped_surface.render, 'activity has ended')
end)
refuses(escaped_application.pump, 'activity has ended')

-- A notification can close its owner; later queued notifications are then discarded.
Ui.with_application(Native)(function(application)
    opened(application.with_surface{}(function(surface)
        surface.with_content(function(place)
            local first = place.slider{ value = 0 }
            first.connect{ changed = surface.close }
            local second = place.slider{ value = 0 }
            second.connect{ changed = function() error('delivery after close') end }
            return { change = function() first.change(0.2); second.change(0.4) end }
        end)(function(panel)
            panel.change(); application.pump()
            check(application.statistics().surfaces == 0)
        end)
    end))
end)

refuses(function()
    Ui.with_application(Native)(function(application)
        opened(application.with_surface{}(function(surface)
            surface.with_content(function(place)
                local slider = place.slider{}
                slider.connect{ changed = function() error('notification fault', 0) end }
                return slider
            end)(function(slider) slider.change(0.3); application.pump() end)
        end))
    end)
end, 'notification fault')
-- Reacquiring after error proves the global owner and its native stop hook were released.
Ui.with_application(Native)(function(application) check(application.statistics().surfaces == 0) end)

-- Pure descriptions and specialized editors share the same mounting/ownership engine.
do
    local escaped_drawing
    local coordinates = { 0, 0, 50, 30 }
    local description = Ui.drawing(function(draw)
        escaped_drawing = draw
        draw.rectangle{ coordinates = coordinates, fill = { 0.2, 0.4, 0.6, 1 } }
        draw.text{ coordinates = { 5, 10 }, text = 'retained font', family = 'sans-serif' }
    end)
    coordinates[1] = 999
    check(description[1].coordinates[1] == 0, 'builder snapshots caller data')
    refuses(function() escaped_drawing.oval{ coordinates = { 1, 2, 3, 4 } } end, 'activity has ended')
    refuses(function() Ui.drawing(function(draw)
        draw.line{ id = 4, coordinates = { 0, 0, 1, 1 } }
        draw.line{ id = 4, coordinates = { 0, 0, 2, 2 } }
    end) end, 'duplicate')
    Ui.with_application(Native)(function(application)
        opened(application.with_surface{ width = 500, height = 500 }(function(surface)
            surface.with_content(function(place)
                local canvas = place.canvas{ height = 100 }
                local ramp = place.ramp{}
                local curve = place.curve{}
                local textarea = place.textarea{ value = 'aéz', height = 100 }
                local histogram = place.histogram{}
                local grid = place.grid_view{ items = { 'first', 'second' } }
                return { canvas = canvas, ramp = ramp, curve = curve, textarea = textarea,
                    histogram = histogram, grid = grid }
            end)(function(editors)
                local canvas = editors.canvas
                canvas.replace(description); check(canvas.count() == 2)
                refuses(function() canvas.replace{{ kind = 'polygon', id = 7, coordinates = { 0, 1 } }} end,
                    'three or more')
                check(canvas.count() == 2, 'invalid replacement preserves drawing')
                canvas.append{ kind = 'image', id = 3, coordinates = { 30, 30, 40, 40 },
                    rgba = string.char(255, 0, 0, 255), image_width = 1, image_height = 1 }
                check(canvas.count() == 3 and canvas.raise(1) and canvas.lower(1))
                canvas.set_item{ kind = 'oval', id = 1, coordinates = { 0, 0, 25, 25 } }
                check(canvas.count() == 3)
                canvas.put_at(1) { kind = 'round_rectangle', id = 4, coordinates = { 1, 2, 30, 40 }, radius = 4 }
                check(canvas.delete(3) and not canvas.delete(999))
                canvas.truncate(1); check(canvas.count() == 1)
                local ramp = editors.ramp
                ramp.set_stops{ { position = 0, color = { 0, 0, 0, 1 } },
                    { position = 1, color = { 1, 1, 1, 1 } } }
                check(#ramp.stops() == 2 and math.abs(ramp.sample(0.5)[1] - 0.5) < 0.01)
                ramp.select_stop(2); ramp.set_active_color{ 1, 0, 0, 1 }
                check(ramp.active_stop() == 2 and ramp.stops()[2].color[2] == 0)
                refuses(function() ramp.set_stops{} end, '2..32')
                local curve = editors.curve
                curve.set_points(0) { { 0, 0 }, { 1, 1 } }
                check(#curve.points(0) == 2 and math.abs(curve.sample(0)(0.5) - 0.5) < 0.01)
                refuses(function() curve.points(4) end, 'range')
                local textarea = editors.textarea
                refuses(function() textarea.insert_at(2) 'split' end, 'UTF-8')
                textarea.select { start = 1, stop = 3 }
                textarea.selection(){ selected = function(range) check(range.start == 1 and range.stop == 3) end,
                    empty = function() error('missing selection') end }
                textarea.erase { start = 1, stop = 3 }; check(textarea.current() == 'az')
                textarea.insert_at(1) 'é'; check(textarea.current() == 'aéz')
                textarea.move_caret(4); check(textarea.caret() == 4)
                textarea.select { start = 0, stop = 0 }
                textarea.selection(){ selected = function() error('unexpected selection') end,
                    empty = function() check(true) end }
                textarea.set_spans{ { start = 1, stop = 3, foreground = { 1, 0, 0, 1 } } }
                textarea.reveal(4)
                editors.histogram.set_bins{ { 0, 0.5, 1 }, { 1, 0.5, 0 } }
                refuses(function() editors.histogram.set_bins{ { 1 } } end, '2..65536')
                refuses(function() editors.histogram.set_bins{ { 0, 1 }, { 0, 1, 0 } } end, 'unequal')
                editors.grid.set_colors{ { 1, 0, 0, 1 }, { 0, 1, 0, 1 } }
                collectgarbage(); check(surface.render())
            end)
        end))
    end)
end

-- A failing native notification adapter must return to C before the error surfaces.
do
    local broken = setmetatable({}, { __index = function(_, key)
        if key == 'BK_get_num' then return function() error('snapshot fault', 0) end end
        return Native[key]
    end })
    refuses(function()
        Ui.with_application(broken)(function(application)
            opened(application.with_surface{ width = 400, height = 100 }(function(surface)
                surface.with_content(function(place)
                    return place.slider{ minimum = 0, maximum = 1, value = 0 }
                end)(function(slider)
                    surface.render()
                    local rectangle = slider.rectangle()
                    surface.input.press { x = rectangle.x + math.floor(rectangle.width / 2), y = rectangle.y + 5 }
                    surface.input.motion { x = rectangle.x + rectangle.width - 2, y = rectangle.y + 5 }
                    surface.input.release { x = rectangle.x + rectangle.width - 2, y = rectangle.y + 5 }
                end)
            end))
        end)
    end, 'snapshot fault')
end

if arg[2] == '--window' then
    local frames, timer_ran, animation_steps = 0, false, 0
    Ui.with_application(Native)(function(application)
        application.gpu_default(false)
        opened(application.with_window{ title = 'Mua UI activity regression', width = 360, height = 240 }(
            function(window)
                window.with_content(function(place)
                    local readout = place.label('Activity-owned window')
                    return { display = readout.display }
                end)(function(panel)
                    window.show()
                    window.animate(function()
                        animation_steps = animation_steps + 1
                        panel.display('Frame ' .. animation_steps)
                        if animation_steps < 4 then return Ui.Frame.next_frame() end
                        return Ui.Frame.finished()
                    end)
                    window.after(120)(function()
                        timer_ran = true
                        frames = window.frames()
                        window.resize { width = 420, height = 280 }
                        window.after(80)(window.close)
                    end)
                    application.run()
                end)
            end))
    end)
    check(timer_ran and frames > 0 and animation_steps == 4, 'native frame/timer progress')
end
print(('BUI UI: %d checks passed (%s)'):format(checks, ffi.os))
