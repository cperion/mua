-- mua.lint: a Mua source read as its declarations and their comments.
--
-- Three rules, and one view that shows whether they were followed. A file opens with a comment
-- saying what the file is for — a rule of dashes is a divider, not a description. A declaration at
-- the file's own level — the left margin, which the formatter keeps — says what it is for, in a
-- comment above it or beside it. That comment does not open by naming what the declaration already
-- names: the name is in front of the reader, so the words are spent on its purpose instead. Printing only the
-- declarations and their comments then shows the file as the comment poem it has to read as; when
-- a comment is vague or misaimed, that is where it shows.
--
-- Why the left margin and not scope: `fmt` writes one level to `indent_width`, so a declaration's
-- indentation already says whether it is the file's or a block's. Locals inside a block are
-- explained by the block that holds them, and appear in the outline only when someone commented
-- them anyway.

local lex = require 'mua.lex'
local parse = require 'mua.parse'

local M = {}

-- the layout the outline follows: the formatter's defaults, so `mua lint --outline` and `mua fmt`
-- agree about where a level starts
M.column_width = 100
M.indent_width = 4

-- the source by line
local function lines_of(source)
    local lines = {}
    for line in (source .. '\n'):gmatch('([^\n]*)\n') do lines[#lines + 1] = line end
    return lines
end

-- the comments by line: the text on a line, which lines hold only comments, and how many
-- long-bracket comments there are (they hold data and output, so the outline counts them only)
local function comments(source, filename)
    local text, only, hidden = {}, {}, 0
    for _, token in ipairs(lex.scan(source, filename)) do
        if token.t == 'comment' then
            local _, breaks = token.v:gsub('\n', '')
            if breaks > 0 then
                hidden = hidden + 1
            else
                for offset = 0, breaks do
                    local at = token.line + offset
                    only[at] = true
                    text[at] = text[at] and (text[at] .. ' ' .. token.v) or token.v
                end
            end
        end
    end
    return text, only, hidden
end

-- the comment's words: its `--` opener goes, and `--` written inside the prose stays
local function strip(raw)
    return ((raw or ''):gsub('^%s*%-%-+%s?', ''):gsub('%s+$', ''))
end

-- the column a line's text starts at
local function column_of(lines, line)
    local lead = (lines[line] or ''):match('^[ \t]*')
    return #lead
end

-- the declarations in source order, as the line, the column, and the names they declare
local function declarations(source, filename)
    local found = {}
    local function walk(node)
        if type(node) ~= 'table' then return end
        if node.k == 'local' then
            local names = {}
            for _, name in ipairs(node.names) do names[#names + 1] = name.name end
            found[#found + 1] = { line = node.line, names = names }
        elseif node.k == 'localfunction' or node.k == 'open' then
            found[#found + 1] = { line = node.line, names = { node.name } }
        end
        for key, value in pairs(node) do
            if key ~= 'k' and type(value) == 'table' then
                if value.k then walk(value)
                elseif #value > 0 then for _, item in ipairs(value) do walk(item) end
                else walk(value) end
            end
        end
    end
    walk(parse.parse(source, filename))
    table.sort(found, function(a, b) return a.line < b.line end)
    return found
end

-- the comment a declaration is documented by: the lines above it that hold only comments, or a
-- comment beside it
local function documentation(text, only, line)
    local parts = {}
    if text[line] then parts[1] = strip(text[line]) end
    local at = line - 1
    while only[at] do
        local words = strip(text[at])
        table.insert(parts, 1, words)
        at = at - 1
    end
    return table.concat(parts, ' ')
end

-- the file's own opening: a comment before any code, holding words and not only a rule of dashes
local function opening(text, only, lines)
    local at = 1
    while at <= #lines and lines[at]:match('^%s*$') do at = at + 1 end
    local start = at
    if not only[at] then return start, 'code' end
    local prose = false
    while only[at] do
        local words = strip(text[at])
        if words ~= '' and not words:find('^[-=]+$') then prose = true end
        at = at + 1
    end
    if prose then return start end
    return start, 'rule'
end

-- what the rules say about a source: `file` is a file that does not open by saying what it is for,
-- `undocumented` is a declaration at the file's level with no comment, `repeats` is one whose
-- comment opens by naming it
function M.findings(source, filename)
    filename = filename or '=(lint)'
    local lines = lines_of(source)
    local text, only = comments(source, filename)
    local reports = {}
    local opening_line, opening_problem = opening(text, only, lines)
    if opening_problem then
        reports[#reports + 1] = { line = math.min(opening_line, #lines), kind = 'file',
            detail = opening_problem, names = {} }
    end
    for _, declaration in ipairs(declarations(source, filename)) do
        if column_of(lines, declaration.line) == 0 then
            local block = documentation(text, only, declaration.line)
            if block == '' then
                reports[#reports + 1] = { line = declaration.line, kind = 'undocumented',
                    names = declaration.names }
            else
                local opening = block:match('^`?([%w_]+)`?')
                for _, name in ipairs(declaration.names) do
                    if opening == name then
                        reports[#reports + 1] = { line = declaration.line, kind = 'repeats', names = { name } }
                        break
                    end
                end
            end
        end
    end
    return reports
end

-- a paragraph wrapped to `columns`, words kept whole
local function wrap(words, columns)
    local out, line = {}, ''
    for word in words:gmatch('%S+') do
        if line == '' then line = word
        elseif #line + 1 + #word <= columns then line = line .. ' ' .. word
        else
            out[#out + 1] = line
            line = word
        end
    end
    if line ~= '' then out[#out + 1] = line end
    return out
end

-- a declaration written over more than its first line keeps saying so
local function continues(text)
    local depth = 0
    for _ in text:gmatch('[%({%[]') do depth = depth + 1 end
    for _ in text:gmatch('[%)}%]]') do depth = depth - 1 end
    return depth > 0
end

local function declaration_line(lines, line)
    local text = (lines[line] or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local room = M.column_width - M.indent_width - column_of(lines, line)
    if #text > room then return text:sub(1, room - 1) .. '…' end
    return continues(text) and (text .. ' …') or text
end

-- one item per thing the reader needs: a comment block and the declaration it describes, a
-- heading, or the file's own opening words
local function items_of(lines, text, only, declared)
    local items, at = {}, 1
    while at <= #lines do
        if only[at] then
            local paragraphs, block = { {} }, {}
            while only[at] do
                local raw = strip(text[at])
                if raw:find('^[-=]+$') then
                    at = at + 1
                elseif raw == '' then
                    paragraphs[#paragraphs + 1] = {}
                    at = at + 1
                else
                    block[#block + 1] = raw
                    local current = paragraphs[#paragraphs]
                    current[#current + 1] = raw
                    at = at + 1
                end
            end
            local after = at
            while after <= #lines and lines[after]:match('^%s*$') do after = after + 1 end
            local kept = {}
            for _, words in ipairs(paragraphs) do
                if #words > 0 then kept[#kept + 1] = table.concat(words, ' ') end
            end
            if declared[after] then
                items[#items + 1] = { kind = 'entry', line = after, paragraphs = kept }
                at = after + 1
            elseif #kept == 1 and #kept[1] <= 64 then
                items[#items + 1] = { kind = 'heading', paragraphs = kept }
            else
                items[#items + 1] = { kind = 'prose', paragraphs = kept }
            end
        else
            if declared[at] and column_of(lines, at) == 0 then
                items[#items + 1] = { kind = 'entry', line = at, paragraphs = {} }
            end
            at = at + 1
        end
    end
    return items
end

-- the source as its declarations and their comments: numbered, the declaration first, what it is
-- for wrapped underneath it
function M.outline(source, filename)
    filename = filename or '=(lint)'
    local lines = lines_of(source)
    local text, only, hidden = comments(source, filename)
    local declared = {}
    for _, declaration in ipairs(declarations(source, filename)) do declared[declaration.line] = true end
    local items = items_of(lines, text, only, declared)

    local gutter, shown = 4, 0
    for _, item in ipairs(items) do
        if item.kind == 'entry' then
            shown = shown + 1
            gutter = math.max(gutter, #tostring(item.line))
        end
    end

    local out = { ('%s — %d declaration%s%s'):format(filename, shown, shown == 1 and '' or 's',
        hidden > 0 and (', %d long comment%s not shown'):format(hidden, hidden == 1 and '' or 's') or '') }
    local bare_before = false
    for _, item in ipairs(items) do
        local bare = item.kind == 'entry' and #item.paragraphs == 0
        if not (bare and bare_before) then out[#out + 1] = '' end
        bare_before = bare
        if item.kind == 'heading' then
            out[#out + 1] = item.paragraphs[1]
            out[#out + 1] = ('-'):rep(math.min(#item.paragraphs[1], M.column_width))
        elseif item.kind == 'prose' then
            for index, paragraph in ipairs(item.paragraphs) do
                if index > 1 then out[#out + 1] = '' end
                for _, line in ipairs(wrap(paragraph, M.column_width)) do out[#out + 1] = line end
            end
        else
            local number = tostring(item.line)
            local margin = (' '):rep(gutter - #number) .. number .. '  '
                .. (' '):rep(column_of(lines, item.line))
            out[#out + 1] = margin .. declaration_line(lines, item.line)
            local under = (' '):rep(#margin + M.indent_width)
            for index, paragraph in ipairs(item.paragraphs) do
                if index > 1 then out[#out + 1] = '' end
                for _, line in ipairs(wrap(paragraph, M.column_width - #under)) do
                    out[#out + 1] = under .. line
                end
            end
        end
    end
    return table.concat(out, '\n') .. '\n'
end

return M
