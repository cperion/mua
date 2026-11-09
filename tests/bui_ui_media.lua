-- Managed media contracts: byte ownership, retained loans, rollback, and UI-thread delivery.
local mua = require 'mua.init'
table.insert(package.loaders, 2, mua.searcher())
local ffi = require 'ffi'
local Ui = require 'bui.ui'
local Scope = require 'bui.ui.scope'
local Clock = require 'bui.ui.clock'
ffi.cdef[[int usleep(unsigned int); void __stdcall Sleep(unsigned long);]]
local function pause_briefly()
    if ffi.os == 'Windows' then ffi.C.Sleep(1) else ffi.C.usleep(1000) end
end
local Native = require('bui.ffi').load(assert(arg[1], 'usage: tests/bui_ui_media.lua library video_fixture'))
local video_fixture = assert(arg[2], 'pass the pinned BUI tests/videos/clip.mp4 fixture')
local checks = 0
local function check(condition, message)
    assert(condition, message); checks = checks + 1
end
local function rejects(body, fragment)
    local succeeded, problem = pcall(body)
    check(not succeeded and tostring(problem):find(fragment, 1, true), tostring(problem))
end
local function ready(result)
    return result { ready = function(value) return value end, unavailable = function(reason) error(reason) end }
end
local function opened(result)
    return result { opened = function(value) return value end, unavailable = function(reason) error(reason) end }
