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
    RBBrushFrame left = RBBrushFrameForHost(100, 50, 500, 800, 112, 60, 300);
    assert(left.x == 180 && left.y == 78 && left.width == 60 && left.height == 444);
    assert(left.x >= 112 && left.x + left.width <= 588);
    assert(left.y >= 62 && left.y + left.height <= 838);
    RBBrushFrame right = RBBrushFrameForHost(100, 50, 500, 800, 528, 60, 700);
    assert(right.x == 460 && right.y == 394); // Prefer the screen-center side and clamp vertically.
    RBBrushFrame narrow = RBBrushFrameForHost(0, 0, 200, 400, 90, 60, 200);
    assert(narrow.x == 22); // The toolbar straddles the midpoint; the left side has more room.
    RBBrushFrame centered = RBBrushFrameForHost(0, 0, 1024, 768, 490, 60, 400);
    assert(centered.x == 422); // Use the toolbar center rather than its left edge to choose a side.
    RBBrushFrame edge = RBBrushFrameForHost(0, 0, 120, 400, 30, 60, 200);
    assert(edge.x == 12 && edge.x + edge.width <= 108); // Neither side fits; keep the panel in bounds.
    RBBrushFrame shortSplit = RBBrushFrameForHost(20, 30, 320, 200, 20, 60, 31);
    assert(shortSplit.width == 60 && shortSplit.height == 176);
    assert(shortSplit.x >= 32 && shortSplit.x + shortSplit.width <= 328);
    assert(shortSplit.y == 42 && shortSplit.y + shortSplit.height <= 218);
    RBBrushFrame landscape = RBBrushFrameForHost(40, 24, 1000, 600, 950, 60, 250);
    assert(landscape.x == 882 && landscape.y == 36);
    RBBrushFrame tiny = RBBrushFrameForHost(20, 30, 10, 10, 20, 60, 35);
    assert(tiny.x == 25 && tiny.y == 35 && tiny.width == 0 && tiny.height == 0);
    assert(RBBrushTapEdits(2, 2));
    assert(!RBBrushTapEdits(2, 1));
    assert(!RBBrushTapEdits(-1, 0));
    assert(!RBBrushTapEdits(4, 4));
    assert(RBBrushColorTarget >= 44);
    puts("Compact brush bounds, centered targets and selected-slot edit gesture passed.");
    return 0;
}
