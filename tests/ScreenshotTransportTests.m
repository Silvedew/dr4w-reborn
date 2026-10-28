#import <Foundation/Foundation.h>
#include <assert.h>
#include <unistd.h>
#import "../Shared/RBScreenshotTransport.m"

static mach_port_t receivePort(void) {
    mach_port_t port = MACH_PORT_NULL;
    assert(mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port) == KERN_SUCCESS);
    assert(mach_port_insert_right(mach_task_self(), port, port, MACH_MSG_TYPE_MAKE_SEND) == KERN_SUCCESS);
    return port;
}

static RBScreenshotRequestMessage requestFor(mach_port_t server, mach_port_t reply) {
    RBScreenshotRequestMessage request = {0};
    request.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND_ONCE);
    request.header.msgh_size = sizeof(request);
    request.header.msgh_remote_port = server;
    request.header.msgh_local_port = reply;
    request.header.msgh_id = RBScreenshotMessageID;
    request.version = RBScreenshotVersion;
    request.nonce = 123;
    request.deadline = NSProcessInfo.processInfo.systemUptime + 3;
    return request;
}

static void auditTrailer(void) {
    mach_port_t server = receivePort(), reply = receivePort();
    RBScreenshotRequestMessage request = requestFor(server, reply);
    assert(mach_msg(&request.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT,
        sizeof(request), 0, MACH_PORT_NULL, 0, MACH_PORT_NULL) == KERN_SUCCESS);
    RBScreenshotReceiveBuffer buffer = {0};
    assert(mach_msg(&buffer.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT |
        MACH_RCV_TRAILER_TYPE(MACH_MSG_TRAILER_FORMAT_0) | MACH_RCV_TRAILER_ELEMENTS(MACH_RCV_TRAILER_AUDIT),
        0, sizeof(buffer), server, 100, MACH_PORT_NULL) == KERN_SUCCESS);
    RBScreenshotRequestMessage decoded;
    RBScreenshotSender sender = {0};
    assert(RBReadScreenshotRequest(&buffer, &decoded, &sender));
    assert(sender.pid == getpid() && decoded.nonce == 123);
    mach_msg_header_t original = buffer.header;
    buffer.header.msgh_size--;
    assert(!RBReadScreenshotRequest(&buffer, &decoded, &sender));
    buffer.header = original;
    ((RBScreenshotRequestMessage *)&buffer)->version++;
    assert(!RBReadScreenshotRequest(&buffer, &decoded, &sender));
    ((RBScreenshotRequestMessage *)&buffer)->version--;
    ((RBScreenshotRequestMessage *)&buffer)->reserved = (uint32_t)(getpid() + 1000);
    assert(!RBReadScreenshotRequest(&buffer, &decoded, &sender));
    ((RBScreenshotRequestMessage *)&buffer)->reserved = 0;
    size_t offset = (buffer.header.msgh_size + 3u) & ~3u;
    mach_msg_audit_trailer_t *trailer = (void *)(buffer.bytes + offset);
    mach_msg_size_t size = trailer->msgh_trailer_size;
    trailer->msgh_trailer_size = 0;
    assert(!RBReadScreenshotRequest(&buffer, &decoded, &sender));
    trailer->msgh_trailer_size = size;
    mach_msg_destroy(&buffer.header);
    mach_port_destroy(mach_task_self(), reply);
    mach_port_destroy(mach_task_self(), server);
}

static mach_port_urefs_t references(mach_port_t port, mach_port_right_t right) {
    mach_port_urefs_t count = 0;
    assert(mach_port_get_refs(mach_task_self(), port, right, &count) == KERN_SUCCESS);
    return count;
}

static void timedOutSendReturnsRights(void) {
    mach_port_t server = receivePort(), reply = receivePort();
    mach_port_limits_t limits = {.mpl_qlimit = 1};
    assert(mach_port_set_attributes(mach_task_self(), server, MACH_PORT_LIMITS_INFO,
        (mach_port_info_t)&limits, MACH_PORT_LIMITS_INFO_COUNT) == KERN_SUCCESS);
    RBScreenshotRequestMessage first = requestFor(server, reply);
    assert(mach_msg(&first.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT,
        sizeof(first), 0, MACH_PORT_NULL, 0, MACH_PORT_NULL) == KERN_SUCCESS);
    mach_port_urefs_t before = references(server, MACH_PORT_RIGHT_SEND);
    for (int i = 0; i < 32; i++) {
        RBScreenshotRequestMessage request = requestFor(server, reply);
        mach_msg_return_t result = mach_msg(&request.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT,
            sizeof(request), 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
        assert((result & ~MACH_MSG_MASK) == MACH_SEND_TIMED_OUT);
        mach_port_t returned = request.header.msgh_local_port;
        assert(MACH_MSGH_BITS_LOCAL(request.header.msgh_bits) == MACH_MSG_TYPE_MOVE_SEND_ONCE);
        RBDestroyUnsentScreenshot(&request.header, result);
        mach_port_type_t type = 0;
        assert(mach_port_type(mach_task_self(), returned, &type) == KERN_INVALID_NAME);
        assert(references(server, MACH_PORT_RIGHT_SEND) == before);
    }
    // Destroying a receive port also destroys its queued request and the request's send-once reply right.
    mach_port_destroy(mach_task_self(), server);
    mach_port_destroy(mach_task_self(), reply);
}

int main(void) {
    @autoreleasepool { auditTrailer(); timedOutSendReturnsRights(); }
    puts("screenshot Mach transport tests passed");
}
