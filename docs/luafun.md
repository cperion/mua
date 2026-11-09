# Lua Fun in Mua: grow the vocabulary, not the language

For a compiler targeting generator composition, with a reference interpreter,
benchmarks and actual JIT-trace observations, see [the compiler experiment](luafun-compiler.md).

Lua Fun already speaks Lua's iterator protocol and provides a callable wrapper with
methods. Mua needs neither a new iterator type nor syntax to use it. The optional
experiment is `examples/luafun/idioms.mua`, tested against upstream commit
`057ede73d78b0e6bdbb354b35492d28c7950f857` (master, not a stable release).

The dependency is NOT vendored or installed by Mua. Clone it separately; do not
`git pull` its unrelated history into the Mua repository:

```sh
git clone https://github.com/luafun/luafun.git /path/to/luafun
LUA_PATH='/path/to/luafun/?.lua;;' /path/to/patched/luajit mua.lua examples/luafun/idioms.mua
LUA_PATH='/path/to/luafun/?.lua;;' make test-luafun LUA=/path/to/patched/luajit
```

## Start with no adapter

```mua
local Fun = require "fun"
local even = value -> value % 2 == 0
local square = value -> value * value
local total = Fun.range(100):filter(even):map(square):take(5):sum()
```

This already follows Mua's subject-first style. A lexical opening, `local Fun..`,
provides the functional spelling without Lua Fun's optional global namespace
injection (`require('fun')()`). Do not confuse Mua juxtaposition with supplying
several arguments: native `Fun.map` takes its function and input in ONE call.

## A curried vocabulary when partial application reads better

The example builds `Sequences` by spreading `Fun` and explicitly overriding just
`map`, `filter`, and `take`. A tiny adapter binds the first argument, then accepts
`generator, parameter, control` together. It preserves raw triples and also accepts
Lua Fun wrappers.

```mua
local Sequences..
local squares = map square
local total = sum(take 5 (squares(filter even (range 100))))
```

`squares` is reusable behavior, not a captured traversal. Each application supplies
its own input. Adapters add setup closures; they do not add a callback layer for
each element. That does not establish zero overhead: measure the consuming loop.

Keep native reducers and multi-input combinators native until actual call sites
justify a different signature. Do not curry the entire library indiscriminately.

## A builder for longer pipelines

The example's local `through` builder owns a `current` traversal and offers three
verbs that replace it. Completion returns a normal Lua Fun wrapper and its triple.

```mua
local selected = through(Fun.range 100):
    filter even
    map square
    take 5
end
local total = selected:sum()
```

The block configures composition; iteration happens on consumption. The body return
value is not an outcome channel. This builder acquires no resource and promises no
cleanup. No special stream class, global current pipeline, coroutine, or runtime
code generator is involved. The vocabulary and captured state are fresh per build;
the source itself may still be shared.

This is an exploratory local vocabulary, not a new Mua standard library. Prefer the
native method spelling for short chains. Use a builder when named steps, conditional
configuration, or a domain vocabulary improve the reading.

## Protocol details that matter

- Lua Fun producer calls return a wrapper plus parameter/control. A single local
  retains only the wrapper. Use `for _, value in Fun.iter(selected) do ... end` to
  restore the triple, not `for _, value in selected do ... end`.
- The first iteration result is opaque control, NOT an ordinal. `take`, `zip`, and
  other operations may use compound control state. Use `enumerate` for numbering.
- Map/filter callbacks see payload values, not the control value. Preserve multiple
  payload results and nil holes; do not pack/unpack them through a plain array.
- `nil` control ends iteration; false payloads are ordinary values.
- Pure generators such as a range can be replayed. Wrapping a mutable reader or file
  cursor does not make it replayable. `cycle`, `partition`, and `span` require suitable
  replayability; do not apply them blindly to the Lisp reader.
- Not every operation is fully deferred: the inspected implementation's `drop_n`
  consumes its prefix when called. `take_while` consumes the first rejected item
  while finding the boundary. The builder offers only map, filter and numeric take
  so that constructing it does not pull input.
- Upstream uses tables in wrappers, parameters, and some per-step control values.
  LuaJIT may sink allocations and inline composed calls; this is a trace-dependent
  optimization, not a universal allocation-free guarantee.
- Resource ownership remains external. A generic for loop on this LuaJIT does not
  install deterministic cleanup on break or failure.

## The Lisp connection

The companion's `Lisp.compiled_programs` answers a cursor, and a cursor's
`step`/`state`/`control` are already a Lua Fun iterator triple, so the example hands
those three fields straight to `Fun.iter` — no adapter — maps compiled programs to
execution, and takes one. A malformed second program is never compiled. It also verifies that
repeated `head` calls on a wrapped mutable reader advance the same cursor rather than
replaying it.

The optional test checks all three interface styles, lexical opening, raw triples,
multiple payload results, no build-time pulls, bounded demand, and the real Lisp
integration. It is deliberately separate from `make test`, which requires no Lua Fun
installation or network access.
