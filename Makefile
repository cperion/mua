# Mua needs LuaJIT 2.1 carrying the LuaJIT 3.0 syntax backport (see README); LUA selects it.
LUA ?= luajit
.PHONY: test
test:
	$(LUA) tests/mua.lua
	$(LUA) tests/guide.lua
