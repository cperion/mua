# BUI activities: implemented API

`bui.ui` is the managed Mua library; `bui.ffi` remains the raw C boundary. See
[bui-activities.md](bui-activities.md) for the larger design and [bui-ffi.md](bui-ffi.md)
for native builds. **The complete design map is not yet complete implementation coverage.**
The sections below describe working code, not proposed methods.

Run the composed example from the repository root:

```sh
luajit mua.lua examples/bui/activities.mua ./build/bui/libmua_bui.so
# Windows: use ./build/bui/mua_bui.dll instead.
# --headless renders without a desktop; --smoke closes the native window automatically.
```

The Mua CLI now installs its module searcher for the invocation, so `require "bui.ui"`
works normally. A plain Lua embedding host installs `require('mua.init').searcher()` in
`package.loaders` before requiring Mua modules; `tests/bui_ui.lua` demonstrates this.

## Ownership spine

```mua
local Ui = require "bui.ui"
local Native = require("bui.ffi").load "./build/bui/libmua_bui.so"

Ui.with_application Native do(application)
    application.gpu_default false
    return application.with_window { title = "Hello", width = 480, height = 240 } do(window)
        window.with_content do(place)
            place.label "An activity owns this UI."
            place.button "Close" window.close
        end do()
            window.show
            application.run
        end
    end {
        opened() = nil,
        unavailable = reason -> print(reason),
    }
end
```

- `with_application Native body` owns the single native integration, child scopes and callbacks.
  BUI's global hooks, theme, scale and image subsystem cannot belong to concurrent applications
  in the same Lua VM. Closing releases registrations/resources; it does not restore global
  theme/font settings to an invented previous configuration. One native namespace per library
  code identity remains pinned for the Lua VM lifetime: BUI exposes no window-host shutdown,
  and Win32 window classes retain DLL procedure addresses even after visible windows close.
  This does not retain disposed UI trees or Lua callbacks.
- `application.with_window options body` and `with_surface options body` return
  `Ui.Opening.opened(body_result)` or `unavailable(reason)`. A surface is headless but uses
  exactly the same context, mounting, editing, input and notification engine.
- `window.with_content installer body` and `with_header installer body` mount for the body
  lifetime. Each region admits one active mount. Window closure can revoke it earlier.
- An installer is `place -> capabilities`. It creates fresh private state in ordinary closures.
  Returning from the installer **does not dispose its children**. Returning from the enclosing
  content activity does. Returned functions are lifetime-checked; arbitrary returned user data
  is not turned into a proxy or sandbox.
- `place.include installer` adopts a child mount and returns its capabilities. `place.slot options`
  returns `replace installer` and `clear`. Replacement prepares a detached mount first; failed
  preparation preserves the old mount. Arbitrary installer I/O/state changes are not rolled back.

Cleanup revokes the entire owner subtree, disconnects registrations, and releases children
before parent resources. Native contexts outlive all mounted node destruction; windows are
freed before their contexts, and contexts before permanent roots. Cleanup continues after a
cleanup error. The original body error takes precedence over secondary cleanup failures.

## Placement and controls

Containers take options then an assembly body: `place.column options do(children) ... end`.
The body receives that container's placement vocabulary. The container's returned capabilities
refer to the live container; its children are adopted rather than released at the assembly exit.

Available container words: `column`, `row`, `split`, `grid`, `box`, `panel`, `tabs`, `side_tabs`,
`sidebar`, `scroll`, `frame`, `node_editor`, `graph_node`, `area_header`.

Leaf words take options and return capabilities. A string is shorthand for `{ caption = text }`.
The exception is `button options activated`: the second stage is explicitly its activation
continuation. Other controls connect with `control.connect Notify`; no empty notification
vocabulary is required for an unobserved field.

The catalog also includes labels, separators, toggles, checkboxes, radio, decorators, text,
search, hotkey, number, slider, dropdown, enum, swatch, popover, menu buttons/bars, lists, trees,
grid views, ramps, curves, normals, histograms, scrollbars, progress, meters, canvases,
textareas, image, custom, video and optional file browser nodes. **Having a constructor does
not imply that all specialized APIs for that native kind are implemented.** An unavailable
optional native kind is rejected rather than replaced with a fake control.

All controls have:

