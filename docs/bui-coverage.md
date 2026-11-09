# BUI managed capability coverage

Audited against BUI `e8126cab68f1b542676e83909671bc803dedb36c`, kit 0.5.0,
and the four headers locked by `bui/native/headers.lock`. This is a **capability and
ownership inventory**, not a claim that exporting a symbol or constructing a node
proves its behavior. `bui.ffi` preserves the 296-function native interface;
`bui.ui` supplies activities rather than a second copy of that interface.

## Activities and evidence

Paths in this table are relative to `bui/ui/` and `tests/` respectively.

| Purpose | Managed implementation | Ownership/publication and behavioral evidence |
|---|---|---|
| Integrate, mount, replace and retire UI | `application.mua`, `scope.mua`, `mount.mua`, `handles.mua` | Private ledgers; detached preparation; sibling revocation before release; native roots outlive contexts. `bui_ui_ownership.mua`, `bui_ui.lua` test rollback, alias expiry, independent instances and release order. |
| Deliver events and drive time | `callbacks.mua`, `queue.mua`, `dispatch.mua` | Pooled UI-thread trampolines; monotonic registration tokens; copied FIFO batches; callback faults raised outside C; cancellation before native destruction. Core, ownership, services, media and menu regressions exercise these paths. |
| Write and compose UI instructions | Opened activity vocabularies, `examples/bui/activities.mua`, `examples/bui/workbench.mua` | `bui_ui_language.mua` tests lexical subjects, independent instances, late commands, nearest-owner resources, rollback and completion. `bui_ui_staging.mua` tests current UTF-8 boundaries, stable identity across replacement, copied upload destinations and use of the current owned texture, prepared menu snapshots, and expiry of saved instruction stages. The workbench exercises title-draft rejection, cancellation and acceptance on native/headless surfaces. |
| Compose controls and edit values | `widgets.mua`, `containers.mua` | Checked `Setting` family and exhaustive publication; native scalar selection codes; independent captions; panel/popover native bodies and an owned scroll body. `bui_ui_controls.mua` changes, renders and retires 46 catalog kinds; graph tests cover the other two. Shared checks do not substitute for the specialized tests below. |
| Arrange and inspect content | `layout.mua`, `fields.mua` | Pack/grid/place descriptions; copied hierarchy and view state; one-based grid tracks; linked-field peers unlinked before any destruction; explicit group clipboard work avoids the native fixed-buffer parent-vector hook. `bui_ui_services.mua`, `bui_ui_integration.mua` cover placement, IME geometry, field-group teardown and aliases. |
| Navigate collections | `collections.mua`, `fields.mua` | Copied forests with stable IDs; explicit native allocation ledger; clear links before free; copied selection, rename, toggle and row snapshots. `bui_ui_collections.mua` tests replacement, validation, events and retirement. Lists expose copied items and marking; view movement uses the same native scroll state. |
| Present commands | `menu_descriptions.mua`, `menus.mua` | Closed `Command`/`Submenu`/`Separator` family; exhaustive rechecking, writing and native lowering; action registrations owned separately from descriptions. `bui_ui_menu_descriptions.mua` and `bui_ui_menus.mua` compare pure interpretation with actual nested native arrays and test rollback, replacement, stale tokens and queued cancellation. |
| Edit node graphs | `graphs.mua`, `mount.mua` | Closed socket family; checked endpoints; native index lowering; opaque stable node identities; copied `GraphChange` outcomes. Graph components stage under a detached editor, then transfer direct children. Removing nodes remaps links before native free. `bui_ui_graphs.mua` covers native dragging/reordering, link preservation, socket replacement, aliases and failed preparation. |
| Draw retained scenes | `canvas.mua`, `canvas_language.mua` | Closed eight-kind shape family and closed image-source alternatives; exhaustive writing and native lowering; retained font strings, arrays and resource loans. `bui_ui_canvas_language.mua`, core and media tests cover shape interpretation, edits, publication and retained ownership. |
| Edit specialized data | `editors.mua` | Checked ramps, curves, text spans, histograms and grid colors; copied queries; UTF-8 byte boundaries; liveness rechecked before publication. Core, control and media regressions cover mutation, validation and rendering, including accessor mutation of input arrays before publication. |
| Own and present media | `media.mua` | Copied image sources; independent animation frames; retained loans require ancestry; pooled UI-thread playback listeners; loader policy belongs to the integration. `bui_ui_media.lua` covers real images, animation, playback, unavailable backends/codecs, listener faults, replacement and exact cleanup. Windows additionally requires successful MP4 decoding. |
| Paint, measure and transfer pixels | `raster.mua`, `paint_geometry.mua`, `typography.mua`, `textures.mua`, `pixels.mua`, `widget_paint.mua` | Scoped frames/views/clip/sinks; copied pixels and masks; generation-aware text cache borrows; owned textures; exclusive evolving video texture transfer; no reusable GPU IDs exposed. `bui_ui_graphics.mua` and `bui_ui_integration.mua` exercise primitives, clipping/damage, text, meshes, widget drawing, NV12 conversion, GPU attachment/release, video textures and expired capabilities. |
| Supply custom behavior | `behavior.mua`, `custom.mua` | Closed `Response`/`Preparation`/`Painting`/`NaturalSize` descriptions; exhaustive checking and lowering before installation. `bui_ui_behavior.mua` tests pure composition and independent pass output. Services tests exercise staged responses/drawing, a narrower frame vocabulary, expired stages, rejected publication preserving the old binding, replacement cancelling queued notifications, stale tokens and faults. |
| Compose input and IME | `interaction.mua`, `surface.mua` | Copied state; byte-safe composition boundaries; explicit input injection, focus, clipboard and undo. Core/services/integration tests cover native and headless paths, host services, composition and callback boundaries. |
| Complete dialogs and file choices | `dialogs.mua`, `file_browser.mua` | Retained child surface; installer and completion are different continuations; exactly-once deferred completion after teardown; destination retirement cancels delivery. `bui_ui_dialogs.mua` covers acceptance, cancellation, failed installation, component retirement and unavailable browser support, on native and headless surfaces. |
| Host and interoperate | `surface.mua`, `interop.mua`, `dispatch.mua` | Embedded hosts supply synchronous services separately from queued notifications. Scoped primitive sinks restore the previous sink and pool callbacks. Explicit unsafe native borrowing forbids ordinary mutation while borrowed. Keep-alive scopes own wake/stop-hook policy. Integration tests cover nesting, copied primitives, host clipboard/scheduling, guard failures, expiry and restoration. |
| Manage windows and appearance | `window_management.mua`, `environment.mua` | Checked manager requests, explicit unavailable outcomes, typed GPU state, theme/font/icon/search policy and number expressions. Native service tests query actual windows; integration/control tests exercise appearance and policy. Core/window/studio tests cover close, resize, idle settling and bounded frame progression. |

