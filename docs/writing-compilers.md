# Writing compilers in Mua

**A guide to writing compilers, interpreters and other language tools in Mua.** It builds one
compiler from text to running Lua, stage by stage, and stops at each stage to say what the
stage is for, what Mua offers it, and what to watch for. [The language](syntax.md) owns the
rules; [Designing and writing Mua](designing-and-writing-mua.md) owns the general design
method, which this guide applies to one kind of program.

A compiler is the program Mua is best at, for a reason worth stating first: a compiler is a
**closed set of shapes** (the kinds of syntax, the kinds of instruction) with an **open set of
operations** over them (checking, interpreting, lowering, optimizing, printing, emitting), and
Mua has a word for each side. `family` closes a set of `struct` kinds; a pass is a vocabulary of
handlers keyed by kind, checked against the family when it is made; vocabularies compose by
spread. The rest of this guide is that idea worked out.

The `lua` blocks below form one program, read top to bottom: `tests/guide.lua` translates and
runs them together, so a later block uses what an earlier one defined, and each is written as
`mua fmt` writes it. `examples/lisp.mua` is a shorter relative of the same compiler, without
source positions or collected problems.

* **Part I** (§1–§4) is the vocabulary: the shape of a compiler, and the tools it is built from
  (families, passes, state).
* **Part II** (§5–§12) builds the compiler: reading, parsing, checking, interpreting, lowering,
  optimizing, emitting, and testing.
* **Part III** (§13–§17) is judgment: names, performance, open and closed sets, languages
  beyond a Lisp, and what this approach still lacks.

## 0. Forms this guide relies on

| Form | Used for |
|---|---|
| `family "description"` … `Family { KindA, KindB }` | a closed set of struct kinds, declared first, sealed once its structs exist (§3) |
| `struct { field: Type }` | one kind: a nominal record with checked fields |
| `Family.pass "description" with … end` | a function over the family: one handler per kind, checked when it is made (§4) |
| `define … end` | a vocabulary: the handlers of a pass, shared and extended by spread |
| `..Base` and an explicit entry | composition: a spread contributes entries, an explicit entry overrides; two spreads that offer one name clash unless an entry names it |
| `checker("name", test)` | a named predicate, for contracts the built-ins do not cover (§3.3) |
| `meta { index = … }` | a metatable from a vocabulary; here, scopes that fall back to the scope around them (§7) |
| `load(text, name)` | running the Lua a compiler emits (§11) |

## Part I: the vocabulary

## 1. The shape of a compiler

A compiler is a pipeline of representations. Each stage reads one and writes the next:

```mermaid
flowchart LR
    text -->|tokenize| tokens -->|read| data -->|parse| tree[syntax tree]
    tree -->|check| tree
    tree -->|interpret| value
    tree -->|lower| instructions -->|optimize| instructions
    instructions -->|emit| lua[Lua text] -->|load| running[running code]
```

Three decisions shape everything else:

1. **Every representation is data.** A stage's output can be printed, compared, stored and fed
   to a test without running the stages after it. That is what makes a compiler debuggable:
   when the output is wrong, you look at each representation in turn until one is.
2. **Each representation is a closed set of kinds.** The syntax has so many kinds of
   expression; the instructions, so many kinds of instruction. Adding a kind is a language
   change, and every operation must learn it. A `family` makes that a checked fact (§3).
3. **Operations are open.** New passes arrive all the time: a new check, an optimization, a
   printer for debugging, a second back end. A pass is a vocabulary, so a new one never edits the
   kinds or the other passes (§4).

The second and third points are the two sides of the *expression problem*: in most languages
either new kinds or new operations are cheap, and the other is expensive. Here kinds are
deliberately expensive (each pass is told when one is missing) and operations are cheap (a
vocabulary and a word).

## 2. Stages, and what an operation knows

A stage is a function from one representation to the next. Inside a stage, the work is a walk
over a tree or along a list, and the walk needs to know things: the names in scope, the code
being written, the problems found so far, what a register is known to hold. Each piece of that
information plays one of four **roles** in the operation:

| Role | How it behaves | In this guide |
|---|---|---|
| **inherited** | handed into nested work, extended there, never seen changed by the outer work | `scope`, `environment`, `registers`, `indent` |
| **accumulated** | shared by all the work, which contributes to one result | `problems`, `reads`, `labels` |
| **evolving** | updated as an ordered computation proceeds, read by what comes after | `known`, `dead` |
| **produced** | created by the current activity, which owns it and hands it back | `code`, `written` |

Beside them sit **capabilities**: something the work may use, shared by everyone who has it, like
the supply of fresh names (`fresh`).

These are roles, not types or rules about storage: one table can hold several (the lowering
state holds produced `code`, inherited `registers` and the `fresh` capability), and a handler
can receive state as an argument or capture it in a closure. A vocabulary may be stateless or
stateful; its state need not be a field on the vocabulary. The roles are questions to ask of
each piece of state, and §4.5 turns them into a way of designing its ownership, lifetime and
access. Name each piece for what it holds (`scope`, `problems`, `lowering`), never `ctx`: the
name is how a reader tells which it is.

## 3. Families: closed sets of kinds

### 3.1 Declaring a family

A family is declared first, so that its structs' fields can be typed with it, and sealed with
its kinds once they exist. Its name is a description: it appears in messages, so write what a
reader of an error should see.

```lua
-- a family of two kinds, to show the mechanism; the compiler's own families follow in §6 and §9
local Shape = family "shape"
local Circle = struct { radius: Number }
local Pair = struct { left: Shape, right: Shape }
Shape { Circle, Pair }

local two_circles = Pair { left = Circle { radius = 1 }, right = Circle { radius = 2 } }
assert(Shape.is(two_circles, Pair) and not Shape.is(two_circles, Circle))
assert(table.concat(Shape.kinds, " ") == "Circle Pair")
```

The family is a checker: a field typed `Shape` refuses anything that is not one of its kinds,
and says so with the description:

```lua
local built, message = pcall(Pair, { left = Circle { radius = 1 }, right = 5 })
assert(not built and message:find("expects shape", 1, true))
```

`Shape.is(node, Kind)` asks a kind, and asking about a struct that is not a kind of the family is
an error rather than `false`, so a misspelled kind cannot quietly answer no.

### 3.2 Kinds are structs

Each kind is an ordinary `struct`: closed (a misspelled field is an error where the node is
built), typed (each field is checked), and nominal (a `Circle` is not a `Pair` with the same
fields). Build nodes only through their struct, and the tree is valid by construction: there is
no node of a kind the family does not know, and no field holding the wrong kind of thing.

Two habits pay off from the start:

* **Give every syntax node its source position** (an `at` field). Every later error needs one,
  and adding it afterwards touches every constructor.
* **Keep nodes free of behavior.** The operations live in passes; a node is its fields. That is
  what lets a node be printed, compared and rebuilt with a spread.

### 3.3 Lists of nodes

A struct field typed `Table` accepts any table. A list of nodes is better described with a
named checker, which `checker` makes from a predicate; `check(Type, value)` asks any checker:

```lua
-- a list whose every element passes the element type, named for messages
local list_of = do(element_type)
    local every = do(value)
        if type value ~= "table" then return false end
        for _, element in ipairs value do
            if not check(element_type, element) then return false end
        end
        return true
    end
    return checker("list of " .. tostring element_type, every)
end
```

A checker that walks a list costs a pass over the list each time a node is built. That is cheap
for a compiler's trees; §14 says how to turn contracts off where it is not.

## 4. Passes: operations over a family

### 4.1 A pass is a vocabulary checked against the family