| Capability | Contract |
|---|---|
| `configure properties` | validate all entries before applying; limits precede initial values |
| `display caption`, `caption()` | presentation text, independent of a field's value |
| `rectangle()`, `natural_size()` | owned geometry snapshots; no C pointer escapes |
| `focus()` | focus now when published; defer a staging node's focus until publication |
| `invalidate()` | damage scheduling, not an animation request |
| `connect Notify` | replace the outward protocol; return idempotent disconnect |

Value controls additionally have `current()`, `set value` (silent), and `change value`
(notifying). Programmatic `change` emits one snapshot even when the value is unchanged; it is
not an undo transaction. Native user editing retains BUI's native undo behavior. Checkbox,
toggle and radio values are booleans; text values are strings; swatches are four RGBA channels;
progress/meter values are fractions; numeric/selection controls use numbers. Native scalar
selection codes remain zero-based; canvas item-list indexes and ramp stop indexes are one-based.

Properties are checked data, not arbitrary native setter names. Common options include:

- `caption`, `text`, `label`, `description`, `placeholder`, `suffix`, `icon`/`icon_on` names;
- `visible`, `enabled`, `bold`, `fill`, `integer`, `live`, `events` and other native flags as
  **booleans**, never numeric truthiness;
- `minimum`, `maximum`, `step`, `precision`, `value`, `default`;
- `padding`, `spacing`, `weight`, `width`, `height`, `height_units`, `font_scale`;
- `items`, `headers`, `groups`, `icons` as dense string arrays;
- `color`, `bg`, `text_color` as dense four-channel arrays in `[0,1]`;
- `text_align` as `left`, `center` or `right`; container `align` is a separate boolean.

`width`/`height` are requested raster-pixel dimensions. `height_units` is BUI widget units.
Window sizes use BUI's native logical window dimensions; window DPI handling may update BUI's
process-global scale. This release does not pretend those units or per-window scales coincide.

## Delivery, timers and frames

`Notify` accepts named functions: `changed`, `activated`, `submitted`, `browse_requested`,
`renamed`, `toggled`, `configured`, `view_changed`, `scrolled`, `pressed`, `released`,
`double_clicked`, `moved`, `entered`, `left`, `key_pressed`, `key_released`, and `wheel`.
Value changes carry owned value snapshots; configuration carries `{x,y,width,height}`.
Other native events currently carry `{first,second}` and raw key/pointer events additionally
carry a **copied** `detail` string. No ephemeral native event pointer is exposed.

Native notifications are queued until C returns. Delivery is FIFO in bounded batches; newly
appended work belongs to the next batch. Disconnecting or retiring an owner invalidates queued
notifications for it. Ordinary application-to-application vocabulary calls remain synchronous
unless the component explicitly chooses another protocol.

- `application.run()` owns blocking dispatch until all native windows close or `quit()` is called.
- `application.pump()` performs nonblocking native dispatch and one notification batch; use this
  from a host's outer event loop. It must not be called recursively from a handler.
- `window.after milliseconds body` and `place.after milliseconds body` return idempotent cancel.
  Completion/cancellation removes the timer owner. Monotonic deadlines remain authoritative even
  while posted Win32 messages delay `WM_TIMER`.
- `window.animate body` and `place.animate body` return cancel. Each body returns
  `Ui.Frame.next_frame()` or `finished()`. The registered native frame callback always exists
  before a request. Ordinary property/canvas changes use damage, never this animation protocol.
- `Ui.using_clock now` supplies an activity vocabulary with an injected monotonic seconds
  function, useful for deterministic headless tests. Backwards/nonfinite time is rejected.

Callbacks catch errors and return safe native results. The first callback error is fatal to
that application and is raised after C returns; subsequent capability calls cannot resume it.
Notification-body errors propagate normally, with the enclosing activities owning cleanup.
Only library native-entry prototypes disable JIT; the library does not globally disable JIT.

## Surface services

Windows and headless surfaces expose `render`, `resize(width,height)`, `size`, `close`,
`with_content`, `with_header`, timers, `undo`, `redo`, `undo_depth`, `close_popups`, and clipboard
`read`/`write`. Clipboard reads return `Ui.Acquisition.ready(text)` or `unavailable(reason)`;
headless clipboards are surface-local. Native clipboard buffers are copied and freed using
BUI's allocator, including on Windows.

