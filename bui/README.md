# BUI for Mua

- `bui.ffi`: hand-written LuaJIT declarations and an explicit native loader. No generator,
  component policy or automatic finalizers. [Build and ownership guide](../docs/bui-ffi.md).
- `bui.ui`: activity-owned windows, mounting, capabilities and deferred interaction.
  [Implemented API and coverage](../docs/bui-ui.md), [full design](../docs/bui-activities.md).

Native builds and the managed activity tests support Linux and Windows (MinGW-w64).
`examples/bui/activities.mua` demonstrates the library; `studio.mua` remains a raw-FFI example.
