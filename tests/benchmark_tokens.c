#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

#pragma pack(push, 1)
typedef struct {
    uint16_t d;
    uint8_t qs[16];
} block_q4_0;
#pragma pack(pop)

extern void forgelm_vec_dot_q4_0_f32(float *out, const void *vx, const float *vy, int k);

static inline double get_time_sec() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

int main() {
    // Архитектура Phi-4 Mini (3.8B параметров):
    // Вес модели в памяти (Q4): ~2.45 GB
    // Число слоев: 32
    // На 1 токен авторегрессионного декодирования (batch=1) необходимо
    // прочитать через ядра матричного умножения ровно весь вес модели: ~2.45 GB
    const size_t model_bytes = 2450000000ULL; // 2.45 GB
    const int k = 3072; // hidden dim
    const int nb = k / 32;

    block_q4_0 *row = (block_q4_0*)malloc(nb * sizeof(block_q4_0));
    float *y = (float*)malloc(k * sizeof(float));
    for (int i = 0; i < nb; i++) {
        row[i].d = 0x3c00; // fp16 1.0f
        for (int j = 0; j < 16; j++) row[i].qs[j] = 0x88;
    }
    for (int i = 0; i < k; i++) y[i] = 1.0f;

    float out = 0.0f;
    // Прогрев ядра
    forgelm_vec_dot_q4_0_f32(&out, row, y, k);

    // Замер скорости скалярного произведения Q4_0 на AVX2
    int iters = 100000;
    double t0 = get_time_sec();
    for (int i = 0; i < iters; i++) {
        forgelm_vec_dot_q4_0_f32(&out, row, y, k);
    }
    double t1 = get_time_sec();
    double total_time = t1 - t0;
    double dot_latency_us = (total_time / iters) * 1e6;
    double bytes_per_dot = nb * sizeof(block_q4_0);
    double bandwidth_gbs = (bytes_per_dot * iters * 1e-9) / total_time;

    // Расчет теоретического времени декодирования 1 токена при чтении 2.45 GB через ASM ядро:
    double sec_per_token_compute = (double)model_bytes / (bandwidth_gbs * 1e9);
    double tokens_per_sec_compute = 1.0 / sec_per_token_compute;

    // С учетом физического лимита DDR4 памяти процессора (DDR4-2666 dual-channel ~ 21.3 GB/s peak, ~17 GB/s real):
    double dram_bandwidth_gbs = 17.0; 
    double tokens_per_sec_memory_bound = dram_bandwidth_gbs / (2.45);

    printf("=== [ForgeLM Pure ASM] Q4_0 Kernel Throughput Benchmark ===\n");
    printf("Hidden Dim: %d (block count: %d)\n", k, nb);
    printf("Q4_0 Dot latency: %.3f us\n", dot_latency_us);
    printf("AVX2 Register Dequant Bandwidth: %.2f GB/s\n", bandwidth_gbs);
    printf("Theoretical Peak Compute Token Rate: %.2f tokens/sec\n", tokens_per_sec_compute);
    printf("Physical Memory-Bound Token Rate (DDR4 17 GB/s): %.2f tokens/sec\n", tokens_per_sec_memory_bound);

    free(row);
    free(y);
    return 0;
}
