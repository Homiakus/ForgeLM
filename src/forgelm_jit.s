/* forgelm_jit.s - JIT-генератор развернутых ассемблерных кернелов GEMV в памяти
 *
 * Генерация исполняемого машинного кода (x86_64 машинные опкоды) прямо в PROT_READ|PROT_WRITE|PROT_EXEC памяти:
 * 
 * Синтезирует специализированную функцию:
 * void specialized_gemv_dot(float *out, const float *A_row, const float *x);
 *
 * Опкоды:
 *   vxorps ymm0, ymm0, ymm0 -> c5 f4 57 c0
 *   vmovups ymm1, [rsi + offset] -> c5 fc 10 8e / c5 fc 10 4e disp
 *   vmovups ymm2, [rdx + offset] -> c5 fc 10 92 / c5 fc 10 52 disp
 *   vfmadd231ps ymm0, ymm1, ymm2 -> c4 e2 75 b8 c2
 *   ... развернуто ровно k/8 раз ...
 *   vextractf128 xmm1, ymm0, 1   -> c4 e3 7d 19 c1 01
 *   vaddps xmm0, xmm0, xmm1      -> c5 f8 58 c1
 *   vhaddps xmm0, xmm0, xmm0     -> c5 f9 7c c0
 *   vhaddps xmm0, xmm0, xmm0     -> c5 f9 7c c0
 *   vmovss [rdi], xmm0           -> c5 fa 11 07
 *   vzeroupper                   -> c5 f8 77
 *   ret                          -> c3
 *
 * void* forgelm_jit_alloc_executable(size_t size);
 * int   forgelm_jit_free_executable(void *ptr, size_t size);
 * int   forgelm_jit_compile_gemv_row(void *code_buf, int K);
 */

.intel_syntax noprefix
.text

.globl forgelm_jit_alloc_executable
.type forgelm_jit_alloc_executable, @function
/*
 * void* forgelm_jit_alloc_executable(size_t size)
 * Выделяет память с правами RWX (PROT_READ|PROT_WRITE|PROT_EXEC = 7)
 */
forgelm_jit_alloc_executable:
    push rbp
    mov rbp, rsp

    # sys_mmap (rax = 9)
    # rdi = 0, rsi = size, rdx = 7 (PROT_READ|WRITE|EXEC), r10 = 0x22 (PRIVATE|ANON), r8 = -1, r9 = 0
    mov rax, 9
    mov rsi, rdi             # size
    xor rdi, rdi
    mov rdx, 7               # PROT_READ | PROT_WRITE | PROT_EXEC
    mov r10, 0x22            # MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    xor r9, r9
    syscall

    test rax, rax
    jns .L_jit_alloc_ok
    xor rax, rax             # NULL on error
.L_jit_alloc_ok:
    pop rbp
    ret

.globl forgelm_jit_free_executable
.type forgelm_jit_free_executable, @function
forgelm_jit_free_executable:
    push rbp
    mov rbp, rsp
    # sys_munmap (rax = 11, rdi = ptr, rsi = size)
    mov rax, 11
    syscall
    pop rbp
    ret

.globl forgelm_jit_compile_gemv_row
.type forgelm_jit_compile_gemv_row, @function
/*
 * int forgelm_jit_compile_gemv_row(void *code_buf, int K)
 * RDI: code_buf
 * RSI: K (размерность, кратна 8)
 * Возвращает размер сгенерированного машинного кода в байтах
 */
forgelm_jit_compile_gemv_row:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi             # out code pointer
    mov rbx, rsi             # K
    xor r14, r14             # byte counter = 0

    # 1. vxorps ymm0, ymm0, ymm0: c5 fc 57 c0 (4 байта)
    mov byte ptr [r12 + r14], 0xc5; inc r14
    mov byte ptr [r12 + r14], 0xfc; inc r14
    mov byte ptr [r12 + r14], 0x57; inc r14
    mov byte ptr [r12 + r14], 0xc0; inc r14

    # 2. Генерируем полностью развернутый цикл для каждого блока из 8 элементов float:
    # blocks = K / 8
    mov r13, rbx
    shr r13, 3               # r13 = num_blocks
    xor rcx, rcx             # block index = 0

