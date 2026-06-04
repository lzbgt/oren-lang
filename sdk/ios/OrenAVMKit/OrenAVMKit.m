#import "OrenAVMKit.h"

#import <CommonCrypto/CommonDigest.h>
#import <dispatch/dispatch.h>
#include <arpa/inet.h>
#include <math.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <string.h>
#include <unistd.h>

NSString* const OrenAVMKitErrorDomain = @"org.oren.avmkit";

@interface OrenAVMRunResult ()
- (instancetype)initWithResult:(const AvmEmbedResult*)result stdoutData:(NSData*)stdoutData;
@end

static NSError* OrenAVMKitMakeError(NSString* message, const AvmEmbedResult* result) {
    NSInteger code = result ? result->status : AVM_EMBED_ERR_VM;
    NSString* detail = message ?: @"OrenAVMKit error";
    if (result && result->message[0]) {
        detail = [NSString stringWithUTF8String:result->message] ?: detail;
    }
    return [NSError errorWithDomain:OrenAVMKitErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: detail}];
}

static BOOL OrenAVMKitAssignError(NSError** error, NSString* message, const AvmEmbedResult* result) {
    if (error) *error = OrenAVMKitMakeError(message, result);
    return NO;
}

static BOOL OrenAVMKitAssignSDKError(NSError** error, NSInteger code, NSString* message) {
    if (error) {
        *error = [NSError errorWithDomain:OrenAVMKitErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: message ?: @"OrenAVMKit error"}];
    }
    return NO;
}

