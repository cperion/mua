# Designing and writing Mua

**A guide to designing and writing programs in Mua, beside [the language](syntax.md), which owns
the rules.** It is about discovering a good program, not deriving one mechanically from a
philosophy. Mua's mechanisms inform the questions (§1); requirements, diagrams, experiments and
code help answer them. Its centre is the **activity**: bounded work with someone responsible for
setup and completion. Inside an opened context an **instruction** is a call without a receiver
(§5). The same composition, run to build a description, is a **builder** (§5.9). Design is
**structural by default**: things are grouped and composed by name, as vocabularies, and given a
nominal type when the program demands one (§3).

If a spelling here looks strange, [Reading Mua](reading-mua.md) undoes it step by step. [Writing compilers in Mua](writing-compilers.md)
applies this method to one kind of program, from text to running code.
[Component patterns](component-patterns.md) develops stateful vocabularies, inward capabilities,
outward continuations, parent wiring and activity-owned lifetimes, with runnable headless examples.

A host adds its own concerns in an addendum (Nua's covers binding times, native layouts,
ownership, concurrency and reading generated C). This guide does not know any host.

* **Part I** is a design process: questions to revisit as the design develops, with diagrams that
  help expose decisions and a small worked investigation.
* **Part II** is about writing code that reads well.
* **Part III** is house style.

The `lua` blocks below form one program, read top to bottom: `tests/guide.lua` translates and
runs them together, so a later block may use what an earlier one defined. It checks that the
examples work, not the prose's claims or the quality of the design. Diagrams use Mermaid.

## 0. Forms this guide relies on

| Form | Used for |
|---|---|
| `x -> e`, `|a, b| -> e`, `do(x) … end` | lambdas: an arrow for an expression, `do` for statements, types and opening |
| `do(x) … end`, `return do(x) … end` | a block assigned to a name, a block returned: a do lambda is a function |
| `f a b`, `f x do … end`, `f a: x … end` | juxtaposed, **curried** application: `f a b` is `f(a)(b)` |
| `define … end`, `{ … }` | a vocabulary: names bound with no layout (`define` entries `end` is a table, written without commas) |
| `{ ..base, name = v }`, `..base` in a `with` block | keyed spread: a vocabulary extended, entries overriding |
| `.name` | `name = name` in a table or `with` block |
| `do(ctx..)`, `do(..)`, `local ctx.. = e` | opening a table: its string keys become names |
| `insert n`, `note 1` inside an opened block | instructions: calls the opened context resolves |
| `endall` | closing a spine of trailing blocks |
| `struct { … }`, `oneof { … }` | a nominal record, a closed set of alternatives |
| `s { name = do(p) … end, name(p) = e }` | matching a `oneof`: one handler per alternative |
| `x: T` on a parameter, result or local | a contract, checked when the value arrives |
| `closed`, `required`, `optional` | a structural type's markers |

Application is curried, so a verb that takes several arguments is written as nested functions
(`do(document) return do(n) … end end`) or called with brackets (`insert(document, n)`); a verb
used as an instruction inside an opened block usually takes one operand, because the context
supplies its subject.

---

# Part I — Designing

## 1. The stance

Mua keeps Lua's values (tables, closures, strings) and adds forms that make composing them
pleasant. It does not add a second object system. These properties make certain practices
especially useful; they do not choose your domain model or activity boundaries for you:

| Principle | What it asks of you |
|---|---|
| **Lua values first.** A program is functions, tables and closures. | Reach for a table and a function before a type. |
| **Name structurally; commit on demand.** A vocabulary groups names and costs nothing; a `struct` or `oneof` commits an identity or a closed set. | Start with vocabularies and compose them; introduce a nominal type when something needs an identity, an invariant or a closed set of alternatives (§3.2). |
| **A block beats an option list.** A call that needs setup and completion takes a block; the callee owns both. | Find the activity (§5) before adding a parameter. |
| **Grow the vocabulary, not the language.** | Say a domain as a vocabulary of verbs (§5.8, §5.9); new syntax is a last resort. |
| **Describe, then run.** A description is data; an engine consumes it. | Keep the description the interface between its writers and its readers (§11). |
| **Check at the edges.** An annotation is a contract. | Put contracts where a value crosses from someone else's code into yours, not on every local (§3.3, §8). |
| **Outcomes are values.** What a caller must act on is returned, not thrown. | Name the alternatives (`oneof`) and match them exhaustively (§3.3). |
| **Names carry the reading.** Opening contributes names; juxtaposition drops punctuation. | Speak in instructions that read as sentences (§13). |

## 2. The process

Start with the job, then investigate the questions below. The numbered steps give a useful first
route, not independent gates. A completion rule can change ownership; an outcome can expose a
missing state. Revisit the affected question as soon as that happens, not only after testing.

```text
flowchart TD
    F[0. Frame: requirements and examples] --> M[1-4. Model the decisions]
    M --> D[Draw a revealing view]
    D --> Q{Does the scenario hold?}
    Q -- revise a decision --> M
    Q -- try it in code --> C[5. Compile a small skeleton]
    C --> V[6. Check behavior]
    V -- new evidence --> M
    V -- requirements met --> R[Keep code, contracts and rationale]
    D -. requirements unclear .-> F
```

| Step | Question | Useful working view | Ready to try in code when |
|---|---|---|---|
| 0. Frame | What is the job? | inputs, outputs, scale, failures, constraints; actor/use-case sketch | success and unacceptable outcomes have concrete examples |
| 1. Names, values and outcomes | What does the program talk about, and what must exist as a thing of its own? | vocabularies first; `struct`s and `oneof`s with example values for what a trigger demands | the vocabulary reads; each nominal type names its trigger; alternatives, payloads and caller decisions are explicit |
| 2. Activities | What bounded work happens, and what is said inside it? | sequence and activity diagrams; context vocabulary | setup, normal completion and rejection each have a responsible participant |
| 3. States | What has a lifecycle? | state diagram or state/event table | legal transitions and invalid combinations are accounted for |
| 4. Composition and edges | Who connects the parts, where does the world come in? | component/dependency diagram | effects are located and domain decisions can be tested independently |
| 5. Skeleton | Does it hold together? | one end-to-end scenario in code | it runs and exercises the important contracts, including rejection |
| 6. Verify | Does it behave as we said? | tests and contract failures | step 0's requirements are met, or the next revision is identified |

### 2.1 Draw to discover

Diagrams are working tools, not illustrations to produce after deciding everything. Choose the
view that makes the uncertain relationship visible:

