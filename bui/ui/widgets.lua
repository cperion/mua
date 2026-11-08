-- Checked property descriptions, shared by construction and in-place updates.
-- Native names remain inside this edge; captions and values have consistent public meanings.
local ffi = require 'ffi'
local Check = require 'bui.ui.check'
if jit then jit.off(true, true) end

local catalog = {}
local function kinds(names, container, value_type, caption)
    for name in names:gmatch('%S+') do
        local public, native = name:match('([^=]+)=([^=]+)')
        public, native = public or name, native or name
        catalog[public] = { kind = native, container = container, value_type = value_type,
            caption = caption or 'text' }
    end
end
kinds('column row split grid box panel scroll frame node_editor=nodeeditor graph_node=graphnode area_header=areaheader', true)
kinds('tabs side_tabs=sidetabs sidebar', true, 'number')
kinds('label separator button decorator popover menu_button=menubutton menu_bar=menubar', false)
kinds('toggle checkbox radio', false, 'boolean', 'label')
kinds('number slider', false, 'number', 'label')
kinds('dropdown enum list tree grid_view=gridview scrollbar', false, 'number')
kinds('text search hotkey textarea', false, 'string')
kinds('swatch', false, 'color')
kinds('progress meter', false, 'fraction')
kinds('ramp curve normal histogram canvas image custom video file_browser=filebrowser', false)

local properties = {}
local function properties_of(names, value_type)
    for name in names:gmatch('%S+') do properties[name] = { key = name, type = value_type } end
end
properties_of('visible enabled align emboss vertical icon_only collapsed integer live alpha square directory line bold events nopropagate viewevents noscrollbar opaque html bare active_default fill', 'boolean')
properties_of('weight factor tile split scroll scroll_x font_scale', 'number')
properties_of('precision spacing padding columns rows current cursor', 'integer')
properties_of('text label description placeholder mask suffix category icon icon_on text_align', 'string')
properties_of('items headers groups icons', 'strings')
properties_of('color bg text_color', 'color')
properties.minimum = { key = 'min', type = 'number', order = 1 }
properties.maximum = { key = 'max', type = 'number', order = 1 }
properties.step = { key = 'step', type = 'number', order = 1 }
properties.default = { key = 'default', type = 'number', order = 2 }
properties.height_units = { key = 'height', type = 'number' }
properties.width = { key = 'reqwidth', type = 'integer', geometry = true }
properties.height = { key = 'reqheight', type = 'integer', geometry = true }

local function specification(descriptor, name)
    if name == 'caption' then return { key = descriptor.caption, type = 'string' } end
    if name == 'value' and descriptor.value_type then
        return { key = descriptor.value_type == 'fraction' and 'factor' or 'value',
            type = descriptor.value_type, order = 3 }
    end
    return properties[name]
end

local function checked_value(specification, value, name)
    local kind = specification.type
    if kind == 'boolean' then return Check.boolean(value, name) and 1 or 0 end
    if kind == 'number' then return Check.number(value, name) end
    if kind == 'integer' then
        return Check.integer(value, name, specification.geometry and 0 or nil)
    end
    if kind == 'fraction' then return Check.number(value, name, 0, 1) end
    if kind == 'string' then
        Check.string(value, name)
        if specification.key == 'text_align' and value ~= 'left' and value ~= 'right'
            and value ~= 'center' then error(name .. ': expected left, center, or right', 3) end
        return value
    end
    if kind == 'color' then return Check.color(value, name) end
    if kind == 'strings' then return Check.strings(value, name) end
end