.L_jit_gen_block:
    cmp rcx, r13
    jge .L_jit_gen_epilogue

    # Смещение offset = rcx * 32
    mov rax, rcx
    shl rax, 5               # rax = offset

    # Инструкция 1: vmovups ymm1, [rsi + disp32]
    # Опкод: c5 fc 10 8e [disp32]
    mov byte ptr [r12 + r14], 0xc5; inc r14
    mov byte ptr [r12 + r14], 0xfc; inc r14
    mov byte ptr [r12 + r14], 0x10; inc r14
    mov byte ptr [r12 + r14], 0x8e; inc r14
    mov dword ptr [r12 + r14], eax; add r14, 4

    # Инструкция 2: vmovups ymm2, [rdx + disp32]
    # Опкод: c5 fc 10 92 [disp32]
    mov byte ptr [r12 + r14], 0xc5; inc r14
    mov byte ptr [r12 + r14], 0xfc; inc r14
    mov byte ptr [r12 + r14], 0x10; inc r14
    mov byte ptr [r12 + r14], 0x92; inc r14
    mov dword ptr [r12 + r14], eax; add r14, 4

    # Инструкция 3: vfmadd231ps ymm0, ymm1, ymm2
    # Опкод: c4 e2 75 b8 c2 (5 байт)
    mov byte ptr [r12 + r14], 0xc4; inc r14
    mov byte ptr [r12 + r14], 0xe2; inc r14
    mov byte ptr [r12 + r14], 0x75; inc r14
    mov byte ptr [r12 + r14], 0xb8; inc r14
    mov byte ptr [r12 + r14], 0xc2; inc r14

    inc rcx
    jmp .L_jit_gen_block

.L_jit_gen_epilogue:
    # Редукция:
    # vextractf128 xmm1, ymm0, 1 -> c4 e3 7d 19 c1 01 (6 байт)
    mov byte ptr [r12 + r14], 0xc4; inc r14
    mov byte ptr [r12 + r14], 0xe3; inc r14
    mov byte ptr [r12 + r14], 0x7d; inc r14
    mov byte ptr [r12 + r14], 0x19; inc r14
    mov byte ptr [r12 + r14], 0xc1; inc r14
    mov byte ptr [r12 + r14], 0x01; inc r14

    # vaddps xmm0, xmm0, xmm1 -> c5 f8 58 c1 (4 байта)
    mov byte ptr [r12 + r14], 0xc5; inc r14
    mov byte ptr [r12 + r14], 0xf8; inc r14
    mov byte ptr [r12 + r14], 0x58; inc r14
    mov byte ptr [r12 + r14], 0xc1; inc r14

    # vhaddps xmm0, xmm0, xmm0 -> c5 fb 7c c0 (4 байта)
    mov byte ptr [r12 + r14], 0xc5; inc r14
    mov byte ptr [r12 + r14], 0xfb; inc r14
    mov byte ptr [r12 + r14], 0x7c; inc r14
    mov byte ptr [r12 + r14], 0xc0; inc r14

    # vhaddps xmm0, xmm0, xmm0 -> c5 fb 7c c0 (4 байта)
    mov byte ptr [r12 + r14], 0xc5; inc r14
    mov byte ptr [r12 + r14], 0xfb; inc r14
    mov byte ptr [r12 + r14], 0x7c; inc r14
    mov byte ptr [r12 + r14], 0xc0; inc r14

    # vmovss [rdi], xmm0 -> c5 fa 11 07 (4 байта)
    mov byte ptr [r12 + r14], 0xc5; inc r14
    mov byte ptr [r12 + r14], 0xfa; inc r14
    mov byte ptr [r12 + r14], 0x11; inc r14
    mov byte ptr [r12 + r14], 0x07; inc r14

    # vzeroupper -> c5 f8 77 (3 байта)
    mov byte ptr [r12 + r14], 0xc5; inc r14
    mov byte ptr [r12 + r14], 0xf8; inc r14
    mov byte ptr [r12 + r14], 0x77; inc r14

    # ret -> c3 (1 байт)
    mov byte ptr [r12 + r14], 0xc3; inc r14

    mov rax, r14             # return code size
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
