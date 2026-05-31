#ifndef OREN_AVM_KIT_H
#define OREN_AVM_KIT_H

#import <Foundation/Foundation.h>

#include "avm_embed.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OrenAVMTimeMode) {
    OrenAVMTimeModeDeterministic = 0,
    OrenAVMTimeModeInteractiveWallClock = 1
};

typedef NS_OPTIONS(uint64_t, OrenAVMDomain) {
    OrenAVMDomainCore = UINT64_C(1) << 0,
    OrenAVMDomainFS = UINT64_C(1) << 1,
    OrenAVMDomainTime = UINT64_C(1) << 2,
    OrenAVMDomainNet = UINT64_C(1) << 4,
    OrenAVMDomainProc = UINT64_C(1) << 5,
    OrenAVMDomainExit = UINT64_C(1) << 6
};

typedef NS_ENUM(NSInteger, OrenAVMVirtualBackend) {
    OrenAVMVirtualBackendHost = 0,
    OrenAVMVirtualBackendVirtual = 1
};

@interface OrenAVMRuntimeConfig : NSObject <NSCopying>

@property(nonatomic) OrenAVMTimeMode timeMode;
@property(nonatomic) uint64_t allowedDomains;
@property(nonatomic) uint64_t gasLimit;
@property(nonatomic) uint64_t heapLimitBytes;
@property(nonatomic) uint64_t ioLimitBytes;
@property(nonatomic) uint32_t frameLimit;
@property(nonatomic) uint32_t taskQuantumSteps;
@property(nonatomic) OrenAVMVirtualBackend fsBackend;
@property(nonatomic) OrenAVMVirtualBackend netBackend;
@property(nonatomic) OrenAVMVirtualBackend procBackend;
@property(nonatomic) BOOL verifyStrict;

+ (instancetype)deterministicDefaults;
+ (instancetype)interactiveAppDefaults;
- (AvmEmbedConfig)makeEmbedConfig;

@end

@interface OrenAVMRunResult : NSObject

@property(nonatomic, readonly) NSInteger status;
@property(nonatomic, readonly) NSInteger avmErrorCode;
@property(nonatomic, readonly) NSInteger exitCode;
@property(nonatomic, readonly) uint64_t gasExecuted;
@property(nonatomic, readonly) uint64_t heapUsedBytes;
@property(nonatomic, readonly) uint64_t ioUsedBytes;
@property(nonatomic, readonly, copy) NSString* message;
@property(nonatomic, readonly, copy) NSData* stdoutData;

@end

@interface OrenAVMRuntime : NSObject

- (instancetype)initWithConfig:(OrenAVMRuntimeConfig*)config NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)setArgv:(NSArray<NSString*>*)argv error:(NSError* _Nullable* _Nullable)error;
- (BOOL)putVFSFileAtPath:(NSString*)path data:(NSData*)data error:(NSError* _Nullable* _Nullable)error;
- (nullable NSData*)getVFSFileAtPath:(NSString*)path error:(NSError* _Nullable* _Nullable)error;
- (BOOL)putVirtualNetResponseForURL:(NSString*)url data:(NSData*)data error:(NSError* _Nullable* _Nullable)error;
- (BOOL)putVirtualProcExitForCommand:(NSString*)command exitCode:(int)exitCode error:(NSError* _Nullable* _Nullable)error;
- (BOOL)setVirtualProcDefaultExitCode:(int)exitCode error:(NSError* _Nullable* _Nullable)error;
- (nullable OrenAVMRunResult*)runOBCData:(NSData*)obcData error:(NSError* _Nullable* _Nullable)error;

@end

FOUNDATION_EXPORT NSString* const OrenAVMKitErrorDomain;

NS_ASSUME_NONNULL_END

#endif
