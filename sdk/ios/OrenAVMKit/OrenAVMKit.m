#import "OrenAVMKit.h"

#import <dispatch/dispatch.h>
#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif
#include <math.h>
#include <string.h>

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

static void OrenAVMKitPutU32LE(uint8_t* dst, uint32_t v) {
    dst[0] = (uint8_t)(v & 255u);
    dst[1] = (uint8_t)((v >> 8) & 255u);
    dst[2] = (uint8_t)((v >> 16) & 255u);
    dst[3] = (uint8_t)((v >> 24) & 255u);
}

static NSData* OrenAVMKitMakeGFXEvent(uint8_t opcode, const uint8_t* payload, uint16_t payloadLen) {
    NSMutableData* data = [NSMutableData dataWithLength:(NSUInteger)12u + (NSUInteger)payloadLen];
    uint8_t* buf = (uint8_t*)data.mutableBytes;
    buf[0] = 'O'; buf[1] = 'G'; buf[2] = 'E'; buf[3] = '0';
    buf[4] = 0; buf[5] = 0; buf[6] = 0; buf[7] = 0;
    buf[8] = opcode; buf[9] = 0;
    buf[10] = (uint8_t)(payloadLen & 255u);
    buf[11] = (uint8_t)((payloadLen >> 8) & 255u);
    if (payloadLen > 0 && payload) memcpy(buf + 12, payload, payloadLen);
    return data;
}

#if TARGET_OS_IPHONE
static uint16_t OrenAVMGfxReadU16LE(const uint8_t* p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t OrenAVMGfxReadU32LE(const uint8_t* p) {
    return (uint32_t)p[0] |
        ((uint32_t)p[1] << 8) |
        ((uint32_t)p[2] << 16) |
        ((uint32_t)p[3] << 24);
}

static UIColor* OrenAVMGfxColor(const uint8_t* rgba) {
    return [UIColor colorWithRed:(CGFloat)rgba[0] / 255.0
                           green:(CGFloat)rgba[1] / 255.0
                            blue:(CGFloat)rgba[2] / 255.0
                           alpha:(CGFloat)rgba[3] / 255.0];
}
#endif

@implementation OrenAVMRuntimeConfig

+ (instancetype)deterministicDefaults {
    OrenAVMRuntimeConfig* cfg = [[self alloc] init];
    cfg.timeMode = OrenAVMTimeModeDeterministic;
    cfg.allowedDomains = OrenAVMDomainCore | OrenAVMDomainFS | OrenAVMDomainTime |
        OrenAVMDomainNet | OrenAVMDomainProc | OrenAVMDomainExit | OrenAVMDomainGFX;
    cfg.gasLimit = 5000000ull;
    cfg.heapLimitBytes = 32ull * 1024ull * 1024ull;
    cfg.ioLimitBytes = 1024ull * 1024ull;
    cfg.frameLimit = 1024u;
    cfg.taskQuantumSteps = 1000u;
    cfg.fsBackend = OrenAVMVirtualBackendVirtual;
    cfg.netBackend = OrenAVMVirtualBackendVirtual;
    cfg.procBackend = OrenAVMVirtualBackendVirtual;
    cfg.verifyStrict = YES;
    return cfg;
}

+ (instancetype)interactiveAppDefaults {
    OrenAVMRuntimeConfig* cfg = [self deterministicDefaults];
    cfg.timeMode = OrenAVMTimeModeInteractiveWallClock;
    return cfg;
}

- (id)copyWithZone:(NSZone*)zone {
    OrenAVMRuntimeConfig* cfg = [[[self class] allocWithZone:zone] init];
    cfg.timeMode = self.timeMode;
    cfg.allowedDomains = self.allowedDomains;
    cfg.gasLimit = self.gasLimit;
    cfg.heapLimitBytes = self.heapLimitBytes;
    cfg.ioLimitBytes = self.ioLimitBytes;
    cfg.frameLimit = self.frameLimit;
    cfg.taskQuantumSteps = self.taskQuantumSteps;
    cfg.fsBackend = self.fsBackend;
    cfg.netBackend = self.netBackend;
    cfg.procBackend = self.procBackend;
    cfg.verifyStrict = self.verifyStrict;
    return cfg;
}

- (AvmEmbedConfig)makeEmbedConfig {
    AvmEmbedConfig out;
    if (self.timeMode == OrenAVMTimeModeInteractiveWallClock) {
        avm_embed_config_interactive_default(&out);
    } else {
        avm_embed_config_default(&out);
    }
    out.verify_strict = self.verifyStrict ? 1 : 0;
    out.allowed_native_domains = self.allowedDomains;
    out.gas_limit = self.gasLimit;
    out.heap_limit_bytes = self.heapLimitBytes;
    out.io_limit_bytes = self.ioLimitBytes;
    out.frame_limit = self.frameLimit;
    out.task_quantum_steps = self.taskQuantumSteps;
    out.fs_backend_kind = (int)self.fsBackend;
    out.net_backend_kind = (int)self.netBackend;
    out.proc_backend_kind = (int)self.procBackend;
    return out;
}

@end

#if TARGET_OS_IPHONE

@implementation OrenAVMGraphicsView

- (instancetype)initWithRuntime:(OrenAVMRuntime*)runtime {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _runtime = runtime;
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    return self;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    self = [super initWithCoder:coder];
    if (!self) return nil;
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    return self;
}

- (BOOL)reloadFrameWithError:(NSError**)error {
    if (!self.runtime) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"graphics view has no AVM runtime");
    }
    NSData* frame = [self.runtime getGraphicsFrameDataWithError:error];
    if (!frame) return NO;
    self.frameData = frame;
    [self setNeedsDisplay];
    return YES;
}

