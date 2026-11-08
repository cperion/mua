-- Specialized editing vocabularies. Arrays cross C only after their complete shape is checked.
local ffi = require 'ffi'
local Check = require 'bui.ui.check'
if jit then jit.off(true, true) end

local function color_values(channels)
    return { tonumber(channels[0]), tonumber(channels[1]), tonumber(channels[2]), tonumber(channels[3]) }
end

local function ramp(record)
    local native, node, owner, capabilities = record.native, record.node, record.owner, record.capabilities
    capabilities.stops = function()
        owner:check('ramp stops')
        local stops, position, color = {}, ffi.new('float[1]'), ffi.new('float[4]')
        for index = 0, native.BK_ramp_count(node) - 1 do
            native.BK_ramp_get(node, index, position, color)
            stops[#stops + 1] = { position = tonumber(position[0]), color = color_values(color) }
        end
        return stops
    end
    capabilities.set_stops = function(stops)
        owner:mutate('set ramp stops'); Check.array(stops, 'ramp stops')
        assert(#stops >= 2 and #stops <= 32, 'a ramp needs 2..32 stops')
        local positions, colors = ffi.new('float[?]', #stops), ffi.new('float[?][4]', #stops)
        for index, stop in ipairs(stops) do
            Check.keys(stop, { position = true, color = true }, 'ramp stop')
            positions[index - 1] = Check.number(stop.position, 'stop position', 0, 1)
            local color = Check.color(stop.color, 'stop color')
            for channel = 0, 3 do colors[index - 1][channel] = color[channel] end
        end
        owner:mutate('publish ramp stops')
        native.BK_ramp_set(node, positions, ffi.cast('const float (*)[4]', colors), #stops)
    end
    capabilities.sample = function(position)
        owner:check('sample ramp')
        local color = ffi.new('float[4]')
        native.BK_ramp_evaluate(node, Check.number(position, 'sample position', 0, 1), color)
        return color_values(color)
    end
    capabilities.active_stop = function() owner:check('active stop'); return native.BK_ramp_active(node) + 1 end
    capabilities.select_stop = function(index)
        owner:mutate('select stop'); Check.integer(index, 'stop index', 1, native.BK_ramp_count(node))
        native.BK_set_num(node, 'active', index - 1)
    end
    capabilities.set_active_color = function(color)
        owner:mutate('set active color')
        local channels = Check.color(color, 'color')
        owner:mutate('publish active color'); native.BK_ramp_set_active_color(node, channels)
    end
    record.change_snapshot = capabilities.stops
end

local function curve(record)
    local native, node, owner, capabilities = record.native, record.node, record.owner, record.capabilities
    capabilities.points = function(channel)
        owner:check('curve points'); Check.integer(channel, 'channel', 0, 3)
        local points, coordinate = {}, ffi.new('float[2]')
        for index = 0, native.BK_curve_count(node, channel) - 1 do
            native.BK_curve_get(node, channel, index, coordinate)
            points[#points + 1] = { tonumber(coordinate[0]), tonumber(coordinate[1]) }
        end
        return points
    end
    capabilities.set_points = function(channel, points)
        owner:mutate('set curve points'); Check.integer(channel, 'channel', 0, 3)
        Check.array(points, 'curve points')
        assert(#points >= 2 and #points <= 64, 'a curve needs 2..64 points')
        local coordinates = ffi.new('float[?][2]', #points)
        for index, point in ipairs(points) do
            Check.array(point, 'curve point'); assert(#point == 2, 'a curve point needs x,y')
            coordinates[index - 1][0] = Check.number(point[1], 'curve x', -1e7, 1e7)
            coordinates[index - 1][1] = Check.number(point[2], 'curve y', -1e7, 1e7)
        end
        owner:mutate('publish curve points')
        native.BK_curve_set(node, channel, ffi.cast('const float (*)[2]', coordinates), #points)
    end
    capabilities.sample = function(channel, position)
        owner:check('sample curve'); Check.integer(channel, 'channel', 0, 3)
        return tonumber(native.BK_curve_evaluate(node, channel, Check.number(position, 'curve position', -1e7, 1e7)))
    end
    record.change_snapshot = function()
        local channel = tonumber(native.BK_get_num(node, 'channel'))
        return { channel = channel, points = capabilities.points(channel) }
    end
end

local function textarea(record)
    local native, node, owner, capabilities = record.native, record.node, record.owner, record.capabilities
    local function offset(position)
        local text = capabilities.current()
        Check.integer(position, 'UTF-8 byte offset', 0, #text)
        local byte = text:byte(position + 1)
        assert(not byte or byte < 128 or byte >= 192, 'offset splits a UTF-8 sequence')
        return position
    end
    local function range(first, last)
        offset(first); offset(last)
        assert(first <= last, 'byte range is reversed')
    end
    capabilities.insert = function(position, text)
        owner:mutate('insert text')
        native.BK_textarea_insert(node, offset(position), Check.string(text, 'inserted text'))
        record.application:check_error()
    end
    capabilities.delete = function(first, last)
        owner:mutate('delete text'); range(first, last)
        native.BK_textarea_delete(node, first, last); record.application:check_error()
    end
    capabilities.caret = function() owner:check('caret'); return tonumber(native.BK_textarea_caret(node)) end
    capabilities.move_caret = function(position)
        owner:mutate('move caret'); native.BK_textarea_set_caret(node, offset(position))
    end
    capabilities.select = function(first, last)
        owner:mutate('select text'); range(first, last)
        native.BK_textarea_set_selection(node, first, last)
    end
    capabilities.selection = function()
        owner:check('text selection')
        local first, last = ffi.new('int[1]'), ffi.new('int[1]')
        local outcomes = record.application.protocols.selection
        if native.BK_textarea_selection(node, first, last) == 0 then return outcomes.empty() end
        return outcomes.selected({ start = tonumber(first[0]), stop = tonumber(last[0]) })
    end
    capabilities.index_at = function(x, y)
        owner:check('text index')
        return tonumber(native.BK_textarea_index_at(node, Check.integer(x, 'x'), Check.integer(y, 'y')))
    end
    capabilities.reveal = function(position)
        owner:mutate('reveal text'); native.BK_textarea_see(node, offset(position))
    end
    capabilities.set_spans = function(spans)
        owner:mutate('set text spans'); Check.array(spans, 'text spans')
        local native_spans = ffi.new('BKTextSpan[?]', math.max(1, #spans))
        for index, span in ipairs(spans) do
            Check.keys(span, { start = true, stop = true, foreground = true, background = true }, 'text span')
            range(span.start, span.stop)
            local destination = native_spans[index - 1]
            destination.start, destination['end'] = span.start, span.stop
            if span.foreground then
                local color = Check.color(span.foreground, 'span foreground')
                destination.has_fg = 1
                for channel = 0, 3 do destination.fg[channel] = color[channel] end
            end
            if span.background then
                local color = Check.color(span.background, 'span background')
                destination.has_bg = 1
                for channel = 0, 3 do destination.bg[channel] = color[channel] end
            end
        end
        owner:mutate('publish text spans')
        native.BK_textarea_set_spans(node, native_spans, #spans)
    end
end

local function histogram(record)
    record.capabilities.set_bins = function(channels)
        record.owner:mutate('set histogram bins'); Check.array(channels, 'histogram channels')
        assert(#channels >= 1 and #channels <= 3, 'histogram needs 1..3 channels')
        Check.array(channels[1], 'histogram channel')
        local count = #channels[1]
        assert(count >= 2 and count <= 65536, 'histogram needs 2..65536 bins per channel')
        local bins = ffi.new('float[?]', count * #channels)
        for channel, values in ipairs(channels) do
            Check.array(values, 'histogram channel'); assert(#values == count, 'unequal histogram channels')
            for index, value in ipairs(values) do
                bins[(index - 1) * #channels + channel - 1] = Check.number(value, 'histogram bin', 0, 1)
            end
        end
        record.owner:mutate('publish histogram bins')
        record.native.BK_histogram_set(record.node, bins, count, #channels)
    end
end

local function gridview(record)
    record.capabilities.set_colors = function(colors)
        record.owner:mutate('set grid colors'); Check.array(colors, 'grid colors')
        local native_colors = ffi.new('float[?][4]', math.max(1, #colors))
        for index, channels in ipairs(colors) do
            local color = Check.color(channels, 'grid color')
            for channel = 0, 3 do native_colors[index - 1][channel] = color[channel] end
        end
        record.owner:mutate('publish grid colors')
        record.native.BK_gridview_set_colors(record.node, ffi.cast('const float (*)[4]', native_colors), #colors)
    end
end

local extensions = { ramp = ramp, curve = curve, textarea = textarea, histogram = histogram, gridview = gridview }
-- Extend only the native kind whose storage layout the specialized API requires.
local function extend(record)
    local install = extensions[record.kind]
    if install then install(record) end
end
return { extend = extend }
