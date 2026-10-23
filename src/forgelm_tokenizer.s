/* forgelm_tokenizer.s - BPE Tokenizer на ассемблере x86-64
 *
 * Токенизатор прямого сопоставления словаря без зависимостей:
 * 1. forgelm_tokenize_bpe: Преобразует входную UTF-8 строку в массив token_id.
 *    Алгоритм: жадное наибольшее совпадение (longest prefix match) по словарю строк.
 *
 * 2. forgelm_detokenize_bpe: Преобразует массив token_id обратно в текст.
 *
 * Структура словаря (vocab):
 *   int vocab_size;
 *   const char* tokens[];
 *   const int token_lens[];
 *
 * int forgelm_tokenize_simple(const char *text, int text_len, 
 *                             const char **vocab_tokens, const int *vocab_lens, 
 *                             int vocab_size, int *out_tokens, int max_tokens);
 */

.intel_syntax noprefix
.text
.globl forgelm_tokenize_simple
.type forgelm_tokenize_simple, @function
forgelm_tokenize_simple:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 48

    mov r12, rdi             # text
    mov r13, rsi             # text_len
    mov r14, rdx             # vocab_tokens (const char**)
    mov r15, rcx             # vocab_lens (const int*)
    mov [rsp], r8            # vocab_size
    mov [rsp + 8], r9        # out_tokens
    # [rbp + 16]: max_tokens

    xor rbx, rbx             # num_tokens_produced = 0
    xor r10, r10             # text_cursor = 0

.L_tok_outer_loop:
    cmp r10, r13
    jge .L_tok_finish

    # Проверка лимита max_tokens
    mov rax, [rbp + 16]
    cmp rbx, rax
    jge .L_tok_finish

    # Поиск самого длинного совпадения в словаре (Greedy match)
    # best_len = 0 (r11), best_id = -1 (rax)
    xor r11, r11
    mov rax, -1
    mov [rsp + 16], rax      # best_id = -1

    # remaining_len = text_len - text_cursor
    mov rdx, r13
    sub rdx, r10             # rdx = remaining_len

    # Перебор всех слов в словаре: i = 0 .. vocab_size - 1
    xor rcx, rcx             # i = 0
    mov r8, [rsp]            # vocab_size

.L_tok_vocab_loop:
    cmp rcx, r8
    jge .L_tok_apply_match

    # len_cand = vocab_lens[i]
    movsxd rax, dword ptr [r15 + rcx*4]
    cmp rax, rdx
    jg .L_tok_vocab_next     # cand длиннее, чем оставшийся текст
    cmp rax, r11
    jle .L_tok_vocab_next    # cand не длиннее текущего best_len

    # Сравниваем строки: text + text_cursor и vocab_tokens[i] длины rax
    mov rsi, [r14 + rcx*8]   # cand_str
    lea rdi, [r12 + r10]     # text_ptr
    push rcx
    push rdx
    mov rcx, rax             # count for repe cmpsb

    # SIMD/Byte compare
    xor rax, rax             # match flag = 0
.L_cmp_loop:
    test rcx, rcx
    jz .L_cmp_matched
    mov dl, [rdi]
    cmp dl, [rsi]
    jne .L_cmp_mismatch
    inc rdi
    inc rsi
    dec rcx
    jmp .L_cmp_loop

.L_cmp_matched:
    mov rax, 1

.L_cmp_mismatch:
    pop rdx
    pop rcx

    test rax, rax
    jz .L_tok_vocab_next

    # Нашли более длинное совпадение:
    movsxd r11, dword ptr [r15 + rcx*4]  # best_len
    mov [rsp + 16], rcx                  # best_id = i

.L_tok_vocab_next:
    inc rcx
    jmp .L_tok_vocab_loop

.L_tok_apply_match:
    # Проверяем, нашли ли совпадение
    cmp qword ptr [rsp + 16], -1
    jne .L_tok_record_token

    # Если ни один токен не подошел - берем одиночный байт как fallback (пропуск 1 байта)
    mov r11, 1
    mov rax, 0               # fallback token 0 (e.g. unknown / raw byte)
    jmp .L_tok_emit

.L_tok_record_token:
    mov rax, [rsp + 16]      # best_id

.L_tok_emit:
    # Записываем токен в out_tokens[rbx]
    mov rdi, [rsp + 8]
    mov [rdi + rbx*4], eax
    inc rbx

    # Сдвигаем курсор на best_len
    add r10, r11
    jmp .L_tok_outer_loop

.L_tok_finish:
    mov rax, rbx             # return num_tokens_produced
    add rsp, 48
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
