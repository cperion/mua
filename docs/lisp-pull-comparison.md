# A cursor over the same Lisp: `iter` at the traversal boundaries

`examples/lisp_pull.mua` is a companion to `examples/lisp.mua`, not a smaller
language. The original example exposes its existing operations when loaded with
`"library"`; normal execution keeps its original printed output.

The companions share the same nominal families, parser, checker, interpreter,
lowering, optimizer handlers and emitter. What differs is where a traversal
boundary is drawn, and the companion states each boundary as the language's
cursor: an `iter` value with a step. The optimizer is built once per strategy with
three supplied operations: `single`, `empty`, and `rewrite`. Eager handlers build
a one-element list per answer; the cursor handlers answer with a cursor over their
replacements. There are no separate copies of the optimizer's language decisions.

## What changes

| Boundary | Eager | Cursor |
|---|---|---|
| Source to tokens | spaced copy of source and full token array | a scanner state read in place, no copy and no array |
| Tokens to data | indexed token array | one cursor over the text, one datum per step |
| Data to syntax | materialized datum list | same materialized datum list |
| Checking and lowering | family passes | identical passes |
| Replacement answer | temporary zero/one-element list | a shared iterator: the instruction is the state, so an answer allocates nothing |
| Optimizer output | owned instruction list | same owned instruction list |
| Emission | Lua string | identical Lua string |
| Batch of programs | compile all, then select | one complete program per step |

The cursor is the language's `iter`: `iter start do(state, control) … end`, whose step is
Lua's own iterator protocol, so `walk.step, walk.state, walk.control` is a triple plain
Lua (and Lua Fun) already understands. Only the two traversals are cursors; a replacement
answer is not a traversal, and the measurements below say why.

A cursor's state is the traversal's own: using a value again continues where it
stopped, two cursors share nothing, and copying a cursor shares its state rather
than cloning it. Reading a prefix of the reader is NOT compiling a prefix as a
complete program. The language still consists of definitions followed by one final
expression. Whole-program compilation consumes the entire input and rejects
malformed tails. Batch laziness applies only across independent complete programs.

## Deliberate materialization boundaries

The parser needs the final expression and preceding definitions. Its datum list is
retained rather than changing parsing order or error precedence just to be lazy.

The optimizer needs read counts, label information, and fixed-point comparisons.
Its reaching pass can delete a previously written jump when it reaches the next
label. Yielding that jump irreversibly to an arbitrary consumer would be wrong.
Each rewrite therefore retains its own output, including in nested closures. Only
the transient answer is an iterator.

Emission retains the inspectable Lua text. Lua execution is unchanged; the cursor
version is not an alternate evaluator.

A cursor acquires no external resources. File-backed traversal would need an
activity to own cleanup on exhaustion, early exit and errors.

## Correctness

`tests/lisp_pull.lua` compares complete datum lists, syntax trees, unoptimized IR,
optimized IR, and emitted Lua. It compares compiled results with the reference
interpreter and unoptimized execution, and checks optimizer fixed points. It also
checks that a handler may answer with any iterator, that nested rewrites keep
private buffers, and that reading one datum leaves a malformed tail unread.

The deterministic corpus includes generated expressions, recursion, captured
variables, shadowing, multiple definitions, and false results. Tests also cover
matching diagnostics, lexical edge cases, nested rewrite ownership, and multiple
replacements. The executable companion adds complete-program batch
stopping/resumption and interleaved cursors.

`tests/iter.lua` covers the cursor type on its own: the curried construction, resumption
after a break, the control as progress, independent and interleaved cursors, `take`
spending from its parent, the triple view, `false` as a value (only nil ends a
traversal), and the checker's contracts.

The eager example's expected-output comment is unchanged. Both example outputs are
checked by `tests/examples.lua`.

## Measurements

Run from the repository root, with the patched LuaJIT required by Mua:

```
/path/to/luajit bench/lisp_pull.lua 30
```

The benchmark compares four full-compilation configurations to isolate changes:
original traversal protocols, cursor reader only, cursor rewrites only, and both.
It also measures the reader and optimizer independently, then separately measures
early-demand workloads.

Factories and Mua translation are outside the timed region. All configurations use
the same checked constructors. The eager comparison uses the shared,
protocol-parameterized optimizer, not an archived pre-refactoring executable. The
workload has sixteen reachable functions, 1,503 source bytes and 386 lowered
instructions. Every generated function remains below Lua's local-variable limit.

Seven samples alternate strategy order. Timing includes normal garbage collection.
The memory column reports median Lua heap growth for one warmed operation with GC
stopped, not allocation counts, peak RSS, or retained memory after collection. JIT
allocation sinking and trace state can affect these numbers.

One run on LuaJIT 2.1.1793383622 (30 iterations per sample):

| Equivalent work | Eager | This companion | Eager heap growth | Companion heap growth |
|---|---:|---:|---:|---:|
| Full compilation | 1,071 us | 1,062 us | 412 KiB | 357 KiB |
| Read complete input | 162 us | 161 us | 35 KiB | 23 KiB |
| Optimize already-lowered input | 232 us | 290 us | 116 KiB | 73 KiB |

## What the numbers say about the type

The cursor pays at a traversal boundary and costs at a per-answer boundary, and the
two measurements separate them.

- **Reading:** a cursor over the text holds the scanner in its own state and the
  position in its control, so there is no spaced copy and no token array. Heap growth
  for a complete read drops by about a third at the same time.
- **Answering:** the same abstraction costs at this boundary, so the answer is not a
  cursor. Measured three ways on this workload, against a list per answer (232 us,
  116 KiB): a cursor whose state is the answer boxed it in one table (373 us,
  213 KiB, 1.9x), and the curried constructor adds a closure per construction, so
  building a cursor per instruction measured 691 us and 372 KiB (3.0x). A shared
  iterator per answer — the step shared, the instruction as its state, the control
  saying whether it has been read — costs no allocation: 290 us with 73 KiB, less
  heap than the list and a quarter more time, because a Lua step is a call where a
  list append is not.
- **Demand:** these rows intentionally do different amounts of work. Reading one
  datum rather than all of a long input, or compiling one program rather than
  eight, demonstrates control over work, not a fair claim of faster full
  compilation. A hand-written eager loop that stops after its first compilation
  would avoid the same batch work; the cursor makes that demand boundary composable
  and explicit.

Full compilation is within noise of the eager version; no throughput claim follows
from it. The memory column is the one that repeats across runs.

The substrate was measured too, on a 1000-element traversal on the same machine: a
C step over a materialized array (`ipairs`) takes 0.58 us, a cursor 1.1 us, and a
coroutine generator 20.6 us. A generator is the expressive option — arbitrary control
flow per element, several values per step — and it is 18x the cursor because a
yield/resume crosses C and cannot live in a trace. That is why a cursor type is worth
having here at all, and why the two traversal boundaries use it.

## Conclusion

- Pull at boundaries where consumers can stop or interleave work, and state each
  one as a cursor so resumption, bounded views and interleaving come from the type.
- Let the cursor's step be Lua's iterator protocol: the value is then a triple where
  plain Lua (and Lua Fun) wants one, with no adapter.
- Keep a per-answer protocol allocation-free; a cursor is a traversal, not a value's
  ferry, and the cost of forgetting that is measured above.
- Retain owned representations where later stages need inspection, global
  knowledge, backward edits, or repeated traversal.
- Measure full consumption separately from avoided work, and measure a type where
  it is used, not where it is convenient.
