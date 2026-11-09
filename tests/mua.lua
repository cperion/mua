-- Mua's tests: lexer, parser, emitter, contracts, struct and oneof, then every Lua source of
-- this repository through the pipeline. Run from the repository root:
--   luajit tests/mua.lua
local root = arg[0]:match('^(.*)/tests/[^/]*$') or '.'
package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path
local lex = require 'mua.lex'

local passed, failed = 0, 0
local function check(name, ok, detail)
    if ok then passed = passed + 1
    else failed = failed + 1; print('FAIL  Mua: ' .. name .. (detail and ('\n' .. tostring(detail)) or '')) end
end

-- the significant tokens of a source, as "kind:text" strings
local function kinds(src)
    local out = {}
    for _, tk in ipairs(lex.scan(src, 't')) do
        if tk.t ~= 'space' and tk.t ~= 'comment' and tk.t ~= 'eof' then out[#out + 1] = tk.t .. ':' .. tk.v end
    end
    return table.concat(out, ' ')
end
local function tokens_are(name, src, expect)
    local ok, got = pcall(kinds, src)
    check('tokens: ' .. name, ok and got == expect, ok and ('got    ' .. got .. '\nexpect ' .. expect) or got)
end
local function rejects(name, src, expect)
    local ok, e = pcall(lex.scan, src, 't')
    check('rejects: ' .. name, not ok and tostring(e):find(expect, 1, true), ok and 'scanned' or e)
end

tokens_are('names and keywords', 'local goto_x = goto end_',
    'keyword:local name:goto_x =:= keyword:goto name:end_')
tokens_are('operators longest first', 'a...b..c.d==e<=f>=g~=h::i::',
    'name:a ...:... name:b ..:.. name:c .:. name:d ==:== name:e <=:<= name:f >=:>= name:g ~=:~= name:h ::::: name:i :::::')
tokens_are('Mua colons stay single', 'f x: key =: y',
    'name:f name:x ::: name:key =:= ::: name:y')
tokens_are('numbers', '1 1.5 .5 5. 1e5 1E-5 0x1F 0x1p4 0x.8P-1 42ULL 7ll 0x10ULL 3i 2.5i',
    'number:1 number:1.5 number:.5 number:5. number:1e5 number:1E-5 number:0x1F number:0x1p4 '
    .. 'number:0x.8P-1 number:42ULL number:7ll number:0x10ULL number:3i number:2.5i')
tokens_are('a hex e is a digit, not an exponent', '0x1e-1', 'number:0x1e -:- number:1')
tokens_are('strings', [===["a\"b" 'c\'d' "e\
f" [[x]] [==[y]]z]==] ]===],
    [===[string:"a\"b" string:'c\'d' string:"e\
f" string:[[x]] string:[==[y]]z]==]]===])
tokens_are('a bracket that opens no long string', 'a[1] b[ [=[s]=] ]',
    'name:a [:[ number:1 ]:] name:b [:[ string:[=[s]=] ]:]')
tokens_are('high bytes in names', 'local \206\187 = 1', 'keyword:local name:\206\187 =:= number:1')
tokens_are('a shebang line', '#!/usr/bin/env luajit\nreturn 1', 'shebang:#!/usr/bin/env luajit keyword:return number:1')

rejects('a malformed number', 'x = 1..2', "t:1: malformed number near '1..2'")
rejects('a suffix on a float', 'x = 1.5ULL', 'malformed number')
rejects('an unfinished string', 'x = "abc\ny', 't:1: unfinished string')
rejects('an unfinished long string', 'x = [==[abc]=]', 'unfinished long string')
rejects('an unfinished long comment', '--[[ abc', 'unfinished long comment')
rejects('a bad long bracket', 'x = [==x', 'invalid long string delimiter')
tokens_are('bitwise operators', 'a ~ ~b << 1 >> 2 & c | d ~= e',
    'name:a ~:~ ~:~ name:b <<:<< number:1 >>:>> number:2 &:& name:c |:| name:d ~=:~= name:e')
rejects('an unexpected symbol', 'x = a @ b', "unexpected symbol near '@'")
tokens_are('LuaJIT 3.0 operators', 'a != b && !c || d ?? e ? f : g?.h ~>> 1 |x| -> x || -> 1',
    'name:a !=:!= name:b &&:&& !:! name:c ||:|| name:d ??:?? name:e ?:? name:f ::: name:g ?.:?. name:h '
    .. '~>>:~>> number:1 |:| name:x |:| ->:-> name:x ||:|| ->:-> number:1')
tokens_are('compound assignments', 'a += 1 b -= 1 c *= 1 d /= 1 e %= 1 f &= 1 g |= 1 h ~= 1 i <<= 1 j >>= 1 k ~>>= 1 l ..= 1',
    'name:a +=:+= number:1 name:b -=:-= number:1 name:c *=:*= number:1 name:d /=:/= number:1 name:e %=:%= number:1 '
    .. 'name:f &=:&= number:1 name:g |=:|= number:1 name:h ~=:~= number:1 name:i <<=:<<= number:1 name:j >>=:>>= number:1 '
    .. 'name:k ~>>=:~>>= number:1 name:l ..=:..= number:1')
tokens_are('underscores and binary', '1_000 0xff_ff 1e1_0 1_0ULL 0b101 0B101LL 0b1_0 1_',
    'number:1_000 number:0xff_ff number:1e1_0 number:1_0ULL number:0b101 number:0B101LL number:0b1_0 number:1_')
tokens_are('a line directive in column 1', 'x = 1\n# 100 "f.lua"\ny = #t',
    'name:x =:= number:1 directive:# 100 "f.lua" name:y =:= #:# name:t')
rejects('a binary digit out of range', 'x = 0b102', 'malformed number')
rejects('a stray character', 'x = $', "t:1: unexpected symbol near '$'")

