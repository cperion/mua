-- Run from the repository root with Neovim 0.10+.
local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root .. '/tools/tree-sitter-mua')
require('mua_treesitter').setup()
vim.cmd('filetype on')
local query = assert(vim.treesitter.query.get('mua', 'highlights'))
local count = 0
local function parse(text, label)
  local parser = vim.treesitter.get_string_parser(text, 'mua')
  local tree = parser:parse()[1]
  assert(not tree:root():has_error(), label .. ': ' .. tree:root():sexpr())
  count = count + 1
  return tree, parser
end
local function read(path) return table.concat(vim.fn.readfile(path), '\n') .. '\n' end
for _, pattern in ipairs({ 'tools/tree-sitter-mua/tests/*.mua' }) do
  for _, path in ipairs(vim.fn.glob(pattern, false, true)) do parse(read(path), path) end
end
local fixture = root .. '/tools/tree-sitter-mua/tests/highlights.mua'
vim.cmd.edit(vim.fn.fnameescape(fixture))
assert(vim.bo.filetype == 'mua', '*.mua filetype detection failed')
assert(vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], 'highlighter did not start')
assert(vim.bo.commentstring == '-- %s')
local parser = vim.treesitter.get_parser(0, 'mua')
local tree = parser:parse()[1]
local captured = {}
for id, node in query:iter_captures(tree:root(), 0) do
  local name = query.captures[id]
  local text = vim.treesitter.get_node_text(node, 0)
  captured[name .. ':' .. text] = true
end
for _, pair in ipairs({
  {'keyword', 'struct'}, {'keyword.function', 'do'},
  {'keyword.function', 'endall'}, {'keyword.function', ':'}, {'type.builtin', 'Unit'}, {'variable.parameter', 'x'},
  {'function', 'inc'}, {'function.call', 'print'}, {'function', 'ok'},
  {'number', '2'}, {'operator', '+'}, {'string.escape', '\\n'},
}) do
  assert(captured[pair[1] .. ':' .. pair[2]], 'missing capture ' .. table.concat(pair, ':'))
end
local string_count, comment_count = 0, 0
for id, node in query:iter_captures(tree:root(), 0) do
  local capture = query.captures[id]
  local first, _, last = node:range()
  if capture == 'string' and first == 7 then
    string_count = string_count + 1
    assert(last == 9, 'long string closed at mismatched delimiter')
  elseif capture == 'comment' and first == 10 then
    comment_count = comment_count + 1
    assert(last == 12, 'long comment ended too early')
  elseif (first >= 8 and first <= 9) or (first >= 11 and first <= 12) then
    error('code capture inside long string/comment: ' .. capture)
  end
end
assert(string_count == 1 and comment_count == 1, 'missing long string/comment captures')
local dots = parse([[
local opened = do(ctx..: T): U32 = ctx.value
local home = do(..: T): T = (..)
local values = do(..args): U32 = add(1, ..args)
local f = do(): U32
    local ctx.. = source
    local a, b = ..pair()
    local text = "a" .. "b"
    return add(..args)
end
local record = T { ..source, x = 1 }
local function host(...) return ... end
]], 'two-dot opening, home, expansion, concatenation, and Lua varargs')
assert(dots:root():sexpr():find('binary_expression', 1, true), 'concatenation lost its infix parse')
assert(dots:root():sexpr():find('spread_expression', 1, true), 'prefix expansion missing')
local spaced_tree = parse('local x = f a (b + 1)\nlocal y = f a(b)\nlocal z = f (g x) y\n', 'spaced parenthesis argument')
local spaced = spaced_tree:root():named_child(0):sexpr()
assert(not spaced:find('member_argument', 1, true), 'a spaced ( continued the argument: ' .. spaced)
assert(spaced_tree:root():named_child(1):sexpr():find('member_argument', 1, true), 'an attached ( left the argument')
local grouped = spaced_tree:root():named_child(2):sexpr()
assert(select(2, grouped:gsub('call_expression', '')) >= 3, 'a spaced group did not go on applying: ' .. grouped)
local newline_tree = parse('local x = f a\nx = x + 1\n', 'newline application boundary')
assert(newline_tree:root():named_child_count() == 2, 'name application crossed newline')
assert(newline_tree:root():named_child(1):type() == 'assignment_statement')
local bare_source = 'refresh\nscreen.refresh\nscreen:refresh\nlocal action = refresh\nlocal result = refresh()\n'
local bare_tree = parse(bare_source, 'bare calls remain statement-only')
assert(bare_tree:root():named_child_count() == 5, 'bare calls crossed a newline')
assert(bare_tree:root():named_child(2):named_child(0):type() == 'bare_method_call')
assert(not bare_tree:root():named_child(3):sexpr():find('call', 1, true), 'callable initializer became a call')
local bare_captures = {}
for id, node in query:iter_captures(bare_tree:root(), bare_source) do
  local row = node:range()
  bare_captures[row .. ':' .. query.captures[id]] = true
