-- Mua: the Lua dialect (design macro-layer.md). Sugared Lua in, plain Lua out.
--
--   mua.parse(source, filename, host)        -> AST, tokens
--   mua.translate(source, filename, opts)    -> Lua text (opts.host, opts.contracts)
--   mua.load(source, chunkname, opts)        -> function | nil, error (as loadstring); opts.cache = a bytecode cache directory
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
-- The bytecode cache (opts.cache = a directory): the translation of a source is loaded as
-- LuaJIT bytecode that an earlier load wrote, keyed by everything that decides what a source
-- means: its text, the chunk name, the contracts switch, Mua's version, LuaJIT's, and the
-- host's `id` (a host that changes what forms mean must say so; without an id a host's loads
-- are not cached).
local bit = require 'bit'
local function fnv(s, h)
    for i = 1, #s do
        h = bit.band(bit.bxor(h, s:byte(i)) * 16777619, 0xffffffff)
    end
    return h
end
local function cache_path(source, chunkname, opts)
    local host = opts.host
    if host and not host.id then return nil end
    local key = table.concat({ M.version, jit and jit.version or '', tostring(opts.contracts ~= false),
        host and host.id or '', chunkname, #source }, '\0')
    local a, b = fnv(key .. '\0' .. source, 2166136261), fnv(source .. '\0' .. key, 5381)
    return ('%s/mua-%08x%08x.luac'):format(opts.cache, a, b)
end

function M.load(source, chunkname, opts)
    chunkname = chunkname or '=(Mua)'
    opts = opts or {}
    local cached = opts.cache and cache_path(source, chunkname, opts)
    if cached then
        local fh = io.open(cached, 'rb')
        if fh then
            local bytecode = fh:read '*a'
            fh:close()
            local chunk = loadstring(bytecode, chunkname)
            if chunk then return chunk end
        end
    end
    local filename = chunkname:gsub('^[@=]', '')
    local ok, text = pcall(M.translate, source, filename, opts)
    if not ok then return nil, text end
    local chunk, err = loadstring(text, chunkname)
    if chunk and cached then
        local fh = io.open(cached, 'wb')
        if fh then fh:write(string.dump(chunk)); fh:close() end
    end
    return chunk, err
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