end
local function unavailable(result)
    return result { ready = function() return false end, unavailable = function(reason) return #reason > 0 end }
end
local function playback_name(result)
    return result { loading = function() return 'loading' end, playing = function() return 'playing' end,
        paused = function() return 'paused' end, ended = function() return 'ended' end, failed = function() return 'failed' end }
end

-- Two 1x1 GIF frames, red then black, each lasting 50 ms. No generated binding/fixture tooling.
local gif = 'GIF89a' .. string.char(1,0,1,0,128,0,0, 0,0,0,255,0,0)
local function gif_frame(pixel_code)
    return string.char(33,249,4,0,5,0,0,0, 44,0,0,0,0,1,0,1,0,0, 2,2,pixel_code,1,0)
end
gif = gif .. gif_frame(76) .. gif_frame(68) .. ';'
local red = string.char(255,0,0,255)
local temporary = os.tmpname()
os.remove(temporary)
local directory = arg[1]:match('^(.*)[/\\]') or '.'
local fixture = directory .. '/ui-media-' .. temporary:gsub('.*[/\\]', '') .. '.gif'
local file = assert(io.open(fixture, 'wb'))
assert(file:write(gif)); assert(file:close())

local function run()
    local parent, cleanup = Scope.new(nil, 'preparation test'), {}
    parent.activate()
    parent.defer(function() cleanup[#cleanup + 1] = 'old' end)
    rejects(function()
        Scope.prepare(parent, function()
            parent.defer(function() cleanup[#cleanup + 1] = 'new'; error('secondary failure') end)
            local child = parent.child('temporary child'); child.activate()
            child.defer(function() cleanup[#cleanup + 1] = 'child' end)
            error('primary failure')
        end)
    end, 'primary failure')
    check(parent.is_alive() and parent.child_count() == 0, 'preparation preserves parent')
    check(table.concat(cleanup, ',') == 'child,new', 'partial resources released in dependency order')
    parent.close()
    check(table.concat(cleanup, ',') == 'child,new,old', 'old acquisitions retained until parent completion')

    local expired_image, expired_animation, expired_player, late_resources
    Ui.with_application(Native)(function(application)
        late_resources = application.resources
        application.images.threads(1)
        application.images.budget(8 * 1024 * 1024)
        check(application.images.statistics().budget == 8 * 1024 * 1024, 'cache budget is explicit')
        check(type(application.images.video_backends()) == 'table', 'backend availability is exposed')
        local image = ready(application.resources.acquire_image { rgba = red, width = 1, height = 1 })
        local info = image.info()
        check(info.width == 1 and info.height == 1 and info.frames == 1 and info.format == 'raw',
            'owned image dimensions and unnamed native raw format')
        check(image.rgba() == red and image.delay() == 0, 'copied straight RGBA pixels')
        local copied = ready(application.resources.acquire_image { argb = ready(image.argb()), width = 1, height = 1 })
        check(copied.rgba() == red, 'premultiplied ARGB round trip')
        local own_data = setmetatable({ rgba = red, width = 1, height = 1 },
            { __index = function() error('source getter must not run') end })
        check(ready(application.resources.acquire_image(own_data)).rgba() == red, 'source options snapshot own fields')
        info.width = 100
        check(image.info().width == 1, 'metadata is copied')
        rejects(function() image.rgba(0) end, 'image frame')
        rejects(function() image.rgba(false) end, 'image frame')
        rejects(function() application.resources.acquire_image { rgba = red, width = 2, height = 1 } end, 'too small')
        rejects(function() application.resources.acquire_image { rgba = red, width = 1, height = 1, stride = false } end, 'stride')
        rejects(function() application.resources.acquire_image { bytes = gif, max_width = false } end, 'maximum width')
        rejects(function() application.resources.acquire_image { bytes = gif, path = fixture } end, 'exactly one')
        rejects(function() application.resources.acquire_image { bytes = gif, width = 1 } end, 'pixel dimensions')
        rejects(function() application.resources.acquire_image { path = 'bad\0path' } end, 'NUL')
        check(unavailable(application.resources.acquire_image { bytes = 'not an image' }), 'decode refusal is an outcome')
        check(unavailable(application.resources.acquire_image { path = fixture .. '.missing' }), 'missing file is an outcome')
        local header = ready(application.images.inspect { bytes = gif })
        check(header.width == 1 and header.height == 1 and header.frames == 2, 'encoded header snapshot')
        check(ready(application.images.inspect { path = fixture }).frames == 2, 'file header snapshot')
        check(unavailable(application.images.inspect { bytes = 'bad header' }), 'header refusal is an outcome')
        local decoded = ready(application.resources.acquire_image { path = fixture, frame = 1 })
        check(decoded.rgba() == red, 'selected frame decoding')
        local padded = ready(application.resources.acquire_image { rgba = red .. 'pad!' .. red,
            width = 1, height = 2, stride = 8 })
        check(padded.rgba() == red .. red, 'strided input is checked and copied')

        local held_frame
        ready(application.resources.with_animation { bytes = gif }(function(animation)
            expired_animation = animation
            check(animation.info().frames == 2, 'animation metadata')
            held_frame = ready(application.resources.next_frame(animation))
            check(held_frame.milliseconds == 50 and held_frame.image.rgba() == red, 'first independent animation frame')
            local next_frame = ready(application.resources.next_frame(animation))
            check(next_frame.image.rgba() == string.char(0,0,0,255), 'animation advances')
        end))
        check(held_frame.image.rgba() == red, 'decoded frame survives its source decoder')
        rejects(function() expired_animation.info() end, 'ended')
        rejects(function() application.resources.next_frame(expired_animation) end, 'ended')
        check(unavailable(application.resources.acquire_animation { bytes = 'bad animation' }), 'animation refusal')
        local ran = false
        check(unavailable(application.resources.with_image { bytes = 'bad image' }(function() ran = true end)) and not ran,
            'unavailable acquisition does not enter body')
        ready(application.resources.with_image { rgba = red, width = 1, height = 1 }(function(temporary_image)
            expired_image = temporary_image
            check(temporary_image.rgba() == red, 'bounded image activity')
        end))
        rejects(function() expired_image.info() end, 'ended')

        opened(application.with_surface { width = 240, height = 160 }(function(surface)
            local registrations_before_content = application.statistics().registrations
            surface.with_content(function(place)
                local picture = place.image { width = 40, height = 40 }
                local canvas = place.canvas { width = 40, height = 40 }
                local video_node = place.video { width = 40, height = 40 }
                local slot = place.slot {}
                picture.show_image(image) 'contain'
                rejects(function() picture.show_image({}) 'contain' end, 'owned image')
                rejects(function() picture.show_image(image)(false) end, 'image fit')
                canvas.replace(Ui.drawing(function(draw)
                    draw.image { coordinates = { 0, 0, 40, 40 }, image = image }
                end))
                check(canvas.count() == 1, 'canvas retains an ancestor-owned image')
                rejects(function()
                    canvas.append { id = 2, kind = 'image', coordinates = { 0, 0 }, image = {} }
                end, 'owned image')
                rejects(function()
                    Ui.drawing(function(draw) draw.rectangle { coordinates = { 0,0,10,10 }, fill = false } end)
                end, 'fill')
                local component_resource = slot.replace(function(child_place)
                    return ready(child_place.resources.acquire_image { rgba = red, width = 1, height = 1 })
                end)
                check(component_resource.rgba() == red, 'component resource alias retains its identity')
                rejects(function() picture.show_image(component_resource) 'contain' end, 'must outlive')
                slot.clear()
                rejects(function() component_resource.info() end, 'ended')
                local target = slot.replace(function(child) return child.label 'Temporary' end)
                local retire_on_read = { __index = function() slot.clear(); return nil end }
                rejects(function() target.configure(setmetatable({ caption = 'Too late' }, retire_on_read)) end, 'ended')
                target = slot.replace(function(child) return child.canvas {} end)
                rejects(function()
                    target.replace { setmetatable({ kind = 'rectangle', id = 1, coordinates = { 0,0,10,10 } }, retire_on_read) }
                end, 'ended')
                target = slot.replace(function(child) return child.ramp {} end)
                rejects(function()
                    target.set_stops { setmetatable({ color = { 1,0,0,1 } }, {
                        __index = function() slot.clear(); return 0 end,
                    }), { position = 1, color = { 0,0,1,1 } } }
                end, 'ended')
                local holes = { 'first', 'second', 'third', 'fourth' }; holes[2] = nil
                setmetatable(holes, { __index = function() return 'not an owned array entry' end })
                rejects(function() place.dropdown { items = holes } end, 'hole')
                ready(application.resources.with_image { rgba = red, width = 1, height = 1 }(function(temporary_image)
                    rejects(function() picture.show_image(temporary_image) 'contain' end, 'must outlive')
                    rejects(function()
                        canvas.replace(Ui.drawing(function(draw)
                            draw.image { coordinates = { 0, 0 }, image = temporary_image }
                        end))
                    end, 'must outlive')
                    check(canvas.count() == 1, 'failed replacement preserves installed items')
                end))
                local local_image = ready(place.resources.acquire_image { rgba = red, width = 1, height = 1 })
                picture.show_image(local_image) 'contain' -- Acquisition may follow construction: children still release first.
                local player = place.resources.acquire_video(video_fixture) {
                    ready = function(value) return value end,
                    unavailable = function(reason)
                        check(#application.images.video_backends() == 0, reason)
                        assert(arg[3] ~= '--require-video', reason)
                    end,
                }
                expired_player = player
                if player then
                    video_node.show_video(player) 'contain'
                    canvas.append { id = 2, kind = 'image', coordinates = { 0, 0, 30, 30 }, video = player }
                end
                picture.show_frame(1); picture.play_image()
                return { player = player, picture = picture, canvas = canvas }
            end)(function(content)
                if content.player then
                    local player, notifications, states = content.player, 0, {}
                    local disconnect = player.on_state_changed(function(playback)
                        content.picture.invalidate() -- Legal only after the native render/input stack returned.
                        notifications = notifications + 1; states[#states + 1] = playback_name(playback)
                    end)
                    check(unavailable(player.size()), 'size is unavailable before decoding')
                    player.loop(true)
                    local deadline = Clock.now() + 3
                    repeat
                        surface.render(); pause_briefly() -- Decode and enqueue, but do not deliver Lua notifications yet.
                    until playback_name(player.state()) ~= 'loading' or Clock.now() >= deadline
                    local state = playback_name(player.state())
                    check(state == 'playing' or state == 'failed', 'decoder settles within bounded wait')
                    check(notifications == 0, 'native playback notification is deferred')
                    application.pump()
                    check(notifications == 1 and states[1] == state, 'loaded/failure snapshot delivered outside C')
                    if state == 'playing' then
                        local dimensions = ready(player.size())
                        check(dimensions.width == 96 and dimensions.height == 54, 'native video intrinsic dimensions')
                        player.pause(); player.play()
                        check(notifications == 1, 'synchronous native state changes are queued')
                        application.pump()
                        check(notifications == 3 and states[2] == 'paused' and states[3] == 'playing',
                            'playback snapshots delivered FIFO after C returns')
                        player.pause(); disconnect()
                        local previous = notifications
                        application.pump()
                        check(notifications == previous, 'disconnect revokes queued playback notification')
                        player.play()
                        local initial = player.time()
                        deadline = Clock.now() + 2
                        repeat
                            surface.render(); application.pump(); pause_briefly()
                        until player.time() > initial or Clock.now() >= deadline
                        check(player.time() > initial, 'native video frames progress while drawn')
                        print('BUI media: real video playback verified')
                    else
                        disconnect()
                        assert(arg[3] ~= '--require-video', 'video decoding is unavailable in this environment')
                        print('BUI media: native video decoder unavailable; failure outcome verified')
                    end
                    local callbacks = application.statistics().callbacks
                    for _ = 1, 100 do
                        local cancel = player.on_state_changed(function() end); cancel()
                    end
                    check(application.statistics().callbacks == callbacks, 'video listener trampoline is pooled')
                    player.rate(2); player.seek(0); player.loop(true)
                    player.controls(true); player.poster(fixture); player.poster(nil)
                    rejects(function() player.rate(0) end, 'rate')
                    rejects(function() player.seek(-1) end, 'seek time')
                    rejects(function() player.seek(1e30) end, 'seek time')
                    rejects(function() player.loop(1) end, 'loop')
                    rejects(function() application.images.threads(2) end, 'before installing')
                    check(player.time() >= 0 and player.duration() >= 0, 'player clock queries')
                end
                content.picture.clear_image(); content.picture.show_source(fixture) 'cover'
                application.images.prefetch(fixture) { width = 10, height = 10 } 'contain'
                application.pump()
                check(application.images.statistics().entries >= 1, 'source cache participates in managed dispatch')
                content.canvas.replace {}
            end)
            if expired_player then rejects(function() expired_player.play() end, 'ended') end
            check(application.statistics().registrations == registrations_before_content, 'retired media listeners are unregistered')
        end))
        application.images.clear()
    end)
    rejects(function() late_resources.acquire_image { rgba = red, width = 1, height = 1 } end, 'ended')

    -- Inject UI-thread callbacks independently of installed codecs; still use actual owned BKVideo objects.
    local callback, callback_token, in_native, invalid_state
    local test_backend = ffi.new('char[5]', 'test')
    local observed = setmetatable({
        BK_video_backends = function() return test_backend end,
        BK_video_set_listener = function(pointer, listener, token)
            if listener ~= nil then callback, callback_token = listener, token end
            Native.BK_video_set_listener(pointer, listener, token)
        end,
        BK_video_play = function(pointer)
            in_native = true
            callback(pointer, invalid_state and 99 or 2, callback_token)
            if not invalid_state then callback(pointer, 1, callback_token) end
            in_native = false
        end,
    }, { __index = function(_, key) return Native[key] end })
    Ui.with_application(observed)(function(application)
        local delivered, states = 0, {}
        local function receive(playback)
            check(not in_native, 'application continuation never runs on the native callback stack')
            application.images.budget(1024 * 1024)
            delivered = delivered + 1; states[#states + 1] = playback_name(playback)
        end
        ready(application.resources.with_video(fixture)(function(player)
            local disconnect = player.on_state_changed(receive)
            player.play()
            check(delivered == 0, 'injected native playback is deferred')
            application.pump()
            check(delivered == 2 and states[1] == 'paused' and states[2] == 'playing', 'callback arguments are snapshotted')
            player.play(); disconnect(); application.pump()
            check(delivered == 2, 'disconnect discards queued snapshots')
            local old_disconnect = player.on_state_changed(function() error('replaced listener ran') end)
            player.play()
            player.on_state_changed(receive); old_disconnect()
            player.play(); application.pump()
            check(delivered == 4, 'replacement revokes old delivery, not the new listener')
            player.play() -- The resource activity ends with these notifications still queued.
        end))
        callback(nil, 4, callback_token) -- A stale registration must not resolve, while the shared trampoline is alive.
        application.pump()
        check(delivered == 4 and application.statistics().registrations == 0, 'retirement discards queued and late native work')
        invalid_state = true
        ready(application.resources.with_video(fixture)(function(player)
            player.on_state_changed(function() error('invalid state was delivered') end)
            rejects(player.play, 'unknown native playback state')
            rejects(application.pump, 'unknown native playback state')
        end))
    end)

    local node_bindings, canvas_bindings = 0, 0
    local presentations = setmetatable({
        BK_video_backends = function() return test_backend end,
        BK_node_set_video = function(node, player, fit)
            if player ~= nil then node_bindings = node_bindings + 1 end
            Native.BK_node_set_video(node, player, fit)
        end,
        BK_canvas_put_item = function(node, index, item)
            if item[0].video ~= nil then canvas_bindings = canvas_bindings + 1 end
            Native.BK_canvas_put_item(node, index, item)
        end,
    }, { __index = function(_, key) return Native[key] end })
    Ui.with_application(presentations)(function(application)
        opened(application.with_surface {}(function(surface)
            surface.with_content(function(place)
                local player = ready(place.resources.acquire_video(fixture))
                local picture, canvas = place.video {}, place.canvas {}
                picture.show_video(player) 'contain'
                canvas.replace { { id = 1, kind = 'image', coordinates = { 0,0,40,40 }, video = player } }
                rejects(function()
                    Ui.drawing(function(draw) draw.image { coordinates = { 0, 0 }, video = player } end)
                end, 'need a box')
                player.poster(fixture)
                check(node_bindings == 2 and canvas_bindings == 2, 'poster refreshes retained node and canvas bindings')
                picture.clear_image(); canvas.replace {}
                player.poster(nil)
                check(node_bindings == 2 and canvas_bindings == 2, 'poster does not resurrect cleared borrowers')
            end)(function() end)
        end))
    end)

    local no_backends = ffi.new('char[1]')
    local unavailable_backend = setmetatable({ BK_video_backends = function() return no_backends end },
        { __index = function(_, key) return Native[key] end })
    Ui.with_application(unavailable_backend)(function(application)
        check(unavailable(application.resources.acquire_video(fixture)), 'missing video backend is explicit')
        local entered = false
        check(unavailable(application.resources.with_video(fixture)(function() entered = true end)) and not entered,
            'missing backend does not enter the resource body')
        check(application.statistics().registrations == 0, 'unavailable backend acquired nothing')
        rejects(function() application.with_surface { width = false }(function() end) end, 'width')
    end)

    -- Disposal while a real worker is loading must revoke its listener before joining the worker.
    Ui.with_application(Native)(function(application)
        if #application.images.video_backends() == 0 then return end
        local delivered = 0
        opened(application.with_surface {}(function(surface)
            local registrations = application.statistics().registrations
            surface.with_content(function(place)
                local player = ready(place.resources.acquire_video(video_fixture))
                player.on_state_changed(function() delivered = delivered + 1 end)
                place.video { width = 80, height = 60 }.show_video(player) 'contain'
            end)(function() surface.render() end)
            application.pump()
            check(delivered == 0 and application.statistics().registrations == registrations,
                'pending worker cannot notify a disposed player')
        end))
    end)

    -- A setup failure after native allocation must free immediately, not merely at application exit.
    local freed = 0
    local faulty = setmetatable({
        BK_imbuf_size = function() error('injected metadata failure') end,
        BK_imbuf_free = function(pointer) freed = freed + 1; Native.BK_imbuf_free(pointer) end,
    }, { __index = function(_, key) return Native[key] end })
    Ui.with_application(faulty)(function(application)
        rejects(function() application.resources.acquire_image { rgba = red, width = 1, height = 1 } end,
            'injected metadata failure')
        check(freed == 1, 'partial resource is freed before returning to caller')
    end)
    check(freed == 1, 'rolled-back resource is not freed twice')

    local destruction = {}
    local tracing = setmetatable({
        BK_node_free = function(node)
            if ffi.string(Native.BK_node_type(node)) == 'image' then destruction[#destruction + 1] = 'node' end
            Native.BK_node_free(node)
        end,
        BK_imbuf_free = function(pointer) destruction[#destruction + 1] = 'image'; Native.BK_imbuf_free(pointer) end,
    }, { __index = function(_, key) return Native[key] end })
    Ui.with_application(tracing)(function(application)
        opened(application.with_surface {}(function(surface)
            surface.with_content(function(place)
                local picture = place.image {}
                local image = ready(place.resources.acquire_image { rgba = red, width = 1, height = 1 })
                picture.show_image(image) 'contain'
            end)(function() surface.render() end)
        end))
    end)
    check(table.concat(destruction, ',') == 'node,image', 'borrower releases before its owner even when acquired first')
end

local succeeded, problem = xpcall(run, debug.traceback)
os.remove(fixture)
assert(succeeded, problem)
print(string.format('BUI media: %d checks passed (%s)', checks, ffi.os))
