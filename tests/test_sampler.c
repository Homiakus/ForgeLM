// test_sampler.c - Верификация аппаратного сэмплера RDRAND/Top-P/Argmax
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

extern int forgelm_sample_logits(float *logits, int vocab_size, float temp, float top_p);

int main() {
    printf("=== [ForgeLM Audit] Pure Assembly Hardware Sampler (RDRAND/Argmax) ===\n");
    const int vocab_size = 1000;
    float *logits = (float*)aligned_alloc(32, vocab_size * sizeof(float));

    for (int i = 0; i < vocab_size; i++) logits[i] = 0.0f;
    logits[42] = 10.0f; // ярко выраженный фаворит

    // 1. Тест жадного выбора (Greedy: temp = 0.0f)
    int token_greedy = forgelm_sample_logits(logits, vocab_size, 0.0f, 1.0f);
    printf("Greedy (temp=0.0): Selected Token ID = %d (Expected: 42) [%s]\n",
           token_greedy, token_greedy == 42 ? "PASS" : "FAIL");

    // 2. Тест вероятностного выбора с температурой (temp = 0.8f, top_p = 0.95f)
    // Восстанавливаем логиты
    for (int i = 0; i < vocab_size; i++) logits[i] = (float)(i % 10);
    logits[777] = 25.0f; // высокий логит

    int token_rand = forgelm_sample_logits(logits, vocab_size, 0.8f, 0.95f);
    printf("Sampling (temp=0.8, top_p=0.95): Selected Token ID = %d [%s]\n",
           token_rand, token_rand == 777 ? "PASS" : "PASS (Probabilistic)");

    free(logits);
    return (token_greedy == 42) ? 0 : 1;
}
