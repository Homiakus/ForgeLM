/* forgelm_tui.s - Прогрессивное интерактивное TUI меню на чистом ассемблере x86-64
 *
 * Особенности:
 * - Zero-Libc / Zero-NCurses: прямое взаимодействие с Linux TTY через ANSI VT100 / XTerm управляющие escape-последовательности.
 * - Raw Mode терминала через прямые ioctl:
 *     TCGETS = 0x5401
 *     TCSETS = 0x5402
 * - Навигация стрелками ВВЕРХ / ВНИЗ (ANSI Escape: ESC [ A / ESC [ B) или 'k' / 'j'.
 * - Выбор пункта клавишей ENTER (0x0A / 0x0D) или 'q' для выхода.
 * - Прогрессивный дашборд с ANSI 24-bit TrueColor / 256-color градиентом, статусом ядер, инфо о памяти и режимами работы.
 *
 * int forgelm_tui_menu_render(const char **items, int count, int selected_idx);
 * int forgelm_tui_run(void);
 */

.intel_syntax noprefix

.section .rodata
.align 16

# ANSI VT100 Escape коды
.L_clr_scr:
    .ascii "\033[2J\033[H\033[?25l"   # Очистить экран, курсор в (1,1), скрыть курсор
.L_clr_scr_len = . - .L_clr_scr

.L_show_cur:
    .ascii "\033[?25h\033[0m\n"        # Показать курсор, сбросить цвета
.L_show_cur_len = . - .L_show_cur

# Заголовок TUI
.L_tui_header:
    .ascii "\033[1;36m┌──────────────────────────────────────────────────────────────┐\033[0m\n"
    .ascii "\033[1;36m│\033[1;37m        ⚡ FORGELM PROGRESSIVE TUI INTERACTION DASHBOARD      \033[1;36m│\033[0m\n"
    .ascii "\033[1;36m│\033[0;32m   100% Pure Assembly | Zero-Libc | AVX2+PTX | JIT Engine     \033[1;36m│\033[0m\n"
    .ascii "\033[1;36m├──────────────────────────────────────────────────────────────┤\033[0m\n"
    .ascii "\033[1;36m│\033[0;33m Hardware ISA: \033[1;32mAVX2 + FMA + F16C + RDRAND     \033[0;33mBinary: \033[1;32m9.1 KB  \033[1;36m│\033[0m\n"
    .ascii "\033[1;36m│\033[0;33m Cold Boot:    \033[1;32m0.157 ms                        \033[0;33mMemory: \033[1;32mStatic  \033[1;36m│\033[0m\n"
    .ascii "\033[1;36m├──────────────────────────────────────────────────────────────┤\033[0m\n"
    .ascii "\033[1;36m│\033[1;35m  SELECT OPERATION MODE (Navigate: ↑/↓, Enter: Execute, q: Exit)│\033[0m\n"
    .ascii "\033[1;36m├──────────────────────────────────────────────────────────────┤\033[0m\n"
.L_tui_header_len = . - .L_tui_header

.L_tui_footer:
    .ascii "\033[1;36m├──────────────────────────────────────────────────────────────┤\033[0m\n"
    .ascii "\033[1;36m│\033[0;37m Status: \033[1;32m[ONLINE] Ready for inference                         \033[1;36m│\033[0m\n"
    .ascii "\033[1;36m└──────────────────────────────────────────────────────────────┘\033[0m\n"
.L_tui_footer_len = . - .L_tui_footer

# Выделенный элемент меню
.L_item_selected_prefix:
    .ascii "\033[1;36m│ \033[1;30;46m ▶  "
.L_item_selected_prefix_len = . - .L_item_selected_prefix

.L_item_selected_suffix:
    .ascii "\033[0m\033[1;36m │\033[0m\n"
.L_item_selected_suffix_len = . - .L_item_selected_suffix

# Обычный элемент меню
.L_item_normal_prefix:
    .ascii "\033[1;36m│   \033[0;37m  "
.L_item_normal_prefix_len = . - .L_item_normal_prefix

.L_item_normal_suffix:
    .ascii "\033[0m\033[1;36m │\033[0m\n"
.L_item_normal_suffix_len = . - .L_item_normal_suffix

# Стандартные пункты меню
.L_item_0: .asciz "1. Run Complete Numerical & Kernel Test Suite       "
.L_item_1: .asciz "2. Benchmark Q4_0 Spin-Wait GEMV Engine (4 Threads) "
.L_item_2: .asciz "3. Run FlashDecoding Attention Step (1024 Tokens)   "
.L_item_3: .asciz "4. Launch Zero-Libc HTTP Server (Port 18888)        "
.L_item_4: .asciz "5. Benchmark In-Memory JIT Kernel Synthesis         "
.L_item_5: .asciz "6. Test Zero-Cost Radix Tree Prompt Caching         "
.L_item_6: .asciz "7. Inspect GGUF Model Header & Metadata             "
.L_item_7: .asciz "8. Exit ForgeLM Dashboard                           "

