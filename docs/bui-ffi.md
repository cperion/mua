# BUI: the thin LuaJIT FFI boundary

`bui/cdef.lua` is a **hand-written transcription** of BUI's public C declarations.
`bui/ffi.lua` registers them with LuaJIT and loads an explicitly named native library.
There is no header compiler, generator, Python dependency, widget wrapper or component policy.
The binding is plain Lua so either LuaJIT or Mua can require it.

The source is `ppmpreetham/BUI` at `e8126cab68f1b542676e83909671bc803dedb36c`:

| Header | Surface |
|---|---|
| `kit/include/BUI_kit.h` | retained nodes, properties, layout, input, contexts, windows, images, menus, editors |
| `gpu/include/GPU_raster.h` | software/GPU rasters, text, images, textures and meshes |
| `gpu/include/GPU_backend_sink.h` | primitive render-sink callbacks |
| `api/bui_c_api.h` | small version/viewport/sink facade |

The kit draws through `BK_render` into a `BuiRaster`, **not through the render-sink facade**.
The latter is included faithfully but is not a replacement for the kit API. At this revision,
`BK_version()` reports 0.5.0 while the older `bui_get_version()` facade reports 0.1.0; the loader
checks the kit version, not the facade version.

## Build and test

The native packaging supports **Linux and Windows**, tested on x86-64. Windows builds use
**MinGW-w64 GCC** (tested with portable w64devkit); MSVC and cross-compilation are not supported
by this packaging. Both the DLL and LuaJIT must be native Windows binaries of the same bitness.
No changes to the hand-written C declarations are needed for Windows.

It needs CMake 3.24+, C/C++ compilers, and LuaJIT for the tests. Use the LuaJIT version described
in the main README when running a `.mua` program; the raw `.lua` binding also works on stock
LuaJIT 2.1.

### Linux

From this repository, with BUI checked out beside it at `../bui`:

```sh
cmake -S bui/native -B build/bui -DCMAKE_BUILD_TYPE=Release
cmake --build build/bui -j4
ctest --test-dir build/bui --output-on-failure

/path/to/patched/luajit mua.lua examples/bui/headless.mua ./build/bui/libmua_bui.so
```

### Windows / PowerShell

Put CMake, MinGW-w64 and Windows LuaJIT on the current shell's PATH. From the Mua checkout,
with BUI beside it:

```powershell
cmake -S bui/native -B build/bui -G "MinGW Makefiles" `
  -DCMAKE_MAKE_PROGRAM=make.exe -DCMAKE_BUILD_TYPE=Release `
  -DLUAJIT_EXECUTABLE=C:/path/to/luajit.exe
cmake --build build/bui -j4
ctest --test-dir build/bui --output-on-failure

C:/path/to/luajit.exe mua.lua examples/bui/headless.mua ./build/bui/mua_bui.dll
```

`make.exe` is w64devkit's GNU Make. With another MinGW distribution, use its make executable
(often `mingw32-make.exe`), or use `-G Ninja` with Ninja installed instead. To build current
upstream LuaJIT with w64devkit, run
`make -j4 HOST_SYS=Windows TARGET_SYS=Windows HOST_MSYS=1` in its source directory; the explicit
host settings select the Windows ABI and the POSIX shell supplied by w64devkit. Keep its
`lua51.dll` beside `luajit.exe`.

From WSL, use `powershell.exe -NoProfile` to run these **Windows** tools. Keep the Windows
build directory separate from the Linux one; a checkout/build under `C:\\...` also avoids
`cmd.exe`'s UNC working-directory limitation. This was tested by invoking PowerShell from WSL,
not with Wine or a Linux LuaJIT loading a PE DLL.

### Build contract

Set `-DBUI_SOURCE_DIR=/absolute/path/to/BUI` for a different checkout and
`-DLUAJIT_EXECUTABLE=/path/to/luajit` to choose the test interpreter.
BUI's optional native features keep their upstream defaults and CMake options. Its Python,
Lua 5.4, ImGui and Qt bindings, examples and reference UI build are disabled. No other Lua
runtime is linked into this bundle.

BUI supplies static libraries. The small CMake project packages their public objects into
`libmua_bui.so` on Linux or `mua_bui.dll` on Windows, keeping even symbols that no C caller
references, since FFI finds them by name. The MinGW linker exports the retained symbols and
links the GCC/C++ runtimes statically; the tested w64devkit DLL imports only Windows system
libraries. The Lua library namespace, ownership and callbacks are identical on both platforms.

