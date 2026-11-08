-- Hand-transcribed public C declarations from ppmpreetham/BUI at
-- e8126cab68f1b542676e83909671bc803dedb36c. Keep C names, types and ownership.
-- Sources: GPU_backend_sink.h, GPU_raster.h, BUI_kit.h, bui_c_api.h.
-- No preprocessing, header parser, generated wrappers or component policy.
-- SPDX-License-Identifier: GPL-3.0-or-later
return [[
/* GPU_backend_sink.h */
typedef struct BuiGpuSink {
    void *user;
    void (*begin_frame)(void *user, int viewport_w, int viewport_h);
    void (*scissor)(void *user, int x, int y, int w, int h);
    void (*triangles)(void *user, const float (*coords)[2], const float (*colors)[4], int count);
    void (*lines)(void *user, const float (*coords)[2], const float (*colors)[4], int count);
    void (*points)(void *user, const float (*coords)[2], const float (*colors)[4], int count, float size);
    void (*text)(void *user, float x, float y, const char *text, float size, const float rgba[4]);
    void (*end_frame)(void *user);
} BuiGpuSink;
void GPU_backend_sink_set(const BuiGpuSink *sink);
const BuiGpuSink *GPU_backend_sink_get(void);
void GPU_viewport_size_set(int width, int height);

/* GPU_raster.h; size_t and fixed-width integers are LuaJIT built-in types. */
typedef struct BuiRaster BuiRaster;
enum { BUI_FONT_BOLD = 1 << 0, BUI_FONT_ITALIC = 1 << 1, BUI_FONT_UNDERLINE = 1 << 2 };
BuiRaster *BUI_raster_create(int width, int height);
void BUI_raster_free(BuiRaster *r);
void BUI_raster_begin_frame(BuiRaster *r, int width, int height);
void BUI_raster_end_frame(BuiRaster *r);
int BUI_raster_width(const BuiRaster *r);
int BUI_raster_height(const BuiRaster *r);
const uint32_t *BUI_raster_pixels(const BuiRaster *r);
int BUI_raster_damage(const BuiRaster *r, const int (**r_rects)[4]);
void BUI_raster_invalidate(BuiRaster *r);
void BUI_raster_set_clip(BuiRaster *r, int x, int y, int w, int h);
void BUI_raster_fill_rect(BuiRaster *r, float x, float y, float w, float h, const float rgba[4]);
void BUI_raster_frame_rect(BuiRaster *r, float x, float y, float w, float h, float thickness,
                         const float rgba[4]);
void BUI_raster_round_rect(BuiRaster *r, float x, float y, float w, float h, float radius,
                         const float rgba[4]);
void BUI_raster_circle(BuiRaster *r, float cx, float cy, float radius, float line_width,
                     const float rgba[4]);
void BUI_raster_line(BuiRaster *r, float x1, float y1, float x2, float y2, float width,
                   const float rgba[4]);
void BUI_raster_ellipse(BuiRaster *r, float cx, float cy, float rx, float ry, float line_width,
                      const float rgba[4]);
void BUI_raster_polygon(BuiRaster *r, const float (*points)[2], int n, const float rgba[4]);
enum {
    BUI_CORNER_TOP_LEFT = 1 << 0, BUI_CORNER_TOP_RIGHT = 1 << 1,
    BUI_CORNER_BOTTOM_RIGHT = 1 << 2, BUI_CORNER_BOTTOM_LEFT = 1 << 3, BUI_CORNER_ALL = 15
};
void BUI_raster_widget(BuiRaster *r, float x, float y, float w, float h, float radius, int corners,
                       const float inner_top[4], const float inner_bottom[4], const float outline[4],
                       float outline_width, const float emboss[4]);
typedef struct BuiWidgetBase {
    float rect[4];
    float rad, radi;
    int corners;
    float inner1[4], inner2[4], outline[4], emboss[4];
    int shade_horizontal;
    int alpha_checker;
    float pixelsize;
} BuiWidgetBase;
void BUI_raster_widget_base(BuiRaster *r, const BuiWidgetBase *params);
typedef struct BuiPixmap {
    const uint32_t *px;
    int w, h;
    uint64_t key;
    int format;
    uint64_t stream;
} BuiPixmap;
enum { BUI_PIXMAP_ARGB = 0, BUI_PIXMAP_NV12_BT601 = 1, BUI_PIXMAP_NV12_BT709 = 2 };
enum { BUI_IMAGE_NEAREST = 1 << 0 };
void BUI_pixmap_read(const BuiPixmap *img, int y0, int rows, uint32_t *dst);
void BUI_raster_image(BuiRaster *r, float x, float y, float w, float h, const BuiPixmap *img,
                      const float src[4], float alpha, int flags);
void BUI_image_forget(uint64_t key);
static const int BUI_IMAGE_ATLAS_MAX = 2047;
void BUI_raster_end_frame_region(BuiRaster *r, int x, int y, int w, int h);
void BUI_raster_shadow(BuiRaster *r, float x, float y, float w, float h, float radius,
                       float size, float alpha);
void BUI_raster_triangles(BuiRaster *r, const float (*coords)[2], const float (*colors)[4], int count);
void BUI_raster_hsv_circle(BuiRaster *r, float cx, float cy, float radius, float value);
void BUI_raster_gradient(BuiRaster *r, float x, float y, float w, float h, const float tl[4],
                         const float tr[4], const float br[4], const float bl[4]);
void BUI_raster_sphere(BuiRaster *r, float cx, float cy, float radius, const float light[3],
                       const float rgba[4]);
void BUI_raster_points(BuiRaster *r, const float (*coords)[2], const float (*colors)[4],
                       int count, float size);
int BUI_texture_create(int w, int h, const void *rgba, int pitch);
int BUI_texture_update(int tex, int x, int y, int w, int h, const void *rgba, int pitch);
void BUI_texture_free(int tex);
int BUI_texture_size(int tex, int *r_w, int *r_h);
typedef struct BuiMeshVertex {
    float x, y;
    float u, v;
    uint32_t col;
} BuiMeshVertex;
enum { BUI_MESH_INDEX32 = 1 << 0, BUI_MESH_NEAREST = 1 << 1 };
void BUI_raster_mesh(BuiRaster *r, const BuiMeshVertex *vtx, int n_vtx, const void *idx, int n_idx,
                     int flags, int tex, const float clip[4], float ox, float oy);
int BUI_text_native(void);
void BUI_raster_set_font(BuiRaster *r, const char *family, int flags);
int BUI_raster_text(BuiRaster *r, float x, float y, const char *utf8, int len, float size,
                    const float rgba[4]);
int BUI_text_measure(const char *family, int flags, float size, const char *utf8, int len,
                     float *r_width);
size_t BUI_raster_view_size(void);
void BUI_raster_view(const BuiRaster *src, BuiRaster *dst, int x0, int y0, int x1, int y1);
typedef struct BuiTextRun BuiTextRun;
const BuiTextRun *BUI_text_prepare(const char *family, int flags, float size, const char *utf8,
                                  int len, float *r_width);
unsigned BUI_text_generation(void);
void BUI_raster_text_run(BuiRaster *r, float x, float y, const BuiTextRun *run, const float rgba[4]);
const uint8_t *BUI_text_run_mask(const BuiTextRun *run, int *r_w, int *r_h, int *r_ox, int *r_ascent);
int BUI_text_add_font(const char *family, int flags, const void *data, int len);
const void *BUI_text_default_font(int *r_len);
typedef struct BuiGpuX11Window {
    void *display;
    unsigned long window;
} BuiGpuX11Window;
int BUI_raster_gpu_attach(BuiRaster *r, void *window_handle, int wait);
int BUI_raster_gpu_poll(BuiRaster *r);
int BUI_raster_gpu_pending(const BuiRaster *r);
void BUI_raster_gpu_release(BuiRaster *r);
int BUI_raster_is_gpu(const BuiRaster *r);
void BUI_gpu_set_default(int on);
int BUI_gpu_default(void);
void BUI_gpu_set_slug(int on);
int BUI_gpu_slug(void);
const BuiGpuSink *BUI_raster_sink(BuiRaster *r);
int BUI_raster_present_native(BuiRaster *r, void *window_handle, int full);

/* BUI_kit.h */
static const int BUI_KIT_VERSION_MAJOR = 0;
static const int BUI_KIT_VERSION_MINOR = 5;
static const int BUI_KIT_VERSION_PATCH = 0;
static const int BUI_KIT_VERSION = 500;
int BK_version(void);
const char *BK_version_string(void);
typedef struct BKNode BKNode;
typedef struct BKContext BKContext;
typedef struct BKTreeItem BKTreeItem;
enum { BK_SHIFT = 1, BK_CTRL = 2, BK_ALT = 4, BK_BUTTON1 = 8, BK_BUTTON2 = 16, BK_BUTTON3 = 32 };
enum {
    BK_CURSOR_DEFAULT = 0, BK_CURSOR_EW, BK_CURSOR_NS, BK_CURSOR_TEXT, BK_CURSOR_CROSSHAIR,
    BK_CURSOR_HAND, BK_CURSOR_MOVE, BK_CURSOR_NONE, BK_CURSOR_NESW, BK_CURSOR_NWSE,
    BK_CURSOR_NOT_ALLOWED, BK_CURSOR_WAIT, BK_CURSOR_PROGRESS
};
enum {
    BK_EV_CHANGE = 1, BK_EV_CLICK, BK_EV_CALL, BK_EV_RENAME, BK_EV_ACTIVATE, BK_EV_TOGGLE,
    BK_EV_BROWSE, BK_EV_PRESS, BK_EV_RELEASE, BK_EV_DOUBLE, BK_EV_MOTION, BK_EV_ENTER,
    BK_EV_LEAVE, BK_EV_KEY, BK_EV_WHEEL, BK_EV_SUBMIT, BK_EV_VIEW, BK_EV_SCROLL,
    BK_EV_CONFIGURE, BK_EV_KEYRELEASE
};
typedef struct BKHost {
    void *data;
    void (*request)(void *data);
    void (*set_cursor)(void *data, int cursor);
    void (*warp)(void *data, int x, int y);
    char *(*clipboard_get)(void *data);
    void (*clipboard_set)(void *data, const char *text);
    void (*schedule)(void *data, int ms, int timer);
    void (*emit)(void *data, BKNode *node, int kind, void *ref, double a, double b);
} BKHost;
void BK_set_ref_hooks(void (*retain)(void *ref), void (*release)(void *ref));
void BK_set_scale(float scale);
float BK_scale(void);
int BK_unit(void);
void BK_set_font(const char *family);
int BK_set_theme(const char *name);
const char *BK_theme_name(void);
int BK_theme_color(const char *key, float r_rgba[4]);
int BK_icon_id(const char *name);
int BK_icon_count(void);
const char *BK_icon_name(int id);
int BK_icon_list_count(void);
const char *BK_icon_list_name(int i);
BKNode *BK_node_new(const char *type);
void BK_node_free(BKNode *node);
const char *BK_node_type(const BKNode *node);
void BK_node_set_ref(BKNode *node, void *ref);
void *BK_node_ref(const BKNode *node);
int BK_node_add(BKNode *parent, BKNode *child, int index);
void BK_node_remove(BKNode *parent, BKNode *child);
int BK_node_child_count(const BKNode *node);
BKNode *BK_node_child(const BKNode *node, int i);
BKNode *BK_node_parent(const BKNode *node);
void BK_node_rect(const BKNode *node, int r_rect[4]);
void BK_node_natural(BKNode *node, int r_size[2]);
void BK_node_invalidate(BKNode *node);
void BK_node_relayout(BKNode *node);
int BK_set_num(BKNode *node, const char *key, double value);
int BK_set_str(BKNode *node, const char *key, const char *value);
int BK_set_color(BKNode *node, const char *key, const float rgba[4]);
int BK_set_strs(BKNode *node, const char *key, const char *const *values, int n);
double BK_get_num(BKNode *node, const char *key);
const char *BK_get_str(BKNode *node, const char *key);
int BK_get_color(BKNode *node, const char *key, float r_rgba[4]);
int BK_strs_count(BKNode *node, const char *key);
const char *BK_strs_get(BKNode *node, const char *key, int i);
void BK_link_fields(BKNode *const *fields, int n);
int BK_ramp_count(BKNode *ramp);
void BK_ramp_get(BKNode *ramp, int i, float *r_pos, float r_rgba[4]);
void BK_ramp_set(BKNode *ramp, const float *pos, const float (*rgba)[4], int n);
int BK_ramp_active(BKNode *ramp);
void BK_ramp_evaluate(BKNode *ramp, float t, float r_rgba[4]);
int BK_curve_count(BKNode *curve, int channel);
void BK_curve_get(BKNode *curve, int channel, int i, float r_xy[2]);
void BK_curve_set(BKNode *curve, int channel, const float (*xy)[2], int n);
float BK_curve_evaluate(BKNode *curve, int channel, float x);
void BK_ramp_set_active_color(BKNode *ramp, const float rgba[4]);
void BK_histogram_set(BKNode *hist, const float *bins, int n, int channels);
void BK_gridview_set_colors(BKNode *grid, const float (*colors)[4], int n);
BKTreeItem *BK_tree_item_new(const char *label, int icon);
void BK_tree_item_free(BKTreeItem *item);
void BK_tree_item_set_ref(BKTreeItem *item, void *ref);
void *BK_tree_item_ref(const BKTreeItem *item);
void BK_tree_item_add(BKTreeItem *parent, BKTreeItem *child);
void BK_tree_item_clear(BKTreeItem *parent);
void BK_tree_item_set(BKTreeItem *item, const char *key, double value);
double BK_tree_item_get(const BKTreeItem *item, const char *key);
void BK_tree_item_set_label(BKTreeItem *item, const char *label);
const char *BK_tree_item_label(const BKTreeItem *item);
int BK_tree_item_child_count(const BKTreeItem *item);
BKTreeItem *BK_tree_item_child(const BKTreeItem *item, int i);
void BK_tree_set_roots(BKNode *tree, BKTreeItem *const *roots, int n);
BKTreeItem *BK_tree_selected(BKNode *tree);
void BK_tree_select(BKNode *tree, BKTreeItem *item);
int BK_tree_row_count(BKNode *tree);
BKTreeItem *BK_tree_row(BKNode *tree, int row);
void BK_tree_row_rect(BKNode *tree, int row, int r_rect[4]);
typedef struct BKMenuSpec {
    const char *text;
    int icon;
    const char *shortcut;
    int checked;
    int enabled;
    void *ref;
    const struct BKMenuSpec *sub;
    int nsub;
    void (*fn)(void *data);
    void *data;
} BKMenuSpec;
void BK_menubutton_set_items(BKNode *button, const BKMenuSpec *items, int n);
void BK_open_menu(BKContext *ctx, BKNode *owner, const BKMenuSpec *items, int n,
                  const char *title, int at_x, int at_y);
void BK_open_pie(BKContext *ctx, const BKMenuSpec *items, int n, const char *title);
enum { BK_GEOM_NONE = 0, BK_GEOM_PACK, BK_GEOM_GRID, BK_GEOM_PLACE };
enum { BK_ANCHOR_N = 1, BK_ANCHOR_S = 2, BK_ANCHOR_W = 4, BK_ANCHOR_E = 8 };
void BK_geom_set_manager(BKNode *child, int manager);
int BK_geom_manager(const BKNode *child);
void BK_geom_set(BKNode *child, const char *key, double value);
double BK_geom_get(const BKNode *child, const char *key);
void BK_frame_grid_weight(BKNode *frame, int column_axis, int index, double weight, int minsize);
typedef struct BKImBuf BKImBuf;
enum {
    BK_IMAGE_NONE = 0, BK_IMAGE_PNG, BK_IMAGE_JPEG, BK_IMAGE_WEBP, BK_IMAGE_GIF, BK_IMAGE_BMP,
    BK_IMAGE_TGA, BK_IMAGE_QOI, BK_IMAGE_HDR, BK_IMAGE_PNM, BK_IMAGE_SVG, BK_IMAGE_VIDEO
};
enum { BK_FIT_FILL = 0, BK_FIT_CONTAIN, BK_FIT_COVER, BK_FIT_NONE, BK_FIT_SCALE_DOWN };
typedef struct BKImageInfo { int format; int width, height, frames; } BKImageInfo;
int BK_image_probe(const void *data, size_t len, BKImageInfo *r_info);
int BK_image_probe_file(const char *path, BKImageInfo *r_info);
const char *BK_image_format_name(int format);
BKImBuf *BK_imbuf_decode(const void *data, size_t len, int max_w, int max_h);
BKImBuf *BK_imbuf_load(const char *path, int max_w, int max_h);
BKImBuf *BK_imbuf_from_rgba(const unsigned char *rgba, int w, int h, int stride);
BKImBuf *BK_imbuf_from_argb(const uint32_t *argb, int w, int h);
void BK_imbuf_free(BKImBuf *ib);
int BK_imbuf_size(const BKImBuf *ib, int *r_w, int *r_h);
int BK_imbuf_format(const BKImBuf *ib);
const uint32_t *BK_imbuf_pixels(const BKImBuf *ib, int frame);
int BK_imbuf_delay(const BKImBuf *ib, int frame);
int BK_imbuf_loops(const BKImBuf *ib);
int BK_imbuf_rgba(const BKImBuf *ib, int frame, unsigned char *dst);
BKImBuf *BK_imbuf_decode_frame(const void *data, size_t len, int frame, int max_w, int max_h);
int BK_imbuf_texture(const BKImBuf *ib, int frame);
int BK_imbuf_texture_update(const BKImBuf *ib, int frame, int tex);
typedef struct BKAnim BKAnim;
BKAnim *BK_anim_open(const void *data, size_t len, int max_w, int max_h);
BKImBuf *BK_anim_next(BKAnim *anim, int *r_delay_ms);
int BK_anim_info(const BKAnim *anim, int *r_w, int *r_h, int *r_loops);
void BK_anim_free(BKAnim *anim);
typedef struct BKVideo BKVideo;
enum { BK_VIDEO_LOADING = 0, BK_VIDEO_PLAYING, BK_VIDEO_PAUSED, BK_VIDEO_ENDED, BK_VIDEO_ERROR };
BKVideo *BK_video_new(const char *src);
void BK_video_free(BKVideo *v);
void BK_video_play(BKVideo *v);
void BK_video_pause(BKVideo *v);
void BK_video_seek(BKVideo *v, double seconds);
void BK_video_set_rate(BKVideo *v, double rate);
void BK_video_set_loop(BKVideo *v, int loop);
void BK_video_set_poster(BKVideo *v, const char *src);
void BK_video_set_controls(BKVideo *v, int on);
int BK_video_state(const BKVideo *v);
double BK_video_time(const BKVideo *v);
double BK_video_duration(const BKVideo *v);
int BK_video_size(const BKVideo *v, int *r_w, int *r_h);
void BK_video_set_listener(BKVideo *v, void (*fn)(BKVideo *v, int state, void *data), void *data);
int BK_video_texture(BKVideo *v, int tex, int max_w, int max_h);
void BK_node_set_video(BKNode *node, BKVideo *v, int fit);
const char *BK_video_backends(void);
typedef struct BKImageStats {
    size_t bytes, budget;
    int entries, pending;
    int decoded, failed, cancelled, evicted;
    double decode_ms;
} BKImageStats;
void BK_image_set_budget(size_t bytes);
void BK_image_set_threads(int n);
void BK_image_set_notify(void (*notify)(void *data), void *data);
int BK_image_poll(void);
void BK_image_stats(BKImageStats *r_stats);
int BK_image_info(const char *src, BKImageInfo *r_info);
void BK_image_prefetch(const char *src, int w, int h, int fit);
void BK_image_clear_cache(void);
void BK_image_exit(void);
enum {
    BK_ITEM_RECT, BK_ITEM_OVAL, BK_ITEM_LINE, BK_ITEM_POLYGON, BK_ITEM_TEXT, BK_ITEM_ARC,
    BK_ITEM_IMAGE, BK_ITEM_ROUNDRECT
};
typedef struct BKCanvasItem {
    int id, type;
    const float *coords;
    int ncoords;
    float fill[4], outline[4];
    float width, radius, size;
    float start, extent;
    const char *text;
    int anchor;
    const unsigned char *rgba;
    int iw, ih;
    int hidden;
    int text_flags;
    int clip_on;
    float clip[4];
    const char *family;
    const BKImBuf *imbuf;
    const char *src;
    int fit;
    int frame;
    BKVideo *video;
} BKCanvasItem;
void BK_canvas_set_item(BKNode *canvas, const BKCanvasItem *item);
void BK_canvas_add_item(BKNode *canvas, const BKCanvasItem *item);
void BK_canvas_put_item(BKNode *canvas, int index, const BKCanvasItem *item);
void BK_canvas_truncate(BKNode *canvas, int count);
void BK_canvas_delete(BKNode *canvas, int id);
void BK_canvas_raise(BKNode *canvas, int id, int to_top);
int BK_canvas_count(BKNode *canvas);
void BK_node_set_image(BKNode *node, const unsigned char *rgba, int w, int h);
void BK_node_set_imbuf(BKNode *node, const BKImBuf *ib);
void BK_node_set_image_source(BKNode *node, const char *src, int fit);
void BK_node_set_image_frame(BKNode *node, int frame);
enum {
    BK_CUSTOM_PRESS = 1, BK_CUSTOM_RELEASE, BK_CUSTOM_MOTION, BK_CUSTOM_LEAVE, BK_CUSTOM_WHEEL,
    BK_CUSTOM_KEY, BK_CUSTOM_KEYUP, BK_CUSTOM_FOCUS, BK_CUSTOM_BLUR
};
typedef struct BKCustomEvent {
    int type;
    float x, y;
    int button;
    int mods;
    int clicks;
    float wheel_x;
    float wheel_y;
    const char *text;
    const char *keysym;
} BKCustomEvent;
typedef struct BKCustomClass {
    int (*event)(void *data, BKNode *node, const BKCustomEvent *e);
    void (*frame)(void *data, BKNode *node);
    void (*draw)(void *data, BKNode *node, BuiRaster *r, const int rect[4]);
    void (*free)(void *data, BKNode *node);
    int natural_w, natural_h;
} BKCustomClass;
int BK_custom_set(BKNode *node, const BKCustomClass *cls, void *data);
void *BK_custom_data(BKNode *node);
void BK_custom_request_frame(BKNode *node, int ms);
void BK_custom_set_cursor(BKNode *node, int cursor);
int BK_custom_has_focus(BKNode *node);
BKContext *BK_node_context(const BKNode *node);
void BK_textarea_insert(BKNode *n, int offset, const char *text);
void BK_textarea_delete(BKNode *n, int start, int end);
int BK_textarea_caret(BKNode *n);
void BK_textarea_set_caret(BKNode *n, int offset);
int BK_textarea_selection(BKNode *n, int *r_start, int *r_end);
void BK_textarea_set_selection(BKNode *n, int start, int end);
typedef struct BKTextSpan {
    int start, end;
    float fg[4], bg[4];
    int has_fg, has_bg;
} BKTextSpan;
void BK_textarea_set_spans(BKNode *n, const BKTextSpan *spans, int count);
int BK_textarea_index_at(BKNode *n, int x, int y);
void BK_textarea_see(BKNode *n, int offset);
void BK_tree_item_set_values(BKTreeItem *item, const char *const *values, int n);
int BK_undo(BKContext *ctx);
int BK_redo(BKContext *ctx);
int BK_undo_depth(BKContext *ctx, int *r_redo);
int BK_animating(BKContext *ctx);
void BK_set_animations(int enabled);
BKContext *BK_context_new(BKNode *root);
void BK_context_free(BKContext *ctx);
void BK_context_set_host(BKContext *ctx, const BKHost *host);
void BK_context_set_header(BKContext *ctx, BKNode *header);
BKNode *BK_context_root(BKContext *ctx);
int BK_render(BKContext *ctx, BuiRaster *r, int w, int h, int full);
int BK_needs_render(BKContext *ctx);
int BK_press(BKContext *ctx, int x, int y, int mods);
int BK_release(BKContext *ctx, int x, int y, int mods);
int BK_motion(BKContext *ctx, int x, int y, int mods);
int BK_wheel(BKContext *ctx, int x, int y, int delta, int mods);
int BK_scroll(BKContext *ctx, int x, int y, float dx, float dy, int mods);
int BK_key(BKContext *ctx, const char *text, const char *keysym, int mods);
int BK_context_menu(BKContext *ctx, int x, int y, int mods);
typedef struct BKImeEvent {
    const char *result;
    const char *composite;
    int cursor_pos;
    int sel_start, sel_end;
} BKImeEvent;
enum { BK_IME_COMPOSITION_START = 0, BK_IME_COMPOSITION, BK_IME_COMPOSITION_END };
int BK_ime_event(BKContext *ctx, int type, const BKImeEvent *e);
typedef struct BKImeState {
    int enabled;
    int restart;
    int x, y;
} BKImeState;
int BK_ime_state(BKContext *ctx, BKImeState *state);
int BK_ime_composing(BKContext *ctx);
int BK_key_release(BKContext *ctx, const char *keysym, int mods);
int BK_button(BKContext *ctx, int x, int y, int button, int release, int mods);
void BK_timer(BKContext *ctx, int timer);
void BK_bind(BKContext *ctx, const char *combo, void *ref);
void BK_close_popups(BKContext *ctx);
void BK_set_pointer(BKContext *ctx, int x, int y);
int BK_cursor(BKContext *ctx);
BKNode *BK_hover(BKContext *ctx);
BKNode *BK_focus(BKContext *ctx);
void BK_focus_node(BKContext *ctx, BKNode *n);
char *BK_clipboard_get(BKContext *ctx);
void BK_clipboard_set(BKContext *ctx, const char *text);
int BK_modal_active(BKContext *ctx);
int BK_tooltip_visible(BKContext *ctx);
int BK_popup_count(BKContext *ctx);
BKNode *BK_popup(BKContext *ctx, int i);
BKNode *BK_popup_owner(BKContext *ctx, int i);
int BK_menu_row_count(BKNode *menu);
const char *BK_menu_row_text(BKNode *menu, int i);
void BK_menu_row_rect(BKNode *menu, int i, int r_rect[4]);
BKNode *BK_picker_part(BKNode *picker, const char *name);
typedef struct BKWindow BKWindow;
typedef struct BKWindowCallbacks {
    void *data;
    void (*on_timer)(void *data, BKWindow *win, int id);
    int (*on_close)(void *data, BKWindow *win);
    void (*on_frame)(void *data, BKWindow *win);
} BKWindowCallbacks;
int BK_window_supported(void);
BKWindow *BK_window_new(BKContext *ctx, const char *title, int width, int height);
void BK_window_free(BKWindow *win);
void BK_window_set_callbacks(BKWindow *win, const BKWindowCallbacks *cb);
void BK_window_show(BKWindow *win);
void BK_window_close(BKWindow *win);
int BK_window_is_open(BKWindow *win);
void BK_window_set_title(BKWindow *win, const char *title);
void BK_window_set_size(BKWindow *win, int width, int height);
void BK_window_get_size(BKWindow *win, int *r_width, int *r_height);
BuiRaster *BK_window_raster(BKWindow *win);
void BK_window_set_gpu(BKWindow *win, int on);
int BK_window_gpu(BKWindow *win);
int BK_window_frames(BKWindow *win);
void BK_window_render_now(BKWindow *win);
int BK_window_timer(BKWindow *win, int ms);
void BK_window_request_frame(BKWindow *win, int vsync);
void BK_window_cancel_timer(BKWindow *win, int id);
void *BK_window_handle(BKWindow *win);
void BK_window_wm(BKWindow *win, const char *key, double a, double b);
int BK_window_wm_get(BKWindow *win, const char *key, double *r_a, double *r_b);
void BK_window_run(void);
int BK_window_pump(void);
void BK_window_quit(void);
void BK_window_set_stop_check(int (*stop)(void));
int BK_window_wake_init(void (*cb)(void));
void BK_window_wake(void);
void BK_window_set_keep_alive(int on);
enum {
    BK_WIDGET_BUTTON = 1, BK_WIDGET_TOGGLE, BK_WIDGET_CHECKBOX, BK_WIDGET_RADIO, BK_WIDGET_NUMBER,
    BK_WIDGET_SLIDER, BK_WIDGET_TEXT, BK_WIDGET_MENU, BK_WIDGET_PULLDOWN, BK_WIDGET_MENU_ITEM,
    BK_WIDGET_LIST_ITEM, BK_WIDGET_SWATCH, BK_WIDGET_PROGRESS, BK_WIDGET_TAB, BK_WIDGET_PANEL_HEADER,
    BK_WIDGET_DISCLOSURE, BK_WIDGET_MENU_BACK, BK_WIDGET_TOOLTIP_BACK, BK_WIDGET_SEPARATOR,
    BK_WIDGET_LABEL, BK_WIDGET_ARROW, BK_WIDGET_BOX
};
enum {
    BK_WS_HOVER = 1 << 0, BK_WS_PRESSED = 1 << 1, BK_WS_SELECTED = 1 << 2, BK_WS_DISABLED = 1 << 3,
    BK_WS_EDITING = 1 << 4, BK_WS_HOVER_LEFT = 1 << 5, BK_WS_HOVER_RIGHT = 1 << 6,
    BK_WS_MIXED = 1 << 7, BK_WS_FLAT = 1 << 8, BK_WS_OPEN = 1 << 9
};
enum { BK_CORNERS_ALL = 15 };
typedef struct BKWidgetDraw {
    int kind, state, corners;
    int align;
    float rect[4];
    float clip[4];
    float text_rect[4];
    float value;
    float color[4];
    float aux[4];
    const char *text;
    const char *text2;
} BKWidgetDraw;
void BK_draw_widget(BuiRaster *r, const BKWidgetDraw *w);
float BK_text_width(const char *s, int len);
int BK_eval_number(const char *expr, double *r_value);
int BK_file_dialog(const char *title, int mode, const char *dir, const char *file,
                   const char *const *filters, int nfilters, int multiple, char ***r_paths);
void BK_file_dialog_free(char **paths);
void BK_recent_searches_enable(int enabled);
void BK_recent_searches_clear(void);
void BK_recent_searches_load(const char *path);
void BK_recent_searches_save(const char *path);

/* bui_c_api.h: the primitive sink seam, NOT the kit's renderer. */
void bui_get_version(int *r_major, int *r_minor, int *r_patch);
const char *bui_version_string(void);
void bui_set_render_sink(const BuiGpuSink *sink);
const BuiGpuSink *bui_get_render_sink(void);
void bui_set_viewport(int width, int height);

/* Our shared-library packaging/allocator seam; no widget wrappers. */
int mua_bui_binding_version(void);
void *mua_bui_malloc(size_t size);
void mua_bui_free(void *pointer);
]]
