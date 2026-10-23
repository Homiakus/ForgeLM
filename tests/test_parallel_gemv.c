// test_parallel_gemv.c - Измерение масштабируемости параллельного GEMV (1 поток vs 4 потока)
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <time.h>

extern void forgelm_gemv_row_range_f32(float *out, const float *A, const float *x, 
                                       int start_row, int end_row, int K);

typedef struct {
    float *out;
    const float *A;
    const float *x;
    int start_row;
    int end_row;
    int K;
} worker_args_t;

void* worker_func(void *arg) {
    worker_args_t *args = (worker_args_t*)arg;
    forgelm_gemv_row_range_f32(args->out, args->A, args->x, 
                               args->start_row, args->end_row, args->K);
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
    const int num_threads = 4;
    const int iters = 100;

    printf("=== [ForgeLM Multithreading Audit] 1 Thread vs %d Threads ===\n", num_threads);
    printf("Matrix: %d x %d (%.2f MB)\n", M, K, (double)(M * K * sizeof(float)) / (1024.0 * 1024.0));

    float *A = (float*)aligned_alloc(32, M * K * sizeof(float));
    float *x = (float*)aligned_alloc(32, K * sizeof(float));
    float *out_single = (float*)aligned_alloc(32, M * sizeof(float));
    float *out_parallel = (float*)aligned_alloc(32, M * sizeof(float));

    for (int i = 0; i < M * K; i++) A[i] = 0.001f;
    for (int i = 0; i < K; i++) x[i] = 1.0f;

    // 1. Однопоточный замер
    double t0 = get_time_sec();
    for (int i = 0; i < iters; i++) {
        forgelm_gemv_row_range_f32(out_single, A, x, 0, M, K);
    }
    double t1 = get_time_sec();
    double single_ms = ((t1 - t0) / iters) * 1000.0;
    double single_bw = ((double)M * (double)K * sizeof(float) * 1e-9) / ((t1 - t0) / iters);

    // 2. Многопоточный замер (4 потока)
    pthread_t threads[num_threads];
    worker_args_t args[num_threads];
    int rows_per_thread = M / num_threads;

    for (int t = 0; t < num_threads; t++) {
        args[t].out = out_parallel;
        args[t].A = A;
        args[t].x = x;
        args[t].start_row = t * rows_per_thread;
        args[t].end_row = (t == num_threads - 1) ? M : (t + 1) * rows_per_thread;
        args[t].K = K;
    }

    t0 = get_time_sec();
    for (int i = 0; i < iters; i++) {
        for (int t = 0; t < num_threads; t++) {
            pthread_create(&threads[t], NULL, worker_func, &args[t]);
        }
        for (int t = 0; t < num_threads; t++) {
            pthread_join(threads[t], NULL);
        }
    }
    t1 = get_time_sec();
    double multi_ms = ((t1 - t0) / iters) * 1000.0;
    double multi_bw = ((double)M * (double)K * sizeof(float) * 1e-9) / ((t1 - t0) / iters);

    printf("Single Thread Latency: %.3f ms (Bandwidth: %.2f GB/s)\n", single_ms, single_bw);
    printf("4 Threads Latency:      %.3f ms (Bandwidth: %.2f GB/s)\n", multi_ms, multi_bw);
    printf("Speedup:                %.2fx\n", single_ms / multi_ms);

    free(A);
    free(x);
    free(out_single);
    free(out_parallel);
    return 0;
}