It leaves the upstream checkout untouched. `headers.lock` checks the four public header hashes
at configure time after normalizing CRLF to LF, so Windows Git line-ending conversion is safe.
Other changes still fail the check and trigger reconfiguration before a rebuild.

The default tests are headless. On a desktop, configure with `-DBUI_FFI_TEST_WINDOW=ON` to also
briefly open a real native window and test presentation, frame/timer callbacks and closing it.
CTest runs the C ABI probe as a fixture and checks its exit status before Lua reads its report;
there are no shell-pipe or shell-quoting requirements.

These tests are separate from `make test`: the language itself does not require a BUI checkout
or a native build.

## Use

```lua
local ffi = require 'ffi'
local Bui = require 'bui.ffi'
local filename = ffi.os == 'Windows' and 'mua_bui.dll' or 'libmua_bui.so'
local Native = Bui.load('./build/bui/' .. filename)

local button = Native.BK_node_new('button')
assert(button ~= nil, 'could not create button')
local set = Native.BK_set_str(button, 'text', 'Hello')
Native.BK_node_free(button)
assert(set == 1)
```

`load(path)` returns the **actual FFI library namespace**, not a proxy or a table of wrappers.
C names, argument order, return codes, null pointers and ownership remain unchanged. Use normal
parenthesized calls for multi-argument C functions; they are not curried. A null pointer is
truthy in Lua: compare it with `nil`, do not use `assert(pointer)` to detect C allocation failure.

Requiring the module registers declarations but does not open a library, create resources,
install callbacks, change themes or run an event loop. Loading checks our bundle revision and
the kit's integer version. Bad paths or incompatible libraries raise ordinary Lua errors;
callers may use `pcall` at this boundary. The loader requires this bundle, not an arbitrary
shared library with similarly named exports.

Keep `Native` alive while using its resources or function pointers. LuaJIT's declaration
namespace is VM-wide: use one BUI ABI per Lua VM, and do not exchange handles with a separate
copy of BUI loaded by another language binding. `BK_*` and `BUI_*` globals remain BUI globals;
loading this module does not make theme settings, ref hooks or image-loader configuration local
to a component.

### Constants and macros

All 136 enumerators and five numeric object-like macros are available directly, for example
`Native.BK_EV_CLICK`, `Native.BK_CTRL` and `Native.BUI_KIT_VERSION`.
LuaJIT cannot declare C string constants this way, so the version string macro is exposed as
`Bui.BUI_KIT_VERSION_STRING`. `BK_version_string()` remains the real C function returning a
borrowed C string.

The function-like macros `BUI_KIT_VERSION_AT_LEAST` and `BUI_DEPRECATED` are not C symbols and
are not exposed as pretend functions. Version comparison is ordinary Lua arithmetic over the
version constants; deprecation is a C declaration annotation. Include guards are not API.

## Ownership is explicit

This boundary deliberately adds no automatic finalizers. Correct destruction order depends on
relationships that a function signature alone does not express. In particular:

- A `BKContext` borrows its root; freeing the context does not free that root. A native window
  must be destroyed before its context. Its raster is borrowed from the window, not separately
  owned by the caller.
- With node refs unset, freeing a root recursively frees its children. Do not also free each
  child or attach independent finalizers to them. `BK_node_remove` detaches; it does not free a
  ref-less child. With host refs installed, BUI's retain/release rules apply instead.
- `BK_node_set_ref` does not make a Lua object a safe `void *`. Ref hooks are process/library
  global and must be designed by the owner; the binding installs none. Tree items have their
  own host-ref ownership rules; node-tree recursion is not a general rule for every handle.
- Borrowed pointers from `BK_get_str`, `BUI_raster_pixels`, menu queries and similar APIs must
  not outlive their owner or the mutation that invalidates their storage. Copy text with
  `ffi.string` when it must be remembered.
- Retained pointers to Lua strings, arrays and other cdata do **not** keep their owners alive.
  Keep the actual objects reachable for the entire borrow. This includes callback data,
  canvas font-family strings, and images/video borrowed by nodes.
- Shutdown of the shared image loader (`BK_image_exit`) belongs to the owner of the whole
  library use, after consumers and workers no longer need their resources, not to every widget.

