/* forgelm_q4_k_avx2.s - Скалярное произведение квантования Q4_K на x86-64 AVX2
 *
 * Формат блока Q4_K (256 весов в супер-блоке):
 *   struct block_q4_K {
 *       float16 d;               // 2 байта (супер-масштаб)
 *       float16 dmin;            // 2 байта (супер-минимум)
 *       uint8_t scales[12];      // 12 байт (6-битные масштабы для 8 подблоков по 32 веса)
 *       uint8_t qs[128];         // 128 байт (256 нибблов)
 *   };
 * Общий размер супер-блока = 2 + 2 + 12 + 128 = 144 байта на 256 весов (4.5 бита на вес).
 *
 * void forgelm_vec_dot_q4_k_f32(float *out, const void *vx, const float *vy, int k);
 */

.intel_syntax noprefix
.section .rodata
.align 32
.L_k_mask_low:
    .byte 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F
    .byte 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F
    .byte 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F
    .byte 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F

.text
.globl forgelm_vec_dot_q4_k_f32
.type forgelm_vec_dot_q4_k_f32, @function
forgelm_vec_dot_q4_k_f32:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rsi             # vx (блоки Q4_K)
    mov r13, rdx             # vy (вектор FP32)
    mov rbx, rcx             # k

    vxorps ymm0, ymm0, ymm0  # sum accumulator

    # Число супер-блоков по 256 весов: nb = k / 256
    mov r8, rbx
    shr r8, 8
    test r8, r8
    jz .L_q4_k_done

    vmovdqa xmm10, [.L_k_mask_low + rip]

.L_super_block_loop:
    # 1. Загружаем супер-масштаб d (FP16 -> FP32)
    vcvtph2ps xmm1, [r12]
    vbroadcastss ymm1, xmm1  # ymm1 = d

    # Указатель на 128 байт нибблов: r12 + 16
    lea r14, [r12 + 16]
    xor rax, rax             # подблок 0..7 (по 32 элемента = 16 байт нибблов)

.L_subblock_loop:
    cmp rax, 8
    jge .L_super_block_next

    # Загружаем 16 байт (32 ниббла)
    vmovdqu xmm2, [r14 + rax*2]

    # Нижние 4 бита
    vpand xmm3, xmm2, xmm10
    # Верхние 4 бита
    vpsrlw xmm4, xmm2, 4
    vpand xmm4, xmm4, xmm10

    # Четверти по 8 элементов: int8 -> int32 -> float32
    vpmovzxbd ymm5, xmm3
    vcvtdq2ps ymm5, ymm5
    vmulps ymm5, ymm5, ymm1
    vmovups ymm6, [r13]
    vfmadd231ps ymm0, ymm5, ymm6

    vpsrldq xmm7, xmm3, 8
    vpmovzxbd ymm5, xmm7
    vcvtdq2ps ymm5, ymm5
    vmulps ymm5, ymm5, ymm1
    vmovups ymm6, [r13 + 32]
    vfmadd231ps ymm0, ymm5, ymm6

    vpmovzxbd ymm5, xmm4
    vcvtdq2ps ymm5, ymm5
    vmulps ymm5, ymm5, ymm1
    vmovups ymm6, [r13 + 64]
    vfmadd231ps ymm0, ymm5, ymm6

    vpsrldq xmm7, xmm4, 8
    vpmovzxbd ymm5, xmm7
    vcvtdq2ps ymm5, ymm5
    vmulps ymm5, ymm5, ymm1
    vmovups ymm6, [r13 + 96]
    vfmadd231ps ymm0, ymm5, ymm6

    add r13, 128             # 32 float = 128 байт
    inc rax
    jmp .L_subblock_loop

.L_super_block_next:
    add r12, 144             # размер одного блока block_q4_K = 144 байта
    dec r8
    jnz .L_super_block_loop

.L_q4_k_done:
    # Горизонтальная сумма ymm0 -> [rdi]
    vextractf128 xmm1, ymm0, 1
    vaddps xmm0, xmm0, xmm1
    vhaddps xmm0, xmm0, xmm0
    vhaddps xmm0, xmm0, xmm0

    vmovss [rdi], xmm0

    vzeroupper
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
