# BUI for Mua

- `bui.ffi`: hand-written LuaJIT declarations and an explicit native loader. No generator,
  component policy or automatic finalizers. [Build and ownership guide](../docs/bui-ffi.md).
- `bui.ui`: implemented in Mua throughout `bui/ui/`, with activity-owned windows,
  closure-backed capabilities, vocabulary composition and deferred interaction.
  [Implemented API](../docs/bui-ui.md), [capability/ownership inventory](../docs/bui-coverage.md),
  [full design](../docs/bui-activities.md).

Native builds and the managed activity tests support Linux and Windows (MinGW-w64).
The managed tests require Mua's LuaJIT syntax backport; select it with CMake's
`MUA_LUAJIT_EXECUTABLE`. Raw ABI/FFI tests use `LUAJIT_EXECUTABLE` separately.
`examples/bui/activities.mua` introduces composition; `examples/bui/workbench.mua` combines
collections, graph editing, menus, file completion and custom drawing in a reusable component.
Both support `--headless` and bounded native `--smoke` runs. `studio.mua` remains a raw-FFI example.
