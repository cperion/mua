-- Owned image/animation/player resources and checked borrows into retained nodes.
-- Image decoding notification stays native: only the documented UI-thread video listener enters Lua.
local ffi = require 'ffi'
local Scope = require 'bui.ui.scope'
local Check = require 'bui.ui.check'
local Handles = require 'bui.ui.handles'
if jit then jit.off(true, true) end

local fits = { fill = 0, contain = 1, cover = 2, none = 3, scale_down = 4 }
local function fit_code(name)
    name = Check.default(name, 'contain')
    assert(fits[name] ~= nil, 'unknown image fit: ' .. tostring(name))
    return fits[name]
end
local function bytes(value, name)
    assert(type(value) == 'string', name .. ' expects an owned byte string')
    return value
end

local function integration(application)
    if not application.extensions.media then application.extensions.media = { loading_started = false } end
    return application.extensions.media
end
local function mark_loading(application) integration(application).loading_started = true end

-- BUI's poster setter does not damage or relayout its borrowers. Refresh their retained
-- bindings explicitly; this happens on a setter, never on every animation frame.
local function refresh_video(application, pointer)
    for _, record in pairs(application.nodes) do
        if record.owner:is_alive() and record.media_changed then record.media_changed(pointer) end
    end
    application:check_error()
end

local function format_name(native, code)
    if code == 0 then return 'raw' end
    local name = native.BK_image_format_name(code)
    assert(name ~= nil, 'unknown native image format')
    return ffi.string(name)
end

local function image_capabilities(application, owner, pointer)
    local native = application.native
    owner:defer(function() native.BK_imbuf_free(pointer) end)
    local width, height = ffi.new('int[1]'), ffi.new('int[1]')
    local frames = tonumber(native.BK_imbuf_size(pointer, width, height))
    local image_width, image_height = tonumber(width[0]), tonumber(height[0])
    local function frame_index(index)
        return Check.integer(Check.default(index, 1), 'image frame', 1, frames) - 1
    end
    local capabilities = {}
    capabilities.info = function()
        owner:check('image info')
        local format = native.BK_imbuf_format(pointer)
        return { width = image_width, height = image_height, frames = frames,
            format = format_name(native, format),
            loops = tonumber(native.BK_imbuf_loops(pointer)) }
    end
    capabilities.rgba = function(index)
        owner:check('copy RGBA pixels')
        local frame = frame_index(index)
        local pixels = ffi.new('unsigned char[?]', image_width * image_height * 4)
        assert(native.BK_imbuf_rgba(pointer, frame, pixels) ~= 0, 'image conversion failed')
        return ffi.string(pixels, image_width * image_height * 4)
    end
    capabilities.argb = function(index)
        owner:check('copy ARGB pixels')
        local pixels = native.BK_imbuf_pixels(pointer, frame_index(index))
        if pixels == nil then return application.protocols.acquisition.unavailable('image has no ARGB view') end
        return application.protocols.acquisition.ready(ffi.string(pixels, image_width * image_height * 4))
    end
    capabilities.delay = function(index)
        owner:check('image frame delay'); return tonumber(native.BK_imbuf_delay(pointer, frame_index(index)))
    end
    return Handles.register(capabilities, owner, 'image', pointer)
end

