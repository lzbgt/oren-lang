#ifndef OREN_AVM_KIT_H
#define OREN_AVM_KIT_H

#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>
#endif

#include "avm_embed.h"

NS_ASSUME_NONNULL_BEGIN

@class OrenAVMPackage;

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
    OrenAVMDomainPermission = UINT64_C(1) << 10,
    OrenAVMDomainEvent = UINT64_C(1) << 11
};

typedef NS_ENUM(NSInteger, OrenAVMVirtualBackend) {
    OrenAVMVirtualBackendHost = 0,
    OrenAVMVirtualBackendVirtual = 1
};

typedef NS_ENUM(NSInteger, OrenAVMPackageInstallPolicy) {
    OrenAVMPackageInstallPolicyReplace = 0,
    OrenAVMPackageInstallPolicyKeepExisting = 1,
    OrenAVMPackageInstallPolicyFailIfInstalled = 2
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

@interface OrenAVMCompileResult : NSObject

@property(nonatomic, readonly, copy) NSData* obcData;
@property(nonatomic, readonly, copy) NSData* diagnosticsData;
@property(nonatomic, readonly, strong) OrenAVMRunResult* compilerRunResult;

@end

@interface OrenAVMCompilerKit : NSObject

@property(nonatomic) uint64_t compilerGasLimit;
@property(nonatomic) uint64_t compilerHeapLimitBytes;
@property(nonatomic) uint64_t compilerIOLimitBytes;
@property(nonatomic) uint32_t compilerFrameLimit;

- (instancetype)initWithCompilerOBCData:(NSData*)compilerOBCData
                         stdlibOBCData:(NSData*)stdlibOBCData NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

+ (nullable instancetype)compilerKitWithCompilerOBCURL:(NSURL*)compilerOBCURL
                                          stdlibOBCURL:(NSURL*)stdlibOBCURL
                                                error:(NSError* _Nullable* _Nullable)error;

- (nullable OrenAVMCompileResult*)compileSource:(NSString*)source
                                       platform:(nullable NSString*)platform
                                          error:(NSError* _Nullable* _Nullable)error;
- (nullable OrenAVMCompileResult*)compileSourceData:(NSData*)sourceData
                                         sourcePath:(NSString*)sourcePath
                                         outputPath:(NSString*)outputPath
                                           platform:(nullable NSString*)platform
                                              error:(NSError* _Nullable* _Nullable)error;

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
- (BOOL)setGraphicsScreenWithID:(uint32_t)screenID
                           width:(uint32_t)width
                          height:(uint32_t)height
                      scaleMilli:(uint32_t)scaleMilli
                   drawableWidth:(uint32_t)drawableWidth
                  drawableHeight:(uint32_t)drawableHeight
                   targetHzMilli:(uint32_t)targetHzMilli
                           flags:(uint32_t)flags
                           error:(NSError* _Nullable* _Nullable)error;
- (BOOL)putVirtualEventWithKind:(NSString*)kind
                         action:(NSString*)action
                         detail:(NSString*)detail
                          flags:(uint32_t)flags
                          error:(NSError* _Nullable* _Nullable)error;

@end

@interface OrenAVMRuntime (GFXInput)

- (BOOL)putGraphicsPointerEventWithKind:(uint8_t)kind x:(int32_t)x y:(int32_t)y pointerId:(uint32_t)pointerId error:(NSError* _Nullable* _Nullable)error;
- (BOOL)putGraphicsResizeEventWithWidth:(uint32_t)width height:(uint32_t)height scaleMilli:(uint32_t)scaleMilli error:(NSError* _Nullable* _Nullable)error;
- (BOOL)putGraphicsMediaEventWithWidth:(uint32_t)width
                                 height:(uint32_t)height
                             scaleMilli:(uint32_t)scaleMilli
                          drawableWidth:(uint32_t)drawableWidth
                         drawableHeight:(uint32_t)drawableHeight
                          targetHzMilli:(uint32_t)targetHzMilli
                                  flags:(uint32_t)flags
                                  error:(NSError* _Nullable* _Nullable)error;
- (BOOL)putGraphicsFrameTickEventWithSequence:(uint32_t)sequence
                                        nowNs:(uint64_t)nowNs
                                      deltaNs:(uint64_t)deltaNs
                                targetHzMilli:(uint32_t)targetHzMilli
                                        flags:(uint32_t)flags
                                        error:(NSError* _Nullable* _Nullable)error;
- (BOOL)putGraphicsKeyEventWithKind:(uint8_t)kind keyCode:(uint32_t)keyCode modifiers:(uint32_t)modifiers error:(NSError* _Nullable* _Nullable)error;
- (BOOL)putGraphicsTextInputString:(NSString*)text error:(NSError* _Nullable* _Nullable)error;
- (BOOL)putGraphicsGamepadEventWithControllerID:(uint32_t)controllerID
                                        buttons:(uint32_t)buttons
                                        lxMilli:(int32_t)lxMilli
                                        lyMilli:(int32_t)lyMilli
                                        rxMilli:(int32_t)rxMilli
                                        ryMilli:(int32_t)ryMilli
                                          error:(NSError* _Nullable* _Nullable)error;
- (BOOL)putGraphicsMotionEventWithSourceID:(uint32_t)sourceID
                                  sequence:(uint32_t)sequence
                               timestampNs:(uint64_t)timestampNs
                              accelXMilli:(int32_t)accelXMilli
                              accelYMilli:(int32_t)accelYMilli
                              accelZMilli:(int32_t)accelZMilli
                               gyroXMilli:(int32_t)gyroXMilli
                               gyroYMilli:(int32_t)gyroYMilli
                               gyroZMilli:(int32_t)gyroZMilli
                                     error:(NSError* _Nullable* _Nullable)error;
- (BOOL)putGraphicsFocusEventWithKind:(uint8_t)kind
                               focusID:(uint32_t)focusID
                                 flags:(uint32_t)flags
                                 error:(NSError* _Nullable* _Nullable)error;
- (BOOL)putGraphicsCompositionEventWithKind:(uint8_t)kind
                                       text:(NSString*)text
                             selectionStart:(uint32_t)selectionStart
                               selectionEnd:(uint32_t)selectionEnd
                                      error:(NSError* _Nullable* _Nullable)error;

@end

@interface OrenAVMPermissionPrompt : NSObject

@property(nonatomic, readonly, copy) NSString* domain;
@property(nonatomic, readonly, copy) NSString* action;
@property(nonatomic, readonly, copy) NSString* detail;
@property(nonatomic, readonly) uint64_t sequence;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, copy) NSString* message;
@property(nonatomic, readonly, copy) NSString* riskLevel;
@property(nonatomic, readonly, nullable, copy) NSString* networkHost;

