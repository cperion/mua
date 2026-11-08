# BUI as a library of Mua activities

**Design contract; implementation coverage is tracked separately.** The
[implemented activity API](bui-ui.md) now has native/headless ownership, mounting, delivery,
controls, editing/drawing vocabularies, and owned images/animation/video resources. The [raw FFI boundary](bui-ffi.md) remains separate.
The original studio is a test of that boundary, not the architecture to generalize. In particular, `add(parent, kind, properties, callback)`
is not the proposed UI language.

The goal is a coherent Mua DSL for **all of BUI**, including the work around widgets:
mounting, interaction, editing, dialogs, drawing, media, hosting and completion. It must remain
possible to use a small capability without importing an application framework into domain code.

This design applies [the activity guide](designing-and-writing-mua.md) and the agreed
[component patterns](component-patterns.md). It introduces no grammar, component class,
inheritance system, global current builder or implicit reactive dependency tracking.

## 1. Organizing decision: purposes, not C functions

There are three different kinds of block:

| Block | What its body does | What completion means |
|---|---|---|
| ownership activity | uses temporary capabilities | cancels/disconnects and releases what it owns |
| assembly activity | installs children in a mounting owner | publishes the assembled subtree, or cleans up partial acquisition |
| pure builder | describes menus, drawing lists, key maps or data | returns checked, inspectable data; no native acquisition |

A container's short assembly block is **not** the lifetime of the controls inside it. Successful
assembly transfers those controls to the enclosing mounting owner. The owning activity remains
active while the event loop runs. Calling a function a builder does not excuse hidden native
allocation: live assembly and pure description have different contracts and names.

Components are ordinary functions and stateful vocabularies. They can combine native controls
with domain behavior. A component returns the capabilities its parent needs, not its entire
implementation tree. Parents wire outward continuations to inward capabilities locally.

### The sentences

The intended ownership spine is:

```mua
Ui.with_application Backend do(application)
    return application.with_window with
        title = "Counter"
        width = 420
        height = 240
    end do(window)
        window.with_content counter_panel do(counter)
            counter.increment()
            window.show()
            application.run()
        end
    end
end
```

`Backend` is explicitly supplied; it retains the loaded library. `with_application` owns native
integration. `with_window` owns a window, its context, permanent content/header roots and child
activities. `with_content` owns a mounted component. `run` dispatches until application completion;
it is not another lifetime owner. Returning from the body, a close request, cancellation, and an
error all have defined cleanup paths. A window can close and revoke its children while `run`
continues serving another window.

`with_window` returns `opened(body_result)` or `unavailable(problem)`; the caller must handle
that ordinary environmental alternative. Contract violations and unexpected body errors are
re-raised after cleanup. The sketch above returns the outcome rather than silently discarding it.

### A component, with the directions visible

```mua
local make_counter_panel = do(inputs)
    return do(Notify)
        return do(place)
            local value = inputs.initial
            local readout
            local increment = do()
                value += 1
                readout.display(tostring value)
                Notify.changed value
            end
            place.column with spacing = 8 end do(children)
                readout = children.label(tostring value)
                children.button "Increment" increment
            end
            return define
                .increment
                current = || -> value
            end
        end
    end
end

local counter_inputs = { initial = 4 }
local counter_panel = make_counter_panel counter_inputs define
    changed = value -> print("count", value)
end
```

The real functions are `inputs -> Notify -> installer`. `with_content` invokes the installer
once with a placement vocabulary and passes its returned capabilities to its own body. State
created inside the installer is fresh per mount; state intentionally captured outside it is
shared. This is ordinary closure behavior, not a new component object system.

The installer contract is small: `installer(place) -> capabilities`. Inputs and outward
protocols belong to the component factory, not to a universal component record. A simple label
needs no empty notification table. A button can take one activation continuation; an editor can
accept a vocabulary of several distinct notifications.

`place.include installer` mounts a child under the same owning component and returns the child's
capabilities. `place.column options body`, and the other containers, pass a placement vocabulary
for their own children. No current-parent global is needed. Returning from these assembly calls
adopts their successful results; it does not destroy them.

