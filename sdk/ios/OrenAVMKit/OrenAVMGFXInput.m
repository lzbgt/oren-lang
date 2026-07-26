#import "OrenAVMGFXInput.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

@interface OrenAVMRuntime (GFXInputRaw)
- (BOOL)orenPutGraphicsInputEventBytes:(const void*)bytes length:(NSUInteger)length error:(NSError**)error;
@end

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

static void OrenAVMGFXInputWriteEvent(uint8_t* buf,
                                      uint8_t opcode,
                                      const uint8_t* prefix,
                                      uint16_t prefixLen,
                                      const void* suffix,
                                      uint16_t suffixLen) {
    uint16_t payloadLen = (uint16_t)(prefixLen + suffixLen);
    buf[0] = 'O'; buf[1] = 'G'; buf[2] = 'E'; buf[3] = '0';
    buf[4] = 0; buf[5] = 0; buf[6] = 0; buf[7] = 0;
    buf[8] = opcode; buf[9] = 0;
    buf[10] = (uint8_t)(payloadLen & 255u);
    buf[11] = (uint8_t)((payloadLen >> 8) & 255u);
    if (prefixLen > 0 && prefix) memcpy(buf + 12, prefix, prefixLen);
    if (suffixLen > 0 && suffix) memcpy(buf + 12 + prefixLen, suffix, suffixLen);
}

static BOOL OrenAVMGFXInputSDKError(NSError** error, NSInteger code, NSString* message) {
    if (error) {
        *error = [NSError errorWithDomain:OrenAVMKitErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: message ?: @"OrenAVMKit error"}];
    }
    return NO;
}

#if TARGET_OS_IPHONE

BOOL OrenAVMGFXInputSendPointerEvent(OrenAVMRuntime* runtime,
                                     uint8_t kind,
                                     CGPoint point,
                                     uint32_t pointerID,
                                     NSString* missingRuntimeMessage,
                                     NSError** error) {
    if (!runtime) {
        return OrenAVMGFXInputSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                      missingRuntimeMessage ?: @"graphics view has no AVM runtime");
    }
    return [runtime putGraphicsPointerEventWithKind:kind
                                                  x:(int32_t)llround((double)point.x)
                                                  y:(int32_t)llround((double)point.y)
                                          pointerId:pointerID
                                              error:error];
}

BOOL OrenAVMGFXInputSendPointerEvents(OrenAVMRuntime* runtime,
                                      uint8_t kind,
                                      NSArray<NSValue*>* points,
                                      NSArray<NSNumber*>* pointerIDs,
                                      NSString* missingRuntimeMessage,
                                      NSString* mismatchMessage,
                                      NSError** error) {
    if (points.count != pointerIDs.count) {
        return OrenAVMGFXInputSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                      mismatchMessage ?: @"graphics pointer batch point/id count mismatch");
    }
    for (NSUInteger i = 0; i < points.count; i++) {
        if (!OrenAVMGFXInputSendPointerEvent(runtime,
                                            kind,
                                            points[i].CGPointValue,
                                            pointerIDs[i].unsignedIntValue,
                                            missingRuntimeMessage,
                                            error)) {
            return NO;
        }
    }
    return YES;
}

uint32_t OrenAVMGFXInputPointerIDForTouch(CFMutableDictionaryRef* touchIDs,
                                          uint32_t* nextTouchID,
                                          UITouch* touch) {
    const void* stored = NULL;
    if (touchIDs && *touchIDs && CFDictionaryGetValueIfPresent(*touchIDs, (__bridge const void*)touch, &stored)) {
        return (uint32_t)(uintptr_t)stored;
    }
    uint32_t pointerID = (nextTouchID && *nextTouchID != 0) ? *nextTouchID : 1u;
    if (nextTouchID) {
        *nextTouchID = pointerID + 1u;
        if (*nextTouchID == 0) *nextTouchID = 1u;
    }
    if (touchIDs && !*touchIDs) *touchIDs = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    if (touchIDs && *touchIDs) {
        CFDictionarySetValue(*touchIDs, (__bridge const void*)touch, (const void*)(uintptr_t)pointerID);
    }
    return pointerID;
}

void OrenAVMGFXInputSendTouches(OrenAVMRuntime* runtime,
                                UIView* view,
                                CFMutableDictionaryRef* touchIDs,
                                uint32_t* nextTouchID,
                                NSSet<UITouch*>* touches,
                                uint8_t kind,
                                BOOL releaseAfterSend,
                                NSString* missingRuntimeMessage) {
    for (UITouch* touch in touches) {
        CGPoint p = [touch locationInView:view];
        uint32_t pointerID = OrenAVMGFXInputPointerIDForTouch(touchIDs, nextTouchID, touch);
        NSError* error = nil;
        (void)OrenAVMGFXInputSendPointerEvent(runtime, kind, p, pointerID, missingRuntimeMessage, &error);
        if (releaseAfterSend && touchIDs && *touchIDs) {
            CFDictionaryRemoveValue(*touchIDs, (__bridge const void*)touch);
        }
    }
}

