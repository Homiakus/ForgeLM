// test_gguf.c - Тест валидации GGUF заголовков
#include <stdio.h>
#include <stdint.h>
#include <assert.h>

extern int forgelm_validate_gguf_header(const void *data, uint64_t size, uint32_t *version, uint64_t *tensor_count, uint64_t *kv_count);

int main() {
    printf("=== [ForgeLM] GGUF Binary Header Parser Verification ===\n");

    // Подготовка фиктивного корректного GGUF заголовка
    #pragma pack(push, 1)
    struct GGUFHeader {
        uint32_t magic;
        uint32_t version;
        uint64_t tensor_count;
        uint64_t kv_count;
    } valid_hdr = {
        0x46554747, // "GGUF"
        3,          // version 3
        128,        // 128 tensors
        42          // 42 metadata items
    };
    #pragma pack(pop)

    uint32_t ver = 0;
    uint64_t tc = 0, kv = 0;

    // 1. Тест корректного заголовка
    int res = forgelm_validate_gguf_header(&valid_hdr, sizeof(valid_hdr), &ver, &tc, &kv);
    assert(res == 0);
    assert(ver == 3);
    assert(tc == 128);
    assert(kv == 42);
    printf("[1] Valid GGUF v3: PASS (version=%u, tensors=%lu, kv=%lu)\n", ver, tc, kv);

    // 2. Тест поврежденного magic
    valid_hdr.magic = 0x12345678;
    res = forgelm_validate_gguf_header(&valid_hdr, sizeof(valid_hdr), &ver, &tc, &kv);
    assert(res == -2);
    printf("[2] Corrupted Magic Rejection: PASS\n");

    // 3. Тест буфера недостаточного размера
    res = forgelm_validate_gguf_header(&valid_hdr, 16, &ver, &tc, &kv);
    assert(res == -1);
    printf("[3] Buffer Undersize Protection: PASS\n");

    printf(">>> ALL GGUF PARSER TESTS PASSED! <<<\n");
    return 0;
}
