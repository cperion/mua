# BUI activities: implemented API

`bui.ui` is the managed Mua library; `bui.ffi` remains the raw C boundary. See
[bui-activities.md](bui-activities.md) for the larger design and [bui-ffi.md](bui-ffi.md)
for native builds. [The coverage inventory](bui-coverage.md) accounts for all 296 public
native functions and 48 node kinds, including deliberate policy replacements and platform
limits. The sections below describe implemented activities, not proposed methods.

Run the composed example from the repository root:

```sh
luajit mua.lua examples/bui/workbench.mua ./build/bui/libmua_bui.so
# Smaller introduction: examples/bui/activities.mua
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
`sidebar`, `scroll`, `frame`, `node_editor`, `area_header`, `menu_bar`, `popover`.
Panel/popover bodies use their native content node. Scroll bodies use one owned column;
ordinary children are never accidentally interpreted as panel header accessories or discarded
by a single-child native scroll view.

Leaf words take options and return capabilities. A string is shorthand for `{ caption = text }`.
The exception is `button options activated`: the second stage is explicitly its activation
continuation. Other controls connect with `control.connect Notify`; no empty notification
vocabulary is required for an unobserved field.

The catalog also includes labels, separators, toggles, checkboxes, radio, decorators, text,
search, hotkey, number, slider, dropdown, enum, swatch, popover, menu buttons/bars, lists, trees,
grid views, ramps, curves, normals, histograms, scrollbars, progress, meters, canvases,
textareas, image, custom, video, graph nodes and optional file browser nodes. The specialized
activities below provide their data, behavior and ownership protocols. An unavailable optional
native kind is rejected rather than replaced with a fake control; `choose_file` instead reports
an `Opening.unavailable` outcome.

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
toggle, radio and decorator values are booleans; text values are strings; swatches are four RGBA
channels; normals are signed three-component unit directions. Progress values and scrollbar
first fractions lie in `[0,1]`; meters and number/slider controls use numbers; selection controls
use integers. Dropdown/enum captions are labels. Native scalar selection codes remain zero-based;
canvas item-list indexes and ramp stop indexes are one-based.

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
View changes carry copied horizontal/vertical ranges; graphs, file choices and standalone
scrollbars have the closed protocols described below. Other native events carry `{first,second}` and raw key/pointer events additionally
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

## Menu descriptions and installation

`Ui.menu body` is a pure builder offering `item(options)`, `separator()`, and
`submenu(options)(body)`. A command has a `caption` and an `action`; optional presentation
fields are `icon`, `shortcut`, `checked`, and `enabled`. A submenu has children instead of an
action. `checked = false` differs from an omitted check indicator. Actions are retained values,
not executed while describing a menu. Returning from the builder revokes its instructions.

`menu_button.menu(descriptions)` installs a menu and returns a disconnect function. Surfaces
provide `open_menu(descriptions, options)`, `open_pie(descriptions, options)`, `close_popups()`,
and copied `popup_rows()` inspection. Placement options are `title`, `x`, and `y`; pie menus
admit at most eight entries. Native notifications enqueue actions for a later driver turn.
Replacement and disconnection revoke old registrations and cancel their queued delivery.
A failed preparation leaves the previously published menu intact.

The menu language follows [the compiler guide](writing-compilers.md), not a collection of
optional-field tests in each consumer:

```text
supplied tables / builder instructions
    → checked menu family: Command | Submenu | Separator
    → exhaustive native-lowering pass
    → owned action registrations and temporary native specifications
    → publication
