# Formatting Mua

`mua fmt` keeps Mua's phrase-oriented style (juxtaposition, trailing blocks, `with` data). It
uses Mua's own parser and the lossless lexer; it does not execute the source or resolve
imports. It removes unused names from opened `do` parameters (see `opening_style`). A host
(Nua is one) can add forms, facts and passes of its own (§Hosts below).

## Commands

Run from the repository root with LuaJIT 2.1 (with the 3.0 syntax backport):

```sh
luajit mua.lua fmt program.mua                  # formatted source on stdout
luajit mua.lua fmt -                            # stdin to stdout (also the default)
luajit mua.lua fmt --check src/*.mua             # CI: report files needing formatting
luajit mua.lua fmt --write program.mua lib/*.mua # explicitly update these files
luajit mua.lua fmt --config path/to/style.lua program.mua
```

There is no implicit repository-wide rewrite. Stdout mode takes one input;
`--check` and `--write` accept several files. Shell globs select files; the
formatter does not recursively discover sources. Use `--` before filenames
that begin with a dash. Stdin cannot be combined with `--write` or other inputs.

Exit status is **0** on success, **1** when `--check` finds differences, and **2**
for a syntax, configuration, usage, or I/O error. Check mode never writes source.
Write mode parses and formats every input before changing any file, so a bad
input does not leave an earlier input reformatted. Filesystem write failures
can still interrupt the subsequent writes; this is not a multi-file transaction.

## Settings

No configuration file is required. These are the defaults:

```lua
-- .muafmt.lua
return {
    indent_width = 4,
    column_width = 100,
    call_style = "minimal",
    spine_style = "pure",
    table_style = "shorthand",
    spread_style = "top",
    opening_style = "anonymous",
    block_style = "colon",
    data_style = "with",
    inline_with = 2,
}
```

The nearest `.muafmt.lua` is found by walking upward from each input's directory.
For stdin, the search starts at the working directory. `--config` selects one
file for all inputs instead. Settings not specified use the defaults; configurations
are not merged with parent directories. The configuration must return a table;
it runs without standard-library or process globals. Use a trusted configuration
file, not arbitrary downloaded Lua code.

