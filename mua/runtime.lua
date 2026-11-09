-- mua.runtime: what emitted Mua code calls (design macro-layer.md §4.5–§4.8). Plain
-- Lua. A host replaces entries by giving its chunks a global `__mua` built with extend().
--
-- Costs are paid where a value is built (a keyed spread, a struct or oneof value, a contract
-- check), never per name access (design E1).

local R = {}
local unpack = unpack or table.unpack

-- describing values and checkers, for diagnostics ----------------------------------------------

local checkers = setmetatable({}, { __mode = 'k' })     -- checker -> { name, test }
local structs = setmetatable({}, { __mode = 'k' })      -- struct type -> { name, fields, index, meta }
local sums = setmetatable({}, { __mode = 'k' })         -- oneof type -> { name, alts, index, meta }
local closed = setmetatable({}, { __mode = 'k' })       -- closed structural type -> { declared names }
local instance_of = setmetatable({}, { __mode = 'k' })  -- instance metatable -> its struct or oneof
local iterations = setmetatable({}, { __mode = 'k' })   -- an iteration's metatable -> true
-- ffistruct ctypes by their printed form (`ctype<struct tag>`: a ctype object is not interned, so
-- it cannot be a table key) -> { name, tag }
local ctypes = {}
local function ctype_info(ct) return ctypes[tostring(ct)] end
local ffi_loaded
local function ffi() ffi_loaded = ffi_loaded or require 'ffi'; return ffi_loaded end

local function describe_value(v)
    local mt = type(v) == 'table' and getmetatable(v)
    local owner = mt and instance_of[mt]
    if owner then
        if structs[owner] then return 'a ' .. structs[owner].name end
        return ('%s.%s'):format(sums[owner].name, rawget(v, 'tag'))
    end
    if mt and iterations[mt] then return 'an iteration' end
    if type(v) == 'cdata' then
        local ct = ffi().typeof(v)
        return 'a ' .. (ctype_info(ct) and ctype_info(ct).name or tostring(ct))
    end
    if type(v) == 'string' then
        local s = #v > 20 and (v:sub(1, 17) .. '...') or v
        return ('a string %q'):format(s)
    end
    if type(v) == 'number' or type(v) == 'boolean' then return ('%s %s'):format(type(v), tostring(v)) end
    if v == nil then return 'nil' end
    return 'a ' .. type(v)
end
R.describe_value = describe_value

function R.describe(T)
    local label = R.label_of and R.label_of(T)
    if type(label) == 'string' then return label end
    if checkers[T] then return checkers[T].name end
    if structs[T] then return structs[T].name end
    if sums[T] then return sums[T].name end
    if closed[T] then return 'a closed structural type' end
    if type(T) == 'cdata' then return ctype_info(T) and ctype_info(T).name or tostring(T) end
    if type(T) == 'function' then return 'a predicate' end
    return describe_value(T)
end

-- the structural markers (design §4.6) ----------------------------------------------------------

R.required = setmetatable({}, { __tostring = function() return 'required' end })
R.optional = setmetatable({}, { __tostring = function() return 'optional' end })

-- the names a closed type declares: its string keys, the markers' included
function R.closed(t)
    if type(t) ~= 'table' then error(('closed: a %s is not a structural type'):format(type(t)), 2) end
    local declared = {}
    for k in pairs(t) do if type(k) == 'string' then declared[k] = true end end
    closed[t] = declared
    return t
end

-- keyed spread: `{ ..a, name = v, ..b }` arrives as a table whose spreads sit under marked keys,
-- numbered in source order; the rest are its fields --------------------------------------------

local marks = {}
function R.spread_mark(n)
    local m = marks[n]
    if not m then
        m = setmetatable({ spread = n }, { __tostring = function() return '..' end })
        marks[n] = m
    end
    return m
end
local function is_mark(k) return type(k) == 'table' and marks[rawget(k, 'spread') or 0] == k end

