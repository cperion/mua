/* Independent ABI measurements from the real headers, not from the Lua declarations.
 * This executable reports data for tests; it does not generate bindings.
 * SPDX-License-Identifier: GPL-3.0-or-later */
#include <stddef.h>
#include <stdio.h>
#include "BUI_kit.h"
#include "bui_c_api.h"

#define TYPE(name) printf("type\t%s\t%zu\t%zu\n", #name, sizeof(name), _Alignof(name))
#define FIELD(record, member) printf("field\t%s\t%s\t%zu\t%zu\n", #record, #member, \
    offsetof(record, member), sizeof(((record *)0)->member))
#define CONSTANT(name) printf("constant\t%s\t%lld\n", #name, (long long)(name))

int main(void)
{
    TYPE(BuiGpuSink);
    FIELD(BuiGpuSink, user); FIELD(BuiGpuSink, begin_frame); FIELD(BuiGpuSink, scissor);
    FIELD(BuiGpuSink, triangles); FIELD(BuiGpuSink, lines); FIELD(BuiGpuSink, points);
    FIELD(BuiGpuSink, text); FIELD(BuiGpuSink, end_frame);
    TYPE(BuiWidgetBase);
    FIELD(BuiWidgetBase, rect); FIELD(BuiWidgetBase, rad); FIELD(BuiWidgetBase, radi);
    FIELD(BuiWidgetBase, corners); FIELD(BuiWidgetBase, inner1); FIELD(BuiWidgetBase, inner2);
    FIELD(BuiWidgetBase, outline); FIELD(BuiWidgetBase, emboss);
    FIELD(BuiWidgetBase, shade_horizontal); FIELD(BuiWidgetBase, alpha_checker);
    FIELD(BuiWidgetBase, pixelsize);
    TYPE(BuiPixmap);
    FIELD(BuiPixmap, px); FIELD(BuiPixmap, w); FIELD(BuiPixmap, h);
    FIELD(BuiPixmap, key); FIELD(BuiPixmap, format); FIELD(BuiPixmap, stream);
    TYPE(BuiMeshVertex);
    FIELD(BuiMeshVertex, x); FIELD(BuiMeshVertex, y); FIELD(BuiMeshVertex, u);
    FIELD(BuiMeshVertex, v); FIELD(BuiMeshVertex, col);
    TYPE(BuiGpuX11Window);
    FIELD(BuiGpuX11Window, display); FIELD(BuiGpuX11Window, window);
    TYPE(BKHost);
    FIELD(BKHost, data); FIELD(BKHost, request); FIELD(BKHost, set_cursor); FIELD(BKHost, warp);
    FIELD(BKHost, clipboard_get); FIELD(BKHost, clipboard_set); FIELD(BKHost, schedule);
    FIELD(BKHost, emit);
    TYPE(BKMenuSpec);
    FIELD(BKMenuSpec, text); FIELD(BKMenuSpec, icon); FIELD(BKMenuSpec, shortcut);
    FIELD(BKMenuSpec, checked); FIELD(BKMenuSpec, enabled); FIELD(BKMenuSpec, ref);
    FIELD(BKMenuSpec, sub); FIELD(BKMenuSpec, nsub); FIELD(BKMenuSpec, fn); FIELD(BKMenuSpec, data);
    TYPE(BKImageInfo);
    FIELD(BKImageInfo, format); FIELD(BKImageInfo, width); FIELD(BKImageInfo, height);
    FIELD(BKImageInfo, frames);
    TYPE(BKImageStats);
    FIELD(BKImageStats, bytes); FIELD(BKImageStats, budget); FIELD(BKImageStats, entries);
    FIELD(BKImageStats, pending); FIELD(BKImageStats, decoded); FIELD(BKImageStats, failed);
    FIELD(BKImageStats, cancelled); FIELD(BKImageStats, evicted); FIELD(BKImageStats, decode_ms);
    TYPE(BKCanvasItem);
    FIELD(BKCanvasItem, id); FIELD(BKCanvasItem, type); FIELD(BKCanvasItem, coords);
    FIELD(BKCanvasItem, ncoords); FIELD(BKCanvasItem, fill); FIELD(BKCanvasItem, outline);
    FIELD(BKCanvasItem, width); FIELD(BKCanvasItem, radius); FIELD(BKCanvasItem, size);
    FIELD(BKCanvasItem, start); FIELD(BKCanvasItem, extent); FIELD(BKCanvasItem, text);
    FIELD(BKCanvasItem, anchor); FIELD(BKCanvasItem, rgba); FIELD(BKCanvasItem, iw);
    FIELD(BKCanvasItem, ih); FIELD(BKCanvasItem, hidden); FIELD(BKCanvasItem, text_flags);
    FIELD(BKCanvasItem, clip_on); FIELD(BKCanvasItem, clip); FIELD(BKCanvasItem, family);
    FIELD(BKCanvasItem, imbuf); FIELD(BKCanvasItem, src); FIELD(BKCanvasItem, fit);
    FIELD(BKCanvasItem, frame); FIELD(BKCanvasItem, video);
    TYPE(BKCustomEvent);
    FIELD(BKCustomEvent, type); FIELD(BKCustomEvent, x); FIELD(BKCustomEvent, y);
    FIELD(BKCustomEvent, button); FIELD(BKCustomEvent, mods); FIELD(BKCustomEvent, clicks);
    FIELD(BKCustomEvent, wheel_x); FIELD(BKCustomEvent, wheel_y);
    FIELD(BKCustomEvent, text); FIELD(BKCustomEvent, keysym);
    TYPE(BKCustomClass);
    FIELD(BKCustomClass, event); FIELD(BKCustomClass, frame); FIELD(BKCustomClass, draw);
    FIELD(BKCustomClass, free); FIELD(BKCustomClass, natural_w); FIELD(BKCustomClass, natural_h);
    TYPE(BKTextSpan);
    FIELD(BKTextSpan, start); FIELD(BKTextSpan, end); FIELD(BKTextSpan, fg);
    FIELD(BKTextSpan, bg); FIELD(BKTextSpan, has_fg); FIELD(BKTextSpan, has_bg);
    TYPE(BKImeEvent);
    FIELD(BKImeEvent, result); FIELD(BKImeEvent, composite); FIELD(BKImeEvent, cursor_pos);
    FIELD(BKImeEvent, sel_start); FIELD(BKImeEvent, sel_end);
    TYPE(BKImeState);
    FIELD(BKImeState, enabled); FIELD(BKImeState, restart); FIELD(BKImeState, x); FIELD(BKImeState, y);
    TYPE(BKWindowCallbacks);
    FIELD(BKWindowCallbacks, data); FIELD(BKWindowCallbacks, on_timer);
    FIELD(BKWindowCallbacks, on_close); FIELD(BKWindowCallbacks, on_frame);
    TYPE(BKWidgetDraw);
    FIELD(BKWidgetDraw, kind); FIELD(BKWidgetDraw, state); FIELD(BKWidgetDraw, corners);
    FIELD(BKWidgetDraw, align); FIELD(BKWidgetDraw, rect); FIELD(BKWidgetDraw, clip);
    FIELD(BKWidgetDraw, text_rect); FIELD(BKWidgetDraw, value); FIELD(BKWidgetDraw, color);
    FIELD(BKWidgetDraw, aux); FIELD(BKWidgetDraw, text); FIELD(BKWidgetDraw, text2);

    CONSTANT(BUI_FONT_BOLD); CONSTANT(BUI_FONT_ITALIC); CONSTANT(BUI_FONT_UNDERLINE);
    CONSTANT(BUI_CORNER_TOP_LEFT); CONSTANT(BUI_CORNER_TOP_RIGHT);
    CONSTANT(BUI_CORNER_BOTTOM_RIGHT); CONSTANT(BUI_CORNER_BOTTOM_LEFT); CONSTANT(BUI_CORNER_ALL);
    CONSTANT(BUI_PIXMAP_ARGB); CONSTANT(BUI_PIXMAP_NV12_BT601); CONSTANT(BUI_PIXMAP_NV12_BT709);
    CONSTANT(BUI_IMAGE_NEAREST); CONSTANT(BUI_MESH_INDEX32); CONSTANT(BUI_MESH_NEAREST);
    CONSTANT(BK_SHIFT); CONSTANT(BK_CTRL); CONSTANT(BK_ALT);
    CONSTANT(BK_BUTTON1); CONSTANT(BK_BUTTON2); CONSTANT(BK_BUTTON3);
    CONSTANT(BK_CURSOR_DEFAULT); CONSTANT(BK_CURSOR_EW); CONSTANT(BK_CURSOR_NS);
    CONSTANT(BK_CURSOR_TEXT); CONSTANT(BK_CURSOR_CROSSHAIR); CONSTANT(BK_CURSOR_HAND);
    CONSTANT(BK_CURSOR_MOVE); CONSTANT(BK_CURSOR_NONE); CONSTANT(BK_CURSOR_NESW);
    CONSTANT(BK_CURSOR_NWSE); CONSTANT(BK_CURSOR_NOT_ALLOWED); CONSTANT(BK_CURSOR_WAIT);
    CONSTANT(BK_CURSOR_PROGRESS);
    CONSTANT(BK_EV_CHANGE); CONSTANT(BK_EV_CLICK); CONSTANT(BK_EV_CALL); CONSTANT(BK_EV_RENAME);
    CONSTANT(BK_EV_ACTIVATE); CONSTANT(BK_EV_TOGGLE); CONSTANT(BK_EV_BROWSE); CONSTANT(BK_EV_PRESS);
    CONSTANT(BK_EV_RELEASE); CONSTANT(BK_EV_DOUBLE); CONSTANT(BK_EV_MOTION); CONSTANT(BK_EV_ENTER);
    CONSTANT(BK_EV_LEAVE); CONSTANT(BK_EV_KEY); CONSTANT(BK_EV_WHEEL); CONSTANT(BK_EV_SUBMIT);
    CONSTANT(BK_EV_VIEW); CONSTANT(BK_EV_SCROLL); CONSTANT(BK_EV_CONFIGURE); CONSTANT(BK_EV_KEYRELEASE);
    CONSTANT(BK_GEOM_NONE); CONSTANT(BK_GEOM_PACK); CONSTANT(BK_GEOM_GRID); CONSTANT(BK_GEOM_PLACE);
    CONSTANT(BK_ANCHOR_N); CONSTANT(BK_ANCHOR_S); CONSTANT(BK_ANCHOR_W); CONSTANT(BK_ANCHOR_E);
    CONSTANT(BK_IMAGE_NONE); CONSTANT(BK_IMAGE_PNG); CONSTANT(BK_IMAGE_JPEG); CONSTANT(BK_IMAGE_WEBP);
    CONSTANT(BK_IMAGE_GIF); CONSTANT(BK_IMAGE_BMP); CONSTANT(BK_IMAGE_TGA); CONSTANT(BK_IMAGE_QOI);
    CONSTANT(BK_IMAGE_HDR); CONSTANT(BK_IMAGE_PNM); CONSTANT(BK_IMAGE_SVG); CONSTANT(BK_IMAGE_VIDEO);
    CONSTANT(BK_FIT_FILL); CONSTANT(BK_FIT_CONTAIN); CONSTANT(BK_FIT_COVER); CONSTANT(BK_FIT_NONE);
    CONSTANT(BK_FIT_SCALE_DOWN);
    CONSTANT(BK_VIDEO_LOADING); CONSTANT(BK_VIDEO_PLAYING); CONSTANT(BK_VIDEO_PAUSED);
    CONSTANT(BK_VIDEO_ENDED); CONSTANT(BK_VIDEO_ERROR);
    CONSTANT(BK_ITEM_RECT); CONSTANT(BK_ITEM_OVAL); CONSTANT(BK_ITEM_LINE); CONSTANT(BK_ITEM_POLYGON);
    CONSTANT(BK_ITEM_TEXT); CONSTANT(BK_ITEM_ARC); CONSTANT(BK_ITEM_IMAGE); CONSTANT(BK_ITEM_ROUNDRECT);
    CONSTANT(BK_CUSTOM_PRESS); CONSTANT(BK_CUSTOM_RELEASE); CONSTANT(BK_CUSTOM_MOTION);
    CONSTANT(BK_CUSTOM_LEAVE); CONSTANT(BK_CUSTOM_WHEEL); CONSTANT(BK_CUSTOM_KEY);
    CONSTANT(BK_CUSTOM_KEYUP); CONSTANT(BK_CUSTOM_FOCUS); CONSTANT(BK_CUSTOM_BLUR);
    CONSTANT(BK_IME_COMPOSITION_START); CONSTANT(BK_IME_COMPOSITION); CONSTANT(BK_IME_COMPOSITION_END);
    CONSTANT(BK_WIDGET_BUTTON); CONSTANT(BK_WIDGET_TOGGLE); CONSTANT(BK_WIDGET_CHECKBOX);
    CONSTANT(BK_WIDGET_RADIO); CONSTANT(BK_WIDGET_NUMBER); CONSTANT(BK_WIDGET_SLIDER);
    CONSTANT(BK_WIDGET_TEXT); CONSTANT(BK_WIDGET_MENU); CONSTANT(BK_WIDGET_PULLDOWN);
    CONSTANT(BK_WIDGET_MENU_ITEM); CONSTANT(BK_WIDGET_LIST_ITEM); CONSTANT(BK_WIDGET_SWATCH);
    CONSTANT(BK_WIDGET_PROGRESS); CONSTANT(BK_WIDGET_TAB); CONSTANT(BK_WIDGET_PANEL_HEADER);
    CONSTANT(BK_WIDGET_DISCLOSURE); CONSTANT(BK_WIDGET_MENU_BACK); CONSTANT(BK_WIDGET_TOOLTIP_BACK);
    CONSTANT(BK_WIDGET_SEPARATOR); CONSTANT(BK_WIDGET_LABEL); CONSTANT(BK_WIDGET_ARROW);
    CONSTANT(BK_WIDGET_BOX);
    CONSTANT(BK_WS_HOVER); CONSTANT(BK_WS_PRESSED); CONSTANT(BK_WS_SELECTED); CONSTANT(BK_WS_DISABLED);
    CONSTANT(BK_WS_EDITING); CONSTANT(BK_WS_HOVER_LEFT); CONSTANT(BK_WS_HOVER_RIGHT);
    CONSTANT(BK_WS_MIXED); CONSTANT(BK_WS_FLAT); CONSTANT(BK_WS_OPEN); CONSTANT(BK_CORNERS_ALL);
    CONSTANT(BUI_KIT_VERSION_MAJOR); CONSTANT(BUI_KIT_VERSION_MINOR); CONSTANT(BUI_KIT_VERSION_PATCH);
    CONSTANT(BUI_KIT_VERSION); CONSTANT(BUI_IMAGE_ATLAS_MAX);
    printf("string\tBUI_KIT_VERSION_STRING\t%s\n", BUI_KIT_VERSION_STRING);
    return 0;
}