static uint16_t OrenAVMKitReadU16LE(const uint8_t* p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t OrenAVMKitReadU32LE(const uint8_t* p) {
    return (uint32_t)p[0] |
        ((uint32_t)p[1] << 8) |
        ((uint32_t)p[2] << 16) |
        ((uint32_t)p[3] << 24);
}

static NSString* OrenAVMKitUTF8Field(const uint8_t* bytes, NSUInteger len) {
    if (len == 0) return @"";
    return [[NSString alloc] initWithBytes:bytes length:len encoding:NSUTF8StringEncoding];
}

static NSString* OrenAVMKitJoinVFSPath(NSString* root, NSString* relative) {
    NSString* cleanRoot = root ?: @"";
    while ([cleanRoot hasSuffix:@"/"] && cleanRoot.length > 1) {
        cleanRoot = [cleanRoot substringToIndex:cleanRoot.length - 1];
    }
    NSString* cleanRel = relative ?: @"";
    while ([cleanRel hasPrefix:@"/"]) {
        cleanRel = [cleanRel substringFromIndex:1];
    }
    if (cleanRoot.length == 0) return cleanRel;
    if (cleanRel.length == 0) return cleanRoot;
    return [cleanRoot stringByAppendingFormat:@"/%@", cleanRel];
}

@interface OrenAVMRuntime ()
@property(nonatomic, readonly) AvmEmbedHandle* handle;
@end

@implementation OrenAVMRuntime {
    AvmEmbedHandle* _handle;
    uint64_t _ioLimitBytes;
    NSSet<NSString*>* _liveNetworkAllowedHosts;
    NSTimeInterval _liveNetworkTimeoutSeconds;
    uint32_t _liveNetworkMaxSessions;
    uint64_t _liveNetworkSessionByteLimitBytes;
    NSURLSession* _networkSession;
    NSMutableDictionary<NSNumber*, NSNumber*>* _networkSockets;
    NSMutableDictionary<NSNumber*, NSString*>* _networkSessionKinds;
    NSMutableDictionary<NSNumber*, NSNumber*>* _networkSessionByteCounts;
	uint32_t _nextNetworkSessionId;
	BOOL _runInProgress;
	OrenAVMGraphicsFrameHandler _graphicsFrameHandler;
}

static void OrenAVMRuntimeGraphicsFramePublished(void* userData, uint32_t sequence, size_t len) {
	if (!userData) return;
	OrenAVMRuntime* runtime = (__bridge OrenAVMRuntime*)userData;
	OrenAVMGraphicsFrameHandler handler = nil;
	@synchronized (runtime) {
		handler = [runtime->_graphicsFrameHandler copy];
	}
	if (handler) handler(sequence, (NSUInteger)len);
}

static uint32_t OrenAVMRuntimeRegisterNetworkSession(OrenAVMRuntime* runtime, int fd, NSString* kind) {
    if (!runtime || fd < 0 || kind.length == 0) return 0;
    @synchronized (runtime) {
        if (runtime->_liveNetworkMaxSessions > 0 && runtime->_networkSockets.count >= runtime->_liveNetworkMaxSessions) {
            return 0;
        }
        runtime->_nextNetworkSessionId += 1u;
        if (runtime->_nextNetworkSessionId == 0) runtime->_nextNetworkSessionId = 1u;
        uint32_t sid = runtime->_nextNetworkSessionId;
        runtime->_networkSockets[@(sid)] = @(fd);
        runtime->_networkSessionKinds[@(sid)] = kind;
        runtime->_networkSessionByteCounts[@(sid)] = @0;
        return sid;
    }
}

static void OrenAVMRuntimeSetSocketTimeout(int fd, uint32_t timeoutMs) {
    if (fd < 0 || timeoutMs == 0) return;
    struct timeval tv;
    tv.tv_sec = (time_t)(timeoutMs / 1000u);
    tv.tv_usec = (suseconds_t)((timeoutMs % 1000u) * 1000u);
    (void)setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    (void)setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
}

static int OrenAVMRuntimeSendAll(int fd, const uint8_t* data, size_t len) {
    size_t total = 0;
    while (total < len) {
        ssize_t n = send(fd, data + total, len - total, 0);
        if (n <= 0) return -1;
        total += (size_t)n;
    }
    return 0;
}

static int OrenAVMRuntimeRecvExact(int fd, uint8_t* data, size_t len) {
    size_t total = 0;
    while (total < len) {
        ssize_t n = recv(fd, data + total, len - total, 0);
        if (n <= 0) return -1;
        total += (size_t)n;
    }
    return 0;
}

static int OrenAVMRuntimeSocketForSession(OrenAVMRuntime* runtime, uint32_t sessionId) {
    __block int fd = -1;
    @synchronized (runtime) {
        NSNumber* value = runtime->_networkSockets[@(sessionId)];
        if (value) fd = value.intValue;
    }
    return fd;
}

static NSString* OrenAVMRuntimeKindForSession(OrenAVMRuntime* runtime, uint32_t sessionId) {
    __block NSString* kind = nil;
    @synchronized (runtime) {
        kind = runtime->_networkSessionKinds[@(sessionId)];
    }
    return kind;
}

static NSString* OrenAVMRuntimeWebSocketAccept(NSString* key) {
    NSString* input = [key stringByAppendingString:@"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"];
    NSData* data = [input dataUsingEncoding:NSASCIIStringEncoding];
    if (!data) return nil;
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    NSData* digestData = [NSData dataWithBytes:digest length:sizeof(digest)];
    return [digestData base64EncodedStringWithOptions:0];
}

static BOOL OrenAVMRuntimeWebSocketHandshake(int fd, NSURL* url, uint32_t timeoutMs) {
    NSMutableData* keyBytes = [NSMutableData dataWithLength:16];
    if (!keyBytes) return NO;
    arc4random_buf(keyBytes.mutableBytes, keyBytes.length);
    NSString* key = [keyBytes base64EncodedStringWithOptions:0];
    NSString* accept = OrenAVMRuntimeWebSocketAccept(key);
    if (!key || !accept) return NO;

    NSString* path = url.path.length > 0 ? url.path : @"/";
    if (url.query.length > 0) path = [path stringByAppendingFormat:@"?%@", url.query];
    NSString* hostHeader = url.port ? [NSString stringWithFormat:@"%@:%@", url.host, url.port] : url.host;
    NSString* request = [NSString stringWithFormat:
        @"GET %@ HTTP/1.1\r\n"
         "Host: %@\r\n"
         "Upgrade: websocket\r\n"
         "Connection: Upgrade\r\n"
         "Sec-WebSocket-Key: %@\r\n"
         "Sec-WebSocket-Version: 13\r\n\r\n",
        path, hostHeader, key];
    NSData* requestData = [request dataUsingEncoding:NSASCIIStringEncoding];
    if (!requestData) return NO;
    OrenAVMRuntimeSetSocketTimeout(fd, timeoutMs);
    if (OrenAVMRuntimeSendAll(fd, requestData.bytes, requestData.length) != 0) return NO;

    NSMutableData* response = [NSMutableData data];
    uint8_t tmp[512];
    BOOL complete = NO;
    while (response.length < 8192u) {
        ssize_t n = recv(fd, tmp, sizeof(tmp), 0);
        if (n <= 0) return NO;
        [response appendBytes:tmp length:(NSUInteger)n];
        const uint8_t* p = response.bytes;
        for (NSUInteger i = 3; i < response.length; i++) {
            if (p[i - 3] == '\r' && p[i - 2] == '\n' && p[i - 1] == '\r' && p[i] == '\n') {
                complete = YES;
                break;
            }
        }
        if (complete) break;
    }
    if (!complete) return NO;
    NSString* header = [[NSString alloc] initWithData:response encoding:NSASCIIStringEncoding];
    NSString* lower = header.lowercaseString;
    if (!header || ![header containsString:@" 101 "] || ![lower containsString:@"upgrade: websocket"]) return NO;
    if (![lower containsString:[accept lowercaseString]]) return NO;
    return YES;
}

static int OrenAVMRuntimeWebSocketWriteText(int fd, const uint8_t* data, size_t len) {
    if (len > 65535u) return -1;
    size_t headerLen = len < 126u ? 6u : 8u;
    size_t frameLen = headerLen + len;
    uint8_t* frame = (uint8_t*)malloc(frameLen);
    if (!frame) return -1;
    size_t off = 0;
    frame[off++] = 0x81u;
    if (len < 126u) {
        frame[off++] = (uint8_t)(0x80u | (uint8_t)len);
    } else {
        frame[off++] = 0xFEu;
        frame[off++] = (uint8_t)((len >> 8) & 255u);
        frame[off++] = (uint8_t)(len & 255u);
    }
    uint8_t mask[4];
    arc4random_buf(mask, sizeof(mask));
    memcpy(frame + off, mask, sizeof(mask));
    off += sizeof(mask);
    for (size_t i = 0; i < len; i++) frame[off + i] = data[i] ^ mask[i & 3u];
    int rc = OrenAVMRuntimeSendAll(fd, frame, frameLen);
    free(frame);
    return rc;
}

static int OrenAVMRuntimeWebSocketReadPayload(int fd, size_t maxLen, uint8_t** outData, size_t* outLen) {
    uint8_t head[2];
    if (OrenAVMRuntimeRecvExact(fd, head, sizeof(head)) != 0) return -1;
    uint8_t opcode = head[0] & 0x0Fu;
    BOOL masked = (head[1] & 0x80u) != 0;
    uint64_t payloadLen = (uint64_t)(head[1] & 0x7Fu);
    if (payloadLen == 126u) {
        uint8_t ext[2];
        if (OrenAVMRuntimeRecvExact(fd, ext, sizeof(ext)) != 0) return -1;
        payloadLen = ((uint64_t)ext[0] << 8) | (uint64_t)ext[1];
    } else if (payloadLen == 127u) {
        return -1;
    }
    uint8_t mask[4] = {0, 0, 0, 0};
    if (masked && OrenAVMRuntimeRecvExact(fd, mask, sizeof(mask)) != 0) return -1;
    if (payloadLen > maxLen || payloadLen > (16u * 1024u * 1024u)) return -1;
    uint8_t* payload = NULL;
    if (payloadLen > 0) {
        payload = (uint8_t*)malloc((size_t)payloadLen);
        if (!payload) return -1;
        if (OrenAVMRuntimeRecvExact(fd, payload, (size_t)payloadLen) != 0) {
            free(payload);
            return -1;
        }
        if (masked) {
            for (size_t i = 0; i < (size_t)payloadLen; i++) payload[i] ^= mask[i & 3u];
        }
    }
    if (opcode == 8u) {
        free(payload);
        *outData = NULL;
        *outLen = 0;
        return 0;
    }
    if (opcode != 1u && opcode != 2u) {
        free(payload);
        return -1;
    }
    *outData = payload;
    *outLen = (size_t)payloadLen;
    return 0;
}

static BOOL OrenAVMRuntimeCanUseSessionBytes(OrenAVMRuntime* runtime, uint32_t sessionId, uint64_t len) {
    if (runtime->_liveNetworkSessionByteLimitBytes == 0 || len == 0) return YES;
    __block BOOL allowed = NO;
    @synchronized (runtime) {
        uint64_t used = [runtime->_networkSessionByteCounts[@(sessionId)] unsignedLongLongValue];
        allowed = used <= runtime->_liveNetworkSessionByteLimitBytes &&
            len <= runtime->_liveNetworkSessionByteLimitBytes - used;
    }
    return allowed;
}

static size_t OrenAVMRuntimeClampSessionReadLen(OrenAVMRuntime* runtime, uint32_t sessionId, size_t maxLen) {
    if (runtime->_liveNetworkSessionByteLimitBytes == 0 || maxLen == 0) return maxLen;
    __block size_t out = 0;
    @synchronized (runtime) {
        uint64_t used = [runtime->_networkSessionByteCounts[@(sessionId)] unsignedLongLongValue];
        if (used < runtime->_liveNetworkSessionByteLimitBytes) {
            uint64_t remaining = runtime->_liveNetworkSessionByteLimitBytes - used;
            out = maxLen > remaining ? (size_t)remaining : maxLen;
        }
    }
    return out;
}

static void OrenAVMRuntimeChargeSessionBytes(OrenAVMRuntime* runtime, uint32_t sessionId, uint64_t len) {
    if (len == 0) return;
    @synchronized (runtime) {
        NSNumber* key = @(sessionId);
        uint64_t used = [runtime->_networkSessionByteCounts[key] unsignedLongLongValue];
        runtime->_networkSessionByteCounts[key] = @(used + len);
    }
}

static BOOL OrenAVMRuntimeFetchURLData(NSURL* url,
                                       NSSet<NSString*>* allowedHosts,
                                       NSTimeInterval timeoutSeconds,
                                       uint64_t ioLimitBytes,
                                       NSURLSession* reusableSession,
                                       NSData** outData,
                                       NSError** error) {
    NSString* scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"network fetch requires an http or https URL");
    }
    NSString* host = url.host;
    if (host.length == 0) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"network fetch URL must include a host");
    }
    if (allowedHosts.count > 0 && ![allowedHosts containsObject:host]) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_VM,
                                        @"network fetch host is not allowlisted");
    }

    NSTimeInterval effectiveTimeout = timeoutSeconds > 0.0 ? timeoutSeconds : 15.0;
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:effectiveTimeout];
    request.HTTPMethod = @"GET";

    NSURLSession* session = reusableSession;
    BOOL ownsSession = NO;
    if (!session) {
        NSURLSessionConfiguration* sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        sessionConfig.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        sessionConfig.timeoutIntervalForRequest = effectiveTimeout;
        sessionConfig.timeoutIntervalForResource = effectiveTimeout;
        session = [NSURLSession sessionWithConfiguration:sessionConfig];
        ownsSession = YES;
    }

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSData* responseData = nil;
    __block NSURLResponse* response = nil;
    __block NSError* requestError = nil;
    NSURLSessionDataTask* task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData* data, NSURLResponse* taskResponse, NSError* taskError) {
        responseData = data ? [data copy] : [NSData data];
        response = taskResponse;
        requestError = taskError;
        dispatch_semaphore_signal(done);
    }];
    [task resume];

    int64_t timeoutNanos = (int64_t)(effectiveTimeout * (NSTimeInterval)NSEC_PER_SEC);
    if (timeoutNanos <= 0) timeoutNanos = (int64_t)(15.0 * (NSTimeInterval)NSEC_PER_SEC);
    long waitResult = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, timeoutNanos));
    if (waitResult != 0) {
        [task cancel];
        if (ownsSession) [session finishTasksAndInvalidate];
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_VM,
                                        @"network fetch timed out");
    }
    if (ownsSession) [session finishTasksAndInvalidate];

    if (requestError) {
        if (error) *error = requestError;
        return NO;
    }
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger statusCode = ((NSHTTPURLResponse*)response).statusCode;
        if (statusCode < 200 || statusCode >= 300) {
            NSString* message = [NSString stringWithFormat:@"network fetch returned HTTP %ld", (long)statusCode];
            return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_VM, message);
        }
    }
    if (ioLimitBytes > 0 && responseData.length > ioLimitBytes) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_VM,
                                        @"network fetch response exceeds runtime I/O budget");
    }
    if (outData) *outData = responseData ?: [NSData data];
    return YES;
}

