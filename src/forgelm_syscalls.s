/* forgelm_syscalls.s - Прямые Linux syscalls без libc для автономного рантайма
 *
 * Архитектура: x86-64 Linux
 *
 * Режимы syscall:
 *   sys_read:   rax = 0 (rdi = fd, rsi = buf, rdx = count)
 *   sys_write:  rax = 1 (rdi = fd, rsi = buf, rdx = count)
 *   sys_open:   rax = 2 (rdi = filename, rsi = flags, rdx = mode)
 *   sys_close:  rax = 3 (rdi = fd)
 *   sys_mmap:   rax = 9 (rdi = addr, rsi = len, rdx = prot, r10 = flags, r8 = fd, r9 = off)
 *   sys_munmap: rax = 11(rdi = addr, rsi = len)
 *   sys_exit:   rax = 60(rdi = status)
 */

.intel_syntax noprefix
.text

.globl forgelm_sys_write
.type forgelm_sys_write, @function
forgelm_sys_write:
    mov rax, 1          # SYS_write
    syscall
    ret

.globl forgelm_sys_mmap
.type forgelm_sys_mmap, @function
forgelm_sys_mmap:
    mov r10, rcx        # В Linux syscalls 4-й аргумент передается в R10 (не RCX)
    mov rax, 9          # SYS_mmap
    syscall
    ret

.globl forgelm_sys_munmap
.type forgelm_sys_munmap, @function
forgelm_sys_munmap:
    mov rax, 11         # SYS_munmap
    syscall
    ret

.globl forgelm_sys_open
.type forgelm_sys_open, @function
forgelm_sys_open:
    mov rax, 2          # SYS_open
    syscall
    ret

.globl forgelm_sys_close
.type forgelm_sys_close, @function
forgelm_sys_close:
    mov rax, 3          # SYS_close
    syscall
    ret

.globl forgelm_sys_exit
.type forgelm_sys_exit, @function
forgelm_sys_exit:
    mov rax, 60         # SYS_exit
    syscall