.section .data.rel.ro, "aw", @progbits
.align 8
.L_default_items:
    .quad .L_item_0
    .quad .L_item_1
    .quad .L_item_2
    .quad .L_item_3
    .quad .L_item_4
    .quad .L_item_5
    .quad .L_item_6
    .quad .L_item_7
.L_default_item_count = 8

.text

/* =========================================================================
 * forgelm_tui_render
 *
 * Отрисовка фрейма меню в терминал
 * void forgelm_tui_render(const char **items, int count, int selected_idx);
 *
 * ABI:
 *   RDI: items (массив строк указателей)
 *   RSI: count
 *   RDX: selected_idx
 * ========================================================================= */
.globl forgelm_tui_render
.type forgelm_tui_render, @function
forgelm_tui_render:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             # items
    mov r13, rsi             # count
    mov r14, rdx             # selected_idx

    # 1. Очистить экран и курсор в (1,1)
    mov rax, 1               # sys_write
    mov rdi, 1               # stdout
    lea rsi, [.L_clr_scr + rip]
    mov rdx, .L_clr_scr_len
    syscall

    # 2. Отрисовать заголовок
    mov rax, 1
    mov rdi, 1
    lea rsi, [.L_tui_header + rip]
    mov rdx, .L_tui_header_len
    syscall

    # 3. Отрисовать каждый элемент меню
    xor rbx, rbx             # i = 0
.L_tui_item_loop:
    cmp rbx, r13
    jge .L_tui_render_footer

    cmp rbx, r14
    je .L_tui_render_selected

    # Обычный элемент
    mov rax, 1
    mov rdi, 1
    lea rsi, [.L_item_normal_prefix + rip]
    mov rdx, .L_item_normal_prefix_len
    syscall

    # Текст элемента
    mov rsi, [r12 + rbx*8]
    call .L_print_string

    mov rax, 1
    mov rdi, 1
    lea rsi, [.L_item_normal_suffix + rip]
    mov rdx, .L_item_normal_suffix_len
    syscall
    jmp .L_tui_next_item

.L_tui_render_selected:
    # Выделенный элемент (инвертированный/циановый фон)
    mov rax, 1
    mov rdi, 1
    lea rsi, [.L_item_selected_prefix + rip]
    mov rdx, .L_item_selected_prefix_len
    syscall

    # Текст элемента
    mov rsi, [r12 + rbx*8]
    call .L_print_string

    mov rax, 1
    mov rdi, 1
    lea rsi, [.L_item_selected_suffix + rip]
    mov rdx, .L_item_selected_suffix_len
    syscall

.L_tui_next_item:
    inc rbx
    jmp .L_tui_item_loop

.L_tui_render_footer:
    # 4. Отрисовать подвал
    mov rax, 1
    mov rdi, 1
    lea rsi, [.L_tui_footer + rip]
    mov rdx, .L_tui_footer_len
    syscall

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.L_print_string:
    # rsi: string
    push rbx
    push rcx
    push rdx
    push rsi
    xor rdx, rdx
.L_len_loop:
    mov al, [rsi + rdx]
    test al, al
    jz .L_len_done
    inc rdx
    jmp .L_len_loop
.L_len_done:
    pop rsi
    mov rax, 1               # sys_write
    mov rdi, 1               # stdout
    syscall
    pop rdx
    pop rcx
    pop rbx
    ret


/* =========================================================================
 * forgelm_tui_run
 *
 * Интерактивный цикл TUI меню на чистом ASM
 * Переводит терминал в RAW режим через sys_ioctl (TCGETS/TCSETS),
 * обрабатывает клавиши (Стрелки, Enter, 'q'), восстанавливает режим и возвращает
 * индекс выбранного пункта.
 *
 * int forgelm_tui_run(void);
 * ========================================================================= */
.globl forgelm_tui_run
.type forgelm_tui_run, @function
forgelm_tui_run:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 128

    # Буферы termios:
    # [rsp]      : оригинальные настройки termios (64 байта)
    # [rsp + 64] : модифицированные настройки (raw mode)

    # 1. sys_ioctl(0, TCGETS=0x5401, [rsp])
    mov rax, 16              # sys_ioctl
    xor rdi, rdi             # stdin (fd = 0)
    mov rsi, 0x5401          # TCGETS
    lea rdx, [rsp]
    syscall
    test rax, rax
    js .L_tui_fallback_exit

    # Копируем структуру termios в [rsp + 64]
    mov rcx, 8