## 2. Ownership and replacement

There is one ownership tree and explicit borrows, not one finalizer per C pointer:

```text
application
  windows
    native window + input context + permanent roots
    mounted components
      child mounts and node subtrees
      connections, timers, animations and dialog activities
      resources acquired for these children
  application-owned shared assets and integration registrations
```

Rules:

- Every acquisition is registered with its owner immediately. Partial failure unwinds only
  successful acquisitions. Cleanup is deterministic and idempotent.
- Closing first prevents new work and revokes the owner's public capabilities. At a safe native
  boundary it disconnects/cancels, closes dependent popups and activities, and releases resources
  in dependency order. A stale capability fails at its call site, before reaching C.
- Dispose a native window before its context; detach/free mounted subtrees while the context is
  still valid; free the permanent roots after the context. Child owners do not independently
  finalize every descendant that BUI's recursive root destruction will already free.
- Normal managed nodes leave BUI's host refs unset. Node identity and Lua reachability live in
  the library's registration records, not arbitrary integers in `BK_node_set_ref`.
- Tree-item roots are a separate resource family. A tree widget borrows its roots; its owner
  detaches them before freeing the item forest. BUI's item/node ownership rules are not conflated.
- A resource owner must outlive its borrowers. Shared images, videos and textures belong to a
  common ancestor owner. A child cannot lend a shorter-lived resource to a surviving parent.
- Copying a capability vocabulary does not transfer ownership or duplicate state.

A named **slot** owns replaceable content. `slot.replace installer` prepares a detached child
mount, validates it, then publishes it at a safe boundary and retires the old mount. Preparation
failure preserves the old mounted subtree. This is an atomic *mount publication*, not rollback
of arbitrary application state or I/O performed by the installer. Stable components update in
place; there is no mandatory whole-tree reconciliation or virtual DOM.

Ownership states are `acquiring -> live -> closing -> closed`, with acquisition failure going
directly through cleanup. Each registration carries an owner generation. Queued work for a
retired generation cannot call a replacement that happens to reuse the same native address.

## 3. Native callbacks are a protocol, not arbitrary application calls

The studio exposed a concrete failure: a Win32 frame request without an `on_frame` callback
continually reposts itself at the pinned BUI revision, starving timers. The library must own
both halves of that protocol. Application authors must not need to discover it.

There are three callback roles; one generic `on_event` facility cannot faithfully cover them:

| Role | Runs when | Allowed result/effects |
|---|---|---|
| notification adapter | C reports a change, activation, timer or media state | snapshot data, enqueue an owned notification, return to C |
| synchronous service | C needs clipboard bytes, an input-consumed decision, or another immediate response | return the required C result under a documented restricted capability set |
| frame/draw adapter | BUI prepares or paints a frame | prepare that frame or draw the current snapshot; no general event-loop entry or lifetime mutation |

Native-originated notification continuations run **after the originating native dispatch returns**.
Their delivery is FIFO and non-reentrant. A notifying command issued during delivery appends work rather
than recursively calling a handler. Value changes are not silently coalesced; motion/frame
subscriptions can explicitly request latest-only delivery. Event values are snapshots; a query
reads current committed state, which may have advanced since an earlier queued event. Ordinary
calls between application vocabularies remain ordinary calls: the counter above calls
`Notify.changed` synchronously. The library does not silently wrap every user continuation in
a queue; each component states its own outward protocol.

Strings, coordinates and other transient payloads are copied before returning to C. Object
references become checked registrations, not queued borrowed pointers. Removed owners invalidate
pending delivery. Activity completion is terminal and delivered once after its cleanup;
interaction notifications are multi-shot and never imply completion.

### Driving the loop without replacing BUI's window host

The native driver owns `BK_window_set_stop_check`. The callback only reports pending delivery,
shutdown or a captured callback failure. `BK_window_run` then returns at its existing native
loop boundary; Lua drains pending work and performs retirement before entering it again. The
engine delivers a bounded batch before returning to native dispatch; work appended by handlers
belongs to a later batch. It never blocks with undelivered work. Nonblocking pumping is used
only when work is already runnable, not as an idle spin loop. This uses BUI's blocking wait
and window host instead of inventing a second Win32/X11 event loop.

