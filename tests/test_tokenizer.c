// test_tokenizer.c - Тестирование чистого BPE токенизатора на ассемблере
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

extern int forgelm_tokenize_simple(const char *text, int text_len, 
                                   const char **vocab_tokens, const int *vocab_lens, 
                                   int vocab_size, int *out_tokens, int max_tokens);

int main() {
    printf("=== [ForgeLM Audit] Pure Assembly BPE Tokenizer ===\n");

    // Тестовый мини-словарь (vocab)
    const char *vocab[] = {
        "<unk>",   // 0
        "Hello",   // 1
        " ",       // 2
        "world",   // 3
        "!",       // 4
        "Forge",   // 5
        "LM",      // 6
        "is",      // 7
        "fast",    // 8
        "er",      // 9
        "than",    // 10
        "llama",   // 11
        ".cpp",    // 12
    };
    int vocab_size = sizeof(vocab) / sizeof(vocab[0]);
    int vocab_lens[vocab_size];
    for (int i = 0; i < vocab_size; i++) {
        vocab_lens[i] = strlen(vocab[i]);
    }

    const char *prompt = "ForgeLM is faster than llama.cpp!";
    int prompt_len = strlen(prompt);

    int out_tokens[64];
    int num_tokens = forgelm_tokenize_simple(prompt, prompt_len, vocab, vocab_lens, 
                                             vocab_size, out_tokens, 64);

    printf("Input Prompt: \"%s\" (length %d)\n", prompt, prompt_len);
    printf("Tokenized into %d tokens:\n", num_tokens);

    for (int i = 0; i < num_tokens; i++) {
        int tid = out_tokens[i];
        printf("  [%d] -> Token ID %d (\"%s\")\n", i, tid, vocab[tid]);
    }

    // Проверка правильности разбиения
    // "Forge" (5), "LM" (6), " " (2), "is" (7), " " (2), "fast" (8), "er" (9), " " (2), "than" (10), " " (2), "llama" (11), ".cpp" (12), "!" (4)
    int expected[] = {5, 6, 2, 7, 2, 8, 9, 2, 10, 2, 11, 12, 4};
    int expected_len = sizeof(expected) / sizeof(expected[0]);

    if (num_tokens != expected_len) {
        printf("FAIL: Expected %d tokens, got %d\n", expected_len, num_tokens);
        return 1;
    }

    for (int i = 0; i < expected_len; i++) {
        if (out_tokens[i] != expected[i]) {
            printf("FAIL at position %d: expected %d, got %d\n", i, expected[i], out_tokens[i]);
            return 1;
        }
    }

    // Замер скорости токенизации
    struct timespec ts0, ts1;
    clock_gettime(CLOCK_MONOTONIC, &ts0);
    int iters = 100000;
    for (int i = 0; i < iters; i++) {
        forgelm_tokenize_simple(prompt, prompt_len, vocab, vocab_lens, vocab_size, out_tokens, 64);
    }
    clock_gettime(CLOCK_MONOTONIC, &ts1);
    double latency_ns = ((ts1.tv_sec - ts0.tv_sec) + (ts1.tv_nsec - ts0.tv_nsec) * 1e-9) / iters * 1e9;

    printf("Tokenizer Latency: %.1f ns per prompt (%.2f Million prompts/sec) [PASS]\n",
           latency_ns, 1e9 / latency_ns / 1e6);

    return 0;
}