| View | Question it makes concrete |
|---|---|
| use-case view | Which actor needs which result, and what lies outside the system? |
| sequence diagram | Who sets up, who calls whom, who receives the outcome, and who still owes completion? |
| activity diagram | Where does work branch, repeat, join or stop? |
| state diagram | Which events are legal now, and what state does each outcome leave? |
| structure diagram | What persists, what is temporary, and which relationships own, name or borrow? |
| component/dataflow view | Where are the effects and the boundaries? |

**A UML activity is not automatically a Mua activity.** UML shows a flow of behavior. A Mua
activity gives bounded work a setup and a completion responsibility. One flow may reveal several
composed activities; a sequence diagram often reveals their boundaries better than a single
activity box.

Walk a successful scenario and a rejected or failed one through the drawing. Label the arrows
with actual values, instructions or outcomes. An arrow called only "uses" usually hides the
decision you need to make. Keep each view focused; split an unreadable drawing by concern rather
than omitting the difficult path.

### 2.2 A worked frame: a bounded edit

**The job.** A caller asks to insert `n` units into a document with a length cap. An accepted
edit increases length, advances the cursor and records one edit. A rejected edit leaves all
three fields unchanged and reports rejection. The document persists; tentative work does not.
This is a small, in-memory operation on three counters, with no I/O.

A first proposal is to call `insert` on the document, then test its length. Drawing the
rejection path exposes the problem: the document has already changed. We could undo each write,
but that gives every new instruction another rollback obligation. Instead, revise ownership:
keep a private draft, run the instructions there, and copy it back only on acceptance. This
discovers the `try_edit` activity (§5.6), rather than assuming a transaction because
transactions are a familiar pattern.

```text
flowchart TD
    A[Request bounded edit] --> B[Copy document into private draft]
    B --> C[Run insert on draft]
    C --> D{Draft length exceeds cap?}
    D -- yes --> E[Discard draft; report rejection]
    D -- no --> F[Commit draft; report acceptance]
```

*This activity diagram is a behavior view: boxes are work, the diamond is a decision, and the
two exits are distinct completion paths. The implementation uses a body outcome to choose them.*

Then separate names from commitment (§3). The verbs the body speaks (`insert`, `move_left`) are
names: they can start as a vocabulary. The document persists across calls and the draft carries
an invariant (only acceptance may copy it back), so those are the two groupings that matter; each
nominal type in an example has a trigger, and later steps refer to it.

Revisit the other questions. The cap may be a runtime input. The body needs `commit` or `abort`
with the rejected length, while this caller needs only a boolean. There is one document owner,
so a task diagram adds nothing. The sequence diagram in §5.1 makes the participant
responsibilities explicit; §5.6 supplies the implementation; §8 returns to acceptance and
rejection tests.

### 2.3 Revisit and record

Symptoms suggest questions, not automatic diagnoses:

* **A hot path interprets configuration:** revisit what is described and what runs. Is the
  description available earlier, so an engine can be written once over data (§11)?
* **Two places want to change the same thing:** revisit ownership and activities. Which one
  persists, and which holds a temporary working copy?
* **A body repeatedly reaches around its context:** revisit the vocabulary. Is a verb missing,
  or are two purposes mixed (§5.8)?
* **A match has a "cannot happen" arm:** revisit state and outcome modeling. Is a state missing,
  or does the representation admit an invalid combination (§6)?
* **A contract fails far from where the value was made:** move the contract to the edge where
  the value crossed in.

Focus on one question while keeping assumptions about the others visible. Draft calls top-down
to discover the vocabulary, then arrange the bindings in valid lexical order (§8). Run a small
scenario before filling in every operation.

Once code exists, use it as the authority for implemented structure. Keep requirements,
completion contracts and consequential rationale alongside it: they explain what code must
preserve and why. Retain diagrams that still answer a useful question.

## 3. Step 1: names, values and outcomes

Design structurally by default: `define` everywhere, and a `struct` or `oneof` only when the
program demands one. Name things first; give a grouping a nominal type when a trigger (§3.2)
prompts it. The program discovers which groupings those are as it is built; nothing has to be
committed in advance.

### 3.1 Name first

While the design is being discovered, group things **by name**: a vocabulary built with
`define` binds names to functions, values, checkers or other vocabularies. It has no required
shape and no identity, so renaming, splitting and recombining stay cheap, and the parts show what
they are by being used:

```lua
-- vocabularies: names bound with no identity of their own
local Moves = define
    left = do(document)
        if document.cursor > 0 then document.cursor = document.cursor - 1 end
    end
    right = do(document)
        if document.cursor < document.length then document.cursor = document.cursor + 1 end
    end
end
local Edits = define
    insert = do(document) = do(n)
        document.length = document.length + n
        document.cursor = document.cursor + n
    end
end

-- capabilities compose by spread; two that both offer a name are rejected
local Editing = define
    ..Moves
    ..Edits
end
local clash = pcall(function() return define ..Edits .. Edits end end)
assert(not clash)

local document = { length = 0, cursor = 0, edits = 0 }
Editing.insert document 5
Editing.left document
assert(document.length == 5 and document.cursor == 4)
```

`define` is a table written as a block; what a definition means comes from where it sits. `with` supplies keyed entries,
and keyed spread composes (syntax §5): explicit entries override, and two spreads that offer the
same name are rejected (`spread-overlap`) rather than silently shadowing, unless the block names
that field itself, which resolves the clash by intent. A function takes a
vocabulary as a parameter and calls its members, or opens it:

```lua
-- a function that takes a vocabulary calls its members
local type_and_step_back = do(ops, document, n)
    ops.insert document n
    ops.left document
end
type_and_step_back(Editing, document, 3)
assert(document.length == 8 and document.cursor == 6)

-- opening a vocabulary brings its names into scope
local type_twice = do(document, n)
    local Editing..
    insert document n
    insert document n
end
type_twice(document, 1)
assert(document.length == 10)
```

**Vocabularies can be stateless or stateful.** `Editing` supplies reusable behavior: each call
receives the document it works on. A factory can instead return verbs that close over one
document, an accumulator or a capability. That state need not appear as fields on the
vocabulary. The builder in §5.9 does exactly this: its `bind` verb captures the current activity's
`bindings` list.

