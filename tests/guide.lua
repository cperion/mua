-- docs/designing-and-writing-mua.md cannot drift: its ```lua blocks form one program, read top to
-- bottom, translated and run together; a failed assert or error fails the check, and is reported
-- with the block it came from.
local root = arg[0]:match('^(.*)/tests/[^/]*$') or '.'
package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path
local mua = require 'mua.init'
local doc = assert(io.open(root .. '/docs/designing-and-writing-mua.md')):read '*a'
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
local source = table.concat(parts)
local chunk, err = mua.load(source, '=guide')
local ok, e = false, err
if chunk then ok, e = pcall(chunk) end
if ok then
    print(('guide: %d blocks ran'):format(n))
else
    local l = tonumber(tostring(e):match('^guide:(%d+):'))
    print(('FAIL  guide (block %s): %s'):format(l and block_of(l) or '?', tostring(e)))
    os.exit(1)
end
