-- Retained canvas descriptions and their one native consumer.
-- In particular, BUI borrows item.family: the installed marshalled records pin every string.
local ffi = require 'ffi'
local Check = require 'bui.ui.check'
local Handles = require 'bui.ui.handles'
local Media = require 'bui.ui.media'
if jit then jit.off(true, true) end

local kinds = { rectangle = 0, oval = 1, line = 2, polygon = 3, text = 4, arc = 5,
    image = 6, round_rectangle = 7 }
local allowed = { kind = true, id = true, coordinates = true, fill = true, outline = true,
    width = true, radius = true, size = true, start = true, extent = true, text = true,
    anchor = true, hidden = true, text_flags = true, family = true, clip = true,
    source = true, rgba = true, image = true, video = true, image_width = true,
    image_height = true, fit = true, frame = true }

local function vector(values, count, name, minimum, maximum)
    Check.array(values, name)
    assert(not count or #values == count, name .. ': incorrect coordinate count')
    local copied = {}
    for index, value in ipairs(values) do copied[index] = Check.number(value, name, minimum, maximum) end
    return copied
end

-- Pure validation/copying: no C calls or acquisitions. Resource identities remain opaque;
-- their liveness and retained-borrow constraints are checked only at publication.
local function describe(kind, options, default_identifier)
    assert(kinds[kind] ~= nil, 'unknown canvas item kind: ' .. tostring(kind))
    Check.keys(options, allowed, kind .. ' item')
    if options.kind ~= nil then assert(options.kind == kind, 'canvas item kind mismatch') end
    local coordinates = vector(options.coordinates, nil, 'coordinates', -1e7, 1e7)
    local count = #coordinates
    if kind == 'text' then assert(count == 2, 'text needs x,y')
    elseif kind == 'image' then assert(count == 2 or count == 4, 'image needs a point or a box')
    elseif kind == 'polygon' then assert(count >= 6 and count % 2 == 0, 'polygon needs three or more points')
    elseif kind == 'line' then assert(count >= 4 and count % 2 == 0, 'line needs two or more points')
    else assert(count == 4, kind .. ' needs x0,y0,x1,y1') end
    local result = {
        kind = kind, id = Check.integer(Check.default(options.id, default_identifier), 'item id', 1),
        coordinates = coordinates,
        fill = vector(Check.default(options.fill, { 0, 0, 0, 1 }), 4, 'fill', 0, 1),
        outline = vector(Check.default(options.outline, { 0, 0, 0, 0 }), 4, 'outline', 0, 1),
        width = Check.number(Check.default(options.width, 1), 'line width', 0, 1e5),
        radius = Check.number(Check.default(options.radius, 0), 'radius', 0, 1e5),
        size = Check.number(Check.default(options.size, 14), 'text size', 1, 4096),
        start = Check.number(Check.default(options.start, 0), 'arc start', -1e6, 1e6),
        extent = Check.number(Check.default(options.extent, 360), 'arc extent', -360, 360),
        text = Check.string(Check.default(options.text, ''), 'item text'),
        anchor = Check.integer(Check.default(options.anchor, 0), 'anchor flags', 0, 15),
        hidden = options.hidden ~= nil and Check.boolean(options.hidden, 'hidden') or false,
        text_flags = Check.integer(Check.default(options.text_flags, 0), 'text flags', 0, 7),
        family = Check.string(Check.default(options.family, ''), 'font family'),
        fit = Check.default(options.fit, 'contain'),
        frame = Check.integer(Check.default(options.frame, 0), 'image frame', 0),
    }
    Media.fit_code(result.fit)
    if options.clip ~= nil then
        result.clip = vector(options.clip, 4, 'clip', -1e7, 1e7)
        assert(result.clip[3] >= 0 and result.clip[4] >= 0, 'negative clip size')
    end
    if kind == 'image' then
        local sources = 0
        for _, name in ipairs { 'source', 'rgba', 'image', 'video' } do
            if options[name] ~= nil then sources = sources + 1 end
        end
        assert(sources == 1, 'image needs exactly one source')
        if options.source ~= nil then result.source = Check.string(options.source, 'image source')
        elseif options.image ~= nil then
            assert(Handles.kind(options.image) == 'image', 'expected an owned image capability')
            result.image = options.image
        elseif options.video ~= nil then
            assert(count == 4, 'video items need a box before their intrinsic size is known')
            assert(Handles.kind(options.video) == 'video', 'expected an owned video capability')
            result.video = options.video
        else
            assert(type(options.rgba) == 'string', 'rgba expects an owned byte string')
            result.image_width = Check.integer(options.image_width, 'image width', 1, 16384)
            result.image_height = Check.integer(options.image_height, 'image height', 1, 16384)
            assert(#options.rgba == result.image_width * result.image_height * 4, 'incorrect RGBA byte count')
            result.rgba = options.rgba
        end
    else
        assert(options.source == nil and options.rgba == nil and options.image == nil and options.video == nil,
            'pixel sources belong to image items')
    end
    return result
end

local function marshal(description, owner)
    local item = ffi.new('BKCanvasItem[1]')
    local coordinates = ffi.new('float[?]', #description.coordinates, description.coordinates)
    item[0].id, item[0].type = description.id, kinds[description.kind]
    item[0].coords, item[0].ncoords = coordinates, #description.coordinates
    for index = 1, 4 do
        item[0].fill[index - 1], item[0].outline[index - 1] = description.fill[index], description.outline[index]
    end
    for _, field in ipairs { 'width', 'radius', 'size', 'start', 'extent', 'text', 'anchor', 'text_flags', 'family' } do
        item[0][field] = description[field]
    end
    item[0].hidden = description.hidden and 1 or 0
    item[0].fit, item[0].frame = Media.fit_code(description.fit), description.frame
    if description.image then item[0].imbuf = Handles.get(description.image, 'image', owner) end
    if description.video then item[0].video = Handles.get(description.video, 'video', owner) end
    if description.clip then
        item[0].clip_on = 1
        for index = 1, 4 do item[0].clip[index - 1] = description.clip[index] end
    end
    if description.source then item[0].src = description.source end
    if description.rgba then
        item[0].rgba = ffi.cast('const unsigned char *', description.rgba)
        item[0].iw, item[0].ih = description.image_width, description.image_height
    end
    return { description = description, item = item, coordinates = coordinates }
end

-- Add retained-item operations only to canvas capabilities; indexes are one-based in the DSL.
local function extend(record)
    if record.kind ~= 'canvas' then return end
    local owner, native, node, capabilities = record.owner, record.native, record.node, record.capabilities
    local installed, pending = {}, nil
    record.media_changed = function(video)
        for index, entry in ipairs(installed) do
            if entry.item[0].video == video then
                owner:mutate('refresh canvas video')
                native.BK_canvas_put_item(node, index - 1, entry.item)
            end
        end
    end
    local function find(identifier)
        for index, entry in ipairs(installed) do
            if entry.description.id == identifier then return index end
        end
    end
    local function prepared(description)
        Check.table(description, 'canvas item')
        return marshal(describe(description.kind, description, description.id), owner)
    end
    local function installing(entry)
        if entry.description.source then Media.mark_loading(record.application) end
    end
    capabilities.replace = function(descriptions)
        owner:mutate('replace canvas')
        Check.array(descriptions, 'drawing list')
        local replacements, identifiers = {}, {}
        for index, description in ipairs(descriptions) do
            replacements[index] = prepared(description)
            local identifier = replacements[index].description.id
            assert(not identifiers[identifier], 'duplicate canvas item id')
            identifiers[identifier] = true
        end
        owner:mutate('publish drawing') -- Input accessors may have retired this owner during copying.
        -- Pin before changing C; even an unexpected native failure cannot leave borrowed strings dangling.
        pending = { previous = pending, replacements = replacements }
        for index, entry in ipairs(replacements) do
            installing(entry)
            native.BK_canvas_put_item(node, index - 1, entry.item)
        end
        native.BK_canvas_truncate(node, #replacements)
        installed, pending = replacements, nil
    end
    capabilities.set_item = function(description)
        owner:mutate('set canvas item')
        local entry = prepared(description)
        owner:mutate('publish canvas item')
        local index = find(entry.description.id) or #installed + 1
        local previous = installed[index]
        installed[index] = entry
        installing(entry)
        native.BK_canvas_set_item(node, entry.item)
        -- Keep the replaced entry reachable through the native call as well.
        if previous then previous = nil end
    end
    capabilities.append = function(description)
        owner:mutate('append canvas item')
        local entry = prepared(description)
        owner:mutate('append prepared canvas item')
        assert(not find(entry.description.id), 'duplicate canvas item id')
        installed[#installed + 1] = entry
        installing(entry)
        native.BK_canvas_add_item(node, entry.item)
    end
    capabilities.put = function(index, description)
        owner:mutate('put canvas item')
        Check.integer(index, 'canvas index', 1, #installed + 1)
        local entry = prepared(description)
        owner:mutate('publish indexed canvas item')
        local existing = find(entry.description.id)
        assert(not existing or existing == index, 'duplicate canvas item id')
        local previous = installed[index]
        installed[index] = entry
        installing(entry)
        native.BK_canvas_put_item(node, index - 1, entry.item)
        if previous then previous = nil end
    end
    capabilities.delete = function(identifier)
        owner:mutate('delete canvas item'); Check.integer(identifier, 'item id', 1)
        local index = find(identifier)
        if not index then return false end
        native.BK_canvas_delete(node, identifier)
        table.remove(installed, index)
        return true
    end
    capabilities.truncate = function(count)
        owner:mutate('truncate canvas'); Check.integer(count, 'item count', 0, #installed)
        native.BK_canvas_truncate(node, count)
        for index = #installed, count + 1, -1 do installed[index] = nil end
    end
    local function reorder(identifier, top)
        owner:mutate('reorder canvas'); Check.integer(identifier, 'item id', 1)
        local index = find(identifier)
        if not index then return false end
        native.BK_canvas_raise(node, identifier, top and 1 or 0)
        local entry = table.remove(installed, index)
        table.insert(installed, top and #installed + 1 or 1, entry)
        return true
    end
    capabilities.raise = function(identifier) return reorder(identifier, true) end
    capabilities.lower = function(identifier) return reorder(identifier, false) end
    capabilities.count = function() owner:check('canvas count'); return #installed end
    -- Captures stay alive through node destruction, even if every public capability was discarded.
    owner:defer(function() native.BK_canvas_truncate(node, 0); installed, pending = {}, nil end)
end

return { kinds = kinds, describe = describe, extend = extend }
