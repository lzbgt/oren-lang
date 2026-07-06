#import "OrenAVMKit.h"

#include <stdlib.h>

static NSString* const OrenAVMCompilerKitErrorDomain = @"org.oren.avmkit";
static const uint64_t OrenAVMCompilerKitDefaultGasLimit = 500000000ull;
static const uint64_t OrenAVMCompilerKitDefaultHeapLimitBytes = 384ull * 1024ull * 1024ull;
static const uint64_t OrenAVMCompilerKitDefaultIOLimitBytes = 128ull * 1024ull * 1024ull;
static const uint32_t OrenAVMCompilerKitDefaultFrameLimit = 65536u;

static BOOL OrenAVMCompilerKitAssignError(NSError** error, NSInteger code, NSString* message) {
    if (error) {
        *error = [NSError errorWithDomain:OrenAVMCompilerKitErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: message ?: @"OrenAVMCompilerKit error"}];
    }
    return NO;
}

static BOOL OrenAVMCompilerKitSafeVFSPath(NSString* path) {
    if (path.length == 0 || [path hasPrefix:@"/"]) return NO;
    NSArray<NSString*>* parts = [path componentsSeparatedByString:@"/"];
    for (NSString* part in parts) {
        if (part.length == 0 || [part isEqualToString:@"."] || [part isEqualToString:@".."]) return NO;
    }
    return YES;
}

@interface OrenAVMCompileResult ()
- (instancetype)initWithOBCData:(NSData*)obcData
                diagnosticsData:(NSData*)diagnosticsData
              compilerRunResult:(OrenAVMRunResult*)compilerRunResult;
@end

@implementation OrenAVMCompileResult

- (instancetype)initWithOBCData:(NSData*)obcData
                diagnosticsData:(NSData*)diagnosticsData
              compilerRunResult:(OrenAVMRunResult*)compilerRunResult {
    self = [super init];
    if (self) {
        _obcData = [obcData copy];
        _diagnosticsData = [diagnosticsData copy];
        _compilerRunResult = compilerRunResult;
    }
    return self;
}

@end

@implementation OrenAVMCompilerKit {
    NSData* _compilerOBCData;
    NSData* _stdlibOBCData;
}

- (instancetype)initWithCompilerOBCData:(NSData*)compilerOBCData
                         stdlibOBCData:(NSData*)stdlibOBCData {
    self = [super init];
    if (self) {
        _compilerOBCData = [compilerOBCData copy];
        _stdlibOBCData = [stdlibOBCData copy];
        _compilerGasLimit = OrenAVMCompilerKitDefaultGasLimit;
        _compilerHeapLimitBytes = OrenAVMCompilerKitDefaultHeapLimitBytes;
        _compilerIOLimitBytes = OrenAVMCompilerKitDefaultIOLimitBytes;
        _compilerFrameLimit = OrenAVMCompilerKitDefaultFrameLimit;
    }
    return self;
}

+ (instancetype)compilerKitWithCompilerOBCURL:(NSURL*)compilerOBCURL
                                 stdlibOBCURL:(NSURL*)stdlibOBCURL
                                       error:(NSError**)error {
    if (!compilerOBCURL.isFileURL || !stdlibOBCURL.isFileURL) {
        OrenAVMCompilerKitAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"CompilerKit requires file URLs");
        return nil;
    }
    NSData* compiler = [NSData dataWithContentsOfURL:compilerOBCURL options:0 error:error];
    if (!compiler) return nil;
    NSData* stdlib = [NSData dataWithContentsOfURL:stdlibOBCURL options:0 error:error];
    if (!stdlib) return nil;
    if (compiler.length == 0 || stdlib.length == 0) {
        OrenAVMCompilerKitAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"CompilerKit OBC resources must be non-empty");
        return nil;
    }
    return [[self alloc] initWithCompilerOBCData:compiler stdlibOBCData:stdlib];
}

- (OrenAVMCompileResult*)compileSource:(NSString*)source
                              platform:(NSString*)platform
                                 error:(NSError**)error {
    if (!source) {
        OrenAVMCompilerKitAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"source must be UTF-8 encodable");
        return nil;
    }
    NSUInteger byteLen = [source lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    if (byteLen == 0 && source.length != 0) {
        OrenAVMCompilerKitAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"source must be UTF-8 encodable");
        return nil;
    }
    enum { inlineSourceCap = 8192 };
    uint8_t inlineSource[inlineSourceCap];
    uint8_t* sourceBytes = byteLen <= inlineSourceCap ? inlineSource : (uint8_t*)malloc((size_t)byteLen);
    if (!sourceBytes && byteLen != 0) {
        OrenAVMCompilerKitAssignError(error, AVM_EMBED_ERR_VM, @"failed to allocate CompilerKit source bytes");
        return nil;
    }
    NSUInteger usedLen = 0;
    NSRange remaining = NSMakeRange(0, 0);
    BOOL ok = [source getBytes:sourceBytes
                     maxLength:byteLen
                    usedLength:&usedLen
                      encoding:NSUTF8StringEncoding
                       options:0
                         range:NSMakeRange(0, source.length)
                remainingRange:&remaining];
    if (!ok || usedLen != byteLen || remaining.length != 0) {
        if (sourceBytes != inlineSource) free(sourceBytes);
        OrenAVMCompilerKitAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"source must be UTF-8 encodable");
        return nil;
    }
    NSData* data = [NSData dataWithBytesNoCopy:sourceBytes length:byteLen freeWhenDone:NO];
    OrenAVMCompileResult* result = data ?
        [self compileSourceData:data sourcePath:@"src.oren" outputPath:@"out.obc" platform:platform error:error] : nil;
    if (sourceBytes != inlineSource) free(sourceBytes);
    if (!data && !result) {
        OrenAVMCompilerKitAssignError(error, AVM_EMBED_ERR_VM, @"failed to wrap CompilerKit source bytes");
    }
    return result;
}