-- The value a keyed spread builds. One pass over the constructor's table gives the explicit
-- fields (which win wherever they are written) and how many spreads there are; each spread's
-- string keys are then copied in source order, skipping the explicit ones. Nothing is sorted and
-- nothing is built that the result does not need. A field two spreads give is an error, named in
-- sorted order so the message does not depend on how the table was walked. `required` fields
-- must be supplied, `optional` ones left out are absent; a spread of a closed type admits only
-- the fields it declares, and the result is closed too.
local function overlap(src, from, i, explicit)
    local names = {}
    for name in pairs(src) do
        if type(name) == 'string' and from[name] ~= nil and from[name] ~= i and explicit[name] == nil then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    error(("spread-overlap: field '%s' comes from two spreads"):format(names[1]), 3)
end

function R.keyed(t)
    local fields, maxn, marked = {}, 0, false
    for k, v in pairs(t) do
        if type(k) == 'string' then
            fields[k] = v
            if v == R.required or v == R.optional then marked = true end
        elseif is_mark(k) then
            if k.spread > maxn then maxn = k.spread end
        else error('spread-context: a keyed spread admits only `name = value` items and spreads', 2) end
    end
    local declared, from
    for i = 1, maxn do
        local src = t[marks[i]]
        if src ~= nil then
            if type(src) ~= 'table' then
                error(('spread-source: a %s has no entries to spread (spread a table)'):format(type(src)), 2)
            end
            local d = closed[src]
            if d then
                declared = declared or {}
                for k in pairs(d) do declared[k] = true end
            end
            if maxn > 1 then from = from or {} end
            for name, value in pairs(src) do
                if type(name) == 'string' then
                    if from then
                        -- two spreads offering one name clash, unless the block names that field itself
                        if from[name] ~= nil and from[name] ~= i and t[name] == nil then overlap(src, from, i, t) end
                        from[name] = i
                    end
                    if t[name] == nil then
                        fields[name] = value
                        if value == R.required or value == R.optional then marked = true end
                    end
                end
            end
        end
    end
    if declared then
        for k in pairs(t) do
            if type(k) == 'string' and not declared[k] then
                error(("closed: '%s' is not a field of this structural type"):format(k), 2)
            end
        end
    end
    if marked then
        for k, v in pairs(fields) do
            if v == R.required then error(("required: the field '%s' is not supplied"):format(k), 2) end
            if v == R.optional then fields[k] = nil end
        end
    end
    if declared then closed[fields] = declared end
    return fields
end

