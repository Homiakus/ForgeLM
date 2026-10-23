// test_gguf_tensor.c - Верификация ассемблерного парсера дескрипторов тензоров GGUF
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

extern int forgelm_parse_tensor_descriptor(
    const uint8_t *stream,
    uint64_t stream_len,
    char *out_name,
    uint32_t max_name_len,
    uint32_t *out_type,
    uint64_t *out_offset,
    uint64_t *out_consumed_bytes
);

int main() {
    printf("=== [ForgeLM Audit] GGUF Tensor Descriptor Binary Parser ===\n");

    // Формируем искусственный бинарный дескриптор тензора в памяти:
    // name = "blk.0.attn_q.weight" (len = 19)
    // n_dims = 2 (shape: [4096, 4096])
    // type = 2 (GGML_TYPE_Q4_0)
    // offset = 1048576 (1 MB)
    uint8_t buffer[256];
    memset(buffer, 0, sizeof(buffer));

    uint64_t name_len = 19;
    const char *name_str = "blk.0.attn_q.weight";
    uint32_t n_dims = 2;
    uint64_t dims[2] = {4096, 4096};
    uint32_t type = 2; // Q4_0
    uint64_t offset = 1048576;

    size_t cursor = 0;
    memcpy(buffer + cursor, &name_len, 8); cursor += 8;
    memcpy(buffer + cursor, name_str, name_len); cursor += name_len;
    memcpy(buffer + cursor, &n_dims, 4); cursor += 4;
    memcpy(buffer + cursor, dims, 16); cursor += 16;
    memcpy(buffer + cursor, &type, 4); cursor += 4;
    memcpy(buffer + cursor, &offset, 8); cursor += 8;

    char out_name[64];
    uint32_t out_type = 0;
    uint64_t out_offset = 0;
    uint64_t consumed = 0;

    int ret = forgelm_parse_tensor_descriptor(
        buffer, sizeof(buffer),
        out_name, sizeof(out_name),
        &out_type, &out_offset, &consumed
    );

    printf("Parser ret = %d (Consumed %lu bytes)\n", ret, consumed);
    printf("Extracted Tensor Name: \"%s\" (Expected: \"%s\")\n", out_name, name_str);
    printf("Extracted Tensor Type: %u (Expected: %u)\n", out_type, type);
    printf("Extracted Tensor Offset: %lu (Expected: %lu)\n", out_offset, offset);

    if (ret == 0 && strcmp(out_name, name_str) == 0 && out_type == type && out_offset == offset && consumed == cursor) {
        printf(">>> GGUF TENSOR DESCRIPTOR PARSER VERIFIED [PASS] <<<\n");
        return 0;
    } else {
        printf("FAIL: parsed tensor descriptor mismatch\n");
        return 1;
    }
}
