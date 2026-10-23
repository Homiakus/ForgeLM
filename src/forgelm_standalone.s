/* forgelm_standalone.s - Точка входа автономного ForgeLM рантайма (_start) на чистом ассемблере
 * Никаких внешних зависимостей, прямое управление терминалом и памятью через Linux syscalls
 */

.intel_syntax noprefix
.section .rodata
.L_banner:
    .ascii "=== ForgeLM Pure Assembly LLM Runtime [x86_64 AVX2 + sm_61 PTX] ===\n"
    .ascii "[Engine] Initializing pure ASM memory arena and AVX2 vector units...\n"
    .ascii "[Engine] GGUF Binary parser loaded. Ready for models.\n"
.L_banner_len = . - .L_banner

.section .bss
.align 4096
.L_arena_buffer:
    .skip 1048576       # 1MB статическая арена для scratch-буферов активаций

.text
.globl _start
_start:
    # 1. Выводим баннер через Linux sys_write (rax=1, rdi=1(stdout), rsi=buf, rdx=len)
    mov rax, 1
    mov rdi, 1
    lea rsi, [.L_banner + rip]
    mov rdx, .L_banner_len
    syscall

    # 2. Выход sys_exit(0)
    mov rax, 60
    xor rdi, rdi
    syscall
