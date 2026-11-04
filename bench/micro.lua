-- Micro-benchmarks of what Mua emits against the Lua it replaces (ns per operation, steady state).
-- Allocations are kept alive in a ring so the JIT cannot sink them. Run from the repository root:
--   luajit bench/micro.lua
local root = arg[0]:match('^(.*)/bench/[^/]*$') or '.'
package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path
local mua=require'mua.init'
local function load_mua(src, opts) return assert(mua.load(src,'=bench',opts))() end
local function time(f, n)
  f(2000); collectgarbage(); collectgarbage()
  local t=os.clock(); f(n); return (os.clock()-t)/n*1e9
end
local rows={}
local function bench(group, name, f, n) rows[#rows+1]={group,name,time(f,n or 2e6)} end

-- allocations escape into a ring, so none can be sunk away
local ring_prefix = "local ring = {} local function keep(i, v) ring[i % 64 + 1] = v return v end "

bench('table','plain table, escaping', load_mua(ring_prefix..[[
return function(n) for i = 1, n do keep(i, { x = i, y = 2 }) end end]]))
bench('struct','struct (checked)', load_mua(ring_prefix..[[
local P = struct { x: Number, y: Number }
return function(n) for i = 1, n do keep(i, P { x = i, y = 2 }) end end]]))
bench('struct','struct (contracts off)', load_mua(ring_prefix..[[
local P = struct { x: Number, y: Number }
return function(n) for i = 1, n do keep(i, P { x = i, y = 2 }) end end]], { contracts = false })) 

bench('oneof','hand-written tagged table', load_mua(ring_prefix..[[
return function(n) local s = 0 for i = 1, n do local v = keep(i, { tag = 'a', value = i }) if v.tag == 'a' then s = s + v.value end end return s end]]))
bench('oneof','oneof construct', load_mua(ring_prefix..[[
local S = oneof { a: Number, b: Number }
return function(n) for i = 1, n do keep(i, S.a(i)) end end]]))
bench('oneof','oneof match (value prebuilt)', load_mua([[
local S = oneof { a: Number, b: Number }
local v = S.a(3)
return function(n) local s = 0 for i = 1, n do s = s + v { a(x) = x, b(x) = x * 2 } end return s end]]))

for _, keys in ipairs{2, 8} do
  local fields, names = {}, {}
  for k = 1, keys do fields[#fields+1] = ('k%d = %d'):format(k, k); names[#names+1] = 'k'..k end
  local sum = table.concat(names, ' + ')
  local lets = {}
  bench('opening', keys..'-key table, direct access', load_mua(ring_prefix..('local step = function(c) return c.k1 + c.k2 end local ctx = { %s } return function(n) local s = 0 for i = 1, n do s = s + step(ctx) end return s end'):format(table.concat(fields, ', '))))
  bench('opening', keys..'-key table, opened (do(c..))', load_mua(ring_prefix..('local step = do(c..) return k1 + k2 end local ctx = { %s } return function(n) local s = 0 for i = 1, n do s = s + step(ctx) end return s end'):format(table.concat(fields, ', '))))
end

for _, keys in ipairs{3, 10} do
  local fields, copy = {}, {}
  for k = 1, keys do fields[#fields+1] = ('k%d = %d'):format(k, k); copy[#copy+1] = ('k%d = base.k%d'):format(k, k) end
  bench('spread', keys..' fields, hand-written copy', load_mua(ring_prefix..('local base = { %s } return function(n) for i = 1, n do keep(i, { %s, extra = i }) end end'):format(table.concat(fields, ', '), table.concat(copy, ', '))), 5e5)
  bench('spread', keys..' fields, { ..base, extra = i }', load_mua(ring_prefix..('local base = { %s } return function(n) for i = 1, n do keep(i, { ..base, extra = i }) end end'):format(table.concat(fields, ', '))), 2e5)
end
bench('spread','two spreads (3 + 3 fields)', load_mua(ring_prefix..[[
local a = { x1 = 1, x2 = 2, x3 = 3 }
local b = { y1 = 1, y2 = 2, y3 = 3 }
return function(n) for i = 1, n do keep(i, { ..a, ..b, extra = i }) end end]]), 2e5)

bench('curry','closure per call: add s i', load_mua([[
local add = do(a) = do(b) = a + b
return function(n) local s = 0 for i = 1, n do s = add s i end return s end]]))
bench('curry','two-argument add(s, i)', load_mua([[
local add = function(a, b) return a + b end
return function(n) local s = 0 for i = 1, n do s = add(s, i) end return s end]]))

print(('%-8s %-40s %10s'):format('group','case','ns/op'))
for _, r in ipairs(rows) do print(('%-8s %-40s %10.1f'):format(r[1], r[2], r[3])) end
