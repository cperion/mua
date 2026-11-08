-- The `mua` command: status codes, tracebacks, dumping, expressions, contracts on and off.
local root = arg[0]:match('^(.*)/tests/[^/]*$') or '.'
local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local function capture(command)
    local p = assert(io.popen(command .. ' 2>&1; printf "\\n__STATUS__%d\\n" "$?"'))
    local text = p:read '*a'; p:close()
    local out, status = text:match('^(.*)\n__STATUS__(%d+)\n$')
    assert(status, text)
    return out, tonumber(status)
end
local passed = 0
local function check(label, command, status, contains, absent)
    local out, rc = capture(command)
    assert(rc == status and (not contains or out:find(contains, 1, true))
        and (not absent or not out:find(absent, 1, true)), label .. ': status ' .. tostring(rc) .. '\n' .. out)
    passed = passed + 1
end
local lua = q(arg[-1] or 'luajit')
local cli = 'timeout 20 ' .. lua .. ' ' .. q(root .. '/mua.lua')
local function fixture(name) return q(root .. '/tests/fixtures/' .. name) end
check('plain program', cli .. ' ' .. fixture('ok.mua'), 0, 'fixture ok')
check('dump only', cli .. ' -d ' .. fixture('ok.mua'), 0, 'fixture ok')
check('standalone expression', cli .. ' -e ' .. q('print(1+1)'), 0, '2')
check('expression error status', cli .. ' -e ' .. q('error("boom")'), 1, 'boom')
check('anonymous traceback names the line', cli .. ' ' .. fixture('anon_error.mua'), 1, ':3:', '[string "')
check('named error status', cli .. ' ' .. fixture('named_error.mua'), 1, 'boom')
check('syntax error location', cli .. ' ' .. fixture('syntax_error.mua'), 1, 'syntax_error.mua:1')
check('missing file status', cli .. ' ' .. fixture('does_not_exist.mua'), 1, 'No such file')
check('no arguments prints usage', cli, 1, 'usage: mua')
check('script arguments', cli .. ' -e ' .. q('print(...)') .. ' a b', 0, 'a\tb')
check('expression lambdas and currying', cli .. ' -e ' .. q([[
local mul = do(a) = do(b) = a * b
assert(mul 6 7 == 42)
local answer = do() = 42
assert(answer() == 42)
print('forms ok')
]]), 0, 'forms ok')
check('nested application in argument groups', cli .. ' -e ' .. q([[
local identity = do(x) = x
local Box = do(fields) = fields
local item = 42
local result = identity Box { value = identity item, nested = { identity item } }
assert(result.value == 42 and result.nested[1] == 42)
local slots = { 42 }
local index = 1
assert(identity slots[index] == 42)
local text = identity Box { value = "identity__apply" }
assert(text.value == "identity__apply")
print('copied groups ok')
]]), 0, 'copied groups ok')
check('exact hexadecimal integer suffixes in bare calls', cli .. ' -e ' .. q([[
local identity = do(x) = x
local u = identity 0xffffffffffffffffULL
local s = identity 0x7fffffffffffffffLL
assert(type(u) == 'cdata' and u == 18446744073709551615ULL)
assert(type(s) == 'cdata' and s == 9223372036854775807LL)
print('hex suffixes ok')
]]), 0, 'hex suffixes ok')
check('two-dot opening keeps infix concatenation', cli .. ' -e ' .. q([[
local named = do(ctx..) = label .. suffix
local unnamed = do(..) = label .. suffix
assert(named { label = 'a', suffix = 'b' } == 'ab')
assert(unnamed { label = 'c', suffix = 'd' } == 'cd')
local function args(...) return ... end
assert(args(42) == 42)
print('two dots ok')
]]), 0, 'two dots ok')
check('contracts are checked', cli .. ' -e ' .. q('local f = do(x: Number): Number = x\nprint(pcall(f, "s"))'), 0, "expects Number")
check('contracts can be switched off', cli .. ' --no-contracts -e ' .. q('local f = do(x: Number): Number = x\nprint(pcall(f, "s"))'), 0, 'true\ts')
check('require a Mua module', cli .. ' -e ' .. q([[local Library = require "tests.fixtures.library"
print(Library.greeting())]]), 0, 'Mua library loaded')
check('preload a Mua module', cli .. ' -l tests.fixtures.library -e ' .. q([[
print(package.loaded["tests.fixtures.library"].greeting())]]), 0, 'Mua library loaded')
check('module contracts are checked', cli .. ' -e ' .. q([[
local Library = require "tests.fixtures.library"
print(pcall(Library.identity, "text"))]]), 0, 'expects Number')
check('module inherits no-contracts', cli .. ' --no-contracts -e ' .. q([[
local Library = require "tests.fixtures.library"
print(pcall(Library.identity, "text"))]]), 0, 'true\ttext')
check('module syntax errors name their file', cli .. ' -e ' .. q([[
require "tests.fixtures.syntax_error"]]), 1, 'syntax_error.mua:1')
check('CLI restores its loader after failure', lua .. ' -e ' .. q([[
local cli = require 'mua.cli'
local before = {}
for index, loader in ipairs(package.loaders) do before[index] = loader end
assert(cli.main({'-e', 'error("expected failure")'}) == 1)
assert(#package.loaders == #before)
for index, loader in ipairs(before) do assert(package.loaders[index] == loader) end
print('loaders restored')]]), 0, 'loaders restored')
print(('%d command checks passed'):format(passed))
