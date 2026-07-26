#!/usr/bin/env python3
"""Verify hot Metal frame paths stay bounded."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMMetalView.m"
FRAME_HEADER = ROOT / "sdk/ios/OrenAVMKit/OrenAVMMetalFrame.h"
FRAME_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMMetalFrame.m"
GEOMETRY_HEADER = ROOT / "sdk/ios/OrenAVMKit/OrenAVMMetalGeometry.h"
GEOMETRY_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMMetalGeometry.m"
RESOURCE_HEADER = ROOT / "sdk/ios/OrenAVMKit/OrenAVMMetalResources.h"
RESOURCE_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMMetalResources.m"
PIPELINE_HEADER = ROOT / "sdk/ios/OrenAVMKit/OrenAVMMetalPipeline.h"
PIPELINE_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMMetalPipeline.m"
TEXT_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMMetalText.m"
TEXT_HEADER = ROOT / "sdk/ios/OrenAVMKit/OrenAVMMetalText.h"
HELPER = "BOOL OrenAVMMetalBindVertexPayload"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def require_before(block: str, before: str, after: str, message: str) -> None:
    before_pos = block.find(before)
    after_pos = block.find(after)
    if before_pos < 0 or after_pos < 0 or before_pos > after_pos:
        fail(message)


def main() -> int:
    text = SOURCE.read_text()
    frame_header = FRAME_HEADER.read_text()
    frame_source = FRAME_SOURCE.read_text()
    frame_text = frame_header + "\n" + frame_source
    geometry_source_text = GEOMETRY_SOURCE.read_text()
    geometry_text = GEOMETRY_HEADER.read_text() + "\n" + geometry_source_text
    resource_source_text = RESOURCE_SOURCE.read_text()
    resource_text = RESOURCE_HEADER.read_text() + "\n" + resource_source_text
    pipeline_text = PIPELINE_HEADER.read_text() + "\n" + PIPELINE_SOURCE.read_text()
    metal_text = text + "\n" + frame_text + "\n" + geometry_text + "\n" + resource_text
    text_source = TEXT_SOURCE.read_text()
    text_header = TEXT_HEADER.read_text()
    if '"OrenAVMMetalFrame.h"' not in text:
        fail("Metal frame/run helpers must be imported through OrenAVMMetalFrame")
    if "OrenAVMMetalInlineVertexBytesLimit" not in frame_text:
        fail("missing inline vertex upload limit")
    if "uint64_t OrenAVMMetalNowNs(void)" not in frame_text or "uint64_t OrenAVMMetalTargetBudgetNs(uint32_t hzMilli)" not in frame_text:
        fail("Metal frame timing helpers must live in OrenAVMMetalFrame")
    if "static uint64_t OrenAVMMetalNowNs" in text or "static uint64_t OrenAVMMetalTargetBudgetNs" in text:
        fail("Metal view must not define frame timing helpers")
    if '"OrenAVMMetalPipeline.h"' not in text or "OrenAVMMetalBuildPipelineStates(" not in pipeline_text:
        fail("Metal shader/pipeline setup must live in OrenAVMMetalPipeline")
    if "newLibraryWithSource:" in text or "newRenderPipelineStateWithDescriptor:" in text:
        fail("Metal view must not inline shader compilation or pipeline descriptor setup")
    if "newLibraryWithSource:" not in pipeline_text or "newRenderPipelineStateWithDescriptor:" not in pipeline_text:
        fail("Metal pipeline helper must compile shaders and create render pipeline states")
    if HELPER not in frame_text:
        fail("missing bounded vertex payload helper")
    if "newBufferWithBytes:" not in frame_text or "addCompletedHandler:" not in text:
        fail("missing large vertex upload buffer retention path")
    if "newBufferWithBytes:" in text:
        fail("Metal view must use the frame helper for large vertex upload buffers")
    if "[transientVertexBuffers copy]" in text:
        fail("large vertex upload completion path must retain the existing tracking array without copying it")
    if "run.vertices = [vertices copy]" in text:
        fail("geometry vertex runs must transfer completed buffers instead of copying them at flush")
    if "[NSMutableData dataWithCapacity:vertices.length]" in text:
        fail("geometry flush must not allocate the next mutable vertex buffer eagerly")
    if "NSArray<OrenAVMMetalVertexRun*>* OrenAVMMetalCoalesceVertexRuns" not in frame_header:
        fail("Metal geometry runs must expose prepared-frame coalescing")
    if "@property(nonatomic) NSUInteger vertexCapacity;" not in resource_text:
        fail("Metal geometry runs must track raw vertex capacity separately from count")
    if "run.vertexCapacity = vertexBytes;" not in frame_text:
        fail("Metal geometry flush must seed vertex-run capacity from the transferred buffer")
    vertex_append_start = frame_source.find("static BOOL OrenAVMMetalVertexRunAppendBytes")
    vertex_append_end = frame_source.find("NSArray<OrenAVMMetalVertexRun*>* OrenAVMMetalCoalesceVertexRuns", vertex_append_start)
    if vertex_append_start < 0 or vertex_append_end < 0:
        fail("missing Metal geometry run append helper body")
    vertex_append_body = frame_source[vertex_append_start:vertex_append_end]
    for token in (
        "pending.vertexCapacity",
        "newCapacity *= 2u",
        "pending.vertexCapacity = newCapacity",
    ):
        if token not in vertex_append_body:
            fail(f"Metal geometry append helper missing expected capacity path: {token}")
    if "realloc(pending.vertices, needed)" in vertex_append_body:
        fail("Metal geometry coalescing must not realloc to the exact requested size")
    vertex_coalesce_start = frame_source.find("NSArray<OrenAVMMetalVertexRun*>* OrenAVMMetalCoalesceVertexRuns")
    vertex_coalesce_end = frame_source.find("BOOL OrenAVMMetalBindVertexPayload", vertex_coalesce_start)
    if vertex_coalesce_start < 0 or vertex_coalesce_end < 0:
        fail("missing Metal geometry run coalescing helper body")
    vertex_coalesce_body = frame_source[vertex_coalesce_start:vertex_coalesce_end]
    for token in (
        "OrenAVMMetalVertexRunScissorEqual(pending, run)",
        "OrenAVMMetalVertexRunAppendBytes(pending, run.vertices, run.vertexBytes)",
        "[NSMutableArray arrayWithCapacity:OrenAVMMetalRunArrayInitialCapacity(runs.count)]",
        "if (!out) return runs;",
        "pending = run;",
        "[out addObject:pending]",
    ):
        if token not in vertex_coalesce_body:
            fail(f"Metal geometry coalescing missing expected path: {token}")
    if "OrenAVMMetalVertexBuffer vertices;" not in frame_text or "OrenAVMMetalVertexBufferInit(&vertices" not in frame_text:
        fail("geometry vertex buffers must use the raw lazy vertex buffer builder")
    if "NSMutableData* vertices" in text or "NSMutableData* vertices" in geometry_text:
        fail("Metal geometry vertex builders must not use NSMutableData wrappers")
    if "[vertices appendBytes:" in geometry_text:
        fail("Metal geometry append helpers must write into raw vertex buffers")
    if "@property(nonatomic, strong) NSData* vertices" in resource_text:
        fail("Metal geometry runs must own raw vertex buffers, not NSData wrappers")
    if "uint8_t* vertices" not in resource_text or "NSUInteger vertexBytes" not in resource_text or "free(_vertices)" not in resource_text:
        fail("Metal geometry vertex runs must expose raw bytes with explicit cleanup")
    if "OrenAVMMetalVertexBufferTakeBytes" not in frame_text or "run.vertexBytes = vertexBytes" not in frame_text:
        fail("Metal geometry flush must transfer raw vertex buffers into runs")
    flush_start = frame_source.find("void OrenAVMMetalFlushVertexRun")
    flush_end = frame_source.find("static BOOL OrenAVMMetalVertexRunScissorEqual", flush_start)
    if flush_start < 0 or flush_end < 0:
        fail("missing Metal vertex-run flush helper")
    flush_body = frame_source[flush_start:flush_end]
    for token in (
        "if (!runs) {\n        free(vertices);\n        return;\n    }",
        "if (!run) {\n        free(vertices);\n        return;\n    }",
    ):
        if token not in flush_body:
            fail("Metal geometry flush must free taken vertex bytes if run allocation fails")
    bind_start = frame_source.find("BOOL OrenAVMMetalBindVertexPayload")
    bind_end = frame_source.find("void OrenAVMMetalEncodePreparedRuns", bind_start)
    if bind_start < 0 or bind_end < 0:
        fail("missing Metal vertex payload binding helper")
    bind_body = frame_source[bind_start:bind_end]
    retention_guard = bind_body.find("if (!transientBuffers) return NO;")
    array_alloc = bind_body.find("if (!*transientBuffers) *transientBuffers = [NSMutableArray arrayWithCapacity:4u];")
    array_guard = bind_body.find("if (!*transientBuffers) return NO;")
    large_upload = bind_body.find("id<MTLBuffer> buffer = [device newBufferWithBytes:bytes")
    if (
        retention_guard < 0
        or array_alloc < 0
        or array_guard < 0
        or large_upload < 0
        or retention_guard > array_alloc
        or array_alloc > array_guard
        or array_guard > large_upload
    ):
        fail("large Metal vertex uploads must preflight transient retention storage before allocating MTLBuffer")
    if "[NSMutableArray array]" in bind_body:
        fail("large Metal vertex upload retention must use a bounded initial capacity")
    if "OrenAVMMetalInitialVertexBuilderCapacity" not in frame_text or "const NSUInteger maxInitialBytes = 64u * 1024u" not in frame_text:
        fail("geometry vertex builder must cap its lazy initial reservation")
    if (
        '"OrenAVMMetalGeometry.h"' not in text
        or "OrenAVMMetalAppendRoundRect" not in geometry_text
        or "BOOL OrenAVMMetalAppendPrimitiveCommand" not in geometry_text
    ):
        fail("Metal primitive geometry helpers must live in OrenAVMMetalGeometry")
    if "OrenAVMMetalAppendPrimitiveCommand(opcode," not in frame_text:
        fail("Metal frame traversal must delegate primitive payload expansion to OrenAVMMetalGeometry")
    primitive_handler_start = geometry_source_text.find("BOOL OrenAVMMetalAppendPrimitiveCommand")
    primitive_handler_end = geometry_source_text.find("#endif", primitive_handler_start)
    if primitive_handler_start < 0 or primitive_handler_end < 0:
        fail("missing Metal primitive command handler")
    primitive_handler = geometry_source_text[primitive_handler_start:primitive_handler_end]
    if "if (opacity <= 0.0f)" not in primitive_handler or "case 10:" not in primitive_handler:
        fail("Metal primitive command handler must skip fully transparent draw-only opcodes before vertex emission")
    if "static void OrenAVMMetalAppendRoundRect" in text or "static void OrenAVMMetalAppendCircle" in text:
        fail("Metal view must not inline primitive geometry append helpers")
    rect_start = geometry_source_text.find("void OrenAVMMetalAppendRect")
    rect_end = geometry_source_text.find("void OrenAVMMetalAppendLine", rect_start)
    stroke_rect_start = geometry_source_text.find("void OrenAVMMetalAppendStrokeRect")
    stroke_rect_end = geometry_source_text.find("void OrenAVMMetalAppendTriangle", stroke_rect_start)
    if rect_start < 0 or rect_end < 0 or stroke_rect_start < 0 or stroke_rect_end < 0:
        fail("missing Metal rectangle append helper bodies")
    rect_body = geometry_source_text[rect_start:rect_end]
    stroke_rect_body = geometry_source_text[stroke_rect_start:stroke_rect_end]
    if "if (w <= 0.0f || h <= 0.0f) return;" not in rect_body:
        fail("Metal filled rectangles must skip zero-area vertex emission")
    if "if (w <= 0.0f || h <= 0.0f) return;" not in stroke_rect_body:
        fail("Metal stroked rectangles must skip zero-area vertex emission before edge expansion")
    triangle_start = geometry_source_text.find("void OrenAVMMetalAppendTriangle")
    triangle_end = geometry_source_text.find("void OrenAVMMetalAppendCircle", triangle_start)
    if triangle_start < 0 or triangle_end < 0:
        fail("missing Metal triangle append helper body")
    triangle_body = geometry_source_text[triangle_start:triangle_end]
    if "OrenAVMMetalTriangleIsDegenerate" not in geometry_source_text or "if (OrenAVMMetalTriangleIsDegenerate(x1, y1, x2, y2, x3, y3)) return;" not in triangle_body:
        fail("Metal triangle append helper must skip degenerate triangle vertex emission")
    primitive_view_tokens = (
        "pointCount = OrenAVMMetalReadU32LE(payload + 4)",
        "triangleCount = OrenAVMMetalReadU32LE(payload)",
        "OrenAVMMetalAppendStrokeRect(",
        "OrenAVMMetalAppendEllipse(",
        "OrenAVMMetalAppendTriangle(",
    )
    for token in primitive_view_tokens:
        if token in text:
            fail("Metal primitive payload expansion must not live in OrenAVMMetalView")
    if "[NSMutableData data]" in text:
        fail("geometry vertex builder must not default-grow from an uncapped zero-capacity buffer")
    if "run.vertices = [vertices copy]" in text_source:
        fail("batched text vertex runs must transfer completed buffers instead of copying them")
    if "NSMutableData* vertices = [NSMutableData dataWithCapacity:sizeof(OrenAVMMetalTextVertex) * 6u]" in text_source:
        fail("single Metal text runs must store fixed quad vertices inline")
    if "OrenAVMMetalWriteTextureQuad(run->inlineVertices" not in text_source or "NSUInteger inlineVertexCount" not in text_header:
        fail("Metal text runs must expose inline single-quad storage")
    if "[NSMutableData dataWithData:pending.vertices]" in text_source:
        fail("text coalescing must use the mutable-vertex helper instead of unconditionally copying pending data")
    if "@property(nonatomic, strong) NSData* vertices" in text_header:
        fail("Metal text runs must not wrap variable vertices in NSData")
    if "NSMutableData* vertices = [NSMutableData dataWithCapacity:(NSUInteger)positionCount" in text_source:
        fail("batched Metal text runs must use raw owned vertex buffers")
    if "OrenAVMMetalAppendTextureQuad" in text_source or "OrenAVMMetalAppendTextureQuad" in text_header:
        fail("Metal text quad writes must target caller-owned raw or inline buffers")
    if "OrenAVMMetalTextVertex* heapVertices" not in text_header or "free(heapVertices)" not in text_source:
        fail("Metal text runs must own raw heap vertex buffers with explicit cleanup")
    if "NSUInteger heapVertexCapacity" not in text_header:
        fail("Metal text runs must track heap vertex capacity separately from count")
    if "newCapacity *= 2u" not in text_source or "run->heapVertexCapacity = newCapacity" not in text_source:
        fail("Metal text heap vertex growth must be geometric, not exact-size per append")
    if "newCapacity > NSUIntegerMax / sizeof(OrenAVMMetalTextVertex)" not in text_source:
        fail("Metal text heap vertex reserve must clamp geometric growth before byte-size overflow")
    if "realloc(run->heapVertices, neededCount * sizeof(OrenAVMMetalTextVertex))" in text_source:
        fail("Metal text heap vertex reserve must not realloc to the exact requested count")
    if (
        "OrenAVMMetalTextRunAllocateExactHeapVertices(run, vertexCount)" not in text_source
        or "static BOOL OrenAVMMetalTextRunAllocateExactHeapVertices" not in text_source
    ):
        fail("known-size batched Metal text runs must allocate exact heap vertex storage once")
    if "OrenAVMMetalEnsureHeapTextVerticesForCoalescing" not in text_source:
        fail("missing raw text coalescing heap-vertex helper")
    if "[vertices isKindOfClass:[NSMutableData class]]" in text_source or "dataWithBytes:pending->inlineVertices" in text_source:
        fail("text coalescing must not materialize inline quads through NSMutableData")
    coalesce_start = text_source.find("NSArray<OrenAVMMetalTextRun*>* OrenAVMMetalCoalesceTextRuns")
    coalesce_end = text_source.find("#endif", coalesce_start)
    if coalesce_start < 0 or coalesce_end < 0:
        fail("missing Metal text run coalescing helper")
    coalesce_body = text_source[coalesce_start:coalesce_end]
    if "pending = [[OrenAVMMetalTextRun alloc] init]" in coalesce_body:
        fail("text coalescing must reuse prepared run objects instead of cloning every run")
    if "pending = run;" not in coalesce_body:
        fail("text coalescing must keep the first run in each compatible group")
    if "if (!out) return runs;" not in coalesce_body:
        fail("text coalescing must preserve original prepared runs if the optional output array cannot be allocated")
    if "[NSMutableArray arrayWithCapacity:OrenAVMMetalRunArrayInitialCapacity(runs.count)]" not in coalesce_body:
        fail("text coalescing must cap optional output-array reservation")
    cache_lookup = text_source.find("OrenAVMMetalTextCacheEntry* cached = cache[cacheKey]")
    attrs_lookup = text_source.find("OrenAVMMetalTextAttributesForRGBA(attributesCache, rgba)")
    if cache_lookup < 0 or attrs_lookup < 0 or cache_lookup > attrs_lookup:
        fail("Metal text cache hits must return before looking up UIKit attributes")
    require_before(text_source,
                   "if (!cacheKey) return nil;",
                   "OrenAVMMetalTextCacheEntry* cached = cache[cacheKey]",
                   "Metal text cache lookups must guard typed cache-key allocation before dictionary access")
    require_before(text_source,
                   "OrenAVMMetalTextCacheEntry* entry = [[OrenAVMMetalTextCacheEntry alloc] init];",
                   "uint8_t* pixels = (uint8_t*)malloc(pixelBytes)",
                   "Metal text cache misses must allocate the cache entry before glyph rasterization storage")
    require_before(text_source,
                   "if (!entry) return nil;",
                   "uint8_t* pixels = (uint8_t*)malloc(pixelBytes)",
                   "Metal text cache misses must guard cache-entry allocation before glyph rasterization storage")
    if "OrenAVMMetalTextAttributeCacheEntryLimit = 256u" not in text_source:
        fail("Metal text attribute cache must stay bounded")
    if "CFDictionaryRemoveAllValues(cache.entries)" not in text_source:
        fail("Metal text attribute cache must admit new colors after hitting its bounded entry limit")
    if "OrenAVMMetalTextAttributeCache* orenTextAttributes" not in text:
        fail("Metal text attributes must be cached through a typed view-owned cache")
    if "self.orenTextAttributes" not in text or "textAttributes" not in resource_text:
        fail("Metal text creation paths must share the view-owned attribute cache")
    if "@interface OrenAVMMetalTextAttributeCache : NSObject" not in text_header:
        fail("Metal text attributes must use a typed cache object")
    attr_helper_start = text_source.find("static NSDictionary<NSAttributedStringKey, id>* OrenAVMMetalTextAttributesForRGBA")
    attr_helper_end = text_source.find("void OrenAVMMetalClearTextTextureCache", attr_helper_start)
    if attr_helper_start < 0 or attr_helper_end < 0:
        fail("missing Metal text attribute helper body")
    attr_helper = text_source[attr_helper_start:attr_helper_end]
    mru_pos = attr_helper.find("cache.lastAttributes && cache.lastRGBA == rgbaValue")
    scalar_key_pos = attr_helper.find("const void* key = OrenAVMMetalTextAttributeKey(rgbaValue)")
    if mru_pos < 0 or scalar_key_pos < 0 or mru_pos > scalar_key_pos:
        fail("Metal repeated-color text attributes must hit a scalar MRU before scalar-map lookup")
    if "NSNumber* key = @(rgbaValue)" in attr_helper or "NSMutableDictionary<NSNumber*, NSDictionary<NSAttributedStringKey, id>*>* entries" in text_header:
        fail("Metal text attribute cache must not box RGBA keys")
    if "CFDictionaryGetValue(cache.entries, key)" not in attr_helper or "CFDictionarySetValue(cache.entries, key" not in attr_helper:
        fail("Metal text attribute cache must use scalar-key CF dictionary lookup/storage")
    if "[NSString stringWithFormat:" in text_source:
        fail("Metal text cache keys must stay typed objects instead of formatted strings")
    if "@interface OrenAVMMetalTextCacheKey : NSObject <NSCopying>" not in text_header:
        fail("Metal text cache must expose a typed immutable cache-key object")
    if "+ (instancetype)keyWithText:(NSString*)text rgba:(const uint8_t*)rgba scaleMilli:(uint32_t)scaleMilli" not in text_source:
        fail("Metal text cache must build compact typed cache keys")
    atlas_rotate = text_source.find("OrenAVMMetalClearTextTextureCache(cache, order, cachePixels)")
    atlas_recreate = text_source.find("*atlas = OrenAVMMetalCreateTextAtlas(device)", atlas_rotate)
    if atlas_rotate < 0 or atlas_recreate < 0:
        fail("Metal text atlas rotation must clear stale texture-cache entries before creating a fresh atlas")
    if "OrenAVMMetalClearTextAtlasPadding" not in text_source:
        fail("Metal text atlases must clear only sampled glyph padding")
    if "dataWithLength:OrenAVMMetalTextAtlasSize * OrenAVMMetalTextAtlasSize * 4u" in text_source:
        fail("Metal text atlas creation must not allocate a full zero buffer")
    if "static const uint8_t zeroAtlasPadding[OrenAVMMetalTextAtlasSize * 4u] = {0}" not in text_source:
        fail("Metal text atlas padding clears must reuse a shared zero stripe")
    if "uint8_t zero[OrenAVMMetalTextAtlasSize * 4u] = {0}" in text_source:
        fail("Metal text atlas padding clears must not rebuild a zero stripe per glyph")
    if "OrenAVMMetalClearTextAtlasPadding((*atlas).texture, atlasX, atlasY, pixelWidth, pixelHeight)" not in text_source:
        fail("packed Metal text uploads must clear transparent atlas padding")
    if "NSMutableData* pixels = [NSMutableData dataWithLength:pixelWidth * pixelHeight * 4u]" in text_source:
        fail("Metal text cache misses must not wrap temporary glyph pixels in NSMutableData")
    if "uint8_t* pixels = (uint8_t*)malloc(pixelBytes)" not in text_source or "free(pixels)" not in text_source:
        fail("Metal text cache misses must use raw temporary glyph pixels with explicit cleanup")
    if "withBytes:pixels.bytes" in text_source or "pixels.mutableBytes" in text_source:
        fail("Metal text texture uploads must use raw glyph pixel pointers")
    if "OrenAVMMetalTextureQuad" in text_source or "OrenAVMMetalTextureQuad" in text_header:
        fail("single Metal texture/text quads must use caller-owned mutable vertex buffers")
    if "dataWithBytes:out length:sizeof(out)" in text_source:
        fail("single Metal texture/text quads must not allocate NSData wrappers from stack vertices")
    single_text_start = text_source.find("OrenAVMMetalTextRun* OrenAVMMetalCreateTextRun")
    single_text_end = text_source.find("static BOOL OrenAVMMetalTextRunReserveHeapVertices", single_text_start)
    batch_text_start = text_source.find("OrenAVMMetalTextRun* OrenAVMMetalCreateTextBatchRun")
    batch_text_end = text_source.find("OrenAVMMetalTextRunVertexBytes", batch_text_start)
    if single_text_start < 0 or single_text_end < 0 or batch_text_start < 0 or batch_text_end < 0:
        fail("missing Metal text run construction helpers")
    single_text_body = text_source[single_text_start:single_text_end]
    batch_text_body = text_source[batch_text_start:batch_text_end]
    require_before(single_text_body,
                   "if (!run) return nil;",
                   "OrenAVMMetalWriteTextureQuad(run->inlineVertices",
                   "single Metal text run construction must guard run allocation before vertex writes")
    if batch_text_body.count("if (!run) return nil;") < 2:
        fail("batched Metal text run construction must guard both single-position and heap run allocations")
    require_before(batch_text_body,
                   "if (!run) return nil;",
                   "OrenAVMMetalWriteTextureQuad(run->inlineVertices",
                   "single-position batched Metal text construction must guard run allocation before vertex writes")
    require_before(batch_text_body,
                   "if (!run) return nil;",
                   "OrenAVMMetalTextRunAllocateExactHeapVertices(run, vertexCount)",
                   "multi-position batched Metal text construction must guard run allocation before heap allocation")
    if "dataWithBytes:payload + 4 length:4" in metal_text:
        fail("retained Metal RGBA fields must stay scalar instead of allocating NSData wrappers")
    if "@property(nonatomic) uint32_t rgbaValue" not in metal_text or "@property(nonatomic) uint32_t rgbaValue" not in text_header:
        fail("missing scalar RGBA storage for retained Metal mesh/text resources")
    for helper in (
        "OrenAVMMetalRetainedImageKey",
        "OrenAVMMetalRetainedImageResource",
        "OrenAVMMetalPutImageResource",
        "OrenAVMMetalRemoveImageResource",
        "OrenAVMMetalImageRunCreate",
        "OrenAVMMetalRetainedTextKey",
        "OrenAVMMetalRetainedTextResource",
        "OrenAVMMetalPutTextResource",
        "OrenAVMMetalRemoveTextResource",
        "OrenAVMMetalRetainedMeshKey",
        "OrenAVMMetalRetainedMesh2DResource",
        "OrenAVMMetalRetainedMesh3DResource",
        "OrenAVMMetalAppendMesh2DResource",
        "OrenAVMMetalAppendMesh3DResource",
        "OrenAVMMetalPutMesh2DResource",
        "OrenAVMMetalRemoveMeshResource",
        "OrenAVMMetalPutPackedMesh3DResource",
        "OrenAVMMetalPutIndexedMesh3DResource",
        "OrenAVMMetalRetainedMaterialKey",
        "OrenAVMMetalRetainedMaterialValue",
        "OrenAVMMetalRetainedMaterialRGBA",
        "OrenAVMMetalPutMaterialResource",
        "OrenAVMMetalRemoveMaterialResource",
        "OrenAVMMetalRetainedModelKey",
        "OrenAVMMetalRetainedModelResource",
        "OrenAVMMetalPutModelResource",
        "OrenAVMMetalRemoveModelResource",
    ):
        if helper not in resource_text:
            fail(f"retained Metal scalar resource helper must live in OrenAVMMetalResources: {helper}")
    if "static const void* OrenAVMMetalRetainedImageKey" in text or "static OrenAVMMetalImageResource* OrenAVMMetalRetainedImageResource" in text:
        fail("Metal view must not define retained image scalar-map helpers")
    if "- (OrenAVMMetalImageRun*)orenImageRunWithTexture:" in text:
        fail("Metal view must not define image texture-run construction helpers")
    if "OrenAVMMetalWriteTextureQuad(run->vertices" in text:
        fail("Metal image run quad construction must live with Metal image-run resources")
    if "static const void* OrenAVMMetalRetainedTextKey" in text or "static OrenAVMMetalTextResource* OrenAVMMetalRetainedTextResource" in text:
        fail("Metal view must not define retained text scalar-map helpers")
    if "static const void* OrenAVMMetalRetainedMeshKey" in text or "static OrenAVMMetalMesh2DResource* OrenAVMMetalRetainedMesh2DResource" in text:
        fail("Metal view must not define retained mesh scalar-map helpers")
    if "static const void* OrenAVMMetalRetainedMaterialKey" in text or "static BOOL OrenAVMMetalRetainedMaterialRGBA" in text:
        fail("Metal view must not define retained material scalar-map helpers")
    if "static const void* OrenAVMMetalRetainedModelKey" in text or "static OrenAVMMetalModelResource* OrenAVMMetalRetainedModelResource" in text:
        fail("Metal view must not define retained model scalar-map helpers")
    if "NSMutableDictionary<NSNumber*, OrenAVMMetalMesh2DResource*>* orenMeshes" in text:
        fail("retained Metal 2D mesh lookups must avoid boxed NSNumber mesh IDs")
    if "NSMutableDictionary<NSNumber*, OrenAVMMetalMesh3DResource*>* orenMeshes3D" in text:
        fail("retained Metal 3D mesh lookups must avoid boxed NSNumber mesh IDs")
    if "CFMutableDictionaryRef _orenMeshesByID" not in text or "CFMutableDictionaryRef _orenMeshes3DByID" not in text:
        fail("retained Metal mesh resources must use scalar-key CF dictionaries")
    if ".meshes2D = &_orenMeshesByID" not in text or "OrenAVMMetalHandleMeshCommand(context->meshes2D," not in frame_text:
        fail("retained Metal mesh/material/model opcodes must delegate through frame traversal to the resource-owned command helper")
    if "BOOL OrenAVMMetalHandleMeshCommand" not in resource_text:
        fail("retained Metal mesh/material/model command helper must live in OrenAVMMetalResources")
    mesh_command = resource_text[resource_text.find("BOOL OrenAVMMetalHandleMeshCommand") :]
    if "OrenAVMMetalRetainedMesh2DResource(meshes2D ? *meshes2D : NULL" not in mesh_command:
        fail("retained Metal 2D mesh draws must use the scalar-map resource helper")
    if "OrenAVMMetalAppendMesh2DResource(mesh, vertices, tx, ty, logicalWidth, logicalHeight, opacity)" not in mesh_command:
        fail("retained Metal 2D mesh draws must delegate raw payload expansion to OrenAVMMetalResources")
    if "OrenAVMMetalAppendMesh3DResource(meshes3D ? *meshes3D : NULL" not in mesh_command:
        fail("retained Metal 3D mesh draws must delegate raw payload expansion to OrenAVMMetalResources")
    if "OrenAVMMetalPutMesh2DResource(meshes2D," not in mesh_command:
        fail("retained Metal 2D mesh uploads must use the resource-owned upload helper")
    if "OrenAVMMetalPutPackedMesh3DResource(meshes3D," not in mesh_command:
        fail("retained Metal packed 3D mesh uploads must use the resource-owned upload helper")
    if "OrenAVMMetalPutIndexedMesh3DResource(meshes3D," not in mesh_command:
        fail("retained Metal indexed 3D mesh uploads must use the resource-owned upload helper")
    if "OrenAVMMetalRemoveMeshResource(meshes2D ? *meshes2D : NULL" not in mesh_command:
        fail("retained Metal 2D mesh removals must use the resource-owned removal helper")
    if "OrenAVMMetalRemoveMeshResource(meshes3D ? *meshes3D : NULL" not in mesh_command:
        fail("retained Metal 3D mesh removals must use the resource-owned removal helper")
    if "CFDictionarySetValue(_orenMeshes" in text or "CFDictionaryRemoveValue(_orenMeshes" in text:
        fail("retained Metal mesh map mutation must live in OrenAVMMetalResources")
    if "OrenAVMMetalRetainedMesh2DResource(_orenMeshesByID" in text or "OrenAVMMetalAppendMesh2DResource(mesh, &vertices" in text:
        fail("retained Metal 2D draw command expansion must not live in the view")
    if "mesh.triangles" in text or "mesh.triangleCount" in text:
        fail("retained Metal 2D draw block must not expand resource payloads in the view")
    if "NSMutableDictionary<NSNumber*, OrenAVMMetalTextResource*>* orenTextResources" in text:
        fail("retained Metal text lookups must avoid boxed NSNumber text IDs")
    if "CFMutableDictionaryRef _orenTextResourcesByID" not in text:
        fail("retained Metal text resources must use a scalar-key CF dictionary")
    if ".textResources = &_orenTextResourcesByID" not in text or "OrenAVMMetalHandleTextCommand(context->textResources," not in frame_text:
        fail("retained Metal text opcodes must delegate through frame traversal to the resource-owned command helper")
    if "BOOL OrenAVMMetalHandleTextCommand" not in resource_text:
        fail("retained Metal text command helper must live in OrenAVMMetalResources")
    if "OrenAVMMetalRetainedTextResource(texts ? *texts : NULL" not in resource_text:
        fail("retained Metal text draws must use the typed scalar-map resource helper")
    if "OrenAVMMetalPutTextResource(texts," not in resource_text:
        fail("retained Metal text uploads must use the resource-owned upload helper")
    if "OrenAVMMetalRemoveTextResource(texts ? *texts : NULL" not in resource_text:
        fail("retained Metal text removals must use the resource-owned removal helper")
    put_text_start = resource_source_text.find("BOOL OrenAVMMetalPutTextResource")
    put_text_end = resource_source_text.find("void OrenAVMMetalRemoveTextResource", put_text_start)
    if put_text_start < 0 or put_text_end < 0:
        fail("missing retained Metal text upload helper")
    put_text_body = resource_source_text[put_text_start:put_text_end]
    if "if (!texts || textID == 0 || !textBytes || textLen == 0) return NO;" not in put_text_body:
        fail("retained Metal text uploads must reject empty text before map/string/resource work")
    require_before(put_text_body,
                   "OrenAVMMetalEnsureRetainedResourceMap(texts)",
                   "[[NSString alloc] initWithBytes:textBytes",
                   "retained Metal text uploads must preflight scalar-map storage before string creation")
    require_before(put_text_body,
                   "OrenAVMMetalEnsureRetainedResourceMap(texts)",
                   "[[OrenAVMMetalTextResource alloc] init]",
                   "retained Metal text uploads must preflight scalar-map storage before resource allocation")
    require_before(put_text_body,
                   "if (!resource) return NO;",
                   "CFDictionarySetValue(*texts",
                   "retained Metal text uploads must guard resource allocation before map insertion")
    text_command = resource_text[resource_text.find("BOOL OrenAVMMetalHandleTextCommand") :]
    for token in (
        "case 2:",
        "case 68:",
        "case 69:",
        "case 70:",
        "case 72:",
        "OrenAVMMetalCreateTextRun(device,",
        "OrenAVMMetalCreateTextBatchRun(device,",
        "OrenAVMMetalPutTextResource(texts,",
        "OrenAVMMetalRetainedTextResource(texts ? *texts : NULL",
    ):
        if token in text:
            fail("retained Metal text opcode expansion must not live in OrenAVMMetalView")
        if token not in text_command:
            fail(f"retained Metal text command helper missing expected path: {token}")
    for token in (
        "case 2: {\n            if (opacity <= 0.0f) return YES;",
        "case 69: {\n            if (opacity <= 0.0f) return YES;",
        "case 72: {\n            if (opacity <= 0.0f) return YES;",
    ):
        if token not in text_command:
            fail(f"retained Metal text draw opcode must skip fully transparent texture work: {token}")
    if "if (textLen == (uint32_t)payloadLen - 16u && textLen > 0)" not in text_command:
        fail("Metal immediate text opcodes must reject trailing payload bytes and empty text before texture creation")
    immediate_text = text_command[text_command.find("case 2:"):text_command.find("case 68:")]
    require_before(
        immediate_text,
        "if (!text) return YES;",
        "OrenAVMMetalCreateTextRun(device,",
        "Metal immediate text must reject invalid UTF-8 before texture/run work",
    )
    if "if (textLen == (uint32_t)payloadLen - 12u && textLen > 0)" not in text_command:
        fail("Metal retained text upload opcodes must reject empty text before resource creation")
    text_batch_start = text_command.find("case 72:")
    text_batch_end = text_command.find("default:", text_batch_start)
    if text_batch_start < 0 or text_batch_end < 0:
        fail("missing retained Metal batched text draw path")
    text_batch_body = text_command[text_batch_start:text_batch_end]
    require_before(
        text_batch_body,
        "posCount == ((uint32_t)payloadLen - 8u) / 8u",
        "OrenAVMMetalRetainedTextResource(texts ? *texts : NULL, textID)",
        "retained Metal batched text draws must validate position counts before retained text lookup",
    )
    if "CFDictionarySetValue(_orenTextResourcesByID" in text or "CFDictionaryRemoveValue(_orenTextResourcesByID" in text:
        fail("retained Metal text map mutation must live in OrenAVMMetalResources")
    if "@(textID)" in text:
        fail("retained Metal text upload/draw paths must not box text IDs")
    if "@property(nonatomic, strong) NSData* triangles" in metal_text or "@property(nonatomic, strong) NSData* indices" in metal_text:
        fail("retained Metal mesh payloads must stay raw owned buffers, not NSData wrappers")
    for pattern in (
        "mesh.triangles = [NSData dataWithBytes:payload",
        "mesh.vertices = [NSData dataWithBytes:payload",
        "mesh.indices = [NSData dataWithBytes:payload",
        "mesh.triangles.bytes",
        "mesh.indices.length",
    ):
        if pattern in metal_text:
            fail("retained Metal mesh payload path regressed to NSData-backed access")
    if "OrenAVMMetalCopyPayloadBytes" not in metal_text:
        fail("missing retained Metal mesh raw payload copy helper")
    if "if (!src || len == 0) return NULL;" not in resource_text:
        fail("retained Metal mesh payload copy helper must reject null sources before memcpy")
    put_mesh2d_start = resource_source_text.find("BOOL OrenAVMMetalPutMesh2DResource")
    put_packed_start = resource_source_text.find("BOOL OrenAVMMetalPutPackedMesh3DResource", put_mesh2d_start)
    put_indexed_start = resource_source_text.find("BOOL OrenAVMMetalPutIndexedMesh3DResource", put_packed_start)
    put_mesh_end = resource_source_text.find("const void* OrenAVMMetalRetainedMaterialKey", put_indexed_start)
    if put_mesh2d_start < 0 or put_packed_start < 0 or put_indexed_start < 0 or put_mesh_end < 0:
        fail("missing retained Metal mesh upload helpers")
    put_mesh2d_body = resource_source_text[put_mesh2d_start:put_packed_start]
    put_packed_body = resource_source_text[put_packed_start:put_indexed_start]
    put_indexed_body = resource_source_text[put_indexed_start:put_mesh_end]
    require_before(put_mesh2d_body,
                   "OrenAVMMetalEnsureRetainedResourceMap(meshes)",
                   "OrenAVMMetalCopyPayloadBytes(triangles, triangleBytes)",
                   "retained Metal 2D mesh uploads must preflight scalar-map storage before payload copies")
    require_before(put_packed_body,
                   "OrenAVMMetalEnsureRetainedResourceMap(meshes)",
                   "OrenAVMMetalCopyPayloadBytes(triangles, triangleBytes)",
                   "retained Metal packed 3D mesh uploads must preflight scalar-map storage before payload copies")
    require_before(put_indexed_body,
                   "OrenAVMMetalEnsureRetainedResourceMap(meshes)",
                   "OrenAVMMetalCopyPayloadBytes(vertices, vertexBytes)",
                   "retained Metal indexed 3D mesh uploads must preflight scalar-map storage before payload copies")
    for token in (
        "uint8_t* triangleCopy = OrenAVMMetalCopyPayloadBytes(triangles, triangleBytes);",
        "mesh.triangles = triangleCopy;",
        "uint8_t* vertexCopy = OrenAVMMetalCopyPayloadBytes(vertices, vertexBytes);",
        "if (!vertexCopy) return NO;",
        "uint8_t* indexCopy = OrenAVMMetalCopyPayloadBytes(indices, indexBytes);",
        "if (!indexCopy) {\n        free(vertexCopy);\n        return NO;\n    }",
        "mesh.vertices = vertexCopy;",
        "mesh.indices = indexCopy;",
    ):
        if token not in resource_text:
            fail(f"retained Metal mesh payload copies must be staged and checked before resource install: {token}")
    for pattern in (
        "mesh.triangles = OrenAVMMetalCopyPayloadBytes(triangles, triangleBytes);",
        "mesh.vertices = OrenAVMMetalCopyPayloadBytes(vertices, vertexBytes);",
        "mesh.indices = OrenAVMMetalCopyPayloadBytes(indices, indexBytes);",
    ):
        if pattern in resource_text:
            fail("retained Metal mesh payload path must not assign unchecked direct copy results")
    if "OrenAVMMetalInlineTriangleOrderCapacity = 128" not in resource_text:
        fail("retained Metal 3D triangle ordering must have a small stack buffer")
    if "static BOOL OrenAVMMetalTriangleOrderAppend" not in resource_text:
        fail("retained Metal 3D triangle ordering must append visible triangles through a bounded helper")
    if "OrenAVMMetalTriangleOrderBuffer(triangleTotal" in resource_text:
        fail("retained Metal 3D triangle ordering must not allocate order storage for fully clipped triangles")
    for helper in (
        "static int64_t OrenAVMMetalMesh3DZSum",
        "OrenAVMMetalMesh3DZSumModel",
        "OrenAVMMetalMesh3DZVisible",
        "static int OrenAVMMetalTriangleOrderCompare",
        "OrenAVMMetalSortTriangleOrder",
        "OrenAVMMetalMesh3DIndexedZSumModel",
        "OrenAVMMetalMesh3DModelCoord",
        "OrenAVMMetalTriangleOrderAppend",
    ):
        if helper not in resource_text:
            fail(f"retained Metal 3D ordering helper must live in OrenAVMMetalResources: {helper}")
    for helper in (
        "static int64_t OrenAVMMetalMesh3DZSum",
        "static BOOL OrenAVMMetalMesh3DZVisible",
        "static int OrenAVMMetalTriangleOrderCompare",
        "static OrenAVMMetalTriangleOrder* OrenAVMMetalTriangleOrderBuffer",
        "static void OrenAVMMetalSortTriangleOrder",
        "static int64_t OrenAVMMetalMesh3DIndexedZSumModel",
        "static float OrenAVMMetalMesh3DModelCoord",
    ):
        if helper in text:
            fail(f"Metal view must not define retained 3D ordering helper: {helper}")
    if resource_text.count("OrenAVMMetalTriangleOrder inlineOrder[OrenAVMMetalInlineTriangleOrderCapacity]") < 2:
        fail("retained Metal 3D draw paths must pass stack triangle-order buffers")
    if "NSMutableData* orderData" in text or "dataWithLength:(NSUInteger)triangleCount * sizeof(OrenAVMMetalTriangleOrder)" in text:
        fail("retained Metal 3D triangle ordering must not use NSMutableData heap fallbacks")
    if "OrenAVMMetalTriangleOrder* heapOrder = NULL" not in resource_text or "free(heapOrder)" not in resource_text:
        fail("retained Metal 3D triangle ordering must free raw heap fallbacks")
    if "order[visibleTotal++] = (OrenAVMMetalTriangleOrder)" in resource_text:
        fail("retained Metal 3D draw paths must grow order storage as visible triangles are appended")
    if "NSMutableDictionary<NSNumber*, NSNumber*>* orenMaterials3D" in text:
        fail("retained Metal materials must avoid boxed NSNumber IDs/RGBA values")
    if "CFMutableDictionaryRef _orenMaterials3DByID" not in text:
        fail("retained Metal materials must use a scalar-key/scalar-value CF dictionary")
    if ".meshes2D = &_orenMeshesByID" not in text or "OrenAVMMetalHandleMeshCommand(context->meshes2D," not in frame_text:
        fail("retained Metal mesh/material/model opcodes must delegate through frame traversal to the resource-owned command helper")
    if "BOOL OrenAVMMetalHandleMeshCommand" not in resource_text:
        fail("retained Metal mesh/material/model command helper must live in OrenAVMMetalResources")
    if "OrenAVMMetalRetainedMaterialRGBA(materials, materialID, &materialRGBAOverride)" not in resource_text:
        fail("retained Metal material draws must use the scalar material lookup helper")
    if "OrenAVMMetalPutMaterialResource(materials," not in resource_text:
        fail("retained Metal material uploads must use the resource-owned upload helper")
    if "OrenAVMMetalRemoveMaterialResource(materials ? *materials : NULL" not in resource_text:
        fail("retained Metal material removals must use the resource-owned removal helper")
    if "CFDictionarySetValue(_orenMaterials3DByID" in text or "CFDictionaryRemoveValue(_orenMaterials3DByID" in text:
        fail("retained Metal material map mutation must live in OrenAVMMetalResources")
    if "materialRGBAValue" in text or "@(materialID)" in text:
        fail("retained Metal material paths must not box material IDs or RGBA values")
    mesh_command = resource_text[resource_text.find("BOOL OrenAVMMetalHandleMeshCommand") :]
    for token in (
        "case 80:",
        "case 81:",
        "case 82:",
        "case 83:",
        "case 84:",
        "case 85:",
        "case 86:",
        "case 87:",
        "case 88:",
        "case 89:",
        "case 90:",
        "case 91:",
        "case 92:",
        "case 93:",
        "case 94:",
        "case 95:",
        "OrenAVMMetalPutMesh2DResource(meshes2D,",
        "OrenAVMMetalPutPackedMesh3DResource(meshes3D,",
        "OrenAVMMetalPutIndexedMesh3DResource(meshes3D,",
        "OrenAVMMetalAppendMesh2DResource(mesh,",
        "OrenAVMMetalAppendMesh3DResource(meshes3D ? *meshes3D : NULL",
        "OrenAVMMetalPutMaterialResource(materials,",
        "OrenAVMMetalPutModelResource(models,",
    ):
        if token in text:
            fail("retained Metal mesh/material/model opcode expansion must not live in OrenAVMMetalView")
        if token not in mesh_command:
            fail(f"retained Metal mesh/material/model command helper missing expected path: {token}")
    if "uint32_t materialRGBA = hasMaterialRGBA ? materialRGBAOverride : mesh.rgbaValue;" not in resource_text:
        fail("retained Metal material overrides must resolve once per draw")
    indexed_start = resource_text.find("if (verts && idx && mesh.hasRGBA")
    packed_start = resource_text.find("} else if (tris && scaleMilli", indexed_start)
    mesh_draw_end = resource_text.find("BOOL OrenAVMMetalHandleMeshCommand", packed_start)
    if indexed_start < 0 or packed_start < 0 or mesh_draw_end < 0:
        fail("retained Metal 3D draw helper missing indexed or packed draw branches")
    indexed_draw = resource_text[indexed_start:packed_start]
    packed_draw = resource_text[packed_start:mesh_draw_end]
    indexed_rgba = "OrenAVMMetalRGBAValueWithOpacity(materialRGBA, opacity, rgba);"
    if indexed_draw.count(indexed_rgba) != 1:
        fail("indexed retained Metal 3D draws must convert constant RGBA exactly once")
    if "if (visibleTotal == 0) {\n            free(heapOrder);\n            return;\n        }" not in indexed_draw:
        fail("indexed retained Metal 3D draws must skip sort/color work when all triangles are clipped")
    require_before(indexed_draw,
                   "if (visibleTotal == 0) {\n            free(heapOrder);\n            return;\n        }",
                   indexed_rgba,
                   "indexed retained Metal 3D RGBA conversion must happen after the zero-visible fast return")
    if indexed_draw.find(indexed_rgba) > indexed_draw.find("for (uint32_t di = 0; di < visibleTotal; di++)"):
        fail("indexed retained Metal 3D RGBA conversion must happen before the triangle draw loop")
    if "BOOL hasConstantRGBA = hasMaterialRGBA || (meshStride == 36u && mesh.hasRGBA);" not in packed_draw:
        fail("packed retained Metal 3D draws must identify constant material/mesh RGBA once")
    if "OrenAVMMetalRGBAValueWithOpacity(hasMaterialRGBA ? materialRGBA : mesh.rgbaValue," not in packed_draw:
        fail("packed retained Metal 3D draws must convert constant material/mesh RGBA before drawing")
    if "if (visibleTotal == 0) {\n            free(heapOrder);\n            return;\n        }" not in packed_draw:
        fail("packed retained Metal 3D draws must skip sort/color work when all triangles are clipped")
    require_before(packed_draw,
                   "if (visibleTotal == 0) {\n            free(heapOrder);\n            return;\n        }",
                   "OrenAVMMetalRGBAValueWithOpacity(hasMaterialRGBA ? materialRGBA : mesh.rgbaValue,",
                   "packed retained Metal 3D constant RGBA conversion must happen after the zero-visible fast return")
    if packed_draw.find("OrenAVMMetalRGBAValueWithOpacity(hasMaterialRGBA ? materialRGBA : mesh.rgbaValue,") > packed_draw.find("for (uint32_t di = 0; di < visibleTotal; di++)"):
        fail("packed retained Metal 3D constant RGBA conversion must happen before the triangle draw loop")
    if "OrenAVMMetalAppendMesh3DResource(_orenMeshes3DByID" in text or "OrenAVMMetalTriangleOrder" in text:
        fail("retained Metal 3D draw block must not expand resource payloads in the view")
    if "unsignedIntValue" in mesh_command:
        fail("retained Metal material override must not unbox NSNumber values inside triangle loops")
    if "@interface OrenAVMMetalImageResource" not in metal_text:
        fail("retained Metal images must use typed resource objects")
    if "NSMutableDictionary<NSNumber*, id<MTLTexture>>* orenImageTextures" in text:
        fail("retained Metal images must not store bare texture values")
    if "orenImagePixels" in text:
        fail("retained Metal image pixel accounting must not use a parallel dictionary")
    if "NSMutableDictionary<NSNumber*, OrenAVMMetalImageResource*>* orenImages" in text:
        fail("retained Metal image lookups must avoid boxed NSNumber image IDs")
    if "CFMutableDictionaryRef _orenImagesByID" not in text:
        fail("retained Metal images must use a scalar-key CF dictionary")
    if ".images = &_orenImagesByID" not in text or "OrenAVMMetalHandleImageCommand(context->images," not in frame_text:
        fail("retained Metal image opcodes must delegate through frame traversal to the resource-owned command helper")
    if "BOOL OrenAVMMetalHandleImageCommand" not in resource_text:
        fail("retained Metal image command helper must live in OrenAVMMetalResources")
    if "OrenAVMMetalPutImageResource(imagesByID," not in resource_text:
        fail("retained Metal image uploads must use the resource-owned upload helper")
    if "OrenAVMMetalRemoveImageResource(imagesByID ? *imagesByID : NULL," not in resource_text:
        fail("retained Metal image removal must use the resource-owned removal helper")
    if "texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm" in text or "CFDictionarySetValue(_orenImagesByID" in text:
        fail("retained Metal image texture creation and map writes must live in OrenAVMMetalResources")
    if "CFDictionaryRemoveValue(_orenImagesByID" in text:
        fail("retained Metal image removals must live in OrenAVMMetalResources")
    if "OrenAVMMetalRetainedImageKey(imageID)" not in resource_text:
        fail("retained Metal image access must use the scalar image-id key helper")
    if "OrenAVMMetalRetainedImageResource(imagesByID ? *imagesByID : NULL" not in resource_text:
        fail("retained Metal image draw paths must use the typed scalar-map resource helper")
    if "@(imageID)" in text:
        fail("retained Metal image draw/upload paths must not box image IDs")
    put_image_start = resource_source_text.find("BOOL OrenAVMMetalPutImageResource")
    put_image_end = resource_source_text.find("void OrenAVMMetalRemoveImageResource", put_image_start)
    if put_image_start < 0 or put_image_end < 0:
        fail("missing retained Metal image upload helper")
    put_image_body = resource_source_text[put_image_start:put_image_end]
    image_map_alloc = put_image_body.find("CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks)")
    texture_alloc = put_image_body.find("[device newTextureWithDescriptor:descriptor]")
    texture_upload = put_image_body.find("[texture replaceRegion:")
    if image_map_alloc < 0 or texture_alloc < 0 or texture_upload < 0:
        fail("retained Metal image upload helper missing scalar map or texture upload path")
    if image_map_alloc > texture_alloc or image_map_alloc > texture_upload:
        fail("retained Metal image uploads must preflight scalar-map storage before allocating/filling MTLTexture")
    require_before(put_image_body,
                   "if (!resource) return NO;",
                   "CFDictionarySetValue(*imagesByID",
                   "retained Metal image uploads must guard resource allocation before map insertion")
    image_run_start = resource_text.find("@interface OrenAVMMetalImageRun")
    image_run_end = resource_text.find("@end", image_run_start)
    if image_run_start < 0 or image_run_end < 0:
        fail("missing Metal image run resource type")
    image_run_block = resource_text[image_run_start:image_run_end]
    if "@interface OrenAVMMetalImageRun : NSObject {\n@public\n    OrenAVMMetalTextVertex vertices[6];" not in image_run_block:
        fail("Metal image runs must store fixed quad vertices inline")
    if (
        "NSUInteger inlineVertexCount" not in image_run_block
        or "OrenAVMMetalTextVertex* heapVertices" not in image_run_block
        or "NSUInteger heapVertexCount" not in image_run_block
        or "NSUInteger heapVertexCapacity" not in image_run_block
    ):
        fail("Metal image runs must track initialized inline vertices and own raw heap vertex spans")
    if "free(heapVertices)" not in resource_text:
        fail("Metal batched image runs must free raw heap vertex spans")
    if "newCapacity *= 2u" not in resource_text or "run->heapVertexCapacity = newCapacity" not in resource_text:
        fail("Metal image heap vertex growth must be geometric for append/coalescing")
    if "realloc(run->heapVertices, neededCount * sizeof(OrenAVMMetalTextVertex))" in resource_text:
        fail("Metal image heap vertex reserve must not realloc to the exact requested count")
    if (
        "OrenAVMMetalImageRunAllocateExactHeapVertices(run, vertexCount)" not in resource_text
        or "static BOOL OrenAVMMetalImageRunAllocateExactHeapVertices" not in resource_text
    ):
        fail("known-size batched Metal image runs must allocate exact heap vertex storage once")
    if "@property(nonatomic, strong) NSData* vertices;" in image_run_block:
        fail("Metal image runs must not allocate NSData wrappers for single quads")
    if "OrenAVMMetalWriteTextureQuad(run->vertices" not in resource_text:
        fail("Metal image runs must write single-quad vertices directly into inline storage")
    if "run->inlineVertexCount = 6u;" not in resource_text:
        fail("Metal image single-quad runs must record initialized inline vertex count")
    if "return run->inlineVertexCount == 0 ? NULL : run->vertices;" not in resource_text:
        fail("Metal image run binding must not expose uninitialized inline vertex storage")
    if "run->heapVertexCount == 0 ? 6u : run->heapVertexCount" in resource_text:
        fail("Metal image run length must come from actual initialized inline or heap vertex count")
    if "NSMutableData* vertices = [NSMutableData dataWithCapacity:sizeof(OrenAVMMetalTextVertex) * 6u]" in text:
        fail("Metal image runs must not allocate mutable vertex data for one quad")
    if "OrenAVMMetalSubrectInTexture" not in frame_text or "OrenAVMMetalSubrectInTexture" not in resource_text:
        fail("retained Metal image sub-rect checks must use the overflow-safe helper")
    if "return sw > 0 && sh > 0 &&" not in frame_text:
        fail("retained Metal image sub-rect checks must reject zero source dimensions locally")
    if "orenImageRunWithID:" in text:
        fail("Metal image runs must be built from cached texture/dimensions, not ID lookups")
    if "OrenAVMMetalImageRunCreate(texture," not in resource_text:
        fail("missing cached-texture Metal image-run helper")
    image_run_start = resource_text.find("OrenAVMMetalImageRun* OrenAVMMetalImageRunCreate")
    image_run_end = resource_text.find("static BOOL OrenAVMMetalImageRectsHaveZeroSize", image_run_start)
    if image_run_start < 0 or image_run_end < 0:
        fail("missing Metal single image-run helper")
    image_run_body = resource_text[image_run_start:image_run_end]
    require_before(
        image_run_body,
        "if (!run) return nil;",
        "OrenAVMMetalWriteTextureQuad(run->vertices",
        "single Metal image run construction must guard run allocation before inline vertex writes",
    )
    image_command = resource_text[resource_text.find("BOOL OrenAVMMetalHandleImageCommand") :]
    for token in (
        "case 64:",
        "case 65:",
        "case 66:",
        "case 67:",
        "case 71:",
        "OrenAVMMetalImageRunCreate(texture,",
        "OrenAVMMetalRetainedImageResource(imagesByID ? *imagesByID : NULL",
    ):
        if token in text:
            fail("retained Metal image opcode expansion must not live in OrenAVMMetalView")
        if token not in image_command:
            fail(f"retained Metal image command helper missing expected path: {token}")
    for token in (
        "case 65: {\n            if (opacity <= 0.0f) return YES;",
        "case 67: {\n            if (opacity <= 0.0f) return YES;",
        "case 71: {\n            if (opacity <= 0.0f) return YES;",
    ):
        if token not in image_command:
            fail(f"retained Metal image draw opcode must skip fully transparent texture work: {token}")
    batched_images = image_command.find("case 71:")
    if batched_images < 0:
        fail("missing batched Metal image-rect path")
    batched_block = image_command[batched_images:image_command.find("default:", batched_images)]
    if "NSUInteger textureWidth = texture.width;" not in batched_block or "NSUInteger textureHeight = texture.height;" not in batched_block:
        fail("batched Metal image-rect draws must cache texture dimensions once")
    if "for (uint32_t ri" in batched_block:
        fail("batched Metal image-rect commands must not append one image run per rect")
    if "OrenAVMMetalImageBatchRunCreate(texture," not in batched_block:
        fail("batched Metal image-rect commands must create one raw vertex batch run")
    single_image_start = image_command.find("case 65:")
    single_image_end = image_command.find("case 66:", single_image_start)
    subrect_image_start = image_command.find("case 67:")
    subrect_image_end = image_command.find("case 71:", subrect_image_start)
    if single_image_start < 0 or single_image_end < 0 or subrect_image_start < 0 or subrect_image_end < 0:
        fail("missing retained Metal image draw preflight paths")
    single_image_body = image_command[single_image_start:single_image_end]
    subrect_image_body = image_command[subrect_image_start:subrect_image_end]
    require_before(
        single_image_body,
        "if (dw == 0 || dh == 0) return YES;",
        "OrenAVMMetalRetainedImageResource(imagesByID ? *imagesByID : NULL",
        "retained Metal image draws must reject zero destinations before retained image lookup",
    )
    require_before(
        subrect_image_body,
        "if (sw == 0 || sh == 0 || dw == 0 || dh == 0) return YES;",
        "OrenAVMMetalRetainedImageResource(imagesByID ? *imagesByID : NULL",
        "retained Metal image subrect draws must reject zero dimensions before retained image lookup",
    )
    require_before(
        batched_block,
        "if (OrenAVMMetalImageRectsHaveZeroSize(payload + 8, rectCount)) return YES;",
        "OrenAVMMetalRetainedImageResource(imagesByID ? *imagesByID : NULL",
        "retained Metal batched image draws must reject zero-size rects before retained image lookup",
    )
    image_batch_start = resource_text.find("OrenAVMMetalImageRun* OrenAVMMetalImageBatchRunCreate")
    image_batch_end = resource_text.find("OrenAVMMetalImageRunVertexBytes", image_batch_start)
    if image_batch_start < 0 or image_batch_end < 0:
        fail("missing Metal image batch-run helper")
    image_batch_body = resource_text[image_batch_start:image_batch_end]
    require_before(
        image_batch_body,
        "if (!run) return nil;",
        "OrenAVMMetalImageRunAllocateExactHeapVertices(run, vertexCount)",
        "batched Metal image run construction must guard run allocation before heap vertex allocation",
    )
    for token in (
        "uint32_t dx = OrenAVMMetalReadU32LE(r + 16);",
        "uint32_t dy = OrenAVMMetalReadU32LE(r + 20);",
        "uint32_t dw = OrenAVMMetalReadU32LE(r + 24);",
        "uint32_t dh = OrenAVMMetalReadU32LE(r + 28);",
        "if (dw == 0 || dh == 0) return nil;",
    ):
        if token not in image_batch_body:
            fail(f"Metal batched image-rect helper missing local destination validation: {token}")
    require_before(
        image_batch_body,
        "if (dw == 0 || dh == 0) return nil;",
        "OrenAVMMetalImageRunAllocateExactHeapVertices(run, vertexCount)",
        "Metal batched image-rect helper must validate destination sizes before heap vertex allocation",
    )
    require_before(
        image_batch_body,
        "if (!OrenAVMMetalSubrectInTexture(sx, sy, sw, sh, textureWidth, textureHeight)) return nil;",
        "OrenAVMMetalImageRunAllocateExactHeapVertices(run, vertexCount)",
        "Metal batched image-rect helper must validate source subrects before heap vertex allocation",
    )
    if image_batch_body.count("if (dw == 0 || dh == 0) return nil;") != 1:
        fail("Metal batched image-rect helper must validate destination sizes once in the preflight pass")
    if image_batch_body.count("if (!OrenAVMMetalSubrectInTexture(sx, sy, sw, sh, textureWidth, textureHeight)) return nil;") != 1:
        fail("Metal batched image-rect helper must validate source subrects once in the preflight pass")
    if "OrenAVMMetalImageRunVertexBytes(run)" not in frame_text or "OrenAVMMetalImageRunVertexCount(run)" not in frame_text:
        fail("Metal image encoding must draw inline or batched image runs from their actual vertex span")
    if "NSArray<OrenAVMMetalImageRun*>* OrenAVMMetalCoalesceImageRuns" not in resource_text:
        fail("Metal image runs must expose prepared-frame coalescing")
    image_coalesce_start = resource_text.find("NSArray<OrenAVMMetalImageRun*>* OrenAVMMetalCoalesceImageRuns")
    image_coalesce_end = resource_text.find("static BOOL OrenAVMMetalAppendImageRun", image_coalesce_start)
    if image_coalesce_start < 0 or image_coalesce_end < 0:
        fail("missing Metal image run coalescing helper body")
    image_coalesce_body = resource_text[image_coalesce_start:image_coalesce_end]
    if "pending = [[OrenAVMMetalImageRun alloc] init]" in image_coalesce_body:
        fail("image coalescing must reuse prepared run objects instead of cloning every run")
    for token in (
        "pending = run;",
        "if (!out) return runs;",
        "[NSMutableArray arrayWithCapacity:OrenAVMMetalRunArrayInitialCapacity(runs.count)]",
        "pending.texture == run.texture",
        "pending.opacity == run.opacity",
        "OrenAVMMetalImageScissorEqual(pending, run)",
        "OrenAVMMetalEnsureHeapImageVerticesForCoalescing(pending)",
        "OrenAVMMetalImageRunAppendVertices(pending,",
        "pending->inlineVertexCount == 0",
        "pending->inlineVertexCount = 0",
    ):
        if token not in image_coalesce_body:
            fail(f"Metal image coalescing missing expected path: {token}")
    image_append_start = resource_text.find("static BOOL OrenAVMMetalAppendImageRun")
    image_append_end = resource_text.find("BOOL OrenAVMMetalHandleImageCommand", image_append_start)
    if image_append_start < 0 or image_append_end < 0:
        fail("missing checked Metal image run append helper")
    image_append_body = resource_text[image_append_start:image_append_end]
    for token in (
        "NSMutableArray* runs = OrenAVMMetalEnsureRunArray((NSMutableArray**)imageRuns, runCapacity);",
        "if (!runs) return NO;",
        "[runs addObject:run];",
    ):
        if token not in image_append_body:
            fail(f"Metal image run append must check lazy run-array allocation: {token}")
    if "@interface OrenAVMMetalModelResource" not in metal_text:
        fail("retained Metal models must use typed resource objects")
    if 'NSMutableDictionary<NSNumber*, NSDictionary<NSString*, NSNumber*>*>* orenModels3D' in text:
        fail("retained Metal models must not use dictionary payload records")
    if 'NSMutableDictionary<NSNumber*, OrenAVMMetalModelResource*>* orenModels3D' in text:
        fail("retained Metal model lookups must avoid boxed NSNumber model IDs")
    if "CFMutableDictionaryRef _orenModels3DByID" not in text:
        fail("retained Metal models must use a scalar-key CF dictionary")
    if "OrenAVMMetalRetainedModelResource(models, meshID)" not in resource_text:
        fail("retained Metal model draws must use the typed scalar-map resource helper")
    if "OrenAVMMetalPutModelResource(models," not in resource_text:
        fail("retained Metal model uploads must use the resource-owned upload helper")
    if "OrenAVMMetalRemoveModelResource(models ? *models : NULL" not in resource_text:
        fail("retained Metal model removals must use the resource-owned removal helper")
    put_model_start = resource_source_text.find("BOOL OrenAVMMetalPutModelResource")
    put_model_end = resource_source_text.find("void OrenAVMMetalRemoveModelResource", put_model_start)
    if put_model_start < 0 or put_model_end < 0:
        fail("missing retained Metal model upload helper")
    put_model_body = resource_source_text[put_model_start:put_model_end]
    require_before(put_model_body,
                   "OrenAVMMetalEnsureRetainedResourceMap(models)",
                   "[[OrenAVMMetalModelResource alloc] init]",
                   "retained Metal model uploads must preflight scalar-map storage before resource allocation")
    require_before(put_model_body,
                   "if (!model) return NO;",
                   "CFDictionarySetValue(*models",
                   "retained Metal model uploads must guard resource allocation before map insertion")
    if "CFDictionarySetValue(_orenModels3DByID" in text or "CFDictionaryRemoveValue(_orenModels3DByID" in text:
        fail("retained Metal model map mutation must live in OrenAVMMetalResources")
    if 'model[@"mesh_id"]' in text or '@"scale_milli"' in text:
        fail("retained Metal model draws must not use string-key dictionary lookups")
    if "OrenAVMMetalFrameBuildContext context" not in text or "OrenAVMMetalBuildVertexRunsForFrame(frame," not in text:
        fail("Metal view must delegate OGF0 command traversal to the frame helper")
    if "memcmp(data, \"OGF0\", 4)" in text or "uint32_t opCount = OrenAVMMetalReadU32LE(data + 20)" in text:
        fail("Metal view must not inline OGF0 frame command traversal")
    if "NSArray<OrenAVMMetalVertexRun*>* OrenAVMMetalBuildVertexRunsForFrame" not in frame_text:
        fail("Metal frame traversal helper must live in OrenAVMMetalFrame")
    if "OrenAVMMetalFrameState frameState" not in frame_text or "OrenAVMMetalFrameStateInit(&frameState)" not in frame_text:
        fail("Metal frame traversal must use the frame-owned state container")
    clear_call = "OrenAVMMetalApplyClearColorCommand(opcode, payload, payloadLen, logicalW, logicalH, frameState.opacity, clearColor)"
    clear_guard = "if (!frameState.clip.enabled && frameState.tx == 0.0f && frameState.ty == 0.0f)"
    if clear_call not in frame_text:
        fail("Metal full-frame clear-color detection must delegate to the frame helper")
    if clear_guard not in frame_text:
        fail("Metal full-frame clear-color detection must require unclipped, untranslated frame state")
    if "BOOL clearHandled = NO;" not in frame_text:
        fail("Metal full-frame clear-color detection must retain the helper result for duplicate-fill elision")
    if "static BOOL OrenAVMMetalHasPreparedDrawWork(NSMutableArray<OrenAVMMetalVertexRun*>* vertexRuns," not in frame_text:
        fail("Metal full-frame clear-color elision must use a prepared-draw-work helper")
    clear_skip = "if (clearHandled && !OrenAVMMetalHasPreparedDrawWork(vertexRuns, &vertices, textRuns, imageRuns))"
    if clear_skip not in frame_text:
        fail("Metal full-frame clear-color elision must skip only leading clear fills with no prepared draw work")
    require_before(
        frame_text,
        clear_guard,
        clear_call,
        "Metal full-frame clear-color detection must guard clip/translation before applying clear color",
    )
    require_before(
        frame_text,
        clear_call,
        clear_skip,
        "Metal full-frame clear-color elision must run after successful helper detection",
    )
    require_before(
        frame_text,
        clear_skip,
        "BOOL primitiveHandled = OrenAVMMetalAppendPrimitiveCommand(opcode,",
        "Metal leading clear fills must skip duplicate primitive vertex emission",
    )
    if "BOOL OrenAVMMetalApplyClearColorCommand" not in frame_text:
        fail("Metal clear-color command helper must live in OrenAVMMetalFrame")
    clear_command = frame_text[frame_text.find("BOOL OrenAVMMetalApplyClearColorCommand") :]
    for token in (
        "opcode != 1",
        "payloadLen != 20",
        "opacity < 0.999f",
        "OrenAVMMetalRGBAWithOpacity(payload + 16, opacity, clearRGBA)",
        "if (clearRGBA[3] != 255) return NO;",
        "MTLClearColorMake",
    ):
        if token not in clear_command:
            fail(f"Metal clear-color command helper missing expected path: {token}")
    if "uint8_t clearRGBA[4]" in text or "OrenAVMMetalRGBAWithOpacity(payload + 16" in text:
        fail("Metal view must not inline clear-color payload decoding")
    mesh2d_draw_start = resource_source_text.find("void OrenAVMMetalAppendMesh2DResource")
    mesh3d_draw_start = resource_source_text.find("void OrenAVMMetalAppendMesh3DResource")
    mesh_draw_end = resource_source_text.find("BOOL OrenAVMMetalHandleMeshCommand", mesh3d_draw_start)
    if mesh2d_draw_start < 0 or mesh3d_draw_start < 0 or mesh_draw_end < 0:
        fail("missing retained Metal mesh draw helper blocks")
    mesh2d_draw_body = resource_source_text[mesh2d_draw_start:mesh3d_draw_start]
    mesh3d_draw_body = resource_source_text[mesh3d_draw_start:mesh_draw_end]
    for block, token in (
        (mesh2d_draw_body, "if (!mesh || !vertices || opacity <= 0.0f) return;"),
        (mesh3d_draw_body, "if (!payload || !vertices || opacity <= 0.0f) return;"),
    ):
        if token not in block:
            fail(f"retained Metal mesh/model draws must skip fully transparent work before resource expansion: {token}")
    if "OrenAVMMetalHandleFrameStateCommand(opcode," not in frame_text:
        fail("Metal frame traversal must delegate state-stack opcodes to the frame-owned command helper")
    if "BOOL OrenAVMMetalHandleFrameStateCommand" not in frame_text:
        fail("Metal state-stack command helper must live in OrenAVMMetalFrame")
    state_command = frame_text[frame_text.find("BOOL OrenAVMMetalHandleFrameStateCommand") :]
    for token in (
        "case 16:",
        "case 17:",
        "case 18:",
        "case 19:",
        "case 20:",
        "case 21:",
        "case 22:",
        "case 23:",
        "OrenAVMMetalFlushVertexRun(runsRef, verticesRef, runCapacity, state->clip, YES)",
    ):
        if token not in state_command:
            fail(f"Metal frame-state command helper missing expected path: {token}")
    state_case_markers = ["case 16:", "case 17:", "case 18:", "case 19:", "case 20:", "case 21:", "case 22:", "case 23:", "default:"]
    state_cases = {}
    for idx, marker in enumerate(state_case_markers[:-1]):
        start = state_command.find(marker)
        end = state_command.find(state_case_markers[idx + 1], start + len(marker))
        if start < 0 or end < 0:
            fail(f"missing Metal frame-state case block: {marker}")
        state_cases[marker] = state_command[start:end]
    for label, marker in (
        ("clip push", "case 16:"),
        ("transform push", "case 18:"),
        ("opacity push", "case 20:"),
        ("camera push", "case 22:"),
    ):
        require_before(
            state_cases[marker],
            "if (OrenAVMMetalPushState(state,",
            "OrenAVMMetalFlushVertexRun(runsRef, verticesRef, runCapacity, state->clip, YES)",
            f"Metal {label} must avoid flushing when the typed state stack overflows",
        )
    for label, marker in (
        ("clip pop", "case 17:"),
        ("transform pop", "case 19:"),
        ("opacity pop", "case 21:"),
        ("camera pop", "case 23:"),
    ):
        require_before(
            state_cases[marker],
            "OrenAVMMetalPopResult pop = OrenAVMMetalPopState(state,",
            "OrenAVMMetalFlushVertexRun(runsRef, verticesRef, runCapacity, state->clip, YES)",
            f"Metal {label} must avoid flushing on overflow no-op or mismatched pops",
        )
    for token in ("clipStack[64]", "txStack[64]", "opacityStack[64]", "depthEnabledStack[64]"):
        if token in text:
            fail("Metal view must not own frame state stacks directly")
    for token in (
        "uint8_t stateStack[OrenAVMMetalFrameStateStackCapacity]",
        "uint32_t stateDepth",
        "uint32_t stateOverflowDepth",
        "OrenAVMMetalPushState",
        "OrenAVMMetalPopState",
        "OrenAVMMetalStateKindClip",
        "OrenAVMMetalStateKindTransform",
        "OrenAVMMetalStateKindOpacity",
        "OrenAVMMetalStateKindCamera",
        "state->stateOverflowDepth++",
        "state->stateOverflowDepth--",
        "state->stateStack[state->stateDepth - 1] != kind",
    ):
        if token not in frame_text:
            fail(f"Metal typed frame-state stack handling missing expected path: {token}")
    for token in (
        "clipOverflowDepth",
        "transformOverflowDepth",
        "opacityOverflowDepth",
        "cameraOverflowDepth",
    ):
        if token in frame_text:
            fail("Metal frame-state overflow must use the shared typed stack, not per-kind counters")
    if "OrenAVMMetalFlushVertexRun(&vertexRuns, &vertices, runCapacity, frameState.clip, NO)" not in frame_text:
        fail("final geometry vertex-run flush must avoid allocating a replacement builder")
    for token in (
        "static BOOL OrenAVMMetalScissorIsEmpty(OrenAVMMetalScissorState clip)",
        "static BOOL OrenAVMMetalOpcodeIsDrawOnly(uint8_t opcode)",
        "case 1:",
        "case 2:",
        "case 65:",
        "case 72:",
        "case 81:",
        "case 94:",
    ):
        if token not in frame_text:
            fail(f"Metal elided draw skip missing expected draw opcode coverage: {token}")
    build_runs = frame_text[frame_text.find("NSArray<OrenAVMMetalVertexRun*>* OrenAVMMetalBuildVertexRunsForFrame") :]
    require_before(
        build_runs,
        "(OrenAVMMetalScissorIsEmpty(frameState.clip) || frameState.opacity <= 0.0f) &&\n            OrenAVMMetalOpcodeIsDrawOnly(opcode)",
        "BOOL primitiveHandled = OrenAVMMetalAppendPrimitiveCommand(opcode,",
        "Metal frame traversal must skip clip/opacity-elided draw work before vertex/resource/text preparation",
    )
    if "OrenAVMMetalEncodePreparedRuns(encoder," not in text:
        fail("Metal view must delegate prepared-run draw submission to the frame helper")
    if "void OrenAVMMetalEncodePreparedRuns" not in frame_text:
        fail("Metal prepared-run draw submission helper must live in OrenAVMMetalFrame")
    encode_runs = frame_text[frame_text.find("void OrenAVMMetalEncodePreparedRuns") :]
    for token in (
        "MTLScissorRect fullScissor",
        "BOOL hasLastScissor = NO;",
        "MTLScissorRect lastScissor = {0, 0, 0, 0};",
        "OrenAVMMetalApplyScissorIfNeeded(encoder, scissor, &hasLastScissor, &lastScissor)",
        "id<MTLTexture> lastFragmentTexture = nil;",
        "BOOL hasLastFragmentOpacity = NO;",
        "float lastFragmentOpacity = 0.0f;",
        "OrenAVMMetalApplyFragmentTextureIfNeeded(encoder, run.texture, &lastFragmentTexture)",
        "OrenAVMMetalApplyFragmentOpacityIfNeeded(encoder, run.opacity, &hasLastFragmentOpacity, &lastFragmentOpacity)",
        "id<MTLRenderPipelineState> currentPipeline = nil;",
        "if (geometryPipeline && vertexRuns.count > 0)",
        "BOOL hasTextureRuns = imageRuns.count > 0 || textRuns.count > 0;",
        "if (textPipeline && hasTextureRuns)",
        "for (OrenAVMMetalImageRun* run in imageRuns)",
        "for (OrenAVMMetalTextRun* run in textRuns)",
        "OrenAVMMetalBindVertexPayload(encoder, device, transientBuffers",
        "OrenAVMMetalApplyPipelineIfNeeded(encoder, geometryPipeline, &currentPipeline)",
        "OrenAVMMetalApplyPipelineIfNeeded(encoder, textPipeline, &currentPipeline)",
        "[encoder drawPrimitives:MTLPrimitiveTypeTriangle",
    ):
        if token not in encode_runs:
            fail(f"Metal prepared-run draw submission helper missing expected path: {token}")
    for token in (
        "[encoder drawPrimitives:MTLPrimitiveTypeTriangle",
        "[encoder setFragmentTexture:",
        "OrenAVMMetalBindVertexPayload(encoder, self.device",
        "MTLScissorRect fullScissor",
    ):
        if token in text:
            fail("Metal view must not own prepared-run encoder draw loops")
    if "static void OrenAVMMetalApplyScissorIfNeeded" not in frame_text:
        fail("Metal prepared-run encoding must cache repeated scissor state")
    if frame_text.count("[encoder setScissorRect:scissor]") != 1:
        fail("Metal prepared-run encoding must set scissor only through the cached helper")
    if "static void OrenAVMMetalApplyFragmentTextureIfNeeded" not in frame_text:
        fail("Metal prepared-run encoding must cache repeated fragment texture state")
    if "static void OrenAVMMetalApplyFragmentOpacityIfNeeded" not in frame_text:
        fail("Metal prepared-run encoding must cache repeated fragment opacity state")
    if frame_text.count("[encoder setFragmentTexture:texture atIndex:0]") != 1:
        fail("Metal prepared-run encoding must set fragment textures only through the cached helper")
    if frame_text.count("[encoder setFragmentBytes:&opacity length:sizeof(opacity) atIndex:0]") != 1:
        fail("Metal prepared-run encoding must set fragment opacity only through the cached helper")
    if "static void OrenAVMMetalApplyPipelineIfNeeded" not in frame_text:
        fail("Metal prepared-run encoding must cache the currently bound render pipeline")
    if frame_text.count("[encoder setRenderPipelineState:pipeline]") != 1:
        fail("Metal prepared-run encoding must set render pipelines only through the cached helper")
    if "[encoder setRenderPipelineState:geometryPipeline]" in encode_runs or "[encoder setRenderPipelineState:textPipeline]" in encode_runs:
        fail("Metal prepared-run encoding must not bypass the cached pipeline helper")
    require_before(encode_runs,
                   "OrenAVMMetalBindVertexPayload(encoder, device, transientBuffers, run.vertices, run.vertexBytes)",
                   "OrenAVMMetalApplyPipelineIfNeeded(encoder, geometryPipeline, &currentPipeline)",
                   "Metal geometry pipeline binding must stay lazy until after valid vertex payload binding")
    require_before(encode_runs,
                   "OrenAVMMetalBindVertexPayload(encoder, device, transientBuffers, OrenAVMMetalImageRunVertexBytes(run), vertexBytes)",
                   "OrenAVMMetalApplyPipelineIfNeeded(encoder, textPipeline, &currentPipeline)",
                   "Metal image pipeline binding must stay lazy until after valid vertex payload binding")
    if "OrenAVMMetalFrameRunCapacity(NSData* frame)" not in frame_text:
        fail("missing bounded Metal frame run-capacity helper")
    if text.count("OrenAVMMetalFrameRunCapacity(") != 1:
        fail("expected one prepare-frame call to the frame run-capacity helper")
    if "NSArray<OrenAVMMetalVertexRun*>* coalescedVertexRuns = OrenAVMMetalCoalesceVertexRuns(vertexRuns)" not in text:
        fail("Metal prepared frames must coalesce geometry runs before metrics and draw submission")
    if "for (OrenAVMMetalVertexRun* run in coalescedVertexRuns)" not in text or "return coalescedVertexRuns" not in text:
        fail("Metal geometry-run metrics and draw submission must use coalesced vertex runs")
    if "NSArray<OrenAVMMetalImageRun*>* coalescedImageRuns = imageRuns ? OrenAVMMetalCoalesceImageRuns(imageRuns) : @[]" not in text:
        fail("Metal prepared frames must coalesce image runs before metrics and draw submission")
    if "self.lastFrameImageRunCount = (uint32_t)coalescedImageRuns.count" not in text or "if (imageRunsOut) *imageRunsOut = coalescedImageRuns" not in text:
        fail("Metal image-run metrics and outputs must use coalesced image runs")
    if "NSMutableArray* OrenAVMMetalEnsureRunArray" not in frame_text:
        fail("missing lazy Metal text/image run-array helper")
    if (
        "OrenAVMMetalRunArrayMaxInitialCapacity = 4096u" not in frame_text
        or "OrenAVMMetalRunArrayInitialCapacity(capacity)" not in frame_text
        or "NSUInteger OrenAVMMetalRunArrayInitialCapacity(NSUInteger capacity)" not in frame_text
        or "[NSMutableArray arrayWithCapacity:OrenAVMMetalRunArrayInitialCapacity(capacity)]" not in frame_text
    ):
        fail("lazy Metal run arrays must cap initial reservation instead of using full frame-derived capacity")
    if "[NSMutableArray arrayWithCapacity:runs.count]" in metal_text:
        fail("Metal coalescing must not reserve full run-list capacity")
    eager_run_arrays = [
        "NSMutableArray<OrenAVMMetalVertexRun*>* vertexRuns = [NSMutableArray arrayWithCapacity:runCapacity]",
        "NSMutableArray<OrenAVMMetalTextRun*>* textRuns = [NSMutableArray arrayWithCapacity:runCapacity]",
        "NSMutableArray<OrenAVMMetalImageRun*>* imageRuns = [NSMutableArray arrayWithCapacity:runCapacity]",
    ]
    for pattern in eager_run_arrays:
        if pattern in metal_text:
            fail("geometry/text/image run arrays must be allocated lazily, not eagerly from runCapacity")
    if "[NSMutableArray arrayWithCapacity:runCapacity]" in metal_text:
        fail("Metal frame run arrays must use lazy OrenAVMMetalEnsureRunArray allocation")
    if metal_text.count("OrenAVMMetalEnsureRunArray(") < 5:
        fail("expected lazy run-array helper calls for geometry/text/image add sites")
    text_append_start = resource_text.find("static BOOL OrenAVMMetalAppendTextRun")
    text_append_end = resource_text.find("BOOL OrenAVMMetalHandleTextCommand", text_append_start)
    if text_append_start < 0 or text_append_end < 0:
        fail("missing checked Metal text run append helper")
    text_append_body = resource_text[text_append_start:text_append_end]
    for token in (
        "NSMutableArray* runs = OrenAVMMetalEnsureRunArray((NSMutableArray**)textRuns, runCapacity);",
        "if (!runs) return NO;",
        "[runs addObject:run];",
    ):
        if token not in text_append_body:
            fail(f"Metal text run append must check lazy run-array allocation: {token}")

    in_helper = False
    saw_helper_body = False
    helper_depth = 0
    helper_set_vertex_bytes = 0
    direct_calls: list[str] = []
    helper_bind_calls = 0

    for lineno, line in enumerate(frame_source.splitlines(), start=1):
        if HELPER in line:
            in_helper = True
            saw_helper_body = False
            helper_depth = 0

        if "setVertexBytes:" in line:
            if in_helper:
                helper_set_vertex_bytes += 1
            else:
                direct_calls.append(f"{FRAME_SOURCE}:{lineno}: {line.strip()}")

        if in_helper:
            if "{" in line:
                saw_helper_body = True
            helper_depth += line.count("{") - line.count("}")
            if saw_helper_body and helper_depth <= 0:
                in_helper = False

    helper_bind_calls = frame_text.count("OrenAVMMetalBindVertexPayload(encoder, device, transientBuffers")
    for lineno, line in enumerate(text.splitlines(), start=1):
        if "setVertexBytes:" in line:
            direct_calls.append(f"{SOURCE}:{lineno}: {line.strip()}")

    if direct_calls:
        fail("direct setVertexBytes calls outside helper:\n" + "\n".join(direct_calls))
    if helper_set_vertex_bytes != 1:
        fail(f"expected exactly one helper setVertexBytes call, found {helper_set_vertex_bytes}")
    if helper_bind_calls < 3:
        fail(f"expected geometry/image/text helper bindings, found {helper_bind_calls}")

    print("OK: Metal frame hot paths use bounded helpers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
