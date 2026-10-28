#pragma once
#include <stdbool.h>
#include <math.h>

enum { RBToolbarButton = 44, RBToolbarGap = 8, RBToolbarPadding = 8,
       RBToolbarCount = 5, RBToolbarThickness = 60,
       RBToolbarContentLength = RBToolbarCount * RBToolbarButton + (RBToolbarCount - 1) * RBToolbarGap,
       RBToolbarLength = RBToolbarContentLength + 2 * RBToolbarPadding };

static inline double RBToolbarScale(double value) {
    return isfinite(value) ? fmax(0.6, fmin(1.5, value)) : 1;
}

typedef struct {
    double button, gap, padding, icon, thickness, contentLength, length, margin;
} RBToolbarMetrics;

static inline RBToolbarMetrics RBToolbarMetricsForScale(double value) {
    double scale = RBToolbarScale(value);
    double button = fmax(44, RBToolbarButton * scale);
    double gap = RBToolbarGap * scale, padding = RBToolbarPadding * scale;
    double contentLength = RBToolbarCount * button + (RBToolbarCount - 1) * gap;
    return (RBToolbarMetrics){button, gap, padding, 21 * scale,
        button + 2 * padding, contentLength, contentLength + 2 * padding, 12 * scale};
}

typedef struct { double x, y; } RBToolbarPosition;

static inline RBToolbarPosition RBToolbarDefaultPosition(void) { return (RBToolbarPosition){1, 0.5}; }
static inline double RBToolbarUnit(double value) { return fmax(0, fmin(1, value)); }

typedef struct {
    double x, y, width, height;
} RBToolbarLayout;

static inline RBToolbarLayout RBLayoutToolbar(double width, double height,
    double top, double left, double bottom, double right, RBToolbarPosition position, double scale) {
    RBToolbarMetrics metrics = RBToolbarMetricsForScale(scale);
    double availableWidth = fmax(0, width - left - right - 2 * metrics.margin);
    double availableHeight = fmax(0, height - top - bottom - 2 * metrics.margin);
    double w = fmin(availableWidth, metrics.thickness);
    double h = fmin(availableHeight, metrics.length);
    return (RBToolbarLayout){
        left + metrics.margin + (availableWidth - w) * RBToolbarUnit(position.x),
        top + metrics.margin + (availableHeight - h) * RBToolbarUnit(position.y), w, h
    };
}

static inline RBToolbarPosition RBToolbarPositionForOrigin(RBToolbarLayout minimum,
    RBToolbarLayout maximum, double x, double y, RBToolbarPosition previous) {
    // Preserve the fraction on a collapsed axis so resizing does not lose the user's position.
    if (maximum.x > minimum.x) previous.x = RBToolbarUnit((x - minimum.x) / (maximum.x - minimum.x));
    if (maximum.y > minimum.y) previous.y = RBToolbarUnit((y - minimum.y) / (maximum.y - minimum.y));
    return previous;
}
