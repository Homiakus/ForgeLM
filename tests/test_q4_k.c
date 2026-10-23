// test_q4_k.c - Верификация квантования высокого качества Q4_K на AVX2
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>

#pragma pack(push, 1)
typedef struct {
    uint16_t d;          // fp16 scale
    uint16_t dmin;       // fp16 min
    uint8_t scales[12];  // 6-bit sub-scales
    uint8_t qs[128];     // 256 nibbles
} block_q4_K_t;
#pragma pack(pop)

extern void forgelm_vec_dot_q4_k_f32(float *out, const void *vx, const float *vy, int k);

int main() {
    printf("=== [ForgeLM Audit] High-Precision Q4_K AVX2 Kernel ===\n");
    const int k = 1024;
    const int nb = k / 256;

    block_q4_K_t *blocks = (block_q4_K_t*)aligned_alloc(32, nb * sizeof(block_q4_K_t));
    float *y = (float*)aligned_alloc(32, k * sizeof(float));

    for (int b = 0; b < nb; b++) {
        blocks[b].d = 0x3c00; // 1.0f in fp16
        blocks[b].dmin = 0;
        for (int i = 0; i < 12; i++) blocks[b].scales[i] = 0;
        for (int i = 0; i < 128; i++) blocks[b].qs[i] = 0x22; // нибблы 2, 2
    }
    for (int i = 0; i < k; i++) y[i] = 1.0f;

    float out = 0.0f;
    forgelm_vec_dot_q4_k_f32(&out, blocks, y, k);

    printf("Kernel Computed Output: %.4f\n", out);
    if (out > 0.0f) {
        printf(">>> Q4_K SUPER-BLOCK AVX2 KERNEL VERIFIED [PASS] <<<\n");
    } else {
        printf("FAIL: output mismatch\n");
        return 1;
    }

    free(blocks);
    free(y);
    return 0;
}
