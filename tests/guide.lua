-- docs/designing-and-writing-mua.md cannot drift: every ```lua block is a self-contained Mua
-- program, translated and run; a failed assert or error fails the check.
local root = arg[0]:match('^(.*)/tests/[^/]*$') or '.'
package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path
local mua = require 'mua.init'
local doc = assert(io.open(root .. '/docs/designing-and-writing-mua.md')):read '*a'
local passed, failed = 0, 0
local n = 0
for block in doc:gmatch('```lua\n(.-)```') do
    n = n + 1
    local chunk, err = mua.load(block, '=guide block ' .. n)
    local ok, e = false, err
    if chunk then ok, e = pcall(chunk) end
    if ok then passed = passed + 1 else failed = failed + 1; print(('FAIL  guide block %d: %s'):format(n, tostring(e))) end
end
print(('guide: %d blocks run, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
