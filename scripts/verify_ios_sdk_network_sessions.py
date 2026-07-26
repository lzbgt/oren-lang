#!/usr/bin/env python3
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SDK = ROOT / "sdk/ios/OrenAVMKit/OrenAVMKit.m"


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def main() -> int:
    text = SDK.read_text()
    if "CFMutableDictionaryRef _networkSockets" not in text:
        fail("iOS VNET sockets must use scalar-key CF dictionaries")
    if "CFMutableDictionaryRef _networkSessionKinds" not in text:
        fail("iOS VNET session kinds must use scalar-key CF dictionaries")
    if "CFMutableDictionaryRef _networkSessionByteCounts" not in text:
        fail("iOS VNET byte counts must use scalar-key CF dictionaries")
    forbidden = [
        "NSMutableDictionary<NSNumber*, NSNumber*>* _networkSockets",
        "NSMutableDictionary<NSNumber*, NSString*>* _networkSessionKinds",
        "NSMutableDictionary<NSNumber*, NSNumber*>* _networkSessionByteCounts",
        "_networkSockets[@(",
        "_networkSessionKinds[@(",
        "_networkSessionByteCounts[@(",
        "NSNumber* key = @(sessionId)",
        "for (NSNumber* fdValue in _networkSockets.allValues)",
        "for (NSNumber* usedValue in _networkSessionByteCounts.allValues)",
        "dataUsingEncoding:NSASCIIStringEncoding",
        "NSMutableData* keyBytes",
        "base64EncodedStringWithOptions:0",
        "NSMutableData* response",
        "appendBytes:tmp",
        "initWithData:response",
        "uint8_t* frame = (uint8_t*)malloc(frameLen)",
        "char** ips = (char**)calloc(cap, sizeof(char*))",
    ]
    for needle in forbidden:
        if needle in text:
            fail(f"iOS VNET session path must not box session state via `{needle}`")
    init_match = re.search(
        r"- \(instancetype\)initWithConfig:\(OrenAVMRuntimeConfig\*\)config \{(?P<body>.*?)\n\}",
        text,
        re.S,
    )
    if not init_match:
        fail("missing OrenAVMRuntime initWithConfig body")
    init_body = init_match.group("body")
    eager_init_forbidden = [
        "_networkSession = [NSURLSession sessionWithConfiguration:sessionConfig]",
        "_networkSockets = CFDictionaryCreateMutable",
        "_networkSessionKinds = CFDictionaryCreateMutable",
        "_networkSessionByteCounts = CFDictionaryCreateMutable",
    ]
    for needle in eager_init_forbidden:
        if needle in init_body:
            fail(f"iOS runtime startup must not eagerly allocate network state via `{needle}`")
    required = [
        "OrenAVMRuntimeNetworkSessionKey",
        "OrenAVMRuntimeNetworkSocketValue",
        "OrenAVMRuntimeNetworkByteCountValue",
        "static BOOL OrenAVMRuntimeEnsureNetworkSessionMaps",
        "static NSURLSession* OrenAVMRuntimeEnsureNetworkSession",
        "if (!OrenAVMRuntimeEnsureNetworkSessionMaps(runtime)) return 0",
        "CFDictionarySetValue(runtime->_networkSockets, key, OrenAVMRuntimeNetworkSocketValue(fd))",
        "CFDictionarySetValue(runtime->_networkSessionKinds, key, (__bridge const void*)kind)",
        "CFDictionarySetValue(runtime->_networkSessionByteCounts, key, OrenAVMRuntimeNetworkByteCountValue(0))",
        "NSURLSession* session = OrenAVMRuntimeEnsureNetworkSession(runtime, runtime->_liveNetworkTimeoutSeconds)",
        "NSURLSession* session = OrenAVMRuntimeEnsureNetworkSession(self, timeoutSeconds)",
        "OrenAVMRuntimeNetworkSessionBytes(runtime->_networkSessionByteCounts, sessionId)",
        "CFDictionaryApplyFunction(_networkSockets, OrenAVMRuntimeCloseNetworkSocketValue, NULL)",
        "CFDictionaryApplyFunction(_networkSessionByteCounts, OrenAVMRuntimeCheckNetworkByteLimit, &check)",
        "static NSString* OrenAVMRuntimeBase64String",
        "OrenAVMRuntimeCopyASCIIBytes",
        "OrenAVMRuntimeSendASCIIString(fd, request)",
        "uint8_t keyBytes[16]",
        "uint8_t response[8192]",
        "[[NSString alloc] initWithBytes:response length:responseLen encoding:NSASCIIStringEncoding]",
        "uint8_t inlineFrame[2048]",
        "uint8_t* frame = frameLen <= sizeof(inlineFrame) ? inlineFrame : (uint8_t*)malloc(frameLen)",
        "if (frame != inlineFrame) free(frame)",
        "char** ips = NULL",
        "if (!ips) {\n            ips = (char**)malloc(cap * sizeof(char*));",
        "if (count == 0) {\n        return -1;\n    }",
    ]
    for needle in required:
        if needle not in text:
            fail(f"missing scalar iOS VNET session map evidence: `{needle}`")
    print("OK: iOS VNET session maps use scalar CF storage, lazy network state, and raw WebSocket handshake buffers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
