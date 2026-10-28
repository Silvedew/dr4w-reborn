#include "RBSettingsPanelLayout.h"
#include <assert.h>
#include <stdio.h>

static void expectSize(RBSettingsPanelSize size, double width, double height) {
    assert(fabs(size.width - width) < 0.001);
    assert(fabs(size.height - height) < 0.001);
}

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
    // Measured content fixtures: the same row targets must not create identical full-height panels.
    RBSettingsPanelSize mainApp = {204, 52 + 6 * 52};
    RBSettingsPanelSize mainHome = {204, 52 + 5 * 52};
    RBSettingsPanelSize choices = {218, 52 + 3 * 52};
    RBSettingsPanelSize slider = {240, 52 + 128};
    RBSettingsPanelSize emptyApps = {246, 52 + 52 + 52};
    RBSettingsPanelSize oneApp = {320, 52 + 52 + 76};
    RBSettingsPanelSize manyApps = {320, 52 + 52 + 1000 * 76};
    expectSize(RBSettingsPanelSizeForContent(mainApp, 1024, 768), 204, 364);
    expectSize(RBSettingsPanelSizeForContent(mainHome, 1024, 768), 204, 312);
    expectSize(RBSettingsPanelSizeForContent(choices, 1024, 768), 218, 208);
    expectSize(RBSettingsPanelSizeForContent(slider, 1024, 768), 240, 180);
    expectSize(RBSettingsPanelSizeForContent(emptyApps, 1024, 768), 246, 156);
    expectSize(RBSettingsPanelSizeForContent(oneApp, 1024, 768), 320, 180);
    expectSize(RBSettingsPanelSizeForContent(manyApps, 1024, 768), 320, 520);
    expectSize(RBSettingsPanelSizeForContent((RBSettingsPanelSize){180, 52 + 12 * 52}, 1024, 768), 180, 520);
    // Long Chinese options / large type can wrap into taller measured rows while respecting both caps.
    expectSize(RBSettingsPanelSizeForContent((RBSettingsPanelSize){700, 96 + 3 * 98}, 1024, 768), 320, 390);
    expectSize(RBSettingsPanelSizeForContent((RBSettingsPanelSize){500, 52 + 188 + 2 * 52}, 1024, 768), 320, 344);
    expectSize(RBSettingsPanelSizeForContent(mainApp, 200, 280), 176, 256);
    expectSize(RBSettingsPanelSizeForContent(choices, 320, 480), 218, 208);
    expectSize(RBSettingsPanelSizeForContent(slider, 200, 180), 176, 156);
    expectSize(RBSettingsPanelSizeForContent(mainApp, 20, 10), 0, 0);
    // Typing from a full list to no results keeps its content target; keyboard and rotation still constrain it.
    RBSettingsPanelSize frozen = {320, 520};
    RBSettingsPanelSize editing = RBSettingsPanelTargetWhileEditing(emptyApps, frozen, true, true);
    expectSize(RBSettingsPanelSizeForContent(editing, 1024, 768), 320, 520);
    expectSize(RBSettingsPanelSizeForContent(editing, 320, 240), 296, 216);
    expectSize(RBSettingsPanelSizeForContent(editing, 250, 768), 226, 520);
    expectSize(RBSettingsPanelSizeForContent(editing, 1024, 768), 320, 520);
    RBSettingsPanelSize ended = RBSettingsPanelTargetWhileEditing(emptyApps, frozen, false, true);
    expectSize(RBSettingsPanelSizeForContent(ended, 1024, 768), 246, 156);
    RBSettingsPanelSize confirmation = {320, 344};
    // Leaving the search page cannot reuse its frozen dimensions, even before focus resignation finishes.
    expectSize(RBSettingsPanelTargetWhileEditing(confirmation, frozen, true, false), 320, 344);
    expectSize(RBSettingsPanelTargetWhileEditing(emptyApps, frozen, false, true), 246, 156);
    assert(RBSettingsPanelScrollHeightForChrome(390, 96, 0) == 294);
    assert(RBSettingsPanelScrollHeightForChrome(100, 96, 60) == 0);
    puts("Content-sized settings pages, dynamic type fixtures, scrolling limits, keyboard constraints and stable search targets passed.");
    return 0;
}
