#import "OrenAVMMetalText.h"

#if TARGET_OS_IPHONE

#import <dispatch/dispatch.h>

#include <math.h>
#include <stdlib.h>
#include <string.h>

@implementation OrenAVMMetalTextRun
- (void)dealloc {
    free(heapVertices);
}
@end

@implementation OrenAVMMetalTextResource
@end

@interface OrenAVMMetalTextCacheKey ()
@property(nonatomic, copy) NSString* text;
@property(nonatomic) uint32_t rgbaValue;
@property(nonatomic) uint32_t scaleMilli;
@property(nonatomic) NSUInteger cachedHash;
@end

@implementation OrenAVMMetalTextCacheKey

+ (instancetype)keyWithText:(NSString*)text rgba:(const uint8_t*)rgba scaleMilli:(uint32_t)scaleMilli {
    if (!text || !rgba) return nil;
    OrenAVMMetalTextCacheKey* key = [[OrenAVMMetalTextCacheKey alloc] init];
    key.text = text;
    key.rgbaValue = (uint32_t)rgba[0] |
        ((uint32_t)rgba[1] << 8) |
        ((uint32_t)rgba[2] << 16) |
        ((uint32_t)rgba[3] << 24);
    key.scaleMilli = scaleMilli;
    key.cachedHash = text.hash ^ ((NSUInteger)key.rgbaValue * 16777619u) ^ ((NSUInteger)scaleMilli << 1);
    return key;
}

- (id)copyWithZone:(NSZone*)zone {
    (void)zone;
    return self;
}

- (NSUInteger)hash {
    return self.cachedHash;
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[OrenAVMMetalTextCacheKey class]]) return NO;
    OrenAVMMetalTextCacheKey* other = (OrenAVMMetalTextCacheKey*)object;
    return self.rgbaValue == other.rgbaValue &&
        self.scaleMilli == other.scaleMilli &&
        [self.text isEqualToString:other.text];
}

@end

@implementation OrenAVMMetalTextCacheEntry
@end

@implementation OrenAVMMetalTextAtlas
@end

@implementation OrenAVMMetalTextAttributeCache
- (void)dealloc {
    if (_entries) {
        CFRelease(_entries);
        _entries = NULL;
    }
}
@end

static const NSUInteger OrenAVMMetalTextCachePixelLimit = 8u * 1024u * 1024u;
static const NSUInteger OrenAVMMetalTextCacheEntryLimit = 256u;
static const NSUInteger OrenAVMMetalTextAttributeCacheEntryLimit = 256u;
enum {
    OrenAVMMetalTextAtlasSize = 1024u,
    OrenAVMMetalTextAtlasPadding = 1u,
};

