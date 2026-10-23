// test_q4.c - Верификационный тест численной точности Q4_0 на AVX2 ASM
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>
#include <assert.h>

#pragma pack(push, 1)
typedef struct {
    uint16_t d;       // fp16 scale
    uint8_t qs[16];   // 32 nibbles
} block_q4_0;
#pragma pack(pop)

// Прототип функции на ассемблере
extern void forgelm_vec_dot_q4_0_f32(float *out, const void *vx, const float *vy, int k);

// Вспомогательная конвертация float -> fp16 (IEEE-754 half precision)
static inline uint16_t float_to_fp16(float f) {
    uint32_t x = *(uint32_t*)&f;
    uint32_t sign = (x >> 16) & 0x8000;
    int32_t exp = ((x >> 23) & 0xFF) - 127 + 15;
    uint32_t mant = (x >> 13) & 0x3FF;
    if (exp <= 0) return (uint16_t)sign;
    if (exp >= 31) return (uint16_t)(sign | 0x7C00);
    return (uint16_t)(sign | (exp << 10) | mant);
}

static inline float fp16_to_float(uint16_t h) {
    uint32_t sign = (h & 0x8000) << 16;
    int32_t exp = (h >> 10) & 0x1F;
    uint32_t mant = h & 0x3FF;
    if (exp == 0) return 0.0f;
    uint32_t f = sign | ((exp - 15 + 127) << 23) | (mant << 13);
    return *(float*)&f;
}

// Эталонное скалярное произведение Q4_0
float ref_vec_dot_q4_0(const block_q4_0 *vx, const float *vy, int k) {
    int nb = k / 32;
    float total_sum = 0.0f;

    for (int b = 0; b < nb; b++) {
        float d = fp16_to_float(vx[b].d);
        const uint8_t *qs = vx[b].qs;
        const float *y = vy + b * 32;

        float block_sum = 0.0f;
        for (int i = 0; i < 16; i++) {
            int8_t q0 = (qs[i] & 0x0F) - 8;
            int8_t q1 = (qs[i] >> 4) - 8;
            block_sum += (float)q0 * d * y[i];
            block_sum += (float)q1 * d * y[i + 16];
        }
        total_sum += block_sum;
    }
    return total_sum;
}

int main() {
    printf("=== [ForgeLM] Q4_0 4-bit Quantization AVX2 ASM Verification ===\n");

    const int k = 128; // 4 блока Q4_0
    block_q4_0 blocks[4];
    float y[128];

    for (int b = 0; b < 4; b++) {
        blocks[b].d = float_to_fp16(0.5f + (float)b * 0.1f);
        for (int i = 0; i < 16; i++) {
            // Тестовые нибблы от 0 до 15
            blocks[b].qs[i] = (uint8_t)((i & 0x0F) | (((15 - i) & 0x0F) << 4));
        }
    }
    for (int i = 0; i < 128; i++) {
        y[i] = 1.0f + (float)(i % 7) * 0.25f;
    }

    float ref_result = ref_vec_dot_q4_0(blocks, y, k);
    float asm_result = 0.0f;

    forgelm_vec_dot_q4_0_f32(&asm_result, blocks, y, k);

    float diff = fabsf(asm_result - ref_result);
    printf("Ref Result: %f | ASM Result: %f | Diff: %e\n", ref_result, asm_result, diff);

    if (diff < 1e-3f) {
        printf(">>> Q4_0 4-BIT QUANTIZED AVX2 ASM KERNEL PASSED! <<<\n");
        return 0;
    } else {
        printf(">>> Q4_0 TEST FAILED! <<<\n");
        return 1;
    }
}