static int OrenAVMRuntimeLiveNetFetch(void* userData, const char* url, uint8_t** outData, size_t* outLen) {
    if (!userData || !url || !outData || !outLen) return -1;
    OrenAVMRuntime* runtime = (__bridge OrenAVMRuntime*)userData;
    NSURL* requestURL = [NSURL URLWithString:[NSString stringWithUTF8String:url] ?: @""];
    if (!requestURL) return -1;
    NSError* error = nil;
    NSData* data = nil;
    if (!OrenAVMRuntimeFetchURLData(requestURL,
                                    runtime->_liveNetworkAllowedHosts,
                                    runtime->_liveNetworkTimeoutSeconds,
                                    runtime->_ioLimitBytes,
                                    runtime->_networkSession,
                                    &data,
                                    &error)) {
        (void)error;
        return -1;
    }
    if (data.length > 0) {
        uint8_t* copy = (uint8_t*)malloc(data.length);
        if (!copy) return -1;
        memcpy(copy, data.bytes, data.length);
        *outData = copy;
        *outLen = data.length;
    } else {
        *outData = NULL;
        *outLen = 0;
    }
    return 0;
}

static int OrenAVMRuntimeNetResolve(void* userData, const char* host, uint32_t timeoutMs, char*** outIPs, size_t* outCount) {
    (void)timeoutMs;
    if (!userData || !host || !outIPs || !outCount) return -1;
    *outIPs = NULL;
    *outCount = 0;
    OrenAVMRuntime* runtime = (__bridge OrenAVMRuntime*)userData;
    NSString* hostString = [NSString stringWithUTF8String:host] ?: @"";
    if (hostString.length == 0) return -1;
    if (runtime->_liveNetworkAllowedHosts.count > 0 && ![runtime->_liveNetworkAllowedHosts containsObject:hostString]) return -1;

    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    struct addrinfo* result = NULL;
    if (getaddrinfo(host, NULL, &hints, &result) != 0) return -1;

    const size_t cap = 16u;
    char** ips = (char**)calloc(cap, sizeof(char*));
    if (!ips) {
        freeaddrinfo(result);
        return -1;
    }
    size_t count = 0;
    for (struct addrinfo* ai = result; ai && count < cap; ai = ai->ai_next) {
        char buf[INET6_ADDRSTRLEN];
        const void* addr = NULL;
        if (ai->ai_family == AF_INET) {
            addr = &((struct sockaddr_in*)ai->ai_addr)->sin_addr;
        } else if (ai->ai_family == AF_INET6) {
            addr = &((struct sockaddr_in6*)ai->ai_addr)->sin6_addr;
        } else {
            continue;
        }
        if (!inet_ntop(ai->ai_family, addr, buf, sizeof(buf))) continue;
        BOOL duplicate = NO;
        for (size_t i = 0; i < count; i++) {
            if (strcmp(ips[i], buf) == 0) {
                duplicate = YES;
                break;
            }
        }
        if (duplicate) continue;
        size_t len = strlen(buf);
        ips[count] = (char*)malloc(len + 1u);
        if (!ips[count]) {
            for (size_t i = 0; i < count; i++) free(ips[i]);
            free(ips);
            freeaddrinfo(result);
            return -1;
        }
        memcpy(ips[count], buf, len + 1u);
        count++;
    }
    freeaddrinfo(result);
    if (count == 0) {
        free(ips);
        return -1;
    }
    *outIPs = ips;
    *outCount = count;
    return 0;
}

