# Mua

Sugared Lua in, plain Lua out. Mua reads LuaJIT 2.1 plus the LuaJIT 3.0 syntax backport and
adds juxtaposed application, lambdas, trailing-colon blocks, `with` data blocks, keyed spread,
opening, structural `define` types, and contracts with `struct` and `oneof`. It is a language in
its own right and knows nothing about Nua, which is a host of it (Lua → Mua → Nua).

- `mua/lex.lua`, `parse.lua`, `emit.lua`: lexer, parser (one AST) and lean emitter.
- `mua/runtime.lua`: what emitted code calls (`__mua`).
- `mua/scope.lua`: lexical analysis over the AST, with a host-supplied fact provider.
- `mua/init.lua`: `parse`, `translate`, `load`, `loadfile`, `searcher`; `load` can keep the
  translation as LuaJIT bytecode in a cache directory (`opts.cache`).
- `mua.lua`, `mua/cli.lua`: the `mua` command: `luajit mua.lua [-e code] [-d] [--no-contracts]
  [-l module] file.mua [args]` runs a file, runs an expression, or prints what a file translates
  to; `MUA_CACHE=dir` turns the bytecode cache on.
- `mua/test_cli.lua`: `mua test [--match text] files…` runs the cases the files name with the
  `test` word (`test "what it shows": … end`), collected first, every failure reported.
- `mua/fmt.lua`, `mua/fmt_text.lua`, `mua/fmt_cli.lua`: the formatter and `mua fmt`; a host (Nua is
  one) passes its parse forms, facts and extra passes (`docs/formatting.md`).
- `mua outline FILE [args]`: executes a file and outlines labels on its returned values,
  including generated vocabularies (`docs/outline.md`). Replaces mandatory comment linting.
- `examples/`: runnable programs, one idea each: `hello` (application, currying, short functions),
  `blocks` (trailing blocks, activities, `endall`), `vocabularies` (`define`, spread, opening, closed
  types), `contracts` (`struct`, `oneof`, matching), `router` (a builder and its engine),
  `lifecycle` (a state machine as a `oneof`), `editor` (activities, outcomes and commands: the guide's
  worked example), `ffi` (`ffistruct`), `variants` (`meta`: a metatable per tag, behaviors shared by spread), `lisp` (a small Lisp compiled to Lua: two `family` types, a pass per stage),
  `lisp_pull` (the same Lisp and passes, with a pull reader, iterator-returning rewrites, and
  demand-driven batches; compared by `bench/lisp_pull.lua`). Each ends with a comment holding what it prints;
  `tests/examples.lua` runs them against it.
- `docs/reading-mua.md`: a tour for newcomers: one function read slowly, its sugar undone step by
  step, and the colon explained. Start here if `with_log "import":` looks strange.
- `bench/micro.lua`: micro-benchmarks of the emitted code against hand-written Lua.
- `docs/specialization.md`: runtime plans, bound factories, and experimental struct specialization;
  `bench/specialization.lua` compares generic and generated construction. Generic remains the default.
- `docs/syntax.md`: the surface language. `docs/designing-and-writing-mua.md`: how to compose with it.
- `docs/writing-compilers.md`: writing compilers and language tools in Mua: one compiler built
  from text to running Lua, with families, passes, an IR, an optimizer and tests; its code blocks run.
- `docs/lisp-pull-comparison.md`: the same compiler with pull traversal boundaries, differential
  tests, and measurements separating full consumption from avoided work.
- `docs/luafun.md`: optional Lua Fun integration using native methods, opened/curried vocabularies,
  and a pipeline builder; `examples/luafun/idioms.mua` exercises them with the Lisp compiler.
  `docs/luafun-compiler.md` tests compiling a vocabulary to generators, with an independent
  interpreter, benchmarks, and JIT-trace evidence of fusion and its limits.

Needs LuaJIT 2.1 with the 3.0 syntax backport (merged upstream 2026-07-20). `make test`
runs `tests/mua.lua`; `LUA=/path/to/luajit make test` selects the interpreter.

Terms: GPL-3.0-or-later, as for Nua (`COPYING`).