static uint32_t OrenAVMMetalTextReadU32LE(const uint8_t* p) {
    return (uint32_t)p[0] |
           ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static const void* OrenAVMMetalTextAttributeKey(uint32_t rgbaValue) {
    return (const void*)(uintptr_t)((uint64_t)rgbaValue + 1ull);
}

static float OrenAVMMetalClipX(float x, float logicalWidth) {
    if (logicalWidth <= 0.0f) return 0.0f;
    return (x / logicalWidth) * 2.0f - 1.0f;
}

static float OrenAVMMetalClipY(float y, float logicalHeight) {
    if (logicalHeight <= 0.0f) return 0.0f;
    return 1.0f - (y / logicalHeight) * 2.0f;
}

static void OrenAVMMetalTouchTextCacheKey(NSMutableArray<OrenAVMMetalTextCacheKey*>* order, OrenAVMMetalTextCacheKey* key) {
    if (!key) return;
    [order removeObject:key];
    [order addObject:key];
}

static void OrenAVMMetalTrimTextCache(NSMutableDictionary<OrenAVMMetalTextCacheKey*, OrenAVMMetalTextCacheEntry*>* cache,
                                      NSMutableArray<OrenAVMMetalTextCacheKey*>* order,
                                      NSUInteger* pixels) {
    if (!pixels) return;
    while ((*pixels > OrenAVMMetalTextCachePixelLimit ||
            order.count > OrenAVMMetalTextCacheEntryLimit) &&
           order.count > 0) {
        OrenAVMMetalTextCacheKey* key = order.firstObject;
        [order removeObjectAtIndex:0];
        OrenAVMMetalTextCacheEntry* entry = cache[key];
        if (entry) {
            *pixels = *pixels > entry.pixelCount ? *pixels - entry.pixelCount : 0;
            [cache removeObjectForKey:key];
        }
    }
}

static OrenAVMMetalTextAtlas* OrenAVMMetalCreateTextAtlas(id<MTLDevice> device) {
    if (!device) return nil;
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                         width:OrenAVMMetalTextAtlasSize
                                                                                        height:OrenAVMMetalTextAtlasSize
                                                                                     mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [device newTextureWithDescriptor:descriptor];
    if (!texture) return nil;
    OrenAVMMetalTextAtlas* atlas = [[OrenAVMMetalTextAtlas alloc] init];
    atlas.texture = texture;
    atlas.width = OrenAVMMetalTextAtlasSize;
    atlas.height = OrenAVMMetalTextAtlasSize;
    return atlas;
}

static BOOL OrenAVMMetalAtlasReserve(OrenAVMMetalTextAtlas* atlas,
                                     NSUInteger pixelWidth,
                                     NSUInteger pixelHeight,
                                     NSUInteger* outX,
                                     NSUInteger* outY) {
    if (!atlas || !atlas.texture || !outX || !outY) return NO;
    NSUInteger paddedWidth = pixelWidth + OrenAVMMetalTextAtlasPadding;
    NSUInteger paddedHeight = pixelHeight + OrenAVMMetalTextAtlasPadding;
    if (paddedWidth > atlas.width || paddedHeight > atlas.height) return NO;
    if (atlas.cursorX + paddedWidth > atlas.width) {
        atlas.cursorX = 0;
        atlas.cursorY += atlas.rowHeight;
        atlas.rowHeight = 0;
    }
    if (atlas.cursorY + paddedHeight > atlas.height) return NO;
    *outX = atlas.cursorX;
    *outY = atlas.cursorY;
    atlas.cursorX += paddedWidth;
    if (paddedHeight > atlas.rowHeight) atlas.rowHeight = paddedHeight;
    return YES;
}

static void OrenAVMMetalClearTextAtlasPadding(id<MTLTexture> texture,
                                              NSUInteger x,
                                              NSUInteger y,
                                              NSUInteger pixelWidth,
                                              NSUInteger pixelHeight) {
    if (!texture || pixelWidth == 0 || pixelHeight == 0) return;
    static const uint8_t zeroAtlasPadding[OrenAVMMetalTextAtlasSize * 4u] = {0};
    if (x + pixelWidth < texture.width) {
        [texture replaceRegion:MTLRegionMake2D(x + pixelWidth, y, OrenAVMMetalTextAtlasPadding, pixelHeight)
                   mipmapLevel:0
                     withBytes:zeroAtlasPadding
                   bytesPerRow:OrenAVMMetalTextAtlasPadding * 4u];
    }
    if (y + pixelHeight < texture.height) {
        NSUInteger bottomWidth = pixelWidth;
        if (x + bottomWidth < texture.width) bottomWidth += OrenAVMMetalTextAtlasPadding;
        [texture replaceRegion:MTLRegionMake2D(x, y + pixelHeight, bottomWidth, OrenAVMMetalTextAtlasPadding)
                   mipmapLevel:0
                     withBytes:zeroAtlasPadding
                   bytesPerRow:bottomWidth * 4u];
    }
}

static NSDictionary<NSAttributedStringKey, id>* OrenAVMMetalTextAttributesForRGBA(
    OrenAVMMetalTextAttributeCache* cache,
    const uint8_t* rgba) {
    if (!rgba) return nil;
    uint32_t rgbaValue = (uint32_t)rgba[0] |
        ((uint32_t)rgba[1] << 8) |
        ((uint32_t)rgba[2] << 16) |
        ((uint32_t)rgba[3] << 24);
    if (cache.lastAttributes && cache.lastRGBA == rgbaValue) return cache.lastAttributes;
    if (cache && !cache.entries) cache.entries = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    const void* key = OrenAVMMetalTextAttributeKey(rgbaValue);
    NSDictionary<NSAttributedStringKey, id>* cached = cache.entries ?
        (__bridge NSDictionary<NSAttributedStringKey, id>*)CFDictionaryGetValue(cache.entries, key) : nil;
    if (cached) {
        cache.lastRGBA = rgbaValue;
        cache.lastAttributes = cached;
        return cached;
    }
    static UIFont* font = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        font = [UIFont systemFontOfSize:14.0];
    });
    UIColor* color = [UIColor colorWithRed:(CGFloat)rgba[0] / 255.0
                                     green:(CGFloat)rgba[1] / 255.0
                                      blue:(CGFloat)rgba[2] / 255.0
                                     alpha:(CGFloat)rgba[3] / 255.0];
    NSDictionary<NSAttributedStringKey, id>* attrs = @{
        NSForegroundColorAttributeName: color,
        NSFontAttributeName: font
    };
    if (cache && cache.entries) {
        if ((NSUInteger)CFDictionaryGetCount(cache.entries) >= OrenAVMMetalTextAttributeCacheEntryLimit) {
            CFDictionaryRemoveAllValues(cache.entries);
        }
        CFDictionarySetValue(cache.entries, key, (__bridge const void*)attrs);
    }
    cache.lastRGBA = rgbaValue;
    cache.lastAttributes = attrs;
    return attrs;
}

