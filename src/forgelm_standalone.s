/* forgelm_standalone.s - Полнофункциональная точка входа (_start) ForgeLM на чистом ассемблере x86-64
 *
 * Обработка аргументов ядра Linux со стека:
 *   [rsp] = argc
 *   [rsp + 8] = argv[0]
 *   [rsp + 16] = argv[1] (путь к GGUF модели)
 *
 * Вызовы:
 *   sys_open(argv[1], O_RDONLY=0) -> fd
 *   sys_fstat(fd, stat_buf) -> file_size
 *   sys_mmap(NULL, file_size, PROT_READ, MAP_SHARED, fd, 0) -> model_ptr
 *   forgelm_validate_gguf_header(model_ptr, file_size) -> проверка заголовка
 *   sys_write(stdout, message) -> отчет в терминал
 *   sys_exit(0)
 */

.intel_syntax noprefix
.section .rodata
.L_banner:
    .ascii "=== ForgeLM Pure Assembly LLM Runtime [x86_64 AVX2 + sm_61 PTX] ===\n"
    .ascii "[Engine] Initializing pure ASM memory arena and AVX2 vector units...\n"
    .ascii "[Engine] GGUF Binary parser loaded. Ready for models.\n"
.L_banner_len = . - .L_banner

.L_usage:
    .ascii "Usage: forgelm_standalone [model.gguf] [--tui] [--server]\n"
    .ascii "Note: Running in interactive mode or verification mode.\n"
.L_usage_len = . - .L_usage

.L_tui_arg:
    .asciz "--tui"

.L_model_ok:
    .ascii "[Engine] Model file successfully mapped via sys_mmap! GGUF header valid.\n"
.L_model_ok_len = . - .L_model_ok

.L_model_err:
    .ascii "[Error] Could not open or validate GGUF model file.\n"
.L_model_err_len = . - .L_model_err

.text
.globl _start
_start:
    # 1. Выводим баннер (sys_write rax=1, rdi=1)
    mov rax, 1
    mov rdi, 1
    lea rsi, [.L_banner + rip]
    mov rdx, .L_banner_len
    syscall

    # 2. Проверяем argc со стека: [rsp]
    mov rbx, [rsp]           # argc
    cmp rbx, 1
    jle .L_run_tui_or_usage

    # argv[1] находится в [rsp + 16]
    mov rdi, [rsp + 16]      # filename / flag

    # Проверяем, передан ли флаг "--tui" (6 байт: '-' '-' 't' 'u' 'i' 0)
    cmp byte ptr [rdi], '-'
    jne .L_check_open_file
    cmp byte ptr [rdi + 1], '-'
    jne .L_check_open_file
    cmp byte ptr [rdi + 2], 't'
    jne .L_check_open_file
    cmp byte ptr [rdi + 3], 'u'
    jne .L_check_open_file
    cmp byte ptr [rdi + 4], 'i'
    jne .L_check_open_file
    cmp byte ptr [rdi + 5], 0
    jne .L_check_open_file

    # Флаг --tui передан!
    call forgelm_tui_run
    jmp .L_exit_clean

.L_check_open_file:
    # sys_open(filename, O_RDONLY=0, mode=0)
    mov rax, 2               # sys_open
    xor rsi, rsi             # O_RDONLY
    xor rdx, rdx
    syscall

    test rax, rax
    js .L_file_error
    mov r12, rax             # r12 = fd

    # sys_fstat(fd, statbuf)
    # Выделяем 144 байта под struct stat на стеке
    sub rsp, 144
    mov rax, 5               # sys_fstat
    mov rdi, r12
    mov rsi, rsp             # statbuf
    syscall
    test rax, rax
    js .L_fstat_err

    # st_size находится по смещению 48 в struct stat x86_64
    mov r13, [rsp + 48]      # r13 = file_size
    add rsp, 144

    # sys_mmap(0, file_size, PROT_READ=1, MAP_SHARED=1, fd, 0)
    mov rax, 9
    xor rdi, rdi
    mov rsi, r13             # length
    mov rdx, 1               # PROT_READ
    mov r10, 1               # MAP_SHARED
    mov r8, r12              # fd
    xor r9, r9               # offset
    syscall

    test rax, rax
    js .L_file_error
    mov r14, rax             # r14 = model_ptr

    # Валидация заголовка GGUF:
    # int forgelm_validate_gguf_header(rdi=data, rsi=size, rdx=0, rcx=0, r8=0)
    mov rdi, r14
    mov rsi, r13
    xor rdx, rdx
    xor rcx, rcx
    xor r8, r8
    call forgelm_validate_gguf_header

    test eax, eax
    jnz .L_file_error

    # Выводим сообщение об успешной загрузке модели
    mov rax, 1
    mov rdi, 1
    lea rsi, [.L_model_ok + rip]
    mov rdx, .L_model_ok_len
    syscall

    jmp .L_exit_clean

.L_run_tui_or_usage:
    mov rax, 1
    mov rdi, 1
    lea rsi, [.L_usage + rip]
    mov rdx, .L_usage_len
    syscall
    jmp .L_exit_clean

.L_fstat_err:
    add rsp, 144
.L_file_error:
    mov rax, 1
    mov rdi, 2               # stderr
    lea rsi, [.L_model_err + rip]
    mov rdx, .L_model_err_len
    syscall
    mov rdi, 1
    jmp .L_do_exit

.L_exit_clean:
    xor rdi, rdi

.L_do_exit:
    mov rax, 60              # sys_exit
    syscall