`Family.pass "description" handlers` returns a function over the family's values. `handlers` has
one entry per kind, keyed by the struct's name. It is checked when the pass is made: a kind with
no handler, a handler for a name that is no kind, and a handler that is not a function are errors
that name them. So a pass that compiles has a handler for every kind, and a new kind makes every
pass that has not learned it fail where it is made, not when some program first uses the kind.

```lua
local Area = define
    Circle = |node, recurse| -> 3 * node.radius * node.radius
    Pair = |node, recurse| -> recurse node.left + recurse node.right
end
local area = Shape.pass "area" with ..Area end
assert(area two_circles == 15)

local made, why = pcall(Shape.pass "area", { Circle = Area.Circle })
assert(not made and why:find("no handler for the kind 'Pair'", 1, true))
```

The `family` builtin's pass machinery calls `handler(node, recurse, ...)`: first the current
node, then the recurse hook, then the context the pass was called with (a scope, an environment,
a lowering state). Those positions are fixed by the builtin, not by convention. Every handler in
this guide spells them that way, `Circle = do(node, recurse)` or
`Variable = do(node, recurse, environment)`, whatever the pass: the first two never move, so a
handler never has to be decoded, and `recurse node.left` says what happens. The pass's own name
(`area`, `check`, `evaluate`) belongs to the place it is called from.

### 4.2 A result and its effects

Each handler of a pass has a **primary result**, what it returns, and may have **effects** on the
state it receives or captures. The interpreter has only a result (a value). The checker has
only an effect (problems added to a list), and returns nothing. Lowering has both, and needs
both: it returns the register holding the node's value, and writes the instructions that
compute it.

Decide both for every pass before writing it, and make every handler of the pass follow the same
decision: a pass whose `Let` handler returns a register while its `Literal` handler returns an
instruction is a bug waiting to happen.

### 4.3 Passing state down the tree

Explicit arguments let one pass serve different calls without retaining their state. The
arguments a pass is called with follow the node to its handler. A handler passes them on in its
own recursive calls, changed or not:

```lua
local Depth = define
    Circle = |node, recurse, depth| -> depth
    Pair = |node, recurse, depth| -> math.max(recurse(node.left, depth + 1),
        recurse(node.right, depth + 1))
end
local depth_of = Shape.pass "depth" with ..Depth end
assert(depth_of(two_circles, 0) == 1)
```

### 4.4 Composing passes

Because handlers are a vocabulary, passes are built from one another by spread:

* **A base and its variants.** A shared base is spread in, and each variant names only the kinds
  it changes. The optimizer (§10) is five passes over one base that answers every instruction
  with itself.
* **An explicit entry overrides a spread.** That is the way to say "this pass does what that one
  does, except here".
* **Two spreads that offer the same kind clash** (`spread-overlap`) unless the block names that
  kind itself. Combining two passes that both handle a kind is a decision, and the clash makes
  you write it down.
* **A handler cannot be removed with `nil`**: in Lua, `nil` is absence, so `{ ..Base, Kind = nil }`
  keeps the base's handler. Copy the vocabulary and delete the entry, and the pass will tell you
  the kind is now missing.
* **Spread does not rebind closures.** It copies function values, not the state they capture.
  A handler inherited from a stateful vocabulary still sees that vocabulary's captured state.
  Make a fresh vocabulary for independent work (§4.6); copying it is not enough.

```lua
-- a variant that names only what it changes
local RoundedArea = define ..Area
    Circle = |node, recurse| -> math.floor(3.14159 * node.radius * node.radius)
end
local rounded_area = Shape.pass "rounded area" with ..RoundedArea end
assert(rounded_area two_circles == 15)
```

### 4.5 Designing the state an operation carries

The state a pass carries is designed, not accumulated as the code grows. Its organizing question
is **what survives a boundary**: entering a binding, entering a function, crossing a label,
starting a new rewrite. For each piece of state, ask:

1. What does it hold, and what role does it play (§2)?
2. Who creates it, and how long should it live?
3. Which boundary changes whether it is still valid?
4. At that boundary, is it **shared**, **extended**, **reset** or **discarded**?
5. Does a handler receive it as an argument, capture it, or use both mechanisms?
6. Who owns its result when the work completes?

The compiler's boundaries, answered:

| Boundary | Kept | Changed |
|---|---|---|
| entering a `Let` (§9.3) | `code`, `fresh`, the outer bindings | `registers` extended with the new name |
| entering a `Lambda` (§9.3) | `fresh`, the enclosing bindings | a new `code`; `registers` extended with the parameters |
| crossing a label (§10.3) | the instruction sequence | every `known` fact forgotten |
| entering a function's code in an optimization (§10.3) | `labels`, `reads` | `known` reset, a new `written` |
| starting a rewrite (§10.1) | whatever the caller's state shares | a new `written`, owned by the rewrite |

**Capture or pass.** Capture what belongs to the whole activity; pass what varies within it.
This is a useful default, not a restriction: a factory can also create a vocabulary for a nested
scope or function. A checker's handlers can capture one `problems` list while receiving `scope`
on each call. A lowering operation can capture its fresh-name supply while passing the current
function's code and bindings. A closure changes how state is reached, not its role or ownership.
§4.6 works through this choice.

**Separate values or one table.** For state passed explicitly, use separate arguments when their
roles differ: the checker below takes `scope` (inherited) and `problems` (accumulated), and the
emitter takes only `indent`. Group them in one table when they are the working circumstances of
one activity, changed together at its boundaries: lowering's `code`, `registers` and `fresh`.
These are choices for this compiler, not a requirement that vocabularies be stateless. There is
no universal context record, and none is needed.

**Giving nested work its state.** Existing mechanisms have different meanings and costs:

* a **closure** gives handlers access to the bindings where they were made. A factory can make
  fresh private state for each activity, or intentionally capture state supplied by its caller;
* a **spread** makes a table with some responsibilities replaced: `{ ..lowering, code = {} }` is
  the lowering state of a new function. It copies the table (shallowly), so what the copy shares
  stays shared;
* a **fallback** (`meta { index = outer }`, §7.1) extends a table of names without copying it:
  entering costs nothing, and looking a name up costs a step per level of nesting;
* a **shared reference** carries an accumulator or a capability into nested work unchanged:
  `problems`, `fresh`, `reads`.

**Order is part of the meaning.** A handler that changes evolving state or appends to produced
state depends on the order in which its children are visited. The Lua manual leaves the order of
evaluation in a multiple assignment undefined, so
`local left, right = lower(a, lowering), lower(b, lowering)` promises nothing about which
operand's instructions come first. Visit such children in separate statements, one after the
other, as the lowering pass does; then the order is the order of the text.

**An activity owns the temporary state it creates.** A rewrite creates the list it writes into;
that list belongs to the rewrite, and a handler reaches it through state the rewrite made, not
through a field the rewrite planted in its caller's table (§10.1 shows why). Capturing that list
in handlers made for the rewrite is another valid design; under that arrangement, each nested
rewrite needs its own captured output, not one list shared across both activities.

This is the design guide's method (*Designing and writing Mua*, Part I) applied to one kind of
operation. For a transformation, the steps are: choose the family it understands; name what it
does (check, evaluate, lower, rewrite, collect, emit); find its default behaviors (what preserves,
contributes nothing, or shares a handler); design its state by role and boundary; compose its
handlers with `define` and spread and let `Family.pass` check them; and test both its results
and its obligations to its state. The family says what can exist; the pass says what the
operation does with each kind; the state says what it knows, carries and produces; the activity
says who owns the work and its completion.

### 4.6 Stateful vocabularies: one instance per activity

