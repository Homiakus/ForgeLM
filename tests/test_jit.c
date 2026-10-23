// test_jit.c - Верификация JIT-компиляции чистого машинного кода в памяти
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>

extern void* forgelm_jit_alloc_executable(size_t size);
extern int   forgelm_jit_free_executable(void *ptr, size_t size);
extern int   forgelm_jit_compile_gemv_row(void *code_buf, int K);

typedef void (*jit_gemv_dot_fn)(float *out, const float *A_row, const float *x);

int main() {
    printf("=== [ForgeLM Audit] In-Memory JIT Kernel Synthesis (AVX2+FMA) ===\n");

    const int K = 256;
    size_t code_arena_size = 65536; // 64 KB
    void *jit_mem = forgelm_jit_alloc_executable(code_arena_size);
    if (!jit_mem) {
        printf("FAIL: JIT memory allocation failed\n");
        return 1;
    }

    int bytes_generated = forgelm_jit_compile_gemv_row(jit_mem, K);
    printf("Synthesized JIT Kernel size: %d bytes of direct machine code for K=%d\n", bytes_generated, K);

    float *A = (float*)aligned_alloc(32, K * sizeof(float));
    float *x = (float*)aligned_alloc(32, K * sizeof(float));
    float out_ref = 0.0f;
    float out_jit = 0.0f;

    for (int i = 0; i < K; i++) {
        A[i] = 0.5f * (float)(i % 5);
        x[i] = 1.0f;
        out_ref += A[i] * x[i];
    }

    // Запускаем JIT-скомпилированную функцию напрямую
    jit_gemv_dot_fn fn = (jit_gemv_dot_fn)jit_mem;
    fn(&out_jit, A, x);

    float diff = fabsf(out_ref - out_jit);
    printf("JIT Result: %.4f | Ref Result: %.4f | Diff: %e [%s]\n",
           out_jit, out_ref, diff, diff < 1e-4f ? "BIT-EXACT MATCH" : "FAIL");

    // Замер скорости JIT вызова (1 000 000 вызовов)
    int iters = 1000000;
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < iters; i++) {
        fn(&out_jit, A, x);
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double latency_ns = ((t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) * 1e-9) / iters * 1e9;
    printf("JIT Kernel Call Latency: %.2f ns (%.2f Million dots/sec)\n", latency_ns, 1e9 / latency_ns / 1e6);

    forgelm_jit_free_executable(jit_mem, code_arena_size);
    free(A);
    free(x);
    return (diff < 1e-4f) ? 0 : 1;
}