```

`bui/ui/menu_descriptions.mua` owns the family and pure reading, rechecking, and writing.
Rechecking and writing are exhaustive passes; `menus.mua` supplies the native-lowering pass.
Adding a kind requires each pass to learn it. Writing gives inspectable data that can be read
back without native allocation. Publication rechecks descriptions because Lua tables and nested
lists remain mutable; nominal identity is not immutability or proof of resource liveness.

State has explicit boundaries: a reading owns its ancestor checks and total-entry budget, with
path/depth inherited into children. A lowering captures one installation's registration owner
and retained storage. Every nested list produces a separate native array; it cannot replace its
parent's output. Descriptions own no native resources. The installation activity owns rollback,
publication, registrations, and retirement.

The builder and structural input share normalization. Inputs reject cycles, depth beyond 32,
more than 10,000 total entries, unknown fields, and fabricated array holes. Presentation inputs
are copied from their own fields; metatables cannot invent actions or child lists.

`Ui.keymap body` offers `bind(combination)(action)`, and `surface.bind_keys(bindings)` returns a
disconnect function. Ctrl/Shift/Alt combinations are canonicalized. BUI has no unbind operation:
disconnection removes the action, **not the context's native reservation or key consumption**.
There are at most 64 distinct reservations per context; rebinding reuses one, and disconnecting
an old binding does not cancel its replacement.

## Collections, graph editing and container services

`Ui.forest rows` checks and copies a recursive forest. Each item has a unique string/integer
`id`, a `label`, optional `icon`, `expanded`, `marked`, dense boolean `toggles`, dense string
`values`, and `children`. Limits are 64 levels, 100,000 total items and 32 toggle columns.
`tree.replace_forest` prepares a complete replacement before publication. Tree capabilities:

- `selection()` and `item(id)` return `Selection.selected(snapshot)` or `empty()`;
- `select_item(id)` (nil clears), `rename_item(id,label)`, `item_values(id,values)`,
  `expand_item(id,bool)`, `mark_item(id,bool)`, `toggle_item(id,column,bool)`;
- `item_children(id)` returns copied selections, and `tree_rows()` returns IDs and rectangles.

Toggle columns are one-based. Tree notifications copy stable IDs and state, never item pointers.
Lists have `items()`, `mark(index,bool)`, `clear_marks()` and the shared view capabilities.
`selection_mode` is `single`, `multiple`, `extended` or `optional` for lists and trees.

`node_editor options body` accepts only direct `graph_node` children. Graph nodes are leaves,
not layout containers. `include` stages graph components under a detached editor and transfers
its children without adding an invalid layout wrapper. A graph node accepts `x`, `y`,
`graph_width`, `selected`, `active`, and `collapsed`. The editor accepts `zoom`, `pan_x`, `pan_y`.
Graph coordinates/pan are bounded to ±1,000,000; width is 40–32768 and zoom is 0.09–2.31.

`Ui.sockets body` supplies `input {caption,type,value}` and `output {caption,type}` instructions.
It produces a closed `Input`/`Output` family, rechecked at publication. Type defaults to `float`;
input values are optional numbers (boolean sockets use 0/1). Captions/type names must fit the
native 63/23-byte fields and cannot contain `|`. A node has `set_sockets`, `sockets()`,
`graph_state()`, `graph_identity()` and `graph_rectangle()`. The latter computes the visible
rectangle from graph coordinates, pan and zoom; the generic native node rectangle is not the
graph editor's visual rectangle. Identity is an opaque comparison token shared by aliases.

An editor has `nodes()`, `links()`, `set_links`, `add_node(options)`, `remove_node(node)`,
`fit_view()` and `graph_view()`. A link is `{from=node,output=1,to=node,input=1}`; socket indices
are one-based, endpoints must belong to this editor, and an input admits one link. At most
1024 sockets/node and 1024 links are accepted. Replacing sockets clears incident links rather
than silently retargeting them. Removing a node remaps surviving links before native free.
Native reordering is read back instead of treating an index as identity.

Graph `changed` notifications carry `Ui.GraphChange`: `moved`, `selection`, `input`, `collapsed`,
`links`, `deletion`, or `order`. Payloads are copied state, with opaque identities instead of
native pointers. `deletion` contains the selected node states: the application decides whether
to remove them. Querying `links()` returns live node capabilities for further editing; outward
link snapshots instead contain identity tokens. See `examples/bui/workbench.mua` for composition.

Panels have silent `expand(bool)`, `expanded()`, and `with_header installer body`. The latter
mounts header accessories independently of the collapsible body and retires them on every exit.
Panel user changes report the expanded boolean. All view-capable controls provide
`view(axis)`, `move_view(axis,fraction)` and `scroll_view(axis,units)`, where axis is `horizontal`
or `vertical`. A view snapshot has `first`, `last`, `total`, `visible`.
Standalone scrollbars add `range()` and `set_range(first,last)`; `scrolled` carries
`Ui.Scrolling.moveto(fraction)` or `units(count)`. Wiring a scrollbar to a view is explicit.

`place.link_fields {first,second,...}` links 2–64 number/slider controls in the same surface.
It returns disconnect and a group vocabulary: `values()` copies values, `set_values(array)`
sets silently, `copy()` writes a bracketed numeric vector to the clipboard, and `paste()`
returns an acquisition and notifies through ordinary changed connections. Malformed clipboard
data is unavailable without partial publication. Bind clipboard commands explicitly if wanted.
The native implicit parent-vector keyboard hook is deliberately not enabled: it copies every
sibling into a fixed-size buffer. A detached integration-owned anchor preserves Alt-linked
editing without that unsafe side effect. Relinking retires prior groups; any member's retirement
unlinks **all real peers** before native destruction. The group vocabulary expires on
disconnection. Copied functions do not forge control identity; mounting aliases retain it.

## Geometry, interaction and custom behavior

Every control has `layout(options)`, `reset_placement()`, `geometry()`, `inspect()`, `children()`
and `parent()`. Inspection returns copied kind/rectangle/child-count data; `parent()` uses
`Selection`. Layout managers are `none`, `pack`, `grid`, `place`; options include side, fill,
anchor/sticky, padding, expand, row/column/spans and absolute/relative placement. Grid row/column
coordinates are zero-based. A frame's `grid_track(axis,index,weight,minimum)` uses a one-based
track index, with axis `row` or `column`. Layout descriptions are validated before publication.

Surfaces add `interaction()`, `clear_focus()`, `pointer(x,y)`, and an `ime` vocabulary:
`start()`, `compose {result,composite,cursor,start,stop}`, `finish()`, `state()`, `composing()`.
Composition offsets are UTF-8 byte offsets, with `-1` meaning unspecified. Invalid byte splits
and reversed selections are refused. `state()` synchronizes native IME state and returns
`changed`, `enabled`, `restart`, `x`, `y`; it is not a pure query. Interaction snapshots include
cursor, hover/focus selections, modal/tooltip/popup state and rendering/animation needs.

A custom control installs `behavior {event,frame,draw,width,height}`, returning disconnect.
Replacement retires the old binding; old disconnects cannot clear a replacement. Width/height
are natural dimensions, default 160 and bounded to 1–32768.

- `event(event,Services)` is synchronous and returns `Ui.Input.consumed()` or `ignored()`.
  Kinds are `pressed`, `released`, `moved`, `left`, `wheel`, `key_pressed`, `key_released`,
  `focused`, `blurred`. Coordinates, modifiers, clicks, wheel deltas, text and keysym are copied.
- `frame(Services)` returns `Ui.Frame.next_frame()` or `finished()`. Each requested frame
  invalidates this control; continuing requests another frame.
- `draw(Paint,rectangle)` is synchronous drawing, not notification delivery. Paint is borrowed
  from the current native raster and expires on return, including exceptional return.
- Borrowed services are `request_frame(milliseconds=0)`, `invalidate()`, `cursor(name)`,
  `focused()`, and `post(notification,payload)`. They expire when the callback returns.
  `post` schedules ordinary work under the behavior's owner; it does not deliver inside C.

Custom controls also expose guarded ordinary `request_frame`, `cursor`, `focused` capabilities.
Ordinary mutation, destruction and recursive dispatch are forbidden during services/drawing.
A thrown callback error becomes the application's first fatal callback fault, not a C unwind.

## Retained dialogs and file choices

Surfaces and placement vocabularies provide:

- `open_dialog options installer completed`, where `installer(place,Finish)` returns inward
  capabilities and `Finish` supplies `accept(value)` and `cancel()`;
- `confirm {title,message,accept="OK",cancel="Cancel"} completed`;
- `choose_file {title,browser=properties} completed`.

Opening returns `Opening.opened(Dialog)` or `unavailable(reason)`. An opened dialog has
`cancel`, `content`, `input`, `render`, `size`; it is retained beyond installation, owned by the
launching activity. Completion receives `Ui.Dialog.accepted(value)` or `cancelled()`, once,
after child teardown and outside C. Closing the launching owner drops queued completion.
Failed setup never completes. Acceptance before installation publishes is an error.

Dialogs share the parent's native/headless backend, but are not implicitly OS-parent-modal.
Headless/embedded hosts present child surfaces themselves. No nested native event loop is used.
A file choice accepts copied path strings. Browser properties include `directory`, `filename`,
`button`, `search`, `bookmarks_file`, `filters`, `mode` (`open`, `save`, `directory`), `multiple`,
`show_hidden`, `filter`, `sort` (`name`, `time`, `size`), `invert`.
The browser's `result()` is `Ui.Choice.browsing()`, `accepted(paths)`, or `cancelled()`;
`location()` is copied text state, and `refresh()`, `execute()`, `cancel()` are commands.
`submitted` carries a choice snapshot. The unavailable browser outcome is tested separately
from successful native/headless installation and completion.

## Raster, typography and texture activities

`application.resources` and placement resources compose image/video resources with
`acquire_raster`, `with_raster`, `acquire_texture`, `with_texture`, `acquire_text`, `with_text`.
Acquisition uses `Acquisition.ready`/`unavailable`; bounded resource bodies have the same
completion/retirement rules as image activities. Resource identities and native IDs stay private.

A raster description is `{width,height}` (1–16384). Capabilities are `size()`, `pixels()`,
`damage()`, `invalidate()`, `with_frame(options)(body)`, `with_gpu(body)`, `gpu_state()`,
`poll_gpu()`. Pixels are copied native-endian raster bytes, not a live pointer. Pixel access is
unavailable for an active GPU target and forbidden during painting. Damage rectangles are copied.
Software pixels are top-down native `uint32_t` words `0x00RRGGBB` (RGB32, **not RGBA**).
Do not reinterpret their zero high byte as image transparency. Frame options can resize or
restrict completion to a checked `{x,y,width,height}` region.
Frame end and temporary-view expiry occur even when drawing fails.

`Paint` provides rectangle/outline/round-rectangle/circle/ellipse/line/polygon/triangle/point
painting; shadows, gradients, HSV circles and spheres; `text`, `text_run`, `image`, `mesh`,
`widget`, `widget_base`; and bounded `with_clip`, `with_view`, `with_primitive_sink` activities.
Colors are RGBA in `[0,1]`. Image source/destination boxes use x/y/width/height. Mesh vertices
have x/y/u/v and optional packed RGBA color; triangle indices are one-based. Mesh/widget clips
use min/max coordinates. A view borrows pixels and never begins/ends/frees a frame.
`with_primitive_sink` temporarily installs the raster's native primitive adapters, leaving
begin/end to the enclosing frame, and restores the previous sink on every exit. Its pooled
clip adapter intersects producer scissors (including reset) with the enclosing view; native
shallow-copy sink userdata cannot escape that clip. Producers must not retain the sink. These are synchronous UI-thread activities, not Lua worker callbacks.

Text descriptions contain `text`, optional `family`, `flags`, `size`. Prepared text exposes
`width()` and a copied `mask()` (bytes, dimensions, origin, ascent). It owns a description, not
an immortal native cache pointer: every use checks the native generation. Whitespace-only or
unavailable native runs are acquisition-unavailable. `application.typography` supplies
`available`, `measure(description)`, `ui_width(text)`, `add_font(family,flags,bytes)` and
`default_font()` (copied embedded font bytes). Font registration is global integration policy.

Textures accept copied `{width,height,rgba,stride}`, an owned `{image,frame}`, or `{video}`.
They provide `size()`, `update(x,y,pixels)`, `copy_image(image,frame)` and video-only `refresh()`.
Only one evolving texture transfer may own a video's native texture bookkeeping at a time;
competing acquisitions and manual updates are refused. A not-yet-decoded texture is an explicit
unavailable size/mesh result. Immediate painting can use live same-integration sibling resources;
retained widget/canvas presentations still require ancestry.

`resources.convert_pixels {format,bytes,width,height,first_row,rows}` copies selected rows to an
owned `{argb,width,height}` image-source value. Formats are `argb`, `nv12_601`, `nv12_709`;
NV12 dimensions must be even. Rows are one-based. No caller-generated cache key is installed.

## Embedding, windows and integration policy

`application.with_host(Services)(options)(body)` opens an offscreen surface with explicit host
capabilities. The host drives the existing `pump`, input, IME, render and pixel APIs. Queued
notifications are `request()`, `cursor(code)`, `warp(x,y)`, `write_clipboard(text)`. Synchronous
services are `wake()` (arm a later host turn), `schedule(milliseconds)`, and `read_clipboard()`
(return `Acquisition.ready(string)` or `unavailable(reason)`). Services may not mutate managed UI
or pump recursively. Keep polling on the UI thread while asynchronous media/GPU work is pending;
there is no Lua callback from a decoder thread. Services are optional, and ordinary offscreen
surfaces retain their private clipboard behavior when no host supplies one.

Surfaces expose `pixels()` as an acquisition of copied raster bytes, and `present(Raster)` for
immediate **software** native presentation on Win32. X11/Wayland window rendering uses its own
host path; an offscreen GPU raster cannot be redirected by passing another window's handle.
Those unsupported transfers return unavailable. `with_native(body)` is
an explicitly **unsafe** integration seam. The borrowed vocabulary's `handles()` exposes the
native namespace, context, roots, raster, native window and platform handle during the body.
Ordinary mutation is forbidden during this borrow. Do not retain/free pointers, replace managed
state or global hooks, or transfer them to a longer-lived/foreign-thread user. Escaped vocabulary
calls are checked; raw pointer copies cannot be made safe by a Mua wrapper.

`application.with_render_sink(Services)(body)` temporarily installs a primitive backend sink,
not a kit renderer. Optional synchronous drawing services are `begin_frame`, `clip`, `triangles`,
`lines`, `points`, `text`, `end_frame`; arguments are copied records/arrays. The body receives
`viewport(width,height)`. Sink restoration is scoped; viewport size is explicit global native
configuration, not an invented restorable query. Nested sinks restore correctly; callback faults
use the normal safe boundary. These bodies/producers must stay synchronous on the UI thread.

`application.with_keep_alive(body)` returns an acquisition and supplies `wake()`. It keeps the
native driver alive without ordinary windows while external integration work owns the activity.
The wake callback runs on the UI thread; only the native C wake function is foreign-thread safe.
The external integration must arrange wakeups and own its worker/queue lifetime. Stop/wake hooks
are cleared before Lua trampolines retire. Without keep-alive, `run` still ends when windows close.

Native windows have `manager` queries (`position`, `screen`, `pointer`, `scale`, `state`) returning
acquisitions of `{first,second}` and checked requests: `move`, `minimum`, `maximum`, `resizable`,
`set_state`, `raise`, `lower`, `focus`, `topmost`, `borderless`, `disabled`, `opacity`.
State names are `normal`, `minimized`, `hidden`, `maximized`. Unsupported host operations return
unavailable; an accepted request does not promise that the window manager honored it.
`gpu(bool)` returns an acquisition; `gpu_state()` is `Gpu.software`, `starting`, or `hardware`.
Offscreen GPU scopes use that same protocol and release attachments on all exits.

Application policy also includes `appearance()`, `theme_color(name)`, `icons()`, `icon_info(name)`,
`animations(bool)`, `slug(bool)`, `evaluate_number(expression)`, and `recent_searches` with
`enable`, `clear`, `load_best_effort`, `save_best_effort`. Theme colors, icon lookup and expressions
use acquisition outcomes. Search persistence is explicitly best-effort because the native calls
return no success indication. `images.source_info(path)` queries retained-source metadata;
`images.inspect` remains an uncached encoded-header probe.

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
- `widgets.mua` lowers checked properties to a closed `Setting` instruction family and publishes
  them through an exhaustive pass. `descriptions.mua` builds drawing data; `canvas_language.mua`
  gives checked shapes nominal identity and exhaustive writing, while `canvas.mua` lowers them
  to retained native storage. `media.mua` owns image/animation/video activities and loader policy;
  `handles.mua` checks resource identities and retained loans.
- `menu_descriptions.mua` models the closed menu language. Its pure passes and the lowering pass
  in `menus.mua` are checked against that family, independently of component capabilities.

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

`tests/bui_ui_menu_descriptions.mua` needs no BUI library: it checks kind identity, exhaustive
passes, composed operations, round trips, independent nested builders, revalidation, and refusal
boundaries. `tests/bui_ui_menus.mua` compares a pure reference projection with actual native
specifications, including nested/sibling arrays, deferred action order, rollback after partial
lowering, stale tokens, and cancellation. Collection and graphics regressions are separate.

CTest runs these regressions, headless UI/media tests and the composed example; `BUI_FFI_TEST_WINDOW=ON` adds
bounded real-window tests, and `BUI_FFI_TEST_VIDEO=ON` additionally requires working video
playback. Set `MUA_LUAJIT_EXECUTABLE` to the LuaJIT with the syntax backport required by Mua
(the same runtime used for the Lisp example); CMake checks this at configuration time.
`LUAJIT_EXECUTABLE` continues to select the raw ABI/FFI test runtime. The raw ABI suite remains separate.

The [coverage inventory](bui-coverage.md) maps every native facility to an activity, ownership
policy and regression. Its handwritten native-function ledger has a separate accounting test;
that test is explicitly not behavioral evidence. The control regression mutates, renders and
retires each ordinary catalog kind; specialized regressions cover collections, graphs, menus,
custom services, dialogs, IME, hosting and graphics. Native-window tests run on Linux and on
actual Windows binaries. Availability remains platform-dependent, particularly for codecs,
GPU/text backends and window-manager operations. No constructor count or raw escape hatch is
used as a substitute for those activity contracts.
