-- Inspect constructed values, not source declarations. Never invoke user callbacks.
local runtime = require 'mua.runtime'
local M = {}

local inspection = require 'mua.runtime.inspection'
local text, key_text, location = inspection.text, inspection.key_text, inspection.location

-- roots is a packed return list, so nil returns do not hide later values.
function M.render(roots, options)
    options = options or {}
    local limit = options.max_entries or 10000
    local depth_limit = options.max_depth or 32
    local nodes, queue, entries = {}, {}, 0
    local function node(value)
        local kind = type(value)
        if kind ~= 'table' and kind ~= 'function' and kind ~= 'userdata' and kind ~= 'cdata' then return end
        if nodes[value] then return nodes[value] end
        local label = runtime.label_of(value)
        local n = { value = value, kind = kind, label = type(label) == 'string' and text(label) or nil,
            edges = {}, parents = {} }
        nodes[value] = n
        queue[#queue + 1] = n
        return n
    end
    local top = {}
    for i = 1, roots.n or #roots do
        local n = node(roots[i])
        if n then top[#top + 1] = { key = 'return ' .. i, node = n } end
    end
    local cursor = 1
    while queue[cursor] do
        local n = queue[cursor]
        cursor = cursor + 1
        if n.kind == 'table' then
            local fields = {}
            for key, value in next, n.value do
                entries = entries + 1
                if entries > limit then error('outline: entry limit exceeded (' .. limit .. ')', 0) end
                fields[#fields + 1] = { key = key, value = value }
            end
            table.sort(fields, function(a, b)
                local ak, bk = type(a.key), type(b.key)
                if ak ~= bk then return ak < bk end
                if ak == 'number' or ak == 'string' then return a.key < b.key end
                return key_text(a.key) < key_text(b.key)
            end)
            for _, field in ipairs(fields) do
                local child = node(field.value)
                if child then
                    n.edges[#n.edges + 1] = { key = key_text(field.key), node = child }
                    child.parents[#child.parents + 1] = n
                end
            end
        end
    end
    -- Mark ancestors of labels, including paths through unlabeled cycles.
    local marked = {}
    local labeled, callable = 0, 0
    for _, n in ipairs(queue) do
        if n.label ~= nil then
            n.visible = true
            marked[#marked + 1] = n
            labeled = labeled + 1
            if n.kind == 'function' then callable = callable + 1 end
        end
    end
    cursor = 1
    while marked[cursor] do
        for _, parent in ipairs(marked[cursor].parents) do
            if not parent.visible then parent.visible = true; marked[#marked + 1] = parent end
        end
        cursor = cursor + 1
    end
    if labeled == 0 then return 'No labeled values returned.\n' end
    local out, seen = {}, {}
    local function draw(edge, prefix, last, depth, root)
        local n = edge.node
        local lead = root and '' or prefix .. (last and '└─ ' or '├─ ')
        local heading = root and (n.label or edge.key)
            or edge.key .. (n.label ~= nil and ('  ' .. n.label) or '')
        if seen[n] then
            out[#out + 1] = lead .. heading .. '  ↩ #' .. seen[n]
            return
        end
        seen[n] = #out + 1
        local where = n.kind == 'function' and options.locations ~= false and location(n.value)
        out[#out + 1] = lead .. heading .. (n.kind == 'function' and '  ƒ' or '')
            .. '  #' .. seen[n] .. (where and ('  ' .. where) or '')
        local children = {}
        for _, child in ipairs(n.edges) do
            if child.node.visible then children[#children + 1] = child end
        end
        local continuation = root and '' or prefix .. (last and '   ' or '│  ')
        if depth >= depth_limit and #children > 0 then
            out[#out + 1] = continuation .. '└─ … depth limit'
        else
            for i, child in ipairs(children) do draw(child, continuation, i == #children, depth + 1, false) end
        end
    end
    for _, edge in ipairs(top) do if edge.node.visible then draw(edge, '', true, 0, true) end end
    out[#out + 1] = ''
    out[#out + 1] = ('%d labeled values · %d callable'):format(labeled, callable)
    return table.concat(out, '\n') .. '\n'
end
return M
