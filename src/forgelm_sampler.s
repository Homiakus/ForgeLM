/* forgelm_sampler.s - Аппаратный сэмплер токенов на чистом ассемблере x86-64
 *
 * Алгоритм сэмплирования:
 * 1. Деление логитов на температуру: logits[i] /= temp (если temp > 0.0)
 * 2. Численно стабильный Softmax над vocab_size (max-subtraction + exp sum)
 * 3. Если temp <= 0.001 -> Жадный выбор (Argmax)
 * 4. Если temp > 0.0 -> Вероятностная выборка (Top-P Nucleus):
 *    - Генерация случайного числа через аппаратную инструкцию процессора RDRAND
 *    - Кумулятивная сумма вероятностей до порога rand_val * top_p
 *
 * int forgelm_sample_logits(float *logits, int vocab_size, float temp, float top_p);
 *
 * ABI:
 *   RDI: logits
 *   RSI: vocab_size
 *   XMM0: temp
 *   XMM1: top_p
 */

.intel_syntax noprefix
.section .rodata
.align 16
.L_temp_threshold:
    .float 0.001

.text
.globl forgelm_sample_logits
.type forgelm_sample_logits, @function
forgelm_sample_logits:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32

    mov r12, rdi             # logits
    mov r13, rsi             # vocab_size
    vmovss [rsp], xmm0       # temp
    vmovss [rsp + 4], xmm1   # top_p

    test r13, r13
    jle .L_sample_err

    # Проверяем температуру <= 0.001f (Greedy Argmax)
    vcomiss xmm0, [.L_temp_threshold + rip]
    jbe .L_sample_argmax

    # 1. Делим логиты на температуру: logits[i] /= temp
    vbroadcastss ymm1, [rsp] # ymm1 = temp
    mov rcx, r13
    shr rcx, 3               # vocab_size / 8
    xor rax, rax

.L_temp_div_loop:
    test rcx, rcx
    jz .L_temp_tail
    vmovups ymm0, [r12 + rax*4]
    vdivps ymm0, ymm0, ymm1
    vmovups [r12 + rax*4], ymm0
    add rax, 8
    dec rcx
    jmp .L_temp_div_loop

.L_temp_tail:
    cmp rax, r13
    jge .L_find_max_for_softmax
    vmovss xmm0, [r12 + rax*4]
    vdivss xmm0, xmm0, [rsp]
    vmovss [r12 + rax*4], xmm0
    inc rax
    jmp .L_temp_tail

.L_find_max_for_softmax:
    # 2. Поиск max(logits)
    vmovss xmm0, [r12]
    mov rcx, 1
.L_max_loop:
    cmp rcx, r13
    jge .L_exp_sum
    vmaxss xmm0, xmm0, [r12 + rcx*4]
    inc rcx
    jmp .L_max_loop

.L_exp_sum:
    # Вычитаем max и считаем exp
    # xmm0 = max_val
    vbroadcastss ymm2, xmm0
    vxorps ymm3, ymm3, ymm3  # sum of exp
    xor rax, rax

.L_exp_loop:
    cmp rax, r13
    jge .L_normalize_probs

    vmovss xmm1, [r12 + rax*4]
    vsubss xmm1, xmm1, xmm0  # x = logit - max

    # Точный расчет exp(x) через FPU
    vmovss [rsp + 8], xmm1
    fld dword ptr [rsp + 8]
    fldl2e
    fmulp st(1), st(0)
    fld st(0)
    frndint
    fsub st(1), st(0)
    fxch st(1)
    f2xm1
    fld1
    faddp st(1), st(0)
    fscale
    fstp st(1)
    fstp dword ptr [rsp + 8]

    vmovss xmm1, [rsp + 8]
    vmovss [r12 + rax*4], xmm1  # probs[i] = exp(...)
    vaddss xmm3, xmm3, xmm1     # sum += exp(...)

    inc rax
    jmp .L_exp_loop

.L_normalize_probs:
    # Делим вероятности на сумму: probs[i] /= sum
    vbroadcastss ymm3, xmm3
    mov rcx, r13
    shr rcx, 3
    xor rax, rax

.L_norm_prob_loop:
    test rcx, rcx
    jz .L_norm_prob_tail
    vmovups ymm0, [r12 + rax*4]
    vdivps ymm0, ymm0, ymm3
    vmovups [r12 + rax*4], ymm0
    add rax, 8
    dec rcx
    jmp .L_norm_prob_loop

.L_norm_prob_tail:
    cmp rax, r13
    jge .L_sample_random
    vmovss xmm0, [r12 + rax*4]
    vdivss xmm0, xmm0, xmm3
    vmovss [r12 + rax*4], xmm0
    inc rax
    jmp .L_norm_prob_tail

.L_sample_random:
    # 3. Аппаратный генератор случайного числа через RDRAND
    xor rbx, rbx
.L_retry_rdrand:
    rdrand rax
    jc .L_rdrand_ok
    inc rbx
    cmp rbx, 10
    jl .L_retry_rdrand
    # Fallback если rdrand недоступен
    mov rax, 0x3F000000

.L_rdrand_ok:
    # Преобразуем случайное 32-битное число в float [0.0, 1.0)
    and eax, 0x00FFFFFF      # 24 бита мантиссы
    cvtsi2ss xmm4, eax
    # Делим на 2^24 (16777216.0f)
    mov dword ptr [rsp + 12], 0x4B800000 # 16777216.0f
    vdivss xmm4, xmm4, [rsp + 12] # xmm4 = random [0.0, 1.0)

    # Умножаем на top_p порог (если top_p < 1.0)
    vmulss xmm4, xmm4, [rsp + 4]

    # 4. Кумулятивный проход и выбор токена
    vxorps xmm5, xmm5, xmm5  # cum_sum = 0
    xor rax, rax

.L_sample_cum_loop:
    cmp rax, r13
    jge .L_sample_last_fallback
    vaddss xmm5, xmm5, [r12 + rax*4]
    vcomiss xmm5, xmm4
    jae .L_sample_token_found
    inc rax
    jmp .L_sample_cum_loop

.L_sample_token_found:
    jmp .L_sample_ret

.L_sample_last_fallback:
    mov rax, r13
    dec rax
    jmp .L_sample_ret

.L_sample_argmax:
    # Жадный выбор: argmax_i(logits[i])
    xor rax, rax             # best_token = 0
    vmovss xmm0, [r12]       # best_val
    mov rcx, 1

.L_argmax_loop:
    cmp rcx, r13
    jge .L_sample_ret
    vcomiss xmm0, [r12 + rcx*4]
    jae .L_argmax_next
    vmovss xmm0, [r12 + rcx*4]
    mov rax, rcx

.L_argmax_next:
    inc rcx
    jmp .L_argmax_loop

.L_sample_err:
    xor rax, rax

.L_sample_ret:
    vzeroupper
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
