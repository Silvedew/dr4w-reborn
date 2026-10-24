#pragma once
#include <math.h>

static inline double RBStrokeWidthFromLegacyIndex(long index) {
    const double widths[] = {2, 4, 7, 12, 20};
    return widths[index >= 0 && index < 5 ? index : 2];
}

static inline double RBStrokeWidth(double value, double fallback) {
    return isfinite(value) ? round(fmax(1, fmin(30, value))) : fallback;
}
