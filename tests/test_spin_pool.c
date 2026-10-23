// test_spin_pool.c - Высокоскоростной Spin-Wait Thread Pool без оверхеда pthread_create
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <stdatomic.h>
#include <time.h>

extern void forgelm_gemv_row_range_f32(float *out, const float *A, const float *x, 
                                       int start_row, int end_row, int K);

#define NUM_WORKERS 4

typedef struct {
    float *out;
    const float *A;
    const float *x;
    int start_row;
    int end_row;
    int K;
    atomic_int work_signal;
    atomic_int done_signal;
    int stop;
} spin_worker_t;

spin_worker_t workers[NUM_WORKERS];
pthread_t worker_threads[NUM_WORKERS];

void* spin_worker_loop(void *arg) {
    spin_worker_t *w = (spin_worker_t*)arg;
    while (!w->stop) {
        // Ожидание сигнала задачи (spin-wait)
        while (atomic_load_explicit(&w->work_signal, memory_order_acquire) == 0) {
            if (w->stop) return NULL;
            __builtin_ia32_pause();
        }
        forgelm_gemv_row_range_f32(w->out, w->A, w->x, w->start_row, w->end_row, w->K);
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

    float *A = (float*)aligned_alloc(32, M * K * sizeof(float));
    float *x = (float*)aligned_alloc(32, K * sizeof(float));
    float *out = (float*)aligned_alloc(32, M * sizeof(float));

    for (int i = 0; i < M * K; i++) A[i] = 0.001f;
    for (int i = 0; i < K; i++) x[i] = 1.0f;

    int rows_per_worker = M / NUM_WORKERS;
    for (int i = 0; i < NUM_WORKERS; i++) {
        workers[i].out = out;
        workers[i].A = A;
        workers[i].x = x;
        workers[i].start_row = i * rows_per_worker;
        workers[i].end_row = (i == NUM_WORKERS - 1) ? M : (i + 1) * rows_per_worker;
        workers[i].K = K;
        atomic_init(&workers[i].work_signal, 0);
        atomic_init(&workers[i].done_signal, 0);
        workers[i].stop = 0;
        pthread_create(&worker_threads[i], NULL, spin_worker_loop, &workers[i]);
    }

    double t0 = get_time_sec();
    for (int iter = 0; iter < iters; iter++) {
        // Запуск воркеров
        for (int i = 0; i < NUM_WORKERS; i++) {
            atomic_store_explicit(&workers[i].done_signal, 0, memory_order_relaxed);
            atomic_store_explicit(&workers[i].work_signal, 1, memory_order_release);
        }
        // Барьер ожидания
        for (int i = 0; i < NUM_WORKERS; i++) {
            while (atomic_load_explicit(&workers[i].done_signal, memory_order_acquire) == 0) {
                __builtin_ia32_pause();
            }
        }
    }
    double t1 = get_time_sec();

    double avg_ms = ((t1 - t0) / iters) * 1000.0;
    double bw = ((double)M * (double)K * sizeof(float) * 1e-9) / ((t1 - t0) / iters);

    printf("=== [ForgeLM Spin-Wait Pool Performance] ===\n");
    printf("4 Workers Latency: %.3f ms (Bandwidth: %.2f GB/s)\n", avg_ms, bw);

    for (int i = 0; i < NUM_WORKERS; i++) {
        workers[i].stop = 1;
        atomic_store_explicit(&workers[i].work_signal, 1, memory_order_release);
        pthread_join(worker_threads[i], NULL);
    }

    free(A);
    free(x);
    free(out);
    return 0;
}
