#include "RBPolicy.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    for (int master = 0; master < 2; master++) {
        for (int home = 0; home < 2; home++) {
            for (int selected = 0; selected < 2; selected++) {
                assert(RBPolicyEnabled(master, home, selected, true) == (master && home));
                assert(RBPolicyEnabled(master, home, selected, false) == (master && selected));
                assert(!RBPolicyBall(false, master, home, selected));
                assert(RBPolicyBall(true, master, home, selected) == (home ? selected : master));
            }
        }
    }
    RBVolumeSequence state = {0};
    assert(!RBVolumePress(&state, false, 1, true)); // Down alone.
    assert(!RBVolumePress(&state, true, 2, true));
    assert(RBVolumePress(&state, false, 2.5, true));
    assert(!RBVolumePress(&state, false, 2.6, true)); // No double trigger.
    assert(!RBVolumePress(&state, true, 4, true));
    assert(!RBVolumePress(&state, false, 5, true)); // Too slow.
    assert(!RBVolumePress(&state, true, 6, true));
    assert(!RBVolumePress(&state, false, 5, true)); // Clock goes backwards.
    assert(!RBVolumePress(&state, true, 7, true));
    assert(!RBVolumePress(&state, false, 7.1, false)); // Disabled or locked.
    assert(!RBVolumePress(&state, false, 7.2, true)); // Disabling clears state.
    assert(!RBVolumePress(&state, true, 0, true));
    assert(RBVolumePress(&state, false, 0.9, true)); // Boundary included.
    assert(!RBVolumePress(&state, true, 10, true));
    assert(!RBVolumePress(&state, true, 10.5, true));
    assert(RBVolumePress(&state, false, 11, true)); // Repeated up.
    assert(!RBVolumePress(&state, true, 12, true));
    assert(!RBVolumePress(&state, false, NAN, true));
    assert(!RBVolumePress(&state, false, 12.1, true));
    puts("Activation, floating-ball policy, and volume sequence tests passed.");
    return 0;
}
