#include "RBFloatingLayout.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    const double hosts[][4] = {{0,0,1024,1366}, {0,0,1366,1024},
        {0,0,320,768}, {0,0,200,180}, {200,24,320,600}};
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
            // An origin saved before rotation/resizing must clamp inside the new host.
            RBFloatingOrigin resized = RBClampFloatingOrigin(1280, 900, x, y, w, h, s);
            assert(resized.x >= x + 8 && resized.x + s <= x + w - 8);
            assert(resized.y >= y + 8 && resized.y + s <= y + h - 8);
        }
    }
    RBFloatingOrigin tiny = RBClampFloatingOrigin(90, 90, 0, 0, 50, 40, 80);
    assert(tiny.x == 8 && tiny.y == 8);
    puts("Floating-ball bounds across rotation, resizing, edge positions and ball sizes passed.");
    return 0;
}
