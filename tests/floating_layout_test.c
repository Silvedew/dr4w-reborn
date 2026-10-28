#include "RBFloatingLayout.h"
#include "RBToolbarLayout.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    const double hosts[][4] = {{0,0,1024,1366}, {0,0,1366,1024},
        {0,0,320,768}, {0,0,200,180}, {200,24,320,600}, {-80,56,375,240}};
    const double sizes[] = {44,56,80};
    for (unsigned i = 0; i < sizeof(hosts) / sizeof(hosts[0]); i++) {
        for (unsigned j = 0; j < sizeof(sizes) / sizeof(sizes[0]); j++) {
            double x = hosts[i][0], y = hosts[i][1], w = hosts[i][2], h = hosts[i][3], s = sizes[j];
            RBFloatingOrigin low = RBClampFloatingOrigin(-1000, -1000, x, y, w, h, s);
            RBFloatingOrigin high = RBClampFloatingOrigin(9000, 9000, x, y, w, h, s);
            assert(low.x == x + 8 && low.y == y + 8);
            assert(high.x + s == x + w - 8 && high.y + s == y + h - 8);
            RBFloatingOrigin middle = RBClampFloatingOrigin(x + 60, y + 40, x, y, w, h, s);
            assert(middle.x == x + 60 && middle.y == y + 40);
            RBFloatingOrigin center = RBClampFloatingCenter(middle.x + s / 2, middle.y + s / 2, x, y, w, h, s);
            assert(center.x == middle.x + s / 2 && center.y == middle.y + s / 2);
            RBFloatingOrigin centerLow = RBClampFloatingCenter(-1000, -1000, x, y, w, h, s);
            RBFloatingOrigin centerHigh = RBClampFloatingCenter(9000, 9000, x, y, w, h, s);
            assert(centerLow.x == x + 8 + s / 2 && centerLow.y == y + 8 + s / 2);
            assert(centerHigh.x == x + w - 8 - s / 2 && centerHigh.y == y + h - 8 - s / 2);
            const double scales[] = {0.6, 1, 1.5};
            for (unsigned k = 0; k < sizeof(scales) / sizeof(scales[0]); k++) {
                RBToolbarLayout minimum = RBLayoutToolbar(w, h, 24, 0, 20, 0, (RBToolbarPosition){0,0}, scales[k]);
                RBToolbarLayout maximum = RBLayoutToolbar(w, h, 24, 0, 20, 0, (RBToolbarPosition){1,1}, scales[k]);
                RBToolbarLayout bar = RBLayoutToolbar(w, h, 24, 0, 20, 0, (RBToolbarPosition){0.5,0.5}, scales[k]);
                RBToolbarPoint anchor = RBToolbarTopAnchor(bar, scales[k]);
                // A scene host may have a nonzero origin; closing stores its center in host axes.
                RBFloatingOrigin followed = RBClampFloatingCenter(anchor.x + x, anchor.y + y, x, y, w, h, s);
                RBToolbarPosition reopened = RBToolbarPositionForTopAnchor(minimum, maximum,
                    (RBToolbarPoint){followed.x - x, followed.y - y}, (RBToolbarPosition){0.5,0.5}, scales[k]);
                RBToolbarLayout restored = RBLayoutToolbar(w, h, 24, 0, 20, 0, reopened, scales[k]);
                assert(fabs(restored.x - bar.x) < 0.001 && fabs(restored.y - bar.y) < 0.001);
                RBToolbarMetrics metrics = RBToolbarMetricsForScale(scales[k]);
                assert(fabs(RBToolbarTopAnchor(restored, scales[k]).x -
                    (restored.x + restored.width / 2)) < 0.001);
                assert(fabs(RBToolbarTopAnchor(restored, scales[k]).y -
                    (restored.y + metrics.padding + metrics.button / 2)) < 0.001);
            }
            // An origin saved before rotation/resizing must clamp inside the new host.
            RBFloatingOrigin resized = RBClampFloatingOrigin(1280, 900, x, y, w, h, s);
            assert(resized.x >= x + 8 && resized.x + s <= x + w - 8);
            assert(resized.y >= y + 8 && resized.y + s <= y + h - 8);
        }
    }
    RBFloatingOrigin tiny = RBClampFloatingOrigin(90, 90, 0, 0, 50, 40, 80);
    assert(tiny.x == 8 && tiny.y == 8);
    puts("Floating-ball bounds, toolbar-anchor follow/reopen, nonzero hosts and center clamps passed.");
    return 0;
}