local function source_options(options)
    -- Source descriptions are owned data, not inherited/accessor-driven properties.
    Check.table(options, 'image source')
    local source = {}
    for key, value in pairs(options) do source[key] = value end
    Check.keys(source, { path = true, bytes = true, rgba = true, argb = true, width = true,
        height = true, stride = true, max_width = true, max_height = true, frame = true }, 'image source')
    local selected, count = nil, 0
    for _, key in ipairs { 'path', 'bytes', 'rgba', 'argb' } do
        if source[key] ~= nil then selected, count = key, count + 1 end
    end
    assert(count == 1, 'image source needs exactly one of path, bytes, rgba, or argb')
    if selected == 'path' then Check.string(source.path, 'image path')
    else bytes(source[selected], 'image bytes') end
    local maximum_width = Check.integer(Check.default(source.max_width, 0), 'maximum width', 0, 16384)
    local maximum_height = Check.integer(Check.default(source.max_height, 0), 'maximum height', 0, 16384)
    if source.frame ~= nil then Check.integer(source.frame, 'decoded frame', 1) end
    if selected == 'rgba' or selected == 'argb' then
        assert(source.frame == nil and source.max_width == nil and source.max_height == nil,
            'raw pixel sources do not take decode options')
        local width = Check.integer(source.width, 'pixel width', 1, 16384)
        local height = Check.integer(source.height, 'pixel height', 1, 16384)
        local stride = Check.integer(Check.default(source.stride, width * 4), 'pixel stride', width * 4)
        if selected == 'argb' then assert(stride == width * 4, 'ARGB pixels must be tightly packed') end
        assert(#source[selected] >= (height - 1) * stride + width * 4, 'pixel buffer is too small')
        return source, selected, width, height, stride
    end
    assert(source.width == nil and source.height == nil and source.stride == nil,
        'encoded images do not take pixel dimensions')
    return source, selected, maximum_width, maximum_height
end

local function read_bytes(source)
    if source.bytes then return source.bytes end
    local file, problem = io.open(source.path, 'rb')
    if not file then return nil, problem end
    local succeeded, data, read_problem = pcall(file.read, file, '*a')
    local closed, close_problem = file:close()
    if not succeeded then return nil, tostring(data) end
    if not data then return nil, read_problem end
    if not closed then return nil, close_problem end
    return data
end

local function acquire_image(application, owner, options)
    owner:mutate('acquire image')
    local source, kind, width, height, stride = source_options(options)
    local native, pointer = application.native
    if kind == 'rgba' then
        pointer = native.BK_imbuf_from_rgba(ffi.cast('const unsigned char *', source.rgba), width, height, stride)
    elseif kind == 'argb' then
        local pixels = ffi.new('uint32_t[?]', width * height)
        ffi.copy(pixels, source.argb, width * height * 4)
        pointer = native.BK_imbuf_from_argb(pixels, width, height)
    elseif source.frame then
        local data, problem = read_bytes(source)
        if not data then return application.protocols.acquisition.unavailable(tostring(problem)) end
        pointer = native.BK_imbuf_decode_frame(data, #data, source.frame - 1, width, height)
    elseif kind == 'path' then pointer = native.BK_imbuf_load(source.path, width, height)
    else pointer = native.BK_imbuf_decode(source.bytes, #source.bytes, width, height) end
    if pointer == nil then return application.protocols.acquisition.unavailable('image could not be decoded or allocated') end
    return application.protocols.acquisition.ready(image_capabilities(application, owner, pointer))
end

local function acquire_animation(application, owner, options)
    owner:mutate('acquire animation')
    local source, kind, maximum_width, maximum_height = source_options(options)
    assert(kind == 'bytes' or kind == 'path', 'animation needs an encoded source')
    assert(not source.frame, 'an animation stream does not take a frame index')
    local data, problem = read_bytes(source)
    if not data then return application.protocols.acquisition.unavailable(tostring(problem)) end
    local native = application.native
    local pointer = native.BK_anim_open(data, #data, maximum_width, maximum_height)
    if pointer == nil then return application.protocols.acquisition.unavailable('source is not a supported animation') end
    owner:defer(function() native.BK_anim_free(pointer) end) -- BK_anim_open copies the input bytes.
    local capabilities = { info = function()
        owner:check('animation info')
        local width, height, loops = ffi.new('int[1]'), ffi.new('int[1]'), ffi.new('int[1]')
        local frames = native.BK_anim_info(pointer, width, height, loops)
        return { width = tonumber(width[0]), height = tonumber(height[0]),
            loops = tonumber(loops[0]), frames = tonumber(frames) }
    end }
    return application.protocols.acquisition.ready(Handles.register(capabilities, owner, 'animation', pointer))
end

local playback_names = { [0] = 'loading', 'playing', 'paused', 'ended', 'failed' }
local function playback(application, code)
    local name = assert(playback_names[tonumber(code)], 'unknown native playback state')
    return application.protocols.playback[name]()
end

local function acquire_video(application, owner, source)
    owner:mutate('acquire video'); Check.string(source, 'video source')
    local native = application.native
    if ffi.string(native.BK_video_backends()) == '' then
        return application.protocols.acquisition.unavailable('this BUI build has no video backend')
    end
    local pointer = native.BK_video_new(source)
    if pointer == nil then return application.protocols.acquisition.unavailable('video player creation failed') end
    owner:defer(function() native.BK_video_free(pointer) end)
    mark_loading(application)
    local media = integration(application)
    if not media.video_listener then
        media.video_listener = application:callback('void (*)(BKVideo *, int, void *)', function(_, code, token)
            local player = application:resolve(token)
            if player and player.connection then
                application:post(player.connection.owner, player.connection.body, playback(application, code))
            end
        end)
    end
    local player = {}
    local token = application:register(owner, player)
    owner:defer(function() native.BK_video_set_listener(pointer, nil, nil) end)
    native.BK_video_set_listener(pointer, media.video_listener, token)
    local capabilities = {}
    capabilities.play = function() owner:mutate('play'); native.BK_video_play(pointer); application:check_error() end
    capabilities.pause = function() owner:mutate('pause'); native.BK_video_pause(pointer); application:check_error() end
    -- GStreamer's signed nanosecond seek conversion must not overflow, even before duration is known.
    capabilities.seek = function(seconds)
        owner:mutate('seek'); native.BK_video_seek(pointer, Check.number(seconds, 'seek time', 0, 9223372036))
        application:check_error()
    end
    capabilities.rate = function(rate)
        owner:mutate('playback rate'); native.BK_video_set_rate(pointer, Check.number(rate, 'rate', 1/16, 16))
        application:check_error()
    end
    capabilities.loop = function(enabled)
        owner:mutate('playback loop'); native.BK_video_set_loop(pointer, Check.boolean(enabled, 'loop') and 1 or 0)
        application:check_error()
    end
    capabilities.poster = function(path)
        owner:mutate('poster'); if path ~= nil then Check.string(path, 'poster path') end
        native.BK_video_set_poster(pointer, path)
        refresh_video(application, pointer)
    end
    capabilities.controls = function(enabled)
        owner:mutate('video controls'); native.BK_video_set_controls(pointer, Check.boolean(enabled, 'controls') and 1 or 0)
        application:check_error()
    end
    capabilities.state = function() owner:check('playback state'); return playback(application, native.BK_video_state(pointer)) end
    capabilities.time = function() owner:check('playback time'); return tonumber(native.BK_video_time(pointer)) end
    capabilities.duration = function() owner:check('video duration'); return tonumber(native.BK_video_duration(pointer)) end
    capabilities.size = function()
        owner:check('video size')
        local width, height = ffi.new('int[1]'), ffi.new('int[1]')
        if native.BK_video_size(pointer, width, height) == 0 then
            return application.protocols.acquisition.unavailable('video size is not known yet')
        end
        return application.protocols.acquisition.ready({ width = tonumber(width[0]), height = tonumber(height[0]) })
    end
    capabilities.on_state_changed = function(body)
        owner:mutate('connect playback'); Check.callable(body, 'playback notification')
        if player.connection then player.connection.owner:close() end
        local connection_owner = owner:child('playback connection')
        local connection = { owner = connection_owner, body = body }
        player.connection = connection
        connection_owner:activate()
        return function()
            connection_owner:close()
            if player.connection == connection then player.connection = nil end
        end
    end
    return application.protocols.acquisition.ready(Handles.register(capabilities, owner, 'video', pointer))
end

local acquisitions = { image = acquire_image, animation = acquire_animation, video = acquire_video }
-- Persistent acquisitions belong to this owner; with_* acquisitions have a bounded child owner.
local function resources(application, owner)
    local vocabulary = {}
    for name, acquire in pairs(acquisitions) do
        vocabulary['acquire_' .. name] = function(source)
            return Scope.prepare(owner, function() return acquire(application, owner, source) end)
        end
        vocabulary['with_' .. name] = function(source)
            owner:mutate('open ' .. name)
            return function(body)
                Check.callable(body, name .. ' body')
                return Scope.with(owner:child(name), function(temporary_owner)
                    return acquire(application, temporary_owner, source) {
                        ready = function(resource)
                            temporary_owner:activate()
                            return application.protocols.acquisition.ready(body(resource))
                        end,
                        unavailable = application.protocols.acquisition.unavailable,
                    }
                end)
            end
        end
    end
    vocabulary.next_frame = function(animation)
        return Scope.prepare(owner, function()
            local pointer = Handles.get(animation, 'animation')
            assert(Handles.owner(animation, 'animation').application == application, 'animation belongs to another application')
            local delay = ffi.new('int[1]')
            local frame = application.native.BK_anim_next(pointer, delay)
            if frame == nil then return application.protocols.acquisition.unavailable('animation frame decode failed') end
            return application.protocols.acquisition.ready({ image = image_capabilities(application, owner, frame),
                milliseconds = tonumber(delay[0]) })
        end)
    end
    return vocabulary
end

-- Global loader policy belongs only to the application, never to individual widgets.
local function images(application)
    local native, owner = application.native, application.owner
    local vocabulary = {}
    vocabulary.inspect = function(options)
        owner:mutate('inspect image')
        Check.keys(options, { path = true, bytes = true }, 'image header source')
        local source, kind = source_options(options)
        assert(kind == 'path' or kind == 'bytes', 'inspection needs an encoded source')
        local info = ffi.new('BKImageInfo[1]')
        local accepted
        if kind == 'path' then accepted = native.BK_image_probe_file(source.path, info)
        else accepted = native.BK_image_probe(source.bytes, #source.bytes, info) end
        if accepted == 0 then return application.protocols.acquisition.unavailable('image header is unavailable') end
        return application.protocols.acquisition.ready({ width = tonumber(info[0].width),
            height = tonumber(info[0].height), frames = tonumber(info[0].frames),
            format = format_name(native, info[0].format) })
    end
    vocabulary.budget = function(count)
        owner:mutate('image cache budget'); native.BK_image_set_budget(Check.integer(count, 'cache bytes', 0,
            ffi.sizeof('size_t') == 8 and 2^53 - 1 or 2^32 - 1))
    end
    vocabulary.threads = function(count)
        owner:mutate('image loader threads')
        assert(not integration(application).loading_started, 'configure loader threads before installing sources or players')
        native.BK_image_set_threads(Check.integer(count, 'loader threads', 0, 64))
    end
    vocabulary.prefetch = function(path, width, height, fit)
        owner:mutate('prefetch image')
        Check.string(path, 'image path'); Check.integer(width, 'width', 1, 16384); Check.integer(height, 'height', 1, 16384)
        local mode = fit_code(fit)
        mark_loading(application); native.BK_image_prefetch(path, width, height, mode)
    end
    vocabulary.clear = function()
        owner:mutate('clear image cache'); native.BK_image_clear_cache(); application:check_error()
    end
    vocabulary.statistics = function()
        owner:check('image cache statistics')
        local statistics = ffi.new('BKImageStats[1]'); native.BK_image_stats(statistics)
        local result = {}
        for _, name in ipairs { 'bytes', 'budget', 'entries', 'pending', 'decoded', 'failed',
            'cancelled', 'evicted', 'decode_ms' } do result[name] = tonumber(statistics[0][name]) end
        return result
    end
    vocabulary.video_backends = function()
        owner:check('video backends')
        local backends = {}
        for name in ffi.string(native.BK_video_backends()):gmatch('[^,]+') do backends[#backends + 1] = name end
        return backends
    end
    return vocabulary
end

local function extend(record)
    if record.kind ~= 'image' and record.kind ~= 'video' and record.kind ~= 'label' and record.kind ~= 'button' then return end
    local native, node, owner, capabilities = record.native, record.node, record.owner, record.capabilities
    local shown_video, shown_fit
    record.media_changed = function(pointer)
        if shown_video == pointer then
            owner:mutate('refresh video presentation')
            native.BK_node_set_video(node, shown_video, shown_fit)
        end
    end
    capabilities.show_image = function(image, fit)
        owner:mutate('show image')
        local pointer, mode = Handles.get(image, 'image', owner), fit_code(fit)
        -- The API has no independent image-fit setter. Clear/set fit before lending the imbuf.
        native.BK_node_set_video(node, nil, mode)
        native.BK_node_set_imbuf(node, pointer)
        shown_video = nil
    end
    capabilities.show_source = function(path, fit)
        owner:mutate('show source'); Check.string(path, 'image source')
        local mode = fit_code(fit)
        mark_loading(record.application); native.BK_node_set_image_source(node, path, mode)
        shown_video = nil
    end
    capabilities.show_frame = function(index)
        owner:mutate('show image frame'); native.BK_node_set_image_frame(node, Check.integer(index, 'image frame', 1))
    end
    capabilities.play_image = function() owner:mutate('play image'); native.BK_node_set_image_frame(node, 0) end
    capabilities.clear_image = function()
        owner:mutate('clear image'); native.BK_node_set_imbuf(node, nil); shown_video = nil
    end
    if record.kind == 'image' or record.kind == 'video' then
        capabilities.show_video = function(video, fit)
            owner:mutate('show video')
            local pointer, mode = Handles.get(video, 'video', owner), fit_code(fit)
            native.BK_node_set_video(node, pointer, mode)
            shown_video, shown_fit = pointer, mode
        end
    end
end

return { resources = resources, images = images, extend = extend, fit_code = fit_code,
    mark_loading = mark_loading }