Choose the vocabulary's lifetime and what its calls share. Capture what belongs to the whole
activity; pass what varies within it, or make a fresh vocabulary at the boundary. A spread
copies function values, not their captured state: copied verbs still reach the same bindings.
Independent activities need independently owned state, usually created by a factory, rather
than a copy of an existing vocabulary.
[Writing compilers, §4.5–§4.6](writing-compilers.md#45-designing-the-state-an-operation-carries)
works through the choice, including a pass that captures its accumulator but receives its depth.

A structural type carries its defaults: its values are the default of each member, and an
instance is the type spread with overrides. No constructor, defaults table or prototype mechanism
is needed, and an instance can serve as the type of further instances:

```lua
-- a structural type carries its defaults; an instance is the type spread with overrides
local Margins = { left = 4, right = 4 }
local wide = { ..Margins, right = 12 }
local text_width = doc -> doc.length - wide.left - wide.right
assert(text_width document == 10 - 4 - 12)
```

A `define` block holds lists too: positional entries, one per line, with no commas.

```lua
-- positional entries make a list
local steps = define
    "parse"
    "check"
    "emit"
end
assert(#steps == 3 and steps[2] == "check")
```

Overrides are explicit fields, never a second spread: two spreads that offer one name are
rejected until an explicit field names it, and an explicit field wins by intent.

### 3.2 Commit on demand

**A `struct` is an identity and a closed shape, not a semantic product.** The meaning of a
grouping (what its parts are called, what they do, how they compose) lives in names, and a
vocabulary carries it without committing anything. Structural design keeps only the nominal types
the program needs, and every `struct` or `oneof` that remains marks a place where something is
really a thing of its own.

A grouping becomes a nominal type when a trigger appears, and only then. The trigger is the
reason the type exists; name it when you introduce one:

| Trigger | Why names are not enough | Introduce |
|---|---|---|
| a value must be recognized wherever it travels: checked at a boundary, matched, told from another record with the same fields | a table carries no identity | a `struct` (branded, closed, typed fields) |
| it carries an invariant: fields only certain verbs may change | a vocabulary's entries are open | a `struct` whose methods guard its fields |
| the set of alternatives is closed, and a miss must be an error | a vocabulary is open to extension | a `oneof` |
| its misuse should be reported where it is declared | a structural mistake surfaces deep inside the function that uses it | a named type: `Point has no field 'z'` |
| it is a contract with the outside | the other side needs a fixed layout | a `struct`, or an FFI type (`ffistruct`) |

Promotion is mechanical, because the structural phase found the names: value entries become
fields, word entries become methods; uses such as `span.stop` read the same.

```lua
-- promoted when it must be recognized: now it has an identity and typed fields
local Span = struct { start: Number, stop: Number }
local span = Span { start = 2, stop = 9 }
assert(span.stop - span.start == 7)
assert(not pcall(Span, { start = 2 }))  -- stop is required: the contract fails at the call
```

`define` and `with` mark the two sides of the same decision. A `define` block is names and
nothing more: structural, open to extension by spread, never given a type. A `with` block is data
that waits for a type: where the program's contract names a `struct` (a typed local, parameter or
result, or a field of another struct), the table becomes an instance there, in place and checked,
and nowhere else does it change. Write `define` while the grouping is only names; write `with`
where a type will recognize it.

```lua
local Span = struct { start: Number, stop: Number }
local width = do(span: Span): Number = span.stop - span.start
assert(width(with
    start = 2
    stop = 9
end) == 7)
```

Scenarios show which groupings meet a trigger: what must be stored, replayed, logged, undone or
tested independently of the action that produced it? Those are the program's values. A command
that a key press produces, a log records and a replay re-applies is such a value:

```lua
local Direction = oneof { left: Unit, right: Unit }
local Command = oneof { move: Direction, insert: Number, undo: Unit, quit: Unit }
```

Commands as data give replay and tests a shared input, and (§11) they give an engine something
to consume.

**Closed sets and open sets.** A `oneof` is a closed set: its alternatives are fixed where it is
declared, a match handles each one, and adding an alternative makes every match that must learn
it fail where it is written. Use it where completeness is part of the meaning: a connection's
states, an operation's outcomes, the commands an editor understands. A vocabulary of known values
is an open set: an enumeration is names for codes (`{ get = 1, post = 2 }`), and anyone may
extend it by spread, so code that meets an unknown member needs a default. Use it where extension
is expected: protocol methods, opcodes, tokens, plugin points. Ask whether someone else may
legitimately add a member: if so, keep the set open; if adding one should make every user
reconsider, close it.

Composing vocabularies structurally does not make types structural: a `struct` stays nominal and
a `with` block stays keyed and unordered. A vocabulary that describes a structure (an interface, a
capability set, a namespace) is capitalized like a type, `Editing`; one that holds data is
lowercase, `config`, `span` (§13).

### 3.3 Outcomes and failures

An outcome a caller acts on is a value that crosses a function's boundary: use a `oneof` when
alternatives carry different data or require distinct handling, and match it exhaustively. A
predicate can return a boolean; a named `oneof` makes a richer protocol explicit. Do not encode
absence as a magic value:

```lua
local Found = oneof { found: Number, missing: Unit }

local find_nonzero = do(xs): Found
    for i, x in ipairs xs do
        if x ~= 0 then return Found.found i end
    end
    return Found.missing()
end
local where = find_nonzero { 0, 0, 7 } { found = i -> i, missing = || -> -1 }
assert(where == 3)
assert(not pcall(function() return find_nonzero {} { found = i -> i } end))  -- no `missing` handler
```

**Which kind of failure is which:**

| Situation | Expressed as | Example |
|---|---|---|
| alternatives need distinct handling or payloads | a `oneof` | `missing`, `closed`, `failed(errno)` |
| an invariant is broken | an error, at the line that broke it | a contract failure, a missing handler, `error(msg, 2)` |
| the caller made a mistake | an error at the caller's line | `error(msg, 3)` from a builder's verb (§5.10) |
| the world refused | an outcome `oneof` | `failed(e)`, `timed_out` |

An error is for a broken rule; an outcome is for something the caller is expected to handle.
Never use an error to carry an ordinary alternative, and never return a magic value to avoid
naming one.

## 4. Step 2: activities

> **Entities own what persists. Activities own or borrow what is needed for a purpose. Functions
> express what happens inside.**

An activity is a design role made of ordinary parts: a function that sets up a context, runs a
body that opens it, and owns completion. **The activity is the centre of this design method.**
Look for bounded responsibilities: a working copy and its commit, a file and its close, a guarded
iteration (`each(t): k v … end`), a retry and its limit. Inside an activity you speak
**instructions**: calls written without a receiver, which the opened context resolves (§5.3).
The same construct, run to build a description, is a **builder** (§5.9). Design the activities,
and the program's shape follows.

## 5. Activities in detail

### 5.1 Finding activities

**Walk a use case; look for work that must belong together.** One use case may compose several
activities, and the same activity may serve several use cases. Ask:

1. **What persists?** Which entity or resource exists before and after this work?
2. **What must succeed together?** Which changes must be committed or discarded as a unit?
3. **What access is temporary?** Which working copy or acquired resource is valid only during
   this work?
4. **What must happen afterward?** Who commits, discards, closes, releases or reports each
   ordinary outcome?
5. **What does the body need to say?** Which instructions belong to this responsibility, rather
   than to every use of the entity?

