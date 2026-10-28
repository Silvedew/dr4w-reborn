#include "RBScreenshotPolicy.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static int queryResult = 56;
static uint32_t processVersion = 7;
static int queryCalls;
static int query(int pid, int flavor, uint64_t argument, void *buffer, int bytes) {
    assert(pid == 42 && flavor == 17 && argument == 0 && bytes == 56);
    queryCalls++;
    ((RBScreenshotProcessIdentity *)buffer)->version = (int32_t)processVersion;
    return queryResult;
}

typedef struct { bool foreground, enabled, supported, changeIdentity; int checks; } Facts;
static bool identity(void *context, RBScreenshotSender sender) {
    Facts *facts = context;
    if (++facts->checks == 2 && facts->changeIdentity) processVersion++;
    return RBScreenshotIdentityMatches(sender, query);
}
static bool foreground(void *context, int pid) { assert(pid == 42); return ((Facts *)context)->foreground; }
static bool enabled(void *context, int pid) { assert(pid == 42); return ((Facts *)context)->enabled; }
static bool supported(void *context) { return ((Facts *)context)->supported; }

static void sessions(void) {
    RBScreenshotSession session = {0};
    assert(RBScreenshotBegin(&session));
    uint64_t first = session.generation;
    assert(!RBScreenshotBegin(&session));
    assert(RBScreenshotAcknowledge(&session, RBScreenshotRejected) == RBScreenshotRejected);
    assert(RBScreenshotObserved(&session) == RBScreenshotPending && !session.observed);
    assert(RBScreenshotExpired(&session) == RBScreenshotRejected);
    session.sent = true;
    assert(RBScreenshotObserved(&session) == RBScreenshotPending);
    assert(RBScreenshotAcknowledge(&session, RBScreenshotAccepted) == RBScreenshotSucceeded);
    RBScreenshotCancel(&session);
    assert(!RBScreenshotIsCurrent(&session, first));
    assert(RBScreenshotObserved(&session) == RBScreenshotPending);
    assert(RBScreenshotAcknowledge(&session, RBScreenshotAccepted) == RBScreenshotPending);
    assert(RBScreenshotBegin(&session));
    assert(!RBScreenshotIsCurrent(&session, first));
    assert(!session.observed && !session.accepted && !session.sent);
    session.sent = true;
    assert(RBScreenshotAcknowledge(&session, RBScreenshotAccepted) == RBScreenshotPending);
    assert(RBScreenshotObserved(&session) == RBScreenshotSucceeded);
    assert(RBScreenshotExpired(&session) == RBScreenshotUncertain);
    assert(RBScreenshotAcknowledge(&session, RBScreenshotUncertain) == RBScreenshotUncertain);
    assert(RBScreenshotAcknowledge(&session, RBScreenshotRejected) == RBScreenshotRejected);
}

static void authorization(void) {
    RBScreenshotSender sender = {42, 7};
    Facts facts = {true, true, true, false, 0};
    RBScreenshotAuthorization provider = {&facts, identity, foreground, enabled, supported};
    assert(RBScreenshotAuthorize(sender, &provider) && facts.checks == 2);
    assert(!RBScreenshotAuthorize(sender, NULL));
    RBScreenshotAuthorization missing = provider; missing.identity = NULL;
    assert(!RBScreenshotAuthorize(sender, &missing));
    missing = provider; missing.foreground = NULL;
    assert(!RBScreenshotAuthorize(sender, &missing));
    missing = provider; missing.enabledBundleForPID = NULL;
    assert(!RBScreenshotAuthorize(sender, &missing));
    missing = provider; missing.captureSupported = NULL;
    assert(!RBScreenshotAuthorize(sender, &missing));
    assert(!RBScreenshotAuthorize((RBScreenshotSender){0, 7}, &provider));
    assert(!RBScreenshotIdentityMatches(sender, NULL));
    queryResult = -1;
    assert(!RBScreenshotAuthorize(sender, &provider));
    queryResult = 55;
    assert(!RBScreenshotAuthorize(sender, &provider));
    queryResult = 56;
    processVersion = 8;
    assert(!RBScreenshotAuthorize(sender, &provider));
    processVersion = 7;
    facts.foreground = false;
    assert(!RBScreenshotAuthorize(sender, &provider));
    facts.foreground = true; facts.enabled = false;
    assert(!RBScreenshotAuthorize(sender, &provider));
    facts.enabled = true; facts.supported = false;
    assert(!RBScreenshotAuthorize(sender, &provider));
    facts.supported = true; facts.changeIdentity = true; facts.checks = 0;
    assert(!RBScreenshotAuthorize(sender, &provider)); // PID reused after the foreground lookup.
    assert(queryCalls > 0);
}

static void replay(void) {
    RBScreenshotReplay entries[2] = {0};
    RBScreenshotSender sender = {42, 7};
    assert(RBScreenshotClaim(entries, 2, sender, 1, 10, 13));
    assert(!RBScreenshotClaim(entries, 2, sender, 1, 11, 13));
    assert(RBScreenshotClaim(entries, 2, sender, 2, 11, 13));
    assert(!RBScreenshotClaim(entries, 2, sender, 3, 11, 13));
    assert(RBScreenshotClaim(entries, 2, sender, 3, 13, 15));
    assert(!RBScreenshotClaim(entries, 2, sender, 0, 13, 15));
    assert(!RBScreenshotClaim(entries, 2, sender, 4, 13, 13));
    assert(!RBScreenshotClaim(entries, 2, sender, 4, 13, 16.1));
    assert(!RBScreenshotClaim(entries, 2, sender, 4, 13, NAN));
    assert(!RBScreenshotClaim(entries, 2, sender, 4, 13, INFINITY));
}

int main(void) { sessions(); authorization(); replay(); puts("screenshot policy tests passed"); }
