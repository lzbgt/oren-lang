#import "OrenAVMKit.h"

@interface OrenAVMRunResult ()
- (instancetype)initWithResult:(const AvmEmbedResult*)result stdoutData:(NSData*)stdoutData;
@end

@implementation OrenAVMRuntimeConfig

+ (instancetype)deterministicDefaults {
    OrenAVMRuntimeConfig* cfg = [[self alloc] init];
    cfg.timeMode = OrenAVMTimeModeDeterministic;
    cfg.allowedDomains = OrenAVMDomainCore | OrenAVMDomainFS | OrenAVMDomainTime |
        OrenAVMDomainNet | OrenAVMDomainProc | OrenAVMDomainExit | OrenAVMDomainGFX |
        OrenAVMDomainPermission | OrenAVMDomainEvent;
    cfg.gasLimit = 5000000ull;
    cfg.heapLimitBytes = 32ull * 1024ull * 1024ull;
    cfg.ioLimitBytes = 1024ull * 1024ull;
    cfg.frameLimit = 1024u;
    cfg.taskQuantumSteps = 1000u;
    cfg.fsBackend = OrenAVMVirtualBackendVirtual;
    cfg.netBackend = OrenAVMVirtualBackendVirtual;
    cfg.procBackend = OrenAVMVirtualBackendVirtual;
    cfg.liveNetworkEnabled = NO;
    cfg.liveNetworkAllowedHosts = nil;
    cfg.liveNetworkTimeoutSeconds = 15.0;
    cfg.liveNetworkMaxSessions = 64u;
    cfg.liveNetworkSessionByteLimitBytes = 1024ull * 1024ull;
    cfg.verifyStrict = YES;
    return cfg;
}

+ (instancetype)interactiveAppDefaults {
    OrenAVMRuntimeConfig* cfg = [self deterministicDefaults];
    cfg.timeMode = OrenAVMTimeModeInteractiveWallClock;
    cfg.liveNetworkEnabled = YES;
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
    cfg.liveNetworkEnabled = self.liveNetworkEnabled;
    cfg.liveNetworkAllowedHosts = [self.liveNetworkAllowedHosts copy];
    cfg.liveNetworkTimeoutSeconds = self.liveNetworkTimeoutSeconds;
    cfg.liveNetworkMaxSessions = self.liveNetworkMaxSessions;
    cfg.liveNetworkSessionByteLimitBytes = self.liveNetworkSessionByteLimitBytes;
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