A vocabulary is not necessarily reusable, stateless behavior. It can be the verbs of one
particular operation, closing over that operation's state. Here a factory creates a vocabulary
that collects the depth of every circle. `depths` is accumulated state, captured once; `depth` is
inherited state, passed at each recursive call because it changes within the traversal:

```lua
local collecting_depths = do()
    local depths = {}
    local Collecting = define
        Circle = do(node, recurse, depth)
            depths[#depths + 1] = depth
        end
        Pair = do(node, recurse, depth)
            recurse(node.left, depth + 1)
            recurse(node.right, depth + 1)
        end
    end
    return Collecting, depths
end

local collect_depths = do(tree)
    local Collecting, depths = collecting_depths()
    local collect = Shape.pass "collect circle depths" with ..Collecting end
    collect(tree, 0)
    return depths
end

local uneven = Pair { left = two_circles, right = Circle { radius = 3 } }
local first_depths = collect_depths uneven
local second_depths = collect_depths two_circles
assert(first_depths ~= second_depths)
assert(table.concat(first_depths, " ") == "2 2 1")
assert(table.concat(second_depths, " ") == "1 1")
```

The factory creates the state and its handlers together; `collect_depths` builds a pass once per
operation, not once per node, runs it and hands back its result. Repeating the operation creates
another list without clearing or changing the previous result. Nothing in `family` requires
state to travel as an argument, and the handler contract remains `node, recurse, ...`.

**Composition shares captures; factories can separate them.** The following pass copies the
collector's handlers. Its `Circle` handler still appends to the original list. The override for
`Pair` starts a separate, nested collection before continuing the outer one:

```lua
local Collecting, shared_depths = collecting_depths()
local collect_original = Shape.pass "collect into the original list" with ..Collecting end
local collect_nested = Shape.pass "collect with nested work" with ..Collecting
    Pair = do(node, recurse, depth)
        local nested_depths = collect_depths node
        assert(table.concat(nested_depths, " ") == "1 1")
        assert(table.concat(shared_depths, " ") == "1 1")
        Collecting.Pair(node, recurse, depth)
    end
end
collect_original(two_circles, 0)
collect_nested(two_circles, 2)
assert(table.concat(shared_depths, " ") == "1 1 3 3")
```

Sharing the first collector's list between these two passes is intentional; the nested
`collect_depths` call creates its own vocabulary and result. For independent variants, invoke
the factory separately before composing them. A factory that captures a caller-supplied table
still shares that table: fresh closures alone do not guarantee fresh state. Passing the same
table to two operations also shares it; isolation follows ownership, not argument versus capture.

**Choose the lifetime, not a ban on state.** A module-level vocabulary may intentionally share a
cache or configuration. Per-compilation problems and temporary output normally belong to a
fresh operation instead. Keeping a vocabulary after its activity returns keeps its captures
reachable too: escaped handlers and any resources they retain need an explicit lifetime.

Keeping one mutable `current_scope` in a closure and swapping it on entry and exit is possible,
but then restoration on errors, reentrant calls and interleaved work becomes part of the
design. Explicit scope arguments, or fresh vocabularies bound to each scope, avoid that
shared-current-state obligation. A captured output buffer needs the same boundary care:
entering another function must not accidentally write into its parent's buffer.

The compiler below keeps its pass state explicit so one pass can be reused and the boundaries
are visible at each call. Capturing activity-owned state is an equally valid arrangement, not a
workaround and not a reason to introduce a context framework.

## Part II: building a compiler

The language is a small Lisp: numbers, names, `(+ a b)` and the other binary operators,
`(if condition when-true when-false)`, `(let ((name value) …) body)` (a binding sees itself, so a
function can recur), `(lambda (name …) body)`, applications, and a program of
`(define name value)` forms ending in an expression. The target is Lua text.

## 5. Reading text

### 5.1 Tokens carry positions

The tokenizer is the one place that knows where things are in the text. Every token records its
position, as `source:line:column`, and every stage after it passes positions on.

```lua
local Token = struct { text: String, at: String }

local tokenize = do(text, source_name)
    local tokens, index, line, line_start = {}, 1, 1, 1
    while index <= #text do
        local character = text:sub(index, index)
        if character == "\n" then
            line, line_start = line + 1, index + 1
            index += 1
        elseif character:match "%s" then
            index += 1
        elseif character == ";" then
            -- a comment runs to the end of its line
            index = text:find("\n", index, true) or #text + 1
        else
            local last = index
            if character ~= "(" and character ~= ")" then
                local boundary = text:find("[%s();]", index) or #text + 1
                last = boundary - 1
            end
            local at = ("%s:%d:%d"):format(source_name, line, index - line_start + 1)
            tokens[#tokens + 1] = Token { text = text:sub(index, last), .at }
            index = last + 1
        end
    end
    return tokens
end
```

### 5.2 Reading into data

A Lisp reads in two steps: tokens to *data* (atoms and lists), then data to syntax (§6). The
first step knows only brackets; the second knows the language. Keeping them apart means the
reader never changes when the language does. The data are a family too, so the parser can ask
`Datum.is`.

```lua
local Datum = family "datum"
local Atom = struct { text: String, at: String }
local List = struct { items: Table, at: String }
Datum { Atom, List }

-- a problem at a position: every stage that stops reports this way
local fail = |at, message| -> error(at .. ": " .. message, 0)

local read = do(tokens)
    local position = 1
    local read_datum
    read_datum = do()
        local token = tokens[position]
        position += 1
        if token.text == ")" then fail(token.at, "this ) closes nothing") end
        if token.text ~= "(" then return Atom { text = token.text, at = token.at } end
        local items = {}
        while true do
            local next_token = tokens[position]
            if next_token == nil then fail(token.at, "this ( is never closed") end
            if next_token.text == ")" then break end
            items[#items + 1] = read_datum()
        end
        position += 1
        return List { .items, at = token.at }
    end
    local forms = {}
    while tokens[position] do forms[#forms + 1] = read_datum() end
    return forms
end
```

The error names the opening bracket's position, not the end of the text: the place to fix is
where the list began.

## 6. The syntax tree, and parsing

### 6.1 The family

```lua
local Expression = family "expression"
local Expressions = list_of Expression
local Literal = struct { value: Number, at: String }
local Variable = struct { name: String, at: String }
local Primitive = struct { operator: String, arguments: Expressions, at: String }
local Conditional = struct
    condition: Expression
    when_true: Expression
    when_false: Expression
    at: String
end
local Let = struct { name: String, value: Expression, body: Expression, at: String }
local Lambda = struct { parameters: Table, body: Expression, at: String }
local Application = struct { callee: Expression, arguments: Expressions, at: String }
Expression { Literal, Variable, Primitive, Conditional, Let, Lambda, Application }

-- the operators the language knows, and what each means
local operators = {
    ["+"] = |left, right| -> left + right,
    ["-"] = |left, right| -> left - right,
    ["*"] = |left, right| -> left * right,
    ["<"] = |left, right| -> left < right,
    ["="] = |left, right| -> left == right,
}
```

The kinds are named for what they are, in full: an `if` is a `Conditional` with a `condition`, a
`when_true` and a `when_false`; a call is an `Application` of a `callee` to `arguments`. Every
handler of every pass below reads with these words.

Two design choices are visible here. `let` desugars to nested `Let` nodes of one binding each, so
the rest of the compiler meets one form instead of two. And `operators` is a table of meanings
shared by the parser (which operators exist), the interpreter (what they do) and the optimizer
(what they compute when the operands are known): one definition, three uses.

### 6.2 Parsing data into the family

Parsing is a function over data, not a pass: what a list means depends on its first element, not
on its kind. Each form checks its own shape and fails at its own position.

