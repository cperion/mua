local mua = require 'mua.init'
local outline = require 'mua.outline'
local M = {}
local usage = [[usage: mua outline FILE [args]
Executes FILE (including its side effects), then outlines its returned labels.
Functions are displayed, not called. Table fields are read without metamethods.
]]
local function pack(...) return { n = select('#', ...), ... } end
function M.run(argv)
    if argv[1] == '--help' or argv[1] == '-h' then io.stdout:write(usage); return 0 end
    if not argv[1] then io.stderr:write(usage); return 1 end
    local path, args = argv[1], {}
    for i = 2, #argv do args[#args + 1] = argv[i] end
    local previous = _G.arg
    _G.arg = { [0] = path }
    for i, value in ipairs(args) do _G.arg[i] = value end
    local ok, result = xpcall(function()
        local chunk, problem = mua.loadfile(path)
        if not chunk then error(problem, 0) end
        return outline.render(pack(chunk(unpack(args))))
    end, function(problem) return debug.traceback(tostring(problem), 2) end)
    _G.arg = previous
    if not ok then io.stderr:write(result, '\n'); return 1 end
    io.stdout:write(result)
    return 0
end
return M