The boundary is a native message on Win32 and a native turn on X11. The library does not promise
one Lua turn per OS event. Native modal move/resize loops can delay general application delivery;
synchronous rendering services must not depend on that delivery to finish.

Native entry functions that can call Lua are kept out of JIT compilation by the driver. Callback
trampolines catch errors, record the first failure and return a safe C result. The owning activity
then stops and unwinds outside the C stack. An arbitrary user handler cannot be preempted if it
never returns; this is a cooperative UI, not a sandbox.

`BK_image_set_notify` is a worker-thread hook, not a Lua event. The native wake mechanism stays
native; image results are polled/delivered on the UI thread. An embedded host supplies its own
native-thread-safe wake adapter. No Lua callback is installed on a foreign thread.

### Close decisions, timers and frames

- A native close request is initially vetoed, queued and delivered as `close_requested`. The
  owner's `close` capability accepts it later; a component can instead start a confirmation
  dialog. External host destruction is reported as closure and still triggers retirement.
- `after owner duration body` is a window/mount-owned, one-shot activity. The driver's
  monotonic clock owns its deadline; native timers provide idle wakeups, not the only evidence
  that time passed. The stop check also notices due deadlines during continuous input/animation.
  This matters on Win32, where posted messages can delay `WM_TIMER`. A periodic policy explicitly
  re-arms it; cancellation invalidates the registration even if a native timer was already queued.
  A headless driver supplies the same clock/wake contract, including a fake clock in tests.
- `animate owner body` owns its frame registration and pending request. Its body returns
  `next_frame` or `finished`, explicitly. A frame is never requested without its trampoline,
  and disposal cancels the activity before the trampoline can be released.
- Ordinary setters and canvas changes rely on BUI damage tracking; they do not start animation.
- A custom draw body receives a borrowed `drawing` vocabulary and current state. It may run
  several times per render for different damaged regions. It must not advance application state.
  Library capabilities reject lifetime/structural operations in drawing; Lua itself cannot
  prevent arbitrary side effects in a captured closure.

The pure scheduling state and notification queue are testable without a desktop. Platform
adapters provide dispatch/wake/clock services; they do not duplicate component behavior.

## 4. Values, commands and continuations

The defaults are deliberate:

- Initial options are checked and snapshotted at construction, not implicitly reactive.
- `current` queries; `set` changes a control silently; `change` changes it and reports the
  declared outward notification. `display` changes presentation without pretending to be user
  input. Domain commands such as `save` are supplied behavior, not inferred native events.
- Notifications say `changed`, `activated`, `submitted`, `selection_changed`, or
  `close_requested`. A button activation does not mean a save succeeded.
- UI value editing uses BUI's undo context; document undo is a separate domain capability.
  They are connected explicitly, not merged into an implicit universal transaction stack.
- Dialogs and other bounded workflows return/report a closed outcome protocol, such as
  `accepted(value)` or `cancelled`. Ordinary errors are not cancellation outcomes.

The widget descriptors are checked data: native kind, legal properties and value domains,
construction order, capabilities, event decoding, and resource borrows. Common descriptors are
composed by vocabulary spread; widget-specific operations remain in their own vocabulary. One
mounting/property engine consumes the descriptors. There is no second hand-specialized path.

A caption maps to `text` for a button and `label` for a checkbox/toggle. `text_align` is not the
numeric container `align` flag. Limits are installed before initial values, and handlers become
live only after setup commits. The DSL accepts meaningful concepts, not an unvalidated string
bag whose behavior depends on `pairs` order.

Use nominal value types where their distinction matters: colors, rectangles, text byte ranges,
and resource identity. Use closed alternatives for outcomes and source choices. Component and
capability vocabularies remain structural. Geometry explicitly distinguishes logical layout
sizes, widget units and raster-pixel drawing rectangles; text editing preserves BUI's UTF-8
**byte offsets**, rather than quietly relabeling them character indexes.

