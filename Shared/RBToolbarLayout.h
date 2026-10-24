#pragma once
#include <stdbool.h>
#include <math.h>

enum { RBToolbarButton = 44, RBToolbarGap = 8, RBToolbarPadding = 8,
       RBToolbarCount = 5, RBToolbarThickness = 60, RBToolbarLength = 268 };

typedef struct {
    double x, y, width, height;
    bool horizontal;
} RBToolbarLayout;

static inline RBToolbarLayout RBLayoutToolbar(double width, double height,
    double top, double left, double bottom, double right) {
    double availableWidth = fmax(0, width - left - right - 24);
    double availableHeight = fmax(0, height - top - bottom - 24);
    bool horizontal = availableHeight < RBToolbarLength && availableWidth >= RBToolbarLength;
    double w = fmin(availableWidth, horizontal ? RBToolbarLength : RBToolbarThickness);
    double h = fmin(availableHeight, horizontal ? RBToolbarThickness : RBToolbarLength);
    return (RBToolbarLayout){
        horizontal ? left + 12 + (availableWidth - w) / 2 : width - right - 12 - w,
        horizontal ? height - bottom - 12 - h : top + 12 + (availableHeight - h) / 2,
        w, h, horizontal
    };
}
