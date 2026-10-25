#include "RBToolbarLayout.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    // Full-screen iPad, Split View, rotation, and short windows with safe areas.
    const double sizes[][2] = {{1024,1366}, {1366,1024}, {320,1024}, {375,240}, {320,240}, {200,180}};
    for (unsigned i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
        double w = sizes[i][0], h = sizes[i][1];
        RBToolbarLayout layout = RBLayoutToolbar(w, h, 24, 0, 20, 0, RBToolbarDefaultPosition());
        assert(layout.width > 0 && layout.height > 0);
        assert(layout.x >= 12 && layout.y >= 36);
        assert(layout.x + layout.width <= w - 12);
        assert(layout.y + layout.height <= h - 32);
        assert(layout.width == RBToolbarThickness); // Always vertical, even in short windows.
    }
    RBToolbarLayout minimum = RBLayoutToolbar(1024, 1366, 24, 0, 20, 0, (RBToolbarPosition){0,0});
    RBToolbarLayout maximum = RBLayoutToolbar(1024, 1366, 24, 0, 20, 0, (RBToolbarPosition){1,1});
    RBToolbarLayout initial = RBLayoutToolbar(1024, 1366, 24, 0, 20, 0, RBToolbarDefaultPosition());
    assert(initial.x == maximum.x && initial.y == (minimum.y + maximum.y) / 2);
    RBToolbarPosition moved = RBToolbarPositionForOrigin(minimum, maximum, 200, 300, RBToolbarDefaultPosition());
    RBToolbarLayout restored = RBLayoutToolbar(1024, 1366, 24, 0, 20, 0, moved);
    assert(fabs(restored.x - 200) < 0.001 && fabs(restored.y - 300) < 0.001);
    RBToolbarPosition edge = RBToolbarPositionForOrigin(minimum, maximum, -1000, 9000, moved);
    assert(edge.x == 0 && edge.y == 1);
    RBToolbarLayout resized = RBLayoutToolbar(320, 768, 24, 0, 20, 0, moved);
    assert(fabs((resized.x - 12) / (320 - 24 - RBToolbarThickness) - moved.x) < 0.001);
    RBToolbarLayout tiny = RBLayoutToolbar(200, 180, 24, 0, 20, 0, moved);
    assert(tiny.height - RBToolbarScrollTop - RBToolbarGap - RBToolbarHandle - RBToolbarPadding >= 44);
    assert(RBToolbarScrollTop == RBToolbarPadding);
    RBToolbarLayout lowMin = RBLayoutToolbar(200, 180, 24, 0, 20, 0, (RBToolbarPosition){0,0});
    RBToolbarLayout lowMax = RBLayoutToolbar(200, 180, 24, 0, 20, 0, (RBToolbarPosition){1,1});
    RBToolbarPosition collapsed = RBToolbarPositionForOrigin(lowMin, lowMax, 70, -100, moved);
    assert(collapsed.y == moved.y); // Resizing back restores the fraction on the collapsed axis.
    assert(RBToolbarDefaultPosition().x == 1 && RBToolbarDefaultPosition().y == 0.5);
    assert(RBToolbarButton >= 44 && RBToolbarHandle >= 44);
    assert(RBToolbarCount == 5);
    puts("Toolbar dragging, safe bounds, relative resizing, fixed handle, overflow and session defaults passed.");
    return 0;
}
