# ForgeLM Implementation Plan & Architecture Specification

## 1. Архитектурные принципы
- **Чистый ассемблер**: x86-64 System V ABI (GNU Assembler `as`) для CPU и PTX / CUDA Driver API для GPU (GTX 1050 Ti, sm_61).
- **Zero-allocation inference loop**: единовременное выделение арены памяти, отсутствие динамических аллокаций во время генерации токенов.
- **Совместимость с GGUF**: поддержка формата GGUF v2/v3 (Llama, Mistral, Qwen и др.).
- **Поддержка AVX2/FMA**: максимальное использование SIMD инструкций x86-64 для GEMV, RMSNorm, Softmax, RoPE.

## 2. Модули ForgeLM
1. `src/forgelm_mmap.s` — низкоуровневый mmap и file I/O (POSIX syscalls).
2. `src/forgelm_gguf.s` — парсер GGUF заголовков, метаданных и тензорных дескрипторов.
3. `src/forgelm_math_avx2.s` — SIMD вычислительные ядра:
   - `forgelm_rmsnorm_f32`
   - `forgelm_gemv_f32` (Matrix-vector multiply с 4/8-way AVX2 unrolling)
   - `forgelm_rope_f32` (Rotary Positional Embeddings)
   - `forgelm_softmax_f32` (Numerically stable online max-subtracted softmax)
   - `forgelm_silu_f32` (SwiGLU activation)
4. `src/forgelm_cuda_driver.s` — загрузка PTX модулей и запуск кернелов на GTX 1050 Ti через `libcuda.so.1`.
5. `src/forgelm_sampler.s` — Greedy / Top-P / Temperature выбор следующего токена.
6. `tests/` — тестовый harness для валидации численной точности каждого ядра по сравнению с эталонной C/Python моделью.
