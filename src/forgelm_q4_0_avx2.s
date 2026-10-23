/* forgelm_q4_0_avx2.s - Высокоскоростное скалярное произведение Q4_0 на AVX2 (PIC/PIE-совместимое)
 * 
 * Формат блока Q4_0 (размер блока 32 элемента = 18 байт):
 *   float16 d;        // 2 байта (FP16 масштабный коэффициент)
 *   uint8_t qs[16];   // 16 байт (32 4-битных квантованных значения, смещенных на -8: q = nibble - 8)
 *
 * void forgelm_vec_dot_q4_0_f32(float *out, const void *vx, const float *vy, int k);
 */

.intel_syntax noprefix
.section .rodata
.align 32
.L_mask_low_nibble:
    .byte 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F
    .byte 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F
    .byte 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F
    .byte 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F

.align 32
.L_offset_eight:
    .byte 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8
    .byte 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8

.text
.globl forgelm_vec_dot_q4_0_f32
.type forgelm_vec_dot_q4_0_f32, @function
forgelm_vec_dot_q4_0_f32:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    vxorps ymm0, ymm0, ymm0    # float accumulator

    mov r8, rcx
    shr r8, 5                  # nb = k / 32
    test r8, r8
    jz .L_q4_0_done

    mov r12, rsi               # vx
    mov r13, rdx               # vy
    xor rax, rax               # block_idx = 0

    # Загружаем маски в xmm10 и xmm11 через RIP-relative адресацию
    vmovdqa xmm10, [.L_mask_low_nibble + rip]
    vmovdqa xmm11, [.L_offset_eight + rip]

.L_q4_0_block_loop:
    # 1. fp16 scale d из [r12] -> float32
    vcvtph2ps xmm1, [r12]
    vbroadcastss ymm1, xmm1

    # 2. Нибблы [r12 + 2]
    vmovdqu xmm2, [r12 + 2]

    # Нижние 4 бита
    vpand xmm3, xmm2, xmm10
    vpsubb xmm3, xmm3, xmm11

    # Верхние 4 бита
    vpsrlw xmm4, xmm2, 4
    vpand xmm4, xmm4, xmm10
    vpsubb xmm4, xmm4, xmm11

    # 3. int8 -> int32 -> float32 (0..7)
    vpmovsxbd ymm5, xmm3
    vcvtdq2ps ymm5, ymm5
    vmulps ymm5, ymm5, ymm1
    vmovups ymm6, [r13]
    vfmadd231ps ymm0, ymm5, ymm6

    # 8..15
    vpsrldq xmm7, xmm3, 8
    vpmovsxbd ymm5, xmm7
    vcvtdq2ps ymm5, ymm5
    vmulps ymm5, ymm5, ymm1
    vmovups ymm6, [r13 + 32]
    vfmadd231ps ymm0, ymm5, ymm6

    # 16..23
    vpmovsxbd ymm5, xmm4
    vcvtdq2ps ymm5, ymm5
    vmulps ymm5, ymm5, ymm1
    vmovups ymm6, [r13 + 64]
    vfmadd231ps ymm0, ymm5, ymm6

    # 24..31
    vpsrldq xmm7, xmm4, 8
    vpmovsxbd ymm5, xmm7
    vcvtdq2ps ymm5, ymm5
    vmulps ymm5, ymm5, ymm1
    vmovups ymm6, [r13 + 96]
    vfmadd231ps ymm0, ymm5, ymm6

    add r12, 18
    add r13, 128
    inc rax
    cmp rax, r8
    jl .L_q4_0_block_loop

.L_q4_0_done:
    vextractf128 xmm1, ymm0, 1
    vaddps xmm0, xmm0, xmm1
    vhaddps xmm0, xmm0, xmm0
    vhaddps xmm0, xmm0, xmm0

    vmovss [rdi], xmm0

    vzeroupper
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

