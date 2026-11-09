-- Reading constructed values for people: the outline (mua/outline.lua) and `inspect`/`trace`.
-- Nothing here invokes user code: tables are read raw, without `__index`, `__pairs` or
-- `__tostring`.
local M = {}

-- text with its control characters escaped
function M.text(s)
    return (s:gsub('[%c]', function(c)
        return ({ ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' })[c]
            or ('\\x%02x'):format(c:byte())
    end))
end

function M.key_text(key)
    local kind = type(key)
    if kind == 'string' then return M.text(key) end
    if kind == 'number' or kind == 'boolean' then return tostring(key) end
    return '<' .. kind .. ' key>'
end

-- numbers before strings, each in order; other keys after, in an unspecified order
function M.sorted_keys(value)
    local keys = {}
    for key in next, value do keys[#keys + 1] = key end
    local rank = function(key) return type(key) == 'number' and 1 or type(key) == 'string' and 2 or 3 end
    table.sort(keys, function(a, b)
        local left, right = rank(a), rank(b)
        if left ~= right then return left < right end
        if left == 3 then return false end
        return a < b
    end)
    return keys
end

-- Debug metadata identifies the function definition, not its labeling/call site.
-- Missing/stripped debug data and C functions simply have no source location.
function M.location(value)
    if not debug or not debug.getinfo then return end
    local info = debug.getinfo(value, 'S')
    if not info or info.what == 'C' or not info.linedefined or info.linedefined < 1 then return end
    local source = info.source or ''
    if source:sub(1, 1) == '@' or source:sub(1, 1) == '=' then
        source = source:sub(2)
    else
        source = info.short_src or '(chunk)'
    end
    return M.text(source) .. ':' .. info.linedefined
end

-- What a value is and what it holds. A labeled value is its label: whoever labeled it summed
-- it up. An unlabeled table is opened, all of it, so the depth is decided by how well the code
-- is labeled. `options.open = n` drills through n levels of labeled values deliberately: such a
-- value shows its label beside its contents. A table met twice is numbered and referred to (`↩ #2`); a short table stays on one
-- line, a long one is a tree. `label_of` and `describe` come from the runtime.
function M.inspect(value, label_of, describe, options)
    options = options or {}
    local width = options.width or 80
    local entry_limit = options.max_entries or 500
    local depth_limit = options.max_depth or 32
    local open = options.open or 0
    -- tables reached more than once, by the walk that will print them
    local seen, shared = {}, {}
    -- `opened`: how many labeled values deep this part lies
    local function count(item, root, opened)
        if type(item) ~= 'table' then return end
        local labeled = not root and label_of(item) ~= nil
        if labeled and opened >= open then return end
        if seen[item] then shared[item] = true; return end
        seen[item] = true
        local inner = labeled and opened + 1 or opened
        for key, child in next, item do count(child, false, inner) end
    end
    count(value, true, 0)
    local numbers, next_number, entries = {}, 0, 0
    local render
    local function scalar(item)
        local kind = type(item)
        if kind == 'string' then return ('%q'):format(item):gsub('\\\n', '\\n') end
        if kind == 'number' or kind == 'boolean' or item == nil then return tostring(item) end
        if kind == 'function' then
            local where = M.location(item)
            return 'a function' .. (where and (' at ' .. where) or '')
        end
        return describe(item)
    end
    render = function(item, indent, depth, root, opened)
        local own = label_of(item)
        local labeled = own ~= nil and not root
        if labeled and (opened >= open or type(item) ~= 'table') then return '«' .. M.text(own) .. '»' end
        if type(item) ~= 'table' then return scalar(item) end
        local inner = labeled and opened + 1 or opened
        if numbers[item] then return '↩ #' .. numbers[item] end
        local head = describe(item)
        if labeled then head = '«' .. M.text(own) .. '» ' .. head end
        if shared[item] then
            next_number = next_number + 1
            numbers[item] = next_number
            head = head .. ' #' .. next_number
        end
        if depth >= depth_limit then return head .. ' { … }' end
        local keys = M.sorted_keys(item)
        if #keys == 0 then return head .. ' {}' end
        local parts = {}
        for _, key in ipairs(keys) do
            entries = entries + 1
            if entries > entry_limit then
                parts[#parts + 1] = ('… %d more'):format(#keys - #parts)
                break
            end
            local name = type(key) == 'string' and key:match('^[%a_][%w_]*$') and key or ('[' .. render(key, indent .. '    ', depth + 1, false, inner) .. ']')
            parts[#parts + 1] = name .. ' = ' .. render(rawget(item, key), indent .. '    ', depth + 1, false, inner)
        end
        local line = head .. ' { ' .. table.concat(parts, ', ') .. ' }'
        if #indent + #line <= width and not line:find('\n', 1, true) then return line end
        return head .. ' {\n' .. indent .. '    ' .. table.concat(parts, ',\n' .. indent .. '    ') .. ',\n' .. indent .. '}'
    end
    local body = render(value, '', 0, true, 0)
    local own = label_of(value)
    if own ~= nil then return M.text(own) .. ': ' .. body end
    return body
end

return M
