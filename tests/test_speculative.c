// test_speculative.c - Верификация быстрого спекулятивного N-Gram поиска
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

extern int forgelm_ngram_speculative_match(const int *tokens, int total_tokens, 
                                           int ngram_size, int *out_draft_tokens, int max_draft);

int main() {
    printf("=== [ForgeLM Audit] Pure Assembly Speculative Decoding Engine ===\n");

    // Имитация контекста генерации (повторяющиеся паттерны кода или текста):
    // "for (int i = 0; i < N; i++) { ... } for (int i = 0;" -> спекуляция: "; i < N; i++)"
    int history[] = {
        100, 101, 102, 103, 104, 105, 106, 107, 108,   // первое вхождение
        200, 201, 202,                                  // тело цикла
        100, 101, 102                                   // недавний префикс (ngram=3)
    };
    int total_tokens = sizeof(history) / sizeof(history[0]);
    int draft[8];

    int drafted = forgelm_ngram_speculative_match(history, total_tokens, 3, draft, 4);

    printf("Total Context Length: %d tokens | N-gram size: 3 | Max Draft: 4\n", total_tokens);
    printf("Speculated Drafted Tokens Count: %d\n", drafted);
    for (int i = 0; i < drafted; i++) {
        printf("  Draft [%d] = %d\n", i, draft[i]);
    }

    if (drafted == 4 && draft[0] == 103 && draft[1] == 104 && draft[2] == 105 && draft[3] == 106) {
        printf(">>> SPECULATIVE PATTERN MATCH VERIFIED [PASS] <<<\n");
    } else {
        printf("FAIL: unexpected draft result\n");
        return 1;
    }

    // Замер скорости поиска по контексту 4096 токенов
    int large_ctx_len = 4096;
    int *large_ctx = (int*)malloc(large_ctx_len * sizeof(int));
    for (int i = 0; i < large_ctx_len; i++) large_ctx[i] = i % 256;
    // Вставляем префикс в конец
    large_ctx[large_ctx_len - 3] = 40;
    large_ctx[large_ctx_len - 2] = 41;
    large_ctx[large_ctx_len - 1] = 42;

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    int iters = 100000;
    for (int i = 0; i < iters; i++) {
        forgelm_ngram_speculative_match(large_ctx, large_ctx_len, 3, draft, 4);
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double latency_ns = ((t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) * 1e-9) / iters * 1e9;

    printf("Speculative Search Latency on 4k Context: %.2f ns (%.2f Million lookups/sec)\n", 
           latency_ns, 1e9 / latency_ns / 1e6);

    free(large_ctx);
    return 0;
}