## 5. The complete vocabulary map

Coverage means every public native operation has an identified role, ownership contract and
acceptance test. It does **not** mean renaming 296 functions, or claiming the raw escape hatch
makes a missing library feature complete. Native frees become completion obligations; redundant
native entry points can implement the same capability. Internal integration hooks need not
become ordinary widget instructions.

| Domain | Activities / vocabularies | Native surface accounted for |
|---|---|---|
| Application | `with_application`, `run`, `quit`, native or embedded driver | version/ABI identity, global loop, keep-alive, stop check, wake registration, callback pools |
| Windows | `with_window`, `show`, `close`, title/size/placement, frame statistics | all `BK_window_*`, native handles, window-owned rasters, GPU selection and pending startup |
| Mounting | `with_content`, `with_header`, `include`, slots, checked inspection | node creation/attachment/detachment, root/header contexts, parent/child queries, invalidation and relayout |
| Layout | columns, rows, split, grid, boxes, panels, tabs, side tabs/sidebar, scrolling | retained layout kinds and their properties; pack/grid/place frames, weights, spans, anchors and requested sizes |
| Controls | labels, separators, buttons, toggles, checkboxes, radio, decorators, meters/progress | common visibility/enabled/caption/icon state; activation and value protocols; Blender/HTML appearance |
| Fields | text, search, hotkey, number, slider, dropdown and enum | typed values, bounds/precision, options, vector-field linking, submit/browse/change, number expression evaluation |
| Collections | lists, trees, grid views, tree-item forests and column data | selection, expansion, rename, toggles, row/item inspection, preview colors, scrolling and reveal |
| Editors | textarea editing, ramps, curves, normals, histograms, node editor and graph nodes | byte-range edits/selections/spans, evaluation/sampling, color stops, bins, specialized editor properties |
| Menus | pure menu/key-map builders, owned menu bindings, popovers, menu bars, pie menus | menu specs/submenus, shortcuts, actions, popup ownership/closing and row inspection |
| Dialogs | owned child dialog activities; file choice and confirmation outcomes | filebrowser widget, filters/results, file-dialog allocation/free; modal state, without nested application dispatch |
| Drawing | pure drawing lists; `with_raster`, paint/frame/clip activities | every raster primitive, gradients, shadows, text, image drawing, damage, pixel views, subviews and native presentation |
| Canvas | retained items plus replaceable drawing-list publication | all canvas item kinds, append/replace/put/truncate/delete/reorder, clipping and borrowed media |
| Custom controls | event decisions, frame preparation, draw snapshots | the complete custom class protocol, cursor, focus, natural size and frame scheduling |
| Images | inspect, `with_image`, source-backed display, prefetch/cache policy | probes, synchronous/file decode, frame decode, pixel conversions, imbuf lifetime, cache stats/budget/threads/poll/shutdown |
| Animation/video | `with_animation`, owned decoded frames, `with_video`, playback vocabulary | animation looping/delays; video state/time/rate/seek/loop/poster/controls/listeners and backend availability |
| GPU resources | `with_texture`, upload/update, meshes, GPU attachment | texture lifetime, vertex/index buffers, pixmap formats/keys/streams, image-cache forgetting, GPU/Slug controls |
| Typography/theme | application look vocabulary, font registration, scoped prepared-text access | theme colors, scale/unit/font, icons, text measurement/runs/masks/generation, font bytes and default font |
| Input/host services | injected input, focus/hover/cursor, clipboard, IME, toolkit timers | all context input functions, precise scroll, pointer/buttons/keys, composition state and native host services |
| Editing/inspection | UI undo/redo, popup/picker inspection, recent-search storage | undo depths, tooltip/modal/popup state, picker parts, explicit recent-search load/save/clear/enable |
| Interoperation | exclusive host registrations and scoped native borrows | host/ref hooks, primitive `BuiGpuSink` and viewport facade, raster sink, low-level widget drawing and allocator seam |