+ (nullable instancetype)promptWithPermissionRequest:(NSDictionary<NSString*, id>*)request
                                              error:(NSError* _Nullable* _Nullable)error;
- (NSDictionary<NSString*, id>*)permissionRequest;

@end

@interface OrenAVMPermissionGrantStore : NSObject

@property(nonatomic, readonly, copy) NSURL* storeURL;

- (instancetype)initWithStoreURL:(NSURL*)storeURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)loadWithError:(NSError* _Nullable* _Nullable)error;
- (BOOL)saveWithError:(NSError* _Nullable* _Nullable)error;
- (BOOL)setGranted:(BOOL)granted
            domain:(NSString*)domain
            action:(NSString*)action
            detail:(NSString*)detail
             error:(NSError* _Nullable* _Nullable)error;
- (BOOL)isGrantedForDomain:(NSString*)domain
                    action:(NSString*)action
                    detail:(NSString*)detail;
- (NSSet<NSString*>*)allowedNetworkHosts;
- (BOOL)applyNetworkGrantsToRuntime:(OrenAVMRuntime*)runtime
                      timeoutSeconds:(NSTimeInterval)timeoutSeconds
                               error:(NSError* _Nullable* _Nullable)error;
- (BOOL)recordDecisionForPermissionRequest:(NSDictionary<NSString*, id>*)request
                                   granted:(BOOL)granted
                                   runtime:(nullable OrenAVMRuntime*)runtime
                            timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                      error:(NSError* _Nullable* _Nullable)error;
- (BOOL)recordDecisionForPermissionPrompt:(OrenAVMPermissionPrompt*)prompt
                                  granted:(BOOL)granted
                                  runtime:(nullable OrenAVMRuntime*)runtime
                           timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                     error:(NSError* _Nullable* _Nullable)error;