| Setting | Values | Meaning |
|---|---|---|
| `indent_width` | integer 1–8 | Spaces per block or continued delimited list. |
| `column_width` | integer 20–240 | Soft wrapping target, not a hard limit. |
| `call_style` | `"minimal"`, `"preserve"` | Remove safe call parentheses (and fold a spine's closers), or retain call spelling. |
| `table_style` | `"shorthand"`, `"preserve"` | `"shorthand"` writes a table entry `name = name` as `.name` (syntax doc, §4); `"preserve"` keeps the spelling, including any `.name` already written. |
| `spread_style` | `"top"`, `"preserve"` | `"top"` writes the one `..base` of a table first, beside its `with` (below); `"preserve"` keeps entries where they are written. |
| `opening_style` | `"anonymous"`, `"preserve"` | Remove an unused name from an opened `do` parameter, or keep named openings. |
| `block_style` | `"colon"`, `"do"` | Write an untyped trailing `do(..)` that ends a line in the colon form (syntax doc, §4), or keep the `do` spelling. |
| `data_style` | `"with"`, `"preserve"` | Write a multi-line table that follows a head (`T {`, `f(x) {`) as a `with` block (syntax doc, §4), or keep the braces. |
| `inline_with` | integer 0–16 | A table of at most this many plain entries that follows a head is written on one line (`Point { x = 1, y = 2 }`) when it fits `column_width`; `0` keeps the layout as written. Has no effect with `data_style = "preserve"`. |
| `spine_style` | `"pure"`, `"all"`, `"none"` | Which link bodies of an `endall` spine lose their indent. |

Unknown settings and invalid values are errors, not silently ignored options.

## Anonymous openings

With `opening_style = "anonymous"`, the formatter writes an unused opened
parameter `do(ctx..)` as `do(..)`. A type annotation stays: `do(ctx..: T)` becomes
`do(..: T)`. Ordinary parameters and `local ctx..` declarations are not changed.

Only the parameter-name token is removed. Comments and strings are preserved;
mentions inside them, field names, and table keys are not uses of the parameter.
References, assignments, reopening the receiver, and captures in nested blocks
keep the name. The analysis is conservative: a nested reference also keeps the
name when an intervening binding might shadow it.

The formatter keeps the name if the block contains an anonymous-home read
(`(..)`) or refers to the internal `__home` binding, since introducing a home
could change that lookup. It also avoids conflicting `__home` parameters and
repeated parameter names that affect which argument is opened.
The candidate is reparsed and checked against exactly the intended parameter
change. Set `opening_style = "preserve"` to retain named openings.

## Trailing colon

With `block_style = "colon"`, an untyped `do(names)` that ends a line, after an
operand and outside brackets, is written `: names`; after an `=` (also inside brackets) it is written `=: names` (`do(..)` as `:`, `do(scope..)`
as `: scope..`). Typed lambdas, inline blocks, blocks that open a new argument
inside brackets and parameterless `do` blocks keep their spelling. The colon form
is read back as the `do(..)` it means before anything else is analysed, and the
result is accepted only when that reading equals the original source.

## With blocks

A `with` block (syntax doc, §4) stays a `with` block, and with
`data_style = "with"` a multi-line table that follows a head is written as one.
The head is an operand: a name, a call or an index (`Point {`, `Store(Node) {`,
`s {` for a match, `f(x) {`). Tables on one line, and tables with no head
(`{ 1, 2 }`, `local t = { a = 1 }`, `return { ... }`, which are Lua's), keep their
braces. `data_style = "preserve"` keeps every table as written: `with` blocks stay
`with`, braces stay braces.

A short table is not worth a block. With `inline_with = 2` (the default) a table that
follows a head and has one or two entries is written on one line, in braces, when the line
fits `column_width`: `local p = Point { x = 1, y = 2 }`, whether it was written as a `with`
block or as a multi-line table. A table keeps its block when it has more entries, when an
entry holds a handler or a comment, when its line would not fit, and when its head is the
contextual `with` (there is no type to put braces after). Formatting twice changes nothing:
a one-line table stays one line, and a long one stays a block.

The entries are laid out as a table's are, and the block is written without the
separators the reader would put back: the comma at the end of a line goes, and a
trailing comma goes too. Entries that share a line keep their commas, which keeps
them readable (`Point with x = 1, y = 2 end`). A separator is
kept where the reader would not recover it, before an entry that starts with a
bracket or a literal. Each table is converted on its own, and only when expanding
the result gives the same program as the braces.

## Definitions

`define` followed by entries and `end` is a table, written without commas. The formatter keeps a
`define` block a block (it never collapses it onto one line); a table written in braces stays in
braces.

## Spreads

A table with one keyed spread, `..base`, has a base and the entries that change it. A `with`
block is not ordered, so the formatter writes that spread first, on the line of the `with`, with
the changes below it:

```lua
local document = define ..Document
    length = 10
end
```

Explicit fields override spread fields wherever they are written, so moving the spread to the
front changes nothing, provided nothing observable happens in the entries it moves ahead of: a
spread is moved only past entries that are names, literals, functions or tables of those. A
table with several spreads, or with an entry that calls something before its spread, stays as
written. A table with a spread is not collapsed onto one line when it spans lines, whatever
`inline_with` says; a table already on one line (`Point { ..p, x = 1 }`) is left alone.
`spread_style = "preserve"` turns the rule off.

## End chains

A trailing run of `end` lines that closes Mua blocks (`do`, colon, `=:` and `with`)
back to Lua control, three or more of them and including a `with` block, is folded
into one `endall` and laid out flat (syntax doc, §4): the wrappers (`tasks:`, `spawn:`)
at one indent, the content after them indented once, the handler chain flat in the
content, sibling entries one level in under their `with`, and the innermost body one
level in. Blocks that stand between two others (an entry after the deep one) end the
run, so put the deepest handler last. The fold is accepted only when expanding the
result gives the same program. `spine_style = "none"` keeps the staircase of handlers.

## Default style

```lua
local Point = struct { x: Number, y: Number }
local move = do(x: Number): Number
    local p = Point { x = x, y = 2 }
    p.x = p.x + 1
    return p.x
end
```

- Spaces around operators and after commas/type colons; no spaces around member
  selection or a method colon. No trailing whitespace outside literal/comment text.
- A table entry `name = name` is written `.name` (`Point { .x, .y, z = 3 }`), per
  `table_style`; set it to `"preserve"` to keep the long form.
- Indentation follows parsed blocks and delimiters, including trailing lambdas,
  context openings and `endall`; `spine_style` decides how a spine's link bodies
  indent.
- Existing statement/application line boundaries stay in place, except that safe
  call rewrites join whitespace just inside removed argument delimiters, and a
  folded spine's run of closers becomes one `endall` line. Single-line blocks
  stay single-line; runs of empty lines become one empty line.
- Long delimited lists can wrap after commas. Long application chains, comments,
  and literals may exceed `column_width`: wrapping must not change application.
- Comments and literal contents retain their exact bytes. Long strings and long
  comments are not reindented internally. Whitespace line endings become LF;
  a shebang and literal/comment bytes are preserved. Nonempty output ends in LF.
- Inferred declarations stay inferred, and explicit annotations remain explicit.

With `call_style = "minimal"`, `show(h)` becomes `show h`, and a safe unary-call
chain such as `f(a)(b)` can become `f a b`. Unary call statements also use this
style: `consume(value)` becomes `consume value`. Whitespace just inside the call
delimiters can be joined, so multiline arguments and chains get the same treatment.
A sole `do` block argument also loses its call parentheses: `items:each(do(item)
... end)` becomes `items:each do(item) ... end`, even with a multiline body or a
next-line `do`. The block body's line boundaries remain intact.
Comments are not a blanket barrier: `f(--[[ note ]] x)` becomes
`f --[[ note ]] x`, and `f(x -- note` followed by a newline and `)` can become
`f x -- note`. Comment and literal bytes are preserved. Rewrites repeat until no
further safe removal is available; `call_style = "preserve"` retains the original
parentheses and argument line boundaries.

Minimal style also omits empty parentheses from named call **statements**:
`refresh()` becomes `refresh`, `screen.refresh()` becomes `screen.refresh`, and
`screen:refresh()` becomes `screen:refresh`. It never does this in a value or
return expression: `local result = refresh()` and `return refresh()` keep `()`.
`call_style = "preserve"` retains both explicit and already-bare spellings.
Reparsing prevents adjacent statements from becoming an argument chain; host
Lua postfix ambiguities are also kept delimited.

### Facts and word applications

Application in Mua is curried, so `f(x, y)` is not `f x y` unless the callee takes its groups as
one supply. Without facts the formatter removes parentheses only where one argument and the
syntax make it safe (`show(h)` → `show h`, a sole block argument, a named call statement). A host
supplies facts (a `host.facts` provider for `mua.scope`) that say which callees are words
taking every group as one supply, and inside typed bodies the formatter then also rewrites
`add(x, y)` to `add x y`:

A compound argument becomes a spaced group (syntax doc, §2 rule 3):

```lua
f(x + 1, y)            -- f (x + 1) y
place(s, fresh + out)  -- place s (fresh + out)
f(g(x), y)             -- f (g x) y      when g is a word
f(x, "s")              -- f x ("s")      a name's chain would take the string
```

A call in the middle of the supply is regrouped only when it is a word (one
value); spreads, explicit `call` boundaries, overapplication and postfix results
(`f(x, y).value`) keep their groups. A group whose arguments sit on several
lines is joined only when the call then fits `column_width`.

Decisions are made once per round from the syntax tree, innermost first, and
the whole round is verified with one reparse. If it does not verify, each
application chain is accepted only if it verifies on its own.

## Trailing-block spines

A spine is a stack of calls whose bodies are the next call, closed by one
`endall`:

```lua
    counted stats do
    counted stats do
    transaction document do(draft..)
        insert n
    endall
```

`spine_style` decides how the link bodies indent:

| Value | Behaviour |
|---|---|
| `"pure"` (default) | A link whose body is exactly the next trailing call keeps that call aligned with its opener; any other body indents once. |
| `"all"` | Every link body loses its indent; only the innermost body indents. |
| `"none"` | Every link body indents, so the spine reads as nested blocks. |

`endall` always sits where the innermost `end` would: aligned with the last
opener of the chain, so a flat spine closes at its base and a nested spine closes
at its innermost level. With `call_style = "minimal"`, a run of `end`s that
closes a spine inside a typed body folds into one `endall`; a comment between
the closers blocks the fold, and host Lua keeps its `end`s because `endall` is a
typed-body form.

Formatting reparses candidate call rewrites and the final output and compares
syntax trees in the application normal form the facts prove, ignoring source
positions and equivalent application spelling. Unknown call groups retain their
original structure.
A parse failure or a changed tree is an error; the input is not rewritten.
This check is not a type checker or a substitute for compiling the program.
Forms Mua does not know and no host defines are rejected rather than guessed at.

## Hosts

```lua
local fmt = require 'mua.fmt'
fmt.format(source, options, filename, host)    -- host is optional
```

A host is a table: `parse(filename)` gives the Mua parse host (the host's statement and prefix
forms), `facts` a fact provider, `environment(filename, api)` the facts of the chunk's world
(what modules export), `defaults` and `validate(options)` the host's own settings, `passes` extra
rewrites `(source, info, filename, options, api)` run after the first parse, and
`mentions(node, matches)` lets the unused-opening analysis see host nodes. Nua's formatter is
this formatter with Nua's host: it adds `type_style`, its words and externs as facts, and
reads `.nuafmt.lua`.

## Checks and embedding

```sh
make test
```

`tests/fmt.lua` and `tests/fmt_do.lua` cover golden output, comments and literals, call
boundaries, `endall`, configuration discovery, CLI status codes and failed-write preflight.

From Lua:

```lua
local fmt = require 'mua.fmt'
local formatted = fmt.format(source, { indent_width = 2 }, "program.mua")
```

The library returns formatted text or raises an error. It does not search for configuration
files or read/write source files; that is the command's responsibility.
