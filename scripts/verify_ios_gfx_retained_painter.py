#!/usr/bin/env python3
"""Verify retained 3D fallback painter ordering stays on compact buffers."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsView.m"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def main() -> int:
    text = SOURCE.read_text()
    required = [
        "OrenAVMGfxTriangleOrder",
        "OrenAVMGfxTriangleOrderBuffer",
        "OrenAVMGfxSortTriangleOrder",
    ]
    for token in required:
        if token not in text:
            fail(f"missing retained 3D painter helper: {token}")
    if "NSMutableSet<NSNumber*>* drawn" in text or "[drawn containsObject:" in text:
        fail("retained 3D painter path still uses boxed set tracking")
    if text.count("OrenAVMGfxSortTriangleOrder(order, visibleCount)") < 2:
        fail("expected sorted order path for indexed and packed retained 3D meshes")
    if "OrenAVMGfxInlineTriangleOrderCapacity = 128" not in text:
        fail("CoreGraphics retained 3D triangle ordering must have a small stack buffer")
    if "OrenAVMGfxTriangleOrderBuffer(uint32_t triangleCount,\n                                                              OrenAVMGfxTriangleOrder* inlineOrder" not in text:
        fail("CoreGraphics retained 3D triangle ordering must try inline storage before heap storage")
    if text.count("OrenAVMGfxTriangleOrder inlineOrder[OrenAVMGfxInlineTriangleOrderCapacity]") < 2:
        fail("CoreGraphics retained 3D draw paths must pass stack triangle-order buffers")
    if "NSMutableData* orderData" in text or "dataWithLength:(NSUInteger)triangleCount * sizeof(OrenAVMGfxTriangleOrder)" in text:
        fail("CoreGraphics retained 3D triangle ordering must not use NSMutableData heap fallbacks")
    if "OrenAVMGfxTriangleOrder* heapOrder = NULL" not in text or "free(heapOrder)" not in text:
        fail("CoreGraphics retained 3D triangle ordering must free raw heap fallbacks")
    if "@interface OrenAVMGfxMeshResource" not in text:
        fail("CoreGraphics retained meshes must use typed resource objects")
    if "static UIColor* OrenAVMGfxColor(const uint8_t* rgba)" in text:
        fail("CoreGraphics immediate primitive colors must not allocate UIColor wrappers")
    if "CGContextSetFillColorWithColor(ctx, color.CGColor)" in text or "CGContextSetStrokeColorWithColor(ctx, color.CGColor)" in text:
        fail("CoreGraphics immediate primitive colors must use direct byte/scalar setters")
    if "OrenAVMGfxSetFillColorBytes(ctx, payload + 16)" not in text or "OrenAVMGfxSetStrokeColorBytes(ctx, payload + 20)" not in text:
        fail("CoreGraphics immediate primitive color fast path is missing")
    if 'NSMutableDictionary<NSNumber*, NSDictionary<NSString*, id>*>* orenMeshes' in text:
        fail("CoreGraphics retained meshes must not use dictionary payload records")
    if "@property(nonatomic, strong) NSData* triangles" in text or "@property(nonatomic, strong) NSData* indices" in text:
        fail("CoreGraphics retained mesh payloads must stay raw owned buffers, not NSData wrappers")
    for pattern in (
        "mesh.triangles = [NSData dataWithBytes:payload",
        "mesh.vertices = [NSData dataWithBytes:payload",
        "mesh.indices = [NSData dataWithBytes:payload",
        "mesh.triangles.bytes",
        "mesh.indices.length",
    ):
        if pattern in text:
            fail("CoreGraphics retained mesh payload path regressed to NSData-backed access")
    if "OrenAVMGfxCopyPayloadBytes" not in text:
        fail("missing CoreGraphics retained mesh raw payload copy helper")
    if "NSMutableDictionary<NSNumber*, UIColor*>* orenMaterials3D" in text:
        fail("CoreGraphics retained materials must store scalar RGBA values")
    if "NSMutableDictionary<NSNumber*, NSNumber*>* orenMaterials3D" in text:
        fail("CoreGraphics retained materials must avoid boxed NSNumber IDs/RGBA values")
    if "CFMutableDictionaryRef _orenMaterials3DByID" not in text:
        fail("CoreGraphics retained materials must use a scalar-key/scalar-value CF dictionary")
    if "OrenAVMGfxRetainedMaterialRGBA(_orenMaterials3DByID, materialID, &materialRGBAOverride)" not in text:
        fail("CoreGraphics retained material draws must use the scalar material lookup helper")
    if "materialRGBAValue" in text or "@(materialID)" in text:
        fail("CoreGraphics retained material paths must not box material IDs or RGBA values")
    if '@"color": OrenAVMGfxColor' in text:
        fail("CoreGraphics retained mesh colors must stay scalar, not retained UIColor objects")
    if "@interface OrenAVMGfxTextResource" not in text:
        fail("CoreGraphics retained text must use typed resource objects")
    if 'NSMutableDictionary<NSNumber*, NSDictionary<NSString*, id>*>* orenTextResources' in text:
        fail("CoreGraphics retained text must not use dictionary payload records")
    if 'NSMutableDictionary<NSNumber*, OrenAVMGfxTextResource*>* orenTextResources' in text:
        fail("CoreGraphics retained text lookups must avoid boxed NSNumber text IDs")
    if "CFMutableDictionaryRef _orenTextResourcesByID" not in text:
        fail("CoreGraphics retained text resources must use a scalar-key CF dictionary")
    if "OrenAVMGfxRetainedTextResource(_orenTextResourcesByID, textID)" not in text:
        fail("CoreGraphics retained text draws must use the typed scalar-map resource helper")
    if "@(textID)" in text:
        fail("CoreGraphics retained text upload/draw paths must not box text IDs")
    if 'self.orenTextResources[@(textID)] = @{@"text": text, @"color": color}' in text:
        fail("CoreGraphics retained text must cache typed attributed text")
    if "resource.attributes" in text or "@property(nonatomic, strong) NSDictionary<NSAttributedStringKey, id>* attributes" in text:
        fail("CoreGraphics retained text must cache attributed strings, not separate attributes dictionaries")
    if "@property(nonatomic, strong) NSAttributedString* attributedText" not in text:
        fail("CoreGraphics retained text must store cached attributed strings")
    if 'NSDictionary<NSString*, id>* resource = self.orenTextResources[@(textID)]' in text:
        fail("CoreGraphics retained text draws must not use dictionary casts")
    if "NSMutableDictionary<NSNumber*, NSDictionary<NSAttributedStringKey, id>*>* orenTextAttributes" not in text:
        fail("CoreGraphics text draws must cache UIKit text attributes by RGBA")
    if "OrenAVMGfxTextAttributesForView" not in text:
        fail("CoreGraphics text draws must use the per-view text attribute cache")
    attr_helper_start = text.find("static NSDictionary<NSAttributedStringKey, id>* OrenAVMGfxTextAttributesForView")
    attr_helper_end = text.find("@implementation OrenAVMGraphicsView", attr_helper_start)
    if attr_helper_start < 0 or attr_helper_end < 0:
        fail("missing CoreGraphics text attribute helper body")
    attr_helper = text[attr_helper_start:attr_helper_end]
    mru_pos = attr_helper.find("view.orenLastTextAttributes && view.orenLastTextAttributesRGBA == rgbaValue")
    boxed_key_pos = attr_helper.find("NSNumber* key = @(rgbaValue)")
    if mru_pos < 0 or boxed_key_pos < 0 or mru_pos > boxed_key_pos:
        fail("CoreGraphics text attribute cache must check the scalar MRU before boxing NSNumber keys")
    if "OrenAVMGfxTextAttributes(OrenAVMGfxRGBAValue(payload + 8))" in text:
        fail("CoreGraphics immediate text draws must not rebuild text attributes per draw")
    if "OrenAVMGfxTextAttributes(OrenAVMGfxRGBAValue(payload + 4))" in text:
        fail("CoreGraphics retained text resources must use cached text attributes")
    if "@interface OrenAVMGfxImageResource" not in text:
        fail("CoreGraphics retained images must use typed resource objects")
    if "NSMutableDictionary<NSNumber*, UIImage*>* orenImages" in text:
        fail("CoreGraphics retained images must not store bare UIImage values")
    if "NSMutableDictionary<NSNumber*, OrenAVMGfxImageResource*>* orenImages" in text:
        fail("CoreGraphics retained image lookups must avoid boxed NSNumber image IDs")
    if "CFMutableDictionaryRef _orenImagesByID" not in text:
        fail("CoreGraphics retained images must use a scalar-key CF dictionary")
    if "OrenAVMGfxRetainedImageResource(_orenImagesByID, imageID)" not in text:
        fail("CoreGraphics retained image draw paths must use the typed scalar-map resource helper")
    if "@(imageID)" in text:
        fail("CoreGraphics retained image draw/upload paths must not box image IDs")
    if "orenImagePixels" in text:
        fail("CoreGraphics retained image pixel accounting must not use a parallel dictionary")
    if "NSData* imageData = [NSData dataWithBytes:rgba" in text or "CGDataProviderCreateWithCFData" in text:
        fail("CoreGraphics retained image uploads must use provider-owned raw bytes, not NSData wrappers")
    if "CGDataProviderCreateWithData(NULL, imageBytes" not in text or "OrenAVMGfxReleaseImageBytes" not in text:
        fail("CoreGraphics retained image uploads must transfer raw bytes to the CG provider release callback")
    if "OrenAVMGfxSubrectInImage" not in text:
        fail("CoreGraphics retained image sub-rect checks must use the overflow-safe helper")
    if "OrenAVMGfxDrawImageSubrect" not in text:
        fail("CoreGraphics retained image sub-rect draws must share the checked draw helper")
    if "OrenAVMGfxSubrectInImage(sx, sy, sw, sh, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage))" in text:
        fail("CoreGraphics batched image sub-rect draws must cache CGImage dimensions")
    if "size_t imageWidth = CGImageGetWidth(cgImage)" not in text or "size_t imageHeight = CGImageGetHeight(cgImage)" not in text:
        fail("CoreGraphics batched image sub-rect draws must cache image dimensions")
    if "@interface OrenAVMGfxModelResource" not in text:
        fail("CoreGraphics retained models must use typed resource objects")
    if 'NSMutableDictionary<NSNumber*, NSDictionary<NSString*, NSNumber*>*>* orenModels3D' in text:
        fail("CoreGraphics retained models must not use dictionary payload records")
    if 'NSMutableDictionary<NSNumber*, OrenAVMGfxModelResource*>* orenModels3D' in text:
        fail("CoreGraphics retained model lookups must avoid boxed NSNumber model IDs")
    if "CFMutableDictionaryRef _orenModels3DByID" not in text:
        fail("CoreGraphics retained models must use a scalar-key CF dictionary")
    if "OrenAVMGfxRetainedModelResource(_orenModels3DByID, meshID)" not in text:
        fail("CoreGraphics retained model draws must use the typed scalar-map resource helper")
    if 'model[@"mesh_id"]' in text or '@"scale_milli"' in text:
        fail("CoreGraphics retained model draws must not use string-key dictionary lookups")
    print("OK: CoreGraphics retained resources use compact typed records")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
