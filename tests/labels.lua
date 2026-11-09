-- Human labels never change identity, fields, contracts or calling behavior.
local R = require 'mua.runtime'
local plain = {}
assert(R.label('plain')(plain) == plain)
assert(R.label_of(plain) == 'plain' and next(plain) == nil)
assert(getmetatable(plain).__label == 'plain')
local mt = { __label = 'shared', __index = { answer = 42 } }
local a, b = setmetatable({}, mt), setmetatable({}, mt)
R.label('individual')(a)
assert(getmetatable(a) == mt and a.answer == 42)
assert(R.label_of(a) == 'individual' and R.label_of(b) == 'shared')
assert(mt.__label == 'shared' and next(a) == nil)
local f = function(x) return x + 1 end
assert(R.label('increment')(f) == f and f(3) == 4)
assert(R.label_of(f) == 'increment')
local protected = setmetatable({}, { __metatable = false })
assert(R.label('protected')(protected) == protected)
assert(R.label_of(protected) == 'protected')
assert(R.label_of(nil) == nil and R.label_of(3) == nil)
assert(not pcall(R.label, 3))
assert(not pcall(R.label('bad'), 3))
local mua = require 'mua.init'
local chunk = assert(mua.load([[
local words = label "words" define answer = 42 end
assert(label_of words == "words")
local F = family "expressions"
local N = struct { value: Number }
F { N }
local handlers = label "evaluate" define
    N = do(node) return node.value end
end
local evaluate = F.pass handlers
assert(label_of evaluate == "evaluate")
local n = N { value = 7 }
label "seven" n
assert(F.is(n, N))
assert(evaluate(n) == 7)
assert(F.pass "legacy" handlers (n) == 7)
]]))
chunk()
print('labels: passed')
