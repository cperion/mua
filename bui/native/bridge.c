/* Native packaging identity and allocation in BUI's C runtime.
 * BK_clipboard_get returns malloc'd memory; BKHost.clipboard_get must return it.
 * Neither a Lua string nor an ffi.new buffer may be handed to C's free().
 * SPDX-License-Identifier: GPL-3.0-or-later */
#include <stddef.h>
#include <stdlib.h>

int mua_bui_binding_version(void)
{
    return 1;
}

void *mua_bui_malloc(size_t size)
{
    return malloc(size);
}

void mua_bui_free(void *pointer)
{
    free(pointer);
}
