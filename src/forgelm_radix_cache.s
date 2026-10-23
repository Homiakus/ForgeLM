/* forgelm_radix_cache.s - Ассемблерное Radix Tree для Zero-Cost Prompt Caching
 *
 * При многократных запросах с одинаковым системным промптом вычисление KV-кэша
 * пропускается, возвращая ранее вычисленные индексы страниц.
 *
 * Структура узла дерева (radix node = 32 байта):
 *   int token_id;            // токен (4 байта)
 *   int page_index;          // индекс страницы KV кэша (4 байта)
 *   uint64_t child_count;    // число потомков (8 байт)
 *   struct radix_node *children; // указатель на массив детей (8 байт)
 *   uint64_t padding;        // 8 байт
 *
 * int forgelm_radix_find_prefix(
 *     const int *prompt_tokens,
 *     int prompt_len,
 *     const void *root_node,
 *     int *out_cached_pages,
 *     int max_pages
 * );
 */

.intel_syntax noprefix
.text
.globl forgelm_radix_find_prefix
.type forgelm_radix_find_prefix, @function
/*
 * int forgelm_radix_find_prefix(...)
 * ABI:
 *   RDI: prompt_tokens
 *   RSI: prompt_len
 *   RDX: root_node
 *   RCX: out_cached_pages
 *   R8:  max_pages
 * Возвращает: число совпавших токенов/страниц
 */
forgelm_radix_find_prefix:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             # prompt_tokens
    mov r13, rsi             # prompt_len
    mov r14, rdx             # curr_node
    mov r15, rcx             # out_cached_pages
    mov rbx, r8              # max_pages

    xor rax, rax             # matched_count = 0

.L_radix_outer:
    cmp rax, r13
    jge .L_radix_done
    cmp rax, rbx
    jge .L_radix_done

    test r14, r14
    jz .L_radix_done

    # Ищем следующий токен prompt_tokens[rax] среди children текущего узла
    mov edx, [r12 + rax*4]   # target_token
    mov r8, [r14 + 8]        # child_count (offset 8)
    mov r9, [r14 + 16]       # children array ptr (offset 16)

    test r8, r8
    jz .L_radix_done
    test r9, r9
    jz .L_radix_done

    # Перебор потомков
    xor r10, r10             # child_idx = 0
.L_radix_child_search:
    cmp r10, r8
    jge .L_radix_done        # токен не найден в детях -> префикс завершен

    # Ребенок child_ptr = r9 + r10 * 32
    mov r11, r10
    shl r11, 5
    lea r11, [r9 + r11]

    # Сравниваем child->token_id (offset 0)
    mov ecx, [r11]
    cmp ecx, edx
    je .L_radix_matched_child

    inc r10
    jmp .L_radix_child_search

.L_radix_matched_child:
    # Сохраняем child->page_index (offset 4) в out_cached_pages[rax]
    mov ecx, [r11 + 4]
    test r15, r15
    jz .L_radix_advance
    mov [r15 + rax*4], ecx

.L_radix_advance:
    inc rax                  # matched_count++
    mov r14, r11             # curr_node = child
    jmp .L_radix_outer

.L_radix_done:
    # rax содержит число совпавших токенов
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
