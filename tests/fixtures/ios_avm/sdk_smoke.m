#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif
#import "OrenAVMKit/OrenAVMKit.h"
#include "embed_chain_obc.h"
#include "cancel_spin_obc.h"
#include "host_fs_chain_obc.h"

#include <pthread.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static uint64_t host_now_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

typedef struct {
    __unsafe_unretained OrenAVMRuntime* runtime;
    __unsafe_unretained NSData* obc;
    int saw_result;
    NSInteger status;
} SDKConcurrentRunCtx;

static void* sdk_concurrent_run_main(void* arg) {
    @autoreleasepool {
        SDKConcurrentRunCtx* ctx = (SDKConcurrentRunCtx*)arg;
        NSError* error = nil;
        OrenAVMRunResult* result = [ctx->runtime runOBCData:ctx->obc error:&error];
        ctx->saw_result = result != nil;
        ctx->status = result ? result.status : (error ? error.code : -1);
    }
    return NULL;
}

static int run_sdk_concurrent_run_guard_smoke(void) {
    OrenAVMRuntimeConfig* cfg = [OrenAVMRuntimeConfig deterministicDefaults];
    cfg.gasLimit = 0;
    OrenAVMRuntime* runtime = [[OrenAVMRuntime alloc] initWithConfig:cfg];
    if (!runtime) return 170;
    NSData* spinObc = [NSData dataWithBytes:kCancelSpinObc length:kCancelSpinObcLen];
    SDKConcurrentRunCtx ctx = { runtime, spinObc, 0, 0 };
    pthread_t thread;
    if (pthread_create(&thread, NULL, sdk_concurrent_run_main, &ctx) != 0) return 171;
    usleep(10000);
    NSError* error = nil;
    OrenAVMRunResult* second = [runtime runOBCData:spinObc error:&error];
    if (second != nil) return 172;
    if (!error || error.code != AVM_EMBED_ERR_INVALID_ARG) return 173;
    NSString* message = error.userInfo[NSLocalizedDescriptionKey];
    if (![message containsString:@"already running"]) return 174;
    if (![runtime requestCancelWithError:&error]) return 175;
    if (pthread_join(thread, NULL) != 0) return 176;
    if (ctx.saw_result || ctx.status != AVM_EMBED_ERR_VM) return 177;
    if (![runtime clearCancelWithError:&error]) return 178;
    return 0;
}

