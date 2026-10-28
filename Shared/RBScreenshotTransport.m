#import "RBScreenshotTransport.h"
#include <mach/mach.h>
#include <dlfcn.h>
#include <stddef.h>
#include <string.h>

#ifndef RB_SCREENSHOT_SERVICE
#define RB_SCREENSHOT_SERVICE "com.dsh.dr4wreborn.screenshot"
#endif

enum { RBScreenshotMessageID = 0x52425343, RBScreenshotVersion = 1, RBReceiveLimit = 4096 };
typedef struct {
    mach_msg_header_t header;
    uint32_t version;
    uint32_t reserved;
    uint64_t nonce;
    double deadline;
} RBScreenshotRequestMessage;
typedef struct {
    mach_msg_header_t header;
    uint64_t nonce;
    uint32_t result;
    uint32_t reserved;
} RBScreenshotReplyMessage;
typedef union {
    mach_msg_header_t header;
    uint8_t bytes[RBReceiveLimit + MAX_TRAILER_SIZE];
} RBScreenshotReceiveBuffer;

static const char *const RBNames[] = {"cy:" RB_SCREENSHOT_SERVICE, "lh:" RB_SCREENSHOT_SERVICE};

// The public iOS SDK omits servers/bootstrap.h; missing symbols disable this transport.
static kern_return_t RBBootstrap(BOOL registering, const char *name, mach_port_t *port) {
    mach_port_t bootstrap = MACH_PORT_NULL;
    if (task_get_bootstrap_port(mach_task_self(), &bootstrap) != KERN_SUCCESS) return KERN_FAILURE;
    kern_return_t result = KERN_FAILURE;
    if (registering) {
        kern_return_t (*call)(mach_port_t, const char *, mach_port_t) = dlsym(RTLD_DEFAULT, "bootstrap_register");
        if (call) result = call(bootstrap, name, *port);
    } else {
        kern_return_t (*call)(mach_port_t, const char *, mach_port_t *) = dlsym(RTLD_DEFAULT, "bootstrap_look_up");
        if (call) result = call(bootstrap, name, port);
    }
    mach_port_deallocate(mach_task_self(), bootstrap);
    return result;
}

static void RBDestroyUnsentScreenshot(mach_msg_header_t *message, mach_msg_return_t result) {
    // Mach may pseudo-receive a newly named reply right; mach_msg_destroy ignores the local port.
    mach_msg_return_t base = result & ~MACH_MSG_MASK;
    if (base != MACH_SEND_TIMED_OUT && base != MACH_SEND_INTERRUPTED && base != MACH_SEND_INVALID_DEST) return;
    mach_msg_type_name_t local = MACH_MSGH_BITS_LOCAL(message->msgh_bits);
    if (local == MACH_MSG_TYPE_MOVE_SEND || local == MACH_MSG_TYPE_MOVE_SEND_ONCE)
        mach_port_deallocate(mach_task_self(), message->msgh_local_port);
    message->msgh_local_port = MACH_PORT_NULL;
    mach_msg_destroy(message);
}

static BOOL RBRequestIsLive(double deadline) {
    double remaining = deadline - NSProcessInfo.processInfo.systemUptime;
    return remaining > 0 && remaining <= 3.0;
}

