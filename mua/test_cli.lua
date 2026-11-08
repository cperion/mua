-- mua.test_cli: `mua test files…` runs the cases Mua files name with `test "…":` (runtime
-- `test`, `collect`). Each file is loaded and run with its cases collected, then every case
-- runs, in order. A failure is reported with its file, its name and a traceback.
--
--   mua test file.mua…                 run the cases of these files
--   mua test --match text file.mua…    only cases whose name contains text
--
-- Exit status: 0 when every case passed, 1 when a file did not load or run or a case failed,
-- 2 for a usage error. A host runner can call `run_files(paths, opts)` with its own loading
-- options (opts.load, opts.match) and reporting.

local mua = require 'mua.init'
local runtime = require 'mua.runtime'

local M = {}

local USAGE = 'usage: mua test [--match text] file.mua...\n'

-- run the cases of `paths`; opts.load(path) -> chunk | nil, error (default: mua.loadfile with
-- contracts on), opts.match (a plain substring of the names to run), opts.report(line)
-- (default: print). Answers passed, failed.
function M.run_files(paths, opts)
    opts = opts or {}
    local load = opts.load or function(path) return mua.loadfile(path, { contracts = true }) end
    local report = opts.report or print
    local passed, failed = 0, 0
    for _, path in ipairs(paths) do
        local chunk, problem = load(path)
        local cases
        if chunk then
            local ok, collected = pcall(runtime.collect, chunk)
            if ok then cases = collected else problem = collected end
        end
        if not cases then
            failed = failed + 1
            report(('FAIL %s: %s'):format(path, tostring(problem)))
        else
            for _, case in ipairs(cases) do
                if not opts.match or case.name:find(opts.match, 1, true) then
                    local ok, why = xpcall(case.run, function(e) return debug.traceback(tostring(e), 2) end)
                    if ok then
                        passed = passed + 1
                    else
                        failed = failed + 1
                        report(('FAIL %s: %s\n%s'):format(path, case.name, why))
                    end
                end
            end
        end
    end
    report(('%d passed, %d failed'):format(passed, failed))
    return passed, failed
end

function M.run(argv)
    local paths, match = {}, nil
    local i = 1
    while argv[i] do
        local a = argv[i]
        if a == '--match' then
            match = argv[i + 1]
            if not match then io.stderr:write(USAGE); return 2 end
            i = i + 1
        elseif a == '-h' or a == '--help' then
            io.stdout:write(USAGE)
            return 0
        elseif a:sub(1, 1) == '-' then
            io.stderr:write('mua test: unknown option ' .. a .. '\n' .. USAGE)
            return 2
        else
            paths[#paths + 1] = a
        end
        i = i + 1
    end
    if #paths == 0 then io.stderr:write(USAGE); return 2 end
    local _, failed = M.run_files(paths, { match = match })
    return failed == 0 and 0 or 1
end

return M