void OrenAVMMetalClearTextTextureCache(NSMutableDictionary<OrenAVMMetalTextCacheKey*, OrenAVMMetalTextCacheEntry*>* cache,
                                       NSMutableArray<OrenAVMMetalTextCacheKey*>* order,
                                       NSUInteger* pixels) {
    [cache removeAllObjects];
    [order removeAllObjects];
    if (pixels) *pixels = 0;
}

static OrenAVMMetalTextCacheEntry* OrenAVMMetalTextCacheEntryForText(
    id<MTLDevice> device,
    UIScreen* screen,
    OrenAVMMetalTextAtlas** atlas,
    NSMutableDictionary<OrenAVMMetalTextCacheKey*, OrenAVMMetalTextCacheEntry*>* cache,
    NSMutableArray<OrenAVMMetalTextCacheKey*>* order,
    OrenAVMMetalTextAttributeCache* attributesCache,
    NSUInteger* cachePixels,
    NSString* text,
    const uint8_t* rgba) {
    if (!text || text.length == 0 || !device || !rgba || !cachePixels) return nil;
    CGFloat scale = screen.scale;
    if (scale <= 0.0) scale = UIScreen.mainScreen.scale;
    if (scale <= 0.0) scale = 1.0;
    uint32_t scaleMilli = (uint32_t)llround((double)scale * 1000.0);
    OrenAVMMetalTextCacheKey* cacheKey = [OrenAVMMetalTextCacheKey keyWithText:text rgba:rgba scaleMilli:scaleMilli];
    if (!cacheKey) return nil;
    OrenAVMMetalTextCacheEntry* cached = cache[cacheKey];
    if (cached) {
        OrenAVMMetalTouchTextCacheKey(order, cacheKey);
        return cached;
    }
    NSDictionary<NSAttributedStringKey, id>* attrs = OrenAVMMetalTextAttributesForRGBA(attributesCache, rgba);
    if (!attrs) return nil;
    CGSize textSize = [text sizeWithAttributes:attrs];
    if (textSize.width <= 0.0 || textSize.height <= 0.0) return nil;

    NSUInteger pixelWidth = (NSUInteger)ceil(textSize.width * scale);
    NSUInteger pixelHeight = (NSUInteger)ceil(textSize.height * scale);
    if (pixelWidth == 0 || pixelHeight == 0 || pixelWidth > 4096u || pixelHeight > 4096u) return nil;
    OrenAVMMetalTextCacheEntry* entry = [[OrenAVMMetalTextCacheEntry alloc] init];
    if (!entry) return nil;

    if (pixelWidth > ((NSUInteger)-1) / pixelHeight / 4u) return nil;
    NSUInteger pixelBytes = pixelWidth * pixelHeight * 4u;
    uint8_t* pixels = (uint8_t*)malloc(pixelBytes);
    if (!pixels) return nil;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (!colorSpace) {
        free(pixels);
        return nil;
    }
    CGContextRef ctx = CGBitmapContextCreate(pixels,
                                             pixelWidth,
                                             pixelHeight,
                                             8,
                                             pixelWidth * 4u,
                                             colorSpace,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!ctx) {
        free(pixels);
        return nil;
    }
    CGContextClearRect(ctx, CGRectMake(0.0, 0.0, (CGFloat)pixelWidth, (CGFloat)pixelHeight));
    CGContextScaleCTM(ctx, scale, scale);
    UIGraphicsPushContext(ctx);
    [text drawAtPoint:CGPointZero withAttributes:attrs];
    UIGraphicsPopContext();
    CGContextRelease(ctx);

    entry.logicalSize = textSize;
    entry.pixelCount = pixelWidth * pixelHeight;
    NSUInteger atlasX = 0;
    NSUInteger atlasY = 0;
    BOOL packed = NO;
    if (atlas && pixelWidth + OrenAVMMetalTextAtlasPadding <= OrenAVMMetalTextAtlasSize &&
        pixelHeight + OrenAVMMetalTextAtlasPadding <= OrenAVMMetalTextAtlasSize) {
        if (!*atlas) {
            *atlas = OrenAVMMetalCreateTextAtlas(device);
            packed = OrenAVMMetalAtlasReserve(*atlas, pixelWidth, pixelHeight, &atlasX, &atlasY);
        } else {
            packed = OrenAVMMetalAtlasReserve(*atlas, pixelWidth, pixelHeight, &atlasX, &atlasY);
            if (!packed) {
                OrenAVMMetalClearTextTextureCache(cache, order, cachePixels);
                *atlas = OrenAVMMetalCreateTextAtlas(device);
                packed = OrenAVMMetalAtlasReserve(*atlas, pixelWidth, pixelHeight, &atlasX, &atlasY);
            }
        }
    }
    if (packed && atlas && *atlas && (*atlas).texture) {
        [(*atlas).texture replaceRegion:MTLRegionMake2D(atlasX, atlasY, pixelWidth, pixelHeight)
                            mipmapLevel:0
                              withBytes:pixels
                            bytesPerRow:pixelWidth * 4u];
        OrenAVMMetalClearTextAtlasPadding((*atlas).texture, atlasX, atlasY, pixelWidth, pixelHeight);
        entry.texture = (*atlas).texture;
        entry.u0 = (float)atlasX / (float)(*atlas).width;
        entry.v0 = (float)atlasY / (float)(*atlas).height;
        entry.u1 = (float)(atlasX + pixelWidth) / (float)(*atlas).width;
        entry.v1 = (float)(atlasY + pixelHeight) / (float)(*atlas).height;
    } else {
        MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                             width:pixelWidth
                                                                                            height:pixelHeight
                                                                                         mipmapped:NO];
        descriptor.usage = MTLTextureUsageShaderRead;
        id<MTLTexture> texture = [device newTextureWithDescriptor:descriptor];
        if (!texture) {
            free(pixels);
            return nil;
        }
        [texture replaceRegion:MTLRegionMake2D(0, 0, pixelWidth, pixelHeight)
                   mipmapLevel:0
                     withBytes:pixels
                   bytesPerRow:pixelWidth * 4u];
        entry.texture = texture;
        entry.u0 = 0.0f;
        entry.v0 = 0.0f;
        entry.u1 = 1.0f;
        entry.v1 = 1.0f;
    }
    free(pixels);
    cache[cacheKey] = entry;
    *cachePixels += entry.pixelCount;
    OrenAVMMetalTouchTextCacheKey(order, cacheKey);
    OrenAVMMetalTrimTextCache(cache, order, cachePixels);
    return entry;
}

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
                                  float v1) {
    if (!out) return;
    out[0] = (OrenAVMMetalTextVertex){OrenAVMMetalClipX(x, logicalWidth),
                                      OrenAVMMetalClipY(y, logicalHeight),
                                      u0,
                                      v0};
    out[1] = (OrenAVMMetalTextVertex){OrenAVMMetalClipX(x + w, logicalWidth),
                                      OrenAVMMetalClipY(y, logicalHeight),
                                      u1,
                                      v0};
    out[2] = (OrenAVMMetalTextVertex){OrenAVMMetalClipX(x, logicalWidth),
                                      OrenAVMMetalClipY(y + h, logicalHeight),
                                      u0,
                                      v1};
    out[3] = (OrenAVMMetalTextVertex){OrenAVMMetalClipX(x + w, logicalWidth),
                                      OrenAVMMetalClipY(y, logicalHeight),
                                      u1,
                                      v0};
    out[4] = (OrenAVMMetalTextVertex){OrenAVMMetalClipX(x + w, logicalWidth),
                                      OrenAVMMetalClipY(y + h, logicalHeight),
                                      u1,
                                      v1};
    out[5] = (OrenAVMMetalTextVertex){OrenAVMMetalClipX(x, logicalWidth),
                                      OrenAVMMetalClipY(y + h, logicalHeight),
                                      u0,
                                      v1};
}