In the bounded edit, the all-or-nothing requirement discovers a private draft (§2.2). The
activity owns copying and conditional commit; the body needs `insert`, `length` and an outcome.
Drawing the rejected path tests whether that division is complete:

```text
sequenceDiagram
    participant Caller as type_capped
    participant A as try_edit (activity)
    participant D as document (entity)
    participant W as draft (context)
    Caller->>A: bounded edit body
    A->>D: read current fields
    A->>W: setup private copy
    A->>Caller: evaluate body with draft access
    Caller->>W: insert n, read length
    alt length exceeds cap
        Caller-->>A: abort(length)
        Note over A,W: discard draft, document unchanged
        A-->>Caller: false
    else accepted
        Caller-->>A: commit
        A->>D: copy draft fields back
        A-->>Caller: true
    end
```

*Participants are responsibilities, not threads. Solid arrows are calls or reads/writes; dashed
arrows return outcomes. The `alt` frame makes both completion paths visible.*

**Put purpose-specific verbs on the context.** `draft.insert` belongs to tentative editing; basic
document operations may still belong with the document. A free activity function lives beside the
entity without collecting every use case into its methods. The division is a design
responsibility, not access control: fields remain public.

### 5.2 Kinds of activity

| Kind | Setup | Completion | Example |
|---|---|---|---|
| working copy | copy the entity into a context | commit, or conditionally discard | `edit`, `try_edit` |
| in place | open a place | nothing; writes went through | `local node.. = graph.nodes[id]` |
| scoped resource | acquire | release | `with_file` |
| accumulator | create the state | return a result from it | `counting` |
| policy | nothing, or a measurement | record, check, clamp, retry | `count_into`, `clamp_length` |
| builder | a vocabulary | return a description | `keymap`, `router` (§5.9) |

### 5.3 Enter an activity and speak its instructions

An activity hands its body a context. Opening it (`do(..)` unnamed, `do(draft..)` named) makes
the context's names available; a bare call then reads as an instruction.

```lua
-- a working copy of the document, with the verbs of tentative editing
local new_draft = do(document)
    local draft = { length = document.length, cursor = document.cursor, edits = document.edits }
    draft.insert = do(n)
        draft.length = draft.length + n
        draft.cursor = draft.cursor + n
        draft.edits = draft.edits + 1
    end
    draft.move_left = do()
        if draft.cursor > 0 then draft.cursor = draft.cursor - 1 end
    end
    return draft
end

-- an activity that always commits: setup, the body speaking instructions, completion
local edit = do(document)
    return do(body)
        local draft = new_draft document
        body draft
        document.length, document.cursor, document.edits = draft.length, draft.cursor, draft.edits
    end
end

local fresh = { length = 0, cursor = 0, edits = 0 }
local moved = 0
edit fresh:
    insert 5
    local before = cursor
    move_left
    moved = before - cursor
end
assert(moved == 1 and fresh.length == 5 and fresh.cursor == 4 and fresh.edits == 1)
```

`insert 5` and `move_left` are **instructions**: calls without a receiver, resolved by the
innermost opened context that provides the name, subject to lexical shadowing. A name the context
lacks falls through to enclosing contexts (§5.8), and later local declarations can shadow
introduced names. The local binding and assignment are ordinary computation alongside the
instructions. Open the context with a name (`do(draft..)`) when the receiver itself is needed.

### 5.4 Open to work; bind to remember

An opened field name is the field's place: reading it reads the current value, assigning it
stores into the table. A binding takes the value at that point: `local before = cursor` keeps the
cursor from before the `move_left` instruction. That is the whole rule: **open to work; bind to
remember.**

### 5.5 The activity owns completion

`edit` commits a working copy at the end. Its contract is its own: write through, commit,
roll back, retry. Three boundaries hold:

* the body's `return` leaves the body, not the activity;
* cleanup and commit are the activity's code, not a side effect of opening;
* a temporary context does not outlive the activity: do not stash it where the activity cannot
  clean it up.

An outcome protocol is not exception unwinding: an error is not an `abort` return, and opening a
context does not install automatic cleanup.

### 5.6 The body decides; the activity completes

A body cannot leave its activity, so it cannot abort by jumping out. **It returns an outcome, and
the activity matches on it to choose its completion:**

```lua
local Outcome = oneof { commit: Unit, abort: Number }

local try_edit = do(document)
    return do(body)
        local draft = new_draft document
        local committed = body(draft) {
            commit() = true,
            abort(reason) = false,
        }
        if committed then
            document.length, document.cursor, document.edits = draft.length, draft.cursor, draft.edits
        end
        return committed
    end
end

local type_capped = do(document, n, cap)
    return try_edit document:
        insert n
        if length > cap then return Outcome.abort length end
        return Outcome.commit()
    end
end

local doc = { length = 0, cursor = 0, edits = 0 }
assert(type_capped(doc, 4, 10) == true and doc.length == 4 and doc.edits == 1)
assert(type_capped(doc, 9, 10) == false)
assert(doc.length == 4 and doc.cursor == 4 and doc.edits == 1)  -- rejection changed nothing
```

The rule "the activity owns completion" covers the body's ordinary outcomes too: the body says
what happened, and the activity decides what that means for the entity. The outcome type is part
of the activity's contract, so give it outcome names (`commit`, `abort`, `retry`), not
unexplained flags. This completes the bounded-edit design begun in §2.2: `abort` carries the
tentative length to the activity; `try_edit` deliberately projects that richer outcome to
acceptance or rejection. A caller that needs the reason would need a richer outer result. Test
both paths: successful commit changes the document, while rejection must preserve length, cursor
and edit count.

### 5.7 Stack activities instead of adding options

Each policy is its own activity, and the order of the spine is the order of completion:

```lua
-- a policy that completes after the work inside it
local clamp_length = do(document, max)
    return do(body)
        body
        if document.length > max then
            document.length = max
            document.cursor = max
        end
    end
end
local count_into = do(stats)
    return do(body)
        body
        stats.count = stats.count + 1
    end
end

local stats, big = { count = 0 }, { length = 0, cursor = 0, edits = 0 }
count_into stats do
clamp_length(big, 100) do
edit big:
    insert 250
endall
assert(big.length == 100 and stats.count == 1)
```

The edit commits first, then the clamp applies, then the count is recorded, exactly as the
spine reads from the inside out. `endall` closes a spine written flat; it adds no semantics.

### 5.8 Nesting composes, and design the context's vocabulary

Nested activities do not need to know about each other. A name the inner context lacks falls
through to the enclosing ones, innermost first, so a block can speak to several activities at
once:

```lua
-- nested activities compose: a name the inner context lacks reaches the outer one
local collect_notes = do(body)
    local log = { notes = 0 }
    log.note = do(count) log.notes = log.notes + count end
    body log
    return log.notes
end

local type_logged = do(document, n)
    return collect_notes:
        edit document:
            insert n
            note 1
        end
    end
end
assert(type_logged({ length = 0, cursor = 0, edits = 0 }, 3) == 1)
```

`insert` is the draft's; `note` is not, so it reaches the log. If the draft also had a `note`,
the draft's would win: the innermost context always does. Shadowing is how nesting works, so use
it on purpose. When an override would hide something the block needs, the outer name is too
generic, or the two activities should not be nested.

A context's vocabulary is the language of its block. Start it as names: the verbs a body needs,
assembled from small capability vocabularies (§3.1), opened by the activity. Give the context a
nominal type when it holds state with an invariant. Design it the way you would design a small
language for that purpose:

* **Verbs for what happens**: `insert`, `move_left`, `note`. Put invariant-preserving changes
  behind these verbs; public fields do not enforce that discipline for you.
* **Fields for what the block reads**: `cursor`, `length`. If callers repeatedly need to change a
  field directly, ask which operation is missing.
* **One context per purpose.** Repeatedly reaching around a context suggests a missing verb or
  mixed responsibilities (§2.3).
* **Outcomes for how it can end** (§5.6), named for what happened.
* **Names that read in the block**: an instruction is read without its receiver, so `insert n`
  must say everything `draft:insert(n)` said.
* **Functions own their parameter roles; vocabularies compose functions, not parameter lists.** An
  instruction usually takes one operand, because the opened context supplies its subject.
  Do not impose one parameter convention across a vocabulary: two vocabularies compose by spread
  whatever their functions' arities.
* **Compose capabilities rather than growing one type.** Verbs that do not need the context's
  fields can live in small vocabularies assembled by spread (§3.1). Keep verbs that preserve the
  context's invariant as its methods.

### 5.9 Builders: activities that build a description

A **builder** is an activity whose context is a vocabulary (§3.1) and whose completion returns a
description. The block's instructions declare things, and the builder collects them. Opening
supplies the vocabulary without a current-builder global or an interface argument on every
instruction.

```lua
-- a builder: the block declares, the builder returns a description
local keymap = do(body)
    local bindings = {}
    body define
        bind = do(key) = do(command)
            bindings[#bindings + 1] = { .key, .command }
        end
    end
    return bindings
end

local editor_keys = keymap:
    bind "h" (Command.move(Direction.left()))
    bind "l" (Command.move(Direction.right()))
    bind "u" (Command.undo())
end
assert(#editor_keys == 3 and editor_keys[1].key == "h")
```

What a builder's vocabulary offers, and how to design one:

* **Declarations** create named parts, often as nested builders with blocks of their own.
* **Properties** set a value on the current part. Instructions run in order, so **a later setting
  wins**: no merge rules or priorities are needed.
* **Variants** are nested blocks that record conditional settings.
* **Tokens** are names for known values, opened with the vocabulary; give them a kind so a wrong
  argument is an error at its line.
* **Sharing** is a block applied to the current part.
* **Nesting composes** exactly as in §5.8: a name the inner part lacks reaches the enclosing one.
* **Keep builders pure** (§7.1): they build descriptions; engines do the work.

A builder is "describe, then run" (§11) with a syntax that reads like the domain.

### 5.10 Designing a small language

A DSL in Mua is not a parser. It is a vocabulary, a description and an engine, arranged so the
user writes sentences of the domain. Design it in this order.

**1. Choose the kind of each phrase.**

| Kind | Runs | Built from | Example |
|---|---|---|---|
| instruction DSL | when the block runs | an activity that opens a context; the body speaks instructions (§5.3) | editing, transactions, I/O |
| declarative DSL | while building | a builder that returns a description (§5.9) | key maps, routes, UI, protocols |
| data DSL | while building | a vocabulary (§3.1) | configuration, tokens, tables of constants |
| syntax | at translation | a host form | only for genuinely new grammar; last resort |

Most DSLs mix them: a declarative front end describes, an engine runs, and its handlers are
instruction blocks.

**2. Design from the sentences.** Write the text the user should write before anything else, then
derive the vocabulary from it: verbs become instructions, nouns become declared parts or tokens,
qualifiers become properties or stacked policy activities (§5.7), alternatives become a `oneof`.
A sentence that does not read is a vocabulary problem; parentheses or new syntax will not fix it
(§13).

**3. Layer it structurally, and commit only what must be recognized.** The words and tokens of a
DSL are vocabularies: structural and composable. The methods a router speaks are a vocabulary of
known values:

```lua
-- the methods a router speaks: a structural vocabulary of known values
local Methods = { get = 1, post = 2 }
```

**4. Make the builder check its sentences, and report at the user's line.** A structural mistake
surfaces late, deep in an engine; a DSL feels like a language when a bad sentence is rejected
where it is written. Validate while building, and raise the error at the level of the line that
spoke the instruction:

```lua
-- the builder: one verb per method; sentences in, a checked description out
local router = do(Verbs)
    return do(body)
        local routes, seen, Routing = {}, {}, {}
        for name, code in pairs Verbs do
            Routing[name] = do(path)
                -- level 3: the error names the line that spoke the route
                if type path ~= "string" or path:sub(1, 1) ~= "/" then
                    error(name .. ": a path starts with '/', got " .. tostring path, 3)
                end
                if seen[name .. path] then error(name .. " " .. path .. " is declared twice", 3) end
                seen[name .. path] = true
                return do(handler) routes[#routes + 1] = { method = code, .path, .handler } end
            end
        end
        body Routing
        return routes
    end
end
local routes = router Methods
assert(not pcall(routes, do(..) get "notes" (|| -> 1) end))  -- a path starts with '/'
```

The builder makes its verbs from the vocabulary it is given (one verb per method), so the
vocabulary decides what can be said. `Methods` is stateless vocabulary; `Routing` is stateful
vocabulary, made afresh for each build. Its handlers capture that build's `routes` and `seen`,
so repeated or nested builds do not share their temporary state. The factory's placement, not
`define` or opening, gives it that lifetime.

**5. Treat the description as the interface.** The builder's result is keyed data, and the engine
depends only on it. Keep it structural while only the engine reads it; promote it to a `oneof` of
commands when it must be recognized, stored or replayed (§3.2, §11). Several front ends can then
feed one engine: a builder, a file read at start-up, a test.

**6. Let handlers be instruction blocks.** A colon block opens what it is given, so
a handler speaks the request's fields directly, as an activity body speaks its context's (§5.4):

