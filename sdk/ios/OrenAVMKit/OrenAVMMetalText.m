#import "OrenAVMMetalText.h"

#if TARGET_OS_IPHONE

#include <math.h>

@implementation OrenAVMMetalTextRun
@end

@implementation OrenAVMMetalTextResource
@end

@implementation OrenAVMMetalTextCacheEntry
@end

@implementation OrenAVMMetalTextAtlas
@end

static const NSUInteger OrenAVMMetalTextCachePixelLimit = 8u * 1024u * 1024u;
static const NSUInteger OrenAVMMetalTextCacheEntryLimit = 256u;
static const NSUInteger OrenAVMMetalTextAtlasSize = 1024u;
static const NSUInteger OrenAVMMetalTextAtlasPadding = 1u;

static uint32_t OrenAVMMetalTextReadU32LE(const uint8_t* p) {
    return (uint32_t)p[0] |
           ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static float OrenAVMMetalClipX(float x, float logicalWidth) {
    if (logicalWidth <= 0.0f) return 0.0f;
    return (x / logicalWidth) * 2.0f - 1.0f;
}

static float OrenAVMMetalClipY(float y, float logicalHeight) {
    if (logicalHeight <= 0.0f) return 0.0f;
    return 1.0f - (y / logicalHeight) * 2.0f;
}

static NSString* OrenAVMMetalTextCacheKey(NSString* text, const uint8_t* rgba, uint32_t scaleMilli) {
    return [NSString stringWithFormat:@"%u:%u:%u:%u:%u:%@",
            scaleMilli,
            (unsigned)rgba[0],
            (unsigned)rgba[1],
            (unsigned)rgba[2],
            (unsigned)rgba[3],
            text ?: @""];
}

static void OrenAVMMetalTouchTextCacheKey(NSMutableArray<NSString*>* order, NSString* key) {
    if (!key) return;
    [order removeObject:key];
    [order addObject:key];
}

static void OrenAVMMetalTrimTextCache(NSMutableDictionary<NSString*, OrenAVMMetalTextCacheEntry*>* cache,
                                      NSMutableArray<NSString*>* order,
                                      NSUInteger* pixels) {
    if (!pixels) return;
    while ((*pixels > OrenAVMMetalTextCachePixelLimit ||
            order.count > OrenAVMMetalTextCacheEntryLimit) &&
           order.count > 0) {
        NSString* key = order.firstObject;
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
    NSMutableData* zero = [NSMutableData dataWithLength:OrenAVMMetalTextAtlasSize * OrenAVMMetalTextAtlasSize * 4u];
    [texture replaceRegion:MTLRegionMake2D(0, 0, OrenAVMMetalTextAtlasSize, OrenAVMMetalTextAtlasSize)
               mipmapLevel:0
                 withBytes:zero.bytes
               bytesPerRow:OrenAVMMetalTextAtlasSize * 4u];
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

void OrenAVMMetalClearTextTextureCache(NSMutableDictionary<NSString*, OrenAVMMetalTextCacheEntry*>* cache,
                                       NSMutableArray<NSString*>* order,
                                       NSUInteger* pixels) {
    [cache removeAllObjects];
    [order removeAllObjects];
    if (pixels) *pixels = 0;
}

static OrenAVMMetalTextCacheEntry* OrenAVMMetalTextCacheEntryForText(
    id<MTLDevice> device,
    UIScreen* screen,
    OrenAVMMetalTextAtlas** atlas,
    NSMutableDictionary<NSString*, OrenAVMMetalTextCacheEntry*>* cache,
    NSMutableArray<NSString*>* order,
    NSUInteger* cachePixels,
    NSString* text,
    const uint8_t* rgba) {
    if (!text || text.length == 0 || !device || !rgba || !cachePixels) return nil;
    UIFont* font = [UIFont systemFontOfSize:14.0];
    UIColor* color = [UIColor colorWithRed:(CGFloat)rgba[0] / 255.0
                                     green:(CGFloat)rgba[1] / 255.0
                                      blue:(CGFloat)rgba[2] / 255.0
                                     alpha:(CGFloat)rgba[3] / 255.0];
    NSDictionary<NSAttributedStringKey, id>* attrs = @{
        NSForegroundColorAttributeName: color,
        NSFontAttributeName: font
    };
    CGSize textSize = [text sizeWithAttributes:attrs];
    if (textSize.width <= 0.0 || textSize.height <= 0.0) return nil;
    CGFloat scale = screen.scale;
    if (scale <= 0.0) scale = UIScreen.mainScreen.scale;
    if (scale <= 0.0) scale = 1.0;
    uint32_t scaleMilli = (uint32_t)llround((double)scale * 1000.0);
    NSString* cacheKey = OrenAVMMetalTextCacheKey(text, rgba, scaleMilli);
    OrenAVMMetalTextCacheEntry* cached = cache[cacheKey];
    if (cached) {
        OrenAVMMetalTouchTextCacheKey(order, cacheKey);
        return cached;
    }

    NSUInteger pixelWidth = (NSUInteger)ceil(textSize.width * scale);
    NSUInteger pixelHeight = (NSUInteger)ceil(textSize.height * scale);
    if (pixelWidth == 0 || pixelHeight == 0 || pixelWidth > 4096u || pixelHeight > 4096u) return nil;

    NSMutableData* pixels = [NSMutableData dataWithLength:pixelWidth * pixelHeight * 4u];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(pixels.mutableBytes,
                                             pixelWidth,
                                             pixelHeight,
                                             8,
                                             pixelWidth * 4u,
                                             colorSpace,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!ctx) return nil;
    CGContextClearRect(ctx, CGRectMake(0.0, 0.0, (CGFloat)pixelWidth, (CGFloat)pixelHeight));
    CGContextScaleCTM(ctx, scale, scale);
    UIGraphicsPushContext(ctx);
    [text drawAtPoint:CGPointZero withAttributes:attrs];
    UIGraphicsPopContext();
    CGContextRelease(ctx);

    OrenAVMMetalTextCacheEntry* entry = [[OrenAVMMetalTextCacheEntry alloc] init];
    entry.logicalSize = textSize;
    entry.pixelCount = pixelWidth * pixelHeight;
    NSUInteger atlasX = 0;
    NSUInteger atlasY = 0;
    BOOL packed = NO;
    if (atlas && pixelWidth + OrenAVMMetalTextAtlasPadding <= OrenAVMMetalTextAtlasSize &&
        pixelHeight + OrenAVMMetalTextAtlasPadding <= OrenAVMMetalTextAtlasSize) {
        if (!*atlas || !OrenAVMMetalAtlasReserve(*atlas, pixelWidth, pixelHeight, &atlasX, &atlasY)) {
            *atlas = OrenAVMMetalCreateTextAtlas(device);
            packed = OrenAVMMetalAtlasReserve(*atlas, pixelWidth, pixelHeight, &atlasX, &atlasY);
        } else {
            packed = YES;
        }
    }
    if (packed && atlas && *atlas && (*atlas).texture) {
        [(*atlas).texture replaceRegion:MTLRegionMake2D(atlasX, atlasY, pixelWidth, pixelHeight)
                            mipmapLevel:0
                              withBytes:pixels.bytes
                            bytesPerRow:pixelWidth * 4u];
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
        if (!texture) return nil;
        [texture replaceRegion:MTLRegionMake2D(0, 0, pixelWidth, pixelHeight)
                   mipmapLevel:0
                     withBytes:pixels.bytes
                   bytesPerRow:pixelWidth * 4u];
        entry.texture = texture;
        entry.u0 = 0.0f;
        entry.v0 = 0.0f;
        entry.u1 = 1.0f;
        entry.v1 = 1.0f;
    }
    cache[cacheKey] = entry;
    *cachePixels += entry.pixelCount;
    OrenAVMMetalTouchTextCacheKey(order, cacheKey);
    OrenAVMMetalTrimTextCache(cache, order, cachePixels);
    return entry;
}

void OrenAVMMetalAppendTextureQuad(NSMutableData* vertices,
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
    if (!vertices || w <= 0.0f || h <= 0.0f) return;
    OrenAVMMetalTextVertex out[6];
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
    [vertices appendBytes:out length:sizeof(out)];
}

OrenAVMMetalTextRun* OrenAVMMetalCreateTextRun(id<MTLDevice> device,
                                               UIScreen* screen,
                                               OrenAVMMetalTextAtlas** atlas,
                                               NSMutableDictionary<NSString*, OrenAVMMetalTextCacheEntry*>* cache,
                                               NSMutableArray<NSString*>* order,
                                               NSUInteger* cachePixels,
                                               NSString* text,
                                               float x,
                                               float y,
                                               const uint8_t* rgba,
                                               float opacity,
                                               float logicalWidth,
                                               float logicalHeight) {
    OrenAVMMetalTextCacheEntry* entry = OrenAVMMetalTextCacheEntryForText(device, screen, atlas, cache, order, cachePixels, text, rgba);
    if (!entry) return nil;
    OrenAVMMetalTextRun* run = [[OrenAVMMetalTextRun alloc] init];
    run.texture = entry.texture;
    NSMutableData* vertices = [NSMutableData dataWithCapacity:sizeof(OrenAVMMetalTextVertex) * 6u];
    OrenAVMMetalAppendTextureQuad(vertices,
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
    run.vertices = vertices;
    run.opacity = opacity;
    return run;
}

OrenAVMMetalTextRun* OrenAVMMetalCreateTextBatchRun(id<MTLDevice> device,
                                                    UIScreen* screen,
                                                    OrenAVMMetalTextAtlas** atlas,
                                                    NSMutableDictionary<NSString*, OrenAVMMetalTextCacheEntry*>* cache,
                                                    NSMutableArray<NSString*>* order,
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
    OrenAVMMetalTextCacheEntry* entry = OrenAVMMetalTextCacheEntryForText(device, screen, atlas, cache, order, cachePixels, text, rgba);
    if (!entry) return nil;
    NSMutableData* vertices = [NSMutableData dataWithCapacity:(NSUInteger)positionCount * sizeof(OrenAVMMetalTextVertex) * 6u];
    for (uint32_t i = 0; i < positionCount; i++) {
        const uint8_t* p = positions + ((size_t)i * 8u);
        OrenAVMMetalAppendTextureQuad(vertices,
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
    }
    if (vertices.length == 0) return nil;
    OrenAVMMetalTextRun* run = [[OrenAVMMetalTextRun alloc] init];
    run.texture = entry.texture;
    run.vertices = vertices;
    run.opacity = opacity;
    return run;
}

static BOOL OrenAVMMetalTextScissorEqual(OrenAVMMetalTextRun* a, OrenAVMMetalTextRun* b) {
    if (a.hasScissor != b.hasScissor) return NO;
    if (!a.hasScissor) return YES;
    return a.scissor.x == b.scissor.x &&
           a.scissor.y == b.scissor.y &&
           a.scissor.width == b.scissor.width &&
           a.scissor.height == b.scissor.height;
}

static NSMutableData* OrenAVMMetalMutableTextVerticesForCoalescing(OrenAVMMetalTextRun* pending) {
    NSData* vertices = pending.vertices;
    if ([vertices isKindOfClass:[NSMutableData class]]) return (NSMutableData*)vertices;
    NSMutableData* mutableVertices = [NSMutableData dataWithData:vertices];
    pending.vertices = mutableVertices;
    return mutableVertices;
}

NSArray<OrenAVMMetalTextRun*>* OrenAVMMetalCoalesceTextRuns(NSArray<OrenAVMMetalTextRun*>* runs) {
    if (runs.count < 2) return runs ?: @[];
    NSMutableArray<OrenAVMMetalTextRun*>* out = [NSMutableArray arrayWithCapacity:runs.count];
    OrenAVMMetalTextRun* pending = nil;
    NSMutableData* pendingVertices = nil;
    for (OrenAVMMetalTextRun* run in runs) {
        if (!run.texture || run.vertices.length == 0) continue;
        BOOL same = pending &&
            pending.texture == run.texture &&
            pending.opacity == run.opacity &&
            OrenAVMMetalTextScissorEqual(pending, run);
        if (!same) {
            pending = [[OrenAVMMetalTextRun alloc] init];
            pending.texture = run.texture;
            pending.hasScissor = run.hasScissor;
            pending.scissor = run.scissor;
            pending.opacity = run.opacity;
            pending.vertices = run.vertices;
            pendingVertices = nil;
            [out addObject:pending];
            continue;
        }
        if (!pendingVertices) {
            pendingVertices = OrenAVMMetalMutableTextVerticesForCoalescing(pending);
        }
        [pendingVertices appendData:run.vertices];
    }
    return out;
}

#endif
