#pragma once
#include <math.h>
#include <stdbool.h>

enum { RBSettingsPanelWidth = 320, RBSettingsPanelHeight = 520, RBSettingsPanelHeader = 52,
       RBSettingsPanelSearch = 52, RBSettingsPanelTarget = 44 };
typedef struct { double width, height; } RBSettingsPanelSize;
typedef struct { double x, y, width, height; } RBSettingsPanelHost;

static inline RBSettingsPanelHost RBSettingsPanelHostAvoidingKeyboard(RBSettingsPanelHost host,
    RBSettingsPanelHost keyboard) {
    double x = fmax(host.x, keyboard.x), y = fmax(host.y, keyboard.y);
    double right = fmin(host.x + host.width, keyboard.x + keyboard.width);
    double bottom = fmin(host.y + host.height, keyboard.y + keyboard.height);
    if (right <= x || bottom <= y) return host;
    RBSettingsPanelHost candidates[] = {
        {host.x, host.y, host.width, y - host.y},
        {host.x, bottom, host.width, host.y + host.height - bottom},
        {host.x, host.y, x - host.x, host.height},
        {right, host.y, host.x + host.width - right, host.height}
    };
    double best = -1;
    RBSettingsPanelHost available = candidates[0];
    for (unsigned i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
        double width = fmin(RBSettingsPanelWidth, fmax(0, candidates[i].width - 24));
        double height = fmin(RBSettingsPanelHeight, fmax(0, candidates[i].height - 24));
        double area = width * height;
        if (area > best) { best = area; available = candidates[i]; }
    }
    return available;
}

static inline RBSettingsPanelSize RBSettingsPanelSizeForHost(double width, double height) {
    return (RBSettingsPanelSize){fmin(RBSettingsPanelWidth, fmax(0, width - 24)),
        fmin(RBSettingsPanelHeight, fmax(0, height - 24))};
}

static inline double RBSettingsPanelScrollHeight(double height, int hasSearch) {
    return fmax(0, height - RBSettingsPanelHeader - (hasSearch ? RBSettingsPanelSearch : 0));
}

static inline bool RBSettingsAppChangeNeedsConfirmation(bool enabled, bool currentApplication) {
    return !enabled && currentApplication;
}

static inline bool RBSettingsAppRetryAllowed(bool saving, bool hasPendingBundle, bool hasSaveError) {
    return !saving && hasPendingBundle && hasSaveError;
}
