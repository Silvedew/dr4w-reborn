#include "RBToolbarLayout.h"
#include <assert.h>
#include <stdio.h>

static void closeTo(double actual, double expected) {
    assert(fabs(actual - expected) < 0.001);
}

int main(void) {
    assert(RBToolbarScale(NAN) == 1 && RBToolbarScale(INFINITY) == 1);
    assert(RBToolbarScale(-INFINITY) == 1);
    assert(RBToolbarScale(0) == 0.6 && RBToolbarScale(9) == 1.5);
    const double scales[] = {0.6, 0.8, 1, 1.25, 1.5};
    // Full-screen iPad, Split View, rotation, short windows, and inset safe areas.
    const double sizes[][2] = {{1024,1366}, {1366,1024}, {320,1024}, {375,240}, {320,240}, {200,180}};
    for (unsigned s = 0; s < sizeof(scales) / sizeof(scales[0]); s++) {
        double scale = scales[s];
        RBToolbarMetrics metrics = RBToolbarMetricsForScale(scale);
        assert(metrics.button >= 44);
        closeTo(metrics.button, fmax(44, 44 * scale));
        closeTo(metrics.icon, 21 * scale);
        closeTo(metrics.gap, 8 * scale);
        closeTo(metrics.padding, 8 * scale);
        closeTo(metrics.thickness, metrics.button + 2 * metrics.padding);
        closeTo(metrics.contentLength, 5 * metrics.button + 4 * metrics.gap);
        closeTo(metrics.length, metrics.contentLength + 2 * metrics.padding);
        for (unsigned i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
            double w = sizes[i][0], h = sizes[i][1];
            RBToolbarLayout layout = RBLayoutToolbar(w, h, 24, 10, 20, 15, RBToolbarDefaultPosition(), scale);
            assert(layout.width > 0 && layout.height > 0);
            assert(layout.x >= 10 + metrics.margin && layout.y >= 24 + metrics.margin);
            assert(layout.x + layout.width <= w - 15 - metrics.margin + 0.001);
            assert(layout.y + layout.height <= h - 20 - metrics.margin + 0.001);
            closeTo(layout.width, metrics.thickness); // Always vertical, even in short windows.
            assert(layout.height - 2 * metrics.padding >= metrics.button);
            RBToolbarLayout minimum = RBLayoutToolbar(w, h, 24, 10, 20, 15, (RBToolbarPosition){0,0}, scale);
            RBToolbarLayout maximum = RBLayoutToolbar(w, h, 24, 10, 20, 15, (RBToolbarPosition){1,1}, scale);
            RBToolbarPosition edge = RBToolbarPositionForOrigin(minimum, maximum, -1000, 9000, (RBToolbarPosition){0.3,0.7});
            assert(edge.x == 0);
            if (maximum.y > minimum.y) assert(edge.y == 1);
            else assert(edge.y == 0.7); // A collapsed axis preserves its relative position.
        }
        RBToolbarLayout minimum = RBLayoutToolbar(1024, 1366, 24, 0, 20, 0, (RBToolbarPosition){0,0}, scale);
        RBToolbarLayout maximum = RBLayoutToolbar(1024, 1366, 24, 0, 20, 0, (RBToolbarPosition){1,1}, scale);
        RBToolbarLayout initial = RBLayoutToolbar(1024, 1366, 24, 0, 20, 0, RBToolbarDefaultPosition(), scale);
        closeTo(initial.x, maximum.x);
        closeTo(initial.y, (minimum.y + maximum.y) / 2);
        closeTo(initial.height, metrics.length); // No handle or unused bottom slot.
        RBToolbarPosition moved = RBToolbarPositionForOrigin(minimum, maximum, 200, 300, RBToolbarDefaultPosition());
        RBToolbarLayout restored = RBLayoutToolbar(1024, 1366, 24, 0, 20, 0, moved, scale);
        closeTo(restored.x, 200);
        closeTo(restored.y, 300);
        RBToolbarLayout resized = RBLayoutToolbar(320, 768, 24, 0, 20, 0, moved, scale);
        closeTo((resized.x - metrics.margin) / (320 - 2 * metrics.margin - metrics.thickness), moved.x);
        RBToolbarLayout tiny = RBLayoutToolbar(200, 180, 24, 0, 20, 0, moved, scale);
        assert(tiny.height < metrics.length); // The button list scrolls when the host is short.
    }
    RBToolbarMetrics standard = RBToolbarMetricsForScale(1);
    assert(standard.thickness == RBToolbarThickness && standard.length == RBToolbarLength);
    assert(RBToolbarDefaultPosition().x == 1 && RBToolbarDefaultPosition().y == 0.5);
    assert(RBToolbarButton >= 44 && RBToolbarCount == 5);
    puts("Toolbar scale, minimum targets, safe bounds, relative resizing and overflow passed.");
    return 0;
}
