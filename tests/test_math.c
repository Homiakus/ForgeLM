// test_math.c - Верификационный тест численной точности ядер ForgeLM (AVX2 ASM vs Reference C)
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <assert.h>

// Прототипы функций на ассемблере
extern void forgelm_rmsnorm_f32(float *out, const float *x, const float *w, int dim, float eps);
extern void forgelm_gemv_f32(float *out, const float *A, const float *x, int M, int K);

// Эталонная C-реализация RMSNorm
void ref_rmsnorm(float *out, const float *x, const float *w, int dim, float eps) {
    float sum = 0.0f;
    for (int i = 0; i < dim; i++) {
        sum += x[i] * x[i];
    }
    float scale = 1.0f / sqrtf(sum / dim + eps);
    for (int i = 0; i < dim; i++) {
        out[i] = x[i] * scale * w[i];
    }
}

// Эталонная C-реализация GEMV
void ref_gemv(float *out, const float *A, const float *x, int M, int K) {
    for (int i = 0; i < M; i++) {
        float sum = 0.0f;
        for (int j = 0; j < K; j++) {
            sum += A[i * K + j] * x[j];
        }
        out[i] = sum;
    }
}

int main() {
    printf("=== [ForgeLM] Numerical Correctness & Kernel Verification ===\n");

    // 1. Тест RMSNorm
    const int dim = 64;
    float x[dim], w[dim], out_asm[dim], out_ref[dim];
    for (int i = 0; i < dim; i++) {
        x[i] = (float)(i + 1) * 0.1f;
        w[i] = 1.0f + (float)i * 0.01f;
    }
    float eps = 1e-5f;

    ref_rmsnorm(out_ref, x, w, dim, eps);
    forgelm_rmsnorm_f32(out_asm, x, w, dim, eps);

    float max_diff_norm = 0.0f;
    for (int i = 0; i < dim; i++) {
        float diff = fabsf(out_asm[i] - out_ref[i]);
        if (diff > max_diff_norm) max_diff_norm = diff;
    }
    printf("[1] RMSNorm (dim=%d): max_abs_diff = %e [%s]\n", 
           dim, max_diff_norm, (max_diff_norm < 1e-5f) ? "PASS" : "FAIL");

    // 2. Тест GEMV
    const int M = 32;
    const int K = 64;
    float *A = (float*)malloc(M * K * sizeof(float));
    float x_gemv[K];
    float out_gemv_asm[M];
    float out_gemv_ref[M];

    for (int i = 0; i < M * K; i++) {
        A[i] = (float)((i % 17) - 8) * 0.125f;
    }
    for (int j = 0; j < K; j++) {
        x_gemv[j] = (float)(j % 5) * 0.5f;
    }

    ref_gemv(out_gemv_ref, A, x_gemv, M, K);
    forgelm_gemv_f32(out_gemv_asm, A, x_gemv, M, K);

    float max_diff_gemv = 0.0f;
    for (int i = 0; i < M; i++) {
        float diff = fabsf(out_gemv_asm[i] - out_gemv_ref[i]);
        if (diff > max_diff_gemv) max_diff_gemv = diff;
    }
    printf("[2] GEMV (M=%d, K=%d): max_abs_diff = %e [%s]\n", 
           M, K, max_diff_gemv, (max_diff_gemv < 1e-4f) ? "PASS" : "FAIL");

    free(A);

    if (max_diff_norm < 1e-5f && max_diff_gemv < 1e-4f) {
        printf(">>> ALL FORGELM NUMERICAL TESTS PASSED! <<<\n");
        return 0;
    } else {
        printf(">>> VERIFICATION FAILED! <<<\n");
        return 1;
    }
}
