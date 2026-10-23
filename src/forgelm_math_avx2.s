/* forgelm_math_avx2.s - Исправленные численные ядра AVX2 + FMA */

.intel_syntax noprefix
.text

/* =========================================================================
 * forgelm_rmsnorm_f32
 *
 * void forgelm_rmsnorm_f32(float *out, const float *x, const float *w, int dim, float eps);
 *
 * ABI:
 *   RDI: out
 *   RSI: x
 *   RDX: w
 *   ECX: dim
 *   XMM0: eps
 * ========================================================================= */
.globl forgelm_rmsnorm_f32
.type forgelm_rmsnorm_f32, @function
forgelm_rmsnorm_f32:
    push rbp
    mov rbp, rsp

    # 1. Сумма квадратов
    vxorps ymm1, ymm1, ymm1   # acc
    mov eax, ecx
    shr eax, 3               # blocks of 8
    xor r8, r8               # idx = 0

.L_rms_sum_loop:
    test eax, eax
    jz .L_rms_reduce
    vmovups ymm2, [rsi + r8*4]
    vfmadd231ps ymm1, ymm2, ymm2
    add r8, 8
    dec eax
    jmp .L_rms_sum_loop

.L_rms_reduce:
    # Горизонтальная сумма ymm1 -> xmm1 (1 float)
    vextractf128 xmm2, ymm1, 1
    vaddps xmm1, xmm1, xmm2
    vhaddps xmm1, xmm1, xmm1
    vhaddps xmm1, xmm1, xmm1

    # mean = sum / dim
    cvtsi2ss xmm2, ecx
    vdivss xmm1, xmm1, xmm2

    # scale = 1.0f / sqrtf(mean + eps)
    vaddss xmm1, xmm1, xmm0
    vsqrtss xmm1, xmm1, xmm1
    mov eax, 0x3f800000       # 1.0f
    vmovd xmm3, eax
    vdivss xmm1, xmm3, xmm1   # xmm1 = scale
    vbroadcastss ymm1, xmm1   # ymm1 = [scale, ...]

    # out[i] = x[i] * scale * w[i]
    mov eax, ecx
    shr eax, 3
    xor r8, r8

.L_rms_norm_loop:
    test eax, eax
    jz .L_rms_done
    vmovups ymm2, [rsi + r8*4]
    vmovups ymm3, [rdx + r8*4]
    vmulps ymm2, ymm2, ymm1
    vmulps ymm2, ymm2, ymm3
    vmovups [rdi + r8*4], ymm2
    add r8, 8
    dec eax
    jmp .L_rms_norm_loop

.L_rms_done:
    vzeroupper
    pop rbp
    ret


/* =========================================================================
 * forgelm_gemv_f32
 *
 * void forgelm_gemv_f32(float *out, const float *A, const float *x, int M, int K);
 *
 * ABI:
 *   RDI: out
 *   RSI: A
 *   RDX: x
 *   RCX: M
 *   R8:  K
 * ========================================================================= */
.globl forgelm_gemv_f32
.type forgelm_gemv_f32, @function
forgelm_gemv_f32:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             # out
    mov r13, rsi             # A
    mov r14, rdx             # x
    mov r15, rcx             # M
    mov rbx, r8              # K

    xor r9, r9               # m = 0

.L_gemv_row:
    cmp r9, r15
    jge .L_gemv_finish

    # A_row = A + m * K
    mov rax, r9
    imul rax, rbx
    shl rax, 2
    lea r10, [r13 + rax]

    vxorps ymm0, ymm0, ymm0  # sum_vec
    xor r11, r11             # k = 0
    mov rax, rbx
    shr rax, 3               # K / 8

.L_gemv_col:
    test rax, rax
    jz .L_gemv_red
    vmovups ymm1, [r10 + r11*4]
    vmovups ymm2, [r14 + r11*4]
    vfmadd231ps ymm0, ymm1, ymm2
    add r11, 8
    dec rax
    jmp .L_gemv_col

.L_gemv_red:
    # Горизонтальная редукция ymm0
    vextractf128 xmm1, ymm0, 1
    vaddps xmm0, xmm0, xmm1
    vhaddps xmm0, xmm0, xmm0
    vhaddps xmm0, xmm0, xmm0

    vmovss [r12 + r9*4], xmm0
    inc r9
    jmp .L_gemv_row

.L_gemv_finish:
    vzeroupper
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
