#ifndef FORGELM_H
#define FORGELM_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Блок квантования Q4_0: 32 веса = 18 байт (2 байта fp16 scale + 16 байт 4-битных весов)
#pragma pack(push, 1)
typedef struct {
    uint16_t d;        // FP16 scale
    uint8_t qs[16];    // 32 ниббла
} forgelm_block_q4_0_t;
#pragma pack(pop)

// Скалярное произведение вектора Q4_0 на float32 вектор
void forgelm_vec_dot_q4_0_f32(float *out, const void *vx, const float *vy, int k);

// Параллельное умножение матрицы Q4_0 на вектор FP32 по диапазону строк [start_row, end_row)
void forgelm_gemv_q4_0_row_range(float *out, const void *A_blocks, const float *x,
                                 int start_row, int end_row, int K);

// GEMV FP32 на диапазон строк
void forgelm_gemv_row_range_f32(float *out, const float *A, const float *x, 
                                int start_row, int end_row, int K);

// Базовые ядра математики
void forgelm_rmsnorm_f32(float *out, const float *x, const float *weight, int n, float eps);
void forgelm_gemv_f32(float *out, const float *A, const float *x, int M, int K);
void forgelm_rope_f32(float *q_or_k, int head_dim, int pos, float theta_base);
void forgelm_softmax_f32(float *x, int n);

// Высокоточное суперблочное квантование Q4_K (256 весов на блок, 4.5 бит/вес)
void forgelm_vec_dot_q4_k_f32(float *out, const void *vx, const float *vy, int k);

// FlashDecoding и внимание
void forgelm_flash_decode_f32(float *out, const float *q, const float *k_cache,
                              const float *v_cache, int seq_len, int head_dim, float scale);

// Токенизация
int forgelm_tokenize_simple(const char *text, int text_len, 
                            const char **vocab_tokens, const int *vocab_lens, 
                            int vocab_size, int *out_tokens, int max_tokens);

// Спекулятивный декодинг
int forgelm_ngram_speculative_match(const int *tokens, int total_tokens, 
                                    int ngram_size, int *out_draft_tokens, int max_draft);

// Постраничный KV-кэш
void* forgelm_paged_kv_alloc(size_t total_bytes);
int   forgelm_paged_kv_free(void *ptr, size_t total_bytes);
void* forgelm_paged_kv_get_slot(void *base, int page_index, int page_size);

// Zero-Libc HTTP Server
int  forgelm_create_server_socket(int port);
void forgelm_http_handle_connection(int client_fd, const char *body, int body_len);

// In-Memory JIT Compilation
void* forgelm_jit_alloc_executable(size_t size);
int   forgelm_jit_free_executable(void *ptr, size_t size);
int   forgelm_jit_compile_gemv_row(void *code_buf, int K);

// Zero-Cost Radix Tree Prompt Caching
int forgelm_radix_find_prefix(const int *prompt_tokens, int prompt_len,
                              const void *root_node, int *out_cached_pages, int max_pages);

// Progressive TUI Menu
void forgelm_tui_render(const char **items, int count, int selected_idx);
int  forgelm_tui_run(void);

#ifdef __cplusplus
}
#endif

#endif // FORGELM_H
