-- Formatter contract: comments, application boundaries, idempotence, no execution. Mua code, no host.
local root = arg[0]:match('^(.*)/tests/[^/]*$') or '.'
package.path = root .. '/?.lua;' .. package.path
local fmt = require 'mua.fmt'
local lex = require 'mua.lex'
local passed = 0
local function check(name, condition, detail)
    assert(condition, name .. (detail and ('\n' .. tostring(detail)) or ''))
    passed = passed + 1
end
local function read(path)
    local f = assert(io.open(path, 'rb')); local text = f:read('*a'); f:close(); return text
end
local function write(path, text)
    local f = assert(io.open(path, 'wb')); assert(f:write(text)); assert(f:close())
end
local function q(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local function capture(command)
    local p = assert(io.popen(command .. ' 2>&1; printf "\\n__STATUS__%d\\n" "$?"'))
    local text = p:read('*a'); p:close()
    local out, rc = text:match('^(.*)\n__STATUS__(%d+)\n$')
    assert(rc, text); return out, tonumber(rc)
end
local function formatted(name, input, expected, options)
    local out = fmt.format(input, options, name)
    check(name, out == expected, out)
    check(name .. ' idempotent', fmt.format(out, options, name) == out)
end
formatted('golden', read(root .. '/tests/formatter/input.txt'), read(root .. '/tests/formatter/expected.txt'))
formatted('concatenation is still infix', 'local r=a..b..c', 'local r = a .. b .. c\n')
formatted('two-dot expansion', 'local f=do(..args):U32=add(1,..args)',
    'local f = do(..args): U32 = add(1, ..args)\n')
formatted('two-dot anonymous home', 'local f=do(..:T):T=(..)',
    'local f = do(..: T): T = (..)\n')
formatted('two-dot named opening', 'local f=do(ctx..:T):U32=x',
    'local f = do(..: T): U32 = x\n')
formatted('unused opened callback name', 'activity do(ctx..) tick() end',
    'activity do(..) tick end\n')
formatted('used opened callback name', 'activity do(ctx..) use ctx end',
    'activity do(ctx..) use ctx end\n')
formatted('opened name in a nested callback', 'activity do(ctx..) each do(v) use ctx end end',
    'activity do(ctx..) each do(v) use ctx end end\n')
formatted('opened name as assignment target', 'activity do(ctx..) ctx = replacement end',
    'activity do(ctx..) ctx = replacement end\n')
formatted('opening an existing receiver is a use', 'activity do(ctx..) local ctx.. end',
    'activity do(ctx..) local ctx.. end\n')
formatted('receiver name as a table value is a use', 'activity do(ctx..) use { ctx = ctx } end',
    'activity do(ctx..) use { .ctx } end\n')
formatted('receiver used in a nested type annotation', 'activity do(ctx..) local f = do(v: ctx): U32 = 0 end',
    'activity do(ctx..) local f = do(v: ctx): U32 = 0 end\n')
formatted('receiver used in a function declaration path', 'activity do(ctx..) function ctx.tick() end end',
    'activity do(ctx..) function ctx.tick() end end\n')
formatted('nested shadowed mentions are conservative', 'activity do(ctx..) each do(ctx) use ctx end end',
    'activity do(ctx..) each do(ctx) use ctx end end\n')
formatted('table keys are not receiver uses', 'activity do(ctx..) use { ctx = 1 } end',
    'activity do(..) use { ctx = 1 } end\n')
formatted('field names are not receiver uses', 'activity do(ctx..) use other.ctx end',
    'activity do(..) use other.ctx end\n')
formatted('literal text is not a receiver use', 'activity do(ctx..) use "ctx" end -- ctx',
    'activity do(..) use "ctx" end  -- ctx\n')
formatted('keep enclosing anonymous home lookup', 'activity do(ctx..) use((..)) end',
    'activity do(ctx..) use((..)) end\n', { call_style = 'preserve' })
formatted('keep internal home lookup', 'activity do(ctx..) use __home end',
    'activity do(ctx..) use __home end\n')
formatted('avoid duplicate home parameter', 'local f = do(ctx.., __home): U32 = 1',
    'local f = do(ctx.., __home): U32 = 1\n')
formatted('duplicate parameter names keep their binding order', 'local f = do(ctx.., ctx): U32 = value',
    'local f = do(ctx.., ctx): U32 = value\n')
formatted('rest parameter can hide the opened parameter', 'local f = do(ctx.., ..ctx): U32 = value',
    'local f = do(ctx.., ..ctx): U32 = value\n')
formatted('ordinary unused parameter stays', 'activity do(ctx) tick() end',
    'activity do(ctx) tick end\n')
formatted('preserve named opening', 'activity do(ctx..) tick() end',
    'activity do(ctx..) tick end\n', { opening_style = 'preserve' })
formatted('two-dot binding', 'local ctx..=value', 'local ctx.. = value\n')
formatted('spread operand concatenation', 'local r=f(..a..b)', 'local r = f(..a .. b)\n')
formatted('ordinary Lua varargs', 'local function f(...) return ... end',
    'local function f(...) return ... end\n')
formatted('minimal unary', 'local r=Ref(h)', 'local r = Ref h\n')
formatted('minimal chain', 'local r=f(a)(b)', 'local r = f a b\n')
formatted('multiple arguments stay one call', 'local r=f(a,b)', 'local r = f(a, b)\n')
formatted('expression grouping', 'local r=f(a+b)', 'local r = f(a + b)\n')
formatted('result suffix', 'local r=f(x).value', 'local r = f(x).value\n')
formatted('nil argument', 'local r=f(nil)', 'local r = f(nil)\n')
formatted('empty call', 'local r=f()', 'local r = f()\n')
formatted('bare call statements', 'refresh()\nscreen.refresh()\nscreen:refresh()',
    'refresh\nscreen.refresh\nscreen:refresh\n')
formatted('preserve empty calls', 'refresh()\nscreen:refresh()',
    'refresh()\nscreen:refresh()\n', { call_style = 'preserve' })
formatted('bare statements stay bare', 'refresh; save', 'refresh; save\n')
formatted('same-line calls remain separated', 'refresh() save()', 'refresh() save\n')
formatted('return still invokes explicitly', 'local f=do():U32 return answer() end',
    'local f = do(): U32 return answer() end\n')
formatted('return still refers to a callable', 'local f=function() return answer end',
    'local f = function() return answer end\n')
formatted('parenthesized callable bypass stays explicit', '(refresh)()', '(refresh)()\n')
formatted('indexed callable stays explicit', 'actions[i]()', 'actions[i]()\n')
formatted('comments survive bare statement calls', 'refresh(-- keep\n)', 'refresh  -- keep\n')
formatted('unary statement call', 'consume(value)', 'consume value\n')
formatted('multiline unary argument', 'local r=f(\n x\n)', 'local r = f x\n')
formatted('multiline call chain', 'local r=f(\n a\n)(\n b\n)', 'local r = f a b\n')
formatted('inline argument comment', 'local r=f(--[[ note ]] x)', 'local r = f  --[[ note ]] x\n')
formatted('trailing argument comment', 'local r=f(x -- keep\n)', 'local r = f x  -- keep\n')
formatted('leading line comment needs delimiters', 'local r=f(-- keep\n x)',
    'local r = f(  -- keep\n    x)\n')
formatted('typed argument groups stay intact', 'local f=do():U32 return g(a,b) end',
    'local f = do(): U32 return g(a, b) end\n')
formatted('preserve multiline call', 'local r=f(\n x\n)', 'local r = f(\n    x\n)\n',
    { call_style = 'preserve' })
formatted('host newline postfix call stays', 'refresh()\n(other)()', 'refresh()\n(other)()\n')
formatted('preserve calls', 'local r=Ref(h)', 'local r = Ref(h)\n', { call_style = 'preserve' })
formatted('table shorthand is kept and spaced', 'local t = P {.x,.y, z=3}\n', 'local t = P { .x, .y, z = 3 }\n')
formatted('the shorthand rewrites name = name', [[local f = do(x: U32, y: U32): P
    local a, x2 = x, y
    a, x = x, y
    return P { x = x, y = y, z = z }
end
local t = { x = x, y = y }
]], [[local f = do(x: U32, y: U32): P
    local a, x2 = x, y
    a, x = x, y
    return P { .x, .y, .z }
end
local t = { .x, .y }
]])
formatted('table_style preserve keeps name = name', 'local t = { x = x }\n', 'local t = { x = x }\n',
    { table_style = 'preserve' })
formatted('shorthand is the default', 'local t = { x = x, y = 2 }\n', 'local t = { .x, y = 2 }\n')
formatted('a host binding keeps its annotation-free form', 'local a = U32(0)\n', 'local a = U32 0\n')
formatted('unary operators', 'local r = - x + # xs', 'local r = -x + #xs\n')
formatted('minus cannot become comment', 'local r=- -x', 'local r = - -x\n')
formatted('integer suffix', 'local r=U64(0xffffffffffffffffULL)', 'local r = U64 0xffffffffffffffffULL\n')
formatted('application newline', 'f x\ng y\n', 'f x\ng y\n')
formatted('shebang and CRLF', '#!/usr/bin/env nua\r\nlocal x=1\r\n', '#!/usr/bin/env nua\r\nlocal x = 1\n')
formatted('labels', '::again::\ngoto again', '::again::\ngoto again\n')
formatted('does not execute source', 'error("must not run")', 'error "must not run"\n')
formatted('blank lines', '\n\nlocal x=1\n\n\n\nlocal y=2\n\n', 'local x = 1\n\nlocal y = 2\n')
formatted('two spaces', 'local f=do(x:U32):U32\nreturn x\nend',
    'local f = do(x: U32): U32\n  return x\nend\n', { indent_width = 2 })
-- endall spines: pure links flatten, other bodies keep their indent, and a run
-- of closers folds only where the chain is one spine inside a typed body.
formatted('spine flattens pure links', [[local import_words = do(n: U32): Unit
    counted(n) do
    counted(n) do
    counted(n) do
        insert n
    end
    end
    end
end
export import_words
]], [[local import_words = do(n: U32): Unit
    counted n do
    counted n do
    counted n do
        insert n
    endall
end
export import_words
]])
formatted('spine keeps impure bodies nested', [[local import_words = do(n: U32): Unit
    counted(n) do
    log(n)
    counted(n) do
        insert n
    end
    end
end
export import_words
]], [[local import_words = do(n: U32): Unit
    counted n do
        log n
        counted n do
            insert n
        endall
end
export import_words
]])
formatted('spine_style all flattens impure bodies', [[local import_words = do(n: U32): Unit
    counted(n) do
    log(n)
    counted(n) do
        insert n
    end
    end
end
export import_words
]], [[local import_words = do(n: U32): Unit
    counted n do
    log n
    counted n do
        insert n
    endall
end
export import_words
]], { spine_style = 'all' })
formatted('spine_style none keeps every body nested', [[local import_words = do(n: U32): Unit
    counted(n) do
    counted(n) do
        insert n
    end
    end
end
export import_words
]], [[local import_words = do(n: U32): Unit
    counted n do
        counted n do
            insert n
        endall
end
export import_words
]], { spine_style = 'none' })
formatted('a comment between closers blocks folding', [[local import_words = do(n: U32): Unit
    counted(n) do
    counted(n) do
        insert n
    end  -- keep
    end
end
export import_words
]], [[local import_words = do(n: U32): Unit
    counted n do
        counted n do
            insert n
        end  -- keep
    end
end
export import_words
]])
formatted('host spines keep their ends', [[local host = do
    f(do
        return 1
    end)
end
]], [[local host = do
    f do
        return 1
    end
end
]])
formatted('a lone trailing block keeps end', [[local import_words = do(n: U32): Unit
    counted(n) do
        insert n
    end
end
export import_words
]], [[local import_words = do(n: U32): Unit
    counted n do
        insert n
    end
end
export import_words
]])
formatted('preserve keeps end runs', [[local import_words = do(n: U32): Unit
    counted(n) do
    counted(n) do
        insert n
    end
    end
end
export import_words
]], [[local import_words = do(n: U32): Unit
    counted(n) do
        counted(n) do
            insert n
        end
    end
end
export import_words
]], { call_style = 'preserve' })
local long = 'local x = { first_value, second_value, third_value, fourth_value }\n'
local wrapped = fmt.format(long, { column_width = 30 })
check('soft width wraps list', wrapped:find(',\n', 1, true) ~= nil, wrapped)
check('wrapped list is stable', fmt.format(wrapped, { column_width = 30 }) == wrapped)
formatted('application stays on one line', 'local x = very_long_function first_value second_value third_value',
    'local x = very_long_function first_value second_value third_value\n', { column_width = 30 })
local literal = 'local s=[==[\n  literal\n\tbytes -- not a comment\n]==]\n--[=[\n  comment\n]=]\n'
local out = fmt.format(literal)
local function protected(text)
    local result = {}
    for _, tk in ipairs(lex.scan(text, 'protected')) do
        if tk.t == 'string' or tk.t == 'comment' then result[#result + 1] = tk.v end
    end
    return table.concat(result, '\0')
end
check('literal and comment bytes unchanged', protected(literal) == protected(out))
local opening_comment = 'activity do(ctx -- receiver comment\n..) tick() end\n'
local anonymous_comment = fmt.format(opening_comment)
check('opening rewrite preserves comments', protected(opening_comment) == protected(anonymous_comment))
check('commented opened name removed', not anonymous_comment:find('ctx', 1, true), anonymous_comment)
check('commented opening is stable', fmt.format(anonymous_comment) == anonymous_comment)
check('comments in calls keep parentheses', fmt.format('local r = f( -- why\nx)\n'):find('f(  -- why', 1, true) ~= nil)
for _, settings in ipairs { { indent_width = 0 }, { column_width = 10 }, { call_style = 'lua' }, { surprise = true }, { indent_width = false }, { spine_style = 'flat' }, { table_style = 'sugar' }, { opening_style = 'always' } } do
    local ok = pcall(fmt.format, 'local x=1', settings)
    check('reject invalid config', not ok)
end
check('reject invalid syntax', not pcall(fmt.format, 'local =', nil, 'broken.nua'))


-- LuaJIT 3.0 syntax: the conditional, safe navigation, short functions
formatted('a conditional is spaced', 'local x=a?b:c\n', 'local x = a ? b : c\n')
formatted('safe navigation touches', 'local x=a?.b?.c ?? d\n', 'local x = a?.b?.c ?? d\n')
formatted('short functions', 'local f=|a,b|->a+b\nlocal g=x->x*2\n', 'local f = |a, b| -> a + b\nlocal g = x -> x * 2\n')
formatted('a short function with a block', 'local f=|x|->do\n    return x\nend\n', 'local f = |x| -> do\n    return x\nend\n')

formatted('a block with no parameters keeps its do', 'local f = do()\n    return 1\nend\nedit document do(..)\n    go\nend\n',
    'local f = do()\n    return 1\nend\nedit document:\n    go\nend\n')

-- `return:` returns a block
formatted('return do(names) is written return:', 'local f = do(a)\n    return do(body)\n        go body\n    end\nend\n',
    'local f =: a\n    return: body\n        go body\n    end\nend\n')
formatted('return: stays', 'local f =: a\n    return: body\n        go body\n    end\nend\n',
    'local f =: a\n    return: body\n        go body\n    end\nend\n')
formatted('return of an expression lambda is an arrow', 'local f = do(a)\n    return do(x) = x + a\nend\n',
    'local f =: a\n    return x -> x + a\nend\n')

-- lambda_style: a plain `do(a, b) = e` is the short function `|a, b| -> e`
formatted('one name', 'local f = do(x) = x * 2\n', 'local f = x -> x * 2\n')
formatted('several names', 'local g = do(a, b) = a + b\n', 'local g = |a, b| -> a + b\n')
formatted('no names', 'local z = do() = 1\n', 'local z = || -> 1\n')
formatted('a curried lambda', 'local add = do(a) = do(b) = a + b\n', 'local add = a -> b -> a + b\n')
formatted('one name stays a juxtaposed argument', 'map xs do(x) = x + 1\n', 'map xs x -> x + 1\n')
formatted('several names are bracketed after an operand', 'map xs do(a, b) = a + b\n', 'map xs (|a, b| -> a + b)\n')
formatted('in a table', 'local t = { found = do(i) = i, missing = do() = -1 }\n', 'local t = { found = i -> i, missing = || -> -1 }\n')
formatted('an opened parameter has no arrow', 'local f = do(ctx..) = x\n', 'local f = do(..) = x\n')
formatted('a block body keeps its do', 'local f = do(x)\n    return x\nend\n', 'local f =: x\n    return x\nend\n')
formatted('lambda_style do keeps do', 'local f = do(x) = x * 2\n', 'local f = do(x) = x * 2\n', { lambda_style = 'do' })
check('an invalid lambda_style is rejected', not pcall(fmt.format, 'local x=1', { lambda_style = 'fn' }))

-- a with or define block as a call argument: no space after the bracket, entries one unit in
formatted('a define block as the argument', 'local keymap = do(body)\n    body(define\n        bind = do(key) = do(command)\n            go key\n        end\n    end)\nend\n',
    'local keymap =: body\n    body define\n        bind = do(key) = do(command)\n            go key\n        end\n    end\nend\n')
formatted('a with block as the argument', 'local x = f(Point with\n    x = 1\n    y = 2\n    z = 3\nend)\n',
    'local x = f(Point with\n    x = 1\n    y = 2\n    z = 3\nend)\n')
formatted('a define block among arguments', 'local x = f(a, define\n    x = 1\n    y = 2\nend, b)\n',
    'local x = f(a, define\n    x = 1\n    y = 2\nend, b)\n')

-- define: `define` entries `end` is a table
formatted('define is a block and stays one', 'local d = define\n    length = 0\n    cursor = 0\nend\n',
    'local d = define\n    length = 0\n    cursor = 0\nend\n')
formatted('a short define is not collapsed', 'local d = define\n    length = 0\nend\n', 'local d = define\n    length = 0\nend\n')
formatted('a table in braces stays in braces', 'local d = {\n    length = 0,\n    cursor = 0,\n}\n',
    'local d = {\n    length = 0,\n    cursor = 0,\n}\n')
formatted('define as an argument', 'local n = closed define\n    op = "s"\n    place = required\nend\n',
    'local n = closed define\n    op = "s"\n    place = required\nend\n')
formatted('define is not contextual with', 'local w = with\n    x = 1\n    y = 2\n    z = 3\nend\nlocal d = define\n    x = 1\nend\n',
    'local w = with\n    x = 1\n    y = 2\n    z = 3\nend\nlocal d = define\n    x = 1\nend\n')

-- define holds lists: positional entries, one per line, without commas
formatted('a list of numbers', 'local t = define\n    1,\n    2,\n    3\nend\n', 'local t = define\n    1\n    2\n    3\nend\n')
formatted('a list of tables', 'local t = define\n    { x = 1 },\n    { x = 2 }\nend\n', 'local t = define\n    { x = 1 }\n    { x = 2 }\nend\n')
formatted('a list of functions', 'local t = define\n    do(x) = x + 1\n    x -> x * 2\nend\n', 'local t = define\n    x -> x + 1\n    x -> x * 2\nend\n')
formatted('a list of calls', 'local t = define\n    f(1)\n    f(2)\nend\n', 'local t = define\n    f 1\n    f 2\nend\n')
formatted('a list mixed with keys', 'local t = define\n    "a"\n    "b"\n    n = 2\nend\n', 'local t = define\n    "a"\n    "b"\n    n = 2\nend\n')

-- spread_style: one `..base` among a table's entries is written first, beside the `with` or `define`
formatted('a single spread stays beside the with', 'local d = define ..Document\n    length = 10\nend\n',
    'local d = define ..Document\n    length = 10\nend\n')
formatted('a single spread moves to the top', 'local d = define\n    length = 10\n    ..Document\n    cursor = 2\nend\n',
    'local d = define ..Document\n    length = 10\n    cursor = 2\nend\n')
formatted('a last spread moves to the top', 'local d = define\n    length = 10\n    cursor = 2\n    ..Document\nend\n',
    'local d = define ..Document\n    length = 10\n    cursor = 2\nend\n')
formatted('a first spread goes beside the with', 'local d = define\n    ..Document\n    length = 10\n    cursor = 2\n    edits = 3\nend\n',
    'local d = define ..Document\n    length = 10\n    cursor = 2\n    edits = 3\nend\n')
formatted('several spreads stay as written', 'local d = define\n    ..A\n    ..B\n    length = 10\nend\n',
    'local d = define\n    ..A\n    ..B\n    length = 10\nend\n')
formatted('a spread stays behind an entry that does something', 'local d = define\n    length = compute()\n    ..Document\nend\n',
    'local d = define\n    length = compute()\n    ..Document\nend\n')
formatted('a one-line table with a spread is left alone', 'local p = Point { ..p, x = p.x + dx }\n', 'local p = Point { ..p, x = p.x + dx }\n')
formatted('spread_style preserve keeps the order', 'local d = define\n    length = 10\n    ..Document\n    cursor = 2\nend\n',
    'local d = define\n    length = 10\n    ..Document\n    cursor = 2\nend\n', { spread_style = 'preserve' })
check('an invalid spread_style is rejected', not pcall(fmt.format, 'local x=1', { spread_style = 'bottom' }))

-- CLI: output, explicit write, CI status, discovery, and failed preflight.
local build = root .. '/build/formatter-tests'
assert(os.execute('mkdir -p ' .. q(build .. '/nested')) == 0)
local source_path = build .. '/nested/input.mua'
local bad_path = build .. '/nested/bad.mua'
local cfg = build .. '/.muafmt.lua'
local bad_cfg = build .. '/bad-config.lua'
write(source_path, 'local r=Ref(h)')
write(cfg, 'return { indent_width = 2, column_width = 80, call_style = "preserve" }\n')
write(bad_path, 'local =')
write(bad_cfg, 'return { call_style = "wrong" }\n')
local cli = 'timeout 60 ' .. q(arg[-1] or 'luajit') .. ' ' .. q(root .. '/mua.lua') .. ' fmt '
local text, rc = capture(cli .. q(source_path))
check('CLI stdout and nearest config', rc == 0 and text == 'local r = Ref(h)\n', text)
check('stdout does not modify source', read(source_path) == 'local r=Ref(h)')
text, rc = capture(cli .. '--check ' .. q(source_path))
check('check changed status', rc == 1 and text:find(source_path, 1, true), text)
text, rc = capture(cli .. '--write ' .. q(source_path) .. ' ' .. q(bad_path))
check('bad input fails preflight', rc == 2 and read(source_path) == 'local r=Ref(h)', text)
text, rc = capture(cli .. '--write ' .. q(source_path))
check('write applies formatting', rc == 0 and read(source_path) == 'local r = Ref(h)\n', text)
text, rc = capture(cli .. '--check ' .. q(source_path))
check('check clean status', rc == 0 and text == '', text)
text, rc = capture(cli .. '--config ' .. q(bad_cfg) .. ' ' .. q(source_path))
check('invalid config fails', rc == 2 and text:find('call_style', 1, true), text)
text, rc = capture('printf ' .. q('local r=Ref(h)') .. ' | ' .. cli .. '-')
check('stdin to stdout', rc == 0 and text == 'local r = Ref h\n', text)
for _, options in ipairs { '--write -', '--write --check ' .. q(source_path), '--unknown', '--config', q(source_path) .. ' ' .. q(bad_path) } do
    text, rc = capture(cli .. options)
    check('CLI invalid options', rc == 2, text)
end

print(('%d formatter checks passed'):format(passed))