- (BOOL)isGrantedForPermissionPrompt:(OrenAVMPermissionPrompt*)prompt;
- (BOOL)applyPackagePermissionDefaults:(OrenAVMPackage*)package
                                runtime:(nullable OrenAVMRuntime*)runtime
                         timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                  error:(NSError* _Nullable* _Nullable)error;

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

@interface OrenAVMOBCTrustBundle : NSObject

@property(nonatomic, readonly, copy) NSDictionary<NSString*, NSData*>* storePublicKeys;
@property(nonatomic, readonly, copy) NSDictionary<NSString*, NSData*>* publisherPublicKeys;
@property(nonatomic, readonly, copy) NSString* defaultStoreKeyID;
@property(nonatomic, readonly, copy) NSData* defaultStorePublicKey;

+ (nullable instancetype)loadTrustBundleAtURL:(NSURL*)url
                                        error:(NSError* _Nullable* _Nullable)error;

@end

@interface OrenAVMPackageUpdateStatus : NSObject

@property(nonatomic, readonly, copy) NSString* publisher;
@property(nonatomic, readonly, copy) NSString* name;
@property(nonatomic, readonly, copy) NSString* currentVersion;
@property(nonatomic, readonly, copy) NSString* latestVersion;
@property(nonatomic, readonly) BOOL updateAvailable;
@property(nonatomic, readonly, copy) NSDictionary<NSString*, id>* latestRelease;

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
                                                  trustBundle:(OrenAVMOBCTrustBundle*)trustBundle
                                                        error:(NSError* _Nullable* _Nullable)error;
- (nullable OrenAVMPackage*)downloadPackageFromSignedIndexURL:(NSURL*)indexURL
                                                    packageID:(NSString*)packageID
                                                      version:(nullable NSString*)version
                                      destinationDirectoryURL:(NSURL*)destinationDirectoryURL
                                                 allowedHosts:(nullable NSSet<NSString*>*)allowedHosts
                                               timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                                  trustBundle:(OrenAVMOBCTrustBundle*)trustBundle
                                                installPolicy:(OrenAVMPackageInstallPolicy)installPolicy
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
- (nullable OrenAVMPackage*)downloadPackageFromSignedIndexURL:(NSURL*)indexURL
                                                    packageID:(NSString*)packageID
                                                      version:(nullable NSString*)version
                                      destinationDirectoryURL:(NSURL*)destinationDirectoryURL
                                                 allowedHosts:(nullable NSSet<NSString*>*)allowedHosts
                                               timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                        trustedIndexPublicKey:(nullable NSData*)trustedIndexPublicKey
                                   trustedPublisherPublicKeys:(nullable NSDictionary<NSString*, NSData*>*)trustedPublisherPublicKeys
                                                installPolicy:(OrenAVMPackageInstallPolicy)installPolicy
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
- (nullable OrenAVMPackageUpdateStatus*)packageUpdateStatusFromURL:(NSURL*)updateURL
                                                      allowedHosts:(nullable NSSet<NSString*>*)allowedHosts
                                                    timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                                             error:(NSError* _Nullable* _Nullable)error;
- (nullable OrenAVMPackageUpdateStatus*)packageUpdateStatusForPackage:(OrenAVMPackage*)package
                                                         storeBaseURL:(NSURL*)storeBaseURL
                                                         allowedHosts:(nullable NSSet<NSString*>*)allowedHosts
                                                       timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                                                error:(NSError* _Nullable* _Nullable)error;
- (nullable OrenAVMPackageUpdateStatus*)packageUpdateStatusForInstalledPackage:(OrenAVMPackage*)package
                                                                  allowedHosts:(nullable NSSet<NSString*>*)allowedHosts
                                                                timeoutSeconds:(NSTimeInterval)timeoutSeconds
                                                                         error:(NSError* _Nullable* _Nullable)error;

+ (NSString*)sha256HexForData:(NSData*)data;

@end

#if TARGET_OS_IPHONE

@interface OrenAVMGraphicsView : UIView