OrenAVMMetalTextRun* OrenAVMMetalCreateTextRun(id<MTLDevice> device,
                                               UIScreen* screen,
                                               OrenAVMMetalTextAtlas** atlas,
                                               NSMutableDictionary<OrenAVMMetalTextCacheKey*, OrenAVMMetalTextCacheEntry*>* cache,
                                               NSMutableArray<OrenAVMMetalTextCacheKey*>* order,
                                               OrenAVMMetalTextAttributeCache* attributesCache,
                                               NSUInteger* cachePixels,
                                               NSString* text,
                                               float x,
                                               float y,
                                               const uint8_t* rgba,
                                               float opacity,
                                               float logicalWidth,
                                               float logicalHeight) {
    OrenAVMMetalTextCacheEntry* entry = OrenAVMMetalTextCacheEntryForText(device, screen, atlas, cache, order, attributesCache, cachePixels, text, rgba);
    if (!entry) return nil;
    OrenAVMMetalTextRun* run = [[OrenAVMMetalTextRun alloc] init];
    if (!run) return nil;
    run.texture = entry.texture;
    OrenAVMMetalWriteTextureQuad(run->inlineVertices,
                                 x,
                                 y,
                                 (float)entry.logicalSize.width,
                                 (float)entry.logicalSize.height,
                                 logicalWidth,
                                 logicalHeight,
                                 entry.u0,
                                 entry.v0,
                                 entry.u1,
                                 entry.v1);
    run.inlineVertexCount = 6u;
    run.opacity = opacity;
    return run;
}