### All native node kinds

These are the native names, not an alternate constructor API. The public spellings
are documented in [bui-ui.md](bui-ui.md).

```text
column row split grid box panel tabs sidetabs sidebar nodeeditor graphnode areaheader
scroll scrollbar label separator progress button toggle checkbox decorator text
search hotkey number slider dropdown enum swatch popover menubutton menubar list
tree gridview ramp curve normal histogram frame radio canvas textarea image meter
custom video filebrowser
```

Notable distinctions found during the audit:

- Panel and popover content goes into their pre-existing native body; panel header
  accessories have a separate bounded mounting activity. Scroll content is grouped
  under one owned column because native scrolling displays a single child.
- Graph nodes must be direct children of a node editor, not arbitrary layout nodes.
  Native graph z-order changes also renumber links. Stable identity is not an index.
- A decorator is boolean. A scrollbar's current value is its **first** fraction;
  its scroll requests are `Scrolling.moveto` or `units`, not value-change events.
- Text/search/hotkey/textarea captions use `label`, never the storage used by `value`.
  Textarea and HTML-mode fields do not necessarily draw that metadata themselves.
- Meters accept numerical ranges; normals preserve signed unit directions.
- File-browser `directory` is a string, unlike the generic directory-selection flag.

## Native policy replacements and limits

These are deliberate ownership decisions, not hidden missing wrappers:

- Native reference hooks and node refs are not installed. Mua's scope ledger owns
  nodes; tree items use self references only for event identity. Do not combine
  managed nodes with another binding's global reference hooks.
- Removing a mount retires its owned subtree; it does not publish a reusable detached
  raw node. Graph transfer uses native reparenting internally. Native close/free are
  represented by owner retirement, not two independent public destruction verbs.
- The blocking native file-dialog helper and its result-free pair are superseded by
  owned `choose_file` completion. There is no nested managed event loop. Child dialogs
  are not an invented OS-parent-modal facility.
- `BK_image_set_notify` is never given a Lua callback. Safe driver turns poll images;
  native worker wakeups stay in C. Image cache keys are native-owned, and native image
  teardown forgets them. Arbitrary caller-chosen pixmap keys/streams are not exposed.
  External ARGB/NV12 data can be copied, converted, owned and presented.
