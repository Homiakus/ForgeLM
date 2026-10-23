/* forgelm_gguf_tensor.s - Парсер дескрипторов тензоров GGUF на x86-64 ASM
 *
 * Формат дескриптора тензора в бинарном GGUF потоке:
 *   uint64_t name_len;
 *   char name[name_len];
 *   uint32_t n_dimensions;
 *   uint64_t dimensions[n_dimensions];
 *   uint32_t type;            // GGML_TYPE (0=F32, 1=F16, 2=Q4_0, 12=Q4_K, etc.)
 *   uint64_t offset;          // смещение относительно начала блока весов
 *
 * int forgelm_parse_tensor_descriptor(
 *     const uint8_t *stream,
 *     uint64_t stream_len,
 *     char *out_name,
 *     uint32_t max_name_len,
 *     uint32_t *out_type,
 *     uint64_t *out_offset,
 *     uint64_t *out_consumed_bytes
 * );
 */

.intel_syntax noprefix
.text
.globl forgelm_parse_tensor_descriptor
.type forgelm_parse_tensor_descriptor, @function
forgelm_parse_tensor_descriptor:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 48

    mov r12, rdi             # stream
    mov r13, rsi             # stream_len
    mov r14, rdx             # out_name
    mov [rsp], rcx           # max_name_len
    mov [rsp + 8], r8        # out_type
    mov [rsp + 16], r9       # out_offset
    # [rbp + 16]: out_consumed_bytes

    # Минимум для чтения длины имени (8 байт)
    cmp r13, 8
    jb .L_td_err

    # 1. Читаем name_len
    mov rbx, [r12]           # name_len
    lea r15, [r12 + 8]       # ptr to name chars
    mov rax, 8
    add rax, rbx             # текущий курсор

    # Проверяем, помещается ли имя в поток
    cmp rax, r13
    ja .L_td_err

    # Копируем имя в out_name
    test r14, r14
    jz .L_td_skip_copy
    mov rcx, rbx
    cmp rcx, [rsp]           # max_name_len - 1
    jb .L_td_copy_len_ok
    mov rcx, [rsp]
    test rcx, rcx
    jz .L_td_skip_copy
    dec rcx                  # оставляем 1 байт под null terminator

.L_td_copy_len_ok:
    xor rdx, rdx
.L_td_name_copy_loop:
    test rcx, rcx
    jz .L_td_name_null_term
    mov r8b, [r15 + rdx]
    mov [r14 + rdx], r8b
    inc rdx
    dec rcx
    jmp .L_td_name_copy_loop

.L_td_name_null_term:
    mov byte ptr [r14 + rdx], 0

.L_td_skip_copy:
    # 2. Читаем n_dimensions (uint32_t = 4 байта)
    lea r10, [r12 + rax]
    mov rdx, rax
    add rdx, 4
    cmp rdx, r13
    ja .L_td_err

    mov ecx, [r10]           # n_dims
    add rax, 4

    # 3. Пропускаем массив dimensions (n_dims * 8 байт)
    mov r11, rcx
    shl r11, 3               # n_dims * 8
    add rax, r11
    cmp rax, r13
    ja .L_td_err

    # 4. Читаем type (uint32_t = 4 байта) и offset (uint64_t = 8 байт) -> 12 байт
    mov rdx, rax
    add rdx, 12
    cmp rdx, r13
    ja .L_td_err

    lea r10, [r12 + rax]
    mov ecx, [r10]           # type
    mov r8, [rsp + 8]        # out_type
    test r8, r8
    jz .L_td_skip_type
    mov [r8], ecx
.L_td_skip_type:

    mov r11, [r10 + 4]       # offset
    mov r9, [rsp + 16]       # out_offset
    test r9, r9
    jz .L_td_skip_offset
    mov [r9], r11
.L_td_skip_offset:

    add rax, 12              # rax = total consumed bytes

    # Записываем consumed bytes
    mov r8, [rbp + 16]
    test r8, r8
    jz .L_td_ok
    mov [r8], rax

.L_td_ok:
    xor eax, eax             # 0 = OK
    jmp .L_td_exit

.L_td_err:
    mov eax, -1

.L_td_exit:
    add rsp, 48
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
