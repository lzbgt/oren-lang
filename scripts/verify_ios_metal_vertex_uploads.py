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


def main() -> int:
    text = SOURCE.read_text()
    frame_header = FRAME_HEADER.read_text()
    frame_source = FRAME_SOURCE.read_text()
    frame_text = frame_header + "\n" + frame_source
    geometry_text = GEOMETRY_HEADER.read_text() + "\n" + GEOMETRY_SOURCE.read_text()
    resource_text = RESOURCE_HEADER.read_text() + "\n" + RESOURCE_SOURCE.read_text()
    pipeline_text = PIPELINE_HEADER.read_text() + "\n" + PIPELINE_SOURCE.read_text()
    metal_text = text + "\n" + frame_text + "\n" + geometry_text + "\n" + resource_text
    text_source = TEXT_SOURCE.read_text()
    text_header = TEXT_HEADER.read_text()
    if '"OrenAVMMetalFrame.h"' not in text:
        fail("Metal frame/run helpers must be imported through OrenAVMMetalFrame")
    if "OrenAVMMetalInlineVertexBytesLimit" not in frame_text:
        fail("missing inline vertex upload limit")
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
    if "OrenAVMMetalVertexBuffer vertices;" not in text or "OrenAVMMetalEnsureVertexBuilder(&vertices, runCapacity)" not in text:
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
    if "OrenAVMMetalInitialVertexBuilderCapacity" not in frame_text or "const NSUInteger maxInitialBytes = 64u * 1024u" not in frame_text:
        fail("geometry vertex builder must cap its lazy initial reservation")
    if '"OrenAVMMetalGeometry.h"' not in text or "OrenAVMMetalAppendRoundRect" not in geometry_text:
        fail("Metal primitive geometry helpers must live in OrenAVMMetalGeometry")
    if "static void OrenAVMMetalAppendRoundRect" in text or "static void OrenAVMMetalAppendCircle" in text:
        fail("Metal view must not inline primitive geometry append helpers")
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
    cache_lookup = text_source.find("OrenAVMMetalTextCacheEntry* cached = cache[cacheKey]")
    attrs_lookup = text_source.find("OrenAVMMetalTextAttributesForRGBA(attributesCache, rgba)")
    if cache_lookup < 0 or attrs_lookup < 0 or cache_lookup > attrs_lookup:
        fail("Metal text cache hits must return before looking up UIKit attributes")
    if "OrenAVMMetalTextAttributeCacheEntryLimit = 256u" not in text_source:
        fail("Metal text attribute cache must stay bounded")
    if "OrenAVMMetalTextAttributeCache* orenTextAttributes" not in text:
        fail("Metal text attributes must be cached through a typed view-owned cache")
    if text.count("self.orenTextAttributes") < 4:
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
    if "OrenAVMMetalClearTextAtlasPadding" not in text_source:
        fail("Metal text atlases must clear only sampled glyph padding")
    if "dataWithLength:OrenAVMMetalTextAtlasSize * OrenAVMMetalTextAtlasSize * 4u" in text_source:
        fail("Metal text atlas creation must not allocate a full zero buffer")
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
    if "dataWithBytes:payload + 4 length:4" in metal_text:
        fail("retained Metal RGBA fields must stay scalar instead of allocating NSData wrappers")
    if "@property(nonatomic) uint32_t rgbaValue" not in metal_text or "@property(nonatomic) uint32_t rgbaValue" not in text_header:
        fail("missing scalar RGBA storage for retained Metal mesh/text resources")
    for helper in (
        "OrenAVMMetalRetainedImageKey",
        "OrenAVMMetalRetainedImageResource",
        "OrenAVMMetalRetainedTextKey",
        "OrenAVMMetalRetainedTextResource",
        "OrenAVMMetalRetainedMeshKey",
        "OrenAVMMetalRetainedMesh2DResource",
        "OrenAVMMetalRetainedMesh3DResource",
        "OrenAVMMetalRetainedMaterialKey",
        "OrenAVMMetalRetainedMaterialValue",
        "OrenAVMMetalRetainedMaterialRGBA",
        "OrenAVMMetalRetainedModelKey",
        "OrenAVMMetalRetainedModelResource",
    ):
        if helper not in resource_text:
            fail(f"retained Metal scalar resource helper must live in OrenAVMMetalResources: {helper}")
    if "static const void* OrenAVMMetalRetainedImageKey" in text or "static OrenAVMMetalImageResource* OrenAVMMetalRetainedImageResource" in text:
        fail("Metal view must not define retained image scalar-map helpers")
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
    if "OrenAVMMetalRetainedMesh2DResource(_orenMeshesByID, OrenAVMMetalReadU32LE(payload))" not in text:
        fail("retained Metal 2D mesh draws must use the scalar-map resource helper")
    if "OrenAVMMetalRetainedMesh3DResource(_orenMeshes3DByID, meshID)" not in text:
        fail("retained Metal 3D mesh draws must use the scalar-map resource helper")
    if "NSMutableDictionary<NSNumber*, OrenAVMMetalTextResource*>* orenTextResources" in text:
        fail("retained Metal text lookups must avoid boxed NSNumber text IDs")
    if "CFMutableDictionaryRef _orenTextResourcesByID" not in text:
        fail("retained Metal text resources must use a scalar-key CF dictionary")
    if "OrenAVMMetalRetainedTextResource(_orenTextResourcesByID, textID)" not in text:
        fail("retained Metal text draws must use the typed scalar-map resource helper")
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
    if "OrenAVMMetalInlineTriangleOrderCapacity = 128" not in text:
        fail("retained Metal 3D triangle ordering must have a small stack buffer")
    if "OrenAVMMetalTriangleOrderBuffer(uint32_t triangleCount,\n                                                                  OrenAVMMetalTriangleOrder* inlineOrder" not in text:
        fail("retained Metal 3D triangle ordering must try inline storage before heap storage")
    if text.count("OrenAVMMetalTriangleOrder inlineOrder[OrenAVMMetalInlineTriangleOrderCapacity]") < 2:
        fail("retained Metal 3D draw paths must pass stack triangle-order buffers")
    if "NSMutableData* orderData" in text or "dataWithLength:(NSUInteger)triangleCount * sizeof(OrenAVMMetalTriangleOrder)" in text:
        fail("retained Metal 3D triangle ordering must not use NSMutableData heap fallbacks")
    if "OrenAVMMetalTriangleOrder* heapOrder = NULL" not in text or "free(heapOrder)" not in text:
        fail("retained Metal 3D triangle ordering must free raw heap fallbacks")
    if "NSMutableDictionary<NSNumber*, NSNumber*>* orenMaterials3D" in text:
        fail("retained Metal materials must avoid boxed NSNumber IDs/RGBA values")
    if "CFMutableDictionaryRef _orenMaterials3DByID" not in text:
        fail("retained Metal materials must use a scalar-key/scalar-value CF dictionary")
    if "OrenAVMMetalRetainedMaterialRGBA(_orenMaterials3DByID, materialID, &materialRGBAOverride)" not in text:
        fail("retained Metal material draws must use the scalar material lookup helper")
    if "materialRGBAValue" in text or "@(materialID)" in text:
        fail("retained Metal material paths must not box material IDs or RGBA values")
    retained_3d_start = text.find("} else if ((opcode == 84")
    retained_3d_end = text.find("} else if (opcode == 85", retained_3d_start)
    if retained_3d_start < 0 or retained_3d_end < 0:
        fail("missing retained Metal 3D draw block")
    retained_3d_block = text[retained_3d_start:retained_3d_end]
    if "uint32_t materialRGBA = hasMaterialRGBA ? materialRGBAOverride : mesh.rgbaValue;" not in retained_3d_block:
        fail("retained Metal material overrides must resolve once per draw")
    if "unsignedIntValue" in retained_3d_block:
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
    if "OrenAVMMetalRetainedImageKey(imageID)" not in text:
        fail("retained Metal image access must use the scalar image-id key helper")
    if "OrenAVMMetalRetainedImageResource(_orenImagesByID, imageID)" not in text:
        fail("retained Metal image draw paths must use the typed scalar-map resource helper")
    if "@(imageID)" in text:
        fail("retained Metal image draw/upload paths must not box image IDs")
    image_run_start = resource_text.find("@interface OrenAVMMetalImageRun")
    image_run_end = resource_text.find("@end", image_run_start)
    if image_run_start < 0 or image_run_end < 0:
        fail("missing Metal image run resource type")
    image_run_block = resource_text[image_run_start:image_run_end]
    if "@interface OrenAVMMetalImageRun : NSObject {\n@public\n    OrenAVMMetalTextVertex vertices[6];" not in image_run_block:
        fail("Metal image runs must store fixed quad vertices inline")
    if "@property(nonatomic, strong) NSData* vertices;" in image_run_block:
        fail("Metal image runs must not allocate NSData wrappers for single quads")
    if "OrenAVMMetalWriteTextureQuad(run->vertices" not in text:
        fail("Metal image runs must write single-quad vertices directly into inline storage")
    if "NSMutableData* vertices = [NSMutableData dataWithCapacity:sizeof(OrenAVMMetalTextVertex) * 6u]" in text:
        fail("Metal image runs must not allocate mutable vertex data for one quad")
    if "OrenAVMMetalSubrectInTexture" not in frame_text or "OrenAVMMetalSubrectInTexture" not in text:
        fail("retained Metal image sub-rect checks must use the overflow-safe helper")
    if "orenImageRunWithID:" in text:
        fail("Metal image runs must be built from cached texture/dimensions, not ID lookups")
    if "orenImageRunWithTexture:" not in text:
        fail("missing cached-texture Metal image-run helper")
    batched_images = text.find("} else if (opcode == 71")
    if batched_images < 0:
        fail("missing batched Metal image-rect path")
    batched_block = text[batched_images:text.find("} else if", batched_images + 1)]
    if "NSUInteger textureWidth = texture.width;" not in batched_block or "NSUInteger textureHeight = texture.height;" not in batched_block:
        fail("batched Metal image-rect draws must cache texture dimensions once")
    if batched_block.find("NSUInteger textureWidth = texture.width;") > batched_block.find("for (uint32_t ri"):
        fail("batched Metal image-rect dimension cache must happen before the rect loop")
    if "@interface OrenAVMMetalModelResource" not in metal_text:
        fail("retained Metal models must use typed resource objects")
    if 'NSMutableDictionary<NSNumber*, NSDictionary<NSString*, NSNumber*>*>* orenModels3D' in text:
        fail("retained Metal models must not use dictionary payload records")
    if 'NSMutableDictionary<NSNumber*, OrenAVMMetalModelResource*>* orenModels3D' in text:
        fail("retained Metal model lookups must avoid boxed NSNumber model IDs")
    if "CFMutableDictionaryRef _orenModels3DByID" not in text:
        fail("retained Metal models must use a scalar-key CF dictionary")
    if "OrenAVMMetalRetainedModelResource(_orenModels3DByID, meshID)" not in text:
        fail("retained Metal model draws must use the typed scalar-map resource helper")
    if 'model[@"mesh_id"]' in text or '@"scale_milli"' in text:
        fail("retained Metal model draws must not use string-key dictionary lookups")
    if "OrenAVMMetalFlushVertexRun(&vertexRuns, &vertices, runCapacity, clip, NO)" not in text:
        fail("final geometry vertex-run flush must avoid allocating a replacement builder")
    if "OrenAVMMetalFrameRunCapacity(NSData* frame)" not in frame_text:
        fail("missing bounded Metal frame run-capacity helper")
    if text.count("OrenAVMMetalFrameRunCapacity(") != 1:
        fail("expected one prepare-frame call to the frame run-capacity helper")
    if "NSMutableArray* OrenAVMMetalEnsureRunArray" not in frame_text:
        fail("missing lazy Metal text/image run-array helper")
    eager_run_arrays = [
        "NSMutableArray<OrenAVMMetalVertexRun*>* vertexRuns = [NSMutableArray arrayWithCapacity:runCapacity]",
        "NSMutableArray<OrenAVMMetalTextRun*>* textRuns = [NSMutableArray arrayWithCapacity:runCapacity]",
        "NSMutableArray<OrenAVMMetalImageRun*>* imageRuns = [NSMutableArray arrayWithCapacity:runCapacity]",
    ]
    for pattern in eager_run_arrays:
        if pattern in text:
            fail("geometry/text/image run arrays must be allocated lazily, not eagerly from runCapacity")
    if "[NSMutableArray arrayWithCapacity:runCapacity]" in text:
        fail("Metal frame run arrays must use lazy OrenAVMMetalEnsureRunArray allocation")
    if text.count("OrenAVMMetalEnsureRunArray(") < 6:
        fail("expected lazy run-array helper calls for geometry/text/image add sites")

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

    for lineno, line in enumerate(text.splitlines(), start=1):
        if "OrenAVMMetalBindVertexPayload(" in line:
            helper_bind_calls += 1
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