```lua
local parse
parse = do(datum)
    if Datum.is(datum, Atom) then
        local number = tonumber datum.text
        if number then return Literal { value = number, at = datum.at } end
        return Variable { name = datum.text, at = datum.at }
    end
    local items = datum.items
    if #items == 0 then fail(datum.at, "() is not an expression") end
    local head = Datum.is(items[1], Atom) and items[1].text
    if head == "if" then
        if #items ~= 4 then
            fail(datum.at, "(if condition when-true when-false) takes three parts")
        end
        return Conditional with
            condition = parse items[2]
            when_true = parse items[3]
            when_false = parse items[4]
            at = datum.at
        end
    end
    if head == "let" then
        if #items ~= 3 or not Datum.is(items[2], List) then fail(datum.at,
                "a let is (let ((name value) …) body)") end
        local body = parse items[3]
        local bindings = items[2].items
        for index = #bindings, 1, -1 do
            local binding = bindings[index]
            if not Datum.is(binding, List) or #binding.items ~= 2 or not Datum.is(binding.items[1],
                Atom) then
                fail(binding.at, "a binding is (name value)")
            end
            body = Let with
                name = binding.items[1].text
                value = parse binding.items[2]
                .body
                at = binding.at
            end
        end
        return body
    end
    if head == "lambda" then
        if #items ~= 3 or not Datum.is(items[2], List) then fail(datum.at,
                "a lambda is (lambda (name …) body)") end
        local parameters = {}
        for index, parameter in ipairs items[2].items do
            if not Datum.is(parameter, Atom) then fail(parameter.at, "a parameter is a name") end
            parameters[index] = parameter.text
        end
        return Lambda { .parameters, body = parse items[3], at = datum.at }
    end
    local arguments = {}
    for index = 2, #items do arguments[#arguments + 1] = parse items[index] end
    if operators[head] then return Primitive { operator = head, .arguments, at = datum.at } end
    return Application { callee = parse items[1], .arguments, at = datum.at }
end

-- is the datum this symbol?
local is_symbol = |datum, text| -> Datum.is(datum, Atom) and datum.text == text

-- a program: (define name value) forms, then the expression they are for
local parse_program = do(forms)
    if #forms == 0 then error("parse: an empty program", 0) end
    local body = parse forms[#forms]
    for index = #forms - 1, 1, -1 do
        local form = forms[index]
        local items = Datum.is(form, List) and form.items
        local defines = items and #items == 3 and is_symbol(items[1], "define")
        if not defines then
            fail(form.at, "only the last form of a program may be an expression")
        end
        body = Let { name = items[2].text, value = parse items[3], .body, at = form.at }
    end
    return body
end
```

Parsing reports the **first** problem and stops: a malformed form says nothing reliable about
what follows it. Checking (§7) can do better.

### 6.3 Printing the tree back

The first pass to write over a new family is the one that prints it. It is how every other
stage is debugged, and it gives the tree a round-trip test: printing a parsed program and reading
the print must give the same tree.

```lua
local Writing = define
    Literal = |node, recurse| -> tostring node.value
    Variable = |node, recurse| -> node.name
    Primitive = do(node, recurse)
        local left, right = recurse node.arguments[1], recurse node.arguments[2]
        return ("(%s %s %s)"):format(node.operator, left, right)
    end
    Conditional = do(node, recurse)
        local condition = recurse node.condition
        local when_true, when_false = recurse node.when_true, recurse node.when_false
        return ("(if %s %s %s)"):format(condition, when_true, when_false)
    end
    Let = |node, recurse| -> ("(let ((%s %s)) %s)"):format(node.name,
        recurse node.value, recurse node.body)
    Lambda = do(node, recurse)
        local parameters = table.concat(node.parameters, " ")
        return ("(lambda (%s) %s)"):format(parameters, recurse node.body)
    end
    Application = do(node, recurse)
        local parts = { recurse node.callee }
        for _, argument in ipairs node.arguments do parts[#parts + 1] = recurse argument end
        return "(" .. table.concat(parts, " ") .. ")"
    end
end
local write_expression = Expression.pass "write an expression as text" with ..Writing end

local parsed = parse_program(read(tokenize("(let ((x 2)) (* x (+ x 1)))", "round-trip")))
local written = write_expression parsed
assert(written == "(let ((x 2)) (* x (+ x 1)))")
assert(write_expression(parse_program(read(tokenize(written, "written again")))) == written)
```

## 7. Checking

### 7.1 Scopes that fall back

A checker walks the tree carrying the names in scope. Entering a `let` or a `lambda` makes an
inner scope; leaving it must restore the outer one. Copying the whole scope at each entry works
but costs a copy per binding. A scope that **falls back** to the one around it costs nothing:
`meta { index = outer }` makes a metatable whose `__index` is the outer scope, so a name missing
from the inner table is looked up outside.

```lua
-- a scope whose missing names are those of the scope around it
local within = outer -> meta { index = outer } {}
local scope_with = do(outer, names)
    local inner = within outer
    for _, name in ipairs names do inner[name] = true end
    return inner
end

local outer_scope = scope_with({}, { "x" })
local inner_scope = scope_with(outer_scope, { "y" })
assert(inner_scope.x and inner_scope.y and not outer_scope.y)
```

The same scopes serve the interpreter (§8), holding values instead of `true`.

### 7.2 Collecting problems

A checker should report **every** problem it can, not the first: a programmer fixing a program
wants the whole list. So the checker acts on a shared list of problems instead of raising an
error, and the compiler stops after checking if the list is not empty. The two pieces of state
play different roles and travel separately: `scope` is inherited (each handler may extend it, and
the extension is seen only below it), `problems` is accumulated (every handler appends to the
one list).

```lua
local report = do(problems, at, message)
    problems[#problems + 1] = at .. ": " .. message
end

local Checking = define
    Literal = do(node, recurse, scope, problems)
        return
    end
    Variable = do(node, recurse, scope, problems)
        if not scope[node.name] then report(problems,
                node.at, node.name .. " is not defined here") end
    end
    Primitive = do(node, recurse, scope, problems)
        if #node.arguments ~= 2 then
            local message = ("(%s) takes two arguments, got %d"):format(node.operator,
                #node.arguments)
            report(problems, node.at, message)
        end
        for _, argument in ipairs node.arguments do recurse(argument, scope, problems) end
    end
    Conditional = do(node, recurse, scope, problems)
        recurse(node.condition, scope, problems)
        recurse(node.when_true, scope, problems)
        recurse(node.when_false, scope, problems)
    end
    Let = do(node, recurse, scope, problems)
        local inner = scope_with(scope, { node.name })
        recurse(node.value, inner, problems)
        recurse(node.body, inner, problems)
    end
    Lambda = do(node, recurse, scope, problems)
        recurse(node.body, scope_with(scope, node.parameters), problems)
    end
    Application = do(node, recurse, scope, problems)
        recurse(node.callee, scope, problems)
        for _, argument in ipairs node.arguments do recurse(argument, scope, problems) end
    end
end
local check = Expression.pass "check names and arity" with ..Checking end

local problems = {}
check(parse_program(read(tokenize("(+ x (* 1))", "two problems"))), {}, problems)
assert(#problems == 2)
assert(problems[1] == "two problems:1:4: x is not defined here")
assert(problems[2] == "two problems:1:6: (*) takes two arguments, got 1")
```

The problems arrive in the order of the walk, which is the order of the text. Both were found in
one run: the unknown `x`, and the `(*)` with one argument. A checker that stopped at the first
would have made the programmer run it twice.

A checker is also where a language's static rules live as it grows: types, mutability, effects.
Each is a pass of its own, or richer state in this one; none of them needs the others to change.

## 8. A reference interpreter