static int OrenAVMRuntimeNetSessionOpen(void* userData, const char* spec, uint32_t timeoutMs, uint32_t* outSessionId) {
    if (!userData || !spec || !outSessionId) return -1;
    OrenAVMRuntime* runtime = (__bridge OrenAVMRuntime*)userData;
    NSURL* url = [NSURL URLWithString:[NSString stringWithUTF8String:spec] ?: @""];
    NSString* scheme = url.scheme.lowercaseString;
    BOOL isTCP = [scheme isEqualToString:@"tcp"];
    BOOL isTCPListen = [scheme isEqualToString:@"tcp-listen"];
    BOOL isUDP = [scheme isEqualToString:@"udp"];
    BOOL isWS = [scheme isEqualToString:@"ws"];
    if (!url || (!isTCP && !isTCPListen && !isUDP && !isWS) || url.host.length == 0 || !url.port) return -1;
    if (runtime->_liveNetworkAllowedHosts.count > 0 && ![runtime->_liveNetworkAllowedHosts containsObject:url.host]) return -1;

    char service[16];
    snprintf(service, sizeof(service), "%u", url.port.unsignedIntValue);
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = isUDP ? SOCK_DGRAM : SOCK_STREAM;
    hints.ai_protocol = isUDP ? IPPROTO_UDP : IPPROTO_TCP;
    if (isTCPListen) hints.ai_flags = AI_PASSIVE;
    struct addrinfo* result = NULL;
    if (getaddrinfo(url.host.UTF8String, service, &hints, &result) != 0) return -1;

    int fd = -1;
    for (struct addrinfo* ai = result; ai; ai = ai->ai_next) {
        fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) continue;
        OrenAVMRuntimeSetSocketTimeout(fd, timeoutMs);
        if (isTCPListen) {
            int yes = 1;
            (void)setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
            if (bind(fd, ai->ai_addr, ai->ai_addrlen) == 0 && listen(fd, 16) == 0) break;
        } else if (connect(fd, ai->ai_addr, ai->ai_addrlen) == 0) {
            break;
        }
        close(fd);
        fd = -1;
    }
    freeaddrinfo(result);
    if (fd < 0) return -1;
    if (isWS && !OrenAVMRuntimeWebSocketHandshake(fd, url, timeoutMs)) {
        close(fd);
        return -1;
    }

    NSString* kind = isTCPListen ? @"tcp-listen" : (isWS ? @"ws" : (isUDP ? @"udp" : @"tcp"));
    uint32_t sid = OrenAVMRuntimeRegisterNetworkSession(runtime, fd, kind);
    if (sid == 0) {
        close(fd);
        return -1;
    }
    *outSessionId = sid;
    return 0;
}

static int OrenAVMRuntimeNetSessionWrite(void* userData, uint32_t sessionId, const uint8_t* data, size_t len, uint32_t timeoutMs, size_t* outWritten) {
    if (!userData || (!data && len > 0) || !outWritten) return -1;
    OrenAVMRuntime* runtime = (__bridge OrenAVMRuntime*)userData;
    int fd = OrenAVMRuntimeSocketForSession(runtime, sessionId);
    if (fd < 0) return -1;
    if (!OrenAVMRuntimeCanUseSessionBytes(runtime, sessionId, (uint64_t)len)) return -1;
    OrenAVMRuntimeSetSocketTimeout(fd, timeoutMs);
    NSString* kind = OrenAVMRuntimeKindForSession(runtime, sessionId);
    if ([kind isEqualToString:@"ws"]) {
        if (OrenAVMRuntimeWebSocketWriteText(fd, data, len) != 0) return -1;
        OrenAVMRuntimeChargeSessionBytes(runtime, sessionId, (uint64_t)len);
        *outWritten = len;
        return 0;
    }
    if (OrenAVMRuntimeSendAll(fd, data, len) != 0) return -1;
    OrenAVMRuntimeChargeSessionBytes(runtime, sessionId, (uint64_t)len);
    *outWritten = len;
    return 0;
}

static int OrenAVMRuntimeNetSessionRead(void* userData, uint32_t sessionId, size_t maxLen, uint32_t timeoutMs, uint8_t** outData, size_t* outLen) {
    if (!userData || !outData || !outLen || maxLen > (16u * 1024u * 1024u)) return -1;
    *outData = NULL;
    *outLen = 0;
    OrenAVMRuntime* runtime = (__bridge OrenAVMRuntime*)userData;
    int fd = OrenAVMRuntimeSocketForSession(runtime, sessionId);
    if (fd < 0) return -1;
    maxLen = OrenAVMRuntimeClampSessionReadLen(runtime, sessionId, maxLen);
    if (maxLen == 0) return 0;
    NSString* kind = OrenAVMRuntimeKindForSession(runtime, sessionId);
    if ([kind isEqualToString:@"ws"]) {
        uint8_t* payload = NULL;
        size_t payloadLen = 0;
        OrenAVMRuntimeSetSocketTimeout(fd, timeoutMs);
        if (OrenAVMRuntimeWebSocketReadPayload(fd, maxLen, &payload, &payloadLen) != 0) return -1;
        OrenAVMRuntimeChargeSessionBytes(runtime, sessionId, (uint64_t)payloadLen);
        *outData = payload;
        *outLen = payloadLen;
        return 0;
    }
    uint8_t* buf = (uint8_t*)malloc(maxLen);
    if (!buf) return -1;
    OrenAVMRuntimeSetSocketTimeout(fd, timeoutMs);
    ssize_t n = recv(fd, buf, maxLen, 0);
    if (n < 0) {
        free(buf);
        return -1;
    }
    if (n == 0) {
        free(buf);
        return 0;
    }
    OrenAVMRuntimeChargeSessionBytes(runtime, sessionId, (uint64_t)n);
    *outData = buf;
    *outLen = (size_t)n;
    return 0;
}

static int OrenAVMRuntimeNetSessionAccept(void* userData, uint32_t listenerSessionId, uint32_t timeoutMs, uint32_t* outSessionId) {
    if (!userData || !outSessionId) return -1;
    *outSessionId = 0;
    OrenAVMRuntime* runtime = (__bridge OrenAVMRuntime*)userData;
    int fd = OrenAVMRuntimeSocketForSession(runtime, listenerSessionId);
    if (fd < 0) return -1;
    NSString* kind = OrenAVMRuntimeKindForSession(runtime, listenerSessionId);
    if (![kind isEqualToString:@"tcp-listen"]) return -1;

    fd_set rfds;
    FD_ZERO(&rfds);
    FD_SET(fd, &rfds);
    struct timeval tv;
    tv.tv_sec = (time_t)(timeoutMs / 1000u);
    tv.tv_usec = (suseconds_t)((timeoutMs % 1000u) * 1000u);
    int rc = select(fd + 1, &rfds, NULL, NULL, &tv);
    if (rc <= 0) return -1;

    int child = accept(fd, NULL, NULL);
    if (child < 0) return -1;
    OrenAVMRuntimeSetSocketTimeout(child, timeoutMs);
    uint32_t sid = OrenAVMRuntimeRegisterNetworkSession(runtime, child, @"tcp");
    if (sid == 0) {
        close(child);
        return -1;
    }
    *outSessionId = sid;
    return 0;
}

