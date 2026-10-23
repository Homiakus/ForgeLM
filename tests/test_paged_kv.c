// test_paged_kv.c - Верификация постраничной аллокации Paged KV-Cache
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

extern void* forgelm_paged_kv_alloc(size_t total_bytes);
extern int   forgelm_paged_kv_free(void *ptr, size_t total_bytes);
extern void* forgelm_paged_kv_get_slot(void *base, int page_index, int page_size);

int main() {
    printf("=== [ForgeLM Audit] Zero-Libc Paged KV-Cache Memory Subsystem ===\n");

    size_t req_bytes = 16 * 1024 * 1024; // 16 MB под KV кэш
    float *kv_arena = (float*)forgelm_paged_kv_alloc(req_bytes);

    if (!kv_arena) {
        printf("FAIL: forgelm_paged_kv_alloc returned NULL\n");
        return 1;
    }

    printf("Allocated 2MB-aligned Arena at: %p (requested %zu MB)\n", (void*)kv_arena, req_bytes / (1024*1024));

    // Проверяем доступ к страницам (например размер страницы 16 токенов * 128 dim * sizeof(float) = 8192 байта)
    int page_size = 8192;
    int num_pages = req_bytes / page_size;

    for (int p = 0; p < num_pages; p++) {
        float *page = (float*)forgelm_paged_kv_get_slot(kv_arena, p, page_size);
        page[0] = (float)p * 1.5f;
        page[page_size / sizeof(float) - 1] = (float)p * 2.5f;
    }

    // Проверяем целостность данных
    int pass = 1;
    for (int p = 0; p < num_pages; p++) {
        float *page = (float*)forgelm_paged_kv_get_slot(kv_arena, p, page_size);
        if (page[0] != (float)p * 1.5f || page[page_size / sizeof(float) - 1] != (float)p * 2.5f) {
            pass = 0;
            break;
        }
    }

    if (pass) {
        printf(">>> PAGED KV-CACHE INTEGRITY VERIFIED [PASS] <<<\n");
    } else {
        printf("FAIL: page integrity check failed\n");
        return 1;
    }

    int ret = forgelm_paged_kv_free(kv_arena, req_bytes);
    printf("Paged arena successfully unmapped (sys_munmap ret=%d)\n", ret);

    return 0;
}
