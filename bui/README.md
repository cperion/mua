# BUI for Mua

- `bui.ffi`: hand-written LuaJIT declarations and an explicit native loader. No generator,
  component policy or automatic finalizers. [Build and ownership guide](../docs/bui-ffi.md).
- `bui.ui`: implemented in Mua throughout `bui/ui/`, with activity-owned windows,
  closure-backed capabilities, vocabulary composition and deferred interaction.
  [Implemented API and coverage](../docs/bui-ui.md), [full design](../docs/bui-activities.md).

Native builds and the managed activity tests support Linux and Windows (MinGW-w64).
The managed tests require Mua's LuaJIT syntax backport; select it with CMake's
`MUA_LUAJIT_EXECUTABLE`. Raw ABI/FFI tests use `LUAJIT_EXECUTABLE` separately.
`examples/bui/activities.mua` demonstrates the library; `studio.mua` remains a raw-FFI example.