- Low-level widget drawing is covered by the checked kit widget drawing activity;
  the legacy widget entry and C facade sink/viewport functions remain raw aliases or
  lower-level forms. The facade's version is distinct from the kit/binding versions.
- Native context-root, node-ref and custom-data getters expose implementation identity,
  not ordinary managed capabilities. `with_native` is an explicitly unsafe integration
  seam, not permission to retain/free pointers or overwrite ownership/global hooks.
- GPU, native text, file-browser compilation, codec availability and window-manager
  operations are environmental. Closed unavailable outcomes are real branches, not
  software emulation promises. Wayland does not provide arbitrary window position,
  opacity/topmost management. Direct software-raster presentation is Win32-only;
  X11/Wayland window rendering uses its host path. Offscreen GPU targets are not
  redirected by the native presentation function's window-handle argument.
- Theme, scale, loaded fonts and recent-search configuration are native process-global
  integration state. Ending an application revokes its capabilities; it does not
  invent native APIs to remove fonts or restore historical global settings.
- Native key bindings cannot be removed. Disconnecting revokes the action but retains
  its reservation/key consumption; each context has at most 64 reservations.
- Embedded hosts drive `pump`, input, rendering and presentation themselves. They must
  arrange regular UI-thread polling while asynchronous media/GPU work is outstanding.
  Synchronous host services must schedule an outer turn, never call `pump` recursively.

## Verified configurations

The revised activity suite passes **28/28 CTests on Linux** and **29/29 using
actual Windows binaries** through PowerShell. Both include bounded native-window
and composed-workbench runs. Windows additionally requires successful MP4 decoding;
the Linux installation lacks that fixture's runtime codec and verifies the failure
outcome instead. The full Mua language/guide/CLI/formatter/example suite also passes.
These results cover the pinned build and exercised behaviors, not every possible
GPU, compositor, codec or window-manager configuration. They are behavioral evidence, not a
certificate of DSL design quality or a substitute for reviewing the domain sentences.

## Native function ledger

Every public function in the locked interface is listed below. The regression checks
this handwritten inventory against `bui/cdef.lua`; that catches accounting drift,
**not behavioral correctness**. The activity table above supplies the separate
ownership and test evidence.

### Integration, configuration and identities

```text
BK_version BK_version_string BK_set_ref_hooks BK_set_scale BK_scale BK_unit
BK_set_font BK_set_theme BK_theme_name BK_theme_color BK_icon_id BK_icon_count
BK_icon_name BK_icon_list_count BK_icon_list_name BK_set_animations BK_eval_number
BK_recent_searches_enable BK_recent_searches_clear BK_recent_searches_load BK_recent_searches_save
bui_get_version bui_version_string
```

### Nodes, checked properties, layout and linked fields

```text
BK_node_new BK_node_free BK_node_type BK_node_set_ref BK_node_ref BK_node_add
BK_node_remove BK_node_child_count BK_node_child BK_node_parent BK_node_rect
BK_node_natural BK_node_invalidate BK_node_relayout BK_node_context
BK_set_num BK_set_str BK_set_color BK_set_strs BK_get_num BK_get_str BK_get_color
BK_strs_count BK_strs_get BK_link_fields BK_geom_set_manager BK_geom_manager
BK_geom_set BK_geom_get BK_frame_grid_weight
```

### Specialized editors and collections

```text
BK_ramp_count BK_ramp_get BK_ramp_set BK_ramp_active BK_ramp_evaluate
BK_ramp_set_active_color BK_curve_count BK_curve_get BK_curve_set BK_curve_evaluate
BK_histogram_set BK_gridview_set_colors BK_tree_item_new BK_tree_item_free
BK_tree_item_set_ref BK_tree_item_ref BK_tree_item_add BK_tree_item_clear
BK_tree_item_set BK_tree_item_get BK_tree_item_set_label BK_tree_item_label
BK_tree_item_child_count BK_tree_item_child BK_tree_set_roots BK_tree_selected
BK_tree_select BK_tree_row_count BK_tree_row BK_tree_row_rect BK_tree_item_set_values
BK_textarea_insert BK_textarea_delete BK_textarea_caret BK_textarea_set_caret
BK_textarea_selection BK_textarea_set_selection BK_textarea_set_spans
BK_textarea_index_at BK_textarea_see
```

### Menus, shortcuts, popups and dialogs

