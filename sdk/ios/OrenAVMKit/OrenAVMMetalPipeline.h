#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

#if TARGET_OS_IPHONE

#import <Metal/Metal.h>

BOOL OrenAVMMetalBuildPipelineStates(id<MTLDevice> device,
                                     MTLPixelFormat pixelFormat,
                                     id<MTLRenderPipelineState>* geometryPipelineOut,
                                     id<MTLRenderPipelineState>* textPipelineOut);

#endif
