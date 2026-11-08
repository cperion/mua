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
  It controls managed scheduling, not the native media decoder's playback clock.

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

Rectangles/ovals/arcs use `x0,y0,x1,y1`, text uses `x,y`, and lines/polygons use successive
point pairs. Clip arrays use `x,y,width,height`. Image descriptions take a box or an intrinsic-size
`x,y` point and exactly one of: `source` path, tightly packed `rgba` bytes with
`image_width`/`image_height`, owned `image` capability, or owned `video` capability. Videos require
a box because their intrinsic size may not be known yet. `fit` is `fill`, `contain` (default),
`cover`, `none`, or `scale_down`; `frame` is zero for automatic source playback or a one-based
frame number. A pure description retains resource identities, not ownership: publication must
still prove that each borrowed resource outlives the canvas.

Canvas capabilities are `replace descriptions`, `set_item description`, `append description`,
`put(index,description)`, `delete id`, `truncate count`, `raise id`, `lower id`, and `count()`.
Descriptions are validated/copied before publication; duplicate identities and undersized pixel
buffers are refused. Installed records retain borrowed font strings. Replacing/truncating the
native items happens before dropping that retention. A drawing builder cannot be used after
its body completes.

## Images, animation and video

`application.resources` owns acquisitions until the application completes. `place.resources`
owns them until that mount/container completes, **not** merely until its assembly body returns.
Use a replaceable child mount to bound the lifetime of changing assets; do not continually
acquire transient frames into a long-lived application owner.

Both vocabularies provide:

| Capability | Result and lifetime |
|---|---|
| `acquire_image source` | `Ui.Acquisition` containing an owned image |
| `acquire_animation source` | `Ui.Acquisition` containing a GIF/WebP frame decoder |
| `next_frame animation` | `Ui.Acquisition` containing `{image,milliseconds}`, owned by the receiving resource vocabulary |
| `acquire_video path` | `Ui.Acquisition` containing a player; this does **not** mean its media has finished loading |
| `with_image source body`, `with_animation source body`, `with_video path body` | bounded child activities returning `Ui.Acquisition.ready(body_result)` or `unavailable(reason)` |

Programming/body errors propagate; environmental acquisition failures do not enter the body.
Partial setup errors release newly acquired native resources immediately. Resource functions
reject use after their owner completes; no destructor depends on garbage collection.

Image source records are copied from their own fields; inherited/accessor properties are not
an implicit configuration mechanism. An image source is exactly one of:

- `{path=...}` or `{bytes=...}`: encoded data. Optional `max_width`/`max_height` are fit-within
  limits, never upscaled; zero/default means no requested limit. Optional `frame` decodes just
  that one-based frame. Byte strings may contain NUL; paths may not.
- `{rgba=...,width=...,height=...,stride=...}`: straight RGBA bytes, copied. Dimensions are
  1–16384; stride defaults to `width*4`. The buffer must contain every addressed pixel.
- `{argb=...,width=...,height=...}`: tightly packed, native-endian, already-premultiplied
  `0xAARRGGBB` words, copied. The caller supplies premultiplied channel values.

An image exposes `info()` (`width`, `height`, `frames`, `format`, `loops`), `rgba(frame)`
(copied straight RGBA bytes), `argb(frame)` (an acquisition outcome for a copied premultiplied
view), and `delay(frame)` in milliseconds. Frame indexes default to one and are checked.
`format` is the native format name, or `raw` for pixel buffers without an encoded format.
Loop count zero means forever when the image is animated. These byte/metadata snapshots can
outlive the activity; the image capability cannot.

An animation accepts encoded `path`/`bytes` and optional decode dimensions, but no frame index.
Its `info()` returns intrinsic dimensions, frame count and loop count. `next_frame` advances
and copies ownership of a frame into the receiving owner; the resulting image can outlive the
decoder. Advancing the decoder is not rolled back if a later installer fails.

Image, video, label and button nodes expose `show_image(image,fit)`, `show_source(path,fit)`,
`show_frame(index)`, `play_image()` and `clear_image()`. Image/video nodes additionally expose
`show_video(player,fit)`. Labels/buttons retain BUI's intrinsic-size image presentation.

**Retained loans require an ancestor owner.** An application-owned image can be shown by its
windows; a mount-owned image can be shown by that mount's descendants. A shorter-lived or sibling
resource is refused before changing the installed image. Lexical overlap alone does not authorize
retention. Bounded `with_image`/`with_animation` activities are useful for inspection/conversion;
use placement-owned acquisitions for retained UI. Copying/spreading a resource's method table
does not copy its identity. Returning a resource directly from an installer produces a checked
alias whose loan is narrowed to that component's lifetime.

For example, inside an installer:

```mua
local result = place.resources.acquire_image {
    rgba = string.char(255, 180, 80, 255), width = 1, height = 1,
}
result {
    ready = do(image)
        local picture = place.image { width = 64, height = 64 }
        picture.show_image(image, "contain")
    end,
    unavailable(reason) = place.label(reason),
}
```

A player exposes `play`, `pause`, `seek(seconds)`, `rate(number)`, `loop(boolean)`,
`poster(path_or_nil)`, `controls(boolean)`, `state`, `time`, `duration`, `size`, and
`on_state_changed body`. Rate is 1/16–16; seek time is nonnegative and bounded to fit native
signed 64-bit nanoseconds. `size()` is an acquisition outcome for currently known presentation
size (possibly the poster before video loads); duration zero means unknown. Poster changes
explicitly damage/relayout retained borrowers, including canvases. Replaced/cleared borrowers
are not rebound by later poster changes.