```text
BK_menubutton_set_items BK_open_menu BK_open_pie BK_bind BK_close_popups BK_popup_count
BK_popup BK_popup_owner BK_menu_row_count BK_menu_row_text BK_menu_row_rect BK_picker_part
BK_file_dialog BK_file_dialog_free
```

### Owned media and retained canvas

```text
BK_image_probe BK_image_probe_file BK_image_format_name BK_imbuf_decode BK_imbuf_load
BK_imbuf_from_rgba BK_imbuf_from_argb BK_imbuf_free BK_imbuf_size BK_imbuf_format
BK_imbuf_pixels BK_imbuf_delay BK_imbuf_loops BK_imbuf_rgba BK_imbuf_decode_frame
BK_imbuf_texture BK_imbuf_texture_update BK_anim_open BK_anim_next BK_anim_info BK_anim_free
BK_video_new BK_video_free BK_video_play BK_video_pause BK_video_seek BK_video_set_rate
BK_video_set_loop BK_video_set_poster BK_video_set_controls BK_video_state BK_video_time
BK_video_duration BK_video_size BK_video_set_listener BK_video_texture BK_video_backends
BK_image_set_budget BK_image_set_threads BK_image_set_notify BK_image_poll BK_image_stats
BK_image_info BK_image_prefetch BK_image_clear_cache BK_image_exit
BK_node_set_video BK_node_set_image BK_node_set_imbuf BK_node_set_image_source BK_node_set_image_frame
BK_canvas_set_item BK_canvas_add_item BK_canvas_put_item BK_canvas_truncate BK_canvas_delete
BK_canvas_raise BK_canvas_count
```

### Context, input, services and custom behavior

```text
BK_context_new BK_context_free BK_context_set_host BK_context_set_header BK_context_root
BK_render BK_needs_render BK_press BK_release BK_motion BK_wheel BK_scroll BK_key
BK_context_menu BK_ime_event BK_ime_state BK_ime_composing BK_key_release BK_button
BK_timer BK_set_pointer BK_cursor BK_hover BK_focus BK_focus_node BK_clipboard_get
BK_clipboard_set BK_modal_active BK_tooltip_visible BK_undo BK_redo BK_undo_depth BK_animating
BK_custom_set BK_custom_data BK_custom_request_frame BK_custom_set_cursor BK_custom_has_focus
```

### Windows, driving, wakeup and presentation

```text
BK_window_supported BK_window_new BK_window_free BK_window_set_callbacks BK_window_show
BK_window_close BK_window_is_open BK_window_set_title BK_window_set_size BK_window_get_size
BK_window_raster BK_window_set_gpu BK_window_gpu BK_window_frames BK_window_render_now
BK_window_timer BK_window_request_frame BK_window_cancel_timer BK_window_handle
BK_window_wm BK_window_wm_get BK_window_run BK_window_pump BK_window_quit
BK_window_set_stop_check BK_window_wake_init BK_window_wake BK_window_set_keep_alive
BUI_raster_present_native
```

### Raster, text, textures, GPU and primitive integration

```text
BUI_raster_create BUI_raster_free BUI_raster_begin_frame BUI_raster_end_frame
BUI_raster_width BUI_raster_height BUI_raster_pixels BUI_raster_damage BUI_raster_invalidate
BUI_raster_set_clip BUI_raster_fill_rect BUI_raster_frame_rect BUI_raster_round_rect
BUI_raster_circle BUI_raster_line BUI_raster_ellipse BUI_raster_polygon BUI_raster_widget
BUI_raster_widget_base BUI_pixmap_read BUI_raster_image BUI_image_forget
BUI_raster_end_frame_region BUI_raster_shadow BUI_raster_triangles BUI_raster_hsv_circle
BUI_raster_gradient BUI_raster_sphere BUI_raster_points BUI_texture_create BUI_texture_update
BUI_texture_free BUI_texture_size BUI_raster_mesh BUI_text_native BUI_raster_set_font
BUI_raster_text BUI_text_measure BUI_raster_view_size BUI_raster_view BUI_text_prepare
BUI_text_generation BUI_raster_text_run BUI_text_run_mask BUI_text_add_font BUI_text_default_font
BUI_raster_gpu_attach BUI_raster_gpu_poll BUI_raster_gpu_pending BUI_raster_gpu_release
BUI_raster_is_gpu BUI_gpu_set_default BUI_gpu_default BUI_gpu_set_slug BUI_gpu_slug
BUI_raster_sink BK_draw_widget BK_text_width GPU_backend_sink_set GPU_backend_sink_get
GPU_viewport_size_set bui_set_render_sink bui_get_render_sink bui_set_viewport
```
