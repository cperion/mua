# Designing and writing Mua

**A guide to composing programs in Mua, beside [the language](syntax.md), which owns the
rules.** Mua is sugared Lua; this guide is about the shape of programs written in it: how to
group things, how to let a block do the work of an option list, how to write a small language
for a domain, and how it should read. A host (Nua is one) adds its own concerns in an
addendum; this guide does not know any host.

Every `lua` block below is run by `tests/guide.lua`; it checks that the examples work, not the
quality of the advice.

## 1. The stance

- **Lua values first.** A program is functions, tables and closures. Mua adds forms that make
  them pleasant to compose; it does not add a second object system.
- **Structural by default.** Group things by name in a table. Give something a nominal type
  (`struct`, `oneof`) when the program demands an identity or an invariant, not before.
- **Check at the edges.** Annotations are contracts: put them where a value crosses from
  someone else's code into yours, not on every local.
- **A block beats an option list.** When a call needs setup and completion, pass a block and
  let the callee own both (§3).

## 2. Vocabularies

A **vocabulary** is a table of names. `define with … end` reads as a definition; `..base`
extends one, explicit entries overriding.

```lua
local arithmetic = define with
    add = do(a, b) = a + b
    scale = 2
end
local more = define with
    ..arithmetic
    scale = 3
    double = do(x) = x * 2
end
assert(more.add(1, 2) == 3 and more.scale == 3 and more.double(4) == 8)
```

- **Compose by spread, not by inheritance.** Two vocabularies compose whatever their entries'
  arities are; a user's extension overrides entries instead of forking the library.
- **Name for what it is.** `.name` in a `with` block is `name = name`: a vocabulary assembled
  from local definitions needs no repetition.
- **Say what is required.** A closed structural type lists the fields a record may have, marks
  those it must have with `required`, and rejects the rest.

```lua
local Node = closed define with
    op = "store"
    place = required
    what = optional
end
local n = { ..Node, place = 7 }
assert(n.op == "store" and n.place == 7 and n.what == nil)
assert(not pcall(function() return { ..Node } end))     -- `place` is required
```

## 3. Blocks as arguments

A block passed last is an **activity**: the callee sets up, the block says what to do, the
callee completes. The trailing colon and `do … end` are the same thing; use the colon when the
block is the whole point of the line.

```lua
local each_pair = do(t)
    return do(body)
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do body(k, t[k]) end
    end
end

local seen = {}
each_pair { a = 1, b = 2 }: key value
    seen[#seen + 1] = key .. value
end
assert(table.concat(seen, ",") == "a1,b2")
```

- **Application is curried.** `f a b` is `f(a)(b)`, so an activity that takes setup and then a
  block is a function that returns the function taking the block (above); `f a: x … end`
  passes the block as the next argument.
- **The activity owns completion.** The callee closes what it opened, whatever the block does.
- **The block decides, the activity completes.** A block that wants to stop early returns a
  value; it does not reach into the callee's state.
- **Stack activities instead of adding options.** `a do b do … endall` reads as nesting;
  `endall` closes the whole pyramid at once.

**Opening** lets a block speak in the activity's vocabulary without naming it. An opened
table introduces its string keys.

```lua
local total = do(ctx..) return count + 1 end
assert(total({ count = 4 }) == 5)
```

- **Open to work; bind to remember.** An opened name reads the table's current value; take
  `local before = count` to keep the value at that point.
- **One context per purpose.** A block that keeps reaching around its context is missing a verb
  or mixing responsibilities.

## 4. Builders and small languages

A **builder** is an activity whose context is a vocabulary and whose completion returns a
description. The block's instructions declare things; the builder collects them.

```lua
local keymap = do(body)
    local bindings = {}
    body(define with
        bind = do(key) = do(command)
            bindings[#bindings + 1] = { key = key, command = command }
        end
    end)
    return bindings
end

local keys = keymap(do(ctx..)
    bind "h" "left"
    bind "l" "right"
end)
assert(#keys == 2 and keys[1].command == "left" and keys[2].key == "l")
```

A DSL in Mua is not a parser. It is a vocabulary, a description and an engine, designed in
that order:

1. **Choose what each phrase is** (an instruction run now, a declaration collected into a
   description, or plain data).
2. **Give the vocabulary verbs for what happens** and names for what is known (tokens).
3. **Instructions run in order**, so a later setting wins; no merge rules are needed.
4. **Keep builders pure.** A builder describes; an engine walks the description and does the
   work.

## 5. Choices and contracts

Use `oneof` when a value is one of several named alternatives and the program must say what
each means; a match is checked for exhaustiveness every time.

```lua
local Shape = oneof { circle: Number, rect: Table }
local area = do(s: Shape): Number = s {
    circle = do(r) = r * r,
    rect = do(t) = t.w * t.h,
}
assert(area(Shape.circle(3)) == 9 and area(Shape.rect { w = 2, h = 5 }) == 10)
```

A missing or unknown handler is an error at the match, so adding an alternative finds every
place that has to change. Use `struct` for a record whose fields are all known and typed;
an annotation is a contract (`do(p: Point): Number`), checked at the call.

## 6. Style

- **Calls.** Prefer juxtaposition where it reads as a phrase (`bind "h" "left"`, `insert n`);
  keep brackets for grouping and for ambiguity (`f (x + 1) y`).
- **Blocks.** Colon form for a trailing untyped block; `do(params) … end` when the block has
  typed parameters or is not the last thing on the line.
- **Data.** `with` for keyed data that spans lines; `{ }` for Lua tables and compact
  one-liners.
- **Names.** Lowercase words for Mua's own forms (`struct`, `oneof`, `define`); capitals for
  types a program defines (`Point`, `Shape`).
- **Anti-patterns.** A vocabulary that every caller reaches around; contracts on every local;
  one option list that grows a flag per use (use a block); a nominal type nobody needs yet.
- **Review.** Can a stranger read the block without the callee's source? Does the activity own
  its completion? Is each contract at an edge?

Format with the formatter your host provides; Mua's own rule is that source reads as the
phrases above.