`mua_bui_malloc(size)` and `mua_bui_free(pointer)` are the only added allocation helpers. They
use the same C runtime as the bundled BUI. They cover the malloc/free contract of
`BK_clipboard_get` and `BKHost.clipboard_get`: a clipboard callback must return native malloc'd
UTF-8 or NULL, never a Lua string or an `ffi.new` allocation that C will attempt to free.
Use each API's own release function where one exists, such as `BK_file_dialog_free`.

## Callbacks: a raw ABI, not an event framework

Use explicit `ffi.cast` callback objects, keep them reachable, disconnect the native owner,
then call `callback:free()`. Implicit conversion of a Lua function creates a callback whose
resources cannot be explicitly reclaimed. Do not allocate a new callback per event or frame.
A copied C callback struct copies pointers, not Lua ownership.

Specific constraints:

1. **`BK_context_set_host` does not accept NULL.** To clear a headless host, pass a zeroed
   `ffi.new('BKHost[1]')`. If a window owns the host services, destroy/disconnect the window
   before replacing its context's host; otherwise native cursor/timer/render services are lost.
2. **Callbacks must run on the Lua VM's thread.** `BK_image_set_notify` is explicitly called
   from worker threads: never install a Lua FFI callback there. Keep the native wake mechanism
   or provide native-thread-safe machinery. Headless code can call `BK_image_poll` on the Lua
   thread. This binding does not invent a cross-thread dispatcher.
3. **Do not unwind arbitrary Lua errors through BUI's C stack.** Protect application handlers,
   retain an error for reporting after the native call returns, and return a valid C result.
   The same boundary should defer destruction or structural mutation that would invalidate
   objects still being used by the native input handler.
4. **Calls that can reenter Lua need a non-JIT calling boundary.** Use `jit.off` on the Lua
   function that drives input/polling/notifying setters when callbacks may occur. LuaJIT's
   automatic blacklisting can miss a callback that appears only after the call became hot.
   The binding does not disable JIT globally; the native smoke test does so explicitly.
5. **An event's pointer payload may be ephemeral.** Copy strings and values while valid rather
   than queuing raw pointers to temporary C buffers. The ABI does not encode each event's
   payload meaning; consult `BUI_kit.h`.

These are requirements on the eventual owner/activity layer, not guarantees the raw binding
can provide. `tests/bui.lua` shows a retained `BKHost.emit`, native clipboard allocation,
headless input and explicit teardown.

### Pointer-to-array arguments

Keep the original C types. Do not flatten `const float (*)[4]` to `float *` to silence an FFI
conversion failure. LuaJIT needs an explicit cast for this qualification of a nested array:

```lua
local colors = ffi.new('float[2][4]', { { 1, 0, 0, 1 }, { 0, 0, 1, 1 } })
local positions = ffi.new('float[2]', { 0, 1 })
Native.BK_ramp_set(ramp, positions, ffi.cast('const float (*)[4]', colors), 2)
```

Here `ramp` is a live ramp node; both buffers remain alive through the call. The cast does not
copy or transfer ownership.

## Validation and maintenance

`bui/native/abi_probe.c` is a test executable compiled against the **real headers**. It reports
sizes, alignments, offsets and constants. It is not a header translator or binding generator.
`tests/bui.lua` runs against the platform's own compiled report and checks:

- resolution of all 296 declared public function symbols;
- all 17 public record sizes and alignments, all 136 field offsets, and cdata field sizes;
- all 136 enum values, five numeric macros and the string macro;
- loader refusals, scalar/output-pointer calls, pointer-to-array inputs and outputs;
- callbacks carrying pointers and doubles, clipboard allocation, rendering, damage tracking,
  input dispatch, node detachment and cleanup;
- with the desktop test enabled, native window creation, presentation, callbacks and closing.

These checks do not prove every function's behavioral semantics or every signature merely by
resolving its symbol. Review the declarations against the headers; the ABI and smoke tests
provide independent checks of layout and exercised call shapes.

For an upstream change, review all affected declarations and their ownership comments, update
the native probe/tests and header lock, and rerun the checks. Bump the binding revision in both
`bridge.c` and `ffi.lua` for an incompatible bundle ABI, even if upstream reused its kit version.
Never update hashes alone to bypass the check.

The component model remains separate: see [Component patterns](component-patterns.md). This
layer supplies raw native capabilities; it does not decide their Mua activity lifetimes.