```lua
-- the sentences: each handler opens the request it is given
local site = routes:
    get "/":
        return 200
    end
    post "/notes":
        return 200 + #path
    end
end

-- the engine over the description
local dispatch = do(table, request)
    for _, r in ipairs table do
        if request.method == r.method and request.path == r.path then
            return r.handler request
        end
    end
    return 404
end
assert(dispatch(site, { method = 1, path = "/" }) == 200)
assert(dispatch(site, { method = 2, path = "/notes" }) == 206)
assert(dispatch(site, { method = 1, path = "/nope" }) == 404)
```

**7. Test the description where it is built.** It is data, so an assert checks it without running
the engine:

```lua
-- the description is data: test it as it is built
assert(#site == 2 and site[2].path == "/notes")
```

**8. Compose by spread.** A dialect is the same builder over an extended vocabulary; a user
extension overrides entries instead of forking the DSL, and the overlap rule turns two extensions
defining one name into an error. Two DSLs used in one block must not compete for generic names:
qualify a homonym rather than letting one shadow the other (§13):

```lua
-- a dialect: the same builder over a vocabulary extended by spread
local Dav = { ..Methods, propfind = 7 }
local dav_routes = router Dav
local share = dav_routes:
    propfind "/":
        return 207
    end
end
assert(share[1].method == 7)
```

## 6. Step 3: states

For a lifecycle with distinct modes, draw the legal transitions before choosing its
representation. Label events, state what each transition preserves, and decide what happens to
events that are not accepted in the current mode:

```text
stateDiagram-v2
    [*] --> reading
    reading --> reading : bytes
    reading --> rejected : bad line
    rejected --> reading : next event
    reading --> closed : hang up
    closed --> [*]
```

A `oneof` is a natural representation when states carry different data. A function from state
and event to next state makes the transition rules testable. Here `rejected` deliberately
consumes the next event only to reset; even a `hang_up` in that state resets rather than closes.
That is this example's policy, not a consequence of using a `oneof`:

```lua
-- a lifecycle as a oneof, and one function per transition
local Conn = oneof { reading: Number, rejected: Number, closed: Unit }
local Event = oneof { bytes: Number, bad_line: Unit, hang_up: Unit }

local step = do(c: Conn, e: Event): Conn = c {
    reading(n) = e {
        bytes(k) = Conn.reading(n + k),
        bad_line() = Conn.rejected n,
        hang_up() = Conn.closed(),
    },
    rejected(n) = Conn.reading 0,
    closed() = Conn.closed(),
}
local after = step(Conn.reading 3, Event.bytes 4)
assert(after { reading = n -> n, rejected = n -> -1, closed = || -> -2 } == 7)
```

* **Match exhaustively, and account for every state/event combination.** A "cannot happen" arm is
  a prompt to inspect the model: a state may be missing, or separate fields may admit
  combinations that should be one variant. Not every counter or independent condition needs a
  state variant.
* **Test transitions, not just arithmetic.** Include every state and the events that are ignored,
  rejected or terminal. For a real connection, decide explicitly whether a hang-up must close
  from every live state.

## 7. Step 4: composition and edges

```text
flowchart LR
    subgraph Edges
        io[files, sockets, clock] --- c[adapters]
    end
    subgraph Core[pure core]
        fns[functions from values to values]
    end
    root((entry points)) --> Edges
    root --> Core
    cfg[[configuration]] -. start-up .-> Core
```

### 7.1 Roots, edges, core

* **Entry points are the composition roots.** They wire the parts together.
* **Effects enter at the edges.** Files, sockets and the clock are opened at the outside and
  passed in. The function that opens a file is not the function that parses it.
* **Libraries are small instruction sets.** A low-level library (a transport, a codec, a
  scheduler) is a vocabulary of a few verbs; a domain vocabulary composes several by spread, and
  an algorithm opens the composition. Swapping a backend, or supplying a test double, is passing
  another vocabulary: no interface type, no inheritance. Use nominal types for the data that
  crosses those boundaries and activities for the lifetimes they manage.
* **The pure core decides.** Functions from values to values are testable without the world.
* **Keep builders and generators deterministic and pure:** no clock, no unseeded randomness, no
  I/O except declared input. They are functions of their inputs, so equal inputs give equal
  descriptions.

### 7.2 What is a vocabulary, and what is a function

A library module is a vocabulary: write its functions as locals, so they can use each other, and
end the file with the surface it offers, `return define .square .double end`. What is not
listed stays private, and an entry may rename (`area = square`). A layer (a platform, a backend)
is a vocabulary that spreads its base and overrides a few entries; the overlap rule catches two
layers defining the same name.

```lua
local square = x -> x * x
local double = x -> x * 2
local library = define
    .square
    .double
    area = square
end
local platform = define ..library
    double = x -> x * 3
end
assert(library.area 3 == 9 and platform.double 2 == 6 and platform.square 2 == 4)
```

## 8. Steps 5 and 6: the skeleton, and verifying it

Draft a use case top-down to discover the functions you wish you had. Then make one end-to-end
scenario run, including its rejection or failure path. Do not wait for every diagram or operation
to be complete.

A useful implementation route is:

1. **Example inputs and the nominal types** from the values and lifecycle decisions.
2. **A small core operation,** with asserts where it is pure.
3. **The activity and context,** including setup and each completion path.
4. **A composition root** that exercises the scenario.

Drafting order is not source binding order. Mua uses Lua's lexical scope: a later `local` helper
is not visible to an earlier function definition. Put dependencies before their users, or use
deliberate forward bindings.

For the bounded edit, the skeleton is the document, `new_draft`, the draft verbs, `Outcome`,
`try_edit` and `type_capped`. A successful scenario must commit the expected fields; a rejected
one must preserve all of them (§5.6).

**Tests.** Test the pure core with plain asserts next to the functions. Test an activity's
completion obligations on both paths, including unchanged state after rejection. Contracts at the
edges turn a wrong value into an error at the call that made it:

```lua
local area = do(w: Number, h: Number): Number = w * h
assert(area(3, 4) == 12)
local ok, message = pcall(area, "3", 4)
assert(not ok and message:find("parameter 'w' of area expects Number", 1, true))
```

Read what a form emits when a behavior surprises you: the translator writes plain Lua, and the
result is the program that runs. When a number or a result is wrong, use the revisit questions
(§2.3) to choose the next experiment.

---

# Part II — Writing code

## 9. Subject first, body last

A call should read like a sentence: subject, verb, objects, continuation. A method makes the
subject the receiver:

```lua
local Cursor = struct { position: Number, length: Number }

function Cursor:move_left()
    if self.position > 0 then
        self.position = self.position - 1
    end
end

function Cursor:at_end()
    return self.position == self.length
end

local cursor = Cursor { position = 2, length = 2 }
cursor:move_left
assert(cursor.position == 1 and not cursor:at_end())
```

