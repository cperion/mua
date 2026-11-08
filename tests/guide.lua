-- The design, compiler and component guides cannot drift: each one's ```lua blocks form one
-- program, read top to bottom, translated and run together; a failed assert or error fails the
-- check, and is reported with the block it came from.
local root = arg[0]:match('^(.*)/tests/[^/]*$') or '.'
package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path
local mua = require 'mua.init'
local fmt = require 'mua.fmt'
local function check_doc(file, label)
local doc = assert(io.open(root .. '/docs/' .. file)):read '*a'
local parts, starts, line, n = {}, {}, 1, 0
for block in doc:gmatch('```lua\n(.-)```') do
    n = n + 1
    starts[#starts + 1] = { line = line, block = n }
    parts[#parts + 1] = block
    local _, lines = block:gsub('\n', '')
    line = line + lines
end
local function block_of(l)
    local found = 1
    for _, s in ipairs(starts) do if s.line <= l then found = s.block end end
    return found
end
-- the blocks are written as the formatter writes them (the house style)
local unformatted = 0
for i, block in ipairs(parts) do
    local ok, formatted = pcall(fmt.format, block, nil, label .. ' block ' .. i)
    if not ok or formatted ~= block then
        unformatted = unformatted + 1
        print(('FAIL  %s block %d is not formatted as mua fmt writes it'):format(label, i))
    end
end
if unformatted > 0 then os.exit(1) end
local source = table.concat(parts)
local chunk, err = mua.load(source, '=' .. label)
local ok, e = false, err
if chunk then ok, e = pcall(chunk) end
if ok then
    print(('%s: %d blocks ran'):format(label, n))
else
    local l = tonumber(tostring(e):match('^' .. label .. ':(%d+):'))
    print(('FAIL  %s (block %s): %s'):format(label, l and block_of(l) or '?', tostring(e)))
    os.exit(1)
end
end
check_doc('designing-and-writing-mua.md', 'guide')
check_doc('writing-compilers.md', 'compilers')
check_doc('component-patterns.md', 'components')
