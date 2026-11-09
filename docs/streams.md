# Iteration and streams in Mua

One protocol, one place for a value, and the evidence for both. This page exists so the next
person does not rebuild the engine: the fast path here is LuaJIT's, and it is already reachable
with ordinary functions.

## One protocol

A traversal is a step over a state and a control:

```
step(state, control) -> next control, value        -- nil value ends it
```

That is Lua's own iterator protocol, which is why it is worth having nothing else. The three
values travel as arguments, so nothing is packed per element, and the control starts at 0, which
makes `control + 1` the first line of a step that counts. A stage is a function that closes over
its upstream once and answers in the same shape, so composing two stages costs one call per
element and nothing else:

```mua
local mapped = do(up, transform)
    return do(state, control)
        local next_control, value = up(state, control)
        if value == nil then return end
        return next_control, transform(value)
    end
end
```

A stage that filters holds the loop instead, and that inner loop is where trace boundaries
appear — the one shape in [the compiler experiment](luafun-compiler.md) that kept real
allocations. A stage that needs state of its own (a count, a pair of upstreams) keeps it in
its state.

## One place for a value: the edges

`iter` boxes the protocol when a caller wants a traversal as a *value* — to keep it, pass it,
resume it, or name it in a signature (`local x: iter`, `do(…): iter`). The box's fields are the
triple, so it is not a second protocol:

```mua
for value in walk do ... end                                   -- the value
for control, value in walk.step, walk.state, walk.control do ... end   -- the same thing
```

A cursor belongs at a boundary and nowhere else. Boxed per stage it is measurably slower than
functions; boxed per answer (one per instruction, one per row) it is worse still, because a box
is an allocation and a call, and a stage is already a call.

| what | per 1000 elements |
|---|---|
| a C step over a materialized array (`ipairs`) | the floor |
| a bare Lua step | about 2x the floor |
| the same step boxed once | a few percent over the bare step |
| the pipeline with a cursor per stage | about 2.2x the same pipeline with functions |

## Do not emit source

An emitted, fused loop is not worth building. LuaJIT already fuses this shape:
[the Lua Fun compiler experiment](luafun-compiler.md) records traces where a composed
`map`/`sum` hot loop became array loads, a multiply and a jump, with no callback calls left in
it, and where `map`/`take` ran 0.48 µs against 0.36 µs hand-written. The same experiment shows
the honest counter-case: `filter`/`map`/`take` produced `inner loop in root trace` and
`loop unroll limit reached`, kept real allocations, and ran slower than the reference
interpreter. That is a trace boundary, not a missing compiler — the answer is the shape of the
loop you hand the tracer, not generated text.

Mua's own translation to Lua is a separate thing and stays separate. A library that generated
source would add a cache, a shape key and diagnostics pointing into generated code, for a gain
that the tracer already delivers.

## Do not vendor an engine

Lua Fun is not vendored, and remains optional ([Lua Fun in Mua](luafun.md)). A cursor's fields
are its triple, so an installed Lua Fun takes one directly, with no adapter:

```mua
local forms = Lisp.forms "1 2 3"
local reader = Fun.iter(forms.step, forms.state, forms.control)
```

## Arrays are not streams

A table is already a collection. `ipairs` indexes it, needs no definition, no state and no
control, and a C step costs about half a Lua step, so wrapping an array in a cursor is work for
nothing. A cursor is for what is not materialized yet: a text being read, a batch compiled on
demand, a page fetched when the reader wants it.

## Decision rules

- A **stage** earns a place when a second caller needs it.
- A **shape** earns a language word only when an annotation needs the name.
- A **performance claim** earns a change only after `--trace`, never after a stopwatch alone.

Where this is taught: [`examples/iter.mua`](../examples/iter.mua) builds a cursor, stops and
resumes it, takes a bounded view, reads it as a triple, and shows where `ipairs` is the right
answer instead.
