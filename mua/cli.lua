-- mua.cli: the `mua` command. Run a Mua file, dump what it translates to, or run an expression.
--
--   mua [options] file.mua [args]      run a file (a Mua program), passing it `args`
--   mua -e 'code'                      run a chunk of Mua
--   mua -d file.mua                    print the Lua a file translates to
--   mua --no-contracts ...             translate without the contract checks
--   mua -l module ...                  require a module first
--   mua fmt [--check | --write] files  format Mua source (see mua/fmt_cli.lua)
--   mua outline file.mua [args]        execute a file and outline its returned labels
--   MUA_CACHE=dir mua ...              keep translated chunks as bytecode in dir (mua.load opts.cache)
--
-- Exit status: 0, or 1 for a translation error, a missing file or an uncaught error (reported on
-- stderr with a traceback that names the Mua source's lines).

local mua = require 'mua.init'

local M = {}

local USAGE = [[
usage: mua [options] file.mua [args]
  outline FILE     execute FILE and outline its returned labels (has side effects)
  -e code          run a chunk of Mua
  -d               print the translation of the file instead of running it
  -l module        require a module before running
  --no-contracts   translate without the contract checks
]]

local function fail(message)
    io.stderr:write(message, '\n')
    return 1
end

local function read(path)
    local fh, err = io.open(path, 'rb')
    if not fh then return nil, err end
    local text = fh:read '*a'
    fh:close()
    return text
end

-- run a loaded chunk with the traceback of an error written to stderr
local function run(chunk, args)
    local results = { xpcall(chunk, function(e) return debug.traceback(tostring(e), 2) end, unpack(args)) }
    if not results[1] then return fail(results[2]) end
    return 0
end

local function main(argv, opts)
    if argv[1] == 'lint' then
        return fail('mua lint has been retired; mua outline FILE executes code and reads returned labels')
    end
    for _, command in ipairs { 'fmt', 'outline' } do
        if argv[1] == command then
            local rest = {}
            for j = 2, #argv do rest[#rest + 1] = argv[j] end
            return require('mua.' .. command .. '_cli').run(rest)
        end
    end
    local expression, dump, libraries = nil, false, {}
    local i = 1
    while argv[i] and argv[i]:sub(1, 1) == '-' and argv[i] ~= '-' do
        local a = argv[i]
        if a == '-e' then expression = argv[i + 1]; i = i + 1
        elseif a == '-d' then dump = true
        elseif a == '-l' then libraries[#libraries + 1] = argv[i + 1]; i = i + 1
        elseif a == '--no-contracts' then opts.contracts = false
        elseif a == '-h' or a == '--help' then io.stdout:write(USAGE); return 0
        else return fail('mua: unknown option ' .. a .. '\n' .. USAGE) end
        i = i + 1
    end
    for _, name in ipairs(libraries) do
        local ok, err = pcall(require, name)
        if not ok then return fail(tostring(err)) end
    end
    local rest = {}
    for j = i + (expression and 0 or 1), #argv do rest[#rest + 1] = argv[j] end
    if expression then
        if dump then
            local ok, text = pcall(mua.translate, expression, '(command line)', opts)
            if not ok then return fail(tostring(text)) end
            io.stdout:write(text, '\n')
            return 0
        end
        local chunk, err = mua.load(expression, '=(command line)', opts)
        if not chunk then return fail(tostring(err)) end
        return run(chunk, rest)
    end
    local path = argv[i]
    if not path then io.stderr:write(USAGE); return 1 end
    local source, err = read(path)
    if not source then return fail('mua: ' .. tostring(err)) end
    if dump then
        local ok, text = pcall(mua.translate, source, path, opts)
        if not ok then return fail(tostring(text)) end
        io.stdout:write(text)
        return 0
    end
    local chunk, lerr = mua.load(source, '@' .. path, opts)
    if not chunk then return fail(tostring(lerr)) end
    -- the script sees itself as arg[0], and its own arguments after it
    local script_arg = { [0] = path }
    for j, a in ipairs(rest) do script_arg[j] = a end
    _G.arg = script_arg
    return run(chunk, rest)
end

-- A Mua program can require Mua libraries. Scope the searcher to this invocation so an
-- embedding caller does not accumulate loaders or inherit another invocation's contracts.
function M.main(argv)
    local opts = { contracts = true, cache = os.getenv('MUA_CACHE') }
    local searcher = mua.searcher(opts)
    table.insert(package.loaders, 2, searcher)
    local ok, result = pcall(main, argv, opts)
    for index, loader in ipairs(package.loaders) do
        if loader == searcher then table.remove(package.loaders, index); break end
    end
    if not ok then error(result, 0) end
    return result
end

return M
