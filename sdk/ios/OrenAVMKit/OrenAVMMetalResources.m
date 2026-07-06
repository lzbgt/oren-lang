#import "OrenAVMMetalResources.h"

#if TARGET_OS_IPHONE

#include <stdlib.h>
#include <string.h>

@implementation OrenAVMMetalVertexRun
- (void)dealloc {
    free(_vertices);
}
@end

@implementation OrenAVMMetalImageRun
@end

@implementation OrenAVMMetalImageResource
@end

@implementation OrenAVMMetalMesh2DResource
- (void)dealloc {
    free(_triangles);
}
@end

@implementation OrenAVMMetalMesh3DResource
- (void)dealloc {
    free(_triangles);
    free(_vertices);
    free(_indices);
}
@end

@implementation OrenAVMMetalModelResource
@end

uint8_t* OrenAVMMetalCopyPayloadBytes(const uint8_t* src, NSUInteger len) {
    if (len == 0) return NULL;
    uint8_t* out = (uint8_t*)malloc(len);
    if (!out) return NULL;
    memcpy(out, src, len);
    return out;
}

#endif
