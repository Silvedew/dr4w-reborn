#include "RBSettingsPanelLayout.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    RBSettingsPanelSize tablet = RBSettingsPanelSizeForHost(1024, 768);
    assert(tablet.width == 320 && tablet.height == 520);
    const double hosts[][2] = {{320, 480}, {250, 280}, {1024, 260}, {20, 10}, {0, 0}};
    for (unsigned i = 0; i < sizeof(hosts) / sizeof(hosts[0]); i++) {
        RBSettingsPanelSize size = RBSettingsPanelSizeForHost(hosts[i][0], hosts[i][1]);
        assert(size.width >= 0 && size.width <= fmax(0, hosts[i][0] - 24));
        assert(size.height >= 0 && size.height <= fmax(0, hosts[i][1] - 24));
        assert(size.width <= 320 && size.height <= 520);
        assert(RBSettingsPanelScrollHeight(size.height, 1) >= 0);
        assert(RBSettingsPanelScrollHeight(size.height, 1) <= RBSettingsPanelScrollHeight(size.height, 0));
    }
    RBSettingsPanelSize keyboard = RBSettingsPanelSizeForHost(320, 240);
    assert(keyboard.height == 216 && RBSettingsPanelScrollHeight(keyboard.height, 1) == 112);
    assert(RBSettingsPanelScrollHeight(30, 1) == 0);
    assert(RBSettingsPanelTarget >= 44 && RBSettingsPanelHeader >= RBSettingsPanelTarget);
    RBSettingsPanelHost safe = {0, 24, 1024, 720};
    RBSettingsPanelHost available = RBSettingsPanelHostAvoidingKeyboard(safe,
        (RBSettingsPanelHost){0, 500, 1024, 244});
    assert(available.y == 24 && available.height == 476); // Docked keyboard.
    available = RBSettingsPanelHostAvoidingKeyboard(safe, (RBSettingsPanelHost){600, 100, 320, 220});
    assert(available.x == 0 && available.width == 600 && available.height == 720); // Floating above.
    available = RBSettingsPanelHostAvoidingKeyboard((RBSettingsPanelHost){0,24,320,720},
        (RBSettingsPanelHost){0,100,320,220});
    assert(available.y == 320 && available.height == 424); // Use the space below.
    available = RBSettingsPanelHostAvoidingKeyboard(safe, (RBSettingsPanelHost){0,800,1024,300});
    assert(available.x == safe.x && available.y == safe.y && available.height == safe.height);
    assert(RBSettingsAppChangeNeedsConfirmation(false, true));
    assert(!RBSettingsAppChangeNeedsConfirmation(true, true));
    assert(!RBSettingsAppChangeNeedsConfirmation(false, false));
    assert(!RBSettingsAppChangeNeedsConfirmation(true, false));
    assert(RBSettingsAppRetryAllowed(false, true, true));
    assert(!RBSettingsAppRetryAllowed(false, false, true)); // Cancellation clears its pending target.
    assert(!RBSettingsAppRetryAllowed(false, true, false)); // A pending confirmation is not a failed save.
    assert(!RBSettingsAppRetryAllowed(true, true, true)); // A search or retry cannot start a second write.
    puts("Settings panel shrinks for split view and keyboard while its content remains scrollable.");
    return 0;
}