- (BOOL)sendPointerEventWithKind:(uint8_t)kind point:(CGPoint)point pointerId:(uint32_t)pointerId error:(NSError**)error {
    if (!self.runtime) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"graphics view has no AVM runtime");
    }
    return [self.runtime putGraphicsPointerEventWithKind:kind
                                                       x:(int32_t)llround((double)point.x)
                                                       y:(int32_t)llround((double)point.y)
                                               pointerId:pointerId
                                                   error:error];
}

- (BOOL)sendResizeEventWithScaleMilli:(uint32_t)scaleMilli error:(NSError**)error {
    if (!self.runtime) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"graphics view has no AVM runtime");
    }
    CGSize size = self.bounds.size;
    return [self.runtime putGraphicsResizeEventWithWidth:(uint32_t)llround((double)size.width)
                                                  height:(uint32_t)llround((double)size.height)
                                              scaleMilli:scaleMilli
                                                   error:error];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    NSData* frame = self.frameData;
    if (frame.length < 24) return;
    const uint8_t* data = (const uint8_t*)frame.bytes;
    if (memcmp(data, "OGF0", 4) != 0) return;
    uint8_t version = data[4];
    uint16_t headerLen = version == 0 ? 24 : OrenAVMGfxReadU16LE(data + 6);
    if (headerLen < 24 || headerLen > frame.length) return;
    uint32_t width = OrenAVMGfxReadU32LE(data + 8);
    uint32_t height = OrenAVMGfxReadU32LE(data + 12);
    uint32_t opCount = OrenAVMGfxReadU32LE(data + 20);
    if (width == 0 || height == 0) return;

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    size_t off = headerLen;
    size_t len = frame.length;
    for (uint32_t i = 0; i < opCount && off + 4 <= len; i++) {
        uint8_t opcode = data[off];
        uint16_t payloadLen = OrenAVMGfxReadU16LE(data + off + 2);
        off += 4;
        if (off + (size_t)payloadLen > len) return;
        const uint8_t* payload = data + off;

        if (opcode == 1 && payloadLen == 20) {
            uint32_t x = OrenAVMGfxReadU32LE(payload);
            uint32_t y = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t w = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t h = OrenAVMGfxReadU32LE(payload + 12);
            UIColor* color = OrenAVMGfxColor(payload + 16);
            CGContextSetFillColorWithColor(ctx, color.CGColor);
            CGContextFillRect(ctx, CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h));
        } else if (opcode == 3 && payloadLen == 24) {
            uint32_t x1 = OrenAVMGfxReadU32LE(payload);
            uint32_t y1 = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t x2 = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t y2 = OrenAVMGfxReadU32LE(payload + 12);
            uint32_t width = OrenAVMGfxReadU32LE(payload + 16);
            UIColor* color = OrenAVMGfxColor(payload + 20);
            CGContextSetStrokeColorWithColor(ctx, color.CGColor);
            CGContextSetLineWidth(ctx, (CGFloat)(width == 0 ? 1 : width));
            CGContextMoveToPoint(ctx, (CGFloat)x1, (CGFloat)y1);
            CGContextAddLineToPoint(ctx, (CGFloat)x2, (CGFloat)y2);
            CGContextStrokePath(ctx);
        } else if (opcode == 4 && payloadLen == 20) {
            uint32_t cx = OrenAVMGfxReadU32LE(payload);
            uint32_t cy = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t radius = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t flags = OrenAVMGfxReadU32LE(payload + 12);
            UIColor* color = OrenAVMGfxColor(payload + 16);
            int32_t ox = (int32_t)cx - (int32_t)radius;
            int32_t oy = (int32_t)cy - (int32_t)radius;
            CGRect oval = CGRectMake((CGFloat)ox,
                                     (CGFloat)oy,
                                     (CGFloat)(radius * 2u),
                                     (CGFloat)(radius * 2u));
            if ((flags & 1u) != 0) {
                CGContextSetFillColorWithColor(ctx, color.CGColor);
                CGContextFillEllipseInRect(ctx, oval);
            } else {
                CGContextSetStrokeColorWithColor(ctx, color.CGColor);
                CGContextStrokeEllipseInRect(ctx, oval);
            }
        } else if (opcode == 2 && payloadLen >= 16) {
            uint32_t x = OrenAVMGfxReadU32LE(payload);
            uint32_t y = OrenAVMGfxReadU32LE(payload + 4);
            UIColor* color = OrenAVMGfxColor(payload + 8);
            uint32_t textLen = OrenAVMGfxReadU32LE(payload + 12);
            if (textLen <= (uint32_t)payloadLen - 16u) {
                NSString* text = [[NSString alloc] initWithBytes:payload + 16
                                                          length:(NSUInteger)textLen
                                                        encoding:NSUTF8StringEncoding];
                if (text) {
                    NSDictionary<NSAttributedStringKey, id>* attrs = @{
                        NSForegroundColorAttributeName: color,
                        NSFontAttributeName: [UIFont systemFontOfSize:14.0]
                    };
                    [text drawAtPoint:CGPointMake((CGFloat)x, (CGFloat)y) withAttributes:attrs];
                }
            }
        }

        off += payloadLen;
    }
}

