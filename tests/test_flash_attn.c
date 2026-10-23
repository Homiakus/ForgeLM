// test_flash_attn.c - Верификация FlashDecoding против эталонного Naive Attention
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>
#include "forgelm.h"

extern void forgelm_flash_decode_f32(float *out, const float *q, const float *k_cache,
                                     const float *v_cache, int seq_len, int head_dim, float scale);

// Эталонное внимание (O(N) память под scores)
void ref_attention_decode(float *out, const float *q, const float *k_cache,
                          const float *v_cache, int seq_len, int head_dim, float scale) {
    float *scores = (float*)malloc(seq_len * sizeof(float));
    float max_s = -1e30f;

    // 1. Scores = Q * K^T * scale
    for (int t = 0; t < seq_len; t++) {
        float dot = 0.0f;
        for (int d = 0; d < head_dim; d++) {
            dot += q[d] * k_cache[t * head_dim + d];
        }
        scores[t] = dot * scale;
        if (scores[t] > max_s) max_s = scores[t];
    }

    // 2. Softmax
    float sum_exp = 0.0f;
    for (int t = 0; t < seq_len; t++) {
        scores[t] = expf(scores[t] - max_s);
        sum_exp += scores[t];
    }
    for (int t = 0; t < seq_len; t++) {
        scores[t] /= sum_exp;
    }

    // 3. Out = Scores * V
    for (int d = 0; d < head_dim; d++) {
        float val = 0.0f;
        for (int t = 0; t < seq_len; t++) {
            val += scores[t] * v_cache[t * head_dim + d];
        }
        out[d] = val;
    }

    free(scores);
}

static inline double get_time_sec() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

int main() {
    const int head_dim = 64;
    const int seq_len = 1024;
    const float scale = 1.0f / sqrtf((float)head_dim);

    printf("=== [ForgeLM Audit] FlashDecoding AVX2 ASM Kernel ===\n");
    printf("Head Dim: %d | Context Length: %d tokens\n", head_dim, seq_len);

    float *q = (float*)aligned_alloc(32, head_dim * sizeof(float));
    float *k_cache = (float*)aligned_alloc(32, seq_len * head_dim * sizeof(float));
    float *v_cache = (float*)aligned_alloc(32, seq_len * head_dim * sizeof(float));
    float *out_ref = (float*)aligned_alloc(32, head_dim * sizeof(float));
    float *out_asm = (float*)aligned_alloc(32, head_dim * sizeof(float));

    for (int i = 0; i < head_dim; i++) q[i] = ((float)rand() / RAND_MAX - 0.5f);
    for (int i = 0; i < seq_len * head_dim; i++) {
        k_cache[i] = ((float)rand() / RAND_MAX - 0.5f);
        v_cache[i] = ((float)rand() / RAND_MAX - 0.5f);
    }

    ref_attention_decode(out_ref, q, k_cache, v_cache, seq_len, head_dim, scale);
    forgelm_flash_decode_f32(out_asm, q, k_cache, v_cache, seq_len, head_dim, scale);

    float max_diff = 0.0f;
    for (int i = 0; i < head_dim; i++) {
        float diff = fabsf(out_ref[i] - out_asm[i]);
        if (diff > max_diff) max_diff = diff;
    }

    printf("Precision diff vs Float32 Ref: %e [%s]\n", max_diff, max_diff < 1e-4f ? "PASS" : "FAIL");

    // Бенчмарк скорости
    int iters = 1000;
    double t0 = get_time_sec();
    for (int i = 0; i < iters; i++) {
        forgelm_flash_decode_f32(out_asm, q, k_cache, v_cache, seq_len, head_dim, scale);
    }
    double t1 = get_time_sec();

    double latency_us = ((t1 - t0) / iters) * 1e6;
    printf("FlashDecoding Step Latency: %.2f us (%.1f k steps/sec)\n", latency_us, 1e6 / latency_us);

    free(q);
    free(k_cache);
    free(v_cache);
    free(out_ref);
    free(out_asm);
    return (max_diff < 1e-4f) ? 0 : 1;
}
