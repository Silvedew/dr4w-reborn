#include "RBStrokeWidth.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    double legacy[] = {2,4,7,12,20};
    for (long i = 0; i < 5; i++) assert(RBStrokeWidthFromLegacyIndex(i) == legacy[i]);
    assert(RBStrokeWidthFromLegacyIndex(-1) == 7);
    assert(RBStrokeWidthFromLegacyIndex(20) == 7);
    assert(RBStrokeWidth(0, 2) == 1);
    assert(RBStrokeWidth(99, 2) == 30);
    assert(RBStrokeWidth(5.5, 2) == 6);
    assert(RBStrokeWidth(NAN, 12) == 12);
    assert(RBStrokeWidth(INFINITY, 4) == 4);
    for (int i = 1; i <= 30; i++) assert(RBStrokeWidth(i, 2) == i);
    puts("Stroke-width range, integer rounding, legacy values and invalid input passed.");
    return 0;
}
