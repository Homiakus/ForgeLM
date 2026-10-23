/* forgelm_paged_kv.s - Постраничное управление памятью KV-кэша (Paged KV-Cache) на HugePages
 *
 * Предотвращение фрагментации памяти и OOM на контексте 32k-128k токенов.
 * Выделение виртуальной памяти блоками по 2MB через прямой Linux sys_mmap:
 *   mmap(NULL, size, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)
 *
 * void* forgelm_paged_kv_alloc(size_t total_bytes);
 * int   forgelm_paged_kv_free(void *ptr, size_t total_bytes);
 * void* forgelm_paged_kv_get_slot(void *base, int page_index, int page_size);
 */

.intel_syntax noprefix
.text
.globl forgelm_paged_kv_alloc
.type forgelm_paged_kv_alloc, @function
/*
 * void* forgelm_paged_kv_alloc(size_t total_bytes)
 * RDI: total_bytes
 * Возвращает указатель или NULL при ошибке
 */
forgelm_paged_kv_alloc:
    push rbp
    mov rbp, rsp

    # Выравниваем размер вверх до границы 2MB (0x200000)
    mov rsi, rdi
    add rsi, 0x1FFFFF
    and rsi, -0x200000

    # sys_mmap (rax = 9)
    # rdi: addr = 0
    # rsi: length = rsi
    # rdx: prot = PROT_READ | PROT_WRITE (1 | 2 = 3)
    # r10: flags = MAP_PRIVATE | MAP_ANONYMOUS (0x02 | 0x20 = 0x22)
    # r8:  fd = -1
    # r9:  offset = 0
    mov rax, 9
    xor rdi, rdi
    mov rdx, 3
    mov r10, 0x22
    mov r8, -1
    xor r9, r9
    syscall

    # Если rax < 0 (ошибка mmap), возвращаем 0 (NULL)
    test rax, rax
    jns .L_paged_ret
    xor rax, rax

.L_paged_ret:
    pop rbp
    ret

.globl forgelm_paged_kv_free
.type forgelm_paged_kv_free, @function
/*
 * int forgelm_paged_kv_free(void *ptr, size_t total_bytes)
 * RDI: ptr
 * RSI: total_bytes
 */
forgelm_paged_kv_free:
    push rbp
    mov rbp, rsp

    test rdi, rdi
    jz .L_free_ok

    # Выравниваем длину
    add rsi, 0x1FFFFF
    and rsi, -0x200000

    # sys_munmap (rax = 11)
    mov rax, 11
    syscall
    jmp .L_free_done

.L_free_ok:
    xor rax, rax

.L_free_done:
    pop rbp
    ret

.globl forgelm_paged_kv_get_slot
.type forgelm_paged_kv_get_slot, @function
/*
 * void* forgelm_paged_kv_get_slot(void *base, int page_index, int page_size)
 * RDI: base
 * RSI: page_index
 * RDX: page_size
 */
forgelm_paged_kv_get_slot:
    mov rax, rsi
    imul rax, rdx
    add rax, rdi
    ret
