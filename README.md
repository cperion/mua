# Mua

Sugared Lua in, plain Lua out. Mua reads LuaJIT 2.1 plus the LuaJIT 3.0 syntax backport and
adds juxtaposed application, lambdas, trailing-colon blocks, `with` data blocks, keyed spread,
opening, structural `define` types, and contracts with `struct` and `oneof`. It is a language in
its own right and knows nothing about Nua, which is a host of it (Lua → Mua → Nua).

- `mua/lex.lua`, `parse.lua`, `emit.lua`: lexer, parser (one AST) and lean emitter.
- `mua/runtime.lua`: what emitted code calls (`__mua`).
- `mua/scope.lua`: lexical analysis over the AST, with a host-supplied fact provider.
- `mua/init.lua`: `parse`, `translate`, `load`, `loadfile`, `searcher`.
- `docs/syntax.md`: the surface language. `docs/designing-and-writing-mua.md`: how to compose with it.

Needs LuaJIT 2.1 with the 3.0 syntax backport (merged upstream 2026-07-20). `make test`
runs `tests/mua.lua`; `LUA=/path/to/luajit make test` selects the interpreter.

Terms: GPL-3.0-or-later, as for Nua (`COPYING`).
