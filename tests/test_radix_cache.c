// test_radix_cache.c - Верификация Radix Tree Prompt Caching
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

typedef struct radix_node {
    int token_id;
    int page_index;
    uint64_t child_count;
    struct radix_node *children;
    uint64_t padding;
} radix_node_t;

extern int forgelm_radix_find_prefix(
    const int *prompt_tokens,
    int prompt_len,
    const void *root_node,
    int *out_cached_pages,
    int max_pages
);

int main() {
    printf("=== [ForgeLM Audit] Zero-Cost Radix Tree Prompt Caching ===\n");

    // Создаем тестовое дерево префиксов:
    // Root -> [Token 1 (Page 10)] -> [Token 2 (Page 11)] -> [Token 3 (Page 12)]
    radix_node_t n3 = { .token_id = 3, .page_index = 12, .child_count = 0, .children = NULL, .padding = 0 };
    radix_node_t n2 = { .token_id = 2, .page_index = 11, .child_count = 1, .children = &n3, .padding = 0 };
    radix_node_t n1 = { .token_id = 1, .page_index = 10, .child_count = 1, .children = &n2, .padding = 0 };
    radix_node_t root = { .token_id = 0, .page_index = -1, .child_count = 1, .children = &n1, .padding = 0 };

    // Новый промпт: [1, 2, 3, 999, 1000] (первые 3 токена совпадают с закэшированным системным промптом)
    int prompt[] = {1, 2, 3, 999, 1000};
    int prompt_len = sizeof(prompt) / sizeof(prompt[0]);
    int cached_pages[8];

    int matched = forgelm_radix_find_prefix(prompt, prompt_len, &root, cached_pages, 8);

    printf("Prompt Length: %d tokens\n", prompt_len);
    printf("Matched Cached Tokens/Pages: %d (Expected: 3)\n", matched);
    for (int i = 0; i < matched; i++) {
        printf("  Prefix [%d]: Token %d -> Reused KV Page %d\n", i, prompt[i], cached_pages[i]);
    }

    if (matched == 3 && cached_pages[0] == 10 && cached_pages[1] == 11 && cached_pages[2] == 12) {
        printf(">>> RADIX PROMPT CACHING VERIFIED [PASS] <<<\n");
    } else {
        printf("FAIL: radix match mismatch\n");
        return 1;
    }

    // Замер скорости поиска префикса
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    int iters = 1000000;
    for (int i = 0; i < iters; i++) {
        forgelm_radix_find_prefix(prompt, prompt_len, &root, cached_pages, 8);
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double latency_ns = ((t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) * 1e-9) / iters * 1e9;
    printf("Prefix Lookup Latency: %.2f ns (%.2f Million lookups/sec)\n", latency_ns, 1e9 / latency_ns / 1e6);

    return 0;
}