static BOOL RBReadScreenshotRequest(RBScreenshotReceiveBuffer *buffer,
                                    RBScreenshotRequestMessage *request, RBScreenshotSender *sender) {
    mach_msg_header_t *header = &buffer->header;
    if (header->msgh_size != sizeof(*request) || header->msgh_id != RBScreenshotMessageID ||
        (header->msgh_bits & MACH_MSGH_BITS_COMPLEX) ||
        MACH_MSGH_BITS_REMOTE(header->msgh_bits) != MACH_MSG_TYPE_PORT_SEND_ONCE) return NO;
    size_t offset = (header->msgh_size + 3u) & ~3u;
    if (offset + sizeof(mach_msg_audit_trailer_t) > sizeof(*buffer)) return NO;
    mach_msg_audit_trailer_t *trailer = (void *)(buffer->bytes + offset);
    if (trailer->msgh_trailer_type != MACH_MSG_TRAILER_FORMAT_0 ||
        trailer->msgh_trailer_size < sizeof(*trailer) ||
        offset + trailer->msgh_trailer_size > sizeof(*buffer)) return NO;
    memcpy(request, header, sizeof(*request));
    if (request->version != RBScreenshotVersion || request->reserved || !request->nonce) return NO;
    // Darwin's audit_token_t ABI stores pid at index 5; no client-supplied identity is accepted.
    *sender = (RBScreenshotSender){(int)trailer->msgh_audit.val[5], trailer->msgh_audit.val[7]};
    return sender->pid > 0;
}

static void RBReplyToScreenshot(RBScreenshotRequestMessage request, RBScreenshotResult outcome) {
    RBScreenshotReplyMessage reply = {0};
    reply.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_MOVE_SEND_ONCE, 0);
    reply.header.msgh_size = sizeof(reply);
    reply.header.msgh_remote_port = request.header.msgh_remote_port;
    reply.header.msgh_id = RBScreenshotMessageID + 1;
    reply.nonce = request.nonce;
    reply.result = outcome;
    kern_return_t result = mach_msg(&reply.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT | MACH_SEND_INTERRUPT,
        sizeof(reply), 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
    if (result != KERN_SUCCESS) RBDestroyUnsentScreenshot(&reply.header, result);
}

BOOL RBStartScreenshotTransport(RBScreenshotResult (^handler)(RBScreenshotSender, NSTimeInterval)) {
    static dispatch_source_t source;
    if (source) return YES;
    if (!handler || !NSThread.isMainThread) return NO;
    mach_port_t port = MACH_PORT_NULL;
    if (mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port) != KERN_SUCCESS) return NO;
    if (mach_port_insert_right(mach_task_self(), port, port, MACH_MSG_TYPE_MAKE_SEND) != KERN_SUCCESS) {
        mach_port_destroy(mach_task_self(), port);
        return NO;
    }
    BOOL registered = NO;
    for (size_t i = 0; i < sizeof(RBNames) / sizeof(RBNames[0]); i++)
        if (RBBootstrap(YES, RBNames[i], &port) == KERN_SUCCESS) registered = YES;
    if (!registered) {
        mach_port_destroy(mach_task_self(), port);
        return NO;
    }
    dispatch_queue_t queue = dispatch_queue_create("com.dsh.dr4wreborn.screenshot.receive", DISPATCH_QUEUE_SERIAL);
    source = dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_RECV, port, 0, queue);
    if (!source) {
        mach_port_destroy(mach_task_self(), port);
        return NO;
    }
    __block struct { RBScreenshotReplay entries[32]; } replay = {0};
    dispatch_source_set_event_handler(source, ^{
        @autoreleasepool {
            RBScreenshotReceiveBuffer buffer = {0};
            // Without MACH_RCV_LARGE, oversized messages are consumed and destroyed by the kernel.
            kern_return_t result = mach_msg(&buffer.header,
                MACH_RCV_MSG | MACH_RCV_TIMEOUT | MACH_RCV_INTERRUPT | MACH_RCV_TRAILER_TYPE(MACH_MSG_TRAILER_FORMAT_0) |
                MACH_RCV_TRAILER_ELEMENTS(MACH_RCV_TRAILER_AUDIT),
                0, sizeof(buffer), port, 0, MACH_PORT_NULL);
            if (result != KERN_SUCCESS) return;
            RBScreenshotRequestMessage request;
            RBScreenshotSender sender = {0};
            if (!RBReadScreenshotRequest(&buffer, &request, &sender)) {
                mach_msg_destroy(&buffer.header);
                return;
            }
            __block RBScreenshotResult outcome = RBScreenshotRejected;
            dispatch_sync(dispatch_get_main_queue(), ^{
                @try {
                    if (RBScreenshotClaim(replay.entries, 32, sender, request.nonce,
                        NSProcessInfo.processInfo.systemUptime, request.deadline)) outcome = handler(sender, request.deadline);
                }
                @catch (__unused NSException *exception) { outcome = RBScreenshotUncertain; }
            });
            RBReplyToScreenshot(request, outcome);
        }
    });
    dispatch_resume(source);
    return YES;
}