Before compiling anything, write an interpreter: a pass that answers the value of each node. It
is short, obviously right, and it becomes the **reference** every compiled program is compared
with (§12). A compiler without one can only be tested against expected outputs written by hand.

```lua
local Evaluation = define
    Literal = |node, recurse, environment| -> node.value
    Variable = |node, recurse, environment| -> environment[node.name]
    Primitive = do(node, recurse, environment)
        local left = recurse(node.arguments[1], environment)
        local right = recurse(node.arguments[2], environment)
        return operators[node.operator](left, right)
    end
    Conditional = do(node, recurse, environment)
        if recurse(node.condition, environment) then
            return recurse(node.when_true, environment)
        end
        return recurse(node.when_false, environment)
    end
    Let = do(node, recurse, environment)
        local inner = within environment
        inner[node.name] = recurse(node.value, inner)
        return recurse(node.body, inner)
    end
    Lambda = do(node, recurse, environment) = do(..arguments)
        local inner = within environment
        for index, name in ipairs node.parameters do inner[name] = arguments[index] end
        return recurse(node.body, inner)
    end
    Application = do(node, recurse, environment)
        local arguments = {}
        for index, argument in ipairs node.arguments do
            arguments[index] = recurse(argument, environment)
        end
        return recurse(node.callee, environment)(unpack arguments)
    end
end
local evaluate = Expression.pass "evaluate an expression" with ..Evaluation end

local factorial = "(define fact (lambda (n) (if (< n 2) 1 (* n (fact (- n 1)))))) (fact 5)"
assert(evaluate(parse_program(read(tokenize(factorial, "factorial"))), {}) == 120)
```

`Let` binds the name in the inner environment *before* evaluating the value into it, so a
`lambda` bound by a `let` sees itself: that is the whole of recursion here. The interpreter
decides the semantics; the compiler's job is to agree with it, faster.

## 9. Lowering to an intermediate form

### 9.1 Why a second family

The syntax tree is the language as written: nested, with names. A back end wants the program as
it runs: a sequence of simple steps, with every intermediate value named. The **intermediate
form** is a second family, chosen so that optimizations and emission are easy:

* **registers**: every value has a name, written where it is computed;
* **flat code**: each function is one list of instructions, with labels and jumps for control;
* **closures** hold the code of the function they create.

```lua
local Instruction = family "instruction"
local Constant = struct { register: String, value: Any }
local Copy = struct { register: String, source: String }
local Operation = struct { register: String, operator: String, left: String, right: String }
local Call = struct { register: String, callee: String, arguments: Table }
local Label = struct { name: String }
local Jump = struct { label: String }
local JumpUnless = struct { condition: String, label: String }
local Return = struct { source: String }
local Closure = struct { register: String, parameters: Table, code: Table }
Instruction { Constant, Copy, Operation, Call, Label, Jump, JumpUnless, Return, Closure }
```

Write down the intermediate form's **invariants**, because the optimizer will rely on them and a
later change to lowering can break them silently. Here: jumps only go forward (there are no
loops, only recursion through calls); a label is reached by a jump or by falling through; a
register named by a `let` or a conditional may be written in more than one place, every other
register exactly once.

### 9.2 The lowering state

Lowering is a pass over the *syntax* family that writes *instructions*. Its state holds the code
being written, the register each name stands for, and a supply of fresh names. A handler answers
the register holding its node's value.

Fresh names are made from a word that says what the register holds, so the emitted Lua reads:
`value_3` is an intermediate value, `fact_7` the register of the name `fact`, `otherwise_4` a
label. A source name may hold characters Lua does not allow in a name, so they are replaced.

```lua
local fresh_names = do()
    local count = 0
    return do(word)
        count += 1
        return word:gsub("[^%w_]", "_") .. "_" .. count
    end
end

local write_instruction = do(lowering, instruction)
    lowering.code[#lowering.code + 1] = instruction
end
```

The lowering state groups three pieces with three roles, because they are the working
circumstances of one activity: `code` is produced (the instructions of the function being
lowered), `registers` is inherited (the register each name in scope stands for), and `fresh` is a
capability shared by every function, so names never collide across them. The two boundaries of
§4.5 change it differently, each with a spread of the outer state: entering a `Let` keeps `code`
and extends `registers` with one name; entering a `Lambda` starts a new `code`, the function's
own, and extends `registers` with its parameters.

### 9.3 The lowering pass

```lua
local Lowering = define
    Literal = do(node, recurse, lowering)
        local register = lowering.fresh "value"
        write_instruction(lowering, Constant { .register, value = node.value })
        return register
    end
    Variable = |node, recurse, lowering| -> lowering.registers[node.name]
    Primitive = do(node, recurse, lowering)
        local left = recurse(node.arguments[1], lowering)
        local right = recurse(node.arguments[2], lowering)
        local register = lowering.fresh "value"
        local operator = node.operator
        write_instruction(lowering, Operation { .register, .operator, .left, .right })
        return register
    end
    Conditional = do(node, recurse, lowering)
        local condition = recurse(node.condition, lowering)
        local otherwise = lowering.fresh "otherwise"
        local done = lowering.fresh "done"
        local register = lowering.fresh "value"
        write_instruction(lowering, JumpUnless { .condition, label = otherwise })
        write_instruction(lowering,
            Copy { .register, source = recurse(node.when_true, lowering) })
        write_instruction(lowering, Jump { label = done })
        write_instruction(lowering, Label { name = otherwise })
        write_instruction(lowering,
            Copy { .register, source = recurse(node.when_false, lowering) })
        write_instruction(lowering, Label { name = done })
        return register
    end
    Let = do(node, recurse, lowering)
        local register = lowering.fresh node.name
        local inner = { ..lowering, registers = within lowering.registers }
        inner.registers[node.name] = register
        write_instruction(lowering, Copy { .register, source = recurse(node.value, inner) })
        return recurse(node.body, inner)
    end
    Lambda = do(node, recurse, lowering)
        local inner = { ..lowering, code = {}, registers = within lowering.registers }
        local parameters = {}
        for index, name in ipairs node.parameters do
            parameters[index] = lowering.fresh name
            inner.registers[name] = parameters[index]
        end
        write_instruction(inner, Return { source = recurse(node.body, inner) })
        local register = lowering.fresh "lambda"
        write_instruction(lowering, Closure { .register, .parameters, code = inner.code })
        return register
    end
    Application = do(node, recurse, lowering)
        local callee = recurse(node.callee, lowering)
        local arguments = {}
        for index,
        argument in ipairs node.arguments do arguments[index] = recurse(argument, lowering) end
        local register = lowering.fresh "value"
        write_instruction(lowering, Call { .register, .callee, .arguments })
        return register
    end
end
local lower = Expression.pass "lower an expression to instructions" with ..Lowering end

-- a whole program is the body of a function with no parameters
local lower_program = do(tree)
    local lowering = { code = {}, registers = {}, fresh = fresh_names() }
    write_instruction(lowering, Return { source = lower(tree, lowering) })
    return lowering.code
end
```

Read `Conditional` as the template for control flow: evaluate the condition, jump over the branch
that does not run, copy each branch's value into one register, and meet at a label. Every
structured construct lowers to this pattern of labels and jumps.

`Let` writes its register *after* lowering the value, but the value's code already refers to the
register (a recursive call does): the emitted Lua declares every register at the top of its
function (§11), so a closure can capture a register before it is written.

## 10. Optimizing

### 10.1 Rewrites and walks

An optimization is a pass over the instruction family. Two drivers cover them all:

* a **rewrite** answers each instruction with the list of instructions that replace it (none to
  delete it, one to keep or change it, several to expand it);
