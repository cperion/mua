-- mua lint: the two rules, and the outline that shows whether they were followed.
local root = arg[0]:match('^(.*)/tests/[^/]*$') or '.'
package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path
local lint = require 'mua.lint'
local checks = 0
local function check(condition, name)
    assert(condition, name)
    checks = checks + 1
end

local function findings(source)
    return lint.findings(source, 'source.mua')
end

-- the declaration rules, which the file's own rule is reported separately from
local function kinds(source)
    local listed = {}
    for _, finding in ipairs(findings(source)) do
        if finding.kind ~= 'file' then listed[#listed + 1] = finding.kind .. ':' .. finding.line end
    end
    return table.concat(listed, ' ')
end

local function file_rule(source)
    for _, finding in ipairs(findings(source)) do
        if finding.kind == 'file' then return finding.detail .. ':' .. finding.line end
    end
    return 'none'
end

-- a file opens by saying what it is for, and a rule of dashes is not a description
check(file_rule('-- What this file is for.\nlocal value = 1\n') == 'none', 'a written opening')
check(file_rule('\n\n-- What this file is for.\nlocal value = 1\n') == 'none', 'after blank lines')
check(file_rule('local value = 1\n') == 'code:1', 'code first')
check(file_rule('-- ----------\nlocal value = 1\n') == 'rule:1', 'a rule of dashes')
check(file_rule('-- =====\n-- ====\nlocal value = 1\n') == 'rule:1', 'rules of equals')
check(file_rule('-- What this file is for.\n-- ----------\nlocal value = 1\n') == 'none',
    'words before a rule')

-- a declaration at the file's own level says what it is for
check(kinds('-- What the total is for.\nlocal total = 0\n') == '', 'documented above')
check(kinds('local total = 0 -- What the total is for.\n') == '', 'documented beside')
check(kinds('local total = 0\n') == 'undocumented:1', 'a bare declaration')
check(kinds('-- One.\nlocal a = 1\nlocal b = 2\n-- Two.\nlocal c = 3\n') == 'undocumented:3',
    'only the bare one')

-- and it does not open by naming what the declaration already names
check(kinds('-- `total` is what the sum is for.\nlocal total = 0\n') == 'repeats:2', 'backticked name')
check(kinds('-- total is what the sum is for.\nlocal total = 0\n') == 'repeats:2', 'bare name')
check(kinds('-- What the sum is for.\nlocal total = 0\n') == '', 'no name')
check(kinds('-- Total up the readings.\nlocal total = 0\n') == '', 'a word that starts the same')

-- a declaration inside a block is explained by the block: the outline shows the file's level, and
-- a block's own locals only when someone commented them
local blocky = [[
-- What the reading is.
local reading = 1
if reading > 0 then
    local scaled = reading * 2
    print(scaled)
end
]]
check(kinds(blocky) == '', 'a block explains its locals')

local outlined = lint.outline(blocky, 'source.mua')
check(outlined:find('^source%.mua — 1 declaration\n') == 1, 'a title with the count')
check(outlined:find(' 2  local reading = 1\n', 1, true) ~= nil, 'the declaration, numbered')
check(outlined:find('        What the reading is.', 1, true) ~= nil, 'its comment, indented')
check(not outlined:find('local scaled', 1, true), 'an uncommented block local stays out')

-- a commented block local joins the outline at the column it is written at
local nested = [[
-- What the reading is.
local reading = 1
do
    -- Where the doubled reading is kept.
    local doubled = reading * 2
    print(doubled)
end
]]
local deep = lint.outline(nested, 'source.mua')
check(deep:find('   5      local doubled = reading * 2', 1, true) ~= nil,
    'a commented block local at its column')
check(deep:find('              Where the doubled reading is kept.', 1, true) ~= nil, 'under it')
check(deep:find('— 2 declarations', 1, true) ~= nil, 'the count includes it')

-- banner comments become headings, and a longer opening block becomes the file's own words
local sectioned = [[
-- A file about readings.
--
-- It exists to show headings and a preamble.

-- Readings
-- --------

-- What the reading is.
local reading = 1
]]
local poem = lint.outline(sectioned, 'source.mua')
check(poem:find('\nReadings\n--------\n', 1, true) ~= nil, 'a heading')
check(poem:find('A file about readings.', 1, true) ~= nil, 'the preamble')
check(poem:find('It exists to show headings and a preamble.', 1, true) ~= nil, 'its second paragraph')

-- long bracket comments hold data, not prose: counted, not printed
local withdata = [[
-- What the value is for.
local value = 1
--[=[ output
1
]=]
]]
local counted = lint.outline(withdata, 'source.mua')
check(counted:find('1 long comment not shown', 1, true) ~= nil, 'a long comment is counted')
check(not counted:find('output', 1, true), 'and not printed')

print(('lint: %d checks passed'):format(checks))