-- Validate all fields before changing any node; property order never depends on pairs().
local function prepare(descriptor, options)
    if type(options) == 'string' then options = { caption = options } end
    options = Check.default(options, {})
    Check.table(options, descriptor.kind .. ' options')
    local prepared = {}
    if options.minimum and options.maximum then
        Check.number(options.minimum, 'minimum'); Check.number(options.maximum, 'maximum')
        assert(options.minimum <= options.maximum, 'minimum exceeds maximum')
    end
    for name, value in pairs(options) do
        local spec = specification(descriptor, name)
        if not spec then error(descriptor.kind .. ': unknown property ' .. tostring(name), 3) end
        local normalized, retained = checked_value(spec, value, descriptor.kind .. '.' .. name)
        prepared[#prepared + 1] = { name = name, specification = spec, value = normalized,
            retained = retained, count = spec.type == 'strings' and #value or nil }
    end
    table.sort(prepared, function(left, right)
        local left_order, right_order = left.specification.order or 0, right.specification.order or 0
        if left_order ~= right_order then return left_order < right_order end
        return left.name < right.name
    end)
    return prepared
end

local function apply(record, prepared)
    -- Input accessors may have completed the activity while its data was being normalized.
    record.owner:mutate('apply ' .. record.kind .. ' properties')
    local native, node = record.native, record.node
    local limits = record.limits or {}
    local minimum, maximum = limits.minimum, limits.maximum
    for _, entry in ipairs(prepared) do
        if entry.name == 'minimum' then minimum = entry.value end
        if entry.name == 'maximum' then maximum = entry.value end
    end
    assert(not minimum or not maximum or minimum <= maximum, 'minimum exceeds maximum')
    for _, entry in ipairs(prepared) do
        local spec, accepted = entry.specification
        if spec.geometry then
            native.BK_geom_set(node, spec.key, entry.value)
            accepted = 1
        elseif spec.type == 'string' then
            accepted = native.BK_set_str(node, spec.key, entry.value)
        elseif spec.type == 'color' then
            accepted = native.BK_set_color(node, spec.key, entry.value)
        elseif spec.type == 'strings' then
            accepted = native.BK_set_strs(node, spec.key, entry.value, entry.count)
        else
            accepted = native.BK_set_num(node, spec.key, entry.value)
        end
        assert(accepted == 1, record.kind .. ': native property refused ' .. entry.name)
    end
    record.limits = { minimum = minimum, maximum = maximum }
end

local function current(record)
    record.owner:check('read current value')
    local native, node, kind = record.native, record.node, record.descriptor.value_type
    if kind == 'string' then return ffi.string(native.BK_get_str(node, 'value')) end
    if kind == 'color' then
        local channels = ffi.new('float[4]')
        assert(native.BK_get_color(node, 'value', channels) == 1)
        return { tonumber(channels[0]), tonumber(channels[1]), tonumber(channels[2]), tonumber(channels[3]) }
    end
    local value = tonumber(native.BK_get_num(node, kind == 'fraction' and 'factor' or 'value'))
    if kind == 'boolean' then return value ~= 0 end
    return value
end

local event_names = {
    [1] = 'changed', [2] = 'activated', [4] = 'renamed', [5] = 'activated', [6] = 'toggled',
    [7] = 'browse_requested', [8] = 'pressed', [9] = 'released', [10] = 'double_clicked',
    [11] = 'moved', [12] = 'entered', [13] = 'left', [14] = 'key_pressed', [15] = 'wheel',
    [16] = 'submitted', [17] = 'view_changed', [18] = 'scrolled', [19] = 'configured',
    [20] = 'key_released',
}
local notifications = {}
for _, name in pairs(event_names) do notifications[name] = true end

-- Copy native payloads now: pointer/key metadata often lives on a C stack.
local function snapshot(record, kind, reference, first, second)
    local name = event_names[kind]
    if not name then return end
    if name == 'changed' then
        if record.change_snapshot then return name, record.change_snapshot() end
        if record.descriptor.value_type then return name, current(record) end
    end
    if name == 'configured' then
        local rectangle = ffi.new('int[4]')
        record.native.BK_node_rect(record.node, rectangle)
        return name, { x = tonumber(rectangle[0]), y = tonumber(rectangle[1]),
            width = tonumber(rectangle[2]), height = tonumber(rectangle[3]) }
    end
    local payload = { first = first, second = second }
    if (kind >= 8 and kind <= 15) or kind == 20 then
        payload.detail = reference ~= nil and ffi.string(ffi.cast('const char *', reference)) or ''
    end
    return name, payload
end

return { catalog = catalog, prepare = prepare, apply = apply, current = current,
    snapshot = snapshot, notifications = notifications }
