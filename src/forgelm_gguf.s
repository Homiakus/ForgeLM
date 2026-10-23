/* forgelm_gguf.s - Низкоуровневый парсер заголовка GGUF на x86-64 ASM
 * GGUF Magic: 0x46554747 ("GGUF" в little-endian)
 */

.intel_syntax noprefix
.text

/* =========================================================================
 * forgelm_validate_gguf_header
 *
 * int forgelm_validate_gguf_header(const void *data, uint64_t size, uint32_t *version, uint64_t *tensor_count, uint64_t *kv_count);
 *
 * ABI:
 *   RDI: data
 *   RSI: size
 *   RDX: version (out)
 *   RCX: tensor_count (out)
 *   R8:  kv_count (out)
 *
 * Возвращает:
 *   0  - успех (валидный GGUF v2/v3)
 *   -1 - буфер слишком мал (< 24 байт)
 *   -2 - неверный magic (не "GGUF")
 *   -3 - неподдерживаемая версия
 * ========================================================================= */
.globl forgelm_validate_gguf_header
.type forgelm_validate_gguf_header, @function
forgelm_validate_gguf_header:
    push rbp
    mov rbp, rsp

    # Проверка размера (минимум заголовок: magic(4) + ver(4) + tensor_count(8) + kv_count(8) = 24 байта)
    cmp rsi, 24
    jb .L_err_small

    # Проверка magic: "GGUF" = 0x46554747
    mov eax, [rdi]
    cmp eax, 0x46554747
    jne .L_err_magic

    # Чтение версии
    mov eax, [rdi + 4]
    cmp eax, 2
    jl .L_err_version
    cmp eax, 3
    jg .L_err_version

    test rdx, rdx
    jz .L_skip_ver
    mov [rdx], eax
.L_skip_ver:

    # tensor_count (uint64_t)
    mov rax, [rdi + 8]
    test rcx, rcx
    jz .L_skip_tc
    mov [rcx], rax
.L_skip_tc:

    # kv_count (uint64_t)
    mov rax, [rdi + 16]
    test r8, r8
    jz .L_skip_kv
    mov [r8], rax
.L_skip_kv:

    xor eax, eax             # 0 = OK
    pop rbp
    ret

.L_err_small:
    mov eax, -1
    pop rbp
    ret

.L_err_magic:
    mov eax, -2
    pop rbp
    ret

.L_err_version:
    mov eax, -3
    pop rbp
    ret
