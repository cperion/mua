-- Raw BUI C API for LuaJIT (and Mua). Loading owns no UI resources.
-- SPDX-License-Identifier: GPL-3.0-or-later
local ffi = require 'ffi'
ffi.cdef(require 'bui.cdef')

-- Load our pinned native bundle by explicit path; return the C namespace itself.
local function load(path)
    if type(path) ~= 'string' or path == '' then
        error('bui.ffi.load: provide the path to the native BUI library', 2)
    end
    local library = ffi.load(path)
    if library.mua_bui_binding_version() ~= 1 then
        error('bui.ffi.load: incompatible native binding version', 2)
    end
    local actual = library.BK_version()
    if actual ~= ffi.C.BUI_KIT_VERSION then
        error(('bui.ffi.load: kit version %d does not match declarations (%d)')
            :format(actual, ffi.C.BUI_KIT_VERSION), 2)
    end
    return library
end

-- String and function-like macros are not C symbols. The numeric macros are in cdef.
return { load = load, BUI_KIT_VERSION_STRING = '0.5.0' }