@property(nonatomic, strong, nullable) OrenAVMRuntime* runtime;
@property(nonatomic, copy, nullable) NSData* frameData;
@property(nonatomic) NSUInteger retainedImagePixelLimit;
@property(nonatomic) NSUInteger retainedImageCountLimit;
@property(nonatomic, readonly) NSUInteger retainedImagePixelCount;
@property(nonatomic, readonly) NSUInteger retainedImageCount;

- (instancetype)initWithRuntime:(OrenAVMRuntime*)runtime NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(CGRect)frame NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder*)coder NS_DESIGNATED_INITIALIZER;
- (BOOL)reloadFrameWithError:(NSError* _Nullable* _Nullable)error;
- (void)clearImageCache;
- (BOOL)sendPointerEventWithKind:(uint8_t)kind
                           point:(CGPoint)point
                       pointerId:(uint32_t)pointerId
                           error:(NSError* _Nullable* _Nullable)error;
- (BOOL)sendPointerEventsWithKind:(uint8_t)kind
                            points:(NSArray<NSValue*>*)points
                        pointerIDs:(NSArray<NSNumber*>*)pointerIDs
                             error:(NSError* _Nullable* _Nullable)error;
- (BOOL)sendResizeEventWithScaleMilli:(uint32_t)scaleMilli error:(NSError* _Nullable* _Nullable)error;
- (BOOL)sendMediaEventWithTargetHzMilli:(uint32_t)targetHzMilli
                                  flags:(uint32_t)flags
                                  error:(NSError* _Nullable* _Nullable)error;
- (BOOL)publishScreenStateWithTargetHzMilli:(uint32_t)targetHzMilli
                                      flags:(uint32_t)flags
                                      error:(NSError* _Nullable* _Nullable)error;

@end

@interface OrenAVMMetalView : MTKView

@property(nonatomic, strong, nullable) OrenAVMRuntime* runtime;
@property(nonatomic, copy, nullable) NSData* frameData;
@property(nonatomic) uint32_t targetHzMilli;
@property(nonatomic) uint32_t mediaFlags;
@property(nonatomic) uint32_t frameBudgetWarningPermille;
@property(nonatomic) NSUInteger retainedImagePixelLimit;
@property(nonatomic) NSUInteger retainedImageCountLimit;
@property(nonatomic, readonly) uint64_t renderedFrameCount;
@property(nonatomic, readonly) uint64_t lastFrameCPUNs;
@property(nonatomic, readonly) uint64_t lastFrameTargetBudgetNs;
@property(nonatomic, readonly) uint32_t lastFrameBudgetUsagePermille;
@property(nonatomic, readonly) BOOL lastFrameOverBudget;
@property(nonatomic, readonly) uint32_t lastFrameVertexCount;
@property(nonatomic, readonly) uint32_t lastFrameTextRunCount;
@property(nonatomic, readonly) uint32_t lastFrameImageRunCount;
@property(nonatomic, readonly) NSUInteger retainedImagePixelCount;
@property(nonatomic, readonly) NSUInteger retainedImageCount;

- (instancetype)initWithRuntime:(OrenAVMRuntime*)runtime NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(CGRect)frame device:(nullable id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder*)coder NS_DESIGNATED_INITIALIZER;
- (BOOL)reloadFrameWithError:(NSError* _Nullable* _Nullable)error;
- (void)clearTextTextureCache;
- (void)clearImageTextureCache;
- (void)resetFrameMetrics;
- (BOOL)prepareFrameResourcesWithError:(NSError* _Nullable* _Nullable)error;
- (BOOL)frameCPUNsExceedsBudget:(uint64_t)cpuNs;
- (BOOL)sendPointerEventWithKind:(uint8_t)kind
                           point:(CGPoint)point
                       pointerId:(uint32_t)pointerId
                           error:(NSError* _Nullable* _Nullable)error;
- (BOOL)sendPointerEventsWithKind:(uint8_t)kind
                            points:(NSArray<NSValue*>*)points
                        pointerIDs:(NSArray<NSNumber*>*)pointerIDs
                             error:(NSError* _Nullable* _Nullable)error;
- (BOOL)publishScreenStateWithError:(NSError* _Nullable* _Nullable)error;
- (BOOL)sendMediaEventWithError:(NSError* _Nullable* _Nullable)error;

@end

#endif

FOUNDATION_EXPORT NSString* const OrenAVMKitErrorDomain;

NS_ASSUME_NONNULL_END

#endif