/* =========================================================================
 * forgelm_gemv_q4_0_row_range
 * 
 * Параллельное умножение квантованной матрицы Q4_0 на вектор FP32 для диапазона строк
 * void forgelm_gemv_q4_0_row_range(float *out, const void *A_blocks, const float *x,
 *                                  int start_row, int end_row, int K);
 *
 * ABI:
 *   RDI: out
 *   RSI: A_blocks (указатель на непрерывный массив блоков Q4_0 матрицы M x K)
 *   RDX: x (float32 вектор длины K)
 *   RCX: start_row
 *   R8:  end_row
 *   R9:  K (кратно 32)
 * ========================================================================= */
.globl forgelm_gemv_q4_0_row_range
.type forgelm_gemv_q4_0_row_range, @function
forgelm_gemv_q4_0_row_range:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             # out
    mov r13, rsi             # A_blocks
    mov r14, rdx             # x
    mov r15, r8              # end_row
    mov rbx, r9              # K

    # Число блоков на одну строку: nb = K / 32
    mov rax, rbx
    shr rax, 5
    # Размер одной строки в байтах: row_bytes = nb * 18
    imul rax, 18
    push rax                 # [rsp] = row_bytes

    # Загружаем константы нибблов в xmm10 и xmm11
    vmovdqa xmm10, [.L_mask_low_nibble + rip]
    vmovdqa xmm11, [.L_offset_eight + rip]

    mov r8, rcx              # curr_row = start_row

.L_gemv_q4_row_loop:
    cmp r8, r15
    jge .L_gemv_q4_exit

    # Вычисляем указатель на начало текущей строки:
    # A_row = A_blocks + curr_row * row_bytes
    mov rax, r8
    imul rax, [rsp]          # curr_row * row_bytes
    lea r10, [r13 + rax]     # r10 = ptr to current row's blocks

    mov r11, r14             # r11 = ptr to x
    vxorps ymm0, ymm0, ymm0  # sum accumulator

    # Число блоков: cnt = K / 32
    mov rax, rbx
    shr rax, 5

.L_gemv_q4_inner_loop:
    test rax, rax
    jz .L_gemv_q4_inner_done

    # 1. Scale FP16 -> Float32
    vcvtph2ps xmm1, [r10]
    vbroadcastss ymm1, xmm1

    # 2. 16 байт нибблов
    vmovdqu xmm2, [r10 + 2]

    vpand xmm3, xmm2, xmm10
    vpsubb xmm3, xmm3, xmm11

    vpsrlw xmm4, xmm2, 4
    vpand xmm4, xmm4, xmm10
    vpsubb xmm4, xmm4, xmm11

    # Четверти блока (0..7, 8..15, 16..23, 24..31)
    vpmovsxbd ymm5, xmm3
    vcvtdq2ps ymm5, ymm5
    vmulps ymm5, ymm5, ymm1
    vmovups ymm6, [r11]
    vfmadd231ps ymm0, ymm5, ymm6

    vpsrldq xmm7, xmm3, 8
    vpmovsxbd ymm5, xmm7
    vcvtdq2ps ymm5, ymm5
    vmulps ymm5, ymm5, ymm1
    vmovups ymm6, [r11 + 32]
    vfmadd231ps ymm0, ymm5, ymm6

    vpmovsxbd ymm5, xmm4
    vcvtdq2ps ymm5, ymm5
    vmulps ymm5, ymm5, ymm1
    vmovups ymm6, [r11 + 64]
    vfmadd231ps ymm0, ymm5, ymm6

    vpsrldq xmm7, xmm4, 8
    vpmovsxbd ymm5, xmm7
    vcvtdq2ps ymm5, ymm5
    vmulps ymm5, ymm5, ymm1
    vmovups ymm6, [r11 + 96]
    vfmadd231ps ymm0, ymm5, ymm6

    add r10, 18
    add r11, 128
    dec rax
    jmp .L_gemv_q4_inner_loop

.L_gemv_q4_inner_done:
    # Горизонтальная редукция аккумулятора ymm0 -> float scalar
    vextractf128 xmm1, ymm0, 1
    vaddps xmm0, xmm0, xmm1
    vhaddps xmm0, xmm0, xmm0
    vhaddps xmm0, xmm0, xmm0

    vmovss [r12 + r8*4], xmm0
    inc r8
    jmp .L_gemv_q4_row_loop

.L_gemv_q4_exit:
    pop rax                  # pop row_bytes
    vzeroupper
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

