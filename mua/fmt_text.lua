-- The formatter's text passes (mua.fmt): the trailing colon and `with` blocks written as the
-- do-forms and braces they mean (`expand`, driven by Mua's parser), and printed back as colons
-- and `with` blocks (`colonize`, `withize`, `foldends`, `inline_tables`). The trailing colon: a
-- colon that ends a line opens an untyped block lambda that opens the home:
--
--     with_buffer n:               with_buffer n do(..)
--
-- Parameters are written in a do lambda (`words:each do(key, value) … end`), so only the bare
-- colon is written back. The colon is a block opener only where Mua has no annotation colon:
-- not after a parameter list (`do(x: U32): U32`, `function f(x): T`), not in the names of a
-- `local`, not inside brackets, not in a `::label::`, and not directly followed by a name
-- (`xs:each`, a method call). Only the token list changes; a comment after the colon is kept
-- so line numbers stay put.

local M = {}

local OPERAND = { iden = true, string = true, number = true, [')'] = true, [']'] = true, ['}'] = true }
local LITERAL = { ['true'] = true, ['false'] = true, ['nil'] = true }

local function skip_back(tokens, i)
    i = i - 1
    while i >= 1 and (tokens[i][1] == 'space' or tokens[i][1] == 'comment') do i = i - 1 end
    return i
end

local function is_do(tk) return (tk[1] == 'keyword' or tk[1] == 'iden') and tk[2] == 'do' end

-- does the `(` at index i open a function's parameter list: `do(`, `function f(`?
local function parameter_list(tokens, i)
    local j = skip_back(tokens, i)
    if j < 1 then return false end
    if is_do(tokens[j]) then return true end
    if tokens[j][1] ~= 'iden' and tokens[j][2] ~= '__typed_function' then return false end
    while j >= 1 and tokens[j][1] == 'iden' do
        j = skip_back(tokens, j)
        if j >= 1 and (tokens[j][1] == '.' or tokens[j][1] == ':') then
            j = skip_back(tokens, j)
        else
            break
        end
    end
    return j >= 1 and tokens[j][1] == 'keyword' and tokens[j][2] == 'function'
end

local MARK = '--[=[mua:with]=]'
M.MARK = MARK
-- a `define` block is also marked, so it is written back as one (a table, never a contextual `with`)
local DEFINE = '--[=[mua:define]=]'
M.DEFINE = DEFINE

-- `do ( ... ) :` a typed lambda: a word's body, which `endall` never closes
local function typed_lambda(tokens, i)
    local n, j, depth = #tokens, i + 1, 0
    while j <= n and (tokens[j][1] == 'space' or tokens[j][1] == 'comment') do j = j + 1 end
    if not tokens[j] or tokens[j][1] ~= '(' then return false end
    repeat
        local t = tokens[j][1]
        if t == '(' then depth = depth + 1 elseif t == ')' then depth = depth - 1 end
        j = j + 1
    until depth == 0 or j > n
    while j <= n and (tokens[j][1] == 'space' or tokens[j][1] == 'comment') do j = j + 1 end
    return tokens[j] ~= nil and tokens[j][1] == ':'
end

-- `do ( ... )` at index i followed by `=` (an expression lambda has no `end`),
-- also with a result type: `do(x: U32): U32 = ...`
local function expression_lambda(tokens, i)
    local n, j, depth = #tokens, i + 1, 0
    while j <= n and (tokens[j][1] == 'space' or tokens[j][1] == 'comment') do j = j + 1 end
    if not tokens[j] or tokens[j][1] ~= '(' then return false end
    repeat
        local t = tokens[j][1]
        if t == '(' then depth = depth + 1 elseif t == ')' then depth = depth - 1 end
        j = j + 1
    until depth == 0 or j > n
    while j <= n and (tokens[j][1] == 'space' or tokens[j][1] == 'comment') do j = j + 1 end
    if tokens[j] and tokens[j][1] == '=' then return true end
    if tokens[j] and tokens[j][1] == ':' then
        while j <= n do                                 -- the type, up to `=` or the end of the line
            local tk = tokens[j]
            if tk[1] == '=' then return true end
            if tk[1] == 'space' and tk[2]:find '\n' then return false end
            j = j + 1
        end
    end
    return false
end

local function skip_forward(tokens, i)
    i = i + 1
    while tokens[i] and (tokens[i][1] == 'space' or tokens[i][1] == 'comment') do i = i + 1 end
    return tokens[i] and i
end

local function significant_after(tokens, i)
    i = i + 1
    while tokens[i] and (tokens[i][1] == 'space' or tokens[i][1] == 'comment') do i = i + 1 end
    return i
end

-- does the `with` at i stand where an expression starts, and begin entries (not a variable)?
local EXPRESSION_START = { ['='] = true, ['('] = true, [','] = true, ['{'] = true, [';'] = true }
local function contextual_with(tokens, i)
    local p = skip_back(tokens, i)
    if p < 1 then return false end
    local before = tokens[p]
    if not (EXPRESSION_START[before[1]] or (before[1] == 'keyword' and before[2] == 'return')) then return false end
    local nx = tokens[significant_after(tokens, i)]
    if not nx then return false end
    if nx[1] == '.' or nx[1] == '[' or nx[1] == 'iden' or nx[1] == 'string' or nx[1] == 'number' then
        return not (tokens[i + 1] and (tokens[i + 1][1] == '.' or tokens[i + 1][1] == '('))
    end
    return false
end


-- Source text tools (the formatter) work on do-forms. `expand` writes the trailing
-- colons of a source as the `do(..)` they mean; `colonize` writes untyped
-- trailing `do(names)` blocks back as colons. Both go through the lexer and
-- leave everything else byte for byte.
local lex = require 'mua.lex'

-- The text passes below read a token list in an older shape: { kind, text, line }, a name
-- as `iden`, `..` and `...` as separate dots, `::` as two colons. Written from Mua's
-- lexer, which the parser uses too, so both read the same text the same way.
local lexer = {}
function lexer.scan_raw_tokenlist(source)
    local out = {}
    for _, tk in ipairs(lex.scan(source, '?')) do
        local t, v = tk.t, tk.v
        if t == 'name' or (t == 'keyword' and v == 'goto') then
            out[#out + 1] = { 'iden', v, tk.line }
        elseif v == '..' or v == '...' or v == '::' then
            local c = v:sub(1, 1)
            for _ = 1, #v do out[#out + 1] = { c, c, tk.line } end
        elseif t == 'eof' then
            -- the old list ends at the last token
        elseif t == 'directive' or t == 'shebang' then
            out[#out + 1] = { 'comment', v, tk.line }
        else
            out[#out + 1] = { t == 'keyword' and 'keyword' or t, v, tk.line }
        end
    end
    return out
end

local function text_of(tokens)
    local parts = {}
    for i, tk in ipairs(tokens) do parts[i] = tk[2] end
    return table.concat(parts)
end

-- Source text tools (the formatter) work on do-forms: `expand` below writes a source's colon blocks
-- and `with` blocks as the `do(..)` and braces they mean.
local try_expand

-- The same expansion, driven by Mua's parser (no second set of rules for where a colon opens
-- a block or a `with` begins): the parser says where each colon block, `with` block and
-- `endall` is, and the edits are made on Mua's own token list. `mark` writes a comment after
-- each brace that stood for a `with`, `full` writes `endall` out as the closers it stands for.
local parse_mod = require 'mua.parse'
-- the parse host of the language being formatted (its statement and prefix forms), set by
-- the formatter for the call it makes: a function from a file name to a Mua parse host
local parse_host
function M.use_host(f) local saved = parse_host; parse_host = f; return saved end
local WITH_START = { ['='] = true, ['('] = true, [','] = true, ['{'] = true, [';'] = true }

function M.expand(source, mark, full, filename)
    filename = filename or '?'
    local toks = lex.scan(source, filename)
    local r = parse_mod.reader(toks, filename)
    local p = parse_mod.parser(r, (parse_host and parse_host(filename)))
    local last = 0
    local next_token = r.next
    function r:next() local tk = next_token(self); last = tk.index; return tk end
    local replace, drop, after = {}, {}, {}          -- by token index: new text; dropped; text added after
    local function sig_before(index)                 -- the significant token before token `index`
        for k = 1, #r.toks do if r.toks[k].index == index then return r.toks[k - 1] end end
    end
    local function closer_of(braced) return braced and '}' or 'end' end
    local frames = {}                                  -- the `with` blocks being read
    local function open_with(wtk, contextual)
        frames[#frames + 1] = { entries = {}, contextual = contextual }
        -- a headless `with` keeps its word before the brace (`with {`): it is not a table in braces
        -- (a type may fill it in), so no later pass may take it for one or give it a head
        replace[wtk.index] = (contextual and wtk.v ~= 'define') and 'with {' or '{'
        after[wtk.index] = mark and (M.MARK .. (wtk.v == 'define' and M.DEFINE or '')) or nil
    end
    local function close_with(frame)
        local closer = toks[last]
        if closer.v == 'end' then replace[last] = '}' end
        -- entries are separated by commas, which the layout wants written
        for i = 1, #frame.entries - 1 do
            local e = frame.entries[i]
            local j = e.last + 1
            while toks[j] and (toks[j].t == 'space' or toks[j].t == 'comment') do j = j + 1 end
            if not (toks[j] and (toks[j].v == ',' or toks[j].v == ';')) then
                after[e.last] = (after[e.last] or '') .. ','
            end
        end
    end
    -- `with` blocks of tables and calls
    local with_entries = p.with_entries
    function p:with_entries(wtk)
        local prev = sig_before(wtk.index)
        local contextual = prev and (WITH_START[prev.t] or prev.kw == 'return') or false
        open_with(wtk, contextual)
        local frame = frames[#frames]
        local result = with_entries(self, wtk)
        close_with(frame)
        frames[#frames] = nil
        return result
    end
    local entry = p.entry
    function p:entry()
        local frame = self.in_with and frames[#frames]
        local first = r:peek(1).index
        local result = entry(self)
        if frame then frame.entries[#frame.entries + 1] = { first = first, last = last } end
        return result
    end
    -- `struct … end`, `oneof … end`, `ffistruct … end`: the fields are read by the parser's own loop
    local struct = p.struct
    function p:struct(hint)
        local at = r:peek(2)
        if at.t == 'name' and r:peek(3).t == ':' then
            local wtk = r:peek(1)
            open_with(wtk, false)
            replace[wtk.index] = wtk.v .. ' {'              -- the word stays, the block is braced
            local frame = frames[#frames]
            local result = struct(self, hint)
            -- the fields start at a name followed by `:`, outside any brackets
            local depth, starts = 0, {}
            for k = wtk.index + 1, last do
                local t = toks[k]
                if t.t == '(' or t.t == '{' or t.t == '[' then depth = depth + 1
                elseif t.t == ')' or t.t == '}' or t.t == ']' then depth = depth - 1
                elseif depth == 0 and t.t == 'name' then
                    local j = k + 1
                    while toks[j] and (toks[j].t == 'space' or toks[j].t == 'comment') do j = j + 1 end
                    if toks[j] and toks[j].t == ':' then starts[#starts + 1] = k end
                end
            end
            for i, k in ipairs(starts) do
                local stop = (starts[i + 1] or last) - 1
                while stop > k and (toks[stop].t == 'space' or toks[stop].t == 'comment') do stop = stop - 1 end
                if i == #starts then stop = last - 1
                    while toks[stop].t == 'space' or toks[stop].t == 'comment' do stop = stop - 1 end
                end
                frame.entries[#frame.entries + 1] = { first = k, last = stop }
            end
            close_with(frame)
            frames[#frames] = nil
            return result
        end
        return struct(self, hint)
    end
    -- trailing-colon blocks open the home: `f x:` is `f x do(..)`
    local colon_lambda = p.colon_lambda
    function p:colon_lambda(colon, hint)
        replace[colon.index] = ' do(..)'
        return colon_lambda(self, colon, hint)
    end
    -- `endall`: the blocks it closes, innermost first
    local chains = {}
    local close_block = p.close_block
    function p:close_block(what)
        local tk = r:peek(1)
        if tk.t == 'name' and tk.v == 'endall' then
            local c = chains[tk.index] or {}
            chains[tk.index] = c
            local braced = what:find('with', 1, true) or what == 'the struct' or what == 'the oneof'
                or what == 'the ffistruct'
            c[#c + 1] = braced and '}' or 'end'
        end
        return close_block(self, what)
    end
    p:block('top')
    local tk = r:peek(1)
    if tk.t ~= 'eof' then r:error(("unexpected '%s'"):format(tk.v), tk) end
    for index, chain in pairs(chains) do
        local has_with = false
        for _, c in ipairs(chain) do if c == '}' then has_with = true end end
        if has_with or full then
            replace[index] = table.concat(chain, mark and '\n' or ' ')
        end
    end
    local out = {}
    for i, tk in ipairs(toks) do
        if tk.t ~= 'eof' and not drop[i] then
            out[#out + 1] = replace[i] or tk.v
            if after[i] then out[#out + 1] = after[i] end
        end
    end
    return table.concat(out)
end

-- the expansion, or nil when the text does not parse (a candidate rewrite that is not a program)
function try_expand(...)
    local ok, text = pcall(M.expand, ...)
    return ok and text or nil
end

-- `do(..)` at index i, followed by the end of its line: the token list of the colon form it
-- stands for. A named parameter is a do-form, not a colon, and `do()` has none.
local function untyped_head(tokens, i)
    local j = i + 1
    if not tokens[j] or tokens[j][1] ~= '(' then return nil end
    local names, k = {}, j + 1
    while true do
        local tk = tokens[k]
        if not tk then return nil end
        if tk[1] == 'iden' then
            names[#names + 1] = tk[2]
        elseif tk[1] == '.' and tokens[k + 1] and tokens[k + 1][1] == '.' then
            -- a rest parameter (`..arguments`) has no colon spelling
            if tokens[k + 2] and tokens[k + 2][1] == 'iden' then return nil end
            if #names > 0 and tokens[k - 1][1] == 'iden' then names[#names] = names[#names] .. '..'
            else names[#names + 1] = '..' end
            k = k + 1
        elseif tk[1] == ')' then
            break
        elseif tk[1] ~= ',' and tk[1] ~= 'space' then
            return nil
        end
        k = k + 1
    end
    -- `do(..)` opens the home, which is what the colon form means; `do()` takes no parameters
    -- and a named parameter stays a do-form
    if #names ~= 1 or names[1] ~= '..' then return nil end
    local e = k + 1
    while tokens[e] and tokens[e][1] == 'space' and not tokens[e][2]:find '\n' do e = e + 1 end
    if tokens[e] and tokens[e][1] == 'comment' then e = e + 1 end
    if tokens[e] and not (tokens[e][1] == 'space' and tokens[e][2]:find '\n') then return nil end
    return names, k
end

function M.colonize(source)
    local tokens = lexer.scan_raw_tokenlist(source)
    local out, openers, i, n = {}, {}, 1, #tokens
    local closer_of = {}
    for k, tk in ipairs(tokens) do
        local t = tk[1]
        if t == '(' or t == '{' or t == '[' then openers[#openers + 1] = k
        elseif t == ')' or t == '}' or t == ']' then closer_of[k] = table.remove(openers) end
    end
    openers = {}
    while i <= n do
        local tk = tokens[i]
        local t = tk[1]
        if t == '(' or t == '{' or t == '[' then openers[#openers + 1] = i
        elseif t == ')' or t == '}' or t == ']' then table.remove(openers) end
        local done = false
        local p = is_do(tk) and skip_back(tokens, i)
        if is_do(tk) and #openers == 0 then
            local operand = p >= 1 and (OPERAND[tokens[p][1]]
                or (tokens[p][1] == 'keyword' and LITERAL[tokens[p][2]]))
            local after_params = p >= 1 and tokens[p][1] == ')' and closer_of[p]
                and parameter_list(tokens, closer_of[p])
            local names, close = untyped_head(tokens, i)
            if operand and not after_params and names then
                -- drop the space before `do`, write `:`; a comment stays where it was
                while #out > 0 and out[#out][1] == 'space' and not out[#out][2]:find '\n' do out[#out] = nil end
                out[#out + 1] = { ':', ':', tk[3] }
                i = close + 1
                done = true
            end
        end
        if not done then out[#out + 1] = tk; i = i + 1 end
    end
    local result = text_of(out)
    -- the colon form must mean what the do-form meant
    local a, b = try_expand(result), try_expand(source)
    if not a or a ~= b then return source end
    return result
end

-- Which block or bracket is innermost at each token, for source text that has no
-- colon blocks and no `with` (it was expanded): returns top_at[i] (a frame) and
-- the frame each bracket token opens.
local function frames_of(tokens)
    local stack, top_at, opened = {}, {}, {}
    for i, tk in ipairs(tokens) do
        top_at[i] = stack[#stack]
        local t, v = tk[1], tk[2]
        if t == '(' or t == '{' or t == '[' then
            local f = { kind = 'bracket', open = i }
            stack[#stack + 1] = f
            opened[i] = f
        elseif t == ')' or t == '}' or t == ']' then
            if stack[#stack] and stack[#stack].kind == 'bracket' then stack[#stack] = nil end
        elseif (t == 'keyword' or t == 'iden') and v == 'do' then
            if not expression_lambda(tokens, i) then stack[#stack + 1] = { kind = 'block' } end
        elseif t == 'keyword' and (v == 'function' or v == 'if') then
            stack[#stack + 1] = { kind = 'block' }
        elseif t == 'keyword' and v == 'repeat' then
            stack[#stack + 1] = { kind = 'repeat' }
        elseif t == 'keyword' and v == 'until' then
            if stack[#stack] and stack[#stack].kind == 'repeat' then stack[#stack] = nil end
        elseif t == 'keyword' and v == 'end' or (t == 'iden' and v == 'endall') then
            if stack[#stack] and stack[#stack].kind == 'block' then
                stack[#stack] = nil
                if v == 'endall' then
                    while stack[#stack] and stack[#stack].kind == 'block' do stack[#stack] = nil end
                end
            end
        end
    end
    return top_at, opened
end

-- The matching closers of a token list, and whether a table is data: some top-level entry
-- is keyed (`k = v`, `k: T`, `[k] = v`, `.k`).
local function table_scanner(tokens)
    local close_of, stack = {}, {}
    for i, tk in ipairs(tokens) do
        local t = tk[1]
        if t == '(' or t == '{' or t == '[' then stack[#stack + 1] = i
        elseif t == ')' or t == '}' or t == ']' then close_of[table.remove(stack)] = i end
    end
    local function keyed(open)
        local depth = 0
        for k = open + 1, close_of[open] - 1 do
            local t = tokens[k][1]
            if t == '(' or t == '{' or t == '[' then
                if t == '[' and depth == 0 then
                    local c = close_of[k]
                    local nx = c and skip_forward(tokens, c)
                    if nx and tokens[nx][1] == '=' then return true end
                end
                depth = depth + 1
            elseif t == ')' or t == '}' or t == ']' then depth = depth - 1
            elseif depth == 0 and t == 'iden' then
                local nx = skip_forward(tokens, k)
                local n = nx and tokens[nx]
                if n and (n[1] == '=' or (n[1] == ':' and tokens[nx + 1] and tokens[nx + 1][1] == 'space')) then
                    return true
                end
            elseif depth == 0 and t == '.' and tokens[k + 1] and tokens[k + 1][1] == 'iden' then
                local p = skip_back(tokens, k)
                local pt = p >= 1 and tokens[p][1]
                if pt == '{' or pt == ',' or pt == ';' then return true end
            end
        end
        return false
    end
    return close_of, keyed
end

-- A table of at most `limit` plain entries that follows a head (`T { .. }`) is written on one
-- line when the line then fits `width`: `Point { x = 1, y = 2 }`. A table with a block, a
-- comment, more entries, or no room stays as it is (and is written as `with` when it spans
-- lines). Contextual `with` has no type head to attach braces to, so it is left alone.
local BLOCK = { ['do'] = true, ['function'] = true, ['end'] = true, ['if'] = true, ['for'] = true,
                ['while'] = true, ['repeat'] = true, ['return'] = true }
local function inline_pass(source, limit, width, keep_spreads)
    local tokens = lexer.scan_raw_tokenlist(source)
    local close_of, keyed = table_scanner(tokens)
    -- top-level entries of the table opened at i; nil when something forbids a single line
    local function entries(open)
        local depth, count, any = 0, 0, false
        for k = open + 1, close_of[open] - 1 do
            local t, text = tokens[k][1], tokens[k][2]
            if t == 'comment' and text ~= MARK then return nil end
            -- a table that extends a base (`..base`) stays a block when it spans lines
            if keep_spreads and depth == 0 and t == '.' and tokens[k + 1] and tokens[k + 1][1] == '.'
                and not (tokens[k + 2] and tokens[k + 2][1] == '.') and (any == false) then
                local multiline = false
                for q = open + 1, close_of[open] - 1 do
                    if tokens[q][1] == 'space' and tokens[q][2]:find '\n' then multiline = true end
                end
                if multiline then return nil end
            end
            if t == 'keyword' and BLOCK[text] then return nil end
            if t == '(' or t == '{' or t == '[' then depth = depth + 1
            elseif t == ')' or t == '}' or t == ']' then depth = depth - 1
            elseif depth == 0 and (t == ',' or t == ';') then count = count + 1; any = false
            elseif t ~= 'space' and t ~= 'comment' then any = true end
        end
        if any then count = count + 1 end
        return count
    end
    local function nested_within_limit(open)
        for k = open + 1, close_of[open] - 1 do
            if tokens[k][1] == '{' and close_of[k] then
                local n = entries(k)
                if n == nil or n > limit then return false end
            end
        end
        return true
    end
    local out, i, line_used = {}, 1, {}
    local line_start = 1                       -- index of the first token of the current line
    while i <= #tokens do
        local tk = tokens[i]
        local replaced = false
        if tk[1] == '{' and close_of[i] and keyed(i) then
            local p = skip_back(tokens, i)
            local head = p >= 1 and OPERAND[tokens[p][1]] and tokens[p][1] ~= 'string'
                and not (tokens[p][1] == 'iden' and tokens[p][2] == 'with')
            local n = head and entries(i)
            if n and n >= 1 and n <= limit and nested_within_limit(i) and not line_used[line_start] then
                -- the table on one line: newlines inside become single spaces
                local inner = {}
                for k = i + 1, close_of[i] - 1 do
                    local t = tokens[k]
                    if t[1] == 'comment' and t[2] == MARK then
                        -- dropped: the table is written with braces
                    elseif t[1] == 'space' then
                        inner[#inner + 1] = { 'space', ' ', t[3] }
                    else
                        inner[#inner + 1] = t
                    end
                end
                while inner[1] and inner[1][1] == 'space' do table.remove(inner, 1) end
                while inner[#inner] and inner[#inner][1] == 'space' do table.remove(inner) end
                -- a trailing separator is not needed before the closing brace
                if inner[#inner] and (inner[#inner][1] == ',' or inner[#inner][1] == ';') then table.remove(inner) end
                while inner[#inner] and inner[#inner][1] == 'space' do table.remove(inner) end
                local flat = { { '{', '{', tk[3] }, { 'space', ' ', tk[3] } }
                for _, t in ipairs(inner) do flat[#flat + 1] = t end
                flat[#flat + 1] = { 'space', ' ', tk[3] }
                flat[#flat + 1] = tokens[close_of[i]]
                -- the line it would make: what precedes `{` on its line, the table, what follows `}`
                local before = 0
                for k = line_start, i - 1 do before = before + #tokens[k][2] end
                local after, k = 0, close_of[i] + 1
                while tokens[k] and not (tokens[k][1] == 'space' and tokens[k][2]:find '\n') do
                    after = after + #tokens[k][2]; k = k + 1
                end
                local width_now = before + after
                for _, t in ipairs(flat) do width_now = width_now + #t[2] end
                if width_now <= width then
                    for _, t in ipairs(flat) do out[#out + 1] = t end
                    line_used[line_start] = true
                    i = close_of[i] + 1
                    replaced = true
                end
            end
        end
        if not replaced then
            out[#out + 1] = tk
            if tk[1] == 'space' and tk[2]:find '\n' then line_start = i + 1 end
            i = i + 1
        end
    end
    return text_of(out)
end
function M.inline_tables(source, limit, width, keep_spreads)
    if not limit or limit < 1 then return source end
    for _ = 1, 8 do
        local result = inline_pass(source, limit, width, keep_spreads)
        if result == source then break end
        source = result
    end
    return source
end


-- Mark the multi-line tables that follow a head (`T {`, `f(x) {`): `withize` writes
-- them as `with` blocks. One-line tables and tables with no head (`{ 1, 2 }`,
-- `local t = { a = 1 }`, which are Lua's) are left alone.
function M.mark_tables(source)
    local tokens = lexer.scan_raw_tokenlist(source)
    local close_of, keyed = table_scanner(tokens)
    local out, header = {}, false              -- header: between `for`/`while` and its `do`
    for i, tk in ipairs(tokens) do
        out[#out + 1] = tk
        if tk[1] == 'keyword' and (tk[2] == 'for' or tk[2] == 'while') then header = true
        elseif tk[1] == 'keyword' and tk[2] == 'do' then header = false end
        if tk[1] == '{' and close_of[i] and not header and keyed(i) then
            local p = skip_back(tokens, i)
            local head = p >= 1 and (OPERAND[tokens[p][1]]) and tokens[p][1] ~= 'string'
            local multiline = false
            for k = i + 1, close_of[i] - 1 do
                if tokens[k][1] == 'space' and tokens[k][2]:find '\n' then multiline = true; break end
            end
            local k = i + 1
            while tokens[k] and tokens[k][1] == 'space' do k = k + 1 end
            local marked = tokens[k] and tokens[k][1] == 'comment' and tokens[k][2] == MARK
            if head and multiline and not marked then out[#out + 1] = { 'comment', MARK, tk[3] } end
        end
    end
    return text_of(out)
end

-- Write the braces `expand` marked back as `with ... end`. A separator is dropped
-- where the reader would put it back (before an entry that starts with `name =`,
-- `name:` or a line of its own, and before the closing brace). Without the marks
-- the source is returned with its braces; the result is only accepted when
-- expanding it gives the braces' own token stream.
function M.withize(source, unit, spread_beside)
    unit = unit or '    '
    local tokens = lexer.scan_raw_tokenlist(source)
    local top_at, opened = frames_of(tokens)
    local close_of, stack = {}, {}
    for i, tk in ipairs(tokens) do
        local t = tk[1]
        if t == '(' or t == '{' or t == '[' then stack[#stack + 1] = i
        elseif t == ')' or t == '}' or t == ']' then close_of[table.remove(stack)] = i end
    end
    local function next_sig(i)
        i = i + 1
        while tokens[i] and (tokens[i][1] == 'space' or tokens[i][1] == 'comment') do i = i + 1 end
        return i
    end
    local blocks, plain = {}, {}
    for i, tk in ipairs(tokens) do
        if tk[1] == '{' then
            local j = i + 1
            while tokens[j] and tokens[j][1] == 'space' do j = j + 1 end
            if tokens[j] and tokens[j][1] == 'comment' and tokens[j][2] == MARK then
                local block = { open = i, close = close_of[i], drop = {} }
                -- a `define` block carries a second mark right after the first
                local d = j + 1
                while tokens[d] and tokens[d][1] == 'space' and not tokens[d][2]:find '\n' do d = d + 1 end
                if tokens[d] and tokens[d][1] == 'comment' and tokens[d][2] == DEFINE then
                    block.define = true
                    j = d
                end
                blocks[#blocks + 1] = block
                for k = i + 1, j do block.drop[k] = true end
                -- `with {` (a headless `with`): the word stays and the brace goes, with the space
                -- between them
                local w = i - 1
                while tokens[w] and tokens[w][1] == 'space' and not tokens[w][2]:find '\n' do w = w - 1 end
                if tokens[w] and tokens[w][1] == 'iden' and (tokens[w][2] == 'with' or tokens[w][2] == 'struct'
                    or tokens[w][2] == 'oneof' or tokens[w][2] == 'ffistruct') and w < i then
                    block.headless = true
                    for k = w + 1, i - 1 do block.drop[k] = true end
                end
                local f = opened[i]
                local function has_newline(a, b)
                    for q = a, b do
                        if tokens[q][1] == 'space' and tokens[q][2]:find '\n' then return true end
                    end
                    return false
                end
                -- a table that spans lines is written one entry per line, `end` on a line of its own
                local multiline = has_newline(i + 1, close_of[i] - 1)
                block.before, block.moved = {}, {}
                if multiline then
                    -- the block's own line is indented like the entry of the block around it
                    -- (that entry gets a line of its own), else like the line it is on
                    local indent
                    for q = #blocks - 1, 1, -1 do
                        local outer = blocks[q]
                        if outer.open < i and i < outer.close and outer.moved then
                            -- the entry of `outer` this table sits in, if that entry was moved to a line
                            -- of its own and no line break separates its start from the table
                            local start
                            for at in pairs(outer.moved) do
                                if at < i and (not start or at > start) then start = at end
                            end
                            if start and not has_newline(start, i) then indent = outer.moved[start] end
                            break
                        end
                    end
                    if not indent then
                        indent = ''
                        for q = i - 1, 1, -1 do
                            if tokens[q][1] == 'space' and tokens[q][2]:find '\n' then
                                indent = tokens[q][2]:match('[^\n]*$'); break
                            end
                        end
                    end
                    block.indent = indent
                    local function own_line(at, text)
                        local p = at - 1
                        if tokens[p][1] == 'space' and tokens[p][2]:find '\n' then return end
                        if tokens[p][1] == 'space' then block.drop[p] = true end
                        block.before[at] = '\n' .. text
                        block.moved[at] = text
                    end
                    local at = next_sig(j)
                    -- one `..base` among the entries, standing first, stays beside the `with`
                    local beside = false
                    if spread_beside and tokens[at] and tokens[at][1] == '.' and tokens[at + 1] and tokens[at + 1][1] == '.'
                        and not (tokens[at + 2] and tokens[at + 2][1] == '.') then
                        local spreads, entries_n, depth_n = 0, 0, 0
                        local starts_entry = true
                        for k = i + 1, close_of[i] - 1 do
                            local c = tokens[k]
                            if c[1] == '(' or c[1] == '{' or c[1] == '[' then depth_n = depth_n + 1
                            elseif c[1] == ')' or c[1] == '}' or c[1] == ']' then depth_n = depth_n - 1
                            elseif depth_n == 0 and (c[1] == ',' or c[1] == ';') then
                                entries_n = entries_n + 1; starts_entry = true
                            elseif depth_n == 0 and c[1] == '.' and starts_entry and tokens[k + 1] and tokens[k + 1][1] == '.'
                                and not (tokens[k + 2] and tokens[k + 2][1] == '.') then
                                spreads = spreads + 1; starts_entry = false
                            elseif c[1] ~= 'space' and c[1] ~= 'comment' then starts_entry = false end
                        end
                        beside = spreads == 1 and entries_n >= 1
                    end
                    if beside then
                        local p = at - 1
                        while p > i and tokens[p][1] == 'space' do block.drop[p] = true; p = p - 1 end
                        block.before[at] = ' '
                    elseif at < close_of[i] then own_line(at, indent .. unit) end
                    for k = i + 1, close_of[i] - 1 do
                        local c = tokens[k]
                        if top_at[k] == f and (c[1] == ',' or c[1] == ';') then
                            local nx = next_sig(k)
                            if nx < close_of[i] then own_line(nx, indent .. unit) end
                        end
                    end
                    own_line(close_of[i], indent)
                    -- Lines the layout already put on their own keep their indentation, which was
                    -- worked out for braces (inside call brackets it is two levels too deep): shift
                    -- them so the entries stand one unit in from the line the block starts on, and the
                    -- `end` stands under it
                    local function indent_of(k) return #(tokens[k][2]:match('[^\n]*$')) end
                    for k = i + 1, close_of[i] - 1 do
                        if tokens[k][1] == 'space' and tokens[k][2]:find '\n' and not block.drop[k]
                            and not block.before[k + 1] and k + 1 < close_of[i] then
                            block.delta = #(indent .. unit) - indent_of(k)
                            break
                        end
                    end
                    local before_close = close_of[i] - 1
                    if tokens[before_close][1] == 'space' and tokens[before_close][2]:find '\n' and not block.drop[before_close] then
                        block.close_delta = #indent - indent_of(before_close)
                        block.close_space = before_close
                    end
                end
                for k = i + 1, close_of[i] - 1 do
                    local c = tokens[k]
                    if top_at[k] == f and (c[1] == ',' or c[1] == ';') then
                        local nx = next_sig(k)
                        local first, second = tokens[nx], tokens[next_sig(nx)]
                        local newline = multiline or has_newline(k + 1, nx - 1)
                        local starts = first and first[1] == 'iden' and second and (second[1] == '='
                            or (second[1] == ':' and tokens[next_sig(nx) + 1] and tokens[next_sig(nx) + 1][1] == 'space'))
                        -- an entry that begins a line is read as an entry whatever it starts with: a
                        -- name, `.name`, a literal, a table, a bracket, a parenthesis, `-1`, `do`
                        local begins = first and (first[1] == 'iden' or first[1] == '.' or first[1] == 'number'
                            or first[1] == 'string' or first[1] == '{' or first[1] == '[' or first[1] == '('
                            or first[1] == '-' or (first[1] == 'keyword' and (first[2] == 'do' or first[2] == 'true'
                            or first[2] == 'false')))
                        -- entries on one line keep their commas; at a line end the reader writes it back
                        -- a plain `with` keeps the commas of positional entries; a `define` list is
                        -- written without them
                        local plain_start = first and (first[1] == 'iden' or first[1] == '.')
                        if nx == close_of[i] or (newline and (starts or (block.define and begins) or plain_start)) then
                            block.drop[k] = true
                        end
                    end
                end
            end
        elseif tk[1] == 'comment' and (tk[2] == MARK or tk[2] == DEFINE) then
            plain[i] = true
        end
    end
    -- the source with the selected blocks written as `with ... end`
    local function build(selected)
        local drop, replace, before, shift = {}, {}, {}, {}
        -- indentation is shifted only where every line is one the layout wrote: a block that had
        -- entries moved onto lines of their own (or has such a block inside) is already absolute
        local function has_moved(block)
            -- this block's own moved entries are written with their indentation already; the lines
            -- the layout wrote between them still shift. A block inside that moved entries makes
            -- every line in its range absolute.
            for _, inner in ipairs(selected) do
                if inner ~= block and inner.open > block.open and inner.close < block.close and next(inner.moved) then
                    return true
                end
            end
            return false
        end
        for _, block in ipairs(selected) do
            for k in pairs(block.drop) do drop[k] = true end
            for k, text in pairs(block.before) do before[k] = text end
            replace[block.open], replace[block.close] = block.define and 'define' or (block.headless and '' or 'with'), 'end'
            if not has_moved(block) then
                for k = block.open + 1, block.close - 1 do
                    if tokens[k][1] == 'space' and tokens[k][2]:find '\n' and k ~= block.close_space then
                        shift[k] = (shift[k] or 0) + (block.delta or 0)
                    end
                end
                if block.close_space then shift[block.close_space] = (shift[block.close_space] or 0) + block.close_delta end
            end
        end
        local out = {}
        for i, tk in ipairs(tokens) do
            if not plain[i] and not drop[i] then
                if before[i] then out[#out + 1] = { 'space', before[i] } end
                local text = replace[i]
                if text == '' then
                    -- a brace that only marked a headless `with`: nothing is written for it
                elseif text then
                    local prev = out[#out]
                    -- a space before the word, except right after an opening bracket
                    if prev and prev[1] ~= 'space' and prev[1] ~= '(' and prev[1] ~= '[' then out[#out + 1] = { 'space', ' ' } end
                    out[#out + 1] = { 'iden', text }
                elseif shift[i] and shift[i] ~= 0 then
                    local lead, indent = tk[2]:match('^(.*\n)([^\n]*)$')
                    out[#out + 1] = { 'space', lead .. (' '):rep(math.max(0, #indent + shift[i])) }
                else
                    out[#out + 1] = tk
                end
            end
        end
        return text_of(out)
    end
    local function plain_text()
        local out = {}
        for i, tk in ipairs(tokens) do
            local is_mark = tk[1] == 'comment' and (tk[2] == MARK or tk[2] == DEFINE)
            if is_mark then
                -- the spaces the layout put before a mark go with it
                while out[#out] and out[#out][1] == 'space' and not out[#out][2]:find '\n' do out[#out] = nil end
            else
                out[#out + 1] = tk
            end
        end
        return text_of(out)
    end
    local function normal(text)
        -- a comma before the closing brace is only spelling
        local parts = {}
        for _, tk in ipairs(lexer.scan_raw_tokenlist(text)) do
            if tk[1] ~= 'space' and tk[1] ~= 'comment' then
                if tk[1] == '}' and parts[#parts] == ',' then parts[#parts] = nil end
                parts[#parts + 1] = tk[2]
            end
        end
        return table.concat(parts, '\0')
    end
    local braces = plain_text()
    if #blocks == 0 then return braces end
    local want = normal(braces)
    local function accepted(selected)
        local text = build(selected)
        local expanded = try_expand(text, true)
        return expanded and normal(expanded) == want and text
    end
    local all = accepted(blocks)
    if all then return all end
    -- one block the reader would not recover must not keep the others from converting
    local chosen = {}
    for _, block in ipairs(blocks) do
        if accepted({ block }) then chosen[#chosen + 1] = block end
    end
    return accepted(chosen) or braces
end

-- Mua blocks found without rewriting: for text that has `with` blocks and do-forms
-- (the formatter's output before the colon pass). Frames are { kind, open, close, parent }.
local function scan_blocks(tokens)
    local stack, frames, close_frame, depth_at, loops = {}, {}, {}, {}, {}
    local function push(kind, i)
        local f = { kind = kind, open = i, parent = stack[#stack] }
        frames[#frames + 1] = f
        stack[#stack + 1] = f
    end
    for i, tk in ipairs(tokens) do
        depth_at[i] = #stack
        local t, v = tk[1], tk[2]
        if t == '(' or t == '{' or t == '[' then push('bracket', i)
        elseif t == ')' or t == '}' or t == ']' then
            if stack[#stack] and stack[#stack].kind == 'bracket' then stack[#stack] = nil end
        elseif t == 'keyword' and (v == 'while' or v == 'for') then
            loops[#stack] = (loops[#stack] or 0) + 1
        elseif (t == 'keyword' or t == 'iden') and v == 'do' then
            if (loops[#stack] or 0) > 0 then
                loops[#stack] = loops[#stack] - 1
                push('control', i)
            elseif not expression_lambda(tokens, i) then
                local p = skip_back(tokens, i)
                local before = p >= 1 and tokens[p]
                local lambda = before and (OPERAND[before[1]] or EXPRESSION_START[before[1]]
                    or (before[1] == 'keyword' and (before[2] == 'return' or LITERAL[before[2]])))
                push(lambda and not typed_lambda(tokens, i) and 'lambda' or 'control', i)
            end
        elseif t == 'keyword' and (v == 'function' or v == 'if') then push('control', i)
        elseif t == 'keyword' and v == 'repeat' then push('repeat', i)
        elseif t == 'keyword' and v == 'until' then
            if stack[#stack] and stack[#stack].kind == 'repeat' then stack[#stack] = nil end
        elseif t == 'keyword' and v == 'end' then
            local f = stack[#stack]
            if f and f.kind ~= 'bracket' then
                f.close = i
                close_frame[i] = { f }
                stack[#stack] = nil
            end
        elseif t == 'iden' and v == 'endall' then
            -- an `endall` already written closes the lambdas on top of the stack
            local popped = {}
            while stack[#stack] and (stack[#stack].kind == 'lambda' or stack[#stack].kind == 'with') do
                local f = stack[#stack]
                f.close = i
                popped[#popped + 1] = f
                stack[#stack] = nil
            end
            close_frame[i] = popped
        elseif t == 'iden' and (v == 'struct' or v == 'oneof' or v == 'ffistruct') then
            -- the block form: the word, then fields (`name:`) up to `end`
            local a = significant_after(tokens, i)
            local b = tokens[a] and significant_after(tokens, a)
            if tokens[a] and tokens[a][1] == 'iden' and tokens[b] and tokens[b][1] == ':' then push('with', i) end
        elseif t == 'iden' and v == 'with' then
            local p = skip_back(tokens, i)
            local operand = p >= 1 and (OPERAND[tokens[p][1]]
                or (tokens[p][1] == 'keyword' and LITERAL[tokens[p][2]]))
            local nx = tokens[significant_after(tokens, i)]
            local adjacent = tokens[i + 1] and (tokens[i + 1][1] == '.' or tokens[i + 1][1] == '(')
            if (operand and not adjacent and not (nx and nx[1] == '=')) or contextual_with(tokens, i) then
                push('with', i)
            end
        end
    end
    return frames, close_frame, depth_at
end

-- the token that ends a lambda's header: its parameter list's `)`, or `do` itself
local function header_end(tokens, frame)
    local i = frame.open
    local j = significant_after(tokens, i)
    if tokens[j] and tokens[j][1] == '(' then
        local depth = 0
        repeat
            local t = tokens[j][1]
            if t == '(' then depth = depth + 1 elseif t == ')' then depth = depth - 1 end
            j = j + 1
        until depth == 0 or j > #tokens
        return j - 1
    end
    return i
end

-- Fold the trailing `end` lines that close Mua blocks into one `endall`, and lay the chain
-- out flat: the wrappers (`tasks:`, `spawn:`), then the content indented once, with the
-- links of the handler chain at the content's indent, sibling entries one level in, and the
-- innermost body one level in. A chain is folded only if it has a `with` (lambda-only
-- chains keep the spine style) and the macro would read the result back as the same program.
function M.foldends(source, unit)
    unit = unit or '    '
    local tokens = lexer.scan_raw_tokenlist(source)
    local frames, close_frame = scan_blocks(tokens)
    local lines = {}
    for l in (source .. '\n'):gmatch('([^\n]*)\n') do lines[#lines + 1] = l end
    if lines[#lines] == '' then lines[#lines] = nil end
    local sig_on, comment_on = {}, {}
    for i, tk in ipairs(tokens) do
        local line = tk[3]
        if tk[1] == 'comment' then comment_on[line] = true
        elseif tk[1] ~= 'space' then
            sig_on[line] = sig_on[line] or {}
            table.insert(sig_on[line], i)
        end
    end
    local function indent_of(line) return #(lines[line]:match('^ *')) end
    -- lines holding only an `end` that closes a block
    local closer_line = {}
    for line, list in pairs(sig_on) do
        local i = list[1]
        if #list == 1 and not comment_on[line] and close_frame[i] then closer_line[line] = i end
    end
    local runs, ordered = {}, {}
    for line in pairs(closer_line) do ordered[#ordered + 1] = line end
    table.sort(ordered)
    for _, line in ipairs(ordered) do
        local run = runs[#runs]
        if run and run.last == line - 1 then run[#run + 1] = line; run.last = line
        else runs[#runs + 1] = { line, last = line } end
    end
    local edits = {}
    for r = #runs, 1, -1 do
        local run = runs[r]
        -- the closers of the run, innermost first, one frame each (an `endall` line has several)
        local entries = {}
        for _, line in ipairs(run) do
            for _, f in ipairs(close_frame[closer_line[line]]) do entries[#entries + 1] = { line = line, frame = f } end
        end
        -- skip the explicit closers of Lua control blocks that come first (innermost)
        local k = 1
        while entries[k] and entries[k].frame.kind == 'control' do k = k + 1 end
        local chain, first_line = {}, entries[k] and entries[k].line
        local prev, last_chain_line
        while entries[k] do
            local f = entries[k].frame
            if f.kind ~= 'lambda' and f.kind ~= 'with' then break end
            if prev and prev.parent ~= f then break end
            chain[#chain + 1] = f
            last_chain_line = entries[k].line
            prev = f
            k = k + 1
        end
        local outer = chain[#chain]
        local ok = #chain >= 3 and outer.parent and outer.parent.kind == "control"
        local has_with = false
        for _, f in ipairs(chain) do if f.kind == 'with' then has_with = true end end
        if ok and has_with then
            -- C[1] is the outermost link
            local C, m = {}, #chain
            for j = 1, m do C[j] = chain[m - j + 1] end
            local opener_line, header_line = {}, {}
            for j = 1, m do
                local o = C[j].kind == 'with' and C[j].open or header_end(tokens, C[j])
                header_line[j] = tokens[o][3]
                -- the header must end its line, and the line must start the statement
                local list = sig_on[header_line[j]]
                if list[#list] ~= o then ok = false end
                opener_line[j] = tokens[C[j].open][3]
                if opener_line[j] ~= header_line[j] and C[j].kind == 'with' then ok = false end
            end
            local last_line = last_chain_line
            if ok then
                -- bodies: a lambda link holds nothing but the next link
                for j = 1, m - 1 do
                    if C[j].kind == 'lambda' then
                        for l = header_line[j] + 1, opener_line[j + 1] - 1 do
                            if lines[l]:match('%S') then ok = false end
                        end
                    end
                end
            end
            if ok then
                local base = indent_of(opener_line[1])
                local level, seen_with = { base }, C[1].kind == 'with'
                for j = 2, m do
                    local step = 0
                    if C[j].kind == 'with' and not seen_with and C[j - 1].kind == 'lambda' then step = #unit end
                    if C[j].kind == 'with' then seen_with = true end
                    level[j] = level[j - 1] + step
                end
                local first_closer = first_line
                local new_indent = {}                -- line -> target indent of the first line of its segment
                local segments = {}
                local function segment(from, to, target)
                    if from > to then return end
                    local lead
                    for l = from, to do if lines[l]:match('%S') then lead = l; break end end
                    if not lead then return end
                    segments[#segments + 1] = { from = from, to = to, shift = target - indent_of(lead) }
                end
                for j = 1, m do
                    segment(header_line[j], header_line[j], level[j])   -- the link's own line
                    local stop = (j < m) and (opener_line[j + 1] - 1) or (first_closer - 1)
                    segment(header_line[j] + 1, stop, level[j] + #unit)  -- siblings or the innermost body
                end
                edits[#edits + 1] = { segments = segments, closers = { first_line, last_line }, base = base }
            end
        end
    end
    if #edits == 0 then return source end
    local result = {}
    for i, l in ipairs(lines) do result[i] = l end
    for _, e in ipairs(edits) do                     -- bottom-up, so earlier line numbers hold
        for _, sgm in ipairs(e.segments) do
            for l = sgm.from, sgm.to do
                if result[l]:match('%S') then
                    local width = math.max(0, #(result[l]:match('^ *')) + sgm.shift)
                    result[l] = (' '):rep(width) .. result[l]:gsub('^ *', '')
                end
            end
        end
        for l = e.closers[1], e.closers[2] do result[l] = false end
        result[e.closers[1]] = (' '):rep(e.base) .. 'endall'
    end
    local out = {}
    for _, l in ipairs(result) do if l then out[#out + 1] = l end end
    local folded = table.concat(out, '\n') .. '\n'
    -- the macro must read the folded text back as the same program
    local function normal(text)
        local parts = {}
        for _, tk in ipairs(lexer.scan_raw_tokenlist(text)) do
            if tk[1] ~= 'space' and tk[1] ~= 'comment' then parts[#parts + 1] = tk[2] end
        end
        return table.concat(parts, '\0')
    end
    local a, b = try_expand(folded, true, true), try_expand(source, true, true)
    if not a or not b or normal(a) ~= normal(b) then return source end
    return folded
end

return M
