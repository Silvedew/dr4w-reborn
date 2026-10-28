#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef enum {
    RBScreenshotPending,
    RBScreenshotAccepted,
    RBScreenshotRejected,
    RBScreenshotUncertain,
    RBScreenshotSucceeded
} RBScreenshotResult;

typedef struct {
    uint64_t generation;
    bool active, sent, accepted, observed;
} RBScreenshotSession;

typedef struct { int pid; uint32_t version; } RBScreenshotSender;

// XNU proc_uniqidentifierinfo ABI, exposed here so the fail-closed credential check is testable.
typedef struct {
    uint8_t uuid[16];
    uint64_t uniqueID, parentUniqueID;
    int32_t version;
    uint32_t reserved2;
    uint64_t reserved3, reserved4;
} RBScreenshotProcessIdentity;
_Static_assert(sizeof(RBScreenshotProcessIdentity) == 56, "proc_pidinfo identity ABI");

static inline bool RBScreenshotIdentityMatches(RBScreenshotSender sender,
                                               int (*query)(int, int, uint64_t, void *, int)) {
    RBScreenshotProcessIdentity identity = {0};
    return sender.pid > 0 && query && query(sender.pid, 17, 0, &identity, (int)sizeof(identity)) == (int)sizeof(identity) &&
        (uint32_t)identity.version == sender.version;
}

typedef struct { RBScreenshotSender sender; uint64_t nonce; double deadline; } RBScreenshotReplay;

// Keep every live nonce; a full cache rejects rather than evicting a replay guard.
static inline bool RBScreenshotClaim(RBScreenshotReplay *entries, unsigned count,
                                      RBScreenshotSender sender, uint64_t nonce,
                                      double now, double deadline) {
    if (sender.pid <= 0 || !nonce || !(deadline > now && deadline <= now + 3.0)) return false;
    unsigned freeIndex = count;
    for (unsigned i = 0; i < count; i++) {
        if (entries[i].deadline <= now) { if (freeIndex == count) freeIndex = i; continue; }
        if (entries[i].sender.pid == sender.pid && entries[i].sender.version == sender.version &&
            entries[i].nonce == nonce) return false;
    }
    if (freeIndex == count) return false;
    entries[freeIndex] = (RBScreenshotReplay){sender, nonce, deadline};
    return true;
}

static inline bool RBScreenshotBegin(RBScreenshotSession *s) {
    if (s->active) return false;
    *s = (RBScreenshotSession){.generation = s->generation + 1, .active = true};
    return true;
}

static inline bool RBScreenshotIsCurrent(const RBScreenshotSession *s, uint64_t generation) {
    return s->active && s->generation == generation;
}

static inline void RBScreenshotCancel(RBScreenshotSession *s) {
    s->active = false;
    s->generation++;
}

static inline RBScreenshotResult RBScreenshotAcknowledge(RBScreenshotSession *s,
                                                        RBScreenshotResult reply) {
    if (!s->active) return RBScreenshotPending;
    if (reply == RBScreenshotRejected) return reply;
    if (!s->sent) return RBScreenshotPending;
    if (reply == RBScreenshotUncertain) return reply;
    if (reply == RBScreenshotAccepted) s->accepted = true;
    return s->accepted && s->observed ? RBScreenshotSucceeded : RBScreenshotPending;
}

static inline RBScreenshotResult RBScreenshotObserved(RBScreenshotSession *s) {
    if (!s->active || !s->sent) return RBScreenshotPending;
    s->observed = true;
    return s->accepted ? RBScreenshotSucceeded : RBScreenshotPending;
}

static inline RBScreenshotResult RBScreenshotExpired(const RBScreenshotSession *s) {
    return s->sent ? RBScreenshotUncertain : RBScreenshotRejected;
}

// Callers obtain these facts from kernel credentials and runtime-checked SpringBoard APIs.
typedef struct {
    void *context;
    bool (*identity)(void *context, RBScreenshotSender sender);
    bool (*foreground)(void *context, int pid);
    bool (*enabledBundleForPID)(void *context, int pid);
    bool (*captureSupported)(void *context);
} RBScreenshotAuthorization;

static inline bool RBScreenshotAuthorize(RBScreenshotSender sender, const RBScreenshotAuthorization *provider) {
    return sender.pid > 0 && provider && provider->identity && provider->foreground && provider->enabledBundleForPID &&
        provider->captureSupported && provider->identity(provider->context, sender) &&
        provider->foreground(provider->context, sender.pid) &&
        provider->enabledBundleForPID(provider->context, sender.pid) && provider->captureSupported(provider->context) &&
        provider->identity(provider->context, sender);
}
