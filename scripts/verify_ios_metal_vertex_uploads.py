#!/usr/bin/env python3
"""Verify hot Metal frame paths stay bounded."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMMetalView.m"
RESOURCE_HEADER = ROOT / "sdk/ios/OrenAVMKit/OrenAVMMetalResources.h"
RESOURCE_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMMetalResources.m"
TEXT_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMMetalText.m"
TEXT_HEADER = ROOT / "sdk/ios/OrenAVMKit/OrenAVMMetalText.h"
HELPER = "static BOOL OrenAVMMetalBindVertexPayload"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def main() -> int:
    text = SOURCE.read_text()
    resource_text = RESOURCE_HEADER.read_text() + "\n" + RESOURCE_SOURCE.read_text()
    metal_text = text + "\n" + resource_text
    text_source = TEXT_SOURCE.read_text()
    text_header = TEXT_HEADER.read_text()
    if "OrenAVMMetalInlineVertexBytesLimit" not in text:
        fail("missing inline vertex upload limit")
    if HELPER not in text:
        fail("missing bounded vertex payload helper")
    if "newBufferWithBytes:" not in text or "addCompletedHandler:" not in text:
        fail("missing large vertex upload buffer retention path")
    if "[transientVertexBuffers copy]" in text:
        fail("large vertex upload completion path must retain the existing tracking array without copying it")
    if "run.vertices = [vertices copy]" in text:
        fail("geometry vertex runs must transfer completed buffers instead of copying them at flush")
    if "[NSMutableData dataWithCapacity:vertices.length]" in text:
        fail("geometry flush must not allocate the next mutable vertex buffer eagerly")
    if "NSMutableData* vertices = nil;" not in text or "OrenAVMMetalEnsureVertexBuilder(&vertices, runCapacity)" not in text:
        fail("geometry vertex buffers must be allocated lazily on first append with bounded capacity")
    if "OrenAVMMetalInitialVertexBuilderCapacity" not in text or "const NSUInteger maxInitialBytes = 64u * 1024u" not in text:
        fail("geometry vertex builder must cap its lazy initial reservation")
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
    if "OrenAVMMetalMutableTextVerticesForCoalescing" not in text_source:
        fail("missing text coalescing mutable-vertex reuse helper")
    if "[vertices isKindOfClass:[NSMutableData class]]" not in text_source or "dataWithBytes:pending->inlineVertices" not in text_source:
        fail("text coalescing must reuse mutable batches and materialize inline quads only when merging")
    cache_lookup = text_source.find("OrenAVMMetalTextCacheEntry* cached = cache[cacheKey]")
    color_create = text_source.find("UIColor* color = [UIColor colorWithRed:")
    if cache_lookup < 0 or color_create < 0 or cache_lookup > color_create:
        fail("Metal text cache hits must return before constructing UIColor/attributes")
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
    if "OrenAVMMetalTextureQuad" in text_source or "OrenAVMMetalTextureQuad" in text_header:
        fail("single Metal texture/text quads must use caller-owned mutable vertex buffers")
    if "dataWithBytes:out length:sizeof(out)" in text_source:
        fail("single Metal texture/text quads must not allocate NSData wrappers from stack vertices")
    if "dataWithBytes:payload + 4 length:4" in metal_text:
        fail("retained Metal RGBA fields must stay scalar instead of allocating NSData wrappers")
    if "@property(nonatomic) uint32_t rgbaValue" not in metal_text or "@property(nonatomic) uint32_t rgbaValue" not in text_header:
        fail("missing scalar RGBA storage for retained Metal mesh/text resources")
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
    if "NSMutableDictionary<NSNumber*, NSNumber*>* orenMaterials3D" not in text:
        fail("retained Metal materials must store scalar RGBA NSNumber values")
    if "@interface OrenAVMMetalImageResource" not in metal_text:
        fail("retained Metal images must use typed resource objects")
    if "NSMutableDictionary<NSNumber*, id<MTLTexture>>* orenImageTextures" in text:
        fail("retained Metal images must not store bare texture values")
    if "orenImagePixels" in text:
        fail("retained Metal image pixel accounting must not use a parallel dictionary")
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
    if "OrenAVMMetalSubrectInTexture" not in text:
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
    if 'model[@"mesh_id"]' in text or '@"scale_milli"' in text:
        fail("retained Metal model draws must not use string-key dictionary lookups")
    if "OrenAVMMetalFlushVertexRun(vertexRuns, &vertices, clip, NO)" not in text:
        fail("final geometry vertex-run flush must avoid allocating a replacement builder")
    if "static NSUInteger OrenAVMMetalFrameRunCapacity" not in text:
        fail("missing bounded Metal frame run-capacity helper")
    if text.count("OrenAVMMetalFrameRunCapacity(") != 2:
        fail("expected frame run-capacity helper declaration plus one prepare-frame call")
    if "static NSMutableArray* OrenAVMMetalEnsureRunArray" not in text:
        fail("missing lazy Metal text/image run-array helper")
    eager_run_arrays = [
        "NSMutableArray<OrenAVMMetalTextRun*>* textRuns = [NSMutableArray arrayWithCapacity:runCapacity]",
        "NSMutableArray<OrenAVMMetalImageRun*>* imageRuns = [NSMutableArray arrayWithCapacity:runCapacity]",
    ]
    for pattern in eager_run_arrays:
        if pattern in text:
            fail("text/image run arrays must be allocated lazily, not eagerly from runCapacity")
    if text.count("OrenAVMMetalEnsureRunArray(") < 7:
        fail("expected lazy run-array helper declaration plus text/image add sites")

    in_helper = False
    saw_helper_body = False
    helper_depth = 0
    helper_set_vertex_bytes = 0
    direct_calls: list[str] = []
    helper_bind_calls = 0

    for lineno, line in enumerate(text.splitlines(), start=1):
        if HELPER in line:
            in_helper = True
            saw_helper_body = False
            helper_depth = 0

        if "OrenAVMMetalBindVertexPayload(" in line and HELPER not in line:
            helper_bind_calls += 1

        if "setVertexBytes:" in line:
            if in_helper:
                helper_set_vertex_bytes += 1
            else:
                direct_calls.append(f"{SOURCE}:{lineno}: {line.strip()}")

        if in_helper:
            if "{" in line:
                saw_helper_body = True
            helper_depth += line.count("{") - line.count("}")
            if saw_helper_body and helper_depth <= 0:
                in_helper = False

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
