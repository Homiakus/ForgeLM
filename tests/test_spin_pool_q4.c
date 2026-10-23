// test_spin_pool_q4.c - Высокоскоростной Spin-Wait Thread Pool для 4-битного квантованного GEMV Q4_0
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <pthread.h>
#include <stdatomic.h>
#include <time.h>
#include <math.h>
#include "forgelm.h"

#define NUM_WORKERS 4

typedef struct {
    float *out;
    const void *A_blocks;
    const float *x;
    int start_row;
    int end_row;
    int K;
    atomic_int work_signal;
    atomic_int done_signal;
    int stop;
} spin_worker_q4_t;

static spin_worker_q4_t workers[NUM_WORKERS];
static pthread_t worker_threads[NUM_WORKERS];

void* spin_worker_q4_loop(void *arg) {
    spin_worker_q4_t *w = (spin_worker_q4_t*)arg;
    while (!w->stop) {
        while (atomic_load_explicit(&w->work_signal, memory_order_acquire) == 0) {
            if (w->stop) return NULL;
            __builtin_ia32_pause();
        }
        forgelm_gemv_q4_0_row_range(w->out, w->A_blocks, w->x, w->start_row, w->end_row, w->K);
        atomic_store_explicit(&w->work_signal, 0, memory_order_release);
        atomic_store_explicit(&w->done_signal, 1, memory_order_release);
    }
    return NULL;
}

static inline double get_time_sec() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

int main() {
    const int M = 4096;
    const int K = 4096;
    const int iters = 100;
    const int nb = K / 32;

    printf("=== [ForgeLM Audit] Parallel Q4_0 Spin-Wait GEMV Engine ===\n");
    printf("Matrix: %d x %d (Quantized Q4_0)\n", M, K);

    // Выделение памяти под Q4_0 веса и векторы
    size_t q4_matrix_bytes = (size_t)M * nb * sizeof(forgelm_block_q4_0_t);
    printf("Memory Footprint: %.2f MB (vs %.2f MB in FP32, compression 3.56x)\n",
           (double)q4_matrix_bytes / (1024.0 * 1024.0),
           (double)(M * K * sizeof(float)) / (1024.0 * 1024.0));

    forgelm_block_q4_0_t *A_blocks = (forgelm_block_q4_0_t*)aligned_alloc(32, q4_matrix_bytes);
    float *x = (float*)aligned_alloc(32, K * sizeof(float));
    float *out_single = (float*)aligned_alloc(32, M * sizeof(float));
    float *out_pool = (float*)aligned_alloc(32, M * sizeof(float));

    // Инициализация псевдовесов
    for (size_t i = 0; i < (size_t)M * nb; i++) {
        A_blocks[i].d = 0x3c00; // fp16 1.0f
        for (int b = 0; b < 16; b++) A_blocks[i].qs[b] = 0x99; // нибблы 9, 9 -> q = 1
    }
    for (int i = 0; i < K; i++) x[i] = 1.0f;

    // 1. Однопоточный расчет и верификация точности
    forgelm_gemv_q4_0_row_range(out_single, A_blocks, x, 0, M, K);

    // 2. Инициализация Spin-Pool
    int rows_per_worker = M / NUM_WORKERS;
    for (int i = 0; i < NUM_WORKERS; i++) {
        workers[i].out = out_pool;
        workers[i].A_blocks = A_blocks;
        workers[i].x = x;
        workers[i].start_row = i * rows_per_worker;
        workers[i].end_row = (i == NUM_WORKERS - 1) ? M : (i + 1) * rows_per_worker;
        workers[i].K = K;
        atomic_init(&workers[i].work_signal, 0);
        atomic_init(&workers[i].done_signal, 0);
        workers[i].stop = 0;
        pthread_create(&worker_threads[i], NULL, spin_worker_q4_loop, &workers[i]);
    }

    // 3. Бенчмарк Spin-Pool на 4 воркерах
    double t0 = get_time_sec();
    for (int iter = 0; iter < iters; iter++) {
        for (int i = 0; i < NUM_WORKERS; i++) {
            atomic_store_explicit(&workers[i].done_signal, 0, memory_order_relaxed);
            atomic_store_explicit(&workers[i].work_signal, 1, memory_order_release);
        }
        for (int i = 0; i < NUM_WORKERS; i++) {
            while (atomic_load_explicit(&workers[i].done_signal, memory_order_acquire) == 0) {
                __builtin_ia32_pause();
            }
        }
    }
    double t1 = get_time_sec();

    // Численная сверка
    float max_diff = 0.0f;
    for (int i = 0; i < M; i++) {
        float d = fabsf(out_single[i] - out_pool[i]);
        if (d > max_diff) max_diff = d;
    }

    double avg_ms = ((t1 - t0) / iters) * 1000.0;
    double eff_bw = ((double)q4_matrix_bytes * 1e-9) / ((t1 - t0) / iters);

    printf("Result Diff (Single vs Pool): %e [%s]\n", max_diff, max_diff == 0.0f ? "BIT-EXACT PASS" : "FAIL");
    printf("4 Workers Latency: %.3f ms\n", avg_ms);
    printf("Effective Memory Bandwidth: %.2f GB/s\n", eff_bw);
    printf("Equivalent FP32 Compute Speed: %.2f GFLOPS\n", (2.0 * M * K * 1e-6) / avg_ms);

    // Остановка воркеров
    for (int i = 0; i < NUM_WORKERS; i++) {
        workers[i].stop = 1;
        atomic_store_explicit(&workers[i].work_signal, 1, memory_order_release);
        pthread_join(worker_threads[i], NULL);
    }

    free(A_blocks);
    free(x);
    free(out_single);
    free(out_pool);
    return 0;
}