static int OrenAVMRuntimeNetSessionPoll(void* userData, uint32_t sessionId, uint32_t events, uint32_t timeoutMs, uint32_t* outReady) {
    if (!userData || !outReady || events == 0 || (events & ~3u) != 0) return -1;
    *outReady = 0;
    OrenAVMRuntime* runtime = (__bridge OrenAVMRuntime*)userData;
    int fd = OrenAVMRuntimeSocketForSession(runtime, sessionId);
    if (fd < 0) return -1;

    fd_set rfds;
    fd_set wfds;
    fd_set* rp = NULL;
    fd_set* wp = NULL;
    if ((events & 1u) != 0) {
        FD_ZERO(&rfds);
        FD_SET(fd, &rfds);
        rp = &rfds;
    }
    if ((events & 2u) != 0) {
        FD_ZERO(&wfds);
        FD_SET(fd, &wfds);
        wp = &wfds;
    }
    struct timeval tv;
    tv.tv_sec = (time_t)(timeoutMs / 1000u);
    tv.tv_usec = (suseconds_t)((timeoutMs % 1000u) * 1000u);
    int rc = select(fd + 1, rp, wp, NULL, &tv);
    if (rc < 0) return -1;
    uint32_t ready = 0;
    if (rc > 0) {
        if (rp && FD_ISSET(fd, rp)) ready |= 1u;
        if (wp && FD_ISSET(fd, wp)) ready |= 2u;
    }
    *outReady = ready & events;
    return 0;
}

static int OrenAVMRuntimeNetSessionSelect(void* userData, const uint32_t* sessionIds, const uint32_t* events, size_t count, uint32_t timeoutMs, size_t* outIndex, uint32_t* outReady) {
    if (!userData || !sessionIds || !events || !outIndex || !outReady || count == 0) return -1;
    *outIndex = count;
    *outReady = 0;
    OrenAVMRuntime* runtime = (__bridge OrenAVMRuntime*)userData;

    fd_set rfds;
    fd_set wfds;
    FD_ZERO(&rfds);
    FD_ZERO(&wfds);
    int maxfd = -1;
    int fds[1024];
    if (count > sizeof(fds) / sizeof(fds[0])) return -1;
    for (size_t i = 0; i < count; i++) {
        if (events[i] == 0 || (events[i] & ~3u) != 0) return -1;
        int fd = OrenAVMRuntimeSocketForSession(runtime, sessionIds[i]);
        if (fd < 0 || fd >= FD_SETSIZE) return -1;
        fds[i] = fd;
        if ((events[i] & 1u) != 0) FD_SET(fd, &rfds);
        if ((events[i] & 2u) != 0) FD_SET(fd, &wfds);
        if (fd > maxfd) maxfd = fd;
    }
    if (maxfd < 0) return -1;

    struct timeval tv;
    tv.tv_sec = (time_t)(timeoutMs / 1000u);
    tv.tv_usec = (suseconds_t)((timeoutMs % 1000u) * 1000u);
    int rc = select(maxfd + 1, &rfds, &wfds, NULL, &tv);
    if (rc < 0) return -1;
    if (rc == 0) return 0;
    for (size_t i = 0; i < count; i++) {
        uint32_t ready = 0;
        int fd = fds[i];
        if ((events[i] & 1u) != 0 && FD_ISSET(fd, &rfds)) ready |= 1u;
        if ((events[i] & 2u) != 0 && FD_ISSET(fd, &wfds)) ready |= 2u;
        ready &= events[i];
        if (ready != 0) {
            *outIndex = i;
            *outReady = ready;
            return 0;
        }
    }
    return 0;
}

static int OrenAVMRuntimeNetSessionClose(void* userData, uint32_t sessionId) {
    if (!userData) return -1;
    OrenAVMRuntime* runtime = (__bridge OrenAVMRuntime*)userData;
    int fd = -1;
    @synchronized (runtime) {
        NSNumber* key = @(sessionId);
        NSNumber* value = runtime->_networkSockets[key];
        if (value) {
            fd = value.intValue;
            [runtime->_networkSockets removeObjectForKey:key];
            [runtime->_networkSessionKinds removeObjectForKey:key];
            [runtime->_networkSessionByteCounts removeObjectForKey:key];
        }
    }
    if (fd < 0) return -1;
    close(fd);
    return 0;
}

