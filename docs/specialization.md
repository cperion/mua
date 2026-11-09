# Runtime specialization

## Ownership

A plan contains fixed operation structure. A factory compiles that structure. A bound
closure owns declaration identities and behavior. Invocation values remain invocation-local.

The implementation starts with struct constructors; it does not yet specialize spreads,
contracts, oneof matching, or family passes. There is no AST specialization/lowering pass yet.
The existing family pass already prepares a metatable-to-handler map once per pass.

```
mua/plan.lua                  declaration structure, structural keys
mua/specialize/init.lua       strategy selection, preparation
mua/specialize/generate.lua   trusted Lua factory templates
mua/specialize/compile.lua    isolated compilation, bounded factory cache
mua/runtime/structs.lua       identity, generic constructors, factory binding
mua/runtime.lua              existing public facade and shared registries
```

The emitter and emitted runtime ABI are unchanged. No new syntax is introduced.

## Selecting a strategy

The default runtime remains generic. A host can create a runtime view:

```lua
local R = require 'mua.runtime'
local runtime, engine = R.specialized {
    mode = 'generated', -- explicitly experimental; 'generic' and 'auto' stay generic
    max_fields = 16,
    cache_limit = 64,
}
local chunk = assert(require('mua.init').load(source, '@example.mua'))
setfenv(chunk, setmetatable({ __mua = runtime }, { __index = _G }))
chunk()
local stats = engine.stats() -- fresh table: cached, hits, compilations
```

The runtime view shares nominal registries and contract semantics with `R`; it is not
an isolated type universe. Its factory cache is private. There is no global strategy
switch. Ordinary `R.extend` overrides continue to work as before.

`auto` deliberately selects generic construction for now. Initial paired benchmarks
showed regressions for generated constructors at 8 and 16 fields. Code generation is
not itself an optimization guarantee. Keep explicit generated mode for investigation.

## Preparation and binding

`engine.prepare(plan, generic_factory)` returns an artifact containing `strategy`,
`bind`, and, for generated artifacts, `source`. Plans are internal and treated as
immutable by convention; preparation retains no reference to the caller's plan.

Factories take fields, the allowed-field index, instance metatable, diagnostic name,
contract operation, value description, and primitive helpers as explicit arguments.
The cache never receives these bindings. Two identically shaped types share compiled
code but have distinct constructors, branding, methods, and diagnostics.

Compiled chunks run with an empty environment. Only trusted templates are compiled;
this is dependency isolation, not an arbitrary-Lua sandbox. Generator errors and cache
key collisions fail loudly. Large plans select the generic implementation before code
generation. Cache eviction is bounded FIFO, not an unbounded weak-cache heuristic.

Generated source is available on preparation artifacts. It is retained only in the
bounded cache or by explicit callers, not in a global closure-inspection registry.

## Semantic obligations

Structs retain the original construction protocol:

1. An omitted/nil argument becomes a fresh table.
2. Non-table inputs fail.
3. Checked construction rejects unknown keys before checking fields.
4. Fields are checked in declaration order; conversions are written back exactly as
   in the reference implementation, including its field reads and comparisons.
5. The original table is branded and returned; methods remain dynamically accessible.

The public runtime accepts a mutable field descriptor list. Generated constructors
therefore do not capture field contracts as immutable facts. They read each current
field descriptor, stop at the first hole, and continue through newly appended entries.
A predicate can mutate later descriptors during validation. The allowed-field index
retains its existing declaration-time semantics. This is intentionally conservative;
introducing immutable descriptors is a separate semantic decision, not an optimization.

Generated constructors retain the same constructor/contract call depth for diagnostics;
there is no extra validator wrapper. Tests compare error bodies, effects, conversions,
nominal identities, dynamic descriptor mutation, and interoperability with families.

## Lifetimes and limitations

A runtime view owns its engine; the engine owns only a bounded cache of unbound factories.
A type owns its bound constructor. The factory cache cannot retain instances, names,
contracts, or metatables through bindings. Tests verify collection of bound closures
and captured objects while their factory remains cached.

Existing runtime identity registries are unchanged. This work does not claim to fix or
prove their collection behavior on LuaJIT: descriptor/metatable backreferences require
a separate registry-lifetime audit. There is no persistent generated-bytecode cache.

## Validation

```
make test LUA=/path/to/patched/luajit
/path/to/patched/luajit bench/specialization.lua
```

The benchmark alternates strategy order over seven samples and reports medians. Values
escape through a ring. Construction timings include input table population; they are
end-to-end cases, not isolated validator costs. Declaration timings use a warm factory
cache. Cold compilation cost, trace exits, allocation measurements, and application
stage timings still need separate measurements before choosing automatic policies.

## Next architectural extensions

Keep each extension within the same ownership boundaries:

- Contracts: prepared validators with explicit diagnostic contexts and live dependencies.
- Spreads: source-count/explicit-key plans, separate evaluation scheduling and assembly.
- Oneof: declaration-bound constructors, but invocation-bound matching handlers unless
  lexical analysis proves otherwise.
- AST lowering: proven bindings and evaluation schedules, not assumptions about mutable
  table contents. Preserve multiple results and effects in nested expressions.

Each needs its own reference implementation and differential tests. Do not route these
through struct-shaped plans or add an abstract instruction set before their actual
semantic requirements are represented.