end
assert(bare_captures['0:function.call'] and bare_captures['1:function.call']
  and bare_captures['2:function.method.call'], 'bare calls lack call highlighting')
assert(not bare_captures['3:function.call'], 'callable value highlighted as invocation')
parse([[
local run = do(): Unit
    if flag then
        activity do
            activity do
                tick()
            endall
    end
    activity do
        tick()
    end
end
]], 'endall stops at control blocks and does not affect later lambdas')
-- The trailing colon opens a block; annotation colons, labels and methods do not.
local colon_tree = parse([[
with_buffer n:
    go
end
words:each:
    go
end
spawn:
    go
endall
]], 'trailing colon blocks')
local colon_sexpr = colon_tree:root():sexpr()
assert(select(2, colon_sexpr:gsub('%(lambda', '')) == 3, 'colon blocks are not lambdas: ' .. colon_sexpr)
assert(select(2, colon_sexpr:gsub('%(parameter%s', '')) == 0, 'a colon block takes no parameters: ' .. colon_sexpr)
local assigned = parse([[
local f = do(x)
    go x
end
local handlers = {
    found = do(v)
        go v
    end,
    other = do(..)
        go
    end,
}
g.h = do(..)
    go
end
]], 'a do lambda assigns a block')
local assigned_sexpr = assigned:root():sexpr()
assert(select(2, assigned_sexpr:gsub('%(lambda', '')) == 4, 'assigned blocks are not lambdas: ' .. assigned_sexpr)
local with_tree = parse([[
local Point = struct
    x: U32
    y: U32
end
local p = Point with
    .y
    x = 1
    found = do(v)
        go v
    end
end
local q = Point with x = 1, y = 2 end
local r = s with
    circle = do(c) = c * c
    rect = do(p)
        go p
    end
end
local with_name = 3
]], 'with blocks supply keyed data')
local with_sexpr = with_tree:root():sexpr()
assert(select(2, with_sexpr:gsub('%(table_constructor', '')) == 3, 'with blocks are not table constructors: ' .. with_sexpr)
assert(with_sexpr:find('(define_block (field (identifier) (identifier))', 1, true), 'a struct block is not a declaration block: ' .. with_sexpr)
local contextual = parse([[
local make = do(n: U32): Point
    return with
        x = n
        y = 2
    end
end
local q: Point = with
    x = 1
    y = 2
end
local r = f(with
    a = 1
end)
]], 'a with block takes its type from the context')
local contextual_sexpr = contextual:root():sexpr()
assert(select(2, contextual_sexpr:gsub('%(table_constructor', '')) == 3, 'contextual with blocks are not table constructors: ' .. contextual_sexpr)
parse([[
local g = do(n: U32): U32
    a with
        rect = do(r)
            total = r
        end
    circle = do(r)
    b with
        circle = do(q)
            total = r + q
        end
    rect = do(p)
        total = r + p
    endall
    return total
end
]], 'endall closes handlers and data blocks')
local plain = parse([[
local s: Store Node
local a, b: U32
local f = do(x: U32): U32
    return x
end
local Pair = struct {
    first: U32,
    last: U32
}
do
    goto done
    ::done::
end
xs:refresh
xs:each(f)
]], 'annotation colons are not blocks')
assert(select(2, plain:root():sexpr():gsub('%(lambda', '')) == 2, 'an annotation colon opened a block (only the typed lambda and the plain do block are lambdas): ' .. plain:root():sexpr())
local ok, missing = pcall(require('mua_treesitter').setup, { parser = root .. '/build/no-such-mua-parser.so' })
assert(not ok and tostring(missing):find('make tree%-sitter'), 'missing parser must produce build guidance')
require('mua_treesitter').setup({ parser = root .. '/build/tree-sitter-mua/mua.so' })
assert(vim.fn.exists('#MuaTreesitter_mua#FileType') == 1)
assert(vim.filetype.match({ filename = 'ordinary.lua' }) == 'lua', 'Lua filetype changed')
-- Exercise real incremental buffer edits and external-scanner state restoration.
local original = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local function compare_fresh(label)
  local incremental = parser:parse()[1]:root()
  local fresh = vim.treesitter.get_string_parser(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n') .. '\n', 'mua'):parse()[1]:root()
  assert(incremental:sexpr() == fresh:sexpr(), 'incremental mismatch: ' .. label)
end
vim.api.nvim_buf_set_text(0, 2, 6, 2, 9, {'increment'})
compare_fresh('rename')
vim.api.nvim_buf_set_lines(0, 0, 0, false, {'-- inserted before long strings and endall'})
compare_fresh('insert line')
vim.api.nvim_buf_set_lines(0, 0, -1, false, original)
compare_fresh('restore')
assert(not parser:parse()[1]:root():has_error())
vim.api.nvim_buf_set_lines(0, 22, 23, false, {'        end', '    end'})
compare_fresh('expand endall')
assert(not parser:parse()[1]:root():has_error())
vim.api.nvim_buf_set_lines(0, 0, -1, false, original)
compare_fresh('restore endall')
vim.api.nvim_buf_set_text(0, 7, 13, 7, 17, {'[=['})
compare_fresh('change long-string delimiter')
vim.api.nvim_buf_set_lines(0, 0, -1, false, original)
compare_fresh('restore long-string delimiter')
-- Incomplete source must recover; a restored buffer must parse cleanly.
vim.api.nvim_buf_set_lines(0, 0, -1, false, {'local f = do(x: U32): U32', 'return x +'})
assert(parser:parse()[1]:root():has_error(), 'incomplete code unexpectedly accepted')
compare_fresh('incomplete source')
vim.api.nvim_buf_set_lines(0, 0, -1, false, original)
compare_fresh('restore after error')
assert(not parser:parse()[1]:root():has_error())
-- a `..base` is an entry of a `with` block, beside the `with` or on a line of its own; the next
-- `..` on a new line starts another entry instead of concatenating
local spreads = parse([[
local d = define ..Document
    length = 10
end
local e = define
    ..A
    ..B
    n = 1
end
]], 'spread entries in with blocks')
assert(not spreads:root():sexpr():find('binary_expression', 1, true), 'a with spread concatenated: ' .. spreads:root():sexpr())
assert(select(2, spreads:root():sexpr():gsub('spread_expression', '')) == 3, 'with spreads missing: ' .. spreads:root():sexpr())
-- `define` entries `end` is a block; an ordinary use of the name is not
local defined = parse([[
local a = define
    x = 1
end
local define = 5
local b = define
local c = closed define
    op = "s"
end
]], 'define blocks and the name define')
local defined_sexpr = defined:root():sexpr()
assert(select(2, defined_sexpr:gsub('define_block', '')) == 2, 'define blocks missing: ' .. defined_sexpr)
-- a returned block is a do lambda
local returned = parse([[
local with_log = do(title)
    return do(body)
        go title
        body
    end
end
local plain = do(x)
    return x
end
]], 'a returned block is a do lambda')
local returned_sexpr = returned:root():sexpr()
assert(select(2, returned_sexpr:gsub('%(lambda', '')) == 3, 'a returned block is not a lambda: ' .. returned_sexpr)
-- a `define` block holds lists as well: positional entries, one per line
local listed = parse([[
local numbers = define
    1
    2
    -3
end
local shapes = define
    { x = 1 }
    define
        a = 2
    end
    f(1)
end
]], 'define makes lists')
assert(select(2, listed:root():sexpr():gsub('define_block', '')) == 3, 'define lists: ' .. listed:root():sexpr())
print(('Mua Tree-sitter: %d parse cases passed; highlight captures, filetype, startup, and incremental edits passed'):format(count))
vim.cmd('qa!')
