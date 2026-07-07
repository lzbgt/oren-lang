#pragma once

#import "OrenAVMKit.h"

#import <TargetConditionals.h>

#if TARGET_OS_IPHONE

#import <UIKit/UIKit.h>

BOOL OrenAVMGFXInputSendPointerEvent(OrenAVMRuntime* runtime,
                                     uint8_t kind,
                                     CGPoint point,
                                     uint32_t pointerID,
                                     NSString* missingRuntimeMessage,
                                     NSError** error);
BOOL OrenAVMGFXInputSendPointerEvents(OrenAVMRuntime* runtime,
                                      uint8_t kind,
                                      NSArray<NSValue*>* points,
                                      NSArray<NSNumber*>* pointerIDs,
                                      NSString* missingRuntimeMessage,
                                      NSString* mismatchMessage,
                                      NSError** error);
uint32_t OrenAVMGFXInputPointerIDForTouch(CFMutableDictionaryRef* touchIDs,
                                          uint32_t* nextTouchID,
                                          UITouch* touch);
void OrenAVMGFXInputSendTouches(OrenAVMRuntime* runtime,
                                UIView* view,
                                CFMutableDictionaryRef* touchIDs,
                                uint32_t* nextTouchID,
                                NSSet<UITouch*>* touches,
                                uint8_t kind,
                                BOOL releaseAfterSend,
                                NSString* missingRuntimeMessage);

#endif
