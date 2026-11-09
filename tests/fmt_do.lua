-- Focused formatter regression: a same-line do argument needs no call parens.
local root = arg[0]:match('^(.*)/tests/[^/]*$') or '.'
package.path = root .. '/?.lua;' .. package.path
local fmt = require 'mua.fmt'
local passed = 0
local function check(name, condition, detail)
    assert(condition, name .. (detail and ('\n' .. detail) or ''))
    passed = passed + 1
end
local function formatted(name, source, expected, options)
    local result = fmt.format(source, options, name)
    check(name, result == expected, result)
    check(name .. ': idempotent', fmt.format(result, options, name) == result)
    return result
end
formatted('host method block', 'items:each(do(item)\nconsume item\nend)',
    'items:each do(item)\n    consume item\nend\n')
formatted('host plain block', 'visit(do\nwork()\nend)',
    'visit do\n    work\nend\n')
formatted('inline block', 'visit(do(x) return x end)', 'visit x -> x\n')
formatted('comments in body', 'visit(do(x) -- keep this\n-- and this\nconsume x\nend)',
    'visit do(x)  -- keep this\n    -- and this\n    consume x\nend\n')
formatted('already bare', 'visit do(x)\nconsume x\nend',
    'visit do(x)\n    consume x\nend\n')
formatted('preserve option', 'visit(do(x)\nconsume x\nend)',
    'visit(do(x)\n        consume x\n    end)\n', { call_style = 'preserve' })
formatted('next-line do joins owning call', 'visit(\ndo(x)\nconsume x\nend)',
    'visit do(x)\n    consume x\nend\n')
check('invalid split owning call rejected', not pcall(fmt.format, 'visit\n(do end)'))
formatted('multiple arguments stay together', 'visit(1, do(x)\nconsume x\nend)',
    'visit(1, do(x)\n        consume x\n    end)\n')
formatted('callee after call', 'visit(1)(do(x)\nconsume x\nend)',
    'visit 1 do(x)\n    consume x\nend\n')
formatted('native block', 'local f=do():Unit\nvisit(do(x)\nconsume x\nend)\nend',
    'local f = do(): Unit\n    visit do(x)\n        consume x\n    end\nend\n')
formatted('nested do blocks', 'visit(do(x)\nother(do(y)\nconsume y\nend)\nend)',
    'visit do(x)\n    other do(y)\n        consume y\n    end\nend\n')