Put the body last when the function establishes structure: `edit document: … end`. Name
the opened parameter only when its name is used.

## 10. A match reads as a protocol

Handlers are named after outcomes, and the handler sugar `name(p) = e` keeps short arms short:

```lua
local first_or = do(xs, fallback)
    return find_nonzero(xs) {
        found(i) = xs[i],
        missing() = fallback,
    }
end
assert(first_or({ 0, 5 }, -1) == 5 and first_or({}, -1) == -1)
```

## 11. Describe, then run

When a problem has structure (a grammar, a key map, a protocol), write the structure as data and
an engine that consumes it. Keep one engine:

```lua
local apply = do(document, c: Command): Unit
    c with
        move = do(d)
            d with
                left() = Editing.left document
                right() = Editing.right document
            end
        end
        insert = do(n)
            Editing.insert document n
        end
        undo() = nil
        quit() = nil
    end
end

local greeting = { Command.insert 5, Command.move(Direction.left()), Command.insert 1 }
local text = { length = 0, cursor = 0, edits = 0 }
for _, command in ipairs greeting do apply(text, command) end
assert(text.length == 6 and text.cursor == 5)
```

The same engine serves a description built by a builder, read from a file, or written in a test.
A description is often best written with a builder (§5.9): the block reads like the domain, and
the builder hands the engine keyed data (§5.10). Do not maintain a second, hand-specialized
implementation of the engine.

## 12. Connecting behavior

| Connection | Use |
|---|---|
| ordinary result | a computation producing a value: the default |
| subject block | a block receiving a thing to act on: `each(items): item … end` |
| activity block | a block receiving a context and speaking its instructions: `do(..)`, or `do(draft..)` when the name is used |
| builder block | a block declaring a structure while building: `keymap: … end` (§5.9) |
| keyed handlers | one behavior per outcome: matching a `oneof` |

Application is curried, so an activity that takes setup and then a block is a function returning
the function that takes the block; `f a: x … end` passes the block as the next argument. The
signature decides where the activity completes, not the parser.

---

# Part III — Style

## 13. Naming

> **A name is a promise. A vocabulary is a set of promises spoken together.**

**PascalCase for types, including built-in checkers; snake_case for functions and values.**

| Role | Convention | Examples |
|---|---|---|
| entity or value type | PascalCase noun | `Document`, `Heading`, `Command` |
| activity context type | PascalCase noun for what the body holds | `Draft`, `Batch`, `Tally` |
| instance or parameter | snake_case role | `document`, `outline` |
| action | imperative verb | `insert`, `apply`, `release` |
| transformation | participle or adjective | `trimmed`, `translated` |
| query | the thing returned | `line_count`, `text_width` |
| predicate | proposition | `at_end`, `has_selection` |
| activity function | a verb phrase for what it does to its destination, or `with_` + resource | `edit`, `try_edit`, `count_into`, `with_file` |
| activity block parameter | snake_case noun, matching the context | `draft`, `batch`, `file` |
| declared part (a field a builder declares) | long, descriptive snake_case: what it is | `increment_button`, `question_label` |
| builder instruction | the domain's own vocabulary | `bind`, `button`, `get` |
| outcome of a body | snake_case outcome | `commit`, `abort`, `retry` |
| `oneof` alternative | snake_case outcome | `found`, `missing`, `done`, `timed_out` |
| vocabulary describing a structure (interface, capability set, namespace) | PascalCase, like a type | `Editing`, `Moves`, `Storage` |
| vocabulary holding data (configuration, fixture, values in flight) | snake_case, like a value | `config`, `span` |
| Mua's own forms | lowercase keywords | `struct`, `oneof`, `define`, `ffistruct` |

The forms are lowercase so that the capitals are the user's types, not the language's keywords.

**Name an activity for what it does to its destination.** An activity is a verb phrase that takes
the destination first, so the call reads as a sentence: `edit document:`, `try_edit document:`,
`clamp_length document 100 do`, `count_into stats do`, `collect_notes:`. The verb tells the
relationship: `edit` always completes by committing, `try_edit` commits only on acceptance,
`count_into` records into its destination after the work. A scoped resource is `with_` + the
resource (`with_file path:`). Avoid a noun borrowed from another domain (`transaction`,
`session`): it promises a guarantee the activity may not give, and says nothing about what it
acts on.

**Activity functions say what completion means; contexts are nouns for what the body holds.**
`edit` commits after the body returns normally; `try_edit` commits only on acceptance. The
body holds a draft. When an opened parameter needs a name, use the context's noun: `draft`,
`do(draft..)`. Otherwise use `do(..)`.

**Names carry the reading, not parentheses.** The house style drops call parentheses wherever
the grammar permits: `release slot`, `bind "h" (...)`, `count_into stats do … end`. That works only
when names are descriptive. If a line is confusing without parentheses, adding them back hides
the problem: the names are not descriptive enough, or the design is wrong (a function with a
role-less argument, a chain that applies too much at once, a flag where a `oneof` or two
functions belong). Rename or redesign until the line reads as a sentence.

**No short names.** In Mua everything is vocabulary, so naming is part of designing: a name
should read as what it is, not hide behind a shorthand. Write `node`, `scope`, `problems`,
`register`, `condition`, `element_type`, never `n`, `ctx`, `d`, `dst`, `T`, `cfg`, `tmp`. Mua is
concise enough that the words cost nothing; what a shorthand saves in typing, every reader pays
back in decoding. A parameter is named for what it holds (a handler's node by its kind:
`literal`, `application`), a function passed in for what it does (`check`, `evaluate`), and state
for its role (`scope`, `lowering`, `facts`). Loop counters too: `index`, `position`, `line`.

**Prefer long, descriptive names for declared things.** A declared part shares a namespace with
its owner's methods, and a name that says what the part is (`increment_button`) never competes
with one that says what a method does (`increment`). Instructions are read without their
receiver, so their names must carry the whole meaning.

**Let the receiver carry the subject:** `document:move_left`, not `document:move_document_left`.
**Name for the call site:** no unexplained flags; prefer two functions or a `oneof`. **Use
shadowing deliberately:** openings follow ordinary lexical shadowing, so later vocabularies can
override earlier ones. When an override would obscure the subject, ask whether a name is too
generic or a homonym should stay qualified.

## 14. Spelling forms

