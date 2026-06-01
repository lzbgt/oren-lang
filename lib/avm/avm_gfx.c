#include "avm_internal.h"

#include <stdio.h>
#include <string.h>

static void avm_gfx_err(char* err, size_t err_cap, const char* msg) {
    if (!err || err_cap == 0) return;
    snprintf(err, err_cap, "%s", msg ? msg : "invalid GFX payload");
}

static uint16_t avm_gfx_u16le(const uint8_t* p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t avm_gfx_u32le(const uint8_t* p) {
    return (uint32_t)p[0] |
        ((uint32_t)p[1] << 8) |
        ((uint32_t)p[2] << 16) |
        ((uint32_t)p[3] << 24);
}

int avm_gfx_validate_frame(const uint8_t* data, size_t len, char* err, size_t err_cap) {
    if (!data || len < 40u) {
        avm_gfx_err(err, err_cap, "invalid OGF0 frame: short header");
        return 0;
    }
    if (memcmp(data, "OGF0", 4) != 0) {
        avm_gfx_err(err, err_cap, "invalid OGF0 frame: bad magic");
        return 0;
    }
    if (data[4] != 1u) {
        avm_gfx_err(err, err_cap, "invalid OGF0 frame: unsupported version");
        return 0;
    }
    uint16_t header_len = avm_gfx_u16le(data + 6);
    if (header_len != 40u || (size_t)header_len > len) {
        avm_gfx_err(err, err_cap, "invalid OGF0 frame: bad header length");
        return 0;
    }
    uint32_t logical_w = avm_gfx_u32le(data + 8);
    uint32_t logical_h = avm_gfx_u32le(data + 12);
    uint32_t scale_milli = avm_gfx_u32le(data + 16);
    uint32_t op_count = avm_gfx_u32le(data + 20);
    uint32_t drawable_w = avm_gfx_u32le(data + 28);
    uint32_t drawable_h = avm_gfx_u32le(data + 32);
    if (logical_w == 0u || logical_h == 0u || scale_milli == 0u || drawable_w == 0u || drawable_h == 0u) {
        avm_gfx_err(err, err_cap, "invalid OGF0 frame: zero dimension or scale");
        return 0;
    }
    if (op_count > 100000u) {
        avm_gfx_err(err, err_cap, "invalid OGF0 frame: op count too large");
        return 0;
    }

    size_t off = (size_t)header_len;
    for (uint32_t i = 0; i < op_count; i++) {
        if (off + 4u > len) {
            avm_gfx_err(err, err_cap, "invalid OGF0 frame: truncated op header");
            return 0;
        }
        uint8_t opcode = data[off];
        uint16_t payload_len = avm_gfx_u16le(data + off + 2);
        off += 4u;
        if (off + (size_t)payload_len > len) {
            avm_gfx_err(err, err_cap, "invalid OGF0 frame: truncated op payload");
            return 0;
        }
        const uint8_t* payload = data + off;
        if (opcode == 1u) {
            if (payload_len != 20u) {
                avm_gfx_err(err, err_cap, "invalid OGF0 frame: bad fill_rect payload");
                return 0;
            }
        } else if (opcode == 2u) {
            if (payload_len < 16u) {
                avm_gfx_err(err, err_cap, "invalid OGF0 frame: bad text payload");
                return 0;
            }
            uint32_t text_len = avm_gfx_u32le(payload + 12);
            if (text_len != (uint32_t)payload_len - 16u) {
                avm_gfx_err(err, err_cap, "invalid OGF0 frame: text length mismatch");
                return 0;
            }
        } else if (opcode == 3u) {
            if (payload_len != 24u) {
                avm_gfx_err(err, err_cap, "invalid OGF0 frame: bad stroke_line payload");
                return 0;
            }
        } else if (opcode == 4u) {
            if (payload_len != 20u) {
                avm_gfx_err(err, err_cap, "invalid OGF0 frame: bad circle payload");
                return 0;
            }
        } else if (opcode == 5u) {
            if (payload_len != 28u) {
                avm_gfx_err(err, err_cap, "invalid OGF0 frame: bad fill_triangle payload");
                return 0;
            }
        } else if (opcode == 68u) {
            if (payload_len < 12u) {
                avm_gfx_err(err, err_cap, "invalid OGF0 frame: bad text_resource payload");
                return 0;
            }
            uint32_t text_len = avm_gfx_u32le(payload + 8);
            if (text_len != (uint32_t)payload_len - 12u) {
                avm_gfx_err(err, err_cap, "invalid OGF0 frame: text_resource length mismatch");
                return 0;
            }
        } else if (opcode == 69u) {
            if (payload_len != 12u) {
                avm_gfx_err(err, err_cap, "invalid OGF0 frame: bad draw_text payload");
                return 0;
            }
        } else if (opcode == 70u) {
            if (payload_len != 4u) {
                avm_gfx_err(err, err_cap, "invalid OGF0 frame: bad destroy_text payload");
                return 0;
            }
        } else if (opcode == 64u) {
            if (payload_len < 16u) {
                avm_gfx_err(err, err_cap, "invalid OGF0 frame: bad image_rgba payload");
                return 0;
            }
            uint32_t image_w = avm_gfx_u32le(payload + 4);
            uint32_t image_h = avm_gfx_u32le(payload + 8);
            uint32_t image_len = avm_gfx_u32le(payload + 12);
            uint64_t expected_len = (uint64_t)image_w * (uint64_t)image_h * 4u;
            if (image_w == 0u || image_h == 0u || image_len != (uint32_t)payload_len - 16u || expected_len != (uint64_t)image_len) {
                avm_gfx_err(err, err_cap, "invalid OGF0 frame: bad image_rgba dimensions");
                return 0;
            }
        } else if (opcode == 65u) {
            if (payload_len != 20u) {
                avm_gfx_err(err, err_cap, "invalid OGF0 frame: bad draw_image payload");
                return 0;
            }
        } else if (opcode == 66u) {
            if (payload_len != 4u) {
                avm_gfx_err(err, err_cap, "invalid OGF0 frame: bad destroy_image payload");
                return 0;
            }
        } else if (opcode == 67u) {
            if (payload_len != 36u) {
                avm_gfx_err(err, err_cap, "invalid OGF0 frame: bad draw_image_rect payload");
                return 0;
            }
            if (avm_gfx_u32le(payload + 12) == 0u || avm_gfx_u32le(payload + 16) == 0u ||
                avm_gfx_u32le(payload + 28) == 0u || avm_gfx_u32le(payload + 32) == 0u) {
                avm_gfx_err(err, err_cap, "invalid OGF0 frame: bad draw_image_rect dimensions");
                return 0;
            }
        } else if (opcode == 71u) {
            if (payload_len < 40u || ((payload_len - 8u) % 32u) != 0u) {
                avm_gfx_err(err, err_cap, "invalid OGF0 frame: bad draw_image_rects payload");
                return 0;
            }
            uint32_t rect_count = avm_gfx_u32le(payload + 4);
            if (rect_count == 0u || rect_count != ((uint32_t)payload_len - 8u) / 32u) {
                avm_gfx_err(err, err_cap, "invalid OGF0 frame: bad draw_image_rects count");
                return 0;
            }
            for (uint32_t ri = 0; ri < rect_count; ri++) {
                const uint8_t* r = payload + 8u + ((size_t)ri * 32u);
                if (avm_gfx_u32le(r + 8) == 0u || avm_gfx_u32le(r + 12) == 0u ||
                    avm_gfx_u32le(r + 24) == 0u || avm_gfx_u32le(r + 28) == 0u) {
                    avm_gfx_err(err, err_cap, "invalid OGF0 frame: bad draw_image_rects dimensions");
                    return 0;
                }
            }
        } else {
            avm_gfx_err(err, err_cap, "invalid OGF0 frame: unsupported opcode");
            return 0;
        }
        off += (size_t)payload_len;
    }
    if (off != len) {
        avm_gfx_err(err, err_cap, "invalid OGF0 frame: trailing bytes");
        return 0;
    }
    return 1;
}

int avm_gfx_validate_event(const uint8_t* data, size_t len, char* err, size_t err_cap) {
    if (!data || len < 12u) {
        avm_gfx_err(err, err_cap, "invalid OGE0 event: short header");
        return 0;
    }
    if (memcmp(data, "OGE0", 4) != 0) {
        avm_gfx_err(err, err_cap, "invalid OGE0 event: bad magic");
        return 0;
    }
    if (data[4] != 0u) {
        avm_gfx_err(err, err_cap, "invalid OGE0 event: unsupported version");
        return 0;
    }
    uint8_t opcode = data[8];
    uint16_t payload_len = avm_gfx_u16le(data + 10);
    if ((size_t)payload_len + 12u != len) {
        avm_gfx_err(err, err_cap, "invalid OGE0 event: length mismatch");
        return 0;
    }
    if (opcode >= 1u && opcode <= 4u) {
        if (payload_len != 12u) {
            avm_gfx_err(err, err_cap, "invalid OGE0 event: bad pointer payload");
            return 0;
        }
        return 1;
    }
    if (opcode == 16u) {
        if (payload_len != 12u) {
            avm_gfx_err(err, err_cap, "invalid OGE0 event: bad resize payload");
            return 0;
        }
        return 1;
    }
    if (opcode == 17u) {
        if (payload_len != 28u) {
            avm_gfx_err(err, err_cap, "invalid OGE0 event: bad media payload");
            return 0;
        }
        return 1;
    }
    if (opcode == 18u) {
        if (payload_len != 28u) {
            avm_gfx_err(err, err_cap, "invalid OGE0 event: bad frame_tick payload");
            return 0;
        }
        return 1;
    }
    if (opcode == 32u || opcode == 33u) {
        if (payload_len != 8u) {
            avm_gfx_err(err, err_cap, "invalid OGE0 event: bad key payload");
            return 0;
        }
        return 1;
    }
    if (opcode == 48u) {
        if (payload_len < 4u) {
            avm_gfx_err(err, err_cap, "invalid OGE0 event: bad text payload");
            return 0;
        }
        uint32_t text_len = avm_gfx_u32le(data + 12);
        if (text_len != (uint32_t)payload_len - 4u) {
            avm_gfx_err(err, err_cap, "invalid OGE0 event: text length mismatch");
            return 0;
        }
        return 1;
    }
    if (opcode == 64u) {
        if (payload_len != 24u) {
            avm_gfx_err(err, err_cap, "invalid OGE0 event: bad gamepad payload");
            return 0;
        }
        return 1;
    }
    if (opcode == 96u) {
        if (payload_len != 40u) {
            avm_gfx_err(err, err_cap, "invalid OGE0 event: bad motion payload");
            return 0;
        }
        return 1;
    }
    avm_gfx_err(err, err_cap, "invalid OGE0 event: unsupported opcode");
    return 0;
}