- (instancetype)initWithConfig:(OrenAVMRuntimeConfig*)config {
    self = [super init];
    if (!self) return nil;
    OrenAVMRuntimeConfig* effective = config ?: [OrenAVMRuntimeConfig deterministicDefaults];
    _ioLimitBytes = effective.ioLimitBytes;
    _liveNetworkMaxSessions = effective.liveNetworkMaxSessions;
    _liveNetworkSessionByteLimitBytes = effective.liveNetworkSessionByteLimitBytes;
    AvmEmbedConfig embedConfig = [effective makeEmbedConfig];
    AvmEmbedResult result;
    _handle = avm_embed_open(&embedConfig, &result);
    if (!_handle || result.status != AVM_EMBED_OK) return nil;
    avm_embed_set_output_capture(_handle, 1, &result);
    NSURLSessionConfiguration* sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    sessionConfig.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    _networkSession = [NSURLSession sessionWithConfiguration:sessionConfig];
    _networkSockets = [NSMutableDictionary dictionary];
    _networkSessionKinds = [NSMutableDictionary dictionary];
    _networkSessionByteCounts = [NSMutableDictionary dictionary];
    _nextNetworkSessionId = 0;
    if (effective.liveNetworkEnabled) {
        _liveNetworkAllowedHosts = [effective.liveNetworkAllowedHosts copy];
        _liveNetworkTimeoutSeconds = effective.liveNetworkTimeoutSeconds > 0.0 ? effective.liveNetworkTimeoutSeconds : 15.0;
        if (avm_embed_set_net_fetch_callback(_handle, OrenAVMRuntimeLiveNetFetch, (__bridge void*)self, &result) != AVM_EMBED_OK) {
            avm_embed_close(_handle);
            _handle = NULL;
            return nil;
        }
        if (avm_embed_set_net_session_callbacks(_handle, OrenAVMRuntimeNetSessionOpen, OrenAVMRuntimeNetSessionWrite, OrenAVMRuntimeNetSessionRead, OrenAVMRuntimeNetSessionPoll, OrenAVMRuntimeNetSessionSelect, OrenAVMRuntimeNetSessionAccept, OrenAVMRuntimeNetSessionClose, (__bridge void*)self, &result) != AVM_EMBED_OK) {
            avm_embed_close(_handle);
            _handle = NULL;
            return nil;
        }
        if (avm_embed_set_net_resolve_callback(_handle, OrenAVMRuntimeNetResolve, (__bridge void*)self, &result) != AVM_EMBED_OK) {
            avm_embed_close(_handle);
            _handle = NULL;
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
	if (_handle) avm_embed_set_gfx_frame_callback(_handle, NULL, NULL, NULL);
	@synchronized (self) {
		for (NSNumber* fdValue in _networkSockets.allValues) close(fdValue.intValue);
		[_networkSockets removeAllObjects];
        [_networkSessionKinds removeAllObjects];
        [_networkSessionByteCounts removeAllObjects];
    }
    [_networkSession invalidateAndCancel];
	if (_handle) avm_embed_close(_handle);
}

- (AvmEmbedHandle*)handle {
	return _handle;
}

- (void)setGraphicsFrameHandler:(OrenAVMGraphicsFrameHandler)graphicsFrameHandler {
	@synchronized (self) {
		_graphicsFrameHandler = [graphicsFrameHandler copy];
	}
	AvmEmbedResult result;
	(void)avm_embed_set_gfx_frame_callback(_handle,
	                                       graphicsFrameHandler ? OrenAVMRuntimeGraphicsFramePublished : NULL,
	                                       graphicsFrameHandler ? (__bridge void*)self : NULL,
	                                       &result);
}

- (OrenAVMGraphicsFrameHandler)graphicsFrameHandler {
	@synchronized (self) {
		return [_graphicsFrameHandler copy];
	}
}

- (BOOL)beginExclusiveRunWithError:(NSError**)error {
    @synchronized (self) {
        if (_runInProgress) {
            return OrenAVMKitAssignSDKError(error,
                                           AVM_EMBED_ERR_INVALID_ARG,
                                           @"OrenAVMRuntime is already running; use one runtime per concurrent run or call requestCancelWithError:");
        }
        _runInProgress = YES;
    }
    return YES;
}

- (void)endExclusiveRun {
    @synchronized (self) {
        _runInProgress = NO;
    }
}

- (BOOL)setArgv:(NSArray<NSString*>*)argv error:(NSError**)error {
    NSUInteger count = argv.count;
    const char** cargv = NULL;
    if (count > 0) {
        cargv = (const char**)calloc(count, sizeof(const char*));
        if (!cargv) return OrenAVMKitAssignError(error, @"out of memory", NULL);
    }
    for (NSUInteger i = 0; i < count; i++) cargv[i] = argv[i].UTF8String;
    AvmEmbedResult result;
    int rc = avm_embed_set_argv(_handle, (int)count, cargv, &result);
    free(cargv);
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to set argv", &result);
    return YES;
}

- (BOOL)putVFSFileAtPath:(NSString*)path data:(NSData*)data error:(NSError**)error {
    AvmEmbedResult result;
    int rc = avm_embed_vfs_put(_handle, path.UTF8String, data.bytes, data.length, &result);
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to write VFS file", &result);
    return YES;
}

- (NSData*)getVFSFileAtPath:(NSString*)path error:(NSError**)error {
    uint8_t* bytes = NULL;
    size_t len = 0;
    AvmEmbedResult result;
    int rc = avm_embed_vfs_get(_handle, path.UTF8String, &bytes, &len, &result);
    if (rc != AVM_EMBED_OK) {
        OrenAVMKitAssignError(error, @"failed to read VFS file", &result);
        return nil;
    }
    NSData* out = [NSData dataWithBytes:bytes length:len];
    avm_embed_free_bytes(bytes);
    return out;
}

- (BOOL)mountFileURL:(NSURL*)fileURL atVFSPath:(NSString*)vfsPath error:(NSError**)error {
    if (!fileURL.isFileURL || vfsPath.length == 0) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"mountFileURL requires a file URL and non-empty VFS path");
    }
    NSNumber* isRegular = nil;
    NSError* localError = nil;
    if (![fileURL getResourceValue:&isRegular forKey:NSURLIsRegularFileKey error:&localError]) {
        if (error) *error = localError;
        return NO;
    }
    if (!isRegular.boolValue) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"mountFileURL requires a regular file");
    }
    NSData* data = [NSData dataWithContentsOfURL:fileURL options:0 error:&localError];
    if (!data) {
        if (error) *error = localError;
        return NO;
    }
    return [self putVFSFileAtPath:vfsPath data:data error:error];
}

- (BOOL)mountDirectoryURL:(NSURL*)directoryURL atVFSRoot:(NSString*)vfsRoot error:(NSError**)error {
    if (!directoryURL.isFileURL || vfsRoot.length == 0) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"mountDirectoryURL requires a file URL and non-empty VFS root");
    }
    NSNumber* isDirectory = nil;
    NSError* localError = nil;
    if (![directoryURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&localError]) {
        if (error) *error = localError;
        return NO;
    }
    if (!isDirectory.boolValue) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"mountDirectoryURL requires a directory");
    }

    NSString* basePath = directoryURL.path.stringByStandardizingPath;
    __block NSError* enumerationError = nil;
    NSDirectoryEnumerator<NSURL*>* enumerator =
        [[NSFileManager defaultManager] enumeratorAtURL:directoryURL
                             includingPropertiesForKeys:@[NSURLIsRegularFileKey]
                                                options:0
                                           errorHandler:^BOOL(NSURL* url, NSError* enumError) {
        (void)url;
        enumerationError = enumError;
        return NO;
    }];
    for (NSURL* childURL in enumerator) {
        if (enumerationError) {
            if (error) *error = enumerationError;
            return NO;
        }
        NSNumber* isRegular = nil;
        if (![childURL getResourceValue:&isRegular forKey:NSURLIsRegularFileKey error:&localError]) {
            if (error) *error = localError;
            return NO;
        }
        if (!isRegular.boolValue) continue;
        NSString* childPath = childURL.path.stringByStandardizingPath;
        if (![childPath isEqualToString:basePath] &&
            ![childPath hasPrefix:[basePath stringByAppendingString:@"/"]]) {
            return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_VM,
                                            @"mountDirectoryURL encountered path outside base directory");
        }
        NSString* relative = [childPath substringFromIndex:basePath.length];
        NSString* vfsPath = OrenAVMKitJoinVFSPath(vfsRoot, relative);
        if (![self mountFileURL:childURL atVFSPath:vfsPath error:error]) return NO;
    }
    if (enumerationError) {
        if (error) *error = enumerationError;
        return NO;
    }
    return YES;
}

- (BOOL)mountHostDirectoryURL:(NSURL*)directoryURL
                    atVFSRoot:(NSString*)vfsRoot
                     readable:(BOOL)readable
                     writable:(BOOL)writable
                        error:(NSError**)error {
    if (!directoryURL.isFileURL || vfsRoot.length == 0 || (!readable && !writable)) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"mountHostDirectoryURL requires a file URL, non-empty VFS root, and at least one access mode");
    }
    NSNumber* isDirectory = nil;
    NSError* localError = nil;
    if (![directoryURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&localError]) {
        if (error) *error = localError;
        return NO;
    }
    if (!isDirectory.boolValue) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"mountHostDirectoryURL requires a directory");
    }
    NSString* hostRoot = directoryURL.path.stringByStandardizingPath;
    AvmEmbedResult result;
    int rc = AVM_EMBED_OK;
    if (readable && writable) {
        rc = avm_embed_fs_mount(_handle, vfsRoot.UTF8String, hostRoot.UTF8String, &result);
    } else if (readable) {
        rc = avm_embed_fs_mount_read(_handle, vfsRoot.UTF8String, hostRoot.UTF8String, &result);
    } else {
        rc = avm_embed_fs_mount_write(_handle, vfsRoot.UTF8String, hostRoot.UTF8String, &result);
    }
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to mount host directory into AVM FS", &result);
    return YES;
}