- (void)orenSendTouches:(NSSet<UITouch*>*)touches kind:(uint8_t)kind {
    UITouch* touch = touches.anyObject;
    if (!touch) return;
    CGPoint p = [touch locationInView:self];
    NSError* error = nil;
    (void)[self sendPointerEventWithKind:kind
                                   point:p
                               pointerId:(uint32_t)touch.hash
                                   error:&error];
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    [self orenSendTouches:touches kind:1];
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    [self orenSendTouches:touches kind:2];
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    [self orenSendTouches:touches kind:3];
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    [self orenSendTouches:touches kind:4];
}

@end

#endif

@implementation OrenAVMRunResult

- (instancetype)initWithResult:(const AvmEmbedResult*)result stdoutData:(NSData*)stdoutData {
    self = [super init];
    if (!self) return nil;
    _status = result ? result->status : AVM_EMBED_ERR_VM;
    _avmErrorCode = result ? result->avm_error_code : 0;
    _exitCode = result ? result->exit_code : 0;
    _gasExecuted = result ? result->gas_executed : 0;
    _heapUsedBytes = result ? result->heap_used_bytes : 0;
    _ioUsedBytes = result ? result->io_used_bytes : 0;
    _message = result && result->message[0] ? [[NSString alloc] initWithUTF8String:result->message] : @"";
    _stdoutData = [stdoutData copy] ?: [NSData data];
    return self;
}

@end

@interface OrenAVMRuntime ()
@property(nonatomic, readonly) AvmEmbedHandle* handle;
@end

@implementation OrenAVMRuntime {
    AvmEmbedHandle* _handle;
    uint64_t _ioLimitBytes;
}

- (instancetype)initWithConfig:(OrenAVMRuntimeConfig*)config {
    self = [super init];
    if (!self) return nil;
    OrenAVMRuntimeConfig* effective = config ?: [OrenAVMRuntimeConfig deterministicDefaults];
    _ioLimitBytes = effective.ioLimitBytes;
    AvmEmbedConfig embedConfig = [effective makeEmbedConfig];
    AvmEmbedResult result;
    _handle = avm_embed_open(&embedConfig, &result);
    if (!_handle || result.status != AVM_EMBED_OK) return nil;
    avm_embed_set_output_capture(_handle, 1, &result);
    return self;
}

- (void)dealloc {
    if (_handle) avm_embed_close(_handle);
}

