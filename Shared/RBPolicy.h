#pragma once
#include <stdbool.h>
#include <math.h>

static inline bool RBPolicyEnabled(bool master, bool home, bool selected, bool isHome) {
    return master && (isHome ? home : selected);
}

static inline bool RBPolicyBall(bool enabled, bool temporarilyHidden) {
    return enabled && !temporarilyHidden;
}

typedef struct {
    bool waitingForDown;
    double lastUp;
} RBVolumeSequence;

static inline bool RBVolumePress(RBVolumeSequence *sequence, bool up, double now, bool allowed) {
    if (!allowed || !isfinite(now)) {
        sequence->waitingForDown = false;
        return false;
    }
    if (up) {
        sequence->waitingForDown = true;
        sequence->lastUp = now;
        return false;
    }
    bool trigger = sequence->waitingForDown && now >= sequence->lastUp &&
                   now - sequence->lastUp <= 0.9;
    sequence->waitingForDown = false;
    return trigger;
}
