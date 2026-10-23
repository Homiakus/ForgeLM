/* forgelm_threads_avx2.s - Параллельный GEMV на чистом ассемблере x86-64
 * 
 * Параллелизм строк матрицы A (Row-parallelism):
 * Каждый поток T вычисляет диапазон строк [start_row, end_row) матрицы M x K.
 *
 * void forgelm_gemv_row_range_f32(float *out, const float *A, const float *x, 
 *                                 int start_row, int end_row, int K);
 *
 * ABI:
 *   RDI: out
 *   RSI: A
 *   RDX: x
 *   RCX: start_row
 *   R8:  end_row
 *   R9:  K
 */

.intel_syntax noprefix
.text
.globl forgelm_gemv_row_range_f32
.type forgelm_gemv_row_range_f32, @function
forgelm_gemv_row_range_f32:
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
    mov r15, r8              # end_row
    mov rbx, r9              # K

    mov r8, rcx              # current row = start_row

.L_par_gemv_row_loop:
    cmp r8, r15
    jge .L_par_gemv_done

    # A_row = A + row * K * 4
    mov rax, r8
    imul rax, rbx
    shl rax, 2
    lea r10, [r13 + rax]

    vxorps ymm0, ymm0, ymm0  # sum acc
    xor r11, r11             # k = 0
    mov rax, rbx
    shr rax, 3               # K / 8

.L_par_gemv_col_loop:
    test rax, rax
    jz .L_par_gemv_reduce
    vmovups ymm1, [r10 + r11*4]
    vmovups ymm2, [r14 + r11*4]
    vfmadd231ps ymm0, ymm1, ymm2
    add r11, 8
    dec rax
    jmp .L_par_gemv_col_loop

.L_par_gemv_reduce:
    vextractf128 xmm1, ymm0, 1
    vaddps xmm0, xmm0, xmm1
    vhaddps xmm0, xmm0, xmm0
    vhaddps xmm0, xmm0, xmm0

    vmovss [r12 + r8*4], xmm0
    inc r8
    jmp .L_par_gemv_row_loop

.L_par_gemv_done:
    vzeroupper
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
