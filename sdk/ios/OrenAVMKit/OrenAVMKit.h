#ifndef OREN_AVM_KIT_H
#define OREN_AVM_KIT_H

#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

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
    OrenAVMDomainExit = UINT64_C(1) << 6,
    OrenAVMDomainGFX = UINT64_C(1) << 9,
    OrenAVMDomainPermission = UINT64_C(1) << 10
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
@property(nonatomic) BOOL liveNetworkEnabled;
@property(nonatomic, nullable, copy) NSSet<NSString*>* liveNetworkAllowedHosts;
@property(nonatomic) NSTimeInterval liveNetworkTimeoutSeconds;
@property(nonatomic) uint32_t liveNetworkMaxSessions;
@property(nonatomic) uint64_t liveNetworkSessionByteLimitBytes;
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
- (BOOL)mountFileURL:(NSURL*)fileURL atVFSPath:(NSString*)vfsPath error:(NSError* _Nullable* _Nullable)error;
- (BOOL)mountDirectoryURL:(NSURL*)directoryURL atVFSRoot:(NSString*)vfsRoot error:(NSError* _Nullable* _Nullable)error;
- (BOOL)mountHostDirectoryURL:(NSURL*)directoryURL
                    atVFSRoot:(NSString*)vfsRoot
                     readable:(BOOL)readable
                     writable:(BOOL)writable
                        error:(NSError* _Nullable* _Nullable)error;
- (BOOL)exportVFSFileAtPath:(NSString*)vfsPath
                  toFileURL:(NSURL*)fileURL
createIntermediateDirectories:(BOOL)createIntermediateDirectories
                      error:(NSError* _Nullable* _Nullable)error;
- (BOOL)putVirtualNetResponseForURL:(NSString*)url data:(NSData*)data error:(NSError* _Nullable* _Nullable)error;
- (BOOL)enableLiveNetworkWithAllowedHosts:(nullable NSSet<NSString*>*)allowedHosts
                           timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                    error:(NSError* _Nullable* _Nullable)error;
- (BOOL)configureLiveNetworkSessionLimitsWithMaxSessions:(uint32_t)maxSessions
                                          byteLimitBytes:(uint64_t)byteLimitBytes
                                                   error:(NSError* _Nullable* _Nullable)error;
- (BOOL)disableLiveNetworkWithError:(NSError* _Nullable* _Nullable)error;
- (BOOL)fetchURLIntoVirtualNet:(NSURL*)url
                  allowedHosts:(nullable NSSet<NSString*>*)allowedHosts
                timeoutSeconds:(NSTimeInterval)timeoutSeconds
                          error:(NSError* _Nullable* _Nullable)error;
- (BOOL)putVirtualProcExitForCommand:(NSString*)command exitCode:(int)exitCode error:(NSError* _Nullable* _Nullable)error;
- (BOOL)setVirtualProcDefaultExitCode:(int)exitCode error:(NSError* _Nullable* _Nullable)error;
- (nullable OrenAVMRunResult*)runOBCData:(NSData*)obcData error:(NSError* _Nullable* _Nullable)error;
- (BOOL)requestCancelWithError:(NSError* _Nullable* _Nullable)error;
- (BOOL)clearCancelWithError:(NSError* _Nullable* _Nullable)error;
- (nullable NSData*)getGraphicsFrameDataWithError:(NSError* _Nullable* _Nullable)error;
- (BOOL)clearGraphicsFrameWithError:(NSError* _Nullable* _Nullable)error;
- (nullable NSData*)getPermissionRequestDataWithError:(NSError* _Nullable* _Nullable)error;
- (nullable NSDictionary<NSString*, id>*)getPermissionRequestWithError:(NSError* _Nullable* _Nullable)error;
- (BOOL)clearPermissionRequestWithError:(NSError* _Nullable* _Nullable)error;
- (BOOL)putGraphicsInputEventData:(NSData*)data error:(NSError* _Nullable* _Nullable)error;
- (BOOL)putGraphicsPointerEventWithKind:(uint8_t)kind x:(int32_t)x y:(int32_t)y pointerId:(uint32_t)pointerId error:(NSError* _Nullable* _Nullable)error;
- (BOOL)putGraphicsResizeEventWithWidth:(uint32_t)width height:(uint32_t)height scaleMilli:(uint32_t)scaleMilli error:(NSError* _Nullable* _Nullable)error;
- (BOOL)putGraphicsKeyEventWithKind:(uint8_t)kind keyCode:(uint32_t)keyCode modifiers:(uint32_t)modifiers error:(NSError* _Nullable* _Nullable)error;
- (BOOL)putGraphicsTextInputString:(NSString*)text error:(NSError* _Nullable* _Nullable)error;

@end

@interface OrenAVMPackage : NSObject

