-- Same language and same passes; only traversal protocols differ.
local root = arg[0]:match('^(.*)/tests/[^/]*$') or '.'
package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path
local mua = require 'mua.init'
local eager = assert(mua.loadfile(root .. '/examples/lisp.mua'))('library')
local pull = assert(mua.loadfile(root .. '/examples/lisp_pull.mua'))('library', eager)
local checks = 0
local function check(condition, name)
    assert(condition, name)
    checks = checks + 1
end
local function agree(source)
    check(eager.same(eager.read(source), pull.read(source)), 'reader: ' .. source)
    local before = eager.compile(source)
    local after = pull.compile(source)
    check(eager.same(before.tree, after.tree), 'tree: ' .. source)
    check(eager.same(before.instructions, after.instructions), 'IR: ' .. source)
    check(eager.same(before.optimized, after.optimized), 'optimized: ' .. source)
    check(before.lua == after.lua, 'Lua: ' .. source)
    local expected = eager.evaluate(before.tree, {})
    check(assert(loadstring(after.lua))() == expected, 'execution: ' .. source)
    check(assert(loadstring(eager.emit_lua(after.instructions)))() == expected, 'unoptimized: ' .. source)
    check(eager.same(pull.optimizer.optimize(after.optimized), after.optimized), 'fixed point: ' .. source)
end
-- Deterministic generated inputs; no global random state or external corpus.
local function expression(depth, seed)
    if depth == 0 then return tostring(seed % 9 - 4) end
    local left = expression(depth - 1, (seed * 17 + 3) % 997)
    local right = expression(depth - 1, (seed * 11 + 5) % 991)
    local operator = ({ '+', '-', '*' })[seed % 3 + 1]
    if seed % 4 == 0 then return '(if (< ' .. left .. ' ' .. right .. ') ' .. right .. ' ' .. left .. ')' end
    return '(' .. operator .. ' ' .. left .. ' ' .. right .. ')'
end
for seed = 1, 60 do agree(expression(3, seed)) end
for _, source in ipairs {
    '(define f (lambda (n) (if (< n 1) 0 (+ n (f (- n 1)))))) (f 12)',
    '(define f (lambda (x) (lambda (y) (if (< x y) (- y x) (- x y))))) ((f 9) 2)',
    '(let ((x 7)) (+ (let ((x 2)) x) x))',
    '(if (= 1 2) (= 2 2) (= 3 4))',
    '(define first (lambda (x) (+ x 1))) (define second (lambda (x) (first (first x)))) (second 8)',
    '\t( +\n 1\r\n 2 )\t',
} do agree(source) end
for _, source in ipairs { '', ' ', '123', '-0.5', '0x10', 'a;b', '() ()', '(a(b)c)', 'false nil' } do
    check(eager.same(eager.read(source), pull.read(source)), 'lexical equivalence: ' .. source)
end
for _, source in ipairs { '(', ')', '((1)', '(1))', '1 (', '(+ 1)', '(+ 1 missing)', '(if 1 2)', '1 2' } do
    local accepted, reason = pcall(eager.compile, source)
    local pull_accepted, pull_reason = pcall(pull.compile, source)
    check(not accepted and not pull_accepted and reason == pull_reason, 'refusal: ' .. source)
end
-- Each invocation gets a fresh work table; nested collection cannot replace the
-- outer buffer. A handler answers with a cursor: `pull.single` is one step, `pull.empty` none,
-- and a raw iterator (here ipairs) still answers several replacements.
local outer_state = {}
local output = pull.rewrite(function(node, work)
    if node == 1 then
        local nested = pull.rewrite(function(inner) return pull.single(inner + 10) end, { 3 }, work)
        check(nested[1] == 13 and #work.written == 0, 'nested buffer is private')
        return ipairs { node, node + 1 }
    end
    return pull.empty()
end, { 1, 2 }, outer_state)
check(#output == 2 and output[1] == 1 and output[2] == 2 and outer_state.written == nil, 'rewrite ownership')
for _, value in ipairs { false, 0, 'value' } do
    local seen = 0
    for _, item in pull.single(value) do
        check(item == value, 'singleton payload')
        seen = seen + 1
    end
    check(seen == 1, 'singleton ends')
end
check(pull.empty()() == nil and #pull.rewrite(pull.empty, { 1, 2 }, {}) == 0, 'an empty answer replaces nothing')
check(select('#', pull.single('x')) == 3, 'a single answer is a triple, not a table')
local cursor = pull.forms('1 (')
check(cursor.state.position == 1 and cursor.control == 0, 'no prefetch')
check(cursor() == 1 and cursor.state.position == 2 and cursor.control == 2, 'one datum')
check(not pcall(cursor), 'deferred error')
-- The same cursor is the triple plain Lua iterates: no adapter for a Lua Fun style consumer.
local paired = pull.forms('5 6 7')
local pairs_seen = {}
for control, value in paired.step, paired.state, paired.control do
    pairs_seen[#pairs_seen + 1] = control .. ':' .. value
end
check(table.concat(pairs_seen, ' ') == '2:5 4:6 6:7', 'the triple view answers control and value')
print(('Lisp pull: %d checks passed'):format(checks))