static BOOL OrenAVMMetalTextRunReserveHeapVertices(OrenAVMMetalTextRun* run, NSUInteger neededCount) {
    if (!run) return NO;
    if (neededCount <= run->heapVertexCapacity) return YES;
    if (neededCount > NSUIntegerMax / sizeof(OrenAVMMetalTextVertex)) return NO;
    NSUInteger newCapacity = run->heapVertexCapacity > 0 ? run->heapVertexCapacity : 8u;
    while (newCapacity < neededCount) {
        if (newCapacity > NSUIntegerMax / 2u) {
            newCapacity = neededCount;
            break;
        }
        newCapacity *= 2u;
    }
    if (newCapacity > NSUIntegerMax / sizeof(OrenAVMMetalTextVertex)) newCapacity = neededCount;
    OrenAVMMetalTextVertex* grown = (OrenAVMMetalTextVertex*)realloc(run->heapVertices, newCapacity * sizeof(OrenAVMMetalTextVertex));
    if (!grown) return NO;
    run->heapVertices = grown;
    run->heapVertexCapacity = newCapacity;
    return YES;
}

static BOOL OrenAVMMetalTextRunAllocateExactHeapVertices(OrenAVMMetalTextRun* run, NSUInteger vertexCount) {
    if (!run || vertexCount == 0 || run->heapVertices || run->heapVertexCapacity != 0) return NO;
    if (vertexCount > NSUIntegerMax / sizeof(OrenAVMMetalTextVertex)) return NO;
    run->heapVertices = (OrenAVMMetalTextVertex*)malloc(vertexCount * sizeof(OrenAVMMetalTextVertex));
    if (!run->heapVertices) return NO;
    run->heapVertexCapacity = vertexCount;
    return YES;
}

