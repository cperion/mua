-- Mua: the Lua dialect (design macro-layer.md). Sugared Lua in, plain Lua out.
--
--   mua.parse(source, filename, host)        -> AST, tokens
--   mua.translate(source, filename, opts)    -> Lua text (opts.host, opts.contracts)
--   mua.load(source, chunkname, opts)        -> function | nil, error (as loadstring)
--   mua.loadfile(path, opts)                 -> function | nil, error
--   mua.searcher(opts)                       -> a package.loaders entry for Mua modules

local parse = require 'mua.parse'
local emit = require 'mua.emit'

local M = { version = 1 }

function M.parse(source, filename, host) return parse.parse(source, filename, host) end

function M.translate(source, filename, opts)
    opts = opts or {}
    local block = parse.parse(source, filename, opts.host)
    local text = emit.emit(block, { filename = filename, host = opts.host, contracts = opts.contracts })
    -- as many lines as the source: a chunk lines up with it to the end
    local _, want = source:gsub('\n', '')
    local _, have = text:gsub('\n', '')
    if have < want then text = text .. ('\n'):rep(want - have) end
    return text
end

-- errors keep LuaJIT's shape: `file:line: message`
function M.load(source, chunkname, opts)
    chunkname = chunkname or '=(Mua)'
    local filename = chunkname:gsub('^[@=]', '')
    local ok, text = pcall(M.translate, source, filename, opts)
    if not ok then return nil, text end
    return loadstring(text, chunkname)
end

function M.loadfile(path, opts)
    local fh, err = io.open(path, 'rb')
    if not fh then return nil, err end
    local source = fh:read '*a'
    fh:close()
    return M.load(source, '@' .. path, opts)
end

-- a searcher for package.loaders: Mua modules on `path` (default package.path)
function M.searcher(opts)
    opts = opts or {}
    return function(name)
        local file, err = package.searchpath(name, opts.path or package.path)
        if not file then return err end
        local chunk, lerr = M.loadfile(file, opts)
        if not chunk then error(lerr, 0) end
        return chunk
    end
end

return M
