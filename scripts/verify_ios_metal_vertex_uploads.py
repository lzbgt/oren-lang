#!/usr/bin/env python3
"""Verify hot Metal frame paths stay bounded."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMMetalView.m"
TEXT_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMMetalText.m"
TEXT_HEADER = ROOT / "sdk/ios/OrenAVMKit/OrenAVMMetalText.h"
HELPER = "static BOOL OrenAVMMetalBindVertexPayload"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def main() -> int:
    text = SOURCE.read_text()
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
    if "run.vertices = [vertices copy]" in text_source:
        fail("batched text vertex runs must transfer completed buffers instead of copying them")
    if "[NSMutableData dataWithData:pending.vertices]" in text_source:
        fail("text coalescing must use the mutable-vertex helper instead of unconditionally copying pending data")
    if "OrenAVMMetalMutableTextVerticesForCoalescing" not in text_source:
        fail("missing text coalescing mutable-vertex reuse helper")
    if "[vertices isKindOfClass:[NSMutableData class]]" not in text_source:
        fail("text coalescing must reuse mutable batched vertex buffers before falling back to copying")
    if "OrenAVMMetalTextureQuad" in text_source or "OrenAVMMetalTextureQuad" in text_header:
        fail("single Metal texture/text quads must use caller-owned mutable vertex buffers")
    if "dataWithBytes:out length:sizeof(out)" in text_source:
        fail("single Metal texture/text quads must not allocate NSData wrappers from stack vertices")
    if "dataWithBytes:payload + 4 length:4" in text:
        fail("retained Metal RGBA fields must stay scalar instead of allocating NSData wrappers")
    if "@property(nonatomic) uint32_t rgbaValue" not in text or "@property(nonatomic) uint32_t rgbaValue" not in text_header:
        fail("missing scalar RGBA storage for retained Metal mesh/text resources")
    if "@property(nonatomic, strong) NSData* triangles" in text or "@property(nonatomic, strong) NSData* indices" in text:
        fail("retained Metal mesh payloads must stay raw owned buffers, not NSData wrappers")
    for pattern in (
        "mesh.triangles = [NSData dataWithBytes:payload",
        "mesh.vertices = [NSData dataWithBytes:payload",
        "mesh.indices = [NSData dataWithBytes:payload",
        "mesh.triangles.bytes",
        "mesh.indices.length",
    ):
        if pattern in text:
            fail("retained Metal mesh payload path regressed to NSData-backed access")
    if "OrenAVMMetalCopyPayloadBytes" not in text:
        fail("missing retained Metal mesh raw payload copy helper")
    if "NSMutableDictionary<NSNumber*, NSNumber*>* orenMaterials3D" not in text:
        fail("retained Metal materials must store scalar RGBA NSNumber values")
    if "@interface OrenAVMMetalImageResource" not in text:
        fail("retained Metal images must use typed resource objects")
    if "NSMutableDictionary<NSNumber*, id<MTLTexture>>* orenImageTextures" in text:
        fail("retained Metal images must not store bare texture values")
    if "orenImagePixels" in text:
        fail("retained Metal image pixel accounting must not use a parallel dictionary")
    if "OrenAVMMetalSubrectInTexture" not in text:
        fail("retained Metal image sub-rect checks must use the overflow-safe helper")
    if "@interface OrenAVMMetalModelResource" not in text:
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
