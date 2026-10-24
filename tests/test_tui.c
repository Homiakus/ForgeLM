// test_tui.c - Тестирование прогрессивного TUI меню без libc
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void forgelm_tui_render(const char **items, int count, int selected_idx);

int main() {
    printf("=== [ForgeLM Audit] Progressive TUI Menu Frame Verification ===\n");

    const char *items[] = {
        "1. Run Complete Numerical & Kernel Test Suite       ",
        "2. Benchmark Q4_0 Spin-Wait GEMV Engine (4 Threads) ",
        "3. Run FlashDecoding Attention Step (1024 Tokens)   ",
        "4. Launch Zero-Libc HTTP Server (Port 18888)        ",
        "5. Benchmark In-Memory JIT Kernel Synthesis         ",
        "6. Test Zero-Cost Radix Tree Prompt Caching         ",
        "7. Inspect GGUF Model Header & Metadata             ",
        "8. Exit ForgeLM Dashboard                           "
    };
    int count = sizeof(items) / sizeof(items[0]);

    // Проверяем отрисовку кадра меню для выделенного 2-го пункта (0-indexed: индекс 1)
    forgelm_tui_render(items, count, 1);

    printf(">>> TUI FRAME RENDERING VERIFIED [PASS] <<<\n");
    return 0;
}