@property(nonatomic, readonly, copy) NSURL* directoryURL;
@property(nonatomic, readonly, copy) NSDictionary<NSString*, id>* manifest;
@property(nonatomic, readonly, copy) NSData* obcData;
@property(nonatomic, readonly, copy) NSString* packageID;
@property(nonatomic, readonly, copy) NSString* name;
@property(nonatomic, readonly, copy) NSString* publisher;
@property(nonatomic, readonly, copy) NSString* version;
@property(nonatomic, readonly, copy) NSArray<NSString*>* capabilities;

@end

@interface OrenAVMPackageStore : NSObject

- (nullable OrenAVMPackage*)loadPackageAtDirectoryURL:(NSURL*)directoryURL
                                               error:(NSError* _Nullable* _Nullable)error;
- (nullable OrenAVMPackage*)downloadPackageFromIndexURL:(NSURL*)indexURL
                                              packageID:(NSString*)packageID
                                                version:(nullable NSString*)version
                                destinationDirectoryURL:(NSURL*)destinationDirectoryURL
                                           allowedHosts:(nullable NSSet<NSString*>*)allowedHosts
                                         timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                                  error:(NSError* _Nullable* _Nullable)error;
- (nullable OrenAVMPackage*)downloadPackageFromIndexURL:(NSURL*)indexURL
                                              packageID:(NSString*)packageID
                                                version:(nullable NSString*)version
                                destinationDirectoryURL:(NSURL*)destinationDirectoryURL
                                           allowedHosts:(nullable NSSet<NSString*>*)allowedHosts
                                         timeoutSeconds:(NSTimeInterval)timeoutSeconds
                             trustedPublisherPublicKeys:(nullable NSDictionary<NSString*, NSData*>*)trustedPublisherPublicKeys
                                                  error:(NSError* _Nullable* _Nullable)error;
- (nullable OrenAVMPackage*)downloadPackageFromSignedIndexURL:(NSURL*)indexURL
                                                    packageID:(NSString*)packageID
                                                      version:(nullable NSString*)version
                                      destinationDirectoryURL:(NSURL*)destinationDirectoryURL
                                                 allowedHosts:(nullable NSSet<NSString*>*)allowedHosts
                                               timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                        trustedIndexPublicKey:(nullable NSData*)trustedIndexPublicKey
                                   trustedPublisherPublicKeys:(nullable NSDictionary<NSString*, NSData*>*)trustedPublisherPublicKeys
                                                        error:(NSError* _Nullable* _Nullable)error;
- (nullable OrenAVMRuntimeConfig*)runtimeConfigForPackage:(OrenAVMPackage*)package
                                                    error:(NSError* _Nullable* _Nullable)error;
- (BOOL)mountPackageAssetsForPackage:(OrenAVMPackage*)package
                             runtime:(OrenAVMRuntime*)runtime
                               error:(NSError* _Nullable* _Nullable)error;
- (nullable OrenAVMRunResult*)runPackage:(OrenAVMPackage*)package
                                 runtime:(OrenAVMRuntime*)runtime
                                   error:(NSError* _Nullable* _Nullable)error;
- (NSArray<NSString*>*)listInstalledPackageIDsInDirectoryURL:(NSURL*)installRootURL
                                                       error:(NSError* _Nullable* _Nullable)error;
- (nullable OrenAVMPackage*)loadInstalledPackageInDirectoryURL:(NSURL*)installRootURL
                                                     packageID:(NSString*)packageID
                                                       version:(NSString*)version
                                                         error:(NSError* _Nullable* _Nullable)error;
- (BOOL)removeInstalledPackageInDirectoryURL:(NSURL*)installRootURL
                                   packageID:(NSString*)packageID
                                     version:(NSString*)version
                                       error:(NSError* _Nullable* _Nullable)error;

+ (NSString*)sha256HexForData:(NSData*)data;

@end

#if TARGET_OS_IPHONE

@interface OrenAVMGraphicsView : UIView

@property(nonatomic, strong, nullable) OrenAVMRuntime* runtime;
@property(nonatomic, copy, nullable) NSData* frameData;

- (instancetype)initWithRuntime:(OrenAVMRuntime*)runtime NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(CGRect)frame NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder*)coder NS_DESIGNATED_INITIALIZER;
- (BOOL)reloadFrameWithError:(NSError* _Nullable* _Nullable)error;
- (BOOL)sendPointerEventWithKind:(uint8_t)kind
                           point:(CGPoint)point
                       pointerId:(uint32_t)pointerId
                           error:(NSError* _Nullable* _Nullable)error;
- (BOOL)sendResizeEventWithScaleMilli:(uint32_t)scaleMilli error:(NSError* _Nullable* _Nullable)error;

@end

#endif

FOUNDATION_EXPORT NSString* const OrenAVMKitErrorDomain;

NS_ASSUME_NONNULL_END

#endif
