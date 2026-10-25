#include "RBBrushLayout.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    const double sizes[][2] = {{1024,768}, {320,1024}, {320,240}, {200,180}};
    for (unsigned i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
        RBBrushSize panel = RBBrushSizeForHost(sizes[i][0], sizes[i][1]);
        assert(panel.width == RBToolbarThickness);
        assert(panel.height <= RBBrushHeight && panel.height <= sizes[i][1] - 24);
        assert(panel.height >= RBBrushClose + RBBrushColorTarget);
        assert((panel.width - RBBrushColorTarget) / 2 == 8);
    }
    assert(RBBrushSizeForHost(320, 240).height == 216); // Shortens rather than widening into a sheet.
    assert(RBBrushHeight == 444 && RBBrushWidth == RBToolbarThickness);
    assert(RBBrushTapEdits(2, 2));
    assert(!RBBrushTapEdits(2, 1));
    assert(!RBBrushTapEdits(-1, 0));
    assert(!RBBrushTapEdits(4, 4));
    assert(RBBrushColorTarget >= 44);
    puts("Compact brush bounds, centered targets and selected-slot edit gesture passed.");
    return 0;
}