* a **walk** visits each instruction for its effect on shared state (counting, collecting).

```lua
local rewrite = do(pass, code, state)
    local written = {}
    local work = { ..state, .written }
    for _, instruction in ipairs code do
        for _, replacement in ipairs(pass(instruction, work)) do
            written[#written + 1] = replacement
        end
    end
    return written
end
local walk = do(pass, code, state)
    for _, instruction in ipairs code do pass(instruction, state) end
end
```

A rewrite owns the list it writes: it creates `written`, and hands its handlers a `work` table,
a spread of the caller's state with `written` added, so a handler can look one instruction back
(§10.4 uses it). The copy is shallow, so what the caller's state shares (the read counts, the
labels) stays shared. Writing `state.written = written` instead would plant the list in the
caller's table, and a nested rewrite over a closure's code, given the same state, would replace it
in the middle of the outer rewrite: the outer handlers would then look back into the inner
function's code. Each rewrite owning its `work` makes that impossible, which is the rule of §4.5:
an activity owns the temporary state it creates.

### 10.2 The identity, and passes that change only what they name

Every rewrite starts from the identity: each instruction stands for itself. Spread in, it lets an
optimization name only the kinds it changes, and the family still checks that the result covers
every kind.

```lua
local itself = node -> { node }
local Unchanged = define
    Constant = itself
    Copy = itself
    Operation = itself
    Call = itself
    Label = itself
    Jump = itself
    JumpUnless = itself
    Return = itself
    Closure = itself
end
local nothing = do() end
```

### 10.3 Folding what is known

Along straight-line code, a register written by a `Constant` holds a known value, and an
operation on known values can be computed now. Facts are boxed (`{ value }`) because a known
value may be `false`. The facts are **evolving** state: each instruction updates them for the
ones after it, so the rewrite must visit the code in order. Their boundaries come from the
invariants of §9.1: at a **label**, control may arrive from elsewhere, so every fact is
forgotten; a function's code starts knowing nothing, so a closure's code is folded with facts of
its own. A condition that is known decides its jump: a true condition never jumps, a false one
always does.

```lua
local Folding = define ..Unchanged
    Constant = do(node, recurse, facts)
        facts.known[node.register] = { node.value }
        return { node }
    end
    Copy = do(node, recurse, facts)
        local known = facts.known[node.source]
        facts.known[node.register] = known
        if known then return { Constant { register = node.register, value = known[1] } } end
        return { node }
    end
    Operation = do(node, recurse, facts)
        local left, right = facts.known[node.left], facts.known[node.right]
        facts.known[node.register] = nil
        if left and right then
            local value = operators[node.operator](left[1], right[1])
            facts.known[node.register] = { value }
            return { Constant { register = node.register, .value } }
        end
        return { node }
    end
    Call = do(node, recurse, facts)
        facts.known[node.register] = nil
        return { node }
    end
    Label = do(node, recurse, facts)
        facts.known = {}
        return { node }
    end
    JumpUnless = do(node, recurse, facts)
        local condition = facts.known[node.condition]
        if condition == nil then return { node } end
        if condition[1] then return {} end
        return { Jump { label = node.label } }
    end
    Closure = do(node, recurse, facts)
        facts.known[node.register] = nil
        local code = rewrite(recurse, node.code, { known = {} })
        return { Closure { register = node.register, parameters = node.parameters, .code } }
    end
end
local fold = Instruction.pass "fold what is known" with ..Folding end
```

If the language grows loops, jumps go backwards and "forget at labels" is no longer enough: a
fact known before a loop may be changed inside it. Then folding needs a dataflow analysis over
the function's control-flow graph. The invariant written down in §9.1 is what tells you this
optimization has to change.

### 10.4 Removing what cannot run

After folding, some jumps always happen and some labels are never jumped to. Code between an
unconditional jump (or a return) and the next label that is still jumped to can never run.
Finding those labels is a walk that accumulates them; removing the dead code is a rewrite that
carries an evolving "dead" flag along the code, set by a jump or a return and cleared by a label
still jumped to. A jump to the label right after it is no jump, which the rewrite removes by
looking back at the code it has written: `written` is produced by the rewrite, and only the
rewrite's own handlers see it.

```lua
local JumpedTo = define
    Constant = nothing
    Copy = nothing
    Operation = nothing
    Call = nothing
    Label = nothing
    Return = nothing
    Jump = do(node, recurse, labels)
        labels[node.label] = true
    end
    JumpUnless = do(node, recurse, labels)
        labels[node.label] = true
    end
    Closure = do(node, recurse, labels)
        walk(recurse, node.code, labels)
    end
end
local find_labels = Instruction.pass "find the labels still jumped to" with ..JumpedTo end

local unless_dead = do(node, recurse, flow)
    if flow.dead then return {} end
    return { node }
end
local ending_the_flow = do(node, recurse, flow)
    if flow.dead then return {} end
    flow.dead = true
    return { node }
end
local Reaching = define
    Constant = unless_dead
    Copy = unless_dead
    Operation = unless_dead
    Call = unless_dead
    JumpUnless = unless_dead
    Jump = ending_the_flow
    Return = ending_the_flow
    Label = do(node, recurse, flow)
        if not flow.labels[node.name] then return {} end
        local previous = flow.written[#flow.written]
        if previous and Instruction.is(previous, Jump) and previous.label == node.name then
            flow.written[#flow.written] = nil
        end
        flow.dead = false
        return { node }
    end
    Closure = do(node, recurse, flow)
        if flow.dead then return {} end
        local code = rewrite(recurse, node.code, { labels = flow.labels })
        return { Closure { register = node.register, parameters = node.parameters, .code } }
    end
end
local reach = Instruction.pass "drop what cannot run" with ..Reaching end
```

### 10.5 Removing what nobody reads

An instruction with no effect whose register is never read can go. Counting reads is a walk;
removing is a rewrite over the identity that names the pure kinds. A call may have effects, so it
stays. Reads inside a closure count, since the closure may read a register of the function around
it.

```lua
local read_once_more = do(register, counts)
    counts.reads[register] = (counts.reads[register] or 0) + 1
end
local Reads = define
    Constant = nothing
    Label = nothing
    Jump = nothing
    Copy = do(node, recurse, counts)
        read_once_more(node.source, counts)
    end
    Operation = do(node, recurse, counts)
        read_once_more(node.left, counts)
        read_once_more(node.right, counts)
    end
    Call = do(node, recurse, counts)
        read_once_more(node.callee, counts)
        for _, argument in ipairs node.arguments do read_once_more(argument, counts) end
    end
    JumpUnless = do(node, recurse, counts)
        read_once_more(node.condition, counts)
    end
    Return = do(node, recurse, counts)
        read_once_more(node.source, counts)
    end
    Closure = do(node, recurse, counts)
        walk(recurse, node.code, counts)
    end
end
local count_reads = Instruction.pass "count the reads of each register" with ..Reads end

local never_read = |instruction, counts| -> (counts.reads[instruction.register] or 0) == 0
local unless_never_read = do(node, recurse, counts)
    if never_read(node, counts) then return {} end
    return { node }
end
local Sweeping = define ..Unchanged
    Constant = unless_never_read
    Copy = unless_never_read
    Operation = unless_never_read
    Closure = do(node, recurse, counts)
        if never_read(node, counts) then return {} end
        local code = rewrite(recurse, node.code, counts)
        return { Closure { register = node.register, parameters = node.parameters, .code } }
    end
end
local sweep = Instruction.pass "sweep what nobody reads" with ..Sweeping end
```

### 10.6 Running until nothing changes

