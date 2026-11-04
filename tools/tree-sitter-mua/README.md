# Mua Tree-sitter highlighting for Neovim

The editor parser for Mua: Lua source plus Mua's forms (juxtaposed application, `do` lambdas,
typed parameters, `struct`/`oneof`/`ffistruct`, handlers, spread, opened parameters, `endall`,
the trailing colon `f x:` and `with` blocks). It is the language's editor grammar, so it lives
with the language: formatting, highlighting and the compiler front end are Mua's, and a host
such as Nua is another way to run Mua code. A host adds highlight queries over this parser
(see below) and does not carry a grammar of its own.

Limits: a `with` block's entries on one line need `,` or `;` between them, and a `.name` entry
on a new line after a value reads as member access. Highlighting is by spelling, not semantic
resolution; a clean parse does not establish that the program is valid.

## Build

From the Mua repository root:

```sh
make tree-sitter
make test-tree-sitter
```

Needs the Tree-sitter CLI (tested with 0.26.11), Node.js, a C99 compiler, GNU make and Neovim
0.10 or newer. The build targets parser ABI 14 and writes `build/tree-sitter-mua/mua.so`.

## Neovim setup

```lua
local mua = vim.fn.expand('~/dev/mua') -- repository root containing the Makefile
vim.opt.runtimepath:prepend(mua .. '/tools/tree-sitter-mua')
require('mua_treesitter').setup()                    -- files named *.mua
require('mua_treesitter').setup({ extension = false }) -- parser only; set the filetype yourself
```

Mua source is Lua source, so the filetype is opt-in rather than taken from `.lua`.

## Hosts

A host language registers itself over the same library and layers its own queries:

```lua
local mua = require('mua_treesitter')
mua.setup({ extension = false })
mua.add_language('nua', { extension = 'nua' })   -- queries/nua/highlights.scm starts with `; inherits: mua`
```

GPL-3.0-or-later, as the rest of the project (`COPYING`).
