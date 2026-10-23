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