One optimization exposes another: folding a condition makes a branch dead, removing it makes a
register unread, removing that makes another unread. The optimizer runs the passes in order until
a round leaves the code unchanged, with a bound so a mistake cannot loop forever.

"Unchanged" has to mean the representation, not a measure of it. Stopping when the instruction
count stops falling is tempting, but folding can turn a `Copy` into a `Constant` without changing
the count, and that change can enable more work in the next round. Comparing the code itself
(every instruction's kind and fields, closures' code included) is the real fixed-point test.

```lua
-- the same representation: the same kinds, with the same fields, all the way down
local same
same = do(left, right)
    if type left ~= "table" or type right ~= "table" then return left == right end
    if getmetatable left ~= getmetatable right then return false end
    for key, value in pairs left do
        if not same(value, right[key]) then return false end
    end
    for key in pairs right do
        if left[key] == nil then return false end
    end
    return true
end

local instruction_count
instruction_count = do(code)
    local total = 0
    for _, instruction in ipairs code do
        total += 1
        if Instruction.is(instruction, Closure) then total += instruction_count instruction.code end
    end
    return total
end

local optimize = do(code)
    for _ = 1, 8 do
        local before = code
        code = rewrite(fold, code, { known = {} })
        local labels = {}
        walk(find_labels, code, labels)
        code = rewrite(reach, code, { .labels })
        local counts = { reads = {} }
        walk(count_reads, code, counts)
        code = rewrite(sweep, code, counts)
        if same(code, before) then break end
    end
    return code
end
```

The bound makes this a bounded fixed-point loop: if eight rounds are not enough, the code is
still correct, only less optimized. A test (§11) checks that the optimizer's output is a fixed
point: optimizing it again changes nothing.


## 11. Emitting Lua

Emission is a pass over the instructions that answers text. Three facts about Lua decide its
shape:

* **`goto` may not jump into the scope of a local.** So each function declares every register it
  writes at its top, before any label, and the instructions only assign.
* **Lua's truthiness is the language's**: only `false` and `nil` are false. The Lisp here adopts
  it, so a conditional needs no translation. A language with other rules (0 is false, say) must
  emit a test that says so.
* **Operators differ in spelling**: the language's `=` is Lua's `==`.

```lua
local function_body = do(write, code, indent)
    local registers, declared = {}, {}
    for _, instruction in ipairs code do
        local register = instruction.register
        if register and not declared[register] then
            declared[register] = true
            registers[#registers + 1] = register
        end
    end
    local lines = {}
    if #registers > 0 then lines[1] = indent .. "local " .. table.concat(registers, ", ") end
    for _, instruction in ipairs code do lines[#lines + 1] = write(instruction, indent) end
    return table.concat(lines, "\n")
end

local lua_spelling = {["="] = "==" }
local LuaText = define
    Constant = |node, recurse, indent| -> indent .. node.register .. " = " .. tostring node.value
    Copy = |node, recurse, indent| -> indent .. node.register .. " = " .. node.source
    Operation = do(node, recurse, indent)
        local operator = lua_spelling[node.operator] or node.operator
        local expression = node.left .. " " .. operator .. " " .. node.right
        return indent .. node.register .. " = " .. expression
    end
    Call = do(node, recurse, indent)
        local arguments = table.concat(node.arguments, ", ")
        return indent .. node.register .. " = " .. node.callee .. "(" .. arguments .. ")"
    end
    Label = |node, recurse, indent| -> indent .. "::" .. node.name .. "::"
    Jump = |node, recurse, indent| -> indent .. "goto " .. node.label
    JumpUnless = |node, recurse, indent| -> indent .. "if not " .. node.condition .. " then goto " .. node.label .. " end"
    Return = |node, recurse, indent| -> indent .. "return " .. node.source
    Closure = do(node, recurse, indent)
        local header = ("%s%s = function(%s)"):format(indent,
            node.register, table.concat(node.parameters, ", "))
        local body = function_body(recurse, node.code, indent .. "  ")
        return header .. "\n" .. body .. "\n" .. indent .. "end"
    end
end
local write_lua = Instruction.pass "write an instruction as Lua" with ..LuaText end
local emit_lua = code -> function_body(write_lua, code, "")
```

The whole compiler is the stages in order. It answers every representation, not only the last,
so a test or a debugging session can look at any of them:

```lua
local compile = do(text, source_name)
    local tree = parse_program(read(tokenize(text, source_name)))
    local problems_found = {}
    check(tree, {}, problems_found)
    if #problems_found > 0 then error(table.concat(problems_found, "\n"), 0) end
    local instructions = lower_program tree
    local optimized = optimize instructions
    return { .tree, .instructions, .optimized, lua = emit_lua optimized }
end

local run = do(text, source_name)
    local compiled = compile(text, source_name)
    return assert(load(compiled.lua, "=" .. source_name))(), compiled
end

local folded = compile("(if (< 1 2) (+ 10 (* 2 3)) 99)", "folded")
assert(instruction_count folded.instructions == 16 and instruction_count folded.optimized == 2)
assert(folded.lua == "local value_6\nvalue_6 = 16\nreturn value_6")
assert(same(optimize folded.optimized, folded.optimized))
```

`load` takes a chunk name: give each compiled program its own (`"=" .. source_name`), so a Lua
error in compiled code names the program it came from. The emitted text is the place to look
when a compiled program misbehaves; print it. With registers named for what they hold, it reads:

```lua
local factorial_of_ten = "(define fact (lambda (n) (if (< n 2) 1 (* n (fact (- n 1)))))) (fact 10)"
local recursion = compile(factorial_of_ten, "recursion")
assert(recursion.lua:find("fact_1 = lambda_", 1, true))
assert(recursion.lua:find "value_%d+ = fact_1%(")
```

## 12. Testing a compiler

### 12.1 Agree with the interpreter

The strongest test is **differential**: run each program both ways and require the same answer.
Every new program in the corpus tests the whole pipeline, and a disagreement points at a stage:
if the unoptimized code agrees and the optimized code does not, the optimizer is wrong.

```lua
local corpus = {
    { name = "arithmetic", source = "(+ 1 (* 2 3))", expected = 7 },
    { name = "a known branch", source = "(if (< 1 2) (+ 10 (* 2 3)) 99)", expected = 16 },
    { name = "an unknown branch",
        source = "(define f (lambda (x) (if (< x 0) (- 0 x) x))) (f (- 0 4))", expected = 4 },
    { name = "a function",
        source = "(define square (lambda (x) (* x x))) (square (+ 3 4))", expected = 49 },
    { name = "recursion",
        source = "(define fact (lambda (n) (if (< n 2) 1 (* n (fact (- n 1)))))) (fact 10)",
        expected = 3628800 },
    { name = "a closure",
        source = "(define adder (lambda (a) (lambda (b) (+ a b)))) ((adder 3) 4)", expected = 7 },
    { name = "let", source = "(let ((x 2) (y (+ x 1))) (* x y))", expected = 6 },
    { name = "equality", source = "(if (= (+ 1 1) 2) 1 0)", expected = 1 },
}
for _, program in ipairs corpus do
    local compiled_result, compiled = run(program.source, program.name)
    local unoptimized_result = assert(load(emit_lua compiled.instructions, "=" .. program.name))()
    local evaluated_result = evaluate(compiled.tree, {})
    assert(compiled_result == program.expected, program.name)
    assert(unoptimized_result == program.expected and evaluated_result == program.expected,
        program.name)
end
```

### 12.2 Refusals are part of the language

What a compiler refuses, and how it says so, is as much its behavior as what it accepts. Test the
messages, positions included:

