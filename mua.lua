-- The `mua` command: luajit mua.lua [options] file.lua [args]   (see mua/cli.lua)
local here = arg and arg[0] and arg[0]:match('^(.*)/[^/]*$') or '.'
package.path = here .. '/?.lua;' .. here .. '/?/init.lua;' .. package.path
local argv = {}
for i = 1, #arg do argv[i] = arg[i] end
os.exit(require('mua.cli').main(argv))
