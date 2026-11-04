-- Every example runs and prints what its `.expected` file says, and is formatted as `mua fmt`
-- writes it. Run from the repository root: luajit tests/examples.lua
local root = arg[0]:match('^(.*)/tests/[^/]*$') or '.'
local lua = "'" .. (arg[-1] or 'luajit') .. "'"
local function capture(command)
    local p = assert(io.popen(command .. ' 2>&1; printf "\\n__STATUS__%d\\n" "$?"'))
    local text = p:read '*a'; p:close()
    local out, status = text:match('^(.*)\n__STATUS__(%d+)\n$')
    return out, tonumber(status)
end
local function read(path)
    local fh = io.open(path, 'rb')
    if not fh then return nil end
    local text = fh:read '*a'; fh:close()
    return text
end
local passed, failed = 0, 0
local function check(name, ok, detail)
    if ok then passed = passed + 1
    else failed = failed + 1; print('FAIL  example: ' .. name .. (detail and ('\n' .. detail) or '')) end
end
local names = {}
for path in io.popen('ls ' .. root .. '/examples/*.mua'):lines() do names[#names + 1] = path end
check('examples were found', #names >= 8, #names)
for _, path in ipairs(names) do
    local name = path:match('([^/]+)%.mua$')
    local out, status = capture('cd ' .. root .. ' && timeout 30 ' .. lua .. ' mua.lua examples/' .. name .. '.mua')
    local expected = read(root .. '/examples/' .. name .. '.expected')
    check(name .. ' runs', status == 0, out)
    check(name .. ' prints what it should', expected ~= nil and out == expected, out)
    local _, fmt_status = capture('cd ' .. root .. ' && ' .. lua .. ' mua.lua fmt --check examples/' .. name .. '.mua')
    check(name .. ' is formatted', fmt_status == 0)
end
print(('examples: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