Native windows also support `show`, `title text`, `frames`, animation and
`on_close_requested handler`. The default accepts close requests after native dispatch returns;
a supplied handler must eventually call `close` if it wants to accept. Headless surfaces require
explicit rendering/pumping and cannot be shown or animated.

`surface.input` offers `press(x,y,modifiers)`, `release`, `motion`, `wheel(x,y,delta,modifiers)`,
`scroll(x,y,horizontal,vertical,modifiers)`, `button(x,y,button,release,modifiers)`,
`context_menu(x,y,modifiers)`, `key(text,keysym,modifiers)` and `key_release(keysym,modifiers)`.
These are synchronous input injections; their notifications are still deferred. Modifier/button
codes are BUI's published codes. Application `theme`, `scale`, `font`, `gpu_default` change the
corresponding global policy; `statistics()` reports live managed registration counts.

## Canvas descriptions

`Ui.drawing body` collects pure descriptions using `rectangle`, `oval`, `line`, `polygon`,
`text`, `arc`, `image`, and `round_rectangle`. Each takes a table with `coordinates` and optional
`id` (default: declaration order), `fill`, `outline`, `width`, `radius`, `size`, `text`, `family`,
`text_flags`, `anchor`, `hidden`, `clip`, `start` and `extent` where applicable.

Rectangles/ovals/arcs/images use `x0,y0,x1,y1`, text uses `x,y`, and lines/polygons use successive
point pairs. Clip arrays use `x,y,width,height`. Image descriptions require exactly one `source`
path or tightly packed `rgba` byte string with `image_width`/`image_height`; `fit` is `fill`,
`contain`, `cover`, `none`, or `scale_down`.

Canvas capabilities are `replace descriptions`, `set_item description`, `append description`,
`put(index,description)`, `delete id`, `truncate count`, `raise id`, `lower id`, and `count()`.
Descriptions are validated/copied before publication; duplicate identities and undersized pixel
buffers are refused. Installed records retain borrowed font strings. Replacing/truncating the
native items happens before dropping that retention. A drawing builder cannot be used after
its body completes.

## Specialized editors

- Ramp: `stops`, `set_stops`, `sample(position)`, `active_stop`, `select_stop(index)`,
  `set_active_color`. Stops are `{position,color}` records; 2–32 stops are accepted.
- Curve: `points(channel)`, `set_points(channel,points)`, `sample(channel,position)`;
  2–64 `{x,y}` points, native channels 0–3. Change notifications snapshot the active channel.
- Textarea: `insert(offset,text)`, `delete(start,stop)`, `caret`, `move_caret`, `select(start,stop)`,
  `selection`, `index_at(x,y)`, `reveal(offset)`, `set_spans`. Offsets are UTF-8 **bytes**,
  zero-based, with an exclusive stop; splitting a multibyte sequence is rejected. `selection()`
  returns `Ui.Selection.selected({start,stop})` or `empty()`. Spans optionally carry `foreground`
  and `background` RGBA arrays.
- Histogram: `set_bins channels`, 1–3 equally sized channels, each with 2–65536 normalized bins.
  The edge interleaves channels as BUI expects; a single bin is refused because native drawing
  divides by `bin_count - 1`.
- Grid view: `set_colors colors`, a dense RGBA array.

## Implementation and verification

`bui/ui.mua` owns the Mua protocols and activity vocabulary; `descriptions.mua` owns pure drawing
assembly. `scope.lua` and `queue.lua` are native-independent ownership/delivery machinery.
`application.lua` owns native dispatch; `mount.lua` is the single mounting engine;
`widgets.lua` supplies checked property descriptions; specialized modules extend that engine.

`tests/bui_ui.lua` covers completion, partial failure, discarded delivery, slot replacement,
independent mounts, focus during failed assembly, copied values, callbacks, timers, editors,
canvas retention and native animation. CTest runs headless UI tests and the composed example;
`BUI_FFI_TEST_WINDOW=ON` adds bounded real-window tests. The raw ABI suite remains separate.

Remaining design families include managed media assets/playback, tree forests, complete menus
and key maps, dialogs, custom drawing/services, raster/texture activities, IME and advanced
host/GPU integration. They are not certified by constructor presence or raw FFI access. New
features must use these owners and delivery rules, rather than introduce a second runtime.
