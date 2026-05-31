#import "OrenAVMKit.h"

#import <dispatch/dispatch.h>

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

@implementation OrenAVMRuntimeConfig

+ (instancetype)deterministicDefaults {
    OrenAVMRuntimeConfig* cfg = [[self alloc] init];
    cfg.timeMode = OrenAVMTimeModeDeterministic;
    cfg.allowedDomains = OrenAVMDomainCore | OrenAVMDomainFS | OrenAVMDomainTime |
        OrenAVMDomainNet | OrenAVMDomainProc | OrenAVMDomainExit;
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

@end