- (BOOL)exportVFSFileAtPath:(NSString*)vfsPath
                  toFileURL:(NSURL*)fileURL
createIntermediateDirectories:(BOOL)createIntermediateDirectories
                      error:(NSError**)error {
    if (!fileURL.isFileURL || vfsPath.length == 0) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"exportVFSFile requires a file URL and non-empty VFS path");
    }
    NSData* data = [self getVFSFileAtPath:vfsPath error:error];
    if (!data) return NO;
    NSError* localError = nil;
    if (createIntermediateDirectories) {
        NSURL* parent = [fileURL URLByDeletingLastPathComponent];
        if (parent) {
            if (![[NSFileManager defaultManager] createDirectoryAtURL:parent
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:&localError]) {
                if (error) *error = localError;
                return NO;
            }
        }
    }
    if (![data writeToURL:fileURL options:NSDataWritingAtomic error:&localError]) {
        if (error) *error = localError;
        return NO;
    }
    return YES;
}

- (BOOL)putVirtualNetResponseForURL:(NSString*)url data:(NSData*)data error:(NSError**)error {
    AvmEmbedResult result;
    int rc = avm_embed_vnet_put(_handle, url.UTF8String, data.bytes, data.length, &result);
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to write VirtualNET fixture", &result);
    return YES;
}

- (BOOL)enableLiveNetworkWithAllowedHosts:(NSSet<NSString*>*)allowedHosts
                           timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                    error:(NSError**)error {
    _liveNetworkAllowedHosts = [allowedHosts copy];
    _liveNetworkTimeoutSeconds = timeoutSeconds > 0.0 ? timeoutSeconds : 15.0;
    AvmEmbedResult result;
    int rc = avm_embed_set_net_fetch_callback(_handle, OrenAVMRuntimeLiveNetFetch, (__bridge void*)self, &result);
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to set live NET callback", &result);
    rc = avm_embed_set_net_session_callbacks(_handle, OrenAVMRuntimeNetSessionOpen, OrenAVMRuntimeNetSessionWrite, OrenAVMRuntimeNetSessionRead, OrenAVMRuntimeNetSessionPoll, OrenAVMRuntimeNetSessionSelect, OrenAVMRuntimeNetSessionAccept, OrenAVMRuntimeNetSessionClose, (__bridge void*)self, &result);
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to set live NET session callbacks", &result);
    rc = avm_embed_set_net_resolve_callback(_handle, OrenAVMRuntimeNetResolve, (__bridge void*)self, &result);
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to set live NET resolve callback", &result);
    return YES;
}

- (BOOL)configureLiveNetworkSessionLimitsWithMaxSessions:(uint32_t)maxSessions
                                          byteLimitBytes:(uint64_t)byteLimitBytes
                                                   error:(NSError**)error {
    @synchronized (self) {
        if (maxSessions > 0 && _networkSockets.count > maxSessions) {
            return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_VM,
                                            @"live NET max sessions is below current open session count");
        }
        if (byteLimitBytes > 0) {
            for (NSNumber* usedValue in _networkSessionByteCounts.allValues) {
                if (usedValue.unsignedLongLongValue > byteLimitBytes) {
                    return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_VM,
                                                    @"live NET byte limit is below current session usage");
                }
            }
        }
        _liveNetworkMaxSessions = maxSessions;
        _liveNetworkSessionByteLimitBytes = byteLimitBytes;
    }
    return YES;
}

- (BOOL)disableLiveNetworkWithError:(NSError**)error {
    _liveNetworkAllowedHosts = nil;
    _liveNetworkTimeoutSeconds = 15.0;
    AvmEmbedResult result;
    int rc = avm_embed_set_net_fetch_callback(_handle, NULL, NULL, &result);
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to clear live NET callback", &result);
    rc = avm_embed_set_net_session_callbacks(_handle, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, &result);
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to clear live NET session callbacks", &result);
    rc = avm_embed_set_net_resolve_callback(_handle, NULL, NULL, &result);
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to clear live NET resolve callback", &result);
    @synchronized (self) {
        for (NSNumber* fdValue in _networkSockets.allValues) close(fdValue.intValue);
        [_networkSockets removeAllObjects];
        [_networkSessionKinds removeAllObjects];
        [_networkSessionByteCounts removeAllObjects];
    }
    return YES;
}

- (BOOL)fetchURLIntoVirtualNet:(NSURL*)url
                  allowedHosts:(NSSet<NSString*>*)allowedHosts
                timeoutSeconds:(NSTimeInterval)timeoutSeconds
                          error:(NSError**)error {
    NSData* responseData = nil;
    if (!OrenAVMRuntimeFetchURLData(url, allowedHosts, timeoutSeconds, _ioLimitBytes, _networkSession, &responseData, error)) return NO;
    return [self putVirtualNetResponseForURL:url.absoluteString data:(responseData ?: [NSData data]) error:error];
}

- (BOOL)putVirtualProcExitForCommand:(NSString*)command exitCode:(int)exitCode error:(NSError**)error {
    AvmEmbedResult result;
    int rc = avm_embed_vproc_put(_handle, command.UTF8String, exitCode, &result);
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to write VirtualPROC fixture", &result);
    return YES;
}

- (BOOL)setVirtualProcDefaultExitCode:(int)exitCode error:(NSError**)error {
    AvmEmbedResult result;
    int rc = avm_embed_vproc_set_default_exit(_handle, exitCode, &result);
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to set VirtualPROC default", &result);
    return YES;
}

- (OrenAVMRunResult*)runOBCData:(NSData*)obcData error:(NSError**)error {
    if (![self beginExclusiveRunWithError:error]) return nil;
    OrenAVMRunResult* runResult = nil;
    AvmEmbedResult result;
    int rc = avm_embed_run_obc_bytes(_handle, obcData.bytes, obcData.length, &result);
    if (rc != AVM_EMBED_OK) {
        OrenAVMKitAssignError(error, @"failed to run OBC", &result);
    } else {
        uint8_t* stdoutBytes = NULL;
        size_t stdoutLen = 0;
        AvmEmbedResult outputResult;
        NSData* stdoutData = [NSData data];
        if (avm_embed_output_get(_handle, &stdoutBytes, &stdoutLen, &outputResult) == AVM_EMBED_OK) {
            stdoutData = [NSData dataWithBytes:stdoutBytes length:stdoutLen];
            avm_embed_free_bytes(stdoutBytes);
        }
        runResult = [[OrenAVMRunResult alloc] initWithResult:&result stdoutData:stdoutData];
    }
    [self endExclusiveRun];
    return runResult;
}

