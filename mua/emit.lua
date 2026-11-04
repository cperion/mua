-- mua.emit: Mua's AST as plain Lua (design macro-layer.md §4.3, §4.4).
--
--   emit(block, opts) -> text
--
-- The emitter streams: every node is written in source order, after moving the output
-- forward to the node's line, so each statement (and each line of a multi-line expression)
-- keeps its source line and LuaJIT's error positions are the source's.
--
-- opts: filename; host (design §5): typed_lambda(node, cx), opened_lambda(node, cx),
-- typed_function(node, cx), struct(node, cx), sum(node, cx), emit_statements[kind](node, cx),
-- each returning Lua text for the whole node; contracts (default true). Without a host, typed forms have Mua's
-- meaning (design §4.7, §4.8): a typed function evaluates its annotations once, where it is
-- defined, and checks its parameters on entry, its result at each return and its typed
-- locals at each assignment; `contracts = false` drops every check and evaluates no
-- annotation.
--
-- The runtime (mua.runtime, or the host's) is reached through a local `__mua`
-- declared at the start of the first line when the chunk uses it: an environment that
-- defines a global `__mua` supplies its own.
--
-- Opening (design §4.4, E1): an opening is `local __o1 = __mua.open(v)` (the context) and one
-- boolean per name the region mentions, `local __o1_x, __o1_y = __o1.x ~= nil, __o1.y ~= nil`
-- (which of them the context introduces, as it is when opened); a free name inside the opened
-- region (one no scope binds after the opening) reads as (__o2_x ? __o2.x : __o1_x ? __o1.x :
-- x), over the openings newer than its nearest binding, innermost first. Opening allocates
-- nothing, and nothing is allocated or called per access (lean emission: E1).

local M = {}
local WORDS = {}
for _, w in ipairs(require('mua.runtime').words) do WORDS[w] = true end

local function quote(s) return ('%q'):format(s) end

local E = {}
E.__index = E

function E:err(msg, line)
    error(('%s:%d: %s'):format(self.opts.filename or '?', line or self.line, msg), 0)
end

-- write text, first moving to `line` (never back: earlier lines are full)
function E:put(s, line)
    if line and line > self.line then
        self.out[#self.out + 1] = ('\n'):rep(line - self.line)
        self.line = line
    end
    self.out[#self.out + 1] = s
    local _, n = s:gsub('\n', '')
    self.line = self.line + n
end
function E:rt(name) self.uses_runtime = true; return '__mua.' .. name end

-- scopes: the names each binds, and the opened contexts introduced in it ------------------------

function E:push() self.scopes[#self.scopes + 1] = { names = {}, opens = {} } end
function E:pop() self.scopes[#self.scopes] = nil end
-- a binding records how many openings preceded it in its scope, and a typed local's checker
function E:bind(name, typed)
    local sc = self.scopes[#self.scopes]
    sc.names[name] = { opens = #sc.opens, type = typed }
end
function E:binding(name)
    for i = #self.scopes, 1, -1 do local b = self.scopes[i].names[name] if b then return b end end
end
function E:bound(name)
    for i = #self.scopes, 1, -1 do if self.scopes[i].names[name] then return true end end
    return false
end
-- the opened contexts newer than the nearest binding of `name`, innermost first (each is
-- { alias, flags = name -> the local holding whether it introduces the name })
function E:opens_for(name)
    local out = {}
    for i = #self.scopes, 1, -1 do
        local sc = self.scopes[i]
        local bound = name and sc.names[name]
        for k = #sc.opens, (bound and bound.opens or 0) + 1, -1 do out[#out + 1] = sc.opens[k] end
        if bound then return out end
    end
    return out
end
-- `name` read through the openings newer than its nearest binding, innermost first
function E:resolved(name)
    local text = name
    local opens = self:opens_for(name)
    for i = #opens, 1, -1 do
        local o = opens[i]
        text = ('%s ? %s.%s : %s'):format(o.flags[name] or (o.alias .. '.' .. name .. ' ~= nil'), o.alias, name, text)
    end
    return '(' .. text .. ')'
end
-- the names a region of the program mentions: the ones an opening there may have to resolve
local function collect_names(node, out, seen)
    if type(node) ~= 'table' or seen[node] then return end
    seen[node] = true
    if node.k == 'name' and node.name then out[node.name] = true end
    if node.k == 'function' and node.path then out[node.path[1]] = true end
    for _, child in pairs(node) do
        if type(child) == 'table' then collect_names(child, out, seen) end
    end
end

-- open the value of the local `var` in the current scope; `region` is what the opening covers
-- (the statements after it, or a function's body), whose names it will have to resolve
function E:open(var, line, region)
    self.open_id = self.open_id + 1
    local alias = '__o' .. self.open_id
    self:put(('local %s = %s(%s); '):format(alias, self:rt('open'), var), line)
    local names = {}
    collect_names(region, names, {})
    local list = {}
    for name in pairs(names) do list[#list + 1] = name end
    table.sort(list)
    local flags = {}
    -- (a region naming very many things falls back to testing the context where it is read:
    -- Lua allows 200 locals to a function)
    if #list > 0 and #list <= 60 then
        local locals, tests = {}, {}
        for i, name in ipairs(list) do
            flags[name] = alias .. '_' .. name
            locals[i], tests[i] = flags[name], ('%s.%s ~= nil'):format(alias, name)
        end
        self:put(('local %s = %s; '):format(table.concat(locals, ', '), table.concat(tests, ', ')))
    end
    local sc = self.scopes[#self.scopes]
    sc.opens[#sc.opens + 1] = { alias = alias, flags = flags }
end

-- expressions -----------------------------------------------------------------------------------

local PREFIX = { name = true, field = true, index = true, call = true, method = true }

-- write an expression usable as a prefix (a callee, a receiver, an indexed object)
function E:prefix(n)
    if PREFIX[n.k] or (n.k == 'paren' and not n.literal) then return self:expr(n) end
    self:put('(', n.line); self:expr(n); self:put(')')
end
-- write an operand of an operator: nested operators are bracketed, so the tree's grouping holds
local BRACKETED = { binop = true, unop = true, cond = true, lambda = true }
function E:operand(n)
    if BRACKETED[n.k] then self:put('(', n.line); self:expr(n); self:put(')') else self:expr(n) end
end

function E:list(ns)
    for i, n in ipairs(ns) do
        if i > 1 then self:put(', ') end
        if n.k == 'spread' then
            if i ~= #ns then self:err('a spread `..` inside a list needs a host; in Lua it is the last item', n.line) end
            -- a call's results are already a list in last position; anything else is a table
            if n.e.k == 'call' or n.e.k == 'method' or n.e.k == 'vararg' then self:expr(n.e)
            else self:put(self:rt('expand') .. '(', n.line); self:expr(n.e); self:put(')') end
        else
            self:expr(n)
        end
    end
end

function E:table(items, line)
    local has_spread = false
    for _, it in ipairs(items) do if it.kind == 'spread' then has_spread = true end end
    if has_spread then
        -- a duplicated field would vanish in the Lua table the spread is collected in
        local seen = {}
        for _, it in ipairs(items) do
            if it.kind == 'named' then
                if seen[it.name] then self:err(("duplicate field '%s'"):format(it.name), it.line) end
                seen[it.name] = true
            end
        end
        self:put(self:rt('keyed') .. '(', line)
    end
    self:put('{ ', line)
    local nspread = 0
    for i, it in ipairs(items) do
        if i > 1 then self:put(', ') end
        if it.kind == 'named' then
            self:put(it.name .. ' = ', it.line); self:expr(it.e)
        elseif it.kind == 'keyed' then
            self:put('[', it.line); self:expr(it.key); self:put('] = '); self:expr(it.e)
        elseif it.kind == 'spread' then
            nspread = nspread + 1
            self:put('[' .. self:rt('spread_mark') .. '(' .. nspread .. ')] = ', it.line); self:expr(it.e)
        else
            if has_spread then self:err('a keyed spread admits only `name = value` entries and spreads', it.line) end
            self:expr(it.e)
        end
    end
    self:put(' }')
    if has_spread then self:put(')') end
end

-- is `name` free (bound after no opening) inside an opened region?
function E:opened_free(name) return #self:opens_for(name) > 0 end

function E:expr(n)
    local k, line = n.k, n.line
    if k == 'name' then
        if WORDS[n.name] and not self:bound(n.name) then self.words[n.name] = true end
        if self:opened_free(n.name) then self:put(self:resolved(n.name), line)
        else self:put(n.name, line) end
    elseif k == 'num' or k == 'str' then self:put(n.text, line)
    elseif k == 'nil' or k == 'true' or k == 'false' then self:put(k, line)
    elseif k == 'vararg' then self:put('...', line)
    elseif k == 'home' then
        if not self:bound('__home') then self:err('`..` reads an unnamed opened home, and there is none here', line) end
        self:put('__home', line)
    elseif k == 'spread' then
        self:err('a spread `..e` belongs in an argument list, a return or a table', line)
    elseif k == 'paren' then
        if n.literal then self:expr(n.e) else self:put('(', line); self:expr(n.e); self:put(')') end
    elseif k == 'field' then
        self:prefix(n.obj); self:put((n.safe and '?.' or '.') .. n.name)
    elseif k == 'index' then
        self:prefix(n.obj); self:put(n.safe and '?.[' or '['); self:expr(n.key); self:put(']')
    elseif k == 'call' then
        if n.fn.k == 'paren' and n.fn.literal then self:put('(', line); self:expr(n.fn); self:put(')')
        else self:prefix(n.fn) end
        self:put(n.safe and '?.(' or '('); self:list(n.args); self:put(')')
    elseif k == 'method' then
        if n.obj.k == 'paren' and n.obj.literal then self:put('(', line); self:expr(n.obj); self:put(')')
        else self:prefix(n.obj) end
        self:put((n.safe and '?.:' or ':') .. n.name .. (n.safe_call and '?.(' or '('))
        self:list(n.args)
        self:put(')')
    elseif k == 'lambda' then
        if n.fn.result and self.host.typed_lambda then
            return self:put(self.host.typed_lambda(n, self:context(n)), line)
        end
        -- an opened untyped lambda: a host may give its body its own meaning
        if not n.fn.result and self.host.opened_lambda then
            for _, p in ipairs(n.fn.params) do
                if p.opened then return self:put(self.host.opened_lambda(n, self:context(n)), line) end
            end
        end
        local contract = self:contract_of(n.fn)
        if not contract then return self:funcbody(n.fn, line) end
        -- the annotations are evaluated once, where the function is made
        self:put('(function(' .. table.concat(contract.aliases, ', ') .. ') return ', line)
        self:funcbody(n.fn, line, nil, nil, contract)
        self:put(' end)(')
        self:types(contract)
        self:put(')')
    elseif k == 'table' then self:table(n.items, line)
    elseif k == 'with' then
        self:put(self:rt('with') .. '(', line); self:table(n.items, line); self:put(')')
    elseif k == 'binop' then
        self:operand(n.a); self:put(' ' .. n.op .. ' '); self:operand(n.b)
    elseif k == 'unop' then
        self:put(n.op == 'not' and 'not ' or n.op, line); self:operand(n.a)
    elseif k == 'cond' then
        -- the middle operand is bracketed: it may not hold a method call directly
        self:operand(n.c); self:put(' ? ('); self:expr(n.a); self:put(') : '); self:operand(n.b)
    elseif k == 'struct' and n.ffi then
        -- ffistruct: a C struct for LuaJIT's FFI. A field's type is a C type name (a name no
        -- scope binds is read as C's), a string of C, or a ctype value (a name that is bound).
        local translate = self.host.ffi_struct
        if translate then return self:put(translate(n, self:context(n)), line) end
        self:put(('%s(%s, { '):format(self:rt('ffistruct'), quote(n.name or 'ffistruct')), line)
        for i, f in ipairs(n.fields) do
            if i > 1 then self:put(', ') end
            self:put('{ ' .. quote(f.name) .. ', ', f.line)
            if f.type.k == 'name' and not self:bound(f.type.name) then self:put(quote(f.type.name))
            else self:expr(f.type) end
            self:put(' }')
        end
        self:put(' })')
    elseif k == 'struct' then
        local translate = self.host[n.sum and 'sum' or 'struct']
        if translate then return self:put(translate(n, self:context(n)), line) end
        self:put(('%s(%s, { '):format(self:rt(n.sum and 'oneof' or 'struct'), quote(n.name or (n.sum and 'oneof' or 'struct'))), line)
        for i, f in ipairs(n.fields) do
            if i > 1 then self:put(', ') end
            self:put('{ ' .. quote(f.name) .. ', ', f.line); self:expr(f.type); self:put(' }')
        end
        self:put(self:contracts() and ' })' or ' }, true)')
    else
        self:err('cannot emit a ' .. tostring(k), line)
    end
end

-- the context a host translator receives
function E:context(node)
    local e = self
    return {
        filename = self.opts.filename, line = node.line,
        error = function(_, msg, line) e:err(msg, line or node.line) end,
    }
end

-- contracts (design §4.7) -----------------------------------------------------------------------

function E:contracts() return self.opts.contracts ~= false end
-- the checkers of a typed function: an alias per typed parameter and for the result
function E:contract_of(fn)
    if not (fn.result and self:contracts()) then return nil end
    self.type_id = (self.type_id or 0) + 1
    local id = self.type_id
    local c = { aliases = {}, exprs = {}, params = {}, name = fn.name or 'the function' }
    for i, p in ipairs(fn.params) do
        if p.type then
            local alias = ('__t%d_%d'):format(id, i)
            c.aliases[#c.aliases + 1] = alias
            c.exprs[#c.exprs + 1] = p.type
            c.params[#c.params + 1] = { name = p.name, display = p.unnamed and '..' or p.name, alias = alias }
        end
    end
    c.result = ('__r%d'):format(id)
    c.aliases[#c.aliases + 1] = c.result
    c.exprs[#c.exprs + 1] = fn.result
    return c
end
function E:types(c)
    for i, t in ipairs(c.exprs) do
        if i > 1 then self:put(', ') end
        self:expr(t)
    end
end
-- the value of the expression list `exprs` checked against a typed local's checker
function E:checked(b, name, emit_value)
    self:put(('%s(%s, '):format(self:rt('local_'), b.type))
    emit_value()
    self:put((', %s, %s)'):format(quote(name), quote(self.fnctx and self.fnctx.name or 'the chunk')))
end

-- functions -------------------------------------------------------------------------------------

-- `function(params) ... end`, or with `head` (`function name`) for a statement; `contract`
-- (from contract_of) adds the checks, its aliases bound where the function is made
function E:funcbody(fn, line, head, self_param, contract)
    local params = {}
    for _, p in ipairs(fn.params) do params[#params + 1] = p.name end
    if fn.vararg or fn.rest then params[#params + 1] = '...' end
    self:put((head or 'function') .. '(' .. table.concat(params, ', ') .. ') ', line)
    local saved_fn = self.fnctx
    self.fnctx = { name = (contract and contract.name) or fn.name or 'the function', result = contract and contract.result }
    self:push()
    if self_param then self:bind('self') end
    for _, p in ipairs(fn.params) do self:bind(p.name) end
    for _, p in ipairs(contract and contract.params or {}) do
        self:put(('%s = %s(%s, %s, %s, %s); '):format(p.name, self:rt('param'), p.alias, p.name, quote(p.display), quote(self.fnctx.name)))
    end
    if fn.rest then
        self:put(('local %s = { n = select("#", ...), ... }; '):format(fn.rest))
        self:bind(fn.rest)
    end
    for _, p in ipairs(fn.params) do if p.opened then self:open(p.name, nil, fn.body or fn.expr) end end
    if fn.expr then
        self:put('return ', fn.expr.line)
        if contract then self:put(('(%s(%s, %s, '):format(self:rt('result'), contract.result, quote(self.fnctx.name))) end
        self:expr(fn.expr)
        if contract then self:put('))') end
        self:put(' ')
    else
        self:stats(fn.body)
        -- falling off the end returns nothing: the result's contract sees nil
        local last = fn.body[#fn.body]
        if contract and not (last and last.k == 'return') then
            self:put(('return (%s(%s, %s, nil)) '):format(self:rt('result'), contract.result, quote(self.fnctx.name)))
        end
    end
    self:pop()
    self.fnctx = saved_fn
    self:put('end', fn.end_line)
end

-- statements ------------------------------------------------------------------------------------

function E:stats(stats)
    for i, s in ipairs(stats) do
        self.rest = { stats = stats, index = i }       -- what an opening here would cover
        self:stat(s)
    end
end
function E:block(stats, line) self:push(); self:stats(stats); self:pop() end

local function names_of(list) local o = {} for i, v in ipairs(list) do o[i] = v.name end return table.concat(o, ', ') end

function E:stat(s)
    local k, line = s.k, s.line
    if k == 'local' or k == 'const' then
        -- typed locals: their checkers first, then the declaration, then a check of each
        local typed = {}
        if self:contracts() then
            for i, v in ipairs(s.names) do
                if v.type then
                    self.type_id = (self.type_id or 0) + 1
                    local alias = '__lt' .. self.type_id
                    self:put('local ' .. alias .. ' = ', line); self:expr(v.type); self:put('; ')
                    typed[i] = alias
                end
            end
        end
        self:put((k == 'const' and 'const ' or 'local ') .. names_of(s.names), line)
        if #s.exprs > 0 then self:put(' = '); self:list(s.exprs) end
        self:put('; ')
        for i, v in ipairs(s.names) do
            self:bind(v.name, typed[i])
            if typed[i] then
                -- the contract returns the value (a `with` filled into an ffistruct is a new one)
                self:put(('%s%s(%s, %s, %s, %s); '):format(k == 'const' and '' or v.name .. ' = ', self:rt('local_'), typed[i], v.name,
                    quote(v.name), quote(self.fnctx and self.fnctx.name or 'the chunk')))
            end
        end
    elseif k == 'open' then
        local rest = self.rest
        if s.init then
            self:put('local ' .. s.name .. ' = ', line); self:expr(s.init); self:put('; ')
            self:bind(s.name)
        end
        local region = {}
        for i = rest.index + 1, #rest.stats do region[#region + 1] = rest.stats[i] end
        self:open(s.name, line, region)
    elseif k == 'localfunction' then
        self:bind(s.name)
        if s.fn.result and self.host.typed_function then
            return self:put(self.host.typed_function(s, self:context(s)) .. '; ', line)
        end
        local contract = self:contract_of(s.fn)
        if contract then
            -- the name is bound before the body (recursion), the checkers before the function
            self:put((s.const and 'const ' or 'local ') .. s.name .. '; do local ' .. table.concat(contract.aliases, ', ') .. ' = ', line)
            self:types(contract)
            self:put('; ')
            self:funcbody(s.fn, line, s.name .. ' = function', nil, contract)
            self:put(' end; ')
            return
        end
        self:funcbody(s.fn, line, (s.const and 'const' or 'local') .. ' function ' .. s.name)
        self:put('; ')
    elseif k == 'function' then
        if s.fn.result and self.host.typed_function then
            return self:put(self.host.typed_function(s, self:context(s)) .. '; ', line)
        end
        local name = table.concat(s.path, '.') .. (s.method and (':' .. s.method) or '')
        local contract = self:contract_of(s.fn)
        if contract then
            self:put('do local ' .. table.concat(contract.aliases, ', ') .. ' = ', line)
            self:types(contract)
            self:put('; ')
            self:funcbody(s.fn, line, 'function ' .. name, s.method ~= nil, contract)
            self:put(' end; ')
            return
        end
        self:funcbody(s.fn, line, 'function ' .. name, s.method ~= nil)
        self:put('; ')
    elseif k == 'assign' then
        -- a free name assigned inside an opened region: the opened context's member, if any
        if #s.targets == 1 and s.targets[1].k == 'name' and self:opened_free(s.targets[1].name) then
            -- the value once, then the innermost opening that introduces the name, else the name
            local t = s.targets[1].name
            self:put('do local __value = ', line)
            self:list(s.exprs)
            local opens = self:opens_for(t)
            for i, o in ipairs(opens) do
                self:put(('; %s %s then %s.%s = __value'):format(i == 1 and 'if' or 'elseif',
                    o.flags[t] or (o.alias .. '.' .. t .. ' ~= nil'), o.alias, t))
            end
            self:put(('; else %s = __value end end; '):format(t))
            return
        end
        local b = #s.targets == 1 and s.targets[1].k == 'name' and self:binding(s.targets[1].name)
        if b and b.type then
            self:put(s.targets[1].name .. ' = ', line)
            self:checked(b, s.targets[1].name, function() self:list(s.exprs) end)
            self:put('; ')
            return
        end
        for i, t in ipairs(s.targets) do
            if i > 1 then self:put(', ') end
            if i == 1 then self:put('', line) end
            self:expr(t)
        end
        self:put(' = '); self:list(s.exprs); self:put('; ')
        -- typed locals among several targets: checked once assigned
        for _, t in ipairs(s.targets) do
            local tb = t.k == 'name' and self:binding(t.name)
            if tb and tb.type then
                self:put(('%s = %s(%s, %s, %s, %s); '):format(t.name, self:rt('local_'), tb.type, t.name, quote(t.name),
                    quote(self.fnctx and self.fnctx.name or 'the chunk')))
            end
        end
    elseif k == 'compound' then
        self:put('', line); self:expr(s.target); self:put(' ' .. s.op .. '= '); self:expr(s.e); self:put('; ')
        local tb = s.target.k == 'name' and self:binding(s.target.name)
        if tb and tb.type then
            self:put(('%s = %s(%s, %s, %s, %s); '):format(s.target.name, self:rt('local_'), tb.type, s.target.name,
                quote(s.target.name), quote(self.fnctx and self.fnctx.name or 'the chunk')))
        end
    elseif k == 'callstat' then
        self:put('', line); self:expr(s.e); self:put('; ')
    elseif k == 'if' then
        for i, c in ipairs(s.clauses) do
            self:put(i == 1 and 'if ' or 'elseif ', i == 1 and line or nil)
            self:expr(c.cond); self:put(' then ')
            self:block(c.body)
        end
        if s.els then self:put('else '); self:block(s.els) end
        self:put('end; ')
    elseif k == 'while' then
        self:put('while ', line); self:expr(s.cond); self:put(' do ')
        self:block(s.body)
        self:put('end; ')
    elseif k == 'numfor' then
        self:put('for ' .. s.var .. ' = ', line); self:expr(s.lo); self:put(', '); self:expr(s.hi)
        if s.step then self:put(', '); self:expr(s.step) end
        self:put(' do ')
        self:push()
        if s.type and self:contracts() then
            self.type_id = (self.type_id or 0) + 1
            local alias = '__lt' .. self.type_id
            -- the checker once, before the loop would be cleaner; inside, it costs one check per
            -- iteration, which the off switch removes
            self:put(('local %s = '):format(alias)); self:expr(s.type); self:put('; ')
            self:bind(s.var, alias)
            self:put(('%s = %s(%s, %s, %s, %s); '):format(s.var, self:rt('local_'), alias, s.var, quote(s.var),
                quote(self.fnctx and self.fnctx.name or 'the chunk')))
        else
            self:bind(s.var)
        end
        self:stats(s.body); self:pop()
        self:put('end; ')
    elseif k == 'genfor' then
        self:put('for ' .. table.concat(s.names, ', ') .. ' in ', line); self:list(s.exprs); self:put(' do ')
        self:push()
        for _, n in ipairs(s.names) do self:bind(n) end
        self:stats(s.body)
        self:pop()
        self:put('end; ')
    elseif k == 'repeat' then
        -- the condition sees the body's locals
        self:put('repeat ', line)
        self:push(); self:stats(s.body)
        self:put('until '); self:expr(s.cond); self:put('; ')
        self:pop()
    elseif k == 'do' then
        self:put('do ', line); self:block(s.body); self:put('end; ')
    elseif k == 'return' then
        self:put('return ', line)
        local result = self.fnctx and self.fnctx.result
        if result then
            if #s.exprs > 1 then self:err('a typed function returns one value (its result annotation describes one)', line) end
            self:put(('(%s(%s, %s'):format(self:rt('result'), result, quote(self.fnctx.name)))
            if #s.exprs > 0 then self:put(', '); self:list(s.exprs) end
            self:put('))')
        else
            self:list(s.exprs)
        end
        self:put('; ')
    elseif k == 'break' or k == 'continue' then
        self:put(k .. '; ', line)
    elseif k == 'goto' then
        self:put('goto ' .. s.label .. '; ', line)
    elseif k == 'label' then
        self:put('::' .. s.name .. ':: ', line)
    else
        local translate = self.host.emit_statements and self.host.emit_statements[k]
        if translate then return self:put(translate(s, self:context(s)) .. '; ', line) end
        self:err(("the statement '%s' has no meaning without a host"):format(tostring(k)), line)
    end
end

function M.emit(block, opts)
    opts = opts or {}
    local e = setmetatable({ out = {}, line = 1, opts = opts, host = opts.host or {}, scopes = {},
                             uses_runtime = false, open_id = 0, words = {} }, E)
    e:block(block)
    local text = table.concat(e.out)
    -- runtime words free in the chunk (define, Number, Optional, ...): a global of that name,
    -- else the runtime's word; all on the first line
    local words = {}
    for w in pairs(e.words) do words[#words + 1] = w end
    table.sort(words)
    local head = {}
    for _, w in ipairs(words) do head[#head + 1] = ('local %s = %s or __mua.%s; '):format(w, w, w) end
    if #head > 0 then text = table.concat(head) .. text; e.uses_runtime = true end
    if e.uses_runtime then text = 'local __mua = __mua or require("mua.runtime"); ' .. text end
    return text
end

return M