#endif

static BOOL OrenAVMGFXInputPutEventParts(OrenAVMRuntime* runtime,
                                         uint8_t opcode,
                                         const uint8_t* prefix,
                                         uint16_t prefixLen,
                                         const void* suffix,
                                         uint16_t suffixLen,
                                         NSError** error) {
    enum { stackCap = 12 + 256 };
    if ((uint32_t)prefixLen + (uint32_t)suffixLen > UINT16_MAX) {
        return OrenAVMGFXInputSDKError(error, AVM_EMBED_ERR_INVALID_ARG, @"GFX input event is too large");
    }
    uint16_t payloadLen = (uint16_t)(prefixLen + suffixLen);
    NSUInteger totalLen = (NSUInteger)12u + (NSUInteger)payloadLen;
    if (totalLen <= stackCap) {
        uint8_t stackEvent[stackCap];
        OrenAVMGFXInputWriteEvent(stackEvent, opcode, prefix, prefixLen, suffix, suffixLen);
        return [runtime orenPutGraphicsInputEventBytes:stackEvent length:totalLen error:error];
    }
    uint8_t* event = (uint8_t*)malloc(totalLen);
    if (!event) return OrenAVMGFXInputSDKError(error, AVM_EMBED_ERR_VM, @"failed to allocate GFX input event");
    OrenAVMGFXInputWriteEvent(event, opcode, prefix, prefixLen, suffix, suffixLen);
    BOOL ok = [runtime orenPutGraphicsInputEventBytes:event length:totalLen error:error];
    free(event);
    return ok;
}

static BOOL OrenAVMGFXInputPutEvent(OrenAVMRuntime* runtime, uint8_t opcode, const uint8_t* payload, uint16_t payloadLen, NSError** error) {
    return OrenAVMGFXInputPutEventParts(runtime, opcode, payload, payloadLen, NULL, 0, error);
}

static BOOL OrenAVMGFXInputWriteUTF8(NSString* text, uint8_t* dst, NSUInteger expectedLen) {
    if (expectedLen == 0) return text.length == 0;
    NSUInteger usedLen = 0;
    NSRange remaining = NSMakeRange(0, 0);
    BOOL ok = [text getBytes:dst
                   maxLength:expectedLen
                  usedLength:&usedLen
                    encoding:NSUTF8StringEncoding
                     options:0
                       range:NSMakeRange(0, text.length)
              remainingRange:&remaining];
    return ok && usedLen == expectedLen && remaining.length == 0;
}

static BOOL OrenAVMGFXInputPutUTF8EventParts(OrenAVMRuntime* runtime,
                                             uint8_t opcode,
                                             const uint8_t* prefix,
                                             uint16_t prefixLen,
                                             NSString* text,
                                             NSUInteger utf8Len,
                                             NSString* invalidMessage,
                                             NSError** error) {
    if (!text) return OrenAVMGFXInputSDKError(error, AVM_EMBED_ERR_INVALID_ARG, invalidMessage);
    enum { stackCap = 12 + 256 };
    if (utf8Len > (NSUInteger)(UINT16_MAX - prefixLen)) {
        return OrenAVMGFXInputSDKError(error, AVM_EMBED_ERR_INVALID_ARG, @"GFX input event is too large");
    }
    uint16_t suffixLen = (uint16_t)utf8Len;
    uint16_t payloadLen = (uint16_t)(prefixLen + suffixLen);
    NSUInteger totalLen = (NSUInteger)12u + (NSUInteger)payloadLen;
    if (totalLen <= stackCap) {
        uint8_t stackEvent[stackCap];
        OrenAVMGFXInputWriteEvent(stackEvent, opcode, prefix, prefixLen, NULL, suffixLen);
        if (!OrenAVMGFXInputWriteUTF8(text, stackEvent + 12 + prefixLen, utf8Len)) {
            return OrenAVMGFXInputSDKError(error, AVM_EMBED_ERR_INVALID_ARG, invalidMessage);
        }
        return [runtime orenPutGraphicsInputEventBytes:stackEvent length:totalLen error:error];
    }
    uint8_t* event = (uint8_t*)malloc(totalLen);
    if (!event) return OrenAVMGFXInputSDKError(error, AVM_EMBED_ERR_VM, @"failed to allocate GFX input event");
    OrenAVMGFXInputWriteEvent(event, opcode, prefix, prefixLen, NULL, suffixLen);
    if (!OrenAVMGFXInputWriteUTF8(text, event + 12 + prefixLen, utf8Len)) {
        free(event);
        return OrenAVMGFXInputSDKError(error, AVM_EMBED_ERR_INVALID_ARG, invalidMessage);
    }
    BOOL ok = [runtime orenPutGraphicsInputEventBytes:event length:totalLen error:error];
    free(event);
    return ok;
}