- (AvmEmbedHandle*)handle {
    return _handle;
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

- (BOOL)putVirtualNetResponseForURL:(NSString*)url data:(NSData*)data error:(NSError**)error {
    AvmEmbedResult result;
    int rc = avm_embed_vnet_put(_handle, url.UTF8String, data.bytes, data.length, &result);
    if (rc != AVM_EMBED_OK) return OrenAVMKitAssignError(error, @"failed to write VirtualNET fixture", &result);
    return YES;
}

- (BOOL)fetchURLIntoVirtualNet:(NSURL*)url
                  allowedHosts:(NSSet<NSString*>*)allowedHosts
                timeoutSeconds:(NSTimeInterval)timeoutSeconds
                          error:(NSError**)error {
    NSString* scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"network prefetch requires an http or https URL");
    }
    NSString* host = url.host;
    if (host.length == 0) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"network prefetch URL must include a host");
    }
    if (allowedHosts.count > 0 && ![allowedHosts containsObject:host]) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_VM,
                                        @"network prefetch host is not allowlisted");
    }

    NSTimeInterval effectiveTimeout = timeoutSeconds > 0.0 ? timeoutSeconds : 15.0;
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:effectiveTimeout];
    request.HTTPMethod = @"GET";

    NSURLSessionConfiguration* sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    sessionConfig.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    sessionConfig.timeoutIntervalForRequest = effectiveTimeout;
    sessionConfig.timeoutIntervalForResource = effectiveTimeout;
    NSURLSession* session = [NSURLSession sessionWithConfiguration:sessionConfig];

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
        [session finishTasksAndInvalidate];
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_VM,
                                        @"network prefetch timed out");
    }
    [session finishTasksAndInvalidate];

    if (requestError) {
        if (error) *error = requestError;
        return NO;
    }
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger statusCode = ((NSHTTPURLResponse*)response).statusCode;
        if (statusCode < 200 || statusCode >= 300) {
            NSString* message = [NSString stringWithFormat:@"network prefetch returned HTTP %ld", (long)statusCode];
            return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_VM, message);
        }
    }
    if (_ioLimitBytes > 0 && responseData.length > _ioLimitBytes) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_VM,
                                        @"network prefetch response exceeds runtime I/O budget");
    }
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
    AvmEmbedResult result;
    int rc = avm_embed_run_obc_bytes(_handle, obcData.bytes, obcData.length, &result);
    if (rc != AVM_EMBED_OK) {
        OrenAVMKitAssignError(error, @"failed to run OBC", &result);
        return nil;
    }
    uint8_t* stdoutBytes = NULL;
    size_t stdoutLen = 0;
    AvmEmbedResult outputResult;
    NSData* stdoutData = [NSData data];
    if (avm_embed_output_get(_handle, &stdoutBytes, &stdoutLen, &outputResult) == AVM_EMBED_OK) {
        stdoutData = [NSData dataWithBytes:stdoutBytes length:stdoutLen];
        avm_embed_free_bytes(stdoutBytes);
    }
    return [[OrenAVMRunResult alloc] initWithResult:&result stdoutData:stdoutData];
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

- (BOOL)putGraphicsPointerEventWithKind:(uint8_t)kind x:(int32_t)x y:(int32_t)y pointerId:(uint32_t)pointerId error:(NSError**)error {
    uint8_t payload[12];
    uint32_t ux = (uint32_t)x;
    uint32_t uy = (uint32_t)y;
    OrenAVMKitPutU32LE(payload, ux);
    OrenAVMKitPutU32LE(payload + 4, uy);
    OrenAVMKitPutU32LE(payload + 8, pointerId);
    NSData* data = OrenAVMKitMakeGFXEvent(kind, payload, sizeof(payload));
    return [self putGraphicsInputEventData:data error:error];
}

- (BOOL)putGraphicsResizeEventWithWidth:(uint32_t)width height:(uint32_t)height scaleMilli:(uint32_t)scaleMilli error:(NSError**)error {
    uint8_t payload[12];
    OrenAVMKitPutU32LE(payload, width);
    OrenAVMKitPutU32LE(payload + 4, height);
    OrenAVMKitPutU32LE(payload + 8, scaleMilli);
    NSData* data = OrenAVMKitMakeGFXEvent(16, payload, sizeof(payload));
    return [self putGraphicsInputEventData:data error:error];
}

- (BOOL)putGraphicsKeyEventWithKind:(uint8_t)kind keyCode:(uint32_t)keyCode modifiers:(uint32_t)modifiers error:(NSError**)error {
    uint8_t payload[8];
    OrenAVMKitPutU32LE(payload, keyCode);
    OrenAVMKitPutU32LE(payload + 4, modifiers);
    NSData* data = OrenAVMKitMakeGFXEvent(kind, payload, sizeof(payload));
    return [self putGraphicsInputEventData:data error:error];
}

- (BOOL)putGraphicsTextInputString:(NSString*)text error:(NSError**)error {
    NSData* utf8 = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!utf8) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"GFX text input must be valid UTF-8");
    }
    if (utf8.length > UINT16_MAX - 4u) {
        return OrenAVMKitAssignSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"GFX text input event is too large");
    }
    NSMutableData* payload = [NSMutableData dataWithLength:4u + utf8.length];
    uint8_t* out = (uint8_t*)payload.mutableBytes;
    OrenAVMKitPutU32LE(out, (uint32_t)utf8.length);
    if (utf8.length > 0) memcpy(out + 4, utf8.bytes, utf8.length);
    NSData* data = OrenAVMKitMakeGFXEvent(48, payload.bytes, (uint16_t)payload.length);
    return [self putGraphicsInputEventData:data error:error];
}

@end
