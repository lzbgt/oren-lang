#pragma once

#import <TargetConditionals.h>

#if TARGET_OS_IPHONE

#import <UIKit/UIKit.h>
#include <stdint.h>

BOOL OrenAVMGfxDrawImmediatePrimitive(CGContextRef ctx,
                                      uint8_t opcode,
                                      const uint8_t* payload,
                                      uint16_t payloadLen);

#endif