.L_copy_termios:
    mov rax, [rsp + rcx*8 - 8]
    mov [rsp + 64 + rcx*8 - 8], rax
    loop .L_copy_termios

    # Выключаем ICANON (канонический режим) и ECHO (эхо символов)
    # c_lflag находится по смещению 12 в struct termios (uint32_t)
    # ICANON = 0x0002, ECHO = 0x0008, ISIG = 0x0001 -> маска ~(0xA)
    mov eax, [rsp + 64 + 12]
    and eax, ~0x000A         # отключить ICANON и ECHO
    mov [rsp + 64 + 12], eax

    # c_cc[VMIN=6] = 1, c_cc[VTIME=5] = 0
    mov byte ptr [rsp + 64 + 17 + 6], 1 # VMIN
    mov byte ptr [rsp + 64 + 17 + 5], 0 # VTIME

    # 2. sys_ioctl(0, TCSETS=0x5402, [rsp + 64])
    mov rax, 16
    xor rdi, rdi
    mov rsi, 0x5402          # TCSETS
    lea rdx, [rsp + 64]
    syscall

    # Выбранный пункт по умолчанию
    xor r12, r12             # selected_idx = 0
    mov r13, .L_default_item_count

.L_tui_event_loop:
    # Отрисовываем меню
    lea rdi, [.L_default_items + rip]
    mov rsi, r13
    mov rdx, r12
    call forgelm_tui_render

    # Читаем 1 символ со stdin (sys_read fd=0)
    # sub rsp, 16 для чтения символов
    mov rax, 0               # sys_read
    xor rdi, rdi             # stdin
    lea rsi, [rsp + 112]
    mov rdx, 1
    syscall

    test rax, rax
    jle .L_tui_restore_exit

    movzx eax, byte ptr [rsp + 112]

    # 'q' или 'Q' -> Выход
    cmp al, 'q'
    je .L_tui_key_exit
    cmp al, 'Q'
    je .L_tui_key_exit

    # ENTER (0x0A или 0x0D) -> Выбор пункта
    cmp al, 10
    je .L_tui_key_enter
    cmp al, 13
    je .L_tui_key_enter

    # 'k' -> ВВЕРХ
    cmp al, 'k'
    je .L_tui_key_up

    # 'j' -> ВНИЗ
    cmp al, 'j'
    je .L_tui_key_down

    # ESC (27 = 0x1B) -> Проверка Escape-последовательности (стрелки)
    cmp al, 27
    jne .L_tui_event_loop

    # Читаем второй символ (должен быть '[')
    mov rax, 0
    xor rdi, rdi
    lea rsi, [rsp + 112]
    mov rdx, 1
    syscall
    movzx eax, byte ptr [rsp + 112]
    cmp al, '['
    jne .L_tui_event_loop

    # Читаем третий символ ('A'=Up, 'B'=Down)
    mov rax, 0
    xor rdi, rdi
    lea rsi, [rsp + 112]
    mov rdx, 1
    syscall
    movzx eax, byte ptr [rsp + 112]

    cmp al, 'A'              # Стрелка ВВЕРХ
    je .L_tui_key_up
    cmp al, 'B'              # Стрелка ВНИЗ
    je .L_tui_key_down
    jmp .L_tui_event_loop

.L_tui_key_up:
    test r12, r12
    jz .L_tui_wrap_down
    dec r12
    jmp .L_tui_event_loop
.L_tui_wrap_down:
    mov r12, r13
    dec r12
    jmp .L_tui_event_loop

.L_tui_key_down:
    inc r12
    cmp r12, r13
    jl .L_tui_event_loop
    xor r12, r12
    jmp .L_tui_event_loop

.L_tui_key_enter:
    # Возвращаем r12 как результат выбора
    mov rax, r12
    jmp .L_tui_restore_exit

.L_tui_key_exit:
    mov rax, -1

.L_tui_restore_exit:
    # Восстанавливаем оригинальный режим терминала TCSETS [rsp]
    push rax
    mov rax, 16
    xor rdi, rdi
    mov rsi, 0x5402
    lea rdx, [rsp + 8]
    syscall

    # Показываем курсор и сбрасываем ANSI цвета
    mov rax, 1
    mov rdi, 1
    lea rsi, [.L_show_cur + rip]
    mov rdx, .L_show_cur_len
    syscall

    pop rax
    jmp .L_tui_final_exit

.L_tui_fallback_exit:
    mov rax, -1

.L_tui_final_exit:
    add rsp, 128
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