| Form | Use |
|---|---|
| juxtaposition | the default for safe application, including several arguments: `insert 5`, `bind "h" "left"` |
| parentheses | required grouping, argument lists of functions with several parameters, zero-argument calls in expressions; named call statements need no `()` |
| `word` | a zero-argument call statement |
| `word()` | a zero-argument invocation in an expression; also valid as an explicit statement |
| trailing block (colon) | scopes, iteration, activities, builders: `f x:` then the block and `end` |
| `do(x) … end` | a function that is a block: `local f = do(x) … end` for a definition whose body is statements |
| `return do(x) … end` | an activity that returns the function taking its block: `return do(body) … end` |
| instruction | inside an opened block, a call without a receiver: `insert n`, `note 1` |
| `with` blocks | keyed data that spans lines; a `struct` or `oneof` declaration; matching |
| `{ }` braces | Lua tables, compact one-liners |
| `define` entries `end` | a vocabulary or a structural type; `{ … }` for a one-line table |
| `x -> e`, `|a, b| -> e` | a small expression lambda (one name needs no bars; several names after an operand are bracketed) |
| `do(x) … end` | a callback with statements and parameters (the colon form takes none) |
| `do(x: T): R = e` | a lambda with types, or with an opened parameter (`do(ctx..)`): arrows have no spelling for these |
| `endall` | the closing run of a trailing-block spine |
| `local x = e` | a binding |
| `x: T` | a contract at a boundary |

A standalone callable name is a zero-argument call statement: `refresh` calls `refresh()`. In an
expression the name remains a value: `local action = refresh` saves the callable, while
`local result = refresh()` invokes it.

**One lambda spelling for each purpose.** An expression is an arrow (`x -> x * 2`); statements are
a `do` block (`do(x) … end`). The trailing colon (`f x:`) is only the anonymous opening block,
`do(..)`. Types and opening need `do`. A function that returns a block is written
`do(params) … end` with `return do(block_params) … end`, so an activity reads without a
second spelling.

Parentheses group and delimit required argument lists; they are not a substitute for clear
names. Application binds tighter than operators and takes a name's full postfix chain. Write
compound arguments as spaced groups, such as `apply document (Command.insert n)`. When safe
parenthesis-free application is hard to read, revisit names or split the functions (§13).

## 15. Formatting

**Current source and the host's formatter establish the house style.** Use 4-space indentation,
a 100-column soft target, safe parenthesis-free application, `.name` for a `name = name` field,
and anonymous openings when the receiver name is unused. The formatter also writes the house
spellings: the anonymous trailing colon (`f x:`), do blocks for parameters, arrows for plain expression lambdas
(`lambda_style`), `define` blocks, and a single `..base` first and beside its `define`
(`spread_style`). The code blocks of this guide are written that way. What the formatter leaves to you:

* **Where lines break.** Break a long application at its argument groups, and put each handler
  of a multiline match on its own line.
* **Keep `do` on its owning call's line.** A trailing lambda can attach across a newline, but the
  same-line spelling makes the relationship visible.
* **A flat spine for stacked activities:** the opening calls aligned, the innermost body indented
  once, one `endall`.
* **Multiline braces take a trailing comma.**
* **One blank line between top-level functions; `require`s first.**

## 16. Files and libraries

* **A file is a vocabulary or a program**, and a Mua file is `.mua` (a module of plain Lua that a
  Mua program requires stays `.lua`). A program file defines its functions and runs its
  scenario. A library returns its vocabulary through `require`, usually `return define … end`
  after its locals (§7.2).
* **Readable dependency order:** `require`s first, then types and supporting functions before
  their users. Give each exported function a one-line promise. Drafting top-down does not make
  later local bindings visible earlier (§8).
* **Dependencies point toward the domain.** Activities use entities; entities do not import every
  activity that can operate on them.

## 17. Comments

Explain why when the code says what. State what a signature cannot: an invariant, a completion
obligation, a cost condition. Give each exported function one sentence of promise. An overview of
a subtle engine saves the reader a reconstruction; write it.

## 18. Anti-patterns

| Anti-pattern | Prefer |
|---|---|
| repeatedly interpreting a description in a hot path | an engine written once over the data; precompute what is known |
| a second hand-specialized copy of an engine | one engine over a description |
| purpose-specific tentative verbs accumulated on the persistent entity | a context vocabulary and an activity that owns completion |
| an activity configured by flags | stacked policy activities |
| a builder that keeps a current-builder global, or an interface argument passed to every method | a block that opens the builder's vocabulary (§5.9) |
| a nominal interface type introduced only to recognize a set of operations | a vocabulary the function takes or opens (§3.1) |
| a `struct` that groups names, constants or functions | `define` (§3.1) |
| a `struct` invented to carry two values between functions | a vocabulary of the values; promote it when it must be recognized (§3.2) |
| a vocabulary copied to change one entry | spread it and override the entry |
| a block that writes a context's fields to get around its verbs | the verb that is missing (§5.8) |
| naming every context to reach outer names | `do(..)`, and let names fall through (§5.8) |
| parentheses added so a line can be read | descriptive names, or a better split of the functions |
| short names and shorthands (`n`, `ctx`, `cfg`, `dst`, `T`) | the full word for what the thing is (§13) |
| a body that aborts by jumping out | an outcome the activity matches on |
| an error used to carry an ordinary alternative | a `oneof` outcome |
| silently discarding an outcome | propagate or handle it, or explicitly promise a best-effort result and test that contract |
| a magic value for absence | a `oneof` |
| contracts on every local | contracts at the edges where values cross in |
| a `oneof` with a "cannot happen" arm | a missing state, or a representation that admits invalid combinations |

## 19. Review checklist

* **Frame and diagrams:** can a concrete success and failure be followed through the relevant
  views? Did the drawings expose or change a decision? Do retained views agree with the code and
  contracts?
* **Structure:** which trigger (§3.2) justified each nominal type? Is anything grouped as a type
  that only names things?
* **Names:** do calls read as sentences? Is any name a shorthand that should be a word? Is the context a noun for what the body holds? Are
  unused opened receiver names omitted?
* **Activities:** who sets up, who completes, and how does a body abort?
* **DSLs:** do the sentences read without parentheses? Is each phrase the right kind? Are bad
  sentences rejected at their own line? Is the description data an assert can check?
* **Instructions:** does the context supply the verbs its purpose needs? Do instructions read
  clearly without a receiver, and are deliberately qualified calls clear? Does a builder return a
  description rather than hide work?
* **States:** are legal transitions and invalid combinations accounted for? Are matches
  exhaustive and ignored events deliberate?
* **Outcomes:** are alternatives and payloads explicit where needed? Is each failure the right
  kind (§3.3), and is any discarded information justified by the caller's contract?
* **Edges:** are effects opened at the outside and passed in? Is each contract at an edge?
* **Tests:** do asserts cover the core, and do tests check completion obligations, including
  unchanged state after rejection?

## Maxim

> **Name structurally; commit a type when the program demands it. Model the values. Name the
> functions. Enter the activity: open the context, speak its instructions, bind a value to
> remember it, and let the activity complete. Describe with builders, run with engines. Check at
> the edges.**