- (OrenAVMCompileResult*)compileSourceData:(NSData*)sourceData
                                sourcePath:(NSString*)sourcePath
                                outputPath:(NSString*)outputPath
                                  platform:(NSString*)platform
                                     error:(NSError**)error {
    if (_compilerOBCData.length == 0 || _stdlibOBCData.length == 0 || sourceData.length == 0) {
        OrenAVMCompilerKitAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"CompilerKit requires compiler, stdlib, and source data");
        return nil;
    }
    if (!OrenAVMCompilerKitSafeVFSPath(sourcePath) || !OrenAVMCompilerKitSafeVFSPath(outputPath)) {
        OrenAVMCompilerKitAssignError(error, AVM_EMBED_ERR_INVALID_ARG, @"CompilerKit source/output paths must be relative and rootless");
        return nil;
    }
    NSString* targetPlatform = platform.length > 0 ? platform : @"arm64-macos";

    OrenAVMRuntimeConfig* cfg = [OrenAVMRuntimeConfig deterministicDefaults];
    cfg.allowedDomains = OrenAVMDomainCore | OrenAVMDomainFS | OrenAVMDomainTime | OrenAVMDomainExit;
    cfg.fsBackend = OrenAVMVirtualBackendVirtual;
    cfg.gasLimit = self.compilerGasLimit > 0 ? self.compilerGasLimit : OrenAVMCompilerKitDefaultGasLimit;
    cfg.heapLimitBytes = self.compilerHeapLimitBytes > 0 ? self.compilerHeapLimitBytes : OrenAVMCompilerKitDefaultHeapLimitBytes;
    cfg.ioLimitBytes = self.compilerIOLimitBytes > 0 ? self.compilerIOLimitBytes : OrenAVMCompilerKitDefaultIOLimitBytes;
    cfg.frameLimit = self.compilerFrameLimit > 0 ? self.compilerFrameLimit : OrenAVMCompilerKitDefaultFrameLimit;

    OrenAVMRuntime* runtime = [[OrenAVMRuntime alloc] initWithConfig:cfg];
    if (!runtime) {
        OrenAVMCompilerKitAssignError(error, AVM_EMBED_ERR_VM, @"failed to create CompilerKit runtime");
        return nil;
    }
    if (![runtime putVFSFileAtPath:sourcePath data:sourceData error:error]) return nil;
    if (![runtime putVFSFileAtPath:@"stdlib.obc" data:_stdlibOBCData error:error]) return nil;
    NSArray<NSString*>* argv = @[
        @"oren",
        @"build",
        sourcePath,
        @"--backend", @"bytecode",
        @"--platform", targetPlatform,
        @"--no-cache",
        @"--deterministic",
        @"--codesign", @"",
        @"--stdlib-mode", @"obc",
        @"--stdlib-obc", @"stdlib.obc",
        @"-o", outputPath
    ];
    if (![runtime setArgv:argv error:error]) return nil;

    OrenAVMRunResult* run = [runtime runOBCData:_compilerOBCData error:error];
    if (!run) return nil;
    if (run.exitCode != 0) {
        NSString* diagnostics = [[NSString alloc] initWithData:run.stdoutData encoding:NSUTF8StringEncoding] ?: @"";
        NSString* message = [NSString stringWithFormat:@"CompilerKit compile failed with exit code %ld: %@",
                             (long)run.exitCode,
                             diagnostics];
        OrenAVMCompilerKitAssignError(error, run.exitCode, message);
        return nil;
    }
    NSData* out = [runtime getVFSFileAtPath:outputPath error:error];
    if (!out || out.length == 0) {
        OrenAVMCompilerKitAssignError(error, AVM_EMBED_ERR_VM, @"CompilerKit did not produce output OBC");
        return nil;
    }
    return [[OrenAVMCompileResult alloc] initWithOBCData:out
                                        diagnosticsData:run.stdoutData
                                      compilerRunResult:run];
}

@end