int main(void) {
    @autoreleasepool {
        NSDictionary<NSString*, NSString*>* env = [[NSProcessInfo processInfo] environment];
        NSString* netURL = env[@"OREN_AVM_SDK_NET_URL"] ?: @"https://note.local/probe";
        NSString* tcpURL = env[@"OREN_AVM_SDK_TCP_URL"] ?: @"session-none";
        NSString* tcpListenURL = env[@"OREN_AVM_SDK_TCP_LISTEN_URL"] ?: @"listen-none";
        NSString* packageDir = env[@"OREN_AVM_SDK_PACKAGE_DIR"];
        NSString* scenePackageDir = env[@"OREN_AVM_SDK_SCENE_PACKAGE_DIR"];
        NSString* packageIndexURL = env[@"OREN_AVM_SDK_PACKAGE_INDEX_URL"];
        NSString* servicePackageIndexURL = env[@"OREN_AVM_SDK_SERVICE_PACKAGE_INDEX_URL"];
        NSString* packageDownloadDir = env[@"OREN_AVM_SDK_PACKAGE_DOWNLOAD_DIR"];
        NSString* servicePackageDownloadDir = env[@"OREN_AVM_SDK_SERVICE_PACKAGE_DOWNLOAD_DIR"];
        NSString* storeIndexKeyB64 = env[@"OREN_AVM_SDK_STORE_INDEX_KEY_B64"];
        NSString* badStoreIndexKeyB64 = env[@"OREN_AVM_SDK_BAD_STORE_INDEX_KEY_B64"];
        NSString* packagePublisherKeyB64 = env[@"OREN_AVM_SDK_PACKAGE_PUBLISHER_KEY_B64"];
        NSString* trustBundlePath = env[@"OREN_AVM_SDK_TRUST_BUNDLE_PATH"];
        NSString* allowedHost = env[@"OREN_AVM_SDK_NET_ALLOWED_HOST"] ?: @"note.local";
        NSString* allowedHostList = env[@"OREN_AVM_SDK_NET_ALLOWED_HOSTS"];
        BOOL prefetchNetwork = env[@"OREN_AVM_SDK_NET_PREFETCH"] != nil;
        BOOL liveNetwork = env[@"OREN_AVM_SDK_NET_LIVE"] != nil;
        BOOL defaultLiveNetwork = env[@"OREN_AVM_SDK_NET_DEFAULT_LIVE"] != nil;
        NSInteger expectedExit = env[@"OREN_AVM_SDK_EXPECT_EXIT"] ? env[@"OREN_AVM_SDK_EXPECT_EXIT"].integerValue : 9;
        NSString* sessionByteLimit = env[@"OREN_AVM_SDK_SESSION_BYTE_LIMIT"];

        OrenAVMRuntimeConfig* cfg = [OrenAVMRuntimeConfig interactiveAppDefaults];
        if (cfg.timeMode != OrenAVMTimeModeInteractiveWallClock) return 31;
        if (cfg.fsBackend != OrenAVMVirtualBackendVirtual) return 32;
        if (cfg.netBackend != OrenAVMVirtualBackendVirtual) return 33;
        if (cfg.procBackend != OrenAVMVirtualBackendVirtual) return 34;
        if (!cfg.liveNetworkEnabled) return 69;
        if (cfg.liveNetworkMaxSessions == 0) return 80;
        if (cfg.liveNetworkSessionByteLimitBytes == 0) return 81;
        if (sessionByteLimit) cfg.liveNetworkSessionByteLimitBytes = (uint64_t)sessionByteLimit.longLongValue;
        int concurrentGuard = run_sdk_concurrent_run_guard_smoke();
        if (concurrentGuard != 0) return concurrentGuard;

        OrenAVMRuntime* runtime = [[OrenAVMRuntime alloc] initWithConfig:cfg];
        if (!runtime) return 35;
        NSError* error = nil;
        __block NSUInteger graphicsFrameHandlerCount = 0;
        __block uint32_t graphicsFrameHandlerFirstSequence = 0;
        __block NSUInteger graphicsFrameHandlerFirstLength = 0;
        __block uint32_t graphicsFrameHandlerSequence = 0;
        __block NSUInteger graphicsFrameHandlerLength = 0;
        __block NSUInteger graphicsFrameObserverCount = 0;
        id observerToken = [runtime addGraphicsFrameHandler:^(uint32_t sequence, NSUInteger byteLength) {
            (void)sequence;
            (void)byteLength;
            graphicsFrameObserverCount += 1;
        }];
        if (!observerToken) return 190;
        runtime.graphicsFrameHandler = ^(uint32_t sequence, NSUInteger byteLength) {
            if (graphicsFrameHandlerCount == 0) {
                graphicsFrameHandlerFirstSequence = sequence;
                graphicsFrameHandlerFirstLength = byteLength;
            }
            graphicsFrameHandlerCount += 1;
            graphicsFrameHandlerSequence = sequence;
            graphicsFrameHandlerLength = byteLength;
        };
        if (defaultLiveNetwork) {
            if (![runtime disableLiveNetworkWithError:&error]) return 70;
            NSSet<NSString*>* allowedHosts = allowedHostList.length > 0
                ? [NSSet setWithArray:[allowedHostList componentsSeparatedByString:@","]]
                : nil;
            if (![runtime enableLiveNetworkWithAllowedHosts:allowedHosts timeoutSeconds:5.0 error:&error]) return 71;
        }
        if (![runtime configureLiveNetworkSessionLimitsWithMaxSessions:cfg.liveNetworkMaxSessions
                                                        byteLimitBytes:cfg.liveNetworkSessionByteLimitBytes
                                                                 error:&error]) return 82;
        if (![runtime setArgv:@[@"oren", @"ios", netURL, tcpURL, tcpListenURL] error:&error]) return 36;
        NSData* input = [@"abc" dataUsingEncoding:NSUTF8StringEncoding];
        if (![runtime putVFSFileAtPath:@"input.txt" data:input error:&error]) return 37;
        NSURL* tempRoot = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"oren-avmkit-fs-%@", [[NSUUID UUID] UUIDString]]]
                                     isDirectory:YES];
        NSURL* assetDir = [tempRoot URLByAppendingPathComponent:@"assets" isDirectory:YES];
        NSURL* nestedDir = [assetDir URLByAppendingPathComponent:@"nested" isDirectory:YES];
        if (![[NSFileManager defaultManager] createDirectoryAtURL:nestedDir
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&error]) return 60;
        NSURL* configURL = [assetDir URLByAppendingPathComponent:@"config.txt" isDirectory:NO];
        NSURL* nestedURL = [nestedDir URLByAppendingPathComponent:@"skip.txt" isDirectory:NO];
        if (![[@"mount-ok" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:configURL options:NSDataWritingAtomic error:&error]) return 61;
        if (![[@"nested-ok" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:nestedURL options:NSDataWritingAtomic error:&error]) return 62;
        if (![runtime mountDirectoryURL:assetDir atVFSRoot:@"assets" error:&error]) return 63;
        if (![runtime mountFileURL:configURL atVFSPath:@"assets/config.txt" error:&error]) return 64;
        NSData* body = [@"net-ok" dataUsingEncoding:NSUTF8StringEncoding];
        if (liveNetwork) {
            NSURL* url = [NSURL URLWithString:netURL];
            if (![runtime enableLiveNetworkWithAllowedHosts:[NSSet setWithObject:allowedHost] timeoutSeconds:5.0 error:&error]) return 68;
        } else if (prefetchNetwork) {
            NSURL* url = [NSURL URLWithString:netURL];
            if (url.port) {
                NSString* wrongOrigin = [NSString stringWithFormat:@"%@://%@:%ld", url.scheme.lowercaseString, url.host.lowercaseString, (long)url.port.integerValue + 1];
                NSError* deniedError = nil;
                if ([runtime fetchURLIntoVirtualNet:url allowedHosts:[NSSet setWithObject:wrongOrigin] timeoutSeconds:5.0 error:&deniedError]) return 182;
                if (!deniedError) return 183;
            }
            if (![runtime fetchURLIntoVirtualNet:url allowedHosts:[NSSet setWithObject:allowedHost] timeoutSeconds:5.0 error:&error]) return 38;
        } else if (!defaultLiveNetwork && ![runtime putVirtualNetResponseForURL:netURL data:body error:&error]) {
            return 38;
        }
        if (![runtime putVirtualProcExitForCommand:@"probe-ok" exitCode:21 error:&error]) return 39;
        if (![runtime setVirtualProcDefaultExitCode:44 error:&error]) return 40;
        if (![runtime putGraphicsPointerEventWithKind:1 x:1 y:2 pointerId:7 error:&error]) return 51;
        if (![runtime putGraphicsPointerEventWithKind:2 x:2 y:3 pointerId:7 error:&error]) return 58;
        if (![runtime putGraphicsPointerEventWithKind:3 x:3 y:4 pointerId:7 error:&error]) return 59;
        if (![runtime putGraphicsResizeEventWithWidth:4 height:3 scaleMilli:3000 error:&error]) return 54;
        if (![runtime setGraphicsScreenWithID:0 width:4 height:3 scaleMilli:3000 drawableWidth:12 drawableHeight:9 targetHzMilli:120000 flags:5 error:&error]) return 62;
        if (![runtime putGraphicsMediaEventWithWidth:4 height:3 scaleMilli:3000 drawableWidth:12 drawableHeight:9 targetHzMilli:120000 flags:5 error:&error]) return 60;
        if (![runtime putGraphicsFrameTickEventWithSequence:9 nowNs:1000 deltaNs:16 targetHzMilli:120000 flags:5 error:&error]) return 67;
        if (![runtime putGraphicsKeyEventWithKind:32 keyCode:65 modifiers:1 error:&error]) return 55;
        if (![runtime putGraphicsTextInputString:@"hi" error:&error]) return 56;
        if (![runtime putGraphicsGamepadEventWithControllerID:3 buttons:5 lxMilli:-1000 lyMilli:1000 rxMilli:0 ryMilli:-250 error:&error]) return 153;
        if (![runtime putGraphicsMotionEventWithSourceID:2 sequence:7 timestampNs:1234 accelXMilli:-10 accelYMilli:20 accelZMilli:-30 gyroXMilli:40 gyroYMilli:-50 gyroZMilli:60 error:&error]) return 154;
        if (![runtime putGraphicsFocusEventWithKind:112 focusID:4 flags:1 error:&error]) return 155;
        if (![runtime putGraphicsCompositionEventWithKind:128 text:@"abc" selectionStart:1 selectionEnd:2 error:&error]) return 156;
        if (![runtime putVirtualEventWithKind:@"fs" action:@"write" detail:@"host/out.txt" flags:7 error:&error]) return 151;
        if (![runtime putVirtualEventWithKind:@"package" action:@"installed" detail:@"oren-labs/sdk-package-smoke/0.1.0" flags:0 error:&error]) return 152;

#if TARGET_OS_IPHONE
        OrenAVMGraphicsView* eventDrivenGraphicsView = [[OrenAVMGraphicsView alloc] initWithRuntime:runtime];
        OrenAVMMetalView* eventDrivenMetalView = [[OrenAVMMetalView alloc] initWithRuntime:runtime];
        if (!eventDrivenGraphicsView || !eventDrivenMetalView) return 191;
#endif
        NSData* obc = [NSData dataWithBytes:kEmbedChainObc length:kEmbedChainObcLen];
        uint64_t wall0 = host_now_ns();
        OrenAVMRunResult* result = [runtime runOBCData:obc error:&error];
        uint64_t wall1 = host_now_ns();
        if (!result) return 41;
        if (result.exitCode != expectedExit) {
            fprintf(stderr, "sdk_smoke: expected OBC exit %ld got %ld status %ld avm_error %ld\n",
                    (long)expectedExit,
                    (long)result.exitCode,
                    (long)result.status,
                    (long)result.avmErrorCode);
            return 42;
        }
        if (expectedExit != 9) return 0;
        if (wall1 <= wall0 || wall1 - wall0 < 10000000ull) return 43;
        if (graphicsFrameHandlerCount != 2) return 183;
        if (graphicsFrameObserverCount != 2) return 192;
        if (graphicsFrameHandlerFirstSequence != 7u || graphicsFrameHandlerFirstLength != 1102u) return 184;
        if (graphicsFrameHandlerSequence != 8u || graphicsFrameHandlerLength != 1102u) return 184;
#if TARGET_OS_IPHONE
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (!eventDrivenGraphicsView.hasValidFrameData || !eventDrivenMetalView.hasValidFrameData) return 193;
#endif
        if ([runtime capturedOutputLengthWithError:&error] != 14) return 180;
        if (![runtime hasPermissionRequestWithError:&error]) return 181;
        NSNumber* permissionSequence = [runtime permissionRequestSequenceWithError:&error];
        if (!permissionSequence || permissionSequence.unsignedIntValue != 1u) return 182;
        NSDictionary<NSString*, id>* permission = [runtime getPermissionRequestWithError:&error];
        if (!permission) return 72;
        if (![permission[@"domain"] isEqual:@"NET"]) return 73;
        if (![permission[@"action"] isEqual:@"connect"]) return 74;
        if (![permission[@"detail"] isEqual:tcpURL]) return 75;
        if (![permission[@"sequence"] isEqual:@1]) return 76;
        NSData* permissionData = [runtime getPermissionRequestDataWithError:&error];
        if (!permissionData || permissionData.length < 20) return 77;
        OrenAVMPermissionPrompt* prompt = [OrenAVMPermissionPrompt promptWithPermissionRequest:permission error:&error];
        if (!prompt) return 162;
        if (![prompt.domain isEqual:@"NET"]) return 163;
        if (![prompt.action isEqual:@"connect"]) return 164;
        if (![prompt.detail isEqual:tcpURL]) return 165;
        if (prompt.sequence != 1) return 166;
        NSString* expectedPromptHost = [tcpURL containsString:@"://"] ? @"127.0.0.1" : tcpURL;
        if (![prompt.networkHost isEqual:expectedPromptHost]) return 167;
        if (![prompt.riskLevel isEqual:@"network"]) return 168;
        if (prompt.title.length == 0 || prompt.message.length == 0) return 169;
        NSURL* grantsURL = [tempRoot URLByAppendingPathComponent:@"permission-grants.json" isDirectory:NO];
        OrenAVMPermissionGrantStore* grantStore = [[OrenAVMPermissionGrantStore alloc] initWithStoreURL:grantsURL];
        if (![grantStore loadWithError:&error]) return 116;
        if (![grantStore recordDecisionForPermissionPrompt:prompt
                                                   granted:YES
                                                   runtime:runtime
                                            timeoutSeconds:5.0
                                                      error:&error]) return 117;
        if (![grantStore isGrantedForDomain:@"NET" action:@"connect" detail:tcpURL]) return 118;
        if (![grantStore isGrantedForPermissionPrompt:prompt]) return 170;
        if (grantStore.allowedNetworkHosts.count != 1) return 119;
        OrenAVMPermissionGrantStore* reloadedGrantStore = [[OrenAVMPermissionGrantStore alloc] initWithStoreURL:grantsURL];
        if (![reloadedGrantStore loadWithError:&error]) return 120;
        if (![reloadedGrantStore isGrantedForDomain:@"NET" action:@"connect" detail:tcpURL]) return 121;
        if (![reloadedGrantStore recordDecisionForPermissionPrompt:prompt
                                                          granted:NO
                                                          runtime:runtime
                                                   timeoutSeconds:5.0
                                                             error:&error]) return 122;
        if ([reloadedGrantStore isGrantedForDomain:@"NET" action:@"connect" detail:tcpURL]) return 123;
        if ([reloadedGrantStore isGrantedForPermissionPrompt:prompt]) return 171;
        if (reloadedGrantStore.allowedNetworkHosts.count != 0) return 124;
        if (![runtime clearPermissionRequestWithError:&error]) return 78;
        if ([runtime hasPermissionRequestWithError:&error]) return 183;
        if ([runtime permissionRequestSequenceWithError:&error] != nil) return 184;
        if ([runtime getPermissionRequestDataWithError:&error] != nil) return 79;
        NSData* out = [runtime getVFSFileAtPath:@"out.txt" error:&error];
        if (![out isEqualToData:[@"ios:abc" dataUsingEncoding:NSUTF8StringEncoding]]) return 44;
        NSData* nested = [runtime getVFSFileAtPath:@"assets/nested/skip.txt" error:&error];
        if (![nested isEqualToData:[@"nested-ok" dataUsingEncoding:NSUTF8StringEncoding]]) return 65;
        NSURL* exportURL = [tempRoot URLByAppendingPathComponent:@"out/export.txt" isDirectory:NO];
        if (![runtime exportVFSFileAtPath:@"export.txt"
                                toFileURL:exportURL
             createIntermediateDirectories:YES
                                    error:&error]) return 66;
        NSData* exported = [NSData dataWithContentsOfURL:exportURL options:0 error:&error];
        if (![exported isEqualToData:[@"export:mount-ok" dataUsingEncoding:NSUTF8StringEncoding]]) return 67;
        NSURL* liveDir = [tempRoot URLByAppendingPathComponent:@"live-host" isDirectory:YES];
        if (![[NSFileManager defaultManager] createDirectoryAtURL:liveDir
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&error]) return 83;
        NSURL* liveInputURL = [liveDir URLByAppendingPathComponent:@"input.txt" isDirectory:NO];
        if (![[@"host-in" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:liveInputURL options:NSDataWritingAtomic error:&error]) return 84;
        OrenAVMRuntime* hostFSRuntime = [[OrenAVMRuntime alloc] initWithConfig:[OrenAVMRuntimeConfig interactiveAppDefaults]];
        if (!hostFSRuntime) return 85;
        if (![hostFSRuntime mountHostDirectoryURL:liveDir atVFSRoot:@"host" readable:YES writable:YES error:&error]) return 86;
        NSData* hostFSObc = [NSData dataWithBytes:kHostFSChainObc length:kHostFSChainObcLen];
        OrenAVMRunResult* hostFSResult = [hostFSRuntime runOBCData:hostFSObc error:&error];
        if (!hostFSResult || hostFSResult.exitCode != 9) return 87;
        NSData* liveOut = [NSData dataWithContentsOfURL:[liveDir URLByAppendingPathComponent:@"out.txt" isDirectory:NO]
                                                options:0
                                                  error:&error];
        if (![liveOut isEqualToData:[@"host-out:host-in" dataUsingEncoding:NSUTF8StringEncoding]]) return 88;
        if (packageDir.length > 0) {
            OrenAVMPackageStore* store = [[OrenAVMPackageStore alloc] init];
            OrenAVMPackage* package = [store loadPackageAtDirectoryURL:[NSURL fileURLWithPath:packageDir isDirectory:YES]
                                                                  error:&error];
            if (!package || ![package.packageID isEqual:@"oren-labs/sdk-package-smoke/0.1.0"]) return 89;
            OrenAVMRuntimeConfig* packageCfg = [store runtimeConfigForPackage:package error:&error];
            if (!packageCfg || (packageCfg.allowedDomains & OrenAVMDomainFS) == 0 || (packageCfg.allowedDomains & OrenAVMDomainNet) == 0) return 90;
            OrenAVMRuntime* packageRuntime = [[OrenAVMRuntime alloc] initWithConfig:packageCfg];
            if (!packageRuntime) return 91;
            NSURL* packageGrantsURL = [tempRoot URLByAppendingPathComponent:@"package-permission-grants.json" isDirectory:NO];
            OrenAVMPermissionGrantStore* packageGrantStore = [[OrenAVMPermissionGrantStore alloc] initWithStoreURL:packageGrantsURL];
            if (![packageGrantStore loadWithError:&error]) return 147;
            if (![packageGrantStore applyPackagePermissionDefaults:package runtime:packageRuntime timeoutSeconds:5.0 error:&error]) return 148;
            if (![packageGrantStore isGrantedForDomain:@"NET" action:@"connect" detail:@"tcp://package.example:443"]) return 149;
            if (![packageGrantStore.allowedNetworkHosts containsObject:@"package.example"]) return 150;
            OrenAVMRunResult* packageResult = [store runPackage:package runtime:packageRuntime error:&error];
            if (!packageResult || packageResult.exitCode != 9) return 92;
            if (![packageResult.stdoutData isEqualToData:[@"pkg:pkg-asset\n" dataUsingEncoding:NSUTF8StringEncoding]]) return 93;
        }
        if (scenePackageDir.length > 0) {
            OrenAVMPackageStore* store = [[OrenAVMPackageStore alloc] init];
            OrenAVMPackage* package = [store loadPackageAtDirectoryURL:[NSURL fileURLWithPath:scenePackageDir isDirectory:YES]
                                                                  error:&error];
            if (!package || ![package.packageID isEqual:@"oren-labs/sdk-scene3d-package/0.1.0"]) return 157;
            OrenAVMRuntimeConfig* packageCfg = [store runtimeConfigForPackage:package error:&error];
            if (!packageCfg || (packageCfg.allowedDomains & OrenAVMDomainFS) == 0) return 158;
            OrenAVMRuntime* packageRuntime = [[OrenAVMRuntime alloc] initWithConfig:packageCfg];
            if (!packageRuntime) return 159;
            OrenAVMRunResult* packageResult = [store runPackage:package runtime:packageRuntime error:&error];
            if (!packageResult || packageResult.exitCode != 9) return 160;
            if (![packageResult.stdoutData isEqualToData:[@"scene3d:ok\n" dataUsingEncoding:NSUTF8StringEncoding]]) return 161;
        }
        if (packageIndexURL.length > 0 && packageDownloadDir.length > 0) {
            OrenAVMPackageStore* store = [[OrenAVMPackageStore alloc] init];
            NSData* indexKey = [[NSData alloc] initWithBase64EncodedString:(storeIndexKeyB64 ?: @"") options:0];
            NSData* badIndexKey = [[NSData alloc] initWithBase64EncodedString:(badStoreIndexKeyB64 ?: @"") options:0];
            NSData* publisherKey = [[NSData alloc] initWithBase64EncodedString:(packagePublisherKeyB64 ?: @"") options:0];
            NSDictionary<NSString*, NSData*>* trustedKeys = publisherKey ? @{@"oren-labs": publisherKey} : nil;
            OrenAVMOBCTrustBundle* trustBundle = trustBundlePath.length > 0
                ? [OrenAVMOBCTrustBundle loadTrustBundleAtURL:[NSURL fileURLWithPath:trustBundlePath isDirectory:NO] error:&error]
                : nil;
            if (!trustBundle) return 112;
            if (![trustBundle.defaultStoreKeyID isEqual:@"oren-store-dev"]) return 113;
            if (![trustBundle.defaultStorePublicKey isEqualToData:indexKey]) return 114;
            if (![trustBundle.publisherPublicKeys[@"oren-labs"] isEqualToData:publisherKey]) return 115;
            NSURL* packageIndexNSURL = [NSURL URLWithString:packageIndexURL];
            if (!packageIndexNSURL || !packageIndexNSURL.port) return 184;
            NSString* packageOrigin = [NSString stringWithFormat:@"%@://%@:%@", packageIndexNSURL.scheme.lowercaseString, packageIndexNSURL.host.lowercaseString, packageIndexNSURL.port];
            NSString* wrongPackageOrigin = [NSString stringWithFormat:@"%@://%@:%ld", packageIndexNSURL.scheme.lowercaseString, packageIndexNSURL.host.lowercaseString, (long)packageIndexNSURL.port.integerValue + 1];
            error = nil;
            OrenAVMPackage* wrongOriginPackage = [store downloadPackageFromSignedIndexURL:packageIndexNSURL packageID:@"oren-labs/sdk-package-remote" version:@"0.1.0" destinationDirectoryURL:[NSURL fileURLWithPath:packageDownloadDir isDirectory:YES] allowedHosts:[NSSet setWithObject:wrongPackageOrigin] timeoutSeconds:5.0 trustBundle:trustBundle error:&error];
            if (wrongOriginPackage || !error) return 185;
            error = nil;
            OrenAVMPackage* package = [store downloadPackageFromSignedIndexURL:packageIndexNSURL
                                                                      packageID:@"oren-labs/sdk-package-remote"
                                                                        version:@"0.1.0"
                                                        destinationDirectoryURL:[NSURL fileURLWithPath:packageDownloadDir isDirectory:YES]
                                                                   allowedHosts:[NSSet setWithObject:packageOrigin]
                                                                 timeoutSeconds:5.0
                                                                   trustBundle:trustBundle
                                                                          error:&error];
            if (!package || ![package.packageID isEqual:@"oren-labs/sdk-package-remote/0.1.0"]) return 94;
            NSData* bundleOnlySource = [NSData dataWithContentsOfURL:[package.directoryURL URLByAppendingPathComponent:@"assets/source/main.oren" isDirectory:NO]
                                                              options:0
                                                                error:nil];
            if (![bundleOnlySource isEqualToData:[@"print(\"bundle-source\")\n" dataUsingEncoding:NSUTF8StringEncoding]]) return 125;
            OrenAVMRuntimeConfig* packageCfg = [store runtimeConfigForPackage:package error:&error];
            if (!packageCfg || (packageCfg.allowedDomains & OrenAVMDomainFS) == 0) return 95;
            OrenAVMRuntime* packageRuntime = [[OrenAVMRuntime alloc] initWithConfig:packageCfg];
            if (!packageRuntime) return 96;
            OrenAVMRunResult* packageResult = [store runPackage:package runtime:packageRuntime error:&error];
            if (!packageResult || packageResult.exitCode != 9) return 97;
            if (![packageResult.stdoutData isEqualToData:[@"pkg:pkg-asset\n" dataUsingEncoding:NSUTF8StringEncoding]]) return 98;
            NSURL* installRootURL = [NSURL fileURLWithPath:packageDownloadDir isDirectory:YES];
            NSArray<NSString*>* installed = [store listInstalledPackageIDsInDirectoryURL:installRootURL error:&error];
            if (![installed containsObject:@"oren-labs/sdk-package-remote/0.1.0"]) return 101;
            OrenAVMPackage* loadedPackage = [store loadInstalledPackageInDirectoryURL:installRootURL
                                                                            packageID:@"oren-labs/sdk-package-remote"
                                                                              version:@"0.1.0"
                                                                                error:&error];
            if (!loadedPackage || ![loadedPackage.packageID isEqual:@"oren-labs/sdk-package-remote/0.1.0"]) return 102;
            error = nil;
            OrenAVMPackage* keepPackage = [store downloadPackageFromSignedIndexURL:[NSURL URLWithString:packageIndexURL]
                                                                         packageID:@"oren-labs/sdk-package-remote"
                                                                           version:@"0.1.0"
                                                           destinationDirectoryURL:installRootURL
                                                                      allowedHosts:[NSSet setWithObject:@"127.0.0.1"]
                                                                    timeoutSeconds:5.0
                                                             trustedIndexPublicKey:indexKey
                                                        trustedPublisherPublicKeys:trustedKeys
                                                                     installPolicy:OrenAVMPackageInstallPolicyKeepExisting
                                                                             error:&error];
            if (!keepPackage || ![keepPackage.packageID isEqual:@"oren-labs/sdk-package-remote/0.1.0"]) return 106;
            error = nil;
            OrenAVMPackage* duplicatePackage = [store downloadPackageFromSignedIndexURL:[NSURL URLWithString:packageIndexURL]
                                                                              packageID:@"oren-labs/sdk-package-remote"
                                                                                version:@"0.1.0"
                                                                destinationDirectoryURL:installRootURL
                                                                           allowedHosts:[NSSet setWithObject:@"127.0.0.1"]
                                                                         timeoutSeconds:5.0
                                                                  trustedIndexPublicKey:indexKey
                                                             trustedPublisherPublicKeys:trustedKeys
                                                                          installPolicy:OrenAVMPackageInstallPolicyFailIfInstalled
                                                                                  error:&error];
            if (duplicatePackage || !error) return 107;
            error = nil;
            OrenAVMPackage* updatedPackage = [store downloadPackageFromSignedIndexURL:[NSURL URLWithString:packageIndexURL]
                                                                            packageID:@"oren-labs/sdk-package-remote"
                                                                              version:@"0.2.0"
                                                              destinationDirectoryURL:installRootURL
                                                                         allowedHosts:[NSSet setWithObject:@"127.0.0.1"]
                                                                       timeoutSeconds:5.0
                                                                trustedIndexPublicKey:indexKey
                                                           trustedPublisherPublicKeys:trustedKeys
                                                                        installPolicy:OrenAVMPackageInstallPolicyFailIfInstalled
                                                                                error:&error];
            if (!updatedPackage || ![updatedPackage.packageID isEqual:@"oren-labs/sdk-package-remote/0.2.0"]) return 108;
            OrenAVMRuntimeConfig* updatedCfg = [store runtimeConfigForPackage:updatedPackage error:&error];
            OrenAVMRuntime* updatedRuntime = updatedCfg ? [[OrenAVMRuntime alloc] initWithConfig:updatedCfg] : nil;
            OrenAVMRunResult* updatedResult = updatedRuntime ? [store runPackage:updatedPackage runtime:updatedRuntime error:&error] : nil;
            if (!updatedResult || ![updatedResult.stdoutData isEqualToData:[@"pkg:pkg-asset-v2\n" dataUsingEncoding:NSUTF8StringEncoding]]) return 109;
            error = nil;
            OrenAVMPackage* badAssetPackage = [store downloadPackageFromSignedIndexURL:[NSURL URLWithString:packageIndexURL]
                                                                             packageID:@"oren-labs/sdk-package-bad-asset"
                                                                               version:@"0.1.0"
                                                               destinationDirectoryURL:[NSURL fileURLWithPath:packageDownloadDir isDirectory:YES]
                                                                          allowedHosts:[NSSet setWithObject:@"127.0.0.1"]
                                                                        timeoutSeconds:5.0
                                                                 trustedIndexPublicKey:indexKey
                                                            trustedPublisherPublicKeys:trustedKeys
                                                                                 error:&error];
            if (badAssetPackage || !error) return 99;
            error = nil;
            OrenAVMPackage* badSignaturePackage = [store downloadPackageFromSignedIndexURL:[NSURL URLWithString:packageIndexURL]
                                                                                 packageID:@"oren-labs/sdk-package-bad-signature"
                                                                                   version:@"0.1.0"
                                                                   destinationDirectoryURL:[NSURL fileURLWithPath:packageDownloadDir isDirectory:YES]
                                                                              allowedHosts:[NSSet setWithObject:@"127.0.0.1"]
                                                                            timeoutSeconds:5.0
                                                                     trustedIndexPublicKey:indexKey
                                                                trustedPublisherPublicKeys:trustedKeys
                                                                                     error:&error];
            if (badSignaturePackage || !error) return 100;
            error = nil;
            OrenAVMPackage* badIndexPackage = [store downloadPackageFromSignedIndexURL:[NSURL URLWithString:packageIndexURL]
                                                                             packageID:@"oren-labs/sdk-package-remote"
                                                                               version:@"0.1.0"
                                                               destinationDirectoryURL:[NSURL fileURLWithPath:packageDownloadDir isDirectory:YES]
                                                                          allowedHosts:[NSSet setWithObject:@"127.0.0.1"]
                                                                        timeoutSeconds:5.0
                                                                 trustedIndexPublicKey:badIndexKey
                                                            trustedPublisherPublicKeys:trustedKeys
                                                                                 error:&error];
            if (badIndexPackage || !error) return 105;
            error = nil;
            if (![store removeInstalledPackageInDirectoryURL:installRootURL
                                                   packageID:@"oren-labs/sdk-package-remote"
                                                     version:@"0.1.0"
                                                       error:&error]) return 103;
            if (![store removeInstalledPackageInDirectoryURL:installRootURL
                                                   packageID:@"oren-labs/sdk-package-remote"
                                                     version:@"0.2.0"
                                                       error:&error]) return 110;
            NSArray<NSString*>* afterRemove = [store listInstalledPackageIDsInDirectoryURL:installRootURL error:&error];
            if ([afterRemove containsObject:@"oren-labs/sdk-package-remote/0.1.0"]) return 104;
            if ([afterRemove containsObject:@"oren-labs/sdk-package-remote/0.2.0"]) return 111;
        }
        if (servicePackageIndexURL.length > 0 && servicePackageDownloadDir.length > 0) {
            OrenAVMPackageStore* store = [[OrenAVMPackageStore alloc] init];
            OrenAVMOBCTrustBundle* trustBundle = trustBundlePath.length > 0
                ? [OrenAVMOBCTrustBundle loadTrustBundleAtURL:[NSURL fileURLWithPath:trustBundlePath isDirectory:NO] error:&error]
                : nil;
            if (!trustBundle) return 116;
            OrenAVMPackage* package = [store downloadPackageFromSignedIndexURL:[NSURL URLWithString:servicePackageIndexURL]
                                                                      packageID:@"oren-labs/sdk-package-service"
                                                                        version:@"0.1.0"
                                                        destinationDirectoryURL:[NSURL fileURLWithPath:servicePackageDownloadDir isDirectory:YES]
                                                                   allowedHosts:[NSSet setWithObject:@"127.0.0.1"]
                                                                 timeoutSeconds:5.0
                                                                   trustBundle:trustBundle
                                                                          error:&error];
            if (!package || ![package.packageID isEqual:@"oren-labs/sdk-package-service/0.1.0"]) return 117;
            NSData* serviceBundleOnlySource = [NSData dataWithContentsOfURL:[package.directoryURL URLByAppendingPathComponent:@"assets/source/main.oren" isDirectory:NO]
                                                                     options:0
                                                                       error:nil];
            if (![serviceBundleOnlySource isEqualToData:[@"print(\"service-bundle-source\")\n" dataUsingEncoding:NSUTF8StringEncoding]]) return 126;
            OrenAVMPackageUpdateStatus* updateStatus = [store packageUpdateStatusForPackage:package
                                                                                storeBaseURL:[NSURL URLWithString:servicePackageIndexURL]
                                                                                allowedHosts:[NSSet setWithObject:@"127.0.0.1"]
                                                                              timeoutSeconds:5.0
                                                                                       error:&error];
            if (!updateStatus || !updateStatus.updateAvailable) return 162;
            if (![updateStatus.publisher isEqual:@"oren-labs"] ||
                ![updateStatus.name isEqual:@"sdk-package-service"] ||
                ![updateStatus.currentVersion isEqual:@"0.1.0"] ||
                ![updateStatus.latestVersion isEqual:@"0.2.0"]) return 163;
            if (![updateStatus.latestRelease[@"version"] isEqual:@"0.2.0"]) return 164;
            NSURLComponents* updateURL = [NSURLComponents componentsWithURL:[NSURL URLWithString:servicePackageIndexURL]
                                                      resolvingAgainstBaseURL:NO];
            updateURL.path = @"/api/v0/packages/oren-labs/sdk-package-service/update";
            updateURL.queryItems = @[[NSURLQueryItem queryItemWithName:@"current_version" value:@"0.2.0"]];
            OrenAVMPackageUpdateStatus* currentStatus = [store packageUpdateStatusFromURL:updateURL.URL
                                                                             allowedHosts:[NSSet setWithObject:@"127.0.0.1"]
                                                                           timeoutSeconds:5.0
                                                                                    error:&error];
            if (!currentStatus || currentStatus.updateAvailable ||
                ![currentStatus.latestVersion isEqual:@"0.2.0"]) return 165;
            OrenAVMPackage* reloadedServicePackage = [store loadInstalledPackageInDirectoryURL:[NSURL fileURLWithPath:servicePackageDownloadDir isDirectory:YES]
                                                                                     packageID:@"oren-labs/sdk-package-service"
                                                                                       version:@"0.1.0"
                                                                                         error:&error];
            OrenAVMPackageUpdateStatus* persistedStatus = reloadedServicePackage
                ? [store packageUpdateStatusForInstalledPackage:reloadedServicePackage
                                                   allowedHosts:[NSSet setWithObject:@"127.0.0.1"]
                                                 timeoutSeconds:5.0
                                                          error:&error]
                : nil;
            if (!persistedStatus || !persistedStatus.updateAvailable ||
                ![persistedStatus.latestVersion isEqual:@"0.2.0"]) return 166;
            if (persistedStatus.checkedAtUnixMillis <= 0) return 169;
            OrenAVMPackageUpdateStatus* cachedStatus = [store lastKnownPackageUpdateStatusForInstalledPackage:reloadedServicePackage
                                                                                                        error:&error];
            if (!cachedStatus || !cachedStatus.updateAvailable ||
                ![cachedStatus.latestVersion isEqual:@"0.2.0"] ||
                cachedStatus.checkedAtUnixMillis != persistedStatus.checkedAtUnixMillis) return 170;
            OrenAVMPackage* serviceUpdatedPackage = reloadedServicePackage
                ? [store downloadUpdateForInstalledPackage:reloadedServicePackage
                                   destinationDirectoryURL:[NSURL fileURLWithPath:servicePackageDownloadDir isDirectory:YES]
                                              allowedHosts:nil
                                            timeoutSeconds:5.0
                                               trustBundle:trustBundle
                                                     error:&error]
                : nil;
            if (!serviceUpdatedPackage || ![serviceUpdatedPackage.packageID isEqual:@"oren-labs/sdk-package-service/0.2.0"]) {
                fprintf(stderr, "OBC package update install failed: %s\n", error.localizedDescription.UTF8String ?: "");
                return 167;
            }
            OrenAVMPackageUpdateStatus* cachedAfterInstall = [store lastKnownPackageUpdateStatusForInstalledPackage:reloadedServicePackage
                                                                                                             error:&error];
            if (!cachedAfterInstall || !cachedAfterInstall.updateAvailable ||
                ![cachedAfterInstall.latestVersion isEqual:@"0.2.0"]) return 171;
            OrenAVMRuntimeConfig* packageCfg = [store runtimeConfigForPackage:package error:&error];
            if (!packageCfg || (packageCfg.allowedDomains & OrenAVMDomainFS) == 0) return 118;
            OrenAVMRuntime* packageRuntime = [[OrenAVMRuntime alloc] initWithConfig:packageCfg];
            if (!packageRuntime) return 119;
            OrenAVMRunResult* packageResult = [store runPackage:package runtime:packageRuntime error:&error];
            if (!packageResult || packageResult.exitCode != 9) return 120;
            if (![packageResult.stdoutData isEqualToData:[@"pkg:pkg-asset\n" dataUsingEncoding:NSUTF8StringEncoding]]) return 121;
            NSArray<NSString*>* installed = [store listInstalledPackageIDsInDirectoryURL:[NSURL fileURLWithPath:servicePackageDownloadDir isDirectory:YES] error:&error];
            if (![installed containsObject:@"oren-labs/sdk-package-service/0.1.0"]) return 122;
            if (![installed containsObject:@"oren-labs/sdk-package-service/0.2.0"]) return 168;
        }
        if (![result.stdoutData isEqualToData:[@"stdout:net-ok\n" dataUsingEncoding:NSUTF8StringEncoding]]) return 45;
        if (![runtime hasGraphicsFrameWithError:&error]) return 172;
        NSData* frame = [runtime getGraphicsFrameDataWithError:&error];
        if (!frame) return 46;
        if (frame.length != 1102) return 47;
        const uint8_t* frameBytes = frame.bytes;
        if (memcmp(frameBytes, "OGF0", 4) != 0 || frameBytes[4] != 1 || frameBytes[6] != 40) return 48;
        if (frameBytes[20] != 48 || frameBytes[24] != 8 || frameBytes[28] != 16 || frameBytes[32] != 12) return 48;
        if (frameBytes[40] != 1 || frameBytes[64] != 18 || frameBytes[76] != 1 || frameBytes[100] != 19 || frameBytes[104] != 20 || frameBytes[112] != 1 || frameBytes[136] != 21 || frameBytes[140] != 16 || frameBytes[160] != 6 || frameBytes[188] != 9 || frameBytes[224] != 3 || frameBytes[252] != 4 || frameBytes[276] != 7 || frameBytes[308] != 8 || frameBytes[348] != 5 || frameBytes[380] != 10 || frameBytes[440] != 80 || frameBytes[504] != 81 || frameBytes[512] != 82 || frameBytes[520] != 83 || frameBytes[572] != 84 || frameBytes[580] != 85 || frameBytes[588] != 88 || frameBytes[656] != 84 || frameBytes[664] != 89 || frameBytes[676] != 90 || frameBytes[688] != 91 || frameBytes[716] != 93 || frameBytes[748] != 94 || frameBytes[756] != 95 || frameBytes[764] != 92 || frameBytes[772] != 85 || frameBytes[780] != 22 || frameBytes[792] != 86 || frameBytes[844] != 84 || frameBytes[852] != 87 || frameBytes[876] != 23 || frameBytes[880] != 85 || frameBytes[888] != 17 || frameBytes[892] != 68 || frameBytes[910] != 69 || frameBytes[926] != 72 || frameBytes[954] != 70 || frameBytes[962] != 64 || frameBytes[986] != 65 || frameBytes[1010] != 67 || frameBytes[1050] != 71 || frameBytes[1094] != 66) return 48;
#if TARGET_OS_IPHONE
        OrenAVMGraphicsView* graphicsView = [[OrenAVMGraphicsView alloc] initWithRuntime:runtime];
        if (!graphicsView) return 52;
        graphicsView.frameData = frame;
        if (!graphicsView.hasValidFrameData) return 173;
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(4.0, 3.0), NO, 1.0);
        [graphicsView drawRect:CGRectMake(0.0, 0.0, 4.0, 3.0)];
        UIGraphicsEndImageContext();
        if (graphicsView.retainedImageCount != 0 || graphicsView.retainedImagePixelCount != 0) return 142;
        uint8_t imageOnlyFrameBytes[] = {
            79, 71, 70, 48, 1, 0, 40, 0,
            1, 0, 0, 0, 1, 0, 0, 0, 232, 3, 0, 0, 1, 0, 0, 0,
            0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0,
            64, 0, 20, 0,
            1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 4, 0, 0, 0,
            255, 0, 0, 255
        };
        graphicsView.frameData = [NSData dataWithBytes:imageOnlyFrameBytes length:sizeof(imageOnlyFrameBytes)];
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(1.0, 1.0), NO, 1.0);
        [graphicsView drawRect:CGRectMake(0.0, 0.0, 1.0, 1.0)];
        UIGraphicsEndImageContext();
        if (graphicsView.retainedImageCount != 1 || graphicsView.retainedImagePixelCount != 1) return 145;
        [graphicsView clearImageCache];
        if (graphicsView.retainedImageCount != 0 || graphicsView.retainedImagePixelCount != 0) return 146;
        graphicsView.retainedImageCountLimit = 0;
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(4.0, 3.0), NO, 1.0);
        [graphicsView drawRect:CGRectMake(0.0, 0.0, 4.0, 3.0)];
        UIGraphicsEndImageContext();
        if (graphicsView.retainedImageCount != 0 || graphicsView.retainedImagePixelCount != 0) return 143;
        graphicsView.retainedImageCountLimit = 1024;
        if (![graphicsView sendPointerEventWithKind:2 point:CGPointMake(2.0, 1.0) pointerId:8 error:&error]) return 53;
        if (![graphicsView sendPointerEventsWithKind:2 points:@[[NSValue valueWithCGPoint:CGPointMake(1.0, 1.0)],
                                                                 [NSValue valueWithCGPoint:CGPointMake(3.0, 2.0)]]
                                           pointerIDs:@[@(8u), @(9u)]
                                                error:&error]) return 134;
        if (![graphicsView sendResizeEventWithScaleMilli:1000 error:&error]) return 57;
        if (![graphicsView publishScreenStateWithTargetHzMilli:120000 flags:5 error:&error]) return 123;
        if (![graphicsView sendMediaEventWithTargetHzMilli:120000 flags:5 error:&error]) return 124;
        if (![graphicsView sendTextInputString:@"view-hi" error:&error]) return 194;
        if (![graphicsView sendCompositionEventWithKind:128 text:@"view-ime" selectionStart:1 selectionEnd:3 error:&error]) return 195;
        OrenAVMMetalView* metalView = [[OrenAVMMetalView alloc] initWithRuntime:runtime];
        if (!metalView) return 127;
        metalView.frameData = frame;
        if (!metalView.hasValidFrameData) return 174;
        if (![metalView prepareFrameResourcesWithError:&error]) return 162;
        if (metalView.lastFrameVertexCount < 140u) return 163;
        if (metalView.lastFrameTextRunCount != 2u) return 164;
        if (metalView.lastFrameImageRunCount != 3u) return 165;
        if (metalView.retainedImageCount != 0 || metalView.retainedImagePixelCount != 0) return 166;
        metalView.targetHzMilli = 120000;
        metalView.mediaFlags = 5;
        if (metalView.preferredFramesPerSecond != 120) return 129;
        if (metalView.lastFrameTargetBudgetNs != 8333333ull) return 131;
        if (metalView.frameBudgetWarningPermille != 1000u) return 136;
        if ([metalView frameCPUNsExceedsBudget:8333333ull]) return 137;
        if (![metalView frameCPUNsExceedsBudget:8333334ull]) return 138;
        metalView.frameBudgetWarningPermille = 500u;
        if ([metalView frameCPUNsExceedsBudget:4166666ull]) return 139;
        if (![metalView frameCPUNsExceedsBudget:4166667ull]) return 140;
        metalView.frameBudgetWarningPermille = 1000u;
        metalView.targetHzMilli = 90000;
        if (metalView.preferredFramesPerSecond != 90) return 130;
        if (metalView.lastFrameTargetBudgetNs != 11111111ull) return 132;
        metalView.targetHzMilli = 120000;
        metalView.frameData = [NSData dataWithBytes:imageOnlyFrameBytes length:sizeof(imageOnlyFrameBytes)];
        if (!metalView.hasValidFrameData) return 185;
        if (![metalView prepareFrameResourcesWithError:&error]) return 186;
        if (metalView.retainedImageCount != 1 || metalView.retainedImagePixelCount != 1) return 187;
        metalView.frameData = frame;
        if (![metalView prepareFrameResourcesWithError:&error]) return 188;
        if (metalView.lastFrameTextRunCount != 2u || metalView.lastFrameImageRunCount != 3u) return 189;
        [metalView resetFrameMetrics];
        if (metalView.renderedFrameCount != 0 || metalView.lastFrameCPUNs != 0) return 133;
        if (metalView.lastFrameBudgetUsagePermille != 0 || metalView.lastFrameOverBudget || metalView.lastFrameImageRunCount != 0) return 141;
        metalView.retainedImageCountLimit = 0;
        [metalView clearImageTextureCache];
        if (metalView.retainedImageCount != 0 || metalView.retainedImagePixelCount != 0) return 144;
        metalView.retainedImageCountLimit = 1024;
        if (![metalView sendPointerEventsWithKind:2 points:@[[NSValue valueWithCGPoint:CGPointMake(1.0, 1.0)],
                                                             [NSValue valueWithCGPoint:CGPointMake(3.0, 2.0)]]
                                       pointerIDs:@[@(10u), @(11u)]
                                            error:&error]) return 135;
        if (![metalView sendTextInputString:@"metal-hi" error:&error]) return 196;
        if (![metalView sendCompositionEventWithKind:129 text:@"metal-ime" selectionStart:0 selectionEnd:5 error:&error]) return 197;
        [metalView clearTextTextureCache];
        if (![metalView publishScreenStateWithError:&error]) return 128;
#endif
        if (![runtime clearGraphicsFrameWithError:&error]) return 49;
        if ([runtime hasGraphicsFrameWithError:&error]) return 175;
#if TARGET_OS_IPHONE
        NSData* graphicsFrameAfterClear = graphicsView.frameData;
        if (![graphicsView reloadFrameWithError:&error]) return 176;
        if (![graphicsView.frameData isEqualToData:graphicsFrameAfterClear] || !graphicsView.hasValidFrameData) return 177;
        NSData* metalFrameAfterClear = metalView.frameData;
        if (![metalView reloadFrameWithError:&error]) return 178;
        if (![metalView.frameData isEqualToData:metalFrameAfterClear] || !metalView.hasValidFrameData) return 179;
#endif
        if ([runtime getGraphicsFrameDataWithError:&error] != nil) return 50;
    }
    return 0;
}
