/* forgelm_server.s - Автономный Zero-Copy HTTP REST/SSE сервер на чистых Linux Syscalls
 *
 * int forgelm_create_server_socket(int port);
 * void forgelm_http_handle_connection(int client_fd, const char *body, int body_len);
 */

.intel_syntax noprefix
.section .rodata
.align 16
.L_http_200_hdr:
    .ascii "HTTP/1.1 200 OK\r\n"
    .ascii "Content-Type: application/json\r\n"
    .ascii "Server: ForgeLM-PureASM\r\n"
    .ascii "Connection: close\r\n"
    .ascii "Content-Length: "
.L_http_200_hdr_len = . - .L_http_200_hdr

.L_crlf_crlf:
    .ascii "\r\n\r\n"
.L_crlf_crlf_len = . - .L_crlf_crlf

.text
.globl forgelm_http_handle_connection
.type forgelm_http_handle_connection, @function
forgelm_http_handle_connection:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 280

    mov r12, rdi             # client_fd
    mov r13, rsi             # body
    mov r14, rdx             # body_len

    # 1. Читаем запрос (sys_read fd=client_fd)
    mov rax, 0
    mov rdi, r12
    lea rsi, [rsp]
    mov rdx, 256
    syscall

    # 2. Пишем заголовок HTTP
    mov rax, 1
    mov rdi, r12
    lea rsi, [.L_http_200_hdr + rip]
    mov rdx, .L_http_200_hdr_len
    syscall

    # 3. Конвертируем body_len в строку в буфер [rsp + 128]
    lea rdi, [rsp + 128]
    mov rax, r14
    call .L_format_len

    # rax = len
    mov rdx, rax
    mov rax, 1
    mov rdi, r12
    lea rsi, [rsp + 128]
    syscall

    # 4. Пишем \r\n\r\n
    mov rax, 1
    mov rdi, r12
    lea rsi, [.L_crlf_crlf + rip]
    mov rdx, .L_crlf_crlf_len
    syscall

    # 5. Пишем JSON тело
    test r14, r14
    jle .L_done_close
    mov rax, 1
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    syscall

.L_done_close:
    # 6. sys_close(client_fd)
    mov rax, 3
    mov rdi, r12
    syscall

    add rsp, 280
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.L_format_len:
    # rdi: out_buf, rax: number
    push rbx
    push rcx
    push rdx

    test rax, rax
    jnz .L_fl_positive
    mov byte ptr [rdi], '0'
    mov rax, 1
    jmp .L_fl_ret

.L_fl_positive:
    # Делим на 10 и сохраняем остатки в локальный временный массив
    sub rsp, 32
    mov rbx, 10
    xor rcx, rcx             # count

.L_fl_div_loop:
    test rax, rax
    jz .L_fl_write
    xor rdx, rdx
    div rbx                  # rax = rax / 10, rdx = rem
    add dl, '0'
    mov [rsp + rcx], dl
    inc rcx
    jmp .L_fl_div_loop

.L_fl_write:
    # rcx = число цифр (в обратном порядке)
    mov r8, rcx              # total length
    xor rax, rax
.L_fl_copy:
    test rcx, rcx
    jz .L_fl_finish
    dec rcx
    mov dl, [rsp + rcx]
    mov [rdi + rax], dl
    inc rax
    jmp .L_fl_copy

.L_fl_finish:
    add rsp, 32
    mov rax, r8              # return total length

.L_fl_ret:
    pop rdx
    pop rcx
    pop rbx
    ret

.globl forgelm_create_server_socket
.type forgelm_create_server_socket, @function
forgelm_create_server_socket:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 48

    mov rbx, rdi             # port

    # 1. sys_socket(AF_INET=2, SOCK_STREAM=1, 0)
    mov rax, 41
    mov rdi, 2
    mov rsi, 1
    xor rdx, rdx
    syscall
    test rax, rax
    js .L_sock_fail
    mov r12, rax             # r12 = server_fd

    # 2. setsockopt(SO_REUSEADDR)
    mov dword ptr [rsp], 1   # optval = 1
    mov rax, 54
    mov rdi, r12
    mov rsi, 1               # SOL_SOCKET
    mov rdx, 2               # SO_REUSEADDR
    lea r10, [rsp]
    mov r8, 4
    syscall

    # 3. bind(r12, sockaddr, 16)
    mov word ptr [rsp + 16], 2    # sin_family = AF_INET (2)
    # htons(port)
    mov rax, rbx
    rol ax, 8
    mov word ptr [rsp + 18], ax   # sin_port
    mov dword ptr [rsp + 20], 0   # INADDR_ANY (0.0.0.0)
    mov qword ptr [rsp + 24], 0   # padding

    mov rax, 49              # sys_bind
    mov rdi, r12
    lea rsi, [rsp + 16]
    mov rdx, 16
    syscall
    test rax, rax
    js .L_sock_close_fail

    # 4. listen(r12, 128)
    mov rax, 50              # sys_listen
    mov rdi, r12
    mov rsi, 128
    syscall
    test rax, rax
    js .L_sock_close_fail

    mov rax, r12             # return server_fd
    jmp .L_sock_ret

.L_sock_close_fail:
    mov rax, 3
    mov rdi, r12
    syscall

.L_sock_fail:
    mov rax, -1

.L_sock_ret:
    add rsp, 48
    pop r12
    pop rbx
    pop rbp
    ret