-- `with ... end` where an expression starts: the table itself, which a contract may fill in. A
-- table marked here (weakly: it gets no metatable, so it is a plain table to everything else)
-- that meets a `struct` in a contract (a typed local, parameter or result, a struct's field)
-- becomes an instance of it, in place, checked as `T { … }` is. A host may give it other meaning.
local contextual = setmetatable({}, { __mode = 'k' })
function R.with(t)
    if type(t) == 'table' then contextual[t] = true end
    return t
end

-- `define` is a block, not a function: a program that still calls it (and binds no `define` of
-- its own) is told what to write
function R.define()
    error("define opens a block of entries closed by `end` and is a table; "
        .. "to write a table in braces, write { … }", 2)
end

-- `meta` installs a vocabulary as a metatable: `meta { index = …, tostring = … }` copies its
-- entries under `__` names (`__index`, `__tostring`; a name that already starts `__` is kept) and
-- returns a function that sets that metatable on a table and gives the table back. Every table
-- it is given shares the one metatable. It is the plain Lua counterpart of a struct's methods:
-- it brands nothing and checks nothing.
function R.meta(vocabulary)
    if type(vocabulary) ~= 'table' then
        error(('meta takes a table of metamethods (index, tostring, add, …), got %s'):format(describe_value(vocabulary)), 2)
    end
    local mt = {}
    for key, value in pairs(vocabulary) do
        if type(key) ~= 'string' then
            error(('meta names its metamethods: a %s key has no name (write index = …, tostring = …)'):format(type(key)), 2)
        end
        mt[key:sub(1, 2) == '__' and key or '__' .. key] = value
    end
    return function(t)
        if type(t) ~= 'table' then error(('meta applies to a table, got %s'):format(describe_value(t)), 2) end
        return setmetatable(t, mt)
    end
end

-- `f(a, ..t)`: the array part of t, as the call's last arguments
-- Human-facing identity only. Never replace an existing metatable: contracts and
-- native integrations may use its identity. Overrides are weak and instance-local.
local labels = setmetatable({}, { __mode = 'k' })
function R.label_of(value)
    local kind = type(value)
    if kind == 'cdata' then
        local own = labels[value]
        if own ~= nil then return own end
        local info = ctype_info(ffi().typeof(value))
        return info and info.label or nil
    end
    if kind ~= 'table' and kind ~= 'function' and kind ~= 'userdata' then return nil end
    local own = labels[value]
    if own ~= nil then return own end
    local mt = getmetatable(value)
    return type(mt) == 'table' and rawget(mt, '__label') or nil
end
function R.label(text)
    assert(type(text) == 'string', 'label expects a string')
    return function(value)
        local kind = type(value)
        assert(kind == 'table' or kind == 'function' or kind == 'userdata' or kind == 'cdata',
            'label expects a table, function, userdata or cdata')
        if kind == 'table' and getmetatable(value) == nil then
            setmetatable(value, { __label = text })
        else
            labels[value] = text
        end
        return value
    end
end

-- `show value`: print what a value is and what it holds, and answer it unchanged, so it goes
-- anywhere in an expression. `shown value` is the text. One level of contents is read raw, as
-- the outline reads (no `__index`, `__pairs` or `__tostring`); a nested value appears as its
-- label, or as what it is.
local function brief(value)
    local own = R.label_of(value)
    if own then return ('«%s»'):format(own) end
    if type(value) == 'string' then
        local text = #value > 40 and (value:sub(1, 37) .. '...') or value
        return ('%q'):format(text)
    end
    if type(value) == 'number' or type(value) == 'boolean' or value == nil then return tostring(value) end
    return describe_value(value)
end
function R.shown(value)
    local own = R.label_of(value)
    local parts = {}
    if type(value) == 'table' then
        local keys = {}
        for key in next, value do keys[#keys + 1] = key end
        table.sort(keys, function(a, b)
            if type(a) == type(b) and (type(a) == 'number' or type(a) == 'string') then return a < b end
            return type(a) == 'number'
        end)
        local entries = {}
        for position, key in ipairs(keys) do
            if position > 12 then entries[#entries + 1] = ('… %d more'):format(#keys - 12); break end
            local name = type(key) == 'string' and key or ('[' .. brief(key) .. ']')
            entries[#entries + 1] = name .. ' = ' .. brief(rawget(value, key))
        end
        parts[#parts + 1] = (describe_value(value)) .. ' { ' .. table.concat(entries, ', ') .. ' }'
    elseif type(value) == 'function' then
        local info = debug.getinfo(value, 'S')
        parts[#parts + 1] = 'a function' .. ((info and info.short_src and info.linedefined and info.linedefined > 0) and (' at ' .. info.short_src .. ':' .. info.linedefined) or '')
    else
        parts[#parts + 1] = brief(value)
    end
    if own then return own .. ': ' .. parts[1] end
    return parts[1]
end
function R.show(value, ...)
    print(R.shown(value))
    return value, ...
end

function R.expand(t) return unpack(t, 1, t.n or #t) end

-- checkers and contracts (design §4.7) ------------------------------------------------------------

-- `checker "Node" do(value) … end`: a predicate with a name, so a contract that fails says what it
-- expected (`expects Node`) instead of `a predicate`. Curried like `pass`, so a declaration reads
-- without brackets: the name first, then the predicate.
local function checker(name, ...)
    if ... ~= nil then
        error('checker takes its name, then its predicate: checker "Node" do(value) … end', 2)
    end
    if type(name) ~= 'string' then
        error(('checker names the type first: checker "Node" do(value) … end, got %s'):format(describe_value(name)), 3)
    end
    return function(test)
        if type(test) ~= 'function' then
            error(('the predicate of the checker %s is %s, not a function'):format(name, describe_value(test)), 2)
        end
        local c = setmetatable({}, { __label = name, __tostring = function() return name end })
        checkers[c] = { name = name, test = test }
        return c
    end
end
R.checker = checker
R.Number = checker('Number')(function(v) return type(v) == 'number' end)
R.String = checker('String')(function(v) return type(v) == 'string' end)
R.Boolean = checker('Boolean')(function(v) return type(v) == 'boolean' end)
R.Table = checker('Table')(function(v) return type(v) == 'table' end)
R.Function = checker('Function')(function(v) return type(v) == 'function' end)
R.Any = checker('Any')(function() return true end)
R.Unit = checker('Unit')(function(v) return v == nil end)
local optionals = setmetatable({}, { __mode = 'k' })
function R.Optional(T)
    local c = optionals[T]
    if not c then
        c = checker('Optional(' .. R.describe(T) .. ')')(function(v) return v == nil or (R.check(T, v)) end)
        optionals[T] = c
    end
    return c
end

-- does v pass the checker T? Returns true, or false and why
function R.check(T, v)
    local c = checkers[T]
    if c then return c.test(v) end
    local s = structs[T] or sums[T]
    if s then return type(v) == 'table' and getmetatable(v) == s.meta end
    if type(T) == 'cdata' then return ffi().istype(T, v) end      -- a ctype is a checker
    local declared = closed[T]
    if declared then
        if type(v) ~= 'table' then return false end
        for k in pairs(v) do
            if type(k) ~= 'string' or not declared[k] then return false, ("has the undeclared field '%s'"):format(tostring(k)) end
        end
        for k in pairs(declared) do
            if T[k] == R.required and v[k] == nil then return false, ("lacks the required field '%s'"):format(k) end
        end
        return true
    end
    if type(T) == 'function' then return T(v) and true or false end
    error(('%s is not a checker (a checker is a built-in like Number, a predicate, a closed structural type, '
        .. 'a struct or a oneof)'):format(describe_value(T)), 3)
end

-- a contract: v passes T, or an error naming what (`parameter 'x' of f`) at the given level.
-- The message is built only when the contract fails: `what` is a format and its arguments.
local function contract(T, v, level, what, a, b)
    local ok, why = R.check(T, v)
    if not ok and type(v) == 'table' and contextual[v] and getmetatable(v) == nil
        and (structs[T] or (type(T) == 'cdata' and ctype_info(T))) then
        -- a `with` table takes the struct or ffistruct the context names. A struct is constructed
        -- in place, so the table keeps its identity and gains its type; C data cannot be branded,
        -- so an ffistruct is a new value made from the table's fields, and the contract returns it
        -- (the emitted code rebinds the checked name). A failure is the type's own, at the
        -- contract's line.
        local declared = type(T) == 'cdata' and ctype_info(T).fields
        if declared then
            for k in pairs(v) do
                if not declared[k] then error(("%s has no field '%s'"):format(ctype_info(T).name, tostring(k)), level) end
            end
        end
        local built, made = pcall(T, v)
        if not built then error((tostring(made):gsub('^[^:]+:%d+: ', '')), level) end
        return made
    end
    if not ok then
        error(('contract: %s expects %s, got %s%s'):format(what:format(a, b), R.describe(T), describe_value(v),
            why and (' (it ' .. why .. ')') or ''), level)
    end
    return v
end
-- a parameter's contract blames the caller (level 4: contract, param, the function, its
-- caller); a local's and a result's, the line in the function (level 3)
-- (contract is called as a statement: a tail call would drop a frame and shift the level)
function R.param(T, v, name, fname) v = contract(T, v, 4, "parameter '%s' of %s", name, fname); return v end
function R.local_(T, v, name, fname) v = contract(T, v, 3, "local '%s' in %s", name, fname); return v end
-- a result's contract: the value returned (one value: the emitter brackets the call, which
-- also keeps it from being a tail call)
function R.result(T, fname, v)
    v = contract(T, v, 3, 'the result of %s', fname)
    return v
end

-- struct and oneof (design §4.8) --------------------------------------------------------------------

-- a nominal record type: closed, typed fields; instances branded by a metatable through
-- which methods (`function P:m() ... end`) are reached
local Specialize = require 'mua.specialize.init'
local Structs = require 'mua.runtime.structs'
R.struct = Structs.new(structs, instance_of, contract, describe_value, Specialize.new())

-- Opt-in runtime view: shares nominal identities and contracts with this runtime,
-- but owns its factory cache. No global mode switch or hot-path strategy branch.
-- Supply the view as a chunk's __mua, just as with extend().
function R.specialized(options)
    local engine = Specialize.new(options or { mode = 'auto' })
    return R.extend {
        struct = Structs.new(structs, instance_of, contract, describe_value, engine),
    }, engine
end

-- family: a closed set of structs with passes over it ------------------------------------------------
-- `local Expr = family "Expr"` is a checker named Expr that is open until it is sealed with its
-- kinds, `Expr { Num, Add }`, so the structs' own fields can be typed `Expr`. A pass,
-- `Expr.pass "eval" with … end`, is a function over the family's values: a handler per kind,
-- keyed by the struct's name, called as handler(node, recurse, ...): the arguments the pass was called
-- with follow, so a pass can carry a scope or a state down the tree. It is checked against the kinds when
-- it is made, and a value that is no member is named when the pass meets it.
function R.family(name)
    if type(name) ~= 'string' then error('family takes a name: family "Expr"', 2) end
    local F = setmetatable({}, { __label = name, __tostring = function() return name end })
    local kinds, members, sealed = {}, {}, false         -- members: struct -> true
    local function need_sealed(what)
        if not sealed then error(("the family '%s' is %s before it is sealed (seal it with { … } after its structs)"):format(name, what), 3) end
    end
    local function member_of(v)
        local S = type(v) == 'table' and instance_of[getmetatable(v)]
        return S and members[S] and S
    end
    checkers[F] = { name = name, test = function(v) need_sealed('checked'); return not not member_of(v) end }
    getmetatable(F).__call = function(_, list)
        if sealed then error(("the family '%s' is already sealed"):format(name), 2) end
        if type(list) ~= 'table' then error(("seal the family '%s' with the list of its structs: { A, B }"):format(name), 2) end
        local seen = {}
        for i, S in ipairs(list) do
            if not structs[S] then
                error(("the family '%s': entry %d is %s, not a struct"):format(name, i, describe_value(S)), 2)
            end
            local kind = structs[S].name
            if seen[kind] then error(("the family '%s': two kinds are named %s"):format(name, kind), 2) end
            seen[kind] = true
            members[S] = true
            kinds[#kinds + 1] = kind
        end
        sealed = true
        F.kinds = kinds
        return F
    end
    -- is the value of this kind? The kind must belong to the family, so a typo cannot answer no.
    function F.is(node, kind)
        need_sealed('asked')
        if not (structs[kind] and members[kind]) then
            error(("%s is not a kind in the family '%s'"):format(R.describe(kind), name), 2)
        end
        return type(node) == 'table' and instance_of[getmetatable(node)] == kind
    end
    function F.pass(pass_name)
        need_sealed('given a pass')
        local supplied = type(pass_name) == 'table' and pass_name or nil
        if supplied then pass_name = R.label_of(supplied) or 'anonymous pass' end
        local function build(handlers)
            if type(handlers) ~= 'table' then error(("pass '%s' takes a table of handlers, one per kind"):format(pass_name), 2) end
            local by_meta, known = {}, {}
            for S in pairs(members) do known[structs[S].name] = S end
            for _, kind in ipairs(kinds) do
                local handler = handlers[kind]
                if handler == nil then
                    error(("pass '%s': no handler for the kind '%s' of the family '%s'"):format(pass_name, kind, name), 2)
                end
                if type(handler) ~= 'function' then
                    error(("pass '%s': the handler for '%s' is %s, not a function"):format(pass_name, kind, describe_value(handler)), 2)
                end
                by_meta[structs[known[kind]].meta] = handler
            end
            for kind in pairs(handlers) do
                if not known[kind] then
                    error(("pass '%s': '%s' is not a kind in the family '%s' (kinds: %s)"):format(pass_name, tostring(kind), name, table.concat(kinds, ', ')), 2)
                end
            end
            local recurse
            recurse = function(node, ...)
                local handler = by_meta[getmetatable(node)]
                if not handler then
                    error(("pass '%s': %s is not a member of the family '%s'"):format(pass_name, describe_value(node), name), 2)
                end
                return handler(node, recurse, ...)
            end
            return R.label(pass_name)(recurse)
        end
        if supplied then return build(supplied) end
        return build
    end
    return F
end

-- a tagged union: a constructor per alternative, payloads checked; a value is matched by calling
-- it with one handler per alternative, and every match checks the handlers name exactly those
function R.oneof(name, alts, unchecked)
    local S = {}
    local info = { name = name, alts = alts, index = {}, meta = { __label = name } }
    for _, a in ipairs(alts) do info.index[a[1]] = a[2] end
    sums[S] = info
    instance_of[info.meta] = S
    info.meta.__tostring = function(v) return ('%s.%s'):format(name, rawget(v, 'tag')) end
    info.meta.__call = function(v, handlers)
        if type(handlers) ~= 'table' then
            error(('matching a %s takes a table of handlers, one per alternative'):format(name), 2)
        end
        -- the handlers are exactly the alternatives: none unknown, and as many as there are
        -- (which a miss shows; the missing one is looked for only to name it)
        local n = 0
        for k in pairs(handlers) do
            if not info.index[k] then error(("%s has no alternative '%s' to handle"):format(name, tostring(k)), 2) end
            n = n + 1
        end
        if n ~= #alts then
            for _, a in ipairs(alts) do
                if handlers[a[1]] == nil then error(("matching a %s: the alternative '%s' has no handler"):format(name, a[1]), 2) end
            end
        end
        local tag = rawget(v, 'tag')
        if info.index[tag] == R.Unit then return handlers[tag]() end
        return handlers[tag](rawget(v, 'value'))
    end
    for _, a in ipairs(alts) do
        local tag, T = a[1], a[2]
        S[tag] = R.label(name .. '.' .. tag)(function(payload)
            if not unchecked then payload = contract(T, payload, 3, 'the payload of %s.%s', name, tag) end
            return setmetatable({ tag = tag, value = payload }, info.meta)
        end)
    end
    setmetatable(S, { __label = name, __tostring = function() return name end })
    return S
end

-- ffistruct (LuaJIT FFI): a C struct, declared once under a generated tag, as a ctype. A field's
-- type is a string of C (`"double"`, `"char *"`, `"uint8_t[16]"`) or a ctype made by ffistruct;
-- the ctype is a checker (R.check), and `Point { x = 1 }` / `Point(1, 2)` build values as for
-- any ctype.
local ffi_tags = 0
function R.ffistruct(name, fields)
    local decls, names = {}, {}
    for _, f in ipairs(fields) do
        local fname, T = f[1], f[2]
        names[fname] = true
        local text
        if type(T) == 'string' then text = T
        elseif type(T) == 'cdata' and ctype_info(T) then text = 'struct ' .. ctype_info(T).tag
        else error(('ffistruct %s: the field \'%s\' needs a C type (a name, a string of C, or an ffistruct), got %s')
            :format(name, fname, describe_value(T)), 3) end
        local base, array = text:match('^(.-)%s*(%[[^%]]*%])$')
        if base then text = base else array = '' end
        decls[#decls + 1] = ('%s %s%s;'):format(text, fname, array)
    end
    ffi_tags = ffi_tags + 1
    local tag = ('mua_%s_%d'):format(name:gsub('[^%w_]', '_'), ffi_tags)
    ffi().cdef(('struct %s { %s };'):format(tag, table.concat(decls, ' ')))
    local ct = ffi().typeof('struct ' .. tag)
    ctypes[tostring(ct)] = { name = name, label = name, tag = tag, fields = names }
    return ct
end

-- iter: one iteration over a step ------------------------------------------------------------------
-- `iter start do(state, control) … end` is a cursor, curried so the definition reads in the order a
-- traversal has: where it starts, then how it moves on. The step is Lua's own iterator protocol —
-- it answers the next control and the value it produces, and a nil value ends the traversal — so a
-- cursor is a value twice over: `for value in walk do` uses it as one, and
-- `walk.step, walk.state, walk.control` hands plain Lua the triple it already understands, with no
-- adapter. The control starts at 0, so a step that counts begins with `control + 1`; the cursor
-- owns it, so using the value again continues where it stopped, and `take n` is a bounded view
-- that spends from the same cursor. The word is a checker, so a cursor can be a parameter's, a
-- result's or a local's type, and a contract that fails says `expects iter`.

local iteration_meta, iter                                   -- forward: the metatable, then the type

-- the value the for reads: the control it threads is the cursor's own
local function iteration_advance(self)
    local control, value = self.step(self.state, self.control)
    if value ~= nil then self.control = control end
    return value
end

local function iteration_of(start, step)
    if type(step) ~= 'function' then
        error(('iter takes its start and then its step: iter start do(state, control) … end, got %s')
            :format(describe_value(step)), 2)
    end
    return setmetatable({ step = step, state = start, control = 0 }, iteration_meta)
end

local function iteration_take(self, limit)
    if type(limit) ~= 'number' then
        error(('take takes a count of steps, got %s'):format(describe_value(limit)), 2)
    end
    local left = limit
    return iteration_of(nil, function(state, control)
        if left <= 0 then return end
        left = left - 1
        local value = iteration_advance(self)
        if value == nil then return end
        return control + 1, value
    end)
end

iteration_meta = {
    __index = { take = iteration_take, advance = iteration_advance },
    __call = iteration_advance,
    __tostring = function() return 'an iteration' end,
}
iterations[iteration_meta] = true
iter = checker('iter')(function(value)
    return type(value) == 'table' and getmetatable(value) == iteration_meta
end)
getmetatable(iter).__call = function(_, start, step)
    if step ~= nil then
        error('iter takes its start and then its step: iter start do(state, control) … end', 2)
    end
    return function(step) return iteration_of(start, step) end
end
R.iter = iter

-- opening (design §4.4, E1) ----------------------------------------------------------------------
-- An opened Lua table introduces its string keys as they are when it is opened. open returns the
-- context (after checking that it can introduce names); emitted code tests, once, which of the
-- names its region mentions the context has, and reads a free name `x` as (flag ? ctx.x : x)
-- over the openings in scope, innermost first, so opening allocates nothing and no access
-- allocates or calls. A host may return its own accessor (a proxy whose metamethods read, write
-- and bind methods): a name is introduced when the accessor has a value for it.

local EMPTY = {}
function R.open(ctx)
    if ctx == nil then return EMPTY end
    if type(ctx) ~= 'table' then error(('open: a %s introduces no names (open a table)'):format(type(ctx)), 2) end
    return ctx
end

-- a runtime with some entries replaced: a host's chunks see it as their `__mua`
function R.extend(overrides)
    return setmetatable(overrides, { __index = R })
end

-- tests --------------------------------------------------------------------------------------
-- `test "what it shows":` … `end` names a case whose block is its body, and labels the block
-- with it. Inside `collect(run)`,
-- the cases `run` names are registered, in order, for a runner to run; anywhere else a case runs
-- at once and a failure raises `test 'name' failed: …`, so a file of tests is also a program.
local collectors = {}
function R.test(name, body)
    if type(name) ~= 'string' then
        error(('test takes a name first: test "what it shows":, got %s'):format(describe_value(name)), 2)
    end
    local function case(run)
        if type(run) ~= 'function' then
            error(("test '%s' takes a block: test %q: ... end"):format(name, name), 2)
        end
        -- a case's block is labeled with what it shows: its identity in outlines and reports
        R.label(name)(run)
        local collector = collectors[#collectors]
        if collector then
            collector[#collector + 1] = { name = name, run = run }
            return
        end
        local ok, problem = xpcall(run, function(e) return debug.traceback(tostring(e), 2) end)
        if not ok then error(("test '%s' failed: %s"):format(name, problem), 0) end
    end
    if body ~= nil then return case(body) end
    return case
end

-- run `run` and answer the cases its tests named, as { name, run } in order; a collection
-- inside a collection is its own
function R.collect(run)
    if type(run) ~= 'function' then error('collect takes a function to run', 2) end
    local cases = {}
    collectors[#collectors + 1] = cases
    local ok, problem = pcall(run)
    collectors[#collectors] = nil
    if not ok then error(problem, 0) end
    return cases
end

-- the words a Mua program may name without defining them: the emitter binds those a chunk
-- uses to these, unless the chunk's environment defines them
R.words = { 'define', 'meta', 'label', 'label_of', 'checker', 'family', 'iter', 'closed', 'required', 'optional', 'check', 'test', 'collect', 'show', 'shown', 'Number', 'String', 'Boolean', 'Table',
            'Function', 'Any', 'Unit', 'Optional' }

return R
