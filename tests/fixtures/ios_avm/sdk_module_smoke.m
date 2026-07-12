@import Foundation;
@import OrenAVMKit;

int main(void) {
    OrenAVMRuntimeConfig* cfg = [OrenAVMRuntimeConfig interactiveAppDefaults];
    if (!cfg || cfg.timeMode != OrenAVMTimeModeInteractiveWallClock) return 1;
    if (!cfg.liveNetworkEnabled) return 2;
    OrenAVMRuntimeConfig* det = [OrenAVMRuntimeConfig deterministicDefaults];
    if (!det || det.liveNetworkEnabled) return 3;
    OrenAVMRuntime* runtime = [[OrenAVMRuntime alloc] initWithConfig:det];
    if (!runtime) return 4;
    NSError* error = nil;
    if (![runtime requestCancelWithError:&error]) return 5;
    if (![runtime clearCancelWithError:&error]) return 6;
    NSURL* tmp = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"oren-avmkit-module-hostfs"]
                            isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:tmp withIntermediateDirectories:YES attributes:nil error:nil];
    if (![runtime mountHostDirectoryURL:tmp atVFSRoot:@"host" readable:YES writable:NO error:&error]) return 7;
    return 0;
}
