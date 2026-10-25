#pragma once
#include <math.h>

typedef struct { double x, y; } RBFloatingOrigin;

static inline RBFloatingOrigin RBClampFloatingOrigin(double x, double y,
    double hostX, double hostY, double width, double height, double size) {
    return (RBFloatingOrigin){
        fmax(hostX + 8, fmin(x, hostX + width - size - 8)),
        fmax(hostY + 8, fmin(y, hostY + height - size - 8))
    };
}
