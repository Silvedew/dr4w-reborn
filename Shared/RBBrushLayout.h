#pragma once
#include "RBToolbarLayout.h"
#include <math.h>
#include <stdbool.h>

enum { RBBrushWidth = RBToolbarThickness, RBBrushHeight = 444, RBBrushClose = 44,
       RBBrushColorCount = 4, RBBrushColorTarget = 44, RBBrushColorGap = 4 };
typedef struct { double width, height; } RBBrushSize;
typedef struct { double x, y, width, height; } RBBrushFrame;

static inline RBBrushSize RBBrushSizeForHost(double width, double height) {
    return (RBBrushSize){fmin(RBBrushWidth, fmax(0, width - 24)),
        fmin(RBBrushHeight, fmax(0, height - 24))};
}

static inline double RBBrushClampOrigin(double value, double minimum, double maximum) {
    if (maximum < minimum) return (minimum + maximum) / 2;
    return fmin(maximum, fmax(minimum, value));
}

static inline RBBrushFrame RBBrushFrameForHost(double safeX, double safeY,
    double safeWidth, double safeHeight, double barX, double barWidth, double anchorY) {
    RBBrushSize size = RBBrushSizeForHost(safeWidth, safeHeight);
    double minX = safeX + 12;
    double maxX = safeX + safeWidth - 12 - size.width;
    double minY = safeY + 12;
    double maxY = safeY + safeHeight - 12 - size.height;
    double right = barX + barWidth + 8;
    double left = barX - 8 - size.width;
    bool preferRight = barX + barWidth / 2 < safeX + safeWidth / 2;
    double x = preferRight ? right : left;
    x = RBBrushClampOrigin(x, minX, maxX);
    double y = RBBrushClampOrigin(anchorY - size.height / 2, minY, maxY);
    return (RBBrushFrame){x, y, size.width, size.height};
}

static inline bool RBBrushTapEdits(long selected, long tapped) {
    return tapped >= 0 && tapped < RBBrushColorCount && selected == tapped;
}
