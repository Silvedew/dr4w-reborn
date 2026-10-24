#pragma once
#include <stdbool.h>
#include <math.h>

enum { RBToolbarButton = 44, RBToolbarGap = 8, RBToolbarPadding = 8,
       RBToolbarCount = 6, RBToolbarThickness = 60, RBToolbarHandle = 44,
       RBToolbarContentLength = RBToolbarCount * RBToolbarButton + (RBToolbarCount - 1) * RBToolbarGap,
       RBToolbarScrollTop = RBToolbarPadding + RBToolbarHandle + RBToolbarGap,
       RBToolbarLength = RBToolbarScrollTop + RBToolbarContentLength + RBToolbarPadding };

typedef struct { double x, y; } RBToolbarPosition;

static inline RBToolbarPosition RBToolbarDefaultPosition(void) { return (RBToolbarPosition){1, 0.5}; }
static inline double RBToolbarUnit(double value) { return fmax(0, fmin(1, value)); }

typedef struct {
    double x, y, width, height;
} RBToolbarLayout;

static inline RBToolbarLayout RBLayoutToolbar(double width, double height,
    double top, double left, double bottom, double right, RBToolbarPosition position) {
    double availableWidth = fmax(0, width - left - right - 24);
    double availableHeight = fmax(0, height - top - bottom - 24);
    double w = fmin(availableWidth, RBToolbarThickness);
    double h = fmin(availableHeight, RBToolbarLength);
    return (RBToolbarLayout){
        left + 12 + (availableWidth - w) * RBToolbarUnit(position.x),
        top + 12 + (availableHeight - h) * RBToolbarUnit(position.y), w, h
    };
}

static inline RBToolbarPosition RBToolbarPositionForOrigin(RBToolbarLayout minimum,
    RBToolbarLayout maximum, double x, double y, RBToolbarPosition previous) {
    // Preserve the fraction on a collapsed axis so resizing does not lose the user's position.
    if (maximum.x > minimum.x) previous.x = RBToolbarUnit((x - minimum.x) / (maximum.x - minimum.x));
    if (maximum.y > minimum.y) previous.y = RBToolbarUnit((y - minimum.y) / (maximum.y - minimum.y));
    return previous;
}
