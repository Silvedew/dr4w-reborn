#include "RBToolbarLayout.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    // Full-screen iPad, Split View, rotation, and short windows with safe areas.
    const double sizes[][2] = {{1024,1366}, {1366,1024}, {320,1024}, {375,240}, {320,240}, {200,180}};
    for (unsigned i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
        double w = sizes[i][0], h = sizes[i][1];
        RBToolbarLayout layout = RBLayoutToolbar(w, h, 24, 0, 20, 0);
        assert(layout.width > 0 && layout.height > 0);
        assert(layout.x >= 12 && layout.y >= 36);
        assert(layout.x + layout.width <= w - 12);
        assert(layout.y + layout.height <= h - 32);
        if (layout.horizontal) assert(layout.width == RBToolbarLength);
        else assert(layout.width == RBToolbarThickness);
    }
    assert(RBLayoutToolbar(1024, 1366, 24, 0, 20, 0).horizontal == false);
    assert(RBLayoutToolbar(375, 240, 24, 0, 20, 0).horizontal == true);
    RBToolbarLayout tiny = RBLayoutToolbar(200, 180, 24, 0, 20, 0);
    assert(!tiny.horizontal && tiny.height < RBToolbarLength); // Scroll content, never shrink touch targets.
    assert(RBToolbarButton >= 44);
    assert(RBToolbarCount * RBToolbarButton + (RBToolbarCount - 1) * RBToolbarGap + 2 * RBToolbarPadding == RBToolbarLength);
    puts("Toolbar safe-area, Split View, rotation and overflow layout passed.");
    return 0;
}
