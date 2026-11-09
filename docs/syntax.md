# Mua: the surface language

Mua is sugared Lua: every Mua program (a `.mua` file) is read by Mua's lexer and parser and written back as
plain Lua that LuaJIT runs. It knows nothing about any host that gives its forms more meaning
(Nua is one). This document owns Mua's surface syntax and runtime semantics; a host's own
documents say what a host adds.

```
Lua  →  Mua  →  Nua
```

## 1. Lua, and what Mua reads

Mua is **LuaJIT 2.1 with LuaJIT 3.0's syntax backport**, emitted verbatim: short functions
`|a, b| -> e`, `x -> e`, `|| -> e`, `-> do … end`; `c ? a : b`; `?.` in all its forms; `??`;
`! && || !=`; `~ & | << >> ~>>`; compound assignment `+= -= *= /= %= &= |= ~= <<= >>= ~>>= ..=`;
`const`; `continue`; `_` in numbers; `0b` literals; `;;`; the line directive `# n "name"`. Not in
LuaJIT 2.1, so not in Mua: `//`, `^=`, `??=`, `...name`. Precedences are LuaJIT's.

Where LuaJIT's syntax meets Mua's, one reading wins:

- a `:` closes an open `?` (the conditional's middle operand takes no block colon or method colon);
- a name followed by `->` always begins a short function, also as a juxtaposed argument;
- `|` and `||` begin a short function where an expression starts, and are operators between
  operands;
- at the start of a statement, `const` and `continue` followed by a name (or `function`) are
  LuaJIT's declaration and statement; a `~=` statement is the xor-assignment;
- `local ctx..=value` is an opening with an initializer (§6), not `..=`.

The customary spellings `! && || !=` are the same operators as `not and or ~=`.

## 2. Application

Application is juxtaposition:

```lua
local fifteen = triangular 5
local twice = map xs x -> x * 2
```

1. **What can be an argument.** After a callable expression, these start an argument: a number,
   a string, `true` or `false`, a table constructor or a short function — on any line — a `do`
   lambda, only on the same line, and a **name**, only on the same line and only directly after a
   name, a name argument (with its member chain: `f a.b x` is `f(a.b)(x)`), a number, string or boolean
   argument (`f 1 x` is `f(1)(x)`) or a spaced group (rule 3). A name does not continue an
   application after an attached call (`f a(b) x` is `f(a(b))` followed by `x`, rule 7) or
   after a table.
2. **The newline rule.** A newline ends an application chain before any token that can begin a
   statement. Names and `(` can begin statements, so `local y = x` followed by `y = y + 1` on
   the next line stays two statements, and a `do` can begin one too: a `do … end` block on its own
   line is the next statement, while a `do` lambda that continues the line is an argument (for a
   block on a line of its own, §4's colon form is the spelling).
   Literals, tables and short functions cannot begin statements, so they still attach across lines.
3. **What an argument is.** A primary expression with its postfix chain, as Lua parses it:
   `.name`, `[i]`, `:m args`, `(args)`, and for a name, a table constructor or string. So
   `f a.b` is `f(a.b)` and `f a(b)` is `f(a(b))`. A literal's chain stops at a table or string
   (`f 21 {}` is `f(21)({})`). Only an attached `(` continues an argument's chain: a `(` with
   whitespace before it on the same line is the **next argument group**, so `f a (b + 1)` is
   `f(a)(b + 1)`. Such a spaced group is itself an argument, so names after it go on applying:
   `f (g x) y` is `f(g(x))(y)`. After the callee itself the spacing makes no difference.
4. **Left associativity.** `f a b` is `f(a)(b)`. Application binds more tightly than infix
   operators: `f a + 1` is `f(a) + 1`, and `f -1` is subtraction.
5. **Brackets** group, delimit argument lists and resolve ambiguity; a compound argument is
   written as a spaced group: `f (x + 1) y`.
6. **Loop headers.** The `do` of a `while` or `for` header ends the header; a lambda inside a
   header goes in brackets.
7. **Statements on one line.** Two statements on one line where the first ends with a name and
   the second begins with one (`a = b c = d`) form an application; separate them with `;`.
   `f() g()` is unaffected: a name after an attached call's `)` is not an argument.
8. **Zero-argument call statements.** A bare name or qualified name used as a whole statement
   invokes it with no arguments: `refresh`, `screen.refresh` and `screen:refresh` are
   `refresh()`, `screen.refresh()` and `screen:refresh()`. This is statement-only: `local f =
   refresh` and `return refresh` refer to the value. Use separate lines or `;` between calls
   (`refresh; save`); `refresh save` supplies an argument. Parenthesized or indexed callees keep
   explicit invocation.

## 3. Lambdas

```lua
do(a, b) = a + b            -- an expression body
do(a, b) return a + b end   -- a block body
do ... end                  -- no parameters
|a, b| -> a + b             -- short functions (LuaJIT 3.0 syntax)
```

A lambda is a Lua function. A parameter or result may carry an annotation (§7). A `do` that
begins a statement is Lua's own block; a `do` after an operand, `=`, `(`, `,`, `{` or `return`
is a lambda.

## 4. Blocks as arguments

**The trailing colon.** A colon that ends a line opens an untyped block lambda that opens the
home (`do(..)`), closed by `end`:

```lua
with_buffer n:                -- with_buffer n do(..)
    ...
end
words:each:                   -- words:each do(..)
    ...
end
```

A block with parameters, or one assigned or returned, is a do lambda: `words:each do(key,
value) … end`, `local f = do(x) … end`, `found = do(v) … end`, `return do(body) … end`. The
colon always means a block: it passes it to what is on its left. A colon is a block opener only
where there is no annotation colon: not the result type after a parameter list, not the names
of a `local`, not a field inside brackets, not `::label::`, and not a method call (`xs:each`).

**`with` blocks.** `T with entries end` is `T { entries }`: keyed data without commas, closed
by `end`. Entries are `name = value`, `.name` (which is `name = name`), `[k] = v`, `..spread`,
positional values on lines of their own, and handlers `name = do(params) …`. With no head,
`with` where an expression starts (after `return`, `=`, `(`, `,` or `{`) is the table itself,
which a contract can fill in: where a `struct` or an `ffistruct` is the declared type (a typed
local, parameter or result, a typed assignment, a struct's field, a `oneof` payload), the table
becomes an instance, checked as `T { … }` is. A `struct` instance is the same table, branded in
place; an `ffistruct` value is C data, so it is a new value made from the table's fields (the
table is not changed, and a typed `const` cannot take one). Where no type applies, it stays a
plain table. A host may give it other meaning.

```mua
local Point = struct { x: Number, y: Number }
local origin: Point = with
    x = 0
    y = 0
end
```

**`endall`** closes every open block (`do`, colon and `with`) back to the nearest
enclosing Lua control block or typed function body: `if`, `while`, `for`, `function`,
`repeat`, a bare `do … end`, or a typed function. Those keep their own `end`. Nothing may
follow `endall` inside the blocks it closes. It returns nothing and calls nothing: its effects
are exactly those of the expanded program.

## 5. Data: entries, spread, `define`

`{ ..base, extra = true }` spreads the string keys of a table:

- explicit fields override spread fields regardless of position;
- duplicate explicit fields are rejected;
- two spreads contributing the same field are rejected (`spread-overlap`), unless the block
  names that field itself: an explicit entry resolves the clash;
- all operands evaluate in source order;
- a spread source must be a table (`spread-source`).

`..e` in an argument list, a return list or an initializer list expands a call's several
results or a table's array part. `define` followed by entries and `end` is a table (a plain one, never a host's contextual construction), so a definition reads as
a definition; a **structural type** is the table it is given. A block that is a table is a table
wherever a table may appear, an argument included, so a definition passes straight to what reads
it: `iter start do(state, control) … end`.

**Human labels.** `label "description" value` attaches optional human-facing identity
and returns the same table, function, userdata or FFI cdata value. `label_of(value)` reads it, or returns
nil when absent. Labels are not fields, dispatch keys or semantic IDs; they may supply
captions and diagnostics. Labeling a container does not label its contents.

```mua
local Checking = label "check literals" define
    Literal = do(node) assert(node.value ~= nil) end
end
local program = label "recursion" with
    source = "(define fact ...)"
end
```

A metatable's `__label` supplies the default (including `meta with label = "…" end`).
The runtime keeps per-value overrides in a weak registry for functions and values with
existing metatables (and cdata), preserving shared metatables and contract identity. Plain tables
without a metatable receive one containing `__label`. Use `label_of`, not direct metatable
inspection, to read the effective label. Labels do not implicitly enter a block's scope.
A family pass accepts a labeled handler table directly: `Expression.pass Checking`;
the existing `Expression.pass "description" handlers` form remains supported.

Named constructors supply labels automatically: `checker`, `family`, `struct`, `oneof`,
`ffistruct`, and named passes. Primitive checkers and `Optional(T)` are labeled too.
Struct and oneof instances default to their declared type's label; alternative constructor
functions use `Type.tag`. FFI types and instances use their registered declaration label.
An explicit per-value label overrides the default without relabeling siblings. Relabeling
an FFI ctype object is local to that object, not every equivalent ctype handle.
Semantic names (struct handler keys, union tags and C type names) remain unchanged.
`describe` uses the effective label for human-facing contract descriptions.

`trace value` prints what a value is and what it holds (its label, then one level of its
contents, nested values by their labels) and answers the value unchanged, so it goes anywhere in
an expression: `local total = trace(compute x) + 1`. `inspect value` is that text. Like the outline,
it reads raw table values, never `__index`, `__pairs` or `__tostring`.

**`meta`** installs a vocabulary as a metatable. `meta { index = …, tostring = … }` (or
`meta with … end`) copies its entries under `__` names (`__index`, `__tostring`; a name that
already starts with `__` is kept) and returns a function that sets that metatable on the table it
is given and returns the table; every table it is given shares the one metatable:

```mua
local Printable = define
    tostring = self -> self.name
end
local Comparable = {
    eq = |a, b| -> a.id == b.id
}

local Person = meta with
    ..Printable
    ..Comparable
end with
    id = 42
    name = "Alice"

    greet = do(self)
        print("Hello, " .. self.name)
    end
end
Person:greet  -- Hello, Alice
```

The first block composes behavior (metatable entries), the second the ordinary fields and
methods of the table: methods live on the table, and `index` is only for names that are missing
(`index = defaults`). Both blocks compose by spread; two vocabularies that offer one name clash
until the block names it itself.

`meta` brands nothing and checks nothing: it is the plain Lua counterpart of a `struct`'s methods.

**`family`** is a closed set of structs with passes over it, the shape of an AST and its
compiler passes. The family is declared first, so the structs' fields can be typed with it, and
sealed with its kinds once they exist:

```mua
local Expression = family "expression"
local Literal = struct { value: Number }
local Sum = struct { left: Expression, right: Expression }
Expression { Literal, Sum }

local Evaluation = define
    Literal = do(node, recurse)
        return node.value
    end
    Sum = do(node, recurse)
        return recurse node.left + recurse node.right
    end
end
local evaluate = Expression.pass "evaluate an expression" with ..Evaluation end
print(evaluate(Sum { left = Literal { value = 1 }, right = Literal { value = 2 } }))  -- 3
```

- The names are descriptions. `family "expression of the toy language"` and
  `Expression.pass "evaluate an expression to a number"` take any text; messages quote it back
  (`pass 'evaluate…': no handler for the kind 'Sum' of the family 'expression of the toy
  language'`), and a contract says `expects <description>`, so a short noun reads best for the
  family.
- `Expression` is a checker named by its description: a field typed `left: Expression` fails with
  `expects expression` for a value that is no member. Using it before it is sealed is an error.
- `Expression.pass name handlers` returns a function over the family's values. A handler is keyed by
  the struct's name and called as `handler(node, recurse, ...)`, so it can recur; the extra
  arguments are those the pass was called with (a scope, a state), passed down by each handler's
  own calls (`recurse(node.body, scope)`). Every handler spells the contract the same way,
  `Kind = do(node, recurse) …`, whatever the pass. The pass is checked when it is made: a kind with no handler, a handler for a name that is no kind, and a handler
  that is not a function are errors that name it. A value that is no member is named when the
  pass meets it.
- `Expression.is(node, Literal)` tests a kind (a struct that is not a member is an error, not
  `false`); `Expression.kinds` lists the names in order.
- Passes are vocabularies, so they compose by spread, and an explicit entry settles a clash
  between two of them.

**Lists.** A `define` block (like any `with` block) also takes positional entries: any expression,
one per line, or separated by commas on a line, so it writes list-like tables without commas:

```mua
local steps = define
    "parse"
    "check"
    "emit"
end
local shapes = define
    { kind = "circle", r = 2 }
    { kind = "rect", w = 3, h = 4 }
end
```

An entry that begins a line is a new entry, so a literal, a table or a function on the next line is
never an argument of the one before. Positional and keyed entries mix, a spread (`..base`) is for
keyed entries only, and the empty table is `{}` (a bare `define` is a name).

**Tests.** `test "what it shows":` followed by a block and `end` names a case; the block is its
body. A file of such cases is an ordinary program: run, each case runs where it is named, and a
failure raises `test 'name' failed: …` with its traceback. Run by `mua test files…` (or a host's
runner, through `collect`), the cases are collected first and then each one runs, so every
failure in a file is reported. `collect(run)` runs a function and answers the cases it named,
as `{ name, run }` in order.

```mua
test "spread keeps explicit entries":
    local merged = { ..{ a = 1 }, b = 2 }
    assert(merged.a == 1 and merged.b == 2)
end
```

**Structural markers.** `required` and `optional` are values in a structural type: a keyed
spread of the type fails (`required`) when a required field is not supplied and leaves an
optional one out. `closed` marks a type whose spreads admit only its declared fields. Closed
types are checkers (§7).

## 6. Opening

An opened Lua table introduces its string keys, as they are when it is opened:

| Form | Meaning |
|---|---|
| `do(ctx..)` | receive one argument, then open it |
| `do(..)` | the same, without a name; `(..)` reads the home |
| `local ctx..` | open an existing binding |
| `local ctx.. = e` | evaluate once, bind, then open |

Opening follows lexical shadowing: introduced names shadow earlier visible bindings, later
declarations and openings shadow them in turn, and leaving a scope restores the enclosing
bindings. Initializers resolve names before the new binding is introduced. A name read in an
opened region is the opened table's key if it has one, else the enclosing binding; a write
follows the same rule. Reads and writes allocate nothing and call nothing per access.

## 7. Typed forms: contracts, `struct`, `oneof`

Without a host, annotations are contracts, checked when a function is called, when it returns,
and when a typed local is assigned. A checker is a built-in (`Number String Boolean Table
Function Any Unit Optional(T) iter`), a predicate function (`checker "Node" test` gives one a name,
so a failure says `expects Node`; a short function needs a name parameter to follow an argument
without brackets — `checker "Node" v -> …` parses, `checker "Node" |v| -> …` does not, because `|`
is an operator between operands), a closed structural type, a `struct`
or a `oneof`. A failure names what was expected and what was found at the caller's line:

```lua
local area = do(w: Number, h: Number): Number = w * h
area("3", 4)  -- contract: parameter 'w' of area expects Number, got a string "3"
```

The translator's `contracts = false` removes the checks.

**`struct`**, **`oneof`** and **`ffistruct`** declare their fields in braces (`struct { x: Number }`) or
as a block: the word, the fields on lines of their own, and `end`, the way `define` writes a
table. There is no `with` after the word (`struct with` is an error that says so); `T with` is for
constructing a value of a type.

**`struct`** is a nominal record type: closed, with typed fields, instances branded by a
metatable through which methods (`function P:m() … end`) are reached:

```lua
local Point = struct { x: Number, y: Number }
local p = Point { x = 1, y = 2 }
```

A struct's `__index` method, when it defines one, answers the members an instance's fields and
the struct's methods do not; it receives the instance and the member's name. A value that
names members by its contents (the constructors of a type a host builds) is a struct with an
`__index`, not a table with a metatable of its own, so it stays a branded, checked value:

```lua
local Sum = struct { name: String, alternatives: Table }
function Sum:__index(member)
    if self.alternatives[member] then return constructor_of(self, member) end
end
```

Its `__newindex` method, likewise, receives an assignment to a member the instance does not
declare, with the instance, the member's name and the value; a declared field is still
assigned under its contract. A type a host builds can so take members defined after it
(`function Fixed.__cast(v) … end`) while it stays a closed, checked struct.

A method named as another Lua metamethod (`__call`, `__tostring`, `__eq`, `__lt`, `__le`,
`__len`, `__concat`, and the arithmetic ones) is its instances' metamethod: a struct whose
values are applied (`function Scale:__call(x) … end`) stays a struct.

**`oneof`** is a tagged union with a constructor per alternative. A value is matched by calling
it with one handler per alternative, and **every match checks** that the handlers name exactly
the alternatives: a missing or unknown handler is an error at the match.

```lua
local Shape = oneof { circle: Number, rect: Table }
local area = do(s: Shape): Number = s { circle = r -> r * r, rect = t -> t.w * t.h }
```

**`iter`** is one iteration over a step: a cursor. `iter` takes the initial state, then the step,
curried, so the definition reads in the order a traversal has. The step is Lua's own iterator
protocol: it answers the next control and the value it produces, and a nil value ends the
traversal, so there is no sentinel state. The control starts at 0:

```lua
local counting = do(limit: Number): iter
    return iter limit do(state, control)
        if control >= state then return end
        return control + 1, control + 1
    end
end

local walk: iter = counting 3
for value in walk do print value end          -- 1, 2, 3
for value in walk do print value end          -- nothing: it is spent
```

A cursor is a value twice over. `for value in walk do` uses it as one, and
`walk.step, walk.state, walk.control` hands plain Lua the triple it already understands, so a
cursor passes to ordinary Lua code — and to Lua Fun — with no adapter. The cursor owns its
control, so using the value again continues where it stopped: a `for` that breaks leaves the rest
for a later `for`, and a saved value is a saved position. Since the loop names one variable, a
step answers one value; the progress is `walk.control`. `walk:take n` is a bounded view that
spends from the same cursor, so resuming the cursor continues after what the view read. `iter` is
a checker (`local x: iter`, `do(…): iter`), so an iteration can be named in a signature and a
value that is not one is refused: `expects iter, got a table`.

Two cursors are independent, and interleaving them shares nothing; one cursor used from two loops
at once is one traversal, not two. A reusable source is a function that returns a cursor
(`counting` above), not an `iter` value. [`examples/iter.mua`](../examples/iter.mua) is the guided
tour, and [streams.md](streams.md) tells a stage, a box and a fused loop apart.

`iter nil` is not an application (a nil literal is not an argument); write `iter (nil) do(…)` when
the state is nothing.

**`ffistruct`** declares a C struct for LuaJIT's FFI and gives back its ctype:

```lua
local Point = ffistruct { x: double, y: double }
local Segment = ffistruct { a: Point, b: Point, tag: "uint8_t[4]" }
local p = Point { x = 12.5, y = 8 }
```

A field's type is a C type: a name nothing in scope binds is read as C's (`double`), a string is
C text (`"uint8_t[4]"`, `"char *"`), and a name that is bound must hold an `ffistruct` ctype
(nesting). The result is an ordinary ctype: values are built as for any ctype (`Point { … }`,
`Point(1, 2)`). A ctype is a checker, so it works as a contract (`do(p: Point)`), a `struct`
field or a `oneof` payload, and a headless `with` is filled into one (§3). There are no methods on
an `ffistruct`.

## 8. For hosts

A host gives the typed forms and other forms meaning through a table passed to the translator:
`typed_lambda`, `typed_function`, `opened_lambda`, `struct`, `sum`, statement and prefix
keywords the parser consults, a fact provider for analysis, and runtime overrides. A form goes
through the host's meaning or Mua's, never both. A host receives parsed nodes, never source to
reparse. See the design document for the interface.