static BOOL OrenAVMMetalTextRunAppendVertices(OrenAVMMetalTextRun* run,
                                              const OrenAVMMetalTextVertex* vertices,
                                              NSUInteger vertexCount) {
    if (!run) return NO;
    if (!vertices || vertexCount == 0) return YES;
    if (run->heapVertexCount > NSUIntegerMax - vertexCount) return NO;
    NSUInteger neededCount = run->heapVertexCount + vertexCount;
    if (!OrenAVMMetalTextRunReserveHeapVertices(run, neededCount)) return NO;
    memcpy(run->heapVertices + run->heapVertexCount, vertices, vertexCount * sizeof(OrenAVMMetalTextVertex));
    run->heapVertexCount = neededCount;
    return YES;
}

OrenAVMMetalTextRun* OrenAVMMetalCreateTextBatchRun(id<MTLDevice> device,
                                                    UIScreen* screen,
                                                    OrenAVMMetalTextAtlas** atlas,
                                                    NSMutableDictionary<OrenAVMMetalTextCacheKey*, OrenAVMMetalTextCacheEntry*>* cache,
                                                    NSMutableArray<OrenAVMMetalTextCacheKey*>* order,
                                                    OrenAVMMetalTextAttributeCache* attributesCache,
                                                    NSUInteger* cachePixels,
                                                    NSString* text,
                                                    const uint8_t* positions,
                                                    uint32_t positionCount,
                                                    float translateX,
                                                    float translateY,
                                                    const uint8_t* rgba,
                                                    float opacity,
                                                    float logicalWidth,
                                                    float logicalHeight) {
    if (!positions || positionCount == 0) return nil;
    OrenAVMMetalTextCacheEntry* entry = OrenAVMMetalTextCacheEntryForText(device, screen, atlas, cache, order, attributesCache, cachePixels, text, rgba);
    if (!entry) return nil;
    if (positionCount == 1) {
        const uint8_t* p = positions;
        OrenAVMMetalTextRun* run = [[OrenAVMMetalTextRun alloc] init];
        if (!run) return nil;
        run.texture = entry.texture;
        OrenAVMMetalWriteTextureQuad(run->inlineVertices,
                                     (float)OrenAVMMetalTextReadU32LE(p) + translateX,
                                     (float)OrenAVMMetalTextReadU32LE(p + 4) + translateY,
                                     (float)entry.logicalSize.width,
                                     (float)entry.logicalSize.height,
                                     logicalWidth,
                                     logicalHeight,
                                     entry.u0,
                                     entry.v0,
                                     entry.u1,
                                     entry.v1);
        run.inlineVertexCount = 6u;
        run.opacity = opacity;
        return run;
    }
    NSUInteger vertexCount = (NSUInteger)positionCount * 6u;
    if (positionCount != 0 && vertexCount / 6u != (NSUInteger)positionCount) return nil;
    OrenAVMMetalTextRun* run = [[OrenAVMMetalTextRun alloc] init];
    if (!run) return nil;
    run.texture = entry.texture;
    run.opacity = opacity;
    if (!OrenAVMMetalTextRunAllocateExactHeapVertices(run, vertexCount)) return nil;
    for (uint32_t i = 0; i < positionCount; i++) {
        const uint8_t* p = positions + ((size_t)i * 8u);
        OrenAVMMetalWriteTextureQuad(run->heapVertices + run->heapVertexCount,
                                     (float)OrenAVMMetalTextReadU32LE(p) + translateX,
                                     (float)OrenAVMMetalTextReadU32LE(p + 4) + translateY,
                                     (float)entry.logicalSize.width,
                                     (float)entry.logicalSize.height,
                                     logicalWidth,
                                     logicalHeight,
                                     entry.u0,
                                     entry.v0,
                                     entry.u1,
                                     entry.v1);
        run->heapVertexCount += 6u;
    }
    return run;
}

