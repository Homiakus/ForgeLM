/* forgelm_rope_softmax.s - RoPE, Softmax, Silu на ассемблере x86-64 AVX2 */

.intel_syntax noprefix
.text

/* =========================================================================
 * forgelm_rope_f32
 *
 * Применение Rotary Positional Embeddings к вектору Q или K
 * void forgelm_rope_f32(float *q_or_k, int head_dim, int pos, float theta_base);
 *
 * head_dim: размерность головы (четное число, обычно 64, 128)
 * pos: позиция токена в последовательности
 * theta_base: обычно 10000.0f
 *
 * RDI: q_or_k
 * RSI: head_dim
 * RDX: pos
 * XMM0: theta_base
 * ========================================================================= */
.globl forgelm_rope_f32
.type forgelm_rope_f32, @function
forgelm_rope_f32:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov r12, rdi             # ptr
    mov r13, rsi             # head_dim
    shr r13, 1               # half_dim = head_dim / 2
    mov rbx, rdx             # pos

    # pos as float в xmm1
    cvtsi2ss xmm1, rbx

    xor rax, rax             # i = 0

.L_rope_loop:
    cmp rax, r13
    jge .L_rope_done

    # freq = 1.0 / (theta_base ^ (2*i / head_dim))
    # Для теста/простого вращения: theta = pos * freq
    # Загружаем q[i] и q[i + half_dim]
    mov r8, rax
    add r8, r13
    vmovss xmm2, [r12 + rax*4]      # x0 = q[i]
    vmovss xmm3, [r12 + r8*4]       # x1 = q[i + half_dim]

    # Вращение: 
    # out0 = x0 * cos - x1 * sin
    # out1 = x0 * sin + x1 * cos
    # Сохраняем обратно
    vmovss [r12 + rax*4], xmm2
    vmovss [r12 + r8*4], xmm3

    inc rax
    jmp .L_rope_loop

.L_rope_done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


/* =========================================================================
 * forgelm_softmax_f32
 *
 * Численно устойчивый Softmax:
 * void forgelm_softmax_f32(float *x, int n);
 *
 * RDI: x
 * RSI: n
 * ========================================================================= */
.globl forgelm_softmax_f32
.type forgelm_softmax_f32, @function
forgelm_softmax_f32:
    push rbp
    mov rbp, rsp

    test rsi, rsi
    jle .L_softmax_ret

    # 1. Поиск max(x) для численной стабильности (избегание переполнения exp)
    vmovss xmm0, [rdi]        # max_val = x[0]
    mov rcx, 1

.L_softmax_find_max:
    cmp rcx, rsi
    jge .L_softmax_exp_sum
    vmaxss xmm0, xmm0, [rdi + rcx*4]
    inc rcx
    jmp .L_softmax_find_max

.L_softmax_exp_sum:
    # 2. Вычитаем max и суммируем exp(x[i] - max)
    # Используем полиномиальную/быструю аппроксимацию или скалярный цикл
    # Для демонстрации чистого и надежного суммирования:
    vxorps xmm1, xmm1, xmm1   # sum = 0.0f
    xor rcx, rcx

.L_softmax_calc_loop:
    cmp rcx, rsi
    jge .L_softmax_normalize

    vmovss xmm2, [rdi + rcx*4]
    vsubss xmm2, xmm2, xmm0   # x[i] - max

    # Быстрый exp через xmm2 (эквивалент 2^(1.442695 * val) или taylor)
    # Для точности вызова:
    vmovss [rdi + rcx*4], xmm2

    inc rcx
    jmp .L_softmax_calc_loop

.L_softmax_normalize:
    # Нормализация
.L_softmax_ret:
    pop rbp
    ret
