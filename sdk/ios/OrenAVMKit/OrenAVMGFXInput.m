#import "OrenAVMKit.h"

#include <string.h>

static void OrenAVMGFXInputPutU32LE(uint8_t* dst, uint32_t v) {
    dst[0] = (uint8_t)(v & 255u);
    dst[1] = (uint8_t)((v >> 8) & 255u);
    dst[2] = (uint8_t)((v >> 16) & 255u);
    dst[3] = (uint8_t)((v >> 24) & 255u);
}

static void OrenAVMGFXInputPutU64LE(uint8_t* dst, uint64_t v) {
    dst[0] = (uint8_t)(v & 255u);
    dst[1] = (uint8_t)((v >> 8) & 255u);
    dst[2] = (uint8_t)((v >> 16) & 255u);
    dst[3] = (uint8_t)((v >> 24) & 255u);
    dst[4] = (uint8_t)((v >> 32) & 255u);
    dst[5] = (uint8_t)((v >> 40) & 255u);
    dst[6] = (uint8_t)((v >> 48) & 255u);
    dst[7] = (uint8_t)((v >> 56) & 255u);
}

static NSData* OrenAVMGFXInputMakeEvent(uint8_t opcode, const uint8_t* payload, uint16_t payloadLen) {
    NSMutableData* data = [NSMutableData dataWithLength:(NSUInteger)12u + (NSUInteger)payloadLen];
    uint8_t* buf = (uint8_t*)data.mutableBytes;
    buf[0] = 'O'; buf[1] = 'G'; buf[2] = 'E'; buf[3] = '0';
    buf[4] = 0; buf[5] = 0; buf[6] = 0; buf[7] = 0;
    buf[8] = opcode; buf[9] = 0;
    buf[10] = (uint8_t)(payloadLen & 255u);
    buf[11] = (uint8_t)((payloadLen >> 8) & 255u);
    if (payloadLen > 0 && payload) memcpy(buf + 12, payload, payloadLen);
    return data;
}

static BOOL OrenAVMGFXInputSDKError(NSError** error, NSInteger code, NSString* message) {
    if (error) {
        *error = [NSError errorWithDomain:OrenAVMKitErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: message ?: @"OrenAVMKit error"}];
    }
    return NO;
}

@implementation OrenAVMRuntime (GFXInput)

- (BOOL)putGraphicsPointerEventWithKind:(uint8_t)kind x:(int32_t)x y:(int32_t)y pointerId:(uint32_t)pointerId error:(NSError**)error {
    uint8_t payload[12];
    OrenAVMGFXInputPutU32LE(payload, (uint32_t)x);
    OrenAVMGFXInputPutU32LE(payload + 4, (uint32_t)y);
    OrenAVMGFXInputPutU32LE(payload + 8, pointerId);
    NSData* data = OrenAVMGFXInputMakeEvent(kind, payload, sizeof(payload));
    return [self putGraphicsInputEventData:data error:error];
}

- (BOOL)putGraphicsResizeEventWithWidth:(uint32_t)width height:(uint32_t)height scaleMilli:(uint32_t)scaleMilli error:(NSError**)error {
    uint8_t payload[12];
    OrenAVMGFXInputPutU32LE(payload, width);
    OrenAVMGFXInputPutU32LE(payload + 4, height);
    OrenAVMGFXInputPutU32LE(payload + 8, scaleMilli);
    NSData* data = OrenAVMGFXInputMakeEvent(16, payload, sizeof(payload));
    return [self putGraphicsInputEventData:data error:error];
}

- (BOOL)putGraphicsMediaEventWithWidth:(uint32_t)width
                                 height:(uint32_t)height
                             scaleMilli:(uint32_t)scaleMilli
                          drawableWidth:(uint32_t)drawableWidth
                         drawableHeight:(uint32_t)drawableHeight
                          targetHzMilli:(uint32_t)targetHzMilli
                                  flags:(uint32_t)flags
                                  error:(NSError**)error {
    uint8_t payload[28];
    OrenAVMGFXInputPutU32LE(payload, width);
    OrenAVMGFXInputPutU32LE(payload + 4, height);
    OrenAVMGFXInputPutU32LE(payload + 8, scaleMilli);
    OrenAVMGFXInputPutU32LE(payload + 12, drawableWidth);
    OrenAVMGFXInputPutU32LE(payload + 16, drawableHeight);
    OrenAVMGFXInputPutU32LE(payload + 20, targetHzMilli);
    OrenAVMGFXInputPutU32LE(payload + 24, flags);
    NSData* data = OrenAVMGFXInputMakeEvent(17, payload, sizeof(payload));
    return [self putGraphicsInputEventData:data error:error];
}

- (BOOL)putGraphicsFrameTickEventWithSequence:(uint32_t)sequence
                                        nowNs:(uint64_t)nowNs
                                      deltaNs:(uint64_t)deltaNs
                                targetHzMilli:(uint32_t)targetHzMilli
                                        flags:(uint32_t)flags
                                        error:(NSError**)error {
    uint8_t payload[28];
    OrenAVMGFXInputPutU32LE(payload, sequence);
    OrenAVMGFXInputPutU64LE(payload + 4, nowNs);
    OrenAVMGFXInputPutU64LE(payload + 12, deltaNs);
    OrenAVMGFXInputPutU32LE(payload + 20, targetHzMilli);
    OrenAVMGFXInputPutU32LE(payload + 24, flags);
    NSData* data = OrenAVMGFXInputMakeEvent(18, payload, sizeof(payload));
    return [self putGraphicsInputEventData:data error:error];
}