const void* OrenAVMMetalTextRunVertexBytes(OrenAVMMetalTextRun* run) {
    if (!run) return NULL;
    if (run->heapVertexCount != 0) return run->heapVertices;
    return run.inlineVertexCount == 0 ? NULL : run->inlineVertices;
}

NSUInteger OrenAVMMetalTextRunVertexBytesLength(OrenAVMMetalTextRun* run) {
    if (!run) return 0;
    if (run->heapVertexCount != 0) return run->heapVertexCount * sizeof(OrenAVMMetalTextVertex);
    return run.inlineVertexCount * sizeof(OrenAVMMetalTextVertex);
}

NSUInteger OrenAVMMetalTextRunVertexCount(OrenAVMMetalTextRun* run) {
    return OrenAVMMetalTextRunVertexBytesLength(run) / sizeof(OrenAVMMetalTextVertex);
}

static BOOL OrenAVMMetalTextScissorEqual(OrenAVMMetalTextRun* a, OrenAVMMetalTextRun* b) {
    if (a.hasScissor != b.hasScissor) return NO;
    if (!a.hasScissor) return YES;
    return a.scissor.x == b.scissor.x &&
           a.scissor.y == b.scissor.y &&
           a.scissor.width == b.scissor.width &&
           a.scissor.height == b.scissor.height;
}

static BOOL OrenAVMMetalEnsureHeapTextVerticesForCoalescing(OrenAVMMetalTextRun* pending) {
    if (!pending) return NO;
    if (pending->heapVertexCount != 0) return YES;
    if (pending.inlineVertexCount == 0) return YES;
    if (!OrenAVMMetalTextRunAppendVertices(pending, pending->inlineVertices, pending.inlineVertexCount)) return NO;
    pending.inlineVertexCount = 0;
    return YES;
}

NSArray<OrenAVMMetalTextRun*>* OrenAVMMetalCoalesceTextRuns(NSArray<OrenAVMMetalTextRun*>* runs) {
    if (runs.count < 2) return runs ?: @[];
    NSMutableArray<OrenAVMMetalTextRun*>* out = [NSMutableArray arrayWithCapacity:runs.count];
    if (!out) return runs;
    OrenAVMMetalTextRun* pending = nil;
    for (OrenAVMMetalTextRun* run in runs) {
        NSUInteger vertexBytes = OrenAVMMetalTextRunVertexBytesLength(run);
        const void* vertexData = OrenAVMMetalTextRunVertexBytes(run);
        if (!run.texture || vertexBytes == 0 || !vertexData) continue;
        BOOL same = pending &&
            pending.texture == run.texture &&
            pending.opacity == run.opacity &&
            OrenAVMMetalTextScissorEqual(pending, run);
        if (!same) {
            pending = run;
            [out addObject:pending];
            continue;
        }
        if (!OrenAVMMetalEnsureHeapTextVerticesForCoalescing(pending) ||
            !OrenAVMMetalTextRunAppendVertices(pending,
                                               (const OrenAVMMetalTextVertex*)vertexData,
                                               vertexBytes / sizeof(OrenAVMMetalTextVertex))) {
            pending = run;
            [out addObject:pending];
        }
    }
    return out;
}

#endif
