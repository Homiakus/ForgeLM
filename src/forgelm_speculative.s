/* forgelm_speculative.s - ASM N-Gram Prompt & Speculative Lookup Cache
 *
 * Ускорение декодирования:
 * Поиск префикса из последних K токенов (например K=3) в истории контекста.
 * Если найден идентичный N-gram, извлекаются следующие M токенов (спекулятивные кандидаты).
 *
 * int forgelm_ngram_speculative_match(const int *tokens, int total_tokens, 
 *                                     int ngram_size, int *out_draft_tokens, int max_draft);
 *
 * Возвращает: число предсказанных токенов (0 если совпадений нет)
 */

.intel_syntax noprefix
.text
.globl forgelm_ngram_speculative_match
.type forgelm_ngram_speculative_match, @function
forgelm_ngram_speculative_match:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32

    mov r12, rdi             # tokens
    mov r13, rsi             # total_tokens
    mov r14, rdx             # ngram_size
    mov r15, rcx             # out_draft_tokens
    mov [rsp], r8            # max_draft

    # Если токенов меньше, чем ngram_size + 1, спекулировать не из чего
    mov rax, r14
    inc rax
    cmp r13, rax
    jl .L_spec_no_match

    # Указатель на целевой n-gram в конце: target = tokens + (total_tokens - ngram_size)
    mov rax, r13
    sub rax, r14
    lea rbx, [r12 + rax*4]   # rbx = ptr to recent n-gram

    # Ищем совпадение в истории: pos от (total_tokens - ngram_size - 1) вниз до 0
    mov r10, r13
    sub r10, r14
    dec r10                  # r10 = candidate search index

.L_spec_search_loop:
    cmp r10, 0
    jl .L_spec_no_match

    # Сравниваем ngram_size токенов: candidate = tokens + r10 vs recent = rbx
    lea rsi, [r12 + r10*4]
    mov rdi, rbx
    mov rcx, r14             # ngram_size
    xor rax, rax             # match mismatch flag

.L_spec_cmp_token:
    test rcx, rcx
    jz .L_spec_found_match
    mov edx, [rsi]
    cmp edx, [rdi]
    jne .L_spec_search_next
    add rsi, 4
    add rdi, 4
    dec rcx
    jmp .L_spec_cmp_token

.L_spec_search_next:
    dec r10
    jmp .L_spec_search_loop

.L_spec_found_match:
    # Совпадение найдено в позиции r10!
    # Кандидаты следуют сразу за n-gram: draft_start = r10 + ngram_size
    mov r8, r10
    add r8, r14              # r8 = draft_start_index

    # Сколько токенов доступно до конца недавнего n-gram?
    # avail = (total_tokens - ngram_size) - draft_start
    mov r9, r13
    sub r9, r14
    sub r9, r8
    cmp r9, [rsp]            # max_draft
    jle .L_spec_copy_count
    mov r9, [rsp]

.L_spec_copy_count:
    test r9, r9
    jle .L_spec_no_match

    # Копируем r9 токенов в out_draft_tokens
    # r12 + r8*4 = указатель на источник
    lea rsi, [r12 + r8*4]
    xor rcx, rcx
.L_spec_copy_tokens:
    cmp rcx, r9
    jge .L_spec_success
    mov eax, [rsi + rcx*4]
    mov [r15 + rcx*4], eax
    inc rcx
    jmp .L_spec_copy_tokens

.L_spec_success:
    mov rax, r9              # возвращаем число спекулированных токенов
    jmp .L_spec_exit

.L_spec_no_match:
    xor rax, rax

.L_spec_exit:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
