#pragma once
#include "RBToolbarLayout.h"
#include <math.h>
#include <stdbool.h>

enum { RBBrushWidth = RBToolbarThickness, RBBrushHeight = 444, RBBrushClose = 44,
       RBBrushColorCount = 4, RBBrushColorTarget = 44, RBBrushColorGap = 4 };
typedef struct { double width, height; } RBBrushSize;

static inline RBBrushSize RBBrushSizeForHost(double width, double height) {
    return (RBBrushSize){fmin(RBBrushWidth, fmax(0, width - 24)),
        fmin(RBBrushHeight, fmax(0, height - 24))};
}

static inline bool RBBrushTapEdits(long selected, long tapped) {
    return tapped >= 0 && tapped < RBBrushColorCount && selected == tapped;
}