- (BOOL)requestCancelWithError:(NSError**)error {
    AvmEmbedResult result;
    int rc = avm_embed_cancel(_handle, &result);
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to request AVM cancel", &result);
    return YES;
}

- (BOOL)clearCancelWithError:(NSError**)error {
    AvmEmbedResult result;
    int rc = avm_embed_clear_cancel(_handle, &result);
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to clear AVM cancel", &result);
    return YES;
}

- (NSUInteger)capturedOutputLengthWithError:(NSError**)error {
    size_t len = 0;
    AvmEmbedResult result;
    int rc = avm_embed_output_info(_handle, &len, &result);
    if (rc != AVM_EMBED_OK) {
        OrenAVMKitAssignError(error, @"failed to read AVM output info", &result);
        return 0;
    }
    return (NSUInteger)len;
}

- (BOOL)hasGraphicsFrameWithError:(NSError**)error {
	size_t len = 0;
	uint32_t sequence = 0;
	AvmEmbedResult result;
	int rc = avm_embed_gfx_frame_info(_handle, &len, &sequence, &result);
	if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to read GFX frame info", &result);
	return len > 0;
}

- (NSData*)getGraphicsFrameDataWithError:(NSError**)error {
    uint8_t* bytes = NULL;
    size_t len = 0;
    AvmEmbedResult result;
    int rc = avm_embed_gfx_frame_get(_handle, &bytes, &len, &result);
    if (rc != AVM_EMBED_OK) {
        OrenAVMKitAssignError(error, @"failed to read GFX frame", &result);
        return nil;
    }
    NSData* out = [NSData dataWithBytes:bytes length:len];
    avm_embed_free_bytes(bytes);
    return out;
}

- (BOOL)clearGraphicsFrameWithError:(NSError**)error {
    AvmEmbedResult result;
    int rc = avm_embed_gfx_frame_clear(_handle, &result);
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to clear GFX frame", &result);
    return YES;
}

- (BOOL)hasPermissionRequestWithError:(NSError**)error {
    size_t len = 0;
    uint32_t sequence = 0;
    AvmEmbedResult result;
    int rc = avm_embed_permission_request_info(_handle, &len, &sequence, &result);
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to read permission request info", &result);
    return len > 0;
}

- (NSNumber*)permissionRequestSequenceWithError:(NSError**)error {
    size_t len = 0;
    uint32_t sequence = 0;
    AvmEmbedResult result;
    int rc = avm_embed_permission_request_info(_handle, &len, &sequence, &result);
    if (rc != AVM_EMBED_OK) {
        OrenAVMKitAssignError(error, @"failed to read permission request info", &result);
        return nil;
    }
    return len > 0 ? @(sequence) : nil;
}

- (NSData*)getPermissionRequestDataWithError:(NSError**)error {
    uint8_t* bytes = NULL;
    size_t len = 0;
    AvmEmbedResult result;
    int rc = avm_embed_permission_request_get(_handle, &bytes, &len, &result);
    if (rc != AVM_EMBED_OK) {
        OrenAVMKitAssignError(error, @"failed to read permission request", &result);
        return nil;
    }
    NSData* out = [NSData dataWithBytes:bytes length:len];
    avm_embed_free_bytes(bytes);
    return out;
}

- (NSDictionary<NSString*, id>*)getPermissionRequestWithError:(NSError**)error {
    NSData* data = [self getPermissionRequestDataWithError:error];
    if (!data) return nil;
    const uint8_t* b = (const uint8_t*)data.bytes;
    NSUInteger len = data.length;
    if (len < 20 || b[0] != 'O' || b[1] != 'P' || b[2] != 'R' || b[3] != '0') {
        OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG, @"invalid permission request payload");
        return nil;
    }
    uint16_t version = OrenAVMKitReadU16LE(b + 4);
    uint16_t headerLen = OrenAVMKitReadU16LE(b + 6);
    uint32_t sequence = OrenAVMKitReadU32LE(b + 8);
    uint16_t domainLen = OrenAVMKitReadU16LE(b + 12);
    uint16_t actionLen = OrenAVMKitReadU16LE(b + 14);
    uint32_t detailLen = OrenAVMKitReadU32LE(b + 16);
    if (version != 1 || headerLen < 20 || headerLen > len ||
        (NSUInteger)headerLen + (NSUInteger)domainLen + (NSUInteger)actionLen + (NSUInteger)detailLen != len) {
        OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG, @"invalid permission request lengths");
        return nil;
    }
    const uint8_t* p = b + headerLen;
    NSString* domain = OrenAVMKitUTF8Field(p, domainLen); p += domainLen;
    NSString* action = OrenAVMKitUTF8Field(p, actionLen); p += actionLen;
    NSString* detail = OrenAVMKitUTF8Field(p, detailLen);
    if (!domain || !action || !detail) {
        OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG, @"permission request contains invalid UTF-8");
        return nil;
    }
    return @{
        @"schema": @"oren.permission.request.v0",
        @"sequence": @(sequence),
        @"domain": domain,
        @"action": action,
        @"detail": detail
    };
}

- (BOOL)clearPermissionRequestWithError:(NSError**)error {
    AvmEmbedResult result;
    int rc = avm_embed_permission_request_clear(_handle, &result);
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to clear permission request", &result);
    return YES;
}

- (BOOL)putGraphicsInputEventData:(NSData*)data error:(NSError**)error {
    if (!data || data.length == 0) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"GFX input event data must be non-empty");
    }
    AvmEmbedResult result;
    int rc = avm_embed_gfx_input_put(_handle, data.bytes, data.length, &result);
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to enqueue GFX input event", &result);
    return YES;
}

- (BOOL)setGraphicsScreenWithID:(uint32_t)screenID
                           width:(uint32_t)width
                          height:(uint32_t)height
                      scaleMilli:(uint32_t)scaleMilli
                   drawableWidth:(uint32_t)drawableWidth
                  drawableHeight:(uint32_t)drawableHeight
                   targetHzMilli:(uint32_t)targetHzMilli
                           flags:(uint32_t)flags
                           error:(NSError**)error {
    AvmEmbedResult result;
    int rc = avm_embed_gfx_screen_set(_handle,
                                      screenID,
                                      width,
                                      height,
                                      scaleMilli,
                                      drawableWidth,
                                      drawableHeight,
                                      targetHzMilli,
                                      flags,
                                      &result);
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to set GFX screen state", &result);
    return YES;
}

- (BOOL)putVirtualEventWithKind:(NSString*)kind action:(NSString*)action detail:(NSString*)detail flags:(uint32_t)flags error:(NSError**)error {
    if (kind.length == 0 || action.length == 0) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"virtual event kind and action are required");
    }
    AvmEmbedResult result;
    int rc = avm_embed_event_put(_handle,
                                 kind.UTF8String,
                                 action.UTF8String,
                                 (detail ?: @"").UTF8String,
                                 flags,
                                 &result);
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to enqueue virtual event", &result);
    return YES;
}

@end