- (BOOL)putGraphicsKeyEventWithKind:(uint8_t)kind keyCode:(uint32_t)keyCode modifiers:(uint32_t)modifiers error:(NSError**)error {
    uint8_t payload[8];
    OrenAVMGFXInputPutU32LE(payload, keyCode);
    OrenAVMGFXInputPutU32LE(payload + 4, modifiers);
    NSData* data = OrenAVMGFXInputMakeEvent(kind, payload, sizeof(payload));
    return [self putGraphicsInputEventData:data error:error];
}

- (BOOL)putGraphicsTextInputString:(NSString*)text error:(NSError**)error {
    NSData* utf8 = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!utf8) {
        return OrenAVMGFXInputSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                      @"GFX text input must be valid UTF-8");
    }
    if (utf8.length > UINT16_MAX - 4u) {
        return OrenAVMGFXInputSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                      @"GFX text input event is too large");
    }
    NSMutableData* payload = [NSMutableData dataWithLength:4u + utf8.length];
    uint8_t* out = (uint8_t*)payload.mutableBytes;
    OrenAVMGFXInputPutU32LE(out, (uint32_t)utf8.length);
    if (utf8.length > 0) memcpy(out + 4, utf8.bytes, utf8.length);
    NSData* data = OrenAVMGFXInputMakeEvent(48, payload.bytes, (uint16_t)payload.length);
    return [self putGraphicsInputEventData:data error:error];
}

- (BOOL)putGraphicsGamepadEventWithControllerID:(uint32_t)controllerID
                                        buttons:(uint32_t)buttons
                                        lxMilli:(int32_t)lxMilli
                                        lyMilli:(int32_t)lyMilli
                                        rxMilli:(int32_t)rxMilli
                                        ryMilli:(int32_t)ryMilli
                                          error:(NSError**)error {
    uint8_t payload[24];
    OrenAVMGFXInputPutU32LE(payload, controllerID);
    OrenAVMGFXInputPutU32LE(payload + 4, buttons);
    OrenAVMGFXInputPutU32LE(payload + 8, (uint32_t)lxMilli);
    OrenAVMGFXInputPutU32LE(payload + 12, (uint32_t)lyMilli);
    OrenAVMGFXInputPutU32LE(payload + 16, (uint32_t)rxMilli);
    OrenAVMGFXInputPutU32LE(payload + 20, (uint32_t)ryMilli);
    NSData* data = OrenAVMGFXInputMakeEvent(64, payload, sizeof(payload));
    return [self putGraphicsInputEventData:data error:error];
}

- (BOOL)putGraphicsMotionEventWithSourceID:(uint32_t)sourceID
                                  sequence:(uint32_t)sequence
                               timestampNs:(uint64_t)timestampNs
                              accelXMilli:(int32_t)accelXMilli
                              accelYMilli:(int32_t)accelYMilli
                              accelZMilli:(int32_t)accelZMilli
                               gyroXMilli:(int32_t)gyroXMilli
                               gyroYMilli:(int32_t)gyroYMilli
                               gyroZMilli:(int32_t)gyroZMilli
                                     error:(NSError**)error {
    uint8_t payload[40];
    OrenAVMGFXInputPutU32LE(payload, sourceID);
    OrenAVMGFXInputPutU32LE(payload + 4, sequence);
    OrenAVMGFXInputPutU64LE(payload + 8, timestampNs);
    OrenAVMGFXInputPutU32LE(payload + 16, (uint32_t)accelXMilli);
    OrenAVMGFXInputPutU32LE(payload + 20, (uint32_t)accelYMilli);
    OrenAVMGFXInputPutU32LE(payload + 24, (uint32_t)accelZMilli);
    OrenAVMGFXInputPutU32LE(payload + 28, (uint32_t)gyroXMilli);
    OrenAVMGFXInputPutU32LE(payload + 32, (uint32_t)gyroYMilli);
    OrenAVMGFXInputPutU32LE(payload + 36, (uint32_t)gyroZMilli);
    NSData* data = OrenAVMGFXInputMakeEvent(96, payload, sizeof(payload));
    return [self putGraphicsInputEventData:data error:error];
}

- (BOOL)putGraphicsFocusEventWithKind:(uint8_t)kind focusID:(uint32_t)focusID flags:(uint32_t)flags error:(NSError**)error {
    uint8_t payload[8];
    OrenAVMGFXInputPutU32LE(payload, focusID);
    OrenAVMGFXInputPutU32LE(payload + 4, flags);
    NSData* data = OrenAVMGFXInputMakeEvent(kind, payload, sizeof(payload));
    return [self putGraphicsInputEventData:data error:error];
}

- (BOOL)putGraphicsCompositionEventWithKind:(uint8_t)kind text:(NSString*)text selectionStart:(uint32_t)selectionStart selectionEnd:(uint32_t)selectionEnd error:(NSError**)error {
    NSData* utf8 = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!utf8) {
        return OrenAVMGFXInputSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                      @"GFX composition event must be valid UTF-8");
    }
    if (utf8.length > UINT16_MAX - 12u) {
        return OrenAVMGFXInputSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                      @"GFX composition event is too large");
    }
    NSMutableData* payload = [NSMutableData dataWithLength:12u + utf8.length];
    uint8_t* out = (uint8_t*)payload.mutableBytes;
    OrenAVMGFXInputPutU32LE(out, (uint32_t)utf8.length);
    OrenAVMGFXInputPutU32LE(out + 4, selectionStart);
    OrenAVMGFXInputPutU32LE(out + 8, selectionEnd);
    if (utf8.length > 0) memcpy(out + 12, utf8.bytes, utf8.length);
    NSData* data = OrenAVMGFXInputMakeEvent(kind, payload.bytes, (uint16_t)payload.length);
    return [self putGraphicsInputEventData:data error:error];
}

@end