The registered kit includes kinds not enumerated in the header's introductory comment:
`split`, `sidebar`, `nodeeditor`, `graphnode`, `areaheader`, and optional `filebrowser` must not
be lost by treating that comment as the complete widget catalog. Area headers belong to the
window/header and editor composition vocabularies.

Backend availability is queried and reported, not faked: no video decoder, file browser or GPU
must become an explicit unsupported/unavailable outcome. The primitive render sink remains a
separate integration capability; it is not the kit renderer.

## 6. Resource-specific contracts

- **Drawing:** a frame owns begin/end and its clip/font context. A raster view borrows its parent
  and is never passed to the raster free function. Pixel access is a scoped borrow or an explicit
  owned copy. A prepared text run is valid only for its documented native cache generation;
  the text capability re-prepares from its retained description when that generation changes.
- **Media:** decoded animation frames are individually owned. A video/imbuf outlives every node,
  canvas item or texture operation borrowing it. A video texture update may replace the native
  texture ID; the capability owns that evolving ID, not a stale number exposed to callers.
- **Menus and shortcuts:** Lua actions are pinned registrations. Where a C `fn/data` pair is
  available, it dispatches through that registration. Host-ref hooks are never globally installed
  merely to make an arbitrary Lua value fit in a `void *`.
- **Clipboard:** reads copy and free native buffers; clipboard service callbacks allocate in
  BUI's runtime. A Lua string or `ffi.new` buffer is never transferred to C's `free`.
- **Globals:** themes, kit scale/font, image policy, search history and several hooks are truly
  native globals. The application owns them exclusively. The DSL does not promise independent
  per-window themes or concurrent incompatible BUI runtimes. Host-supplied ref hooks require
  exclusive integration ownership and remain installed until all their users are gone.
- **Escape hatch:** scoped access to raw C handles is explicitly unsafe interoperation. It has
  an owner/borrow contract; it is not an alternate implementation of ordinary widget features.

A retained dialog started by an event is owned by the launching component/window, not by the
short callback invocation. Its outcome is delivered after teardown. File choice uses this
protocol with BUI's filebrowser; the blocking native helper is only an explicitly synchronous
integration operation outside the application dispatch loop. No hidden nested `run` is allowed.

## 7. Implementation boundaries and proof obligations

Modules follow these feature vocabularies, not generic `models/`, `controllers/`, or `wrappers/`
folders. Each feature supplies descriptors, specialized operations and tests to the same mounting
and delivery engine. The raw `bui.ffi` module stays raw. A high-level `bui.ui` vocabulary assembles
the activities; it does not become a second C declaration source or a giant forwarding table.

The native-surface inventory must classify **every** declared function and every registered
widget kind as a managed capability, an activity's implementation/completion operation, or an
explicit integration operation. Each entry points to a test. This inventory is a maintenance
check, not a generator. Feature groups are not considered complete because one demo uses them.

Required scenarios include:

1. Two instances with independent state; intentional sharing; parent-to-child wiring tested
   without native rendering.
2. Partial mount failure, slot replacement failure, stale capabilities, queued events after
   disposal, close during notification, and exactly-once dialog completion.
3. Idle frames stop; one-shot timers fire once; animation completes/cancels; no frame request
   without its registration; resize and input remain responsive on Windows and Linux.
4. Callback errors surface after C returns; transient text survives copying; synchronous services
   return valid values; paint cannot destroy its owner; foreign-thread Lua entry is refused.
5. Context/root/window ordering; tree forests; menu/shortcut action retention; image/video/texture
   borrows; prepared-text generation changes; clipboard allocation across the Windows CRT seam.
6. Native, headless and embedded drivers use the same component/mounting behavior. Optional
   backend absence produces the documented outcome. ABI probes remain independent of DSL tests.

The studio regression already checks idle, resize, theme/exposure events, a button-driven timed
job and closing with an external process deadline on both supported platforms. That is evidence
for the native boundary, not proof of this entire design map. The managed library's own
`bui_ui` tests and [API coverage notes](bui-ui.md) identify what is implemented.

> **Owners bound the work. Vocabularies express capabilities. Parents connect continuations.
> Builders describe only where a description is useful. The driver makes native interaction safe.**
