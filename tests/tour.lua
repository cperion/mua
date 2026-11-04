-- docs/reading-mua.md cannot drift: its first five `mua` blocks (the function as written and
-- the four steps of undoing its sugar) print what the page says, every other `mua` block runs,
-- and the translation listing is what `mua -d` writes for the first block.
local root = arg[0]:match('^(.*)/tests/[^/]*$') or '.'
package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path
local mua = require 'mua.init'
local lex = require 'mua.lex'
local doc = assert(io.open(root .. '/docs/reading-mua.md')):read '*a'
local passed, failed = 0, 0
local function check(name, ok, detail)
    if ok then passed = passed + 1
    else failed = failed + 1; print('FAIL  tour: ' .. name .. (detail and ('\n' .. tostring(detail)) or '')) end
end
local function run(source, label)
    local chunk, err = mua.load(source, '=' .. label)
    if not chunk then return nil, err end
    local lines = {}
    local env = setmetatable({ print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[i] = tostring((select(i, ...))) end
        lines[#lines + 1] = table.concat(parts, '\t')
    end }, { __index = _G })
    setfenv(chunk, env)
    local ok, e = pcall(chunk)
    if not ok then return nil, e end
    return table.concat(lines, '\n')
end
local blocks = {}
for block in doc:gmatch('```mua\n(.-)```') do blocks[#blocks + 1] = block end
local texts = {}
for block in doc:gmatch('```text\n(.-)```') do texts[#texts + 1] = block end
check('the page has its blocks', #blocks >= 6, #blocks)

local expected
for _, t in ipairs(texts) do
    if t:match('^begin import') then expected = t:gsub('\n$', '') end
end
check('the page says what the function prints', expected ~= nil)
for i, block in ipairs(blocks) do
    local out, err = run(block, 'block ' .. i)
    check('block ' .. i .. ' runs', out ~= nil, err)
    if i <= 5 then check('block ' .. i .. ' prints the same four lines', out == expected, out) end
end

-- the translation listing, compared token by token
local function tokens(text)
    local out = {}
    for _, tk in ipairs(lex.scan(text, 'listing')) do
        if tk.t ~= 'space' and tk.t ~= 'comment' and tk.t ~= 'eof' then out[#out + 1] = tk.v end
    end
    return table.concat(out, ' ')
end
local listing
for _, t in ipairs(texts) do
    if t:match('^local __mua = __mua or') then listing = t end
end
check('the page lists the translation', listing ~= nil)
if listing then
    local translated = mua.translate(blocks[1], 'listing')
    check('the listing is what mua -d writes', tokens(translated) == tokens(listing), translated)
end
print(('tour: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
