#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

#if TARGET_OS_IPHONE

#include <stdint.h>

typedef struct {
    float x;
    float y;
    float r;
    float g;
    float b;
    float a;
} OrenAVMMetalVertex;

void OrenAVMMetalRGBAWithOpacity(const uint8_t* rgba, float opacity, uint8_t out[4]);
void OrenAVMMetalRGBAValueWithOpacity(uint32_t rgbaValue, float opacity, uint8_t out[4]);
void OrenAVMMetalRGBAValueBytes(uint32_t rgbaValue, uint8_t out[4]);

void OrenAVMMetalAppendRect(NSMutableData* vertices,
                            float x,
                            float y,
                            float w,
                            float h,
                            float logicalWidth,
                            float logicalHeight,
                            const uint8_t* rgba);
void OrenAVMMetalAppendLine(NSMutableData* vertices,
                            float x1,
                            float y1,
                            float x2,
                            float y2,
                            float width,
                            float logicalWidth,
                            float logicalHeight,
                            const uint8_t* rgba);
void OrenAVMMetalAppendStrokeRect(NSMutableData* vertices,
                                  float x,
                                  float y,
                                  float w,
                                  float h,
                                  float width,
                                  float logicalWidth,
                                  float logicalHeight,
                                  const uint8_t* rgba);
void OrenAVMMetalAppendTriangle(NSMutableData* vertices,
                                float x1,
                                float y1,
                                float x2,
                                float y2,
                                float x3,
                                float y3,
                                float logicalWidth,
                                float logicalHeight,
                                const uint8_t* rgba);
void OrenAVMMetalAppendCircle(NSMutableData* vertices,
                              float cx,
                              float cy,
                              float radius,
                              BOOL filled,
                              float logicalWidth,
                              float logicalHeight,
                              const uint8_t* rgba);
void OrenAVMMetalAppendEllipse(NSMutableData* vertices,
                               float x,
                               float y,
                               float w,
                               float h,
                               float width,
                               BOOL filled,
                               float logicalWidth,
                               float logicalHeight,
                               const uint8_t* rgba);
void OrenAVMMetalAppendRoundRect(NSMutableData* vertices,
                                 float x,
                                 float y,
                                 float w,
                                 float h,
                                 float radius,
                                 float width,
                                 BOOL filled,
                                 float logicalWidth,
                                 float logicalHeight,
                                 const uint8_t* rgba);

#endif
