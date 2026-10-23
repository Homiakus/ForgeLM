// benchmark_gemv.c - Измерение пропускной способности и GFLOPS ассемблерного ядра ForgeLM
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

extern void forgelm_gemv_f32(float *out, const float *A, const float *x, int M, int K);

static inline double get_time_sec() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

int main() {
    // Типичный размер проекции для Llama 7B/8B (dim = 4096)
    const int M = 4096;
    const int K = 4096;
    const int iters = 100;

    printf("=== [ForgeLM Benchmark] GEMV Kernel Performance ===\n");
    printf("Matrix size: %d x %d (%.2f MB weights)\n", M, K, (double)(M * K * sizeof(float)) / (1024.0 * 1024.0));

    float *A = (float*)aligned_alloc(32, M * K * sizeof(float));
    float *x = (float*)aligned_alloc(32, K * sizeof(float));
    float *out = (float*)aligned_alloc(32, M * sizeof(float));

    for (int i = 0; i < M * K; i++) A[i] = 0.001f;
    for (int i = 0; i < K; i++) x[i] = 1.0f;

    // Прогрев
    forgelm_gemv_f32(out, A, x, M, K);

    double t0 = get_time_sec();
    for (int i = 0; i < iters; i++) {
        forgelm_gemv_f32(out, A, x, M, K);
    }
    double t1 = get_time_sec();

    double total_time = t1 - t0;
    double avg_time_ms = (total_time / iters) * 1000.0;
    double gflops = (2.0 * (double)M * (double)K * 1e-9) / (total_time / iters);
    double bandwidth_gbs = ((double)M * (double)K * sizeof(float) * 1e-9) / (total_time / iters);

    printf("Iterations: %d\n", iters);
    printf("Avg latency: %.3f ms\n", avg_time_ms);
    printf("Compute Throughput: %.2f GFLOPS\n", gflops);
    printf("Memory Bandwidth: %.2f GB/s\n", bandwidth_gbs);

    free(A);
    free(x);
    free(out);
    return 0;
}
