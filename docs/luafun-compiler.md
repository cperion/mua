# Experiment: compile a vocabulary to Lua Fun

`examples/luafun/compiler.mua` tests whether Lua Fun can be the execution backend
of a small Mua compiler, rather than merely a collection library.

```
builder -> inspectable description -> bound generator composition -> sum -> JIT traces
```

The compiler never generates Lua source or calls `loadstring`. Mua's own normal
translation is separate, and happens before the experiment runs.

## The language

```mua
local program = describe:
    filter even
    map square
    take 128
end
local run = compile program
local answer = run source
```

The program is an ordered list of structural instructions. The source is a dense
array; the terminal operation is summation of numeric payloads. This experiment's
callbacks are scalar: `filter` takes one value and `map` returns one value (not Lua
Fun's general multireturn protocol). `take` accepts a finite nonnegative integer. The builder owns the
list and hands it back for inspection. No additional iterator object or type system
is introduced.

A compiling vocabulary supplies one binder per operation. Each binder captures its
callback/count and the preceding producer, returning a function from an input source
to a Lua Fun iterator triple. The final compiled closure calls `Fun.sum` to drive
that producer. Pipeline wrappers are constructed per invocation; compilation does
not claim to eliminate their setup cost.

Binding snapshots the instruction structure and callback references. It does not
freeze state captured by those callbacks. Changing a program record later does not
rewrite an already compiled operation; changing a callback's captured variable still
changes its behavior. Execution counters are fresh per invocation.

## Three engines and a handwritten baseline

The example includes:

1. **Pull interpreter:** recursively inspects instruction kinds on each demand.
   It is an independent implementation of filtering, transformation and limiting.
2. **Assemble and run:** interprets the description to build a Lua Fun pipeline
   every invocation, then consumes it.
3. **Compile once:** binds the fixed description to producer closures, then supplies
   new sources on each invocation.

The benchmark also includes a handwritten numeric loop for each measured shape.
All engines compute the same result and demand the same elements. Unlike an eager
array-map reference, the pull interpreter also agrees on callback effect order and
early termination.

The example checks 48 combinations of program shape and source length, repeat
execution, callback effect traces, zero demand, and binding/capture behavior.

## Run it

Lua Fun remains optional and unmodified. Put its checkout on the module path:

```sh
export LUA_PATH='/path/to/luafun/?.lua;;'
/path/to/patched/luajit mua.lua examples/luafun/compiler.mua
make test-luafun LUA=/path/to/patched/luajit
/path/to/patched/luajit bench/luafun_compiler.lua 1000
```

The benchmark reports seven alternating timing samples, with source setup and
compile-once preparation outside the timed invocation. Per-invocation composition
setup and normal GC are included. Preparation cost is also reported separately.

Memory measurements are GC-stopped Lua heap growth across 100 warmed invocations,
not allocation counts or peak RSS. Tiny constant-result cases can be optimized
aggressively; nanosecond numbers there are not general call-cost measurements.

Shapes include map alone, map/take, filter/map, and filter/map/take with several
limits. Benchmarks in one process share JIT trace history; short runs and later
cases can change which traces are recorded. Do not interpret one relative timing
as a universal optimization policy.

## Inspect the backend, not just the stopwatch

Each command below starts a fresh process, loads the compiler, flushes existing
traces, and records only the selected engine's workload:

```sh
/path/to/patched/luajit bench/luafun_compiler.lua --trace staged /tmp/map.trace map
/path/to/patched/luajit bench/luafun_compiler.lua --trace staged /tmp/map-take.trace map-take
/path/to/patched/luajit bench/luafun_compiler.lua --trace staged /tmp/filter-map.trace filter-map
/path/to/patched/luajit bench/luafun_compiler.lua --trace staged /tmp/full.trace
/path/to/patched/luajit bench/luafun_compiler.lua --trace handwritten /tmp/manual.trace
```

`assembled` and `interpreted` are also valid engine names. Inspect the IR and machine
code between `LOOP` markers, and the abort/exit messages. Merely finding a `TNEW` in
IR does not prove allocation: LuaJIT marks sunk allocations with `}`. Machine-code
allocation calls and heap measurements help distinguish sunk from surviving tables.

### Observed on LuaJIT 2.1.1793383622

Lua Fun upstream revision: `057ede73d78b0e6bdbb354b35492d28c7950f857`.

- **Map/sum:** the consuming loop in `fun.lua` became array loads, multiplication,
  addition, bounds/type guards and a loop jump. No callback calls or allocation
  instructions remained in that hot loop. Setup/exit traces still did work.
- **Map/take/sum:** the hot loop also fused. Control-table `TNEW` instructions were
  marked sunk; no per-element table allocation calls remained in that loop.
- **Filter/map/take/sum:** this run produced `inner loop in root trace` and
  `loop unroll limit reached` aborts, linked traces and real allocation calls.
  Filtering alone is not inherently unfusable; the composition's trace boundaries
  matter. This is not proof that every input or JIT configuration must behave so.

One seven-sample run (500 invocations per sample) measured:

| Shape | Handwritten | Interpreted | Assembled | Staged |
|---|---:|---:|---:|---:|
| map/sum, 4096 values | 3.60 us | 7.33 us | 4.70 us | 4.75 us |
| map/take 128/sum | 0.36 us | 4.92 us | 0.48 us | 0.58 us |
| filter/map/take 128/sum | 2.75 us | 6.87 us | 10.50 us | 10.29 us |

The staged filtered/limited pipeline grew the heap by about 11.6 KiB per invocation,
versus about 0.37 KiB for map/take. At limit 1024 the filtered/limited case grew about
90 KiB. That growth is consistent with surviving per-item control allocations;
it is not a precise allocation attribution.

Other runs changed relative timings substantially, including the reference
interpreter's performance as it acquired different traces. The stable finding is
not "staging always wins": it is that some compositions demonstrably fuse, while
a nearby shape can retain control-state allocations and run slower than the
reference interpreter. Assembling each invocation can perform almost as well as
binding once because LuaJIT also specializes the assembly engine.

## What this says about Mua

A domain vocabulary can compile to ordinary functions and iterator triples. LuaJIT
can then turn that executable representation into a tight loop without Mua emitting
specialized source. That part of the hypothesis is demonstrated.

But lazy semantics and efficient execution are different properties. Preserve the
clear vocabulary and independent reference; inspect trace boundaries before adding
more staging machinery. No upstream changes, hidden JIT-option tuning, or universal
speed claims are needed to make this a useful compiler experiment.