@implementation OrenAVMRuntime (GFXInput)

- (BOOL)putGraphicsPointerEventWithKind:(uint8_t)kind x:(int32_t)x y:(int32_t)y pointerId:(uint32_t)pointerId error:(NSError**)error {
    uint8_t payload[12];
    OrenAVMGFXInputPutU32LE(payload, (uint32_t)x);
    OrenAVMGFXInputPutU32LE(payload + 4, (uint32_t)y);
    OrenAVMGFXInputPutU32LE(payload + 8, pointerId);
    return OrenAVMGFXInputPutEvent(self, kind, payload, sizeof(payload), error);
}

- (BOOL)putGraphicsResizeEventWithWidth:(uint32_t)width height:(uint32_t)height scaleMilli:(uint32_t)scaleMilli error:(NSError**)error {
    uint8_t payload[12];
    OrenAVMGFXInputPutU32LE(payload, width);
    OrenAVMGFXInputPutU32LE(payload + 4, height);
    OrenAVMGFXInputPutU32LE(payload + 8, scaleMilli);
    return OrenAVMGFXInputPutEvent(self, 16, payload, sizeof(payload), error);
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
    return OrenAVMGFXInputPutEvent(self, 17, payload, sizeof(payload), error);
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
    return OrenAVMGFXInputPutEvent(self, 18, payload, sizeof(payload), error);
}

- (BOOL)putGraphicsKeyEventWithKind:(uint8_t)kind keyCode:(uint32_t)keyCode modifiers:(uint32_t)modifiers error:(NSError**)error {
    uint8_t payload[8];
    OrenAVMGFXInputPutU32LE(payload, keyCode);
    OrenAVMGFXInputPutU32LE(payload + 4, modifiers);
    return OrenAVMGFXInputPutEvent(self, kind, payload, sizeof(payload), error);
}

- (BOOL)putGraphicsTextInputString:(NSString*)text error:(NSError**)error {
    if (!text) return OrenAVMGFXInputSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                             @"GFX text input must be valid UTF-8");
    NSUInteger utf8Len = [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    if (utf8Len > UINT16_MAX - 4u) return OrenAVMGFXInputSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                                                  @"GFX text input event is too large");
    uint8_t prefix[4];
    OrenAVMGFXInputPutU32LE(prefix, (uint32_t)utf8Len);
    return OrenAVMGFXInputPutUTF8EventParts(self, 48, prefix, sizeof(prefix), text,
                                            utf8Len,
                                            @"GFX text input must be valid UTF-8",
                                            error);
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
    return OrenAVMGFXInputPutEvent(self, 64, payload, sizeof(payload), error);
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
    return OrenAVMGFXInputPutEvent(self, 96, payload, sizeof(payload), error);
}

- (BOOL)putGraphicsFocusEventWithKind:(uint8_t)kind focusID:(uint32_t)focusID flags:(uint32_t)flags error:(NSError**)error {
    uint8_t payload[8];
    OrenAVMGFXInputPutU32LE(payload, focusID);
    OrenAVMGFXInputPutU32LE(payload + 4, flags);
    return OrenAVMGFXInputPutEvent(self, kind, payload, sizeof(payload), error);
}

- (BOOL)putGraphicsCompositionEventWithKind:(uint8_t)kind text:(NSString*)text selectionStart:(uint32_t)selectionStart selectionEnd:(uint32_t)selectionEnd error:(NSError**)error {
    if (!text) return OrenAVMGFXInputSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                             @"GFX composition event must be valid UTF-8");
    NSUInteger utf8Len = [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    if (utf8Len > UINT16_MAX - 12u) return OrenAVMGFXInputSDKError(error, AVM_EMBED_ERR_INVALID_ARG,
                                                                   @"GFX composition event is too large");
    uint8_t prefix[12];
    OrenAVMGFXInputPutU32LE(prefix, (uint32_t)utf8Len);
    OrenAVMGFXInputPutU32LE(prefix + 4, selectionStart);
    OrenAVMGFXInputPutU32LE(prefix + 8, selectionEnd);
    return OrenAVMGFXInputPutUTF8EventParts(self, kind, prefix, sizeof(prefix), text,
                                            utf8Len,
                                            @"GFX composition event must be valid UTF-8",
                                            error);
}

@end
