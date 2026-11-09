-- Named builtins share human labels, without making those labels dispatch keys.
local R = require 'mua.runtime'
local outline = require 'mua.outline'
for _, name in ipairs { 'Number', 'String', 'Boolean', 'Table', 'Function', 'Any', 'Unit' } do
    assert(R.label_of(R[name]) == name)
end
local Positive = R.checker('Positive')(function(n) return type(n) == 'number' and n > 0 end)
assert(R.label_of(Positive) == 'Positive')
assert(R.label_of(R.Optional(Positive)) == 'Optional(Positive)')
R.label('a positive quantity')(Positive)
assert(R.contract_text(Positive) == 'a positive quantity')
assert(R.check(Positive, 1) and not R.check(Positive, -1))
local Point = R.struct('Point', { { 'x', R.Number } })
local F = R.family('Geometry')
F { Point }
assert(R.label_of(Point) == 'Point' and R.label_of(F) == 'Geometry')
local a, b = Point { x = 1 }, Point { x = 2 }
assert(R.label_of(a) == 'Point')
local mt = getmetatable(a)
R.label('origin')(a)
R.label('Coordinates')(Point)
R.label('Shapes')(F)
assert(getmetatable(a) == mt and getmetatable(b) == mt)
assert(R.label_of(b) == 'Point')
assert(F.is(a, Point) and R.check(Point, a))
local pass = F.pass('read x')({ Point = function(node) return node.x end })
assert(R.label_of(pass) == 'read x' and pass(a) == 1)
local Sum = R.oneof('Outcome', { { 'ok', R.Number }, { 'cancel', R.Unit } })
assert(R.label_of(Sum) == 'Outcome')
assert(R.label_of(Sum.ok) == 'Outcome.ok')
local result = Sum.ok(42)
assert(R.label_of(result) == 'Outcome')
R.label('answer')(result)
R.label('Accepted')(Sum.ok)
assert(result { ok = function(n) return n end, cancel = function() return 0 end } == 42)
local CPoint = R.ffistruct('CPoint', { { 'x', 'double' } })
local p = CPoint { x = 3 }
assert(R.label_of(CPoint) == 'CPoint' and R.label_of(p) == 'CPoint')
R.label('C origin')(p)
assert(R.label_of(p) == 'C origin' and R.check(CPoint, p))
assert(R.label_of(CPoint { x = 4 }) == 'CPoint')
R.label('native coordinates')(CPoint)
assert(R.label_of(CPoint) == 'native coordinates')
assert(R.label_of(p) == 'C origin' and R.label_of(CPoint { x = 5 }) == 'CPoint')
local ffi = require 'ffi'
local Hostile = ffi.metatype('struct { int value; }', {
    __tostring = function() error('outline must not stringify cdata') end,
})
local hostile = R.label('opaque native value')(Hostile())
assert(outline.render({ n = 1, hostile }):find('opaque native value', 1, true))
local view = R.specialized { mode = 'auto' }
local Fast = view.struct('Fast', { { 'x', R.Number } })
assert(R.label_of(Fast) == 'Fast' and R.label_of(Fast { x = 2 }) == 'Fast')
local tree = outline.render({ n = 1, { Point = Point, F = F, CPoint = CPoint, check = Positive } })
assert(tree:find('Coordinates', 1, true) and tree:find('native coordinates', 1, true))
print('named labels: passed')