-- positions: lines across every kind of line break, columns in bytes
do
    local ts = lex.scan('a\r\nb\n\rc\rd\n--[[x\ny]] e "f\\\ng" h', 't')
    local at = {}
    for _, tk in ipairs(ts) do if tk.t == 'name' or tk.t == 'string' then at[#at + 1] = tk.v .. '@' .. tk.line .. ':' .. tk.col end end
    local got = table.concat(at, ' ')
    check('positions', got == 'a@1:1 b@2:1 c@3:1 d@4:1 e@6:5 "f\\\ng"@6:7 h@7:4', got)
end

-- the parser ---------------------------------------------------------------------------------
local parse = require 'mua.parse'

-- a compact form of an expression or statement: calls as f(a)(b), lambdas as fn(p)
local show
local function list(xs) local o = {} for i, x in ipairs(xs or {}) do o[i] = show(x) end return table.concat(o, ', ') end
local function fnshow(fn)
    local ps = {}
    for i, p in ipairs(fn.params) do ps[i] = (p.unnamed and '..' or p.name) .. (p.opened and not p.unnamed and '..' or '') end
    if fn.vararg then ps[#ps + 1] = '...' end
    local head = (fn.arrow and 'arrow' or (fn.colon and 'colon' or 'fn')) .. '(' .. table.concat(ps, ' ') .. ')'
    if fn.result then head = head .. ':' .. show(fn.result) end
    if fn.expr then return head .. '=' .. show(fn.expr) end
    return head .. '{' .. list(fn.body) .. '}'
end
local function items(its)
    local o = {}
    for i, it in ipairs(its) do
        if it.kind == 'named' then o[i] = it.name .. '=' .. show(it.e)
        elseif it.kind == 'keyed' then o[i] = '[' .. show(it.key) .. ']=' .. show(it.e)
        elseif it.kind == 'spread' then o[i] = '..' .. show(it.e)
        else o[i] = show(it.e) end
    end
    return table.concat(o, ', ')
end
function show(n)
    local k = n.k
    if k == 'name' then return n.name
    elseif k == 'num' or k == 'str' then return n.text
    elseif k == 'nil' or k == 'true' or k == 'false' then return k
    elseif k == 'vararg' then return '...'
    elseif k == 'home' then return '..'
    elseif k == 'paren' then return n.literal and show(n.e) or ('(' .. show(n.e) .. ')')
    elseif k == 'field' then return show(n.obj) .. (n.safe and '?.' or '.') .. n.name
    elseif k == 'index' then return show(n.obj) .. (n.safe and '?.' or '') .. '[' .. show(n.key) .. ']'
    elseif k == 'call' then return show(n.fn) .. (n.safe and '?.' or '') .. '(' .. list(n.args) .. ')'
    elseif k == 'method' then return show(n.obj) .. (n.safe and '?.:' or ':') .. n.name .. (n.safe_call and '?.' or '') .. '(' .. list(n.args) .. ')'
    elseif k == 'lambda' then return fnshow(n.fn)
    elseif k == 'table' then return (n.with and 'with{' or '{') .. items(n.items) .. '}'
    elseif k == 'with' then return 'ctx{' .. items(n.items) .. '}'
    elseif k == 'spread' then return '..' .. show(n.e)
    elseif k == 'binop' then return '(' .. show(n.a) .. ' ' .. n.op .. ' ' .. show(n.b) .. ')'
    elseif k == 'unop' then return '(' .. n.op .. ' ' .. show(n.a) .. ')'
    elseif k == 'cond' then return '(' .. show(n.c) .. ' ? ' .. show(n.a) .. ' : ' .. show(n.b) .. ')'
    elseif k == 'struct' then
        local o = {}
        for i, f in ipairs(n.fields) do o[i] = f.name .. ':' .. show(f.type) end
        return (n.sum and 'oneof' or 'struct') .. '{' .. table.concat(o, ', ') .. '}'
    elseif k == 'callstat' then return show(n.e)
    elseif k == 'assign' then return list(n.targets) .. ' = ' .. list(n.exprs)
    elseif k == 'compound' then return show(n.target) .. ' ' .. n.op .. '= ' .. show(n.e)
    elseif k == 'local' or k == 'const' then
        local o = {}
        for i, v in ipairs(n.names) do o[i] = v.name .. (v.type and (':' .. show(v.type)) or '') end
        return k .. ' ' .. table.concat(o, ', ') .. (#n.exprs > 0 and (' = ' .. list(n.exprs)) or '')
    elseif k == 'localfunction' then return (n.const and 'const ' or 'local ') .. 'function ' .. n.name .. ' ' .. fnshow(n.fn)
    elseif k == 'function' then return 'function ' .. table.concat(n.path, '.') .. (n.method and (':' .. n.method) or '') .. ' ' .. fnshow(n.fn)
    elseif k == 'return' then return 'return ' .. list(n.exprs)
    elseif k == 'open' then return 'open ' .. n.name .. (n.init and (' = ' .. show(n.init)) or '')
    elseif k == 'if' then return 'if ' .. show(n.clauses[1].cond) .. ' {' .. list(n.clauses[1].body) .. '}' .. (n.els and (' else {' .. list(n.els) .. '}') or '')
    elseif k == 'while' then return 'while ' .. show(n.cond) .. ' {' .. list(n.body) .. '}'
    elseif k == 'genfor' then return 'for ' .. table.concat(n.names, ',') .. ' in ' .. list(n.exprs) .. ' {' .. list(n.body) .. '}'
    elseif k == 'numfor' then return 'for ' .. n.var .. ' {' .. list(n.body) .. '}'
    elseif k == 'do' then return 'do {' .. list(n.body) .. '}'
    elseif k == 'label' then return '::' .. n.name .. '::'
    elseif k == 'goto' then return 'goto ' .. n.label
    elseif k == 'continue' or k == 'break' then return k
    end
    return '<' .. tostring(k) .. '>'
end
local function parses(name, src, expect)
    local ok, block = pcall(parse.parse, src, 't')
    local got = ok and list(block) or block
    check('parses: ' .. name, ok and got == expect, 'got    ' .. tostring(got) .. '\nexpect ' .. expect)
end
local function parse_rejects(name, src, expect)
    local ok, e = pcall(parse.parse, src, 't')
    check('parse rejects: ' .. name, not ok and tostring(e):find(expect, 1, true), ok and 'parsed' or e)
end

-- syntax.md §2.4
parses('juxtaposition', 'f a b', 'f(a)(b)')
parses('literal arguments across lines', 'f 1\n  "x"', 'f(1)("x")')
parses('a newline ends a name chain', 'f a\ng b', 'f(a), g(b)')
parses('an argument is a primary with its chain', 'f a.b x', 'f(a.b)(x)')
parses('a string argument takes its chain', 'f "x":rep 3', 'f("x":rep(3))')
parses('a literal chain stops at a table', 'f 21 {}', 'f(21)({})')
parses('a spaced group is the next argument', 'f a (b + 1)', 'f(a)((b + 1))')
parses('names go on after a spaced group', 'f (g x) y', 'f(g(x))(y)')
parses('an attached call ends the name chain', 'f a(b) x', 'f(a(b)), x()')
parses('application binds tighter than operators', 'x = f a + 1', 'x = (f(a) + 1)')
parses('a loop header ends at its do', 'for x in xs do f x end', 'for x in xs {f(x)}')
parses('a lambda argument', 'f(x) do(p) g p end', 'f(x)(fn(p){g(p)})')
parses('a statement do is Lua\'s', 'x = 1 do f() end', 'x = 1, do {f()}')
parses('zero-argument call statements', 'refresh\nscreen.refresh\nscreen:refresh', 'refresh(), screen.refresh(), screen:refresh()')
parses('field shorthand', 'p = P { .x, .y, z = 3 }', 'p = P({x=x, y=y, z=3})')
parses('keyed spread', 't = { ..a, k = 1 }', 't = {..a, k=1}')
parses('trailing colon', 'with_buffer n:\n  use n\nend', 'with_buffer(n)(colon(..){use(n)})')
parses('a trailing colon on a method', 'xs:each:\n  f k v\nend', 'xs:each(colon(..){f(k)(v)})')
parses('a do lambda names parameters', 'xs:each do(k, v)\n  f k v\nend', 'xs:each(fn(k v){f(k)(v)})')
parses('a do lambda opens a name', 'tasks do(scope..)\n  go\nend', 'tasks(fn(scope..){go()})')
parses('a block argument goes on applying', 'r = apply do(v)\n  return v\nend x', 'r = apply(fn(v){return v})(x)')
parses('a do lambda assigns a block', 'local f = do(x)\n  return x\nend', 'local f = fn(x){return x}')
parses('with block', 'p = P with\n  x = 1\n  .y\n  z = f a\nend', 'p = P(with{x=1, y=y, z=f(a)})')
parses('a spread on its own line is the next entry', 't = define\n  ..a\n  ..b\nend', 't = {..a, ..b}')
parses('with entries stop at the next entry', 'p = P with x = a y = b end', 'p = P(with{x=a, y=b})')
parses('contextual with', 'return with\n  x = 1\nend', 'return ctx{x=1}')
parses('with as a name', 'x = with + 1', 'x = (with + 1)')
parses('a handler entry', 'r = s with\n  done() = 0\n  failed(e) = e\nend', 'r = s(with{done=fn()=0, failed=fn(e)=e})')
parses('an applied result type in a with entry', 'r = s with\n  a = do(c: C): Ref U32 = Ref c.x\n  b = do(d: D): Ref U32 = d\nend\nreturn r',
    'r = s(with{a=fn(c):Ref(U32)=Ref(c.x), b=fn(d):Ref(U32)=d}), return r')
parses('endall closes the spine', 'outer:each:\n  inner:each:\n    f a b\nendall\ng()',
    'outer:each(colon(..){inner:each(colon(..){f(a)(b)})}), g()')
parses('endall stops at a typed word', 'local w = do(): U32\n  xs:each do(a)\n    f a\n  end\n  return 1\nend',
    'local w = fn():U32{xs:each(fn(a){f(a)}), return 1}')
parses('struct and oneof', 'local P = struct { x: F32, y: F32 }\nlocal S = oneof\n  a: Unit\n  b: U32\nend',
    'local P = struct{x:F32, y:F32}, local S = oneof{a:Unit, b:U32}')
parses('typed word', 'local f = do(x: U32): U32 = x + 1', 'local f = fn(x):U32=(x + 1)')
parses('opening', 'local ctx.. = e\nf do(..) g end', 'open ctx = e, f(fn(..){g()})')
parses('continue', 'for i = 1, 2 do continue end', 'for i {continue}')
parse_rejects('endall outside', 'endall', "'endall' closes no open lambda")
parse_rejects('a typed parameter without a result', 'f = do(x: U32) = x', 'need a result type')

-- LuaJIT 3.0's syntax (design macro-layer.md L1, L2)
parses('customary operators are normalized', 'x = !a && b || c != d', 'x = (((not a) and b) or (c ~= d))')
parses('?? with or', 'x = a ?? b and c', 'x = (a ?? (b and c))')
parses('bit operators', 'x = ~a & b | c ~ d << 1 ~>> 2', 'x = (((~ a) & b) | (c ~ ((d << 1) ~>> 2)))')
parses('.. binds tighter than shifts', 'x = 1 << 2 .. s', 'x = (1 << (2 .. s))')
parses('conditional', 'x = c ? a : b', 'x = (c ? a : b)')
parses('conditional is right-associative', 'x = c ? a : d ? b : e', 'x = (c ? a : (d ? b : e))')
parses('a conditional at the end of a line is not a block colon', 'x = c ? a : b\ny = 1', 'x = (c ? a : b), y = 1')
parses('safe navigation', 'x = t?.a?.[k]?.(1)\no?.:m(2)\no:m?.(3)', 'x = t?.a?.[k]?.(1), o?.:m(2), o:m?.(3)')
parses('short functions', 'f = |a, b| -> a + b\ng = x -> x * 2\nh = || -> 7\nv = |...| -> select(1, ...)',
    'f = arrow(a b)=(a + b), g = arrow(x)=(x * 2), h = arrow()=7, v = arrow(...)=select(1, ...)')
parses('a short function block', 'f = |x| -> do return x end', 'f = arrow(x){return x}')
parses('name -> as a juxtaposed argument', 'map xs x -> x * 2', 'map(xs)(arrow(x)=(x * 2))')
parses('compound assignment', 'a += 1\nt.n ..= "x"\nb ~= 3\nc ~>>= 2', 'a += 1, t.n ..= "x", b ~= 3, c ~>>= 2')
parses('~= in an expression is not equal', 'x = a ~= b', 'x = (a ~= b)')
parses('const', 'const X = 1\nconst A, B = 1, 2\nconst function f() end', 'const X = 1, const A, B = 1, 2, const function f fn(){}')
parses('const as a name', 'local const = 5\nconst = 6', 'local const = 5, const = 6')
parses('semicolons anywhere', ';; f();; do return;; end', 'f(), do {return }')
parses('goto and labels', 'goto a\n::a::', 'goto a, ::a::')
parse_rejects('a parallel compound assignment', 'a, b += 1, 1', "'=' expected")
parse_rejects('a block colon with parameters', 'xs:each: k v\n  f k v\nend',
    "a block colon takes no parameters; write 'do(k, v) ... end' after the call")
parse_rejects('a block colon opening a name', 'tasks: scope..\n  go\nend',
    "a block colon takes no parameters; write 'do(scope..) ... end' after the call")
parse_rejects('an assigned block', 'local f =: x\n  return x\nend',
    "an assigned block is written '= do(x) ... end', not '=:'")
parse_rejects('an assigned block opening the home', 'local f =:\n  go\nend',
    "an assigned block is written '= do(..) ... end', not '=:'")
parse_rejects('a returned block', 'return: b\n  go\nend',
    "a returned block is written 'return do(b) ... end', not 'return:'")
parse_rejects('a returned block opening the home', 'return:\n  go\nend',
    "a returned block is written 'return do(..) ... end', not 'return:'")

-- the emitter: Mua programs run as plain Lua ------------------------------------------------
local mua = require 'mua.init'
local function runs(name, src, expect)
    local chunk, err = mua.load(src, '=' .. name)
    if not chunk then return check('runs: ' .. name, false, err) end
    local ok, got = pcall(chunk)
    check('runs: ' .. name, ok and got == expect, ok and ('got ' .. tostring(got) .. ', expected ' .. tostring(expect)) or got)
end
local function fails_at(name, src, line)
    local chunk, err = mua.load(src, '=' .. name)
    if not chunk then return check('fails at: ' .. name, false, err) end
    local ok, e = pcall(chunk)
    check('fails at: ' .. name, not ok and tostring(e):find(':' .. line .. ':', 1, true), ok and 'ran' or e)
end

runs('juxtaposition', 'local add = do(a) = do(b) = a + b\nreturn add 1 2', 3)
runs('a string argument takes its chain', 'local id = do(x) = x\nreturn id "ab":rep 2', 'abab')
runs('block lambda', 'local function twice(f) return f() * 2 end\nreturn twice do\n  return 21\nend', 42)
runs('trailing colon', 'local function with_value(v) return function(f) return f(v) end end\nreturn with_value 20 do(x)\n  return x + 1\nend', 21)
runs('a do lambda assigns a block', 'local f = do(x)\n  return x * 3\nend\nreturn f(5)', 15)
runs('zero-argument call statement', 'local n = 0\nlocal function bump() n = n + 1 end\nbump\nbump\nreturn n', 2)
runs('with block', 'local function P(t) return t end\nlocal p = P with\n  x = 1\n  y = 2\nend\nreturn p.x + p.y', 3)
runs('field shorthand', 'local x, y = 3, 4\nlocal t = { .x, .y }\nreturn t.x * t.y', 12)
runs('keyed spread', 'local base = { a = 1, b = 2 }\nlocal t = { ..base, b = 5 }\nreturn t.a + t.b', 6)
parse_rejects = parse_rejects
do
    local ok, e = pcall(mua.translate, 't = { ..a, x = 1, x = 2 }', 't')
    check('a duplicated field beside a spread', not ok and tostring(e):find("duplicate field 'x'", 1, true), e)
end
runs('an explicit field resolves a clash between spreads', 'local t = { ..{ a = 1, b = 1 }, ..{ a = 2 }, a = 3 }\nreturn t.a + t.b', 4)
runs('meta composes vocabularies, an explicit entry settles a clash', [[
local Printable = define
    tostring = self -> self.name
end
local Loud = define
    tostring = self -> "LOUD"
end
local P = meta with
    ..Printable
    ..Loud
    tostring = self -> "mine"
end with
    name = "x"
end
return tostring(P)]], 'mine')
runs('keyed spread overlap', 'local ok = pcall(function() return { ..{ a = 1 }, ..{ a = 2 } } end)\nreturn ok', false)
runs('contextual with is a table', 'local t = with\n  k = 7\nend\nreturn t.k', 7)
runs('a do block after a call begins a statement', 'local function plain() return 7 end\nlocal total = plain()\ndo\n  total += 1\nend\nreturn total', 8)
runs('a do lambda continuing the line is an argument', 'local function apply(f) return f(2) end\nreturn apply do(x) return x * 3 end', 6)
runs('opening reads members', 'local ctx = { a = 10 }\nlocal f = do(..) return a + 1 end\nreturn f(ctx)', 11)
runs('opening calls members', 'local v = { double = function(x) return x * 2 end }\nlocal f = do(..) return double 4 end\nreturn f(v)', 8)
runs('opening writes members it introduces', 'local ctx = { n = 1 }\nlocal f = do(..) n = n + 1 end\nf(ctx)\nreturn ctx.n', 2)
runs('an opening compound-assigns the member it introduces', 'local ctx = { n = 1, t = "a" }\nlocal f = do(..)\n  n += 4\n  t ..= "b"\n  return n\nend\nlocal n = f(ctx)\nreturn n * 10 + #ctx.t', 52)
runs('an opening compound-assigns the innermost member', 'local outer = { n = 1 }\nlocal inner = { n = 2 }\nlocal f = do(o, i)\n  local o..\n  local i..\n  n += 10\n  return n\nend\nreturn f(outer, inner) * 10 + inner.n', 132)
runs('opening writes other names where Lua would', 'local ctx = {}\nlocal f = do(..) fresh_global_x = 4 end\nf(ctx)\nlocal v = fresh_global_x\nfresh_global_x = nil\nreturn v', 4)
runs('a local shadows an opening', 'local ctx = { a = 1 }\nlocal f = do(..)\n  local a = 5\n  return a\nend\nreturn f(ctx)', 5)
runs('local ctx.. opens', 'local v = { k = 9 }\nlocal ctx.. = v\nreturn k', 9)
runs('a spread of a call in an initializer', 'local function pair(x) return x, x + 1 end\nlocal a, b = ..pair 1\nreturn a + b', 3)
runs('rest parameters', 'local f = do(..args) = args.n\nreturn f(1, 2, 3)', 3)
runs('spread in a call', 'local t = { 1, 2, 3 }\nreturn select("#", print and nil, ..t)', 4)
runs('LuaJIT 3.0 forms', 'local t = nil\nlocal a = t?.x ?? 5\nlocal f = |x| -> x * 2\nlocal b = a > 3 ? f(a) : 0\nb += 1\nreturn b', 11)
runs('name -> as an argument', 'local function map(xs) return function(f) local o = {} for i, x in ipairs(xs) do o[i] = f(x) end return o end end\nlocal xs = { 1, 2 }\nlocal r = map xs x -> x * 10\nreturn r[2]', 20)
runs('customary operators', 'return !false && (1 != 2) || false', true)
runs('continue', 'local n = 0\nfor i = 1, 5 do\n  if i % 2 == 0 then continue end\n  n = n + i\nend\nreturn n', 9)
runs('endall', 'local function each(xs) return function(f) for _, x in ipairs(xs) do f(x) end end end\nlocal n = 0\neach { 1, 2 } do(a)\n  each { 10, 20 } do(b)\n    n = n + a * b\nendall\nreturn n', 90)
fails_at('a runtime error keeps its line', 'local x = 1\n\nlocal f = do(a)\n  return a.b.c\nend\nreturn f({})', 4)
fails_at('lines across a with block', 'local t = with\n  a = 1\n  b = 2\nend\nerror("here")', 5)

-- typed forms without a host (design macro-layer.md §4.6–§4.8) ---------------------------------
local function errors(name, src, expect, opts)
    local chunk, err = mua.load(src, '=' .. name, opts)
    if not chunk then return check('errors: ' .. name, false, err) end
    local ok, e = pcall(chunk)
    check('errors: ' .. name, not ok and tostring(e):find(expect, 1, true), ok and 'ran' or e)
end
local function runs_with(name, src, expect, opts)
    local chunk, err = mua.load(src, '=' .. name, opts)
    if not chunk then return check('runs: ' .. name, false, err) end
    local ok, got = pcall(chunk)
    check('runs: ' .. name, ok and got == expect, ok and ('got ' .. tostring(got)) or got)
end

-- contracts
runs('a typed function that keeps its contract', 'local f = do(x: Number): Number = x * 2\nreturn f(21)', 42)
errors('a parameter contract blames the caller', 'local f = do(x: Number): Number = x * 2\n\nreturn f("a")',
    "contract: parameter 'x' of f expects Number, got a string \"a\"")
errors('the caller\'s line', 'local f = do(x: Number): Number = x * 2\n\nlocal r = f("a")\nreturn r', 'line:3:')
errors('a result\'s line', 'local f = do(x: Number): String\n  local y = x\n  return y\nend\nlocal r = f(1)\nreturn r', 'line:3:')
errors('a result contract', 'local f = do(x: Number): String\n  return x + 1\nend\nreturn f(1)',
    'contract: the result of f expects String, got number 2')
errors('falling off the end', 'local f = do(x: Number): Number\n  local y = x\nend\nreturn f(1)',
    'the result of f expects Number, got nil')
runs('Unit results', 'local f = do(x: Number): Unit\n  local y = x\nend\nreturn f(1) == nil', true)
runs('Optional', 'local f = do(x: Optional(Number)): Number = x or 0\nreturn f(nil) + f(2)', 2)
errors('a typed local', 'local f = do(x: Any): Number\n  local y: Number = x\n  return y\nend\nreturn f("s")',
    "local 'y' in f expects Number")
errors('assigning a typed local', 'local f = do(): Number\n  local y: Number = 1\n  y = "two"\n  return y\nend\nreturn f()',
    "local 'y' in f expects Number")
runs('a predicate checker', 'local Even = do(v) = type(v) == "number" and v % 2 == 0\nlocal f = do(x: Even): Number = x / 2\nreturn f(8)', 4)
runs('a typed local function recurses', 'local function fact(n: Number): Number\n  if n <= 1 then return 1 end\n  return n * fact(n - 1)\nend\nreturn fact(5)', 120)
runs_with('contracts switched off', 'local f = do(x: Number): Number = x\nreturn f("unchecked")', 'unchecked', { contracts = false })
do
    local text = mua.translate('local f = do(x: Number): Number = x', 't', { contracts = false })
    check('contracts off evaluate no annotation', not text:find('Number', 1, true), text)
end

-- structural markers
runs('required and optional', 'local Node = closed define\n  op = "store"\n  place = required\n  what = optional\nend\nlocal n = { ..Node, place = 1 }\nreturn n.op .. n.place .. tostring(n.what)', 'store1nil')
errors('a missing required field', 'local Node = closed { op = "s", place = required }\nlocal n = { ..Node }',
    "required: the field 'place' is not supplied")
errors('an unknown field of a closed type', 'local Node = closed { op = "s" }\nlocal n = { ..Node, plcae = 1 }',
    "closed: 'plcae' is not a field")
errors('instances stay closed', 'local Node = closed { op = "s" }\nlocal a = { ..Node }\nlocal b = { ..a, x = 1 }',
    "closed: 'x' is not a field")
runs('a closed type is a checker', 'local P = closed { x = required, y = 0 }\nlocal f = do(p: P): Number = p.x + p.y\nreturn f({ x = 2, y = 3 })', 5)
errors('a closed type rejects an extra field', 'local P = closed { x = required }\nlocal f = do(p: P): Number = p.x\nreturn f({ x = 2, z = 1 })',
    "has the undeclared field 'z'")

-- struct
runs('a struct', 'local Point = struct { x: Number, y: Number }\nfunction Point:sum(): Number return self.x + self.y end\nlocal p = Point with\n  x = 1\n  y = 2\nend\nreturn p:sum()', 3)
errors('a struct field contract', 'local Point = struct { x: Number, y: Number }\nlocal p = Point { x = 1, y = "2" }',
    "the field 'y' of Point expects Number")
errors('an unknown struct field', 'local Point = struct { x: Number }\nlocal p = Point { x = 1, z = 2 }', "Point has no field 'z'")
runs('a struct answers the members it lacks through its __index method', [[
local Sum = struct { name: String, alternatives: Table }
function Sum:describe(): String return "sum " .. self.name end
function Sum:__index(member)
    if self.alternatives[member] then return "constructor " .. member end
    return nil
end
local shape = Sum { name = "shape", alternatives = { circle = true, name = true } }
return table.concat({ shape.circle, shape.name, shape:describe(), tostring(shape.square) }, ",")]], 'constructor circle,shape,sum shape,nil')
runs('a struct without __index looks members up as a table', 'local P = struct { x: Number }\nfunction P:twice(): Number return self.x * 2 end\nlocal p = P { x = 4 }\nreturn p:twice() + (p.y == nil and 1 or 0)', 9)
errors('a struct\'s __index is a method', 'local P = struct { x: Number }\nP.__index = 5', 'is a method')
runs('a struct receives assignments to the members it lacks through its __newindex method', [[
local Type = struct { name: String, count: Number }
local members = {}
function Type:__newindex(member, value) members[member] = value end
function Type:__index(member) return members[member] end
local t = Type { name = "fixed", count = 1 }
t.cast = "a hook"
t.count = 2
return table.concat({ t.cast, rawget(t, "cast") == nil and "kept apart" or "stored", tostring(t.count) }, ",")]], 'a hook,kept apart,2')
errors('a declared field keeps its contract under __newindex', [[
local P = struct { x: Number }
function P:__newindex(member, value) end
local p = P { x = 1 }
p.x = nil
p.x = "no"]], "the field 'x' of P expects Number")
errors('a struct\'s __newindex is a method', 'local P = struct { x: Number }\nP.__newindex = 5', 'is a method')
runs('a struct method named as a metamethod is its instances\' metamethod', [[
local Scale = struct { factor: Number }
function Scale:__call(x) return x * self.factor end
function Scale:__tostring() return "scale " .. self.factor end
function Scale:__eq(other) return self.factor == other.factor end
local s = Scale { factor = 3 }
return table.concat({ s(5), tostring(s), tostring(s == Scale { factor = 3 }) }, ",")]], '15,scale 3,true')
errors('a struct metamethod is a method', 'local P = struct { x: Number }\nP.__call = 5', 'is a method')
runs('a struct is a checker', 'local Point = struct { x: Number }\nlocal f = do(p: Point): Number = p.x\nreturn f(Point { x = 7 })', 7)
errors('a struct checker is nominal', 'local Point = struct { x: Number }\nlocal f = do(p: Point): Number = p.x\nreturn f({ x = 7 })',
    'expects Point, got a table')
runs('spread with overrides builds a struct', 'local Point = struct { x: Number, y: Number }\nlocal p = Point { x = 1, y = 2 }\nlocal q = Point { ..p, y = 5 }\nreturn q.x + q.y', 6)

-- oneof
runs('a oneof and its match', 'local Shape = oneof { circle: Number, square: Number, none: Unit }\nlocal area = do(s) = s with\n  circle = do(r) = 3 * r * r\n  square = do(a) = a * a\n  none = do() = 0\nend\nreturn area(Shape.circle(2)) + area(Shape.square(3)) + area(Shape.none())', 21)
errors('a payload contract', 'local Shape = oneof { circle: Number }\nlocal s = Shape.circle("big")', 'the payload of Shape.circle expects Number')
errors('a missing handler', 'local Shape = oneof { a: Unit, b: Unit }\nlocal v = Shape.a()\nreturn v { a = do() = 1 }', "the alternative 'b' has no handler")
errors('an unknown handler', 'local Shape = oneof { a: Unit }\nlocal v = Shape.a()\nreturn v { a = do() = 1, c = do() = 2 }', "has no alternative 'c'")
runs('a oneof is a checker', 'local R = oneof { ok: Number, err: String }\nlocal f = do(r: R): Number = r { ok = do(v) = v, err = do(e) = -1 }\nreturn f(R.ok(4))', 4)

-- ffistruct (LuaJIT FFI): C structs as ctypes; a ctype is a checker
runs('an ffistruct builds values', 'local P = ffistruct { x: double, y: double }\nlocal p = P { x = 1.5, y = 2 }\nreturn p.x + p.y', 3.5)
runs('an ffistruct in the with form', 'local P = ffistruct\n    x: int32_t\n    y: int32_t\nend\nreturn require("ffi").sizeof(P)', 8)
runs('FFIStructs nest, and an array field is a string of C', 'local P = ffistruct { x: double }\nlocal S = ffistruct { a: P, tag: "uint8_t[4]" }\nlocal s = S { a = P(7) }\nreturn s.a.x', 7)
runs('a ctype is a contract', 'local P = ffistruct { x: double }\nlocal f = do(p: P): Number = p.x\nreturn f(P(4))', 4)
errors('a ctype contract rejects another value', 'local P = ffistruct { x: double }\nlocal f = do(p: P): Number = p.x\nreturn f(5)',
    "parameter 'p' of f expects P, got number 5")
errors('a field needs a C type', 'local P = ffistruct { x: 5 }', "needs a C type")

-- a returned block is a do lambda
runs('a returned block is a function', 'local f = do(a)\n    return do(b)\n        return a + b\n    end\nend\nreturn f(1)(2)', 3)
runs('a returned block opens what it is given', 'local f = do()\n    return do(..)\n        return x\n    end\nend\nreturn f()({ x = 5 })', 5)
-- family: a closed set of structs with passes; every handler spells the contract node recurse
local FAMILY = [[
local Expression = family "expression"
local Literal = struct { value: Number }
local Sum = struct { left: Expression, right: Expression }
local Negation = struct { operand: Expression }
Expression { Literal, Sum, Negation }
local Evaluation = define
    Literal = do(node, recurse)
        return node.value
    end
    Sum = do(node, recurse)
        return recurse node.left + recurse node.right
    end
    Negation = do(node, recurse)
        return -recurse node.operand
    end
end
]]
runs('a family is a type and a pass runs over it', FAMILY .. [[
local evaluate = Expression.pass "evaluate" with ..Evaluation end
return evaluate(Sum { left = Literal { value = 5 }, right = Negation { operand = Literal { value = 2 } } })]], 3)
runs('a family answers is', FAMILY .. [[
local one = Literal { value = 1 }
return tostring(Expression.is(one, Literal)) .. tostring(Expression.is(one, Negation)) .. tostring(Expression.is(5, Literal))]],
    'truefalsefalse')
runs('a family lists its kinds', FAMILY .. 'return table.concat(Expression.kinds, ",")', 'Literal,Sum,Negation')
errors('a family field names the family', FAMILY .. 'local sum = Sum { left = Literal { value = 1 }, right = 2 }', 'expects expression')
errors('a pass with a kind missing', FAMILY .. 'local partial = Expression.pass "partial" with Literal = Evaluation.Literal, Sum = Evaluation.Sum end',
    "no handler for the kind 'Negation' of the family 'expression'")
errors('a pass with an unknown kind', FAMILY .. 'local misspelled = Expression.pass "misspelled" with ..Evaluation, Negatoin = Evaluation.Negation end',
    "'Negatoin' is not a kind in the family 'expression'")
errors('a pass handler that is not a function', FAMILY .. 'local broken = Expression.pass "broken" with ..Evaluation, Negation = 1 end', 'not a function')
-- compound assignment in an opened region (every colon block opens its home)
runs('a compound assignment to a free name in a colon block', [[
local each = do(f) f() end
local n = 1
each:
    n += 2
    n *= 5
end
return n]], 15)
runs('a compound assignment reaches the opened member that has the name', [[
local context = { total = 1 }
local with_context = do(f) f(context) end
with_context:
    total += 41
end
return context.total]], 42)
runs('a compound assignment reads its target before its operand', [[
local each = do(f) f() end
local text = "a"
local bump = do() text = text .. "!" return "b" end
each:
    text ..= bump()
end
return text]], "ab")
-- test: a named case; run at once, or collected for a runner
runs('a test runs where it is named', [[
local ran = false
test "it runs":
    ran = true
end
return ran]], true)
errors('a failing test names itself', [[
test "two is not three":
    assert(2 == 3, "arithmetic")
end]], "test 'two is not three' failed: ")
runs('collect gathers cases in order without running them', [[
local ran = 0
local cases = collect do()
    test "first":
        ran += 1
    end
    test "second":
        ran += 10
    end
end
assert(ran == 0 and #cases == 2 and cases[1].name == "first" and cases[2].name == "second")
cases[2].run()
return ran]], 10)
runs('a collection inside a collection is its own', [[
local outer = collect do()
    test "outer":
    end
    local inner = collect do()
        test "inner":
        end
    end
    assert(#inner == 1 and inner[1].name == "inner")
end
return #outer == 1 and outer[1].name == "outer"]], true)
runs('a case\'s block is labeled with what it shows', [[
local cases = collect do()
    test "first shows this":
    end
end
local ran = nil
test "run at once":
    ran = true
end
return label_of(cases[1].run) == "first shows this" and ran]], true)
runs('trace answers its value, and inspect says what it is and holds', [[
local Point = struct { x: Number, y: Number }
local origin = label "the origin" Point { x = 0, y = 0 }
local plain = { name = "box", inner = origin }
assert(trace(41) + 1 == 42)
assert(inspect(origin) == "the origin: a Point { x = 0, y = 0 }", inspect(origin))
assert(inspect(plain) == 'a table { inner = «the origin», name = "box" }', inspect(plain))
local nested = { point = { x = 1, y = { deep = true } } }
assert(inspect(nested) == "a table { point = a table { x = 1, y = a table { deep = true } } }", inspect(nested))
local cycle = { name = "loop" }
cycle.self = cycle
assert(inspect(cycle) == 'a table #1 { name = "loop", self = ↩ #1 }', inspect(cycle))
local long = {}
for i = 1, 30 do long[i] = i end
assert(inspect(long):find("{\n    [1] = 1,\n", 1, true), inspect(long))
local editor = { themes = label "Available themes" { label "Light" { tone = 1 } } }
assert(inspect(editor) == "a table { themes = «Available themes» }", inspect(editor))
assert(inspect(editor.themes) == "Available themes: a table { [1] = «Light» }", inspect(editor.themes))
assert(inspect_through 1 (editor) == "a table { themes = «Available themes» a table { [1] = «Light» } }", inspect_through 1 (editor))
assert(trace_through 0 (41) + 1 == 42)
assert(inspect_through(math.huge)(editor):find("«Light» a table { tone = 1 }", 1, true), inspect_through(math.huge)(editor))
return inspect "text"]], '"text"')
runs('a vocabulary of an activity is opened, extended by spread, and labeled', [[
local tools.. = { ..debugging, twice = |x| -> x * 2 }
assert(label_of(debugging) == "debugging: say what values are, by their labels")
assert(debugging.trace == trace and testing.test == test and contracts.Number == Number)
return twice(inspect_through 0 (21) == "21" and 21 or 0)]], 42)
errors('a test takes a name first', 'test(5)', 'test takes a name first')
errors('a test takes a block', 'test "named" (5)', "test 'named' takes a block")
runs('a program may define its own test', [[
local test = do(x) = x * 2
return test 21]], 42)
errors('a pass meets a value that is no member', FAMILY .. 'local evaluate = Expression.pass "evaluate" with ..Evaluation end\nevaluate 5',
    "is not a member of the family 'expression'")
errors('a family used before it is sealed', 'local Expression = family "expression"\nlocal Holder = struct { held: Expression }\nlocal holder = Holder { held = 1 }', 'before it is sealed')
errors('a family sealed twice', 'local Expression = family "expression"\nlocal Empty = struct { }\nExpression { Empty }\nExpression { Empty }', 'already sealed')
errors('a family needs structs', 'local Expression = family "expression"\nExpression { 1 }', 'not a struct')
errors('is asks about a kind of the family', FAMILY .. 'local Other = struct { }\nExpression.is(Literal { value = 1 }, Other)', "is not a kind in the family 'expression'")
runs('passes compose by spread and an explicit entry settles a clash', FAMILY .. [[
local Loud = define
    Literal = do(node, recurse)
        return 100
    end
end
local settled = Expression.pass "settled" with
    ..Evaluation
    ..Loud
    Literal = do(node, recurse)
        return 7
    end
end
return settled(Sum { left = Literal { value = 1 }, right = Literal { value = 2 } })]], 14)
errors('a family and a pass take prose as their description', [[
local Expression = family "expression of the toy language"
local Literal = struct { value: Number }
Expression { Literal }
Expression.pass "evaluate an expression to a number" with
    Literal = do(node, recurse)
        return 1
    end
    Literall = do(node, recurse)
        return 2
    end
end]], "pass 'evaluate an expression to a number': 'Literall' is not a kind in the family 'expression of the toy language'")
runs('a pass carries extra arguments down', FAMILY .. [[
local Depth = define
    Literal = do(node, recurse, depth)
        return depth
    end
    Sum = do(node, recurse, depth)
        return math.max(recurse(node.left, depth + 1), recurse(node.right, depth + 1))
    end
    Negation = do(node, recurse, depth)
        return recurse(node.operand, depth + 1)
    end
end
local depth_of = Expression.pass "how deep" with ..Depth end
return depth_of(Sum { left = Literal { value = 1 }, right = Negation { operand = Literal { value = 2 } } }, 0)]], 2)
-- checker names a predicate
errors('a named checker names what it expected', 'local Even = checker "Even" do(v) return v % 2 == 0 end\nlocal f = do(n: Even): Number = n\nf(3)', 'expects Even')
runs('a named checker accepts', 'local Even = checker "Even" do(v) return v % 2 == 0 end\nlocal f = do(n: Even): Number = n\nreturn f(4)', 4)
runs('a checker takes a named predicate', 'local is_even = do(v) return v % 2 == 0 end\nlocal Even = checker "even" is_even\nlocal f = do(n: Even): Number = n\nreturn f(6)', 6)
errors('checker takes its name, then its predicate', 'local c = checker(1, 2)', 'takes its name, then its predicate')
errors('a checker names the type first', 'local c = checker 1', 'names the type first')
errors('a checker wants a predicate', 'local c = checker "x" 5', 'is number 5, not a function')
-- meta installs a vocabulary as a metatable
runs('meta installs methods and metamethods', [[
local Counter = meta with
    index = define
        increment = do(self)
            self.value += 1
        end
    end

    tostring = self -> tostring(self.value)
end with
    value = 0
end
Counter:increment()
Counter:increment()
return tostring(Counter)]], '2')
runs('meta keeps __ names and shares one metatable', 'local make = meta { __index = { hi = do() = 1 }, call = do(self) = 7 }\nlocal a, b = make {}, make {}\nreturn a:hi() + b() + (getmetatable(a) == getmetatable(b) and 100 or 0)', 108)
runs('a program may bind its own meta', 'local meta = 5\nreturn meta', 5)
errors('meta takes named metamethods', 'local m = meta { 1 }', 'names its metamethods')
errors('meta applies to a table', 'local m = meta { index = {} }\nm(3)', 'applies to a table')
errors('a clash left unresolved names the field', 'local t = { ..{ a = 1, b = 1 }, ..{ a = 2, b = 2 }, a = 3 }', "field 'b'")
-- struct, oneof and ffistruct take their fields as a block
runs('struct as a block', 'local P = struct\n    x: Number\n    y: Number\nend\nreturn P { x = 1, y = 2 }.y', 2)
runs('oneof as a block', 'local O = oneof\n    a: Unit\n    b: Number\nend\nreturn O.b(4).value', 4)
runs('ffistruct as a block', 'local V = ffistruct\n    x: double\nend\nreturn V { x = 3 }.x', 3)
runs('a struct block inside a function', 'local f = do(A) = struct\n    a: A\nend\nreturn f(Number) { a = 5 }.a', 5)
do
    local ok, message = pcall(mua.translate, 'local P = struct with\n    x: Number\nend', 'p.mua')
    check('struct with is written struct', not ok and message:find('is written `struct`', 1, true), message)
end
-- a headless `with` is a plain table that a struct contract fills in, in place
runs('with is a plain table without a type', 'local t = with\n    x = 1\nend\nreturn t.x + (getmetatable(t) == nil and 10 or 0)', 11)
runs('a typed local takes the struct', 'local P = struct { x: Number }\nlocal p: P = with\n    x = 1\nend\nreturn getmetatable(p) == getmetatable(P { x = 2 }) and p.x or -1', 1)
runs('a typed parameter takes the struct', 'local P = struct { x: Number }\nlocal f = do(p: P): Number = p.x\nreturn f(with x = 5 end)', 5)
runs('a typed result takes the struct', 'local P = struct { x: Number }\nlocal g = do(): P = with x = 7 end\nreturn getmetatable(g()) == getmetatable(P { x = 0 }) and g().x or -1', 7)
runs('a struct field takes the struct', 'local I = struct { x: Number }\nlocal O = struct { inner: I }\nlocal o = O { inner = with x = 3 end }\nreturn getmetatable(o.inner) == getmetatable(I { x = 0 }) and o.inner.x or -1', 3)
runs('the table keeps its identity', 'local P = struct { x: Number }\nlocal t = with x = 4 end\nlocal f = do(p: P): Number = p.x\nf(t)\nreturn getmetatable(t) == getmetatable(P { x = 0 }) and t.x or -1', 4)
errors('a with that does not fit the struct', 'local P = struct { x: Number }\nlocal p: P = with\n    y = 1\nend', "has no field 'y'")
errors('a with that is missing a field', 'local P = struct { x: Number }\nlocal p: P = with\n    z = nil\nend', "the field 'x' of P expects Number")
errors('a with already branded by another struct is not filled again', 'local P = struct { x: Number }\nlocal Q = struct { x: Number }\nlocal t = with x = 1 end\nlocal p: P = t\nlocal q: Q = t', "expects Q")
-- ... and an ffistruct: a new C value made from the table's fields
runs('a typed local takes the ffistruct', 'local V = ffistruct { x: "double", y: "double" }\nlocal v: V = with x = 1, y = 2 end\nreturn tostring(type(v)) .. v.x + v.y', 'cdata3')
runs('a typed parameter takes the ffistruct', 'local V = ffistruct { x: "double", y: "double" }\nlocal f = do(v: V): Number = v.x * v.y\nreturn f(with x = 3, y = 4 end)', 12)
runs('a typed result takes the ffistruct', 'local V = ffistruct { x: "double" }\nlocal g = do(): V = with x = 7 end\nreturn g().x', 7)
runs('a struct field takes the ffistruct', 'local V = ffistruct { x: "double" }\nlocal S = struct { v: V }\nreturn S { v = with x = 9 end }.v.x', 9)
runs('a oneof payload takes the ffistruct', 'local V = ffistruct { x: "double" }\nlocal O = oneof { some: V, none: Unit }\nreturn O.some(with x = 5 end).value.x', 5)
runs('a typed assignment takes the ffistruct', 'local V = ffistruct { x: "double" }\nlocal v: V = V { x = 1 }\nv = with x = 8 end\nreturn v.x', 8)
errors('a with that does not fit the ffistruct', 'local V = ffistruct { x: "double" }\nlocal v: V = with y = 1 end', 'y')
-- define entries end is a table, and a list when its entries are positional
runs('define makes a list of numbers', 'local t = define\n    1\n    2\n    3\nend\nreturn #t + t[3]', 6)
runs('define makes a list of tables', 'local t = define\n    { x = 1 }\n    { x = 2 }\nend\nreturn t[1].x + t[2].x', 3)
runs('define nests', 'local t = define\n    define\n        a = 1\n    end\n    define\n        a = 2\n    end\nend\nreturn t[1].a + t[2].a', 3)
runs('define makes a list of functions', 'local t = define\n    x -> x + 1\n    do(x) = x * 2\nend\nreturn t[1](1) + t[2](5)', 12)
runs('define makes a list of calls and names', 'local a, f = 5, function(x) return x * 2 end\nlocal t = define\n    a\n    f(4)\nend\nreturn t[1] + t[2]', 13)
runs('define makes a list of negative numbers', 'local t = define\n    -1\n    -2\nend\nreturn t[1] + t[2]', -3)
runs('define mixes a list and keys', 'local t = define\n    "a"\n    "b"\n    n = 2\nend\nreturn t[1] .. t[2] .. t.n', 'ab2')
runs('a list on one line takes commas', 'local t = define 1, 2, 3 end\nreturn #t', 3)
runs('define is a table', 'local d = define\n    a = 1\n    b = 2\nend\nreturn d.a + d.b', 3)
runs('define takes a spread', 'local base = define\n    a = 1\nend\nlocal d = define ..base\n    b = 2\nend\nreturn d.a + d.b', 3)
runs('define is a name when no entry follows', 'local define = 5\nreturn define', 5)
do
    local ok, message = pcall(mua.translate, 'local d = define { a = 1 }', 'd.mua')
    check('define takes entries and end, not braces', not ok and message:find('write { … }', 1, true), message)
end
errors('define called as a function says what to write', 'local define = nil\nlocal d = define(1)', 'attempt to call')
runs('a program may bind its own define', 'local function define(x) return x * 2 end\nreturn define(4)', 8)
-- the bytecode cache: a load writes bytecode that the next load reads; a different source, the
-- contracts switch or a host without an id are different keys or uncached
do
    local dir = os.tmpname(); os.remove(dir); assert(os.execute('mkdir -p ' .. dir))
    local function entries() local p = io.popen('ls ' .. dir); local t = p:read('*a'); p:close(); return select(2, t:gsub('%.luac', '')) end
    local src = 'local f = do(x: Number): Number = x + 1\nreturn f(1)'
    local chunk = assert(mua.load(src, '=cached', { cache = dir }))
    check('a cached load runs', chunk() == 2)
    check('a load writes one bytecode file', entries() == 1, entries())
    local again = assert(mua.load(src, '=cached', { cache = dir }))
    check('a second load reads it', again() == 2 and entries() == 1)
    assert(mua.load('return 3', '=cached', { cache = dir }))
    check('another source is another entry', entries() == 2)
    assert(mua.load(src, '=cached', { cache = dir, contracts = false }))
    check('the contracts switch is part of the key', entries() == 3)
    assert(mua.load(src, '=cached', { cache = dir, host = {} }))
    check('a host without an id is not cached', entries() == 3)
    assert(mua.load(src, '=cached', { cache = dir, host = { id = 'h1' } }))
    check('a host with an id is', entries() == 4)
    os.execute('rm -rf ' .. dir)
end

-- every tracked Lua source: the round trip is exact, every number and string token is one
-- LuaJIT reads the same way, it parses, and what it translates to compiles
local function sh(cmd)
    local p = assert(io.popen(cmd)); local out = p:read '*a'; p:close(); return out
end
local files = {}
for f in sh('cd ' .. root .. ' && git ls-files "*.lua" "*.mua" 2>/dev/null'):gmatch '[^\n]+' do files[#files + 1] = f end
local sources, literals, parsed, compiled = 0, 0, 0, 0
local emit = require 'mua.emit'
for _, f in ipairs(files) do
    local fh = io.open(root .. '/' .. f, 'rb')
    if fh then
        local src = fh:read '*a'; fh:close()
        local ok, ts = pcall(lex.scan, src, f)
        if not ok then check('scans ' .. f, false, ts)
        else
            check('round trip ' .. f, lex.text(ts) == src)
            sources = sources + 1
            for _, tk in ipairs(ts) do
                if tk.t == 'number' or tk.t == 'string' then
                    literals = literals + 1
                    if not loadstring('return ' .. tk.v) then check(('LuaJIT reads %s:%d %s'):format(f, tk.line, tk.v), false) end
                end
            end
            local pok, block = pcall(parse.parse, src, f)
            if f:match('^tests/fixtures/syntax_error') then
                check(f .. ' does not parse, by design', not pok)
            elseif not pok then check('parses ' .. f, false, block)
            else
                parsed = parsed + 1
                local tok, text = pcall(emit.emit, block, { filename = f })
                if not tok then check('translates ' .. f, false, text)
                else
                    local chunk, err = loadstring(text, '@' .. f)
                    if chunk then compiled = compiled + 1 else check('LuaJIT compiles ' .. f, false, err) end
                end
            end
        end
    end
end
check('sources were found', sources >= 7, sources)

print(('Mua: %d passed, %d failed (%d sources round-tripped, %d literals cross-checked, %d parsed, %d compiled)'):format(
    passed, failed, sources, literals, parsed, compiled))
os.exit(failed == 0 and 0 or 1)