```lua
local refusal = do(text)
    local accepted, message = pcall(compile, text, "refusal")
    assert(not accepted, text .. " was accepted")
    return message
end
assert(refusal "(+ 1 2" == "refusal:1:1: this ( is never closed")
assert(refusal "(if 1 2)" == "refusal:1:1: (if condition when-true when-false) takes three parts")
assert(refusal "(let ((x)) x)" == "refusal:1:7: a binding is (name value)")
assert(refusal "(f 1)" == "refusal:1:2: f is not defined here")
assert(refusal "1 2" == "refusal:1:1: only the last form of a program may be an expression")
```

### 12.3 Other tests worth having

* **Round trips.** Writing a tree as text and reading it back gives the same tree (§6.3).
* **Representations at each stage.** For a few small programs, compare the instructions before
  and after optimizing with what you expect; they are the tests that keep an optimization from
  silently stopping (the `16 -> 2` assertion in §11 is one).
* **Pass completeness.** A family checks every pass when it is made, so a new kind is caught by
  simply loading the compiler. Load it in the tests.
* **State ownership and lifetime.** Repeat and nest activities: independent runs must not change
  each other's results. For composed stateful vocabularies, test which captures are deliberately
  shared and which a factory must create afresh (§4.6).
* **Examples with their output.** A file of programs whose expected output is a comment at the
  end, run by the test suite, documents and tests at once (Mua's `examples/` work this way).

## Part III: judgment

## 13. Names

In Mua everything is vocabulary, and a compiler has more of it than most programs: kinds, fields,
passes, states. Name all of it in full words (the design guide's §13 is the rule):

* **Kinds and fields** say what they are: `Conditional { condition, when_true, when_false }`, not
  `If { test, yes, no }`; `register`, not `dst`; `Literal`, not `Num`.
* **A handler** always spells the contract in the same words, `node recurse` and then the state
  by its role: `Let = do(node, recurse, lowering)`. Then `recurse(node.body, inner)` reads the same in
  every pass, and the kind is named once, by the entry (`Let =`).
* **A pass** is named for what it does where it is made and called: `check`, `evaluate`, `lower`,
  `fold`.
* **State** is named for what it holds: `scope` and `problems` in the checker, `environment` in
  the interpreter, `lowering`, `facts`, `flow`, `counts`. A reader never has to look up what a
  `ctx` holds.
* **Derived state** is named for its relation to what it came from: `inner` for the state of
  nested work, `work` for the state an activity makes for its own handlers. A function that
  crosses a boundary is named for the boundary: `within` makes a scope inside another.
* **Generated names** that people read are words too: `fact_1` for the register of `fact`,
  `value_6` for an intermediate value, `otherwise_4` for a label.

Mua is concise enough that full names cost nothing; a shorthand saves its writer a few
keystrokes and costs every reader a lookup.

## 14. Performance

* **Dispatch is cheap.** A pass finds a handler by the node's metatable: one table lookup, no
  string comparison.
* **Contracts cost.** Each struct construction checks its fields, and a `list_of` checker walks
  its list. For a compiler's own trees this is usually invisible next to the work; where it is
  not, the translator's `contracts = false` removes the checks, and the program is otherwise the
  same. Keep contracts on in tests.
* **Spreads copy.** `{ ..lowering, code = {} }` copies the state; it is meant for entering a scope
  or a function, not for every node. Scopes that fall back (§7.1) cost nothing to enter.
* **Vocabulary factories allocate.** Instantiating handlers creates closures, and constructing
  a pass checks its coverage. Usually build it once per activity (§4.6), rather than once per node.
  Reusing a stateless pass with explicit state avoids that repeated setup; measure before
  preferring either arrangement for speed.
* **The emitted code is ordinary Lua.** Registers become locals; LuaJIT compiles them well.
  Locals are limited to 200 per function, so a back end for large functions must reuse
  registers (allocate them by liveness) instead of declaring one per value.
* **Measure the compiler on large inputs** before optimizing it; the stages above are linear in
  the program except the fixed-point loop, which is bounded.

## 15. Open and closed sets

| You have | Use | Because |
|---|---|---|
| a fixed set of kinds, many operations | `family` and passes | each pass is checked to cover every kind |
| a fixed set of alternatives carrying one value each | `oneof` and a match | a match is checked exhaustive at every call |
| an open set of kinds, each bringing its own behavior | `meta` per kind (`examples/variants.mua`) | a new kind needs no change elsewhere, and no check covers it |
| an open set of named codes | a vocabulary (`{ get = 1, post = 2 }`) | anyone may extend it by spread |

Compilers sit firmly in the first row: the language's kinds are fixed, and operations multiply.
Resist making a pass tolerant of unknown kinds with a default handler: the check that every kind
is handled is the reason to use a family. Where most kinds pass through unchanged, spread the
identity (§10.2): every kind is still named, by the base.

Adding a kind is then a mechanical, checked change: add the struct, add it to the family, and
load the compiler. Every pass that has not learned the kind fails, by name, until it does.

## 16. Beyond a Lisp

The Lisp reads data and then parses it because its syntax is data. Other languages differ only in
the first two stages:

* **A language with its own syntax** needs a real parser in place of `read` and `parse`: a
  tokenizer that knows the language's tokens, and a recursive-descent parser that builds the
  same kind of family. Precedence climbing handles operators. Everything from checking on is
  unchanged.
* **A language that extends Mua** need not parse at all. Mua's parser takes a host (syntax §8):
  the host gives the typed forms and other forms meaning, receives parsed nodes, and emits Lua.
  Nua is such a host: its front end is a Mua host that turns Mua's syntax tree into a
  specializing compiler's input. Write a host when your language reads like Mua; write a parser
  when it does not.
* **A language staged in Lua** can skip emission to text: a pass can answer Lua closures directly
  (the interpreter is one), and `load` is for when the generated code must be inspected, cached
  or specialized further.

Mua itself is built the way this guide describes, without families: a lexer, a parser to a tree of
tagged nodes, a scope analysis, and an emitter that writes Lua.

## 17. What this approach still lacks

Writing this compiler surfaced several primitives, and some were added to Mua because of it:
`family` itself, `checker` for named predicates, passes that carry extra arguments, and the rule
that an explicit entry settles a clash between two spreads. Others are still written by hand in
each compiler, and are candidates for a library or the runtime:

* **The identity rewrite.** `Unchanged` (§10.2) lists every kind of the family by hand. A family
  could offer it, so that a new kind needs no edit there.
* **The two drivers.** `rewrite` and `walk` (§10.1) are the same in every compiler.
* **Lists of nodes.** `list_of` (§3.3) is a checker every family wants.
* **Positions and diagnostics.** The `at` strings, `fail` and `report` are conventions. A source
  span type and a list of problems with sorting and context lines would be shared by every tool.
* **Nested patterns.** A handler can ask `Instruction.is(previous, Jump)`, but it cannot match a
  shape (an `Operation` whose left register holds a known `Constant`) in one expression.
  Optimizations written as patterns read far better than chains of tests.
* **Source maps.** A runtime error in compiled code names a line of emitted Lua, not of the
  source. Instructions could carry the source position of the node that produced them, and the
  emitted chunk a table from its lines back to them.

Some things should stay unwritten. A general context framework (a `Context` type with
inherited, accumulated and evolving slots) would hide exactly what §4.5 asks you to decide: the
roles are design questions, answered differently by each operation, and the answers are a few
lines each with what Mua already has (a closure, a spread, a fallback, a shared reference, a
driver that owns its output). A vocabulary factory can own an activity's state without a new
framework. Reusable *operations* on state are worth sharing when they recur, like `within` or
the drivers above; a framework that every pass must fit is not.

None of these is needed to write a compiler; each removes a piece of boilerplate or a class of
mistake. Add them when a second compiler wants the same thing.