`state()` and state notifications use the closed `Ui.Playback` protocol: `loading`, `playing`,
`paused`, `ended`, `failed` (all unit alternatives). Notifications snapshot the native state,
run FIFO after C returns, and are revoked by disconnect/replacement/disposal. One UI-thread
listener trampoline is shared across players. There is **no Lua image-worker callback**;
managed dispatch polls native image completion on the UI thread.

Missing compiled video backends return acquisition `unavailable`. A compiled backend can still
lack a runtime codec; lazy loading then reports `Playback.failed`, without poisoning the
application. At the pinned BUI revision, player loading uses OS movie decoders, despite the
header's broader GIF/WebP wording. Use image sources or the animation decoder for GIF/WebP;
the library does not claim that the video player supports them. Playback is muted, as in BUI.

`application.images` controls the shared loader/cache:

- `inspect {path=...}` or `{bytes=...}` returns an acquisition outcome containing header
  `width`, `height`, `frames`, and `format`. Recognition does not certify full decoding.
- `budget(bytes)` sets the decoded shared-cache budget, not a limit on all owned images.
- `threads(count)` accepts 0–64 (zero: native automatic policy). Choose it before installing
  asynchronous sources/players or prefetching; clearing the cache does not reopen configuration.
- `prefetch(path,width,height,fit)`, `clear()`, and `statistics()` manage settled cache entries.
  Statistics copy `bytes`, `budget`, `entries`, `pending`, `decoded`, `failed`, `cancelled`,
  `evicted`, and `decode_ms`; prefetch success is not promised synchronously.
- `video_backends()` returns compiled backend names, not a runtime codec guarantee.

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

The managed implementation is Mua throughout `bui/ui/`, not a Mua façade over a Lua framework.
It follows [the activity guide](designing-and-writing-mua.md) and the vocabulary/composition
patterns in `examples/lisp.mua`. Raw declarations and library loading remain in `bui.ffi`.

- `application.mua` is the composition root: it owns the exclusive integration and composes
  the driver, resource and appearance vocabularies. There is no `Application` superclass.
- `scope.mua` owns private acquisition ledgers. Each owner supplies closure-backed verbs, not
  writable `children`, `cleanups` or lifecycle fields. `with_owner` completes on every exit;
  `prepare` adopts successful acquisitions or revokes/releases only the tentative entries.
- `callbacks.mua` owns trampoline lifetimes, phase restrictions and captured native failures;
  `queue.mua` owns bounded FIFO delivery; `dispatch.mua` owns deadlines and native wakeups.
  These responsibilities have separate private state rather than one mutable application record.
- `surface.mua` supplies native-window and offscreen acquisition activities over one mounting
  engine in `mount.mua`. Control, editor, canvas and presentation capabilities compose by spread;
  overlapping names are errors, not silent overwrites by extension order.
- `widgets.mua` supplies checked property descriptions. `descriptions.mua` builds drawing data;
  `canvas.mua` consumes it. `media.mua` owns image/animation/video activities and loader policy;
  `handles.mua` checks resource identities and retained loans.

Copying a capability vocabulary shares its captured state; a new activity creates independent
state. No native pointer, destructor or callback registration becomes caller-owned merely because
its vocabulary was copied.

Native publication rechecks owner liveness after input normalization; an input accessor that
retires a mount cannot cause a subsequent write through its freed node. Dense arrays require
actual entries, not metatable-synthesized values for holes.

`tests/bui_ui_ownership.mua` tests the Mua activities without a desktop: private ledgers,
independent versus shared captures, rollback sibling revocation, multiple/nil results, narrowed
loans, cancelled delivery, synchronous-service restrictions and stale registration identities.
`tests/bui_ui.lua` covers completion, partial failure, discarded delivery, slot replacement,
independent mounts, focus during failed assembly, copied values, callbacks, timers, editors,
canvas retention and native animation. `tests/bui_ui_media.lua` covers copied pixels, strided
buffers, selected frames, independent animation frames, checked retained loans, acquisition
rollback, worker cancellation, poster refresh, deferred playback snapshots and callback errors.
Its real-video path uses the pinned BUI `tests/videos/clip.mp4` fixture. Linux without a runtime
codec verifies the failure outcome; Windows Media Foundation playback is tested with an external
deadline. `--require-video` makes missing decoding a test failure.

CTest runs headless UI/media tests and the composed example; `BUI_FFI_TEST_WINDOW=ON` adds
bounded real-window tests, and `BUI_FFI_TEST_VIDEO=ON` additionally requires working video
playback. Set `MUA_LUAJIT_EXECUTABLE` to the LuaJIT with the syntax backport required by Mua
(the same runtime used for the Lisp example); CMake checks this at configuration time.
`LUAJIT_EXECUTABLE` continues to select the raw ABI/FFI test runtime. The raw ABI suite remains separate.

Remaining design families include tree forests, complete menus and key maps, dialogs,
custom drawing/services, raster/texture activities (including media texture transfer), IME and advanced
host/GPU integration. They are not certified by constructor presence or raw FFI access. New
features must use these owners and delivery rules, rather than introduce a second runtime.
