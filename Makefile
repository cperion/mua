# Mua needs LuaJIT 2.1 carrying the LuaJIT 3.0 syntax backport (see README); LUA selects it.
LUA ?= luajit
.PHONY: test
test:
	$(LUA) tests/mua.lua
	$(LUA) tests/guide.lua
	$(LUA) tests/cli.lua
	$(LUA) tests/fmt.lua
	$(LUA) tests/fmt_do.lua

# Editor support (Neovim Tree-sitter): the grammar is Mua's; hosts such as Nua add queries over it
TREE_SITTER ?= tree-sitter
NVIM ?= nvim
TS_SOURCE := tools/tree-sitter-mua
TS_BUILD := build/tree-sitter-mua
.PHONY: tree-sitter test-tree-sitter
tree-sitter:
	mkdir -p $(TS_BUILD)/src
	cp $(TS_SOURCE)/grammar.js $(TS_BUILD)/grammar.js
	cp $(TS_SOURCE)/src/scanner.c $(TS_BUILD)/src/scanner.c
	$(TREE_SITTER) generate --abi 14 $(TS_BUILD)/grammar.js -o $(TS_BUILD)/src
	$(CC) $(CPPFLAGS) $(CFLAGS) -std=c99 -Wall -Wextra -Werror -fPIC -shared -I$(TS_BUILD)/src $(TS_BUILD)/src/parser.c $(TS_BUILD)/src/scanner.c $(LDFLAGS) -o $(TS_BUILD)/mua.so

test-tree-sitter: tree-sitter
	$(NVIM) --headless -u NONE -l $(TS_SOURCE)/tests/check.lua
