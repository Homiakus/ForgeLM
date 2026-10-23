/* forgelm_flash_attn_avx2.s - Register-tiled Flash-Decoding Attention на ассемблере x86-64 AVX2
 *
 * Вычисление внимания для одного токена (decoding step):
 * Out[head_dim] = Attention(Q, K_cache[seq_len, head_dim], V_cache[seq_len, head_dim])
 *
 * Алгоритм (FlashDecode в регистрах без материализации матрицы S = Q * K^T):
 *   1. Масштаб scale = 1.0 / sqrt(head_dim)
 *   2. Онлайн-вычисление Softmax (Online Safe Softmax):
 *      m_new = max(m_old, score_i * scale)
 *      alpha = exp(m_old - m_new)
 *      beta  = exp(score_i * scale - m_new)
 *      l_new = l_old * alpha + beta
 *      acc   = acc * alpha + beta * V_i
 *   3. В конце: Out = acc / l_new
 *
 * void forgelm_flash_decode_f32(float *out, const float *q, const float *k_cache,
 *                               const float *v_cache, int seq_len, int head_dim, float scale);
 *
 * ABI:
 *   RDI: out
 *   RSI: q
 *   RDX: k_cache
 *   RCX: v_cache
 *   R8:  seq_len
 *   R9:  head_dim (кратно 8, например 64, 128)
 *   XMM0: scale
 */

.intel_syntax noprefix
.section .rodata
.align 16
.L_neg_inf:
    .float -1.0e30, -1.0e30, -1.0e30, -1.0e30

.text
.globl forgelm_flash_decode_f32
.type forgelm_flash_decode_f32, @function
forgelm_flash_decode_f32:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 48

    mov r12, rdi             # out
    mov r13, rsi             # q
    mov r14, rdx             # k_cache
    mov r15, rcx             # v_cache
    mov rbx, r8              # seq_len
    mov [rsp], r9            # head_dim
    vmovss [rsp + 8], xmm0   # scale

    test rbx, rbx
    jle .L_flash_ret

    # Инициализация состояния FlashAttention:
    # m = -infinity (xmm14)
    # l = 0.0f (xmm15)
    vmovss xmm14, [.L_neg_inf + rip]
    vxorps xmm15, xmm15, xmm15

    # Инициализируем выходной буфер out нулями (длины head_dim)
    mov rcx, [rsp]
    xor rax, rax
.L_zero_out:
    cmp rax, rcx
    jge .L_start_tokens
    mov dword ptr [r12 + rax*4], 0
    inc rax
    jmp .L_zero_out

.L_start_tokens:
    xor r10, r10             # t = 0 (номер токена в кэше)

.L_token_loop:
    cmp r10, rbx
    jge .L_normalize_done

    # 1. Скалярное произведение score = dot(q, k_cache[t])
    # k_t = k_cache + t * head_dim * 4
    mov rax, r10
    imul rax, [rsp]
    shl rax, 2
    lea rdx, [r14 + rax]     # k_t
    lea rsi, [r15 + rax]     # v_t
    mov [rsp + 16], rsi      # сохраняем v_t на стек

    vxorps ymm0, ymm0, ymm0  # dot acc
    mov rcx, [rsp]
    shr rcx, 3               # head_dim / 8
    xor rax, rax

.L_dot_qk:
    test rcx, rcx
    jz .L_dot_reduce
    vmovups ymm1, [r13 + rax*4]
    vmovups ymm2, [rdx + rax*4]
    vfmadd231ps ymm0, ymm1, ymm2
    add rax, 8
    dec rcx
    jmp .L_dot_qk

.L_dot_reduce:
    vextractf128 xmm1, ymm0, 1
    vaddps xmm0, xmm0, xmm1
    vhaddps xmm0, xmm0, xmm0
    vhaddps xmm0, xmm0, xmm0 # xmm0[0] = q * k_t

    # Умножаем на scale: s = score * scale
    vmulss xmm0, xmm0, [rsp + 8]

    # 2. Онлайн Safe-Softmax
    # m_new = max(m_old, s)
    vmovaps xmm1, xmm14      # m_old
    vmaxss xmm2, xmm1, xmm0  # m_new в xmm2

    # alpha = exp(m_old - m_new)
    # beta  = exp(s - m_new)
    # Вычисляем d_old = m_old - m_new
    vsubss xmm3, xmm1, xmm2
    # Вычисляем d_cur = s - m_new
    vsubss xmm4, xmm0, xmm2

    # Вычисление alpha = exp(d_old):
    vmovss [rsp + 24], xmm3
    fld dword ptr [rsp + 24]
    fldl2e
    fmulp st(1), st(0)       # st0 = x * log2(e)
    fld st(0)
    frndint
    fsub st(1), st(0)
    fxch st(1)
    f2xm1
    fld1
    faddp st(1), st(0)
    fscale
    fstp st(1)
    fstp dword ptr [rsp + 24]
    vmovss xmm5, [rsp + 24]  # xmm5 = alpha

    # Вычисление beta = exp(d_cur):
    vmovss [rsp + 28], xmm4
    fld dword ptr [rsp + 28]
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
    fstp dword ptr [rsp + 28]
    vmovss xmm6, [rsp + 28]  # xmm6 = beta

    # 3. Обновляем l_new = l_old * alpha + beta
    vmulss xmm15, xmm15, xmm5
    vaddss xmm15, xmm15, xmm6
    vmovaps xmm14, xmm2      # m_old = m_new

    # 4. Обновляем вектор out = out * alpha + beta * v_t
    vbroadcastss ymm5, xmm5  # ymm5 = alpha
    vbroadcastss ymm6, xmm6  # ymm6 = beta

    mov rsi, [rsp + 16]      # v_t
    mov rcx, [rsp]
    shr rcx, 3               # head_dim / 8
    xor rax, rax

.L_update_out:
    test rcx, rcx
    jz .L_next_token
    vmovups ymm0, [r12 + rax*4]
    vmovups ymm1, [rsi + rax*4]
    vmulps ymm0, ymm0, ymm5
    vfmadd231ps ymm0, ymm1, ymm6
    vmovups [r12 + rax*4], ymm0
    add rax, 8
    dec rcx
    jmp .L_update_out

.L_next_token:
    inc r10
    jmp .L_token_loop

.L_normalize_done:
    # 5. Итоговая нормализация: out[i] /= l
    vbroadcastss ymm15, xmm15
    mov rcx, [rsp]
    shr rcx, 3
    xor rax, rax

.L_norm_loop:
    test rcx, rcx
    jz .L_flash_ret
    vmovups ymm0, [r12 + rax*4]
    vdivps ymm0, ymm0, ymm15
    vmovups [r12 + rax*4], ymm0
    add rax, 8
    dec rcx
    jmp .L_norm_loop

.L_flash_ret:
    vzeroupper
    add rsp, 48
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