-- Exercise the actual macro translator independently of runtime/compiler
-- initialization. Execute the host case; compare generated staged Lua for the
-- native case, rather than relying only on the formatter's parser fingerprint.
package.path = root .. '/?/init.lua;' .. package.path
local mua = require 'mua.init'
local dlex = require 'mua.lex'
local function translate(source, name) return mua.translate(source, name) end
local function equivalent(name, source, execute)
    local result = fmt.format(source, nil, name)
    local before = translate(source, name)
    local after = translate(result, name)
    local function normalize(code)
        local parts = {}
        local tokens = dlex.scan(code, name)
        for index, tk in ipairs(tokens) do
            local next_index = index + 1
            while tokens[next_index] and (tokens[next_index].t == 'space'
                or tokens[next_index].t == 'comment') do next_index = next_index + 1 end
            -- A return statement emits `; end`; an expression body emits ` end`.
            -- That terminator immediately before end is optional in Lua.
            local terminator = tk.t == ';' and tokens[next_index] and tokens[next_index].v == 'end'
            if tk.t ~= 'space' and tk.t ~= 'comment' and not terminator then parts[#parts + 1] = tk.v end
        end
        return table.concat(parts, '\0')
    end
    check(name .. ': same translated Lua', normalize(before) == normalize(after), after)
    if execute then
        assert(loadstring(before, '@' .. name))()
        assert(loadstring(after, '@' .. name))()
        check(name .. ': host assertions executed', true)
    end
end
equivalent('host_do.nua', [[
local each = do(body)
    body(1)
    body(2)
end
local total = 0
each(do(x)
    total = total + x
end)
assert(total == 3)
]], true)
equivalent('native_do.nua', [[
local twice = do(body) = body(2) + body(3)
local f = do(x: U32): U32
    return twice(do(y)
        return x + y
    end)
end
export f
]])
equivalent('host_minimal_calls.nua', [=[
local identity = do(x) = x
local curry = do(x) = do(y) = x + y
local total = 0
local consume = do(x) total = total + x end
consume(
    identity(--[[ argument ]] 3)
)
local n = curry(
    4
)(
    5
)
local visit = do(body) body(2) end
visit(
    do(x)
        consume(x -- keep this newline
        )
    end
)
assert(total == 5)
assert(n == 9)
]=], true)
equivalent('native_minimal_calls.nua', [=[
local f = do(x: U32): U32
    local n = U32(
        x
    )
    return add(--[[ argument ]] x)(
        n
    )
end
export f
]=])
-- A stage with no setup work needs no return/block staircase. Keep do chains
-- intact when their last stage opens a vocabulary; `-> do(..)` is not that form.
formatted('returned placement stages', [[local title_form = do(initial_title)
    return do(Finish)
        return do(..)
            label initial_title
            button "Accept" Finish.accept
        end
    end
end
]], [[local title_form = do(initial_title) = do(Finish) = do(..)
    label initial_title
    button "Accept" Finish.accept
end
]])
formatted('return-only final stage makes an arrow chain', [[local f = do(a)
    return do(b)
        return a + b
    end
end
]], 'local f = a -> b -> a + b\n')
formatted('expression-ending arrow chain', 'local add = do(a) return do(b) = a + b end',
    'local add = a -> b -> a + b\n')
formatted('expression-ending do preference', 'local add = do(a) return do(b) = a + b end',
    'local add = do(a) = do(b) = a + b\n', { lambda_style = 'do' })
formatted('already written arrow chain sheds a return-only block', [[local f = a -> b -> do
    return a + b
end
]], 'local f = a -> b -> a + b\n')
formatted('blocked do chain does not block independent arrows',
    'local f = do(a) = do(..) tick end\nlocal g = do(x) = x + 1',
    'local f = do(a) = do(..) tick end\nlocal g = x -> x + 1\n')
formatted('opened expression stages stay one style',
    'local f = do(Context..) return do(x) = value + x end',
    'local f = do(..) = do(x) = value + x\n')
formatted('a bare outer do gains its parameter list', 'local f = do return do(..) tick end end',
    'local f = do() = do(..) tick end\n')
formatted('typed stages keep their contracts',
    'local f = do(x: Number): Function return do(y) = x + y end',
    'local f = do(x: Number): Function = do(y) = x + y\n')
formatted('rest stage stays a do chain', 'local f = do(..args) return do(..) use args end end',
    'local f = do(..args) = do(..) use args end\n')
formatted('a collapsed chain needs only one end', [[local f = do(a)
    return do(b)
        return do(..)
            use a b
        endall
]], [[local f = do(a) = do(b) = do(..)
    use a b
end
]])
formatted('setup stays at its stage and still needs endall', [[local f = do(a)
    local count = 0
    return do(b)
        return do(..)
            count += 1
        endall
]], [[local f = do(a)
    local count = 0
    return do(b) = do(..)
        count += 1
    endall
]])
formatted('do chain does not consume an enclosing control end', [[if ready then
    local f = do(a)
        return do(..)
            use a
        endall
end
]], [[if ready then
    local f = do(a) = do(..)
        use a
    end
end
]])
formatted('header comment stays with its stage', [[local f = do(a) -- acquire nothing yet
    return do(..)
        use a
    end
end
]], [[local f = do(a)  -- acquire nothing yet
    return do(..)
        use a
    end
end
]])
formatted('closer comment stays with its stage', [[local f = do(a)
    return do(..)
        use a
    end
end -- end factory
]], [[local f = do(a)
    return do(..)
        use a
    end
end  -- end factory
]])
formatted('several returned values are not a stage',
    'local f = do(a) return do(b) return a+b end, 42 end',
    'local f = do(a) return b -> a + b, 42 end\n')

-- Compile and execute both programs, independently of the formatter's normalized
-- tree comparison. Check effects at each supply, lexical capture, opened lookup,
-- contracts, packed returns and the control boundaries of typed bodies and endall.
local staged_source = [[
local effects = 0
local factory = do(initial)
    effects += 1
    local count = initial
    return do(step)
        return do(..)
            count = count + step
            report count
            return count, nil, "tail", nil
        end
    end
end
local First = factory 10
local Second = factory 100
assert(effects == 2)
local increment = First 2
local decrement = Second(-1)
assert(effects == 2)
local values = {}
local Reports = { report = do(n) values[#values + 1] = n end }
local pack = do(..results) = results
local result = pack(increment Reports)
decrement Reports
increment Reports
assert(result.n == 4 and result[1] == 12 and result[2] == nil and result[3] == "tail")
assert(result[4] == nil and values[1] == 12 and values[2] == 99 and values[3] == 14)
local from_home = do(Context..)
    return do(n)
        return value + n
    end
end
assert(from_home({ value = 3 })(4) == 7)
local typed = do(x: Number): Function
    return do(..)
        return x + value
    end
end
assert(not pcall(typed, "wrong"))
assert(typed(2)({ value = 3 }) == 5)
local outer = do()
    local typed = do(x: Number): Function
        return do(..)
            return x + value
        endall
    end
    return typed
end
assert(outer()(2)({ value = 5 }) == 7)
]]
for _, options in ipairs { { lambda_style = 'arrow' }, { lambda_style = 'do' } } do
    local name = 'staged_' .. options.lambda_style .. '.mua'
    local result = fmt.format(staged_source, options, name)
    check(name .. ': idempotent', fmt.format(result, options, name) == result)
    assert(loadstring(translate(staged_source, name), '@' .. name))()
    assert(loadstring(translate(result, name), '@formatted_' .. name))()
    check(name .. ': original and formatted assertions executed', true)
end
-- Short means one returned expression, not an arbitrary one-line statement.
formatted('short return', 'local increment = do(value) return value + 1 end',
    'local increment = value -> value + 1\n')
formatted('returning a call preserves its results', 'local f = do(value) return fetch(value) end',
    'local f = value -> fetch value\n')
formatted('nil is one result', 'local f = do() return nil end', 'local f = || -> nil\n')
formatted('a bare return is zero results', 'local f = do() return end', 'local f = do() return end\n')
formatted('an action discards call results', 'local f = do(value) notify value end',
    'local f = do(value) notify value end\n')
formatted('a return list is not one expression', 'local f = do(value) return value, nil end',
    'local f = do(value) return value, nil end\n')
formatted('setup cannot be pulled into a return expression', 'local f = do(value) log value; return value end',
    'local f = do(value) log value; return value end\n')
formatted('short typed result keeps its contract', 'local f = do(value): Number return value end',
    'local f = do(value): Number return value end\n')
formatted('short opened body stays do', 'local f = do(Context..) return answer end',
    'local f = do(..) return answer end\n')
formatted('short rest body stays do', 'local f = do(..values) return values end',
    'local f = do(..values) return values end\n')
formatted('do preference keeps a short block', 'local f = do(value) return value end',
    'local f = do(value) return value end\n', { lambda_style = 'do' })
formatted('header comments are not discarded', 'local f = do(value -- parameter\n) return value end',
    'local f = do(value  -- parameter\n) return value end\n')
formatted('body comments are not discarded', 'local f = do(value)\n    -- explanation\n    return value\nend',
    'local f = do(value)\n    -- explanation\n    return value\nend\n')
formatted('comments in an expression survive', 'local f = do(value) return value --[[ offset ]] + 1 end',
    'local f = value -> value  --[[ offset ]] + 1\n')
formatted('arrow head comment is not erased', 'local f = do(value) --[[ meaning ]] = value',
    'local f = do(value)  --[[ meaning ]] = value\n')
formatted('arrow chains have no leftover endall',
    'local f = do(first) return do(second) return first + second endall',
    'local f = first -> second -> first + second\n')
formatted('endall still closes the setup stage',
    'local f = do(first) remember first; return do(second) return first + second endall',
    'local f = do(first) remember first; return second -> first + second end\n')
formatted('arrow does not capture an enclosing operator', 'local n = visit(do(value) return value end) + 1',
    'local n = visit(value -> value) + 1\n')
formatted('an arrow with several parameters is grouped after a callee',
    'visit do(left, right) return left + right end', 'visit (|left, right| -> left + right)\n')
formatted('function-looking text stays literal', 'local f = do() return "do(x) return x end" end',
    'local f = || -> "do(x) return x end"\n')
formatted('parameter pipes are not table separators or bitwise operators', [[local Operations = define
    combine = do(left, right) return left | right end
    mask = do(value, bits) return value & bits end
end
]], [[local Operations = define
    combine = |left, right| -> left | right
    mask = |value, bits| -> value & bits
end
]])
formatted('a table holding handlers stays a block', [[consume {
    combine = do(left, right) return left + right end,
}
]], [[consume with
    combine = |left, right| -> left + right
end
]])

formatted('parameter commas wrap within their own pipe list', [[local Depth = define
    Pair = |node, recurse, depth| -> math.max(recurse(node.left, depth + 1), recurse(node.right, depth + 1))
end
]], [[local Depth = define
    Pair = |node, recurse, depth| -> math.max(recurse(node.left, depth + 1),
        recurse(node.right, depth + 1))
end
]])

formatted('short return of a headless with stays contextual', [[local snapshot = do(value)
    return with
        answer = value
    end
end
]], [[local snapshot = value -> with
    answer = value
end
]])
formatted('arrow before shorthand retains its separator', [[local Capabilities = define
    current = do() return value end
    .close
end
]], [[local Capabilities = define
    current = || -> value,
    .close
end
]])
formatted('arrow before a positional value retains its separator', [[local entries = define
    do(value) return value end
    10
end
]], [[local entries = define
    value -> value,
    10
end
]])

local result_source = [[
local calls = 0
local values = do(value)
    calls += 1
    return value, nil, "tail", nil
end
local results = do(value) return values(value) end
local single = do(value) return (values(value)) end
local action = do(value) values(value) end
local none = do() return end
local one_nil = do() return nil end
local pack = do(..arguments) = arguments
assert(calls == 0)
local returned = pack(results(7))
assert(returned.n == 4 and returned[1] == 7 and returned[2] == nil)
assert(returned[3] == "tail" and returned[4] == nil)
assert(select("#", single(8)) == 1)
assert(select("#", action(9)) == 0)
assert(select("#", none()) == 0 and select("#", one_nil()) == 1)
assert(calls == 3)
local factory = do(first)
    return do(second)
        return first + second
    endall
local add_two = factory 2
assert(add_two(3) == 5 and add_two(8) == 10)
local Handlers = define
    left = do(first, second) return first end
    right = do(first, second) return second end
end
assert(Handlers.left(2, 3) == 2 and Handlers.right(2, 3) == 3)
local snapshot = do(value)
    return with
        answer = value
    end
end
assert(snapshot(42).answer == 42)
local close = do() calls += 1 end
local Capabilities = define
    current = do() return 7 end
    .close
end
assert(Capabilities.current() == 7 and Capabilities.close == close)
local entries = define
    do(value) return value end
    10
end
assert(#entries == 2 and entries[1](7) == 7 and entries[2] == 10)
]]
local short_result = fmt.format(result_source, nil, 'short_results.mua')
check('short results: idempotent', fmt.format(short_result) == short_result)
assert(loadstring(translate(result_source, 'before_short_results.mua')))()
assert(loadstring(translate(short_result, 'after_short_results.mua')))()
check('short results: original and formatted assertions executed', true)
print(('%d do-block formatter checks passed'):format(passed))
