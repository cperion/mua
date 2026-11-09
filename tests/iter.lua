-- iter: one iteration over a step. The cursor's protocol, its value views, and the checker.
local root = arg[0]:match('^(.*)/tests/[^/]*$') or '.'
package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path
local mua = require 'mua.init'
local R = require 'mua.runtime'
local checks = 0
local function check(condition, name)
    assert(condition, name)
    checks = checks + 1
end
local function program(source) return assert(mua.load(source, '=iter'))() end
local function refuses(source, expected, name)
    local ok, err = pcall(program, source)
    check(not ok, 'refused: ' .. (name or source))
    check(tostring(err):find(expected, 1, true) ~= nil,
        ('message for %s: %s'):format(name or source, tostring(err)))
end
local function collect(walk)
    local values = {}
    for value in walk do values[#values + 1] = value end
    return values
end
local function counting(limit)
    return R.iter(limit)(function(state, control)
        if control >= state then return end
        return control + 1, control + 1
    end)
end

-- Curried: the start first, then the step.
check(type(R.iter(3)) == 'function', 'the start alone reads as a step-taking function')
check(collect(counting(3))[3] == 3, 'curried construction')
refuses([[
local walk: iter = iter 5
]], 'expects iter, got a function', 'a start without a step is not a cursor')

-- The step answers the next control and the value; a nil value ends the traversal.
check(table.concat(collect(counting(3)), ',') == '1,2,3', 'three steps')
check(#collect(counting(0)) == 0, 'no steps')
local sum, counted = 0, counting(100)
for value in counted do sum = sum + value end
check(sum == 5050, 'sum of 100')
check(counted.control == 100, 'the control is the progress')
check(counted() == nil, 'a spent cursor advances to nothing')
check(counted.control == 100 and #collect(counted) == 0, 'advancing a spent cursor changes nothing')

-- Using it again continues: the cursor owns its control, so a break leaves the rest.
local walk = counting(10)
local first = {}
for value in walk do
    first[#first + 1] = value
    if #first == 3 then break end
end
check(table.concat(first, ',') == '1,2,3', 'three then break')
check(table.concat(collect(walk), ',') == '4,5,6,7,8,9,10', 'resumed after break')
local one = counting(5)
check(one() == 1 and one() == 2 and one.control == 2, 'advance by hand')

-- A value twice over: the fields are the triple plain Lua iterates.
local triple = counting(4)
local seen = {}
for control, value in triple.step, triple.state, triple.control do
    seen[#seen + 1] = control .. ':' .. value
end
check(table.concat(seen, ' ') == '1:1 2:2 3:3 4:4', 'the same cursor as a Lua triple')
check(triple.control == 0, 'the triple view does not spend the cursor it came from')

-- Two cursors share nothing, so interleaving them keeps both positions.
local left, right = counting(3), counting(3)
local interleaved = {}
for value in left do
    interleaved[#interleaved + 1] = 'l' .. value
    for other in right do
        interleaved[#interleaved + 1] = 'r' .. other
        break
    end
end
check(table.concat(interleaved, ' ') == 'l1 r1 l2 r2 l3 r3', 'interleaved cursors')

-- take is a bounded view that spends from the same cursor.
local pad = counting(20)
check(table.concat(collect(pad:take(3)), ',') == '1,2,3', 'take 3')
check(pad.control == 3, 'take spent the parent')
check(table.concat(collect(pad:take(2)), ',') == '4,5', 'take resumes the parent')
check(#collect(pad:take(0)) == 0 and pad.control == 5, 'take 0 reads nothing')
local spent = counting(2)
check(table.concat(collect(spent:take(9)), ',') == '1,2', 'take past the end stops')
check(#collect(spent:take(1)) == 0, 'take after the end is empty')

-- A value may be false: only nil ends a traversal.
local flags = R.iter(0)(function(state, control)
    if control >= 3 then return end
    return control + 1, control == 2 and false or 'yes'
end)
check(#collect(flags) == 3, 'false is a value, not an end')

-- A state may be a table, and the step need not change it: the control moves.
local items = { 'a', 'b', 'c' }
local cursor = R.iter(items)(function(state, control)
    local value = state[control + 1]
    if value == nil then return end
    return control + 1, value
end)
check(table.concat(collect(cursor), '') == 'abc', 'a table state read by the control')

-- What the type refuses when it is made.
check(not pcall(R.iter(0), 'no'), 'a step is a function')
refuses([[
local walk: iter = iter(0, 1)
]], 'takes its start and then its step', 'two arguments are not the curried shape')
check(not pcall(function() return counting(2):take('3') end), 'take takes a count')

-- The word: an iteration is a parameter's, a result's and a local's type.
check(program [[
local walk: iter = iter 5 do(state, control)
    if control >= state then return end
    return control + 1, control + 1
end
local take_two = do(source: iter): iter return source:take 2 end
local kept = 0
for value in take_two walk do kept += value end
return { kept = kept, control = walk.control }
]].kept == 3, 'typed local, typed parameter and typed result')
check(program [[
local nothing = iter (nil) do(state, control)
    return
end
local count = 0
for value in nothing do count += 1 end
return count
]] == 0, 'iter (nil) do(…) when the state is nothing')
refuses([[
local walk: iter = {}
]], 'expects iter, got a table', 'a typed local that is no iteration')
refuses([[
local f = do(x: iter): iter return x end
f { select, nil, nil }
]], 'expects iter, got a table', 'a triple is not an iteration')
refuses([[
local f = do(x: iter): iter return x end
f(pairs {})
]], 'expects iter, got a function', 'a bare iterator is not an iteration')
refuses([[
local f = do(n: Number): Number return n end
f(iter 0 do(state, control) return control + 1, control end)
]], 'expects Number, got an iteration', 'an iteration is named in the message')
check(R.describe_value(counting(1)) == 'an iteration', 'describe_value')
check(R.check(R.iter, counting(1)), 'the checker accepts an iteration')
check(not R.check(R.iter, {}), 'the checker refuses a table')
check(tostring(R.iter) == 'iter', 'the type names itself')

print(('iter: %d checks passed'):format(checks))