void RBSendScreenshotRequest(NSTimeInterval deadline, BOOL (^stillCurrent)(void),
                             BOOL (^willSend)(void),
                             void (^completion)(RBScreenshotResult)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            mach_port_t server = MACH_PORT_NULL;
            for (size_t i = 0; i < sizeof(RBNames) / sizeof(RBNames[0]); i++) {
                if (RBBootstrap(NO, RBNames[i], &server) == KERN_SUCCESS) break;
                server = MACH_PORT_NULL;
            }
            RBScreenshotResult outcome = RBScreenshotRejected;
            mach_port_t replyPort = MACH_PORT_NULL;
            if (server != MACH_PORT_NULL &&
                mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &replyPort) == KERN_SUCCESS) {
                __block BOOL current = NO;
                dispatch_sync(dispatch_get_main_queue(), ^{
                    current = stillCurrent && stillCurrent() && RBRequestIsLive(deadline);
                    if (current) current = willSend && willSend();
                });
                if (current && RBRequestIsLive(deadline)) {
                    RBScreenshotRequestMessage request = {0};
                    request.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND_ONCE);
                    request.header.msgh_size = sizeof(request);
                    request.header.msgh_remote_port = server;
                    request.header.msgh_local_port = replyPort;
                    request.header.msgh_id = RBScreenshotMessageID;
                    request.version = RBScreenshotVersion;
                    arc4random_buf(&request.nonce, sizeof(request.nonce));
                    if (!request.nonce) request.nonce = 1;
                    request.deadline = deadline;
                    // A send failure or missing ACK is terminal. Never discover another alias or resend.
                    kern_return_t sent = mach_msg(&request.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT | MACH_SEND_INTERRUPT,
                        sizeof(request), 0, MACH_PORT_NULL, 100, MACH_PORT_NULL);
                    outcome = sent == KERN_SUCCESS ? RBScreenshotUncertain : RBScreenshotRejected;
                    if (sent != KERN_SUCCESS) RBDestroyUnsentScreenshot(&request.header, sent);
                    if (sent == KERN_SUCCESS) {
                        RBScreenshotReceiveBuffer buffer = {0};
                        double remaining = deadline - NSProcessInfo.processInfo.systemUptime;
                        mach_msg_timeout_t timeout = remaining > 0 ? (mach_msg_timeout_t)(remaining * 1000) : 0;
                        kern_return_t received = mach_msg(&buffer.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT | MACH_RCV_INTERRUPT,
                            0, sizeof(buffer), replyPort, timeout, MACH_PORT_NULL);
                        if (received == KERN_SUCCESS) {
                            RBScreenshotReplyMessage *reply = (void *)&buffer;
                            if (!(reply->header.msgh_bits & MACH_MSGH_BITS_COMPLEX) &&
                                reply->header.msgh_size == sizeof(*reply) &&
                                reply->header.msgh_id == RBScreenshotMessageID + 1 &&
                                reply->nonce == request.nonce && !reply->reserved &&
                                (reply->result == RBScreenshotAccepted || reply->result == RBScreenshotRejected ||
                                 reply->result == RBScreenshotUncertain))
                                outcome = (RBScreenshotResult)reply->result;
                            mach_msg_destroy(&buffer.header);
                        }
                    }
                }
            }
            if (replyPort != MACH_PORT_NULL) mach_port_destroy(mach_task_self(), replyPort);
            if (server != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), server);
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(outcome); });
        }
    });
}
