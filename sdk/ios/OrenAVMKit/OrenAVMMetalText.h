#import <TargetConditionals.h>

#if TARGET_OS_IPHONE

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <UIKit/UIKit.h>

typedef struct {
    float x;
    float y;
    float u;
    float v;
} OrenAVMMetalTextVertex;

@interface OrenAVMMetalTextRun : NSObject {
@public
    OrenAVMMetalTextVertex inlineVertices[6];
    OrenAVMMetalTextVertex* heapVertices;
    NSUInteger heapVertexCount;
    NSUInteger heapVertexCapacity;
}
@property(nonatomic, strong) id<MTLTexture> texture;
@property(nonatomic) NSUInteger inlineVertexCount;
@property(nonatomic) BOOL hasScissor;
@property(nonatomic) MTLScissorRect scissor;
@property(nonatomic) float opacity;
@end

@interface OrenAVMMetalTextResource : NSObject
@property(nonatomic, copy) NSString* text;
@property(nonatomic) uint32_t rgbaValue;
@end

@interface OrenAVMMetalTextCacheKey : NSObject <NSCopying>
@end

@interface OrenAVMMetalTextCacheEntry : NSObject
@property(nonatomic, strong) id<MTLTexture> texture;
@property(nonatomic) CGSize logicalSize;
@property(nonatomic) NSUInteger pixelCount;
@property(nonatomic) float u0;
@property(nonatomic) float v0;
@property(nonatomic) float u1;
@property(nonatomic) float v1;
@end

@interface OrenAVMMetalTextAtlas : NSObject
@property(nonatomic, strong) id<MTLTexture> texture;
@property(nonatomic) NSUInteger width;
@property(nonatomic) NSUInteger height;
@property(nonatomic) NSUInteger cursorX;
@property(nonatomic) NSUInteger cursorY;
@property(nonatomic) NSUInteger rowHeight;
@end

@interface OrenAVMMetalTextAttributeCache : NSObject
@property(nonatomic) CFMutableDictionaryRef entries;
@property(nonatomic) uint32_t lastRGBA;
@property(nonatomic, strong) NSDictionary<NSAttributedStringKey, id>* lastAttributes;
@end

void OrenAVMMetalClearTextTextureCache(NSMutableDictionary<OrenAVMMetalTextCacheKey*, OrenAVMMetalTextCacheEntry*>* cache,
                                       NSMutableArray<OrenAVMMetalTextCacheKey*>* order,
                                       NSUInteger* pixels);

void OrenAVMMetalWriteTextureQuad(OrenAVMMetalTextVertex* out,
                                  float x,
                                  float y,
                                  float w,
                                  float h,
                                  float logicalWidth,
                                  float logicalHeight,
                                  float u0,
                                  float v0,
                                  float u1,
                                  float v1);

OrenAVMMetalTextRun* OrenAVMMetalCreateTextRun(id<MTLDevice> device,
                                               UIScreen* screen,
                                               OrenAVMMetalTextAtlas** atlas,
                                               NSMutableDictionary<OrenAVMMetalTextCacheKey*, OrenAVMMetalTextCacheEntry*>* __strong * cache,
                                               NSMutableArray<OrenAVMMetalTextCacheKey*>* __strong * order,
                                               OrenAVMMetalTextAttributeCache* __strong * attributesCache,
                                               NSUInteger* cachePixels,
                                               NSString* text,
                                               float x,
                                               float y,
                                               const uint8_t* rgba,
                                               float opacity,
                                               float logicalWidth,
                                               float logicalHeight);

OrenAVMMetalTextRun* OrenAVMMetalCreateTextBatchRun(id<MTLDevice> device,
                                                    UIScreen* screen,
                                                    OrenAVMMetalTextAtlas** atlas,
                                                    NSMutableDictionary<OrenAVMMetalTextCacheKey*, OrenAVMMetalTextCacheEntry*>* __strong * cache,
                                                    NSMutableArray<OrenAVMMetalTextCacheKey*>* __strong * order,
                                                    OrenAVMMetalTextAttributeCache* __strong * attributesCache,
                                                    NSUInteger* cachePixels,
                                                    NSString* text,
                                                    const uint8_t* positions,
                                                    uint32_t positionCount,
                                                    float translateX,
                                                    float translateY,
                                                    const uint8_t* rgba,
                                                    float opacity,
                                                    float logicalWidth,
                                                    float logicalHeight);

NSArray<OrenAVMMetalTextRun*>* OrenAVMMetalCoalesceTextRuns(NSArray<OrenAVMMetalTextRun*>* runs);
const void* OrenAVMMetalTextRunVertexBytes(OrenAVMMetalTextRun* run);
NSUInteger OrenAVMMetalTextRunVertexBytesLength(OrenAVMMetalTextRun* run);
NSUInteger OrenAVMMetalTextRunVertexCount(OrenAVMMetalTextRun* run);

#endif
