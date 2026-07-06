#!/usr/bin/env python3
from pathlib import Path


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
    ]
    for needle in forbidden:
        if needle in text:
            fail(f"iOS VNET session path must not box session state via `{needle}`")
    required = [
        "OrenAVMRuntimeNetworkSessionKey",
        "OrenAVMRuntimeNetworkSocketValue",
        "OrenAVMRuntimeNetworkByteCountValue",
        "CFDictionarySetValue(runtime->_networkSockets, key, OrenAVMRuntimeNetworkSocketValue(fd))",
        "CFDictionarySetValue(runtime->_networkSessionByteCounts, key, OrenAVMRuntimeNetworkByteCountValue(0))",
        "OrenAVMRuntimeNetworkSessionBytes(runtime->_networkSessionByteCounts, sessionId)",
        "CFDictionaryApplyFunction(_networkSockets, OrenAVMRuntimeCloseNetworkSocketValue, NULL)",
        "CFDictionaryApplyFunction(_networkSessionByteCounts, OrenAVMRuntimeCheckNetworkByteLimit, &check)",
        "static NSString* OrenAVMRuntimeBase64String",
        "OrenAVMRuntimeCopyASCIIBytes",
        "OrenAVMRuntimeSendASCIIString(fd, request)",
        "uint8_t keyBytes[16]",
        "uint8_t response[8192]",
        "[[NSString alloc] initWithBytes:response length:responseLen encoding:NSASCIIStringEncoding]",
    ]
    for needle in required:
        if needle not in text:
            fail(f"missing scalar iOS VNET session map evidence: `{needle}`")
    print("OK: iOS VNET session maps use scalar CF storage and raw WebSocket handshake buffers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
