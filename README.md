# ForgeLM — Pure Assembly LLM Runtime

[![Assembly](https://img.shields.io/badge/Language-x86--64%20ASM%20%7C%20CUDA%20PTX-blue.svg)](src/)
[![Architecture](https://img.shields.io/badge/ISA-AVX2%20%2B%20FMA%20%2B%20F16C-green.svg)](src/forgelm_math_avx2.s)
[![Quantization](https://img.shields.io/badge/Quant-Q4__0%20%7C%20FP32-orange.svg)](src/forgelm_q4_0_avx2.s)
[![Zero Libc](https://img.shields.io/badge/Dependencies-Zero%20(Direct%20Linux%20Syscalls)-red.svg)](src/forgelm_syscalls.s)
[![License](https://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)

**ForgeLM** — высокопроизводительный, ультралегковесный автономный рантайм для локального запуска больших языковых моделей (LLM), реализованный **полностью на чистом низкоуровневом ассемблере** (x86-64 SIMD для CPU и CUDA PTX ISA для GPU).

---

## ⚡ Ключевые особенности

- **100% Pure Assembly**: все критические вычислительные пути, ядра нормализации, матричные произведения и парсеры реализованы на ассемблере без тяжелых фреймворков.
- **Zero-Dependency & Zero-Libc**: автономный бинарник `forgelm_standalone` связывается напрямую через GNU Linker (`ld`) и общается с ядром через прямые Linux Syscalls (`sys_mmap`, `sys_write`, `sys_exit`), не требуя даже `libc.so`.
- **4-bit Quantization (Q4_0 AVX2)**: векторное скалярное произведение 4-битных квантованных матриц с побитовой аппаратной распаковкой нибблов и мгновенной конвертацией FP16 масштабов через инструкцию `vcvtph2ps`.
- **AVX2 + FMA Векторизация**: ручной loop unrolling и параллельные аккумуляторы для матрично-векторных умножений (GEMV) и RMSNorm с нулевой погрешностью относительно эталонных расчетов (`0.000000e+00 diff`).
- **Zero-Copy GGUF Engine**: низкоуровневый разбор бинарного формата GGUF (v2 / v3) с прямым отображением файла весов в память через `sys_mmap`.
- **NVIDIA GPU PTX Backend**: поддержка выгрузки слоев и кернелов внимания на GPU через машинный ассемблер PTX (NVIDIA sm_61 Pascal, Turing, Ampere, Ada).

---

## 🏗 Архитектура проекта

```text
forgelm/
├── bin/                       # Скомпилированные артефакты и статический ELF бинарник
│   ├── forgelm_standalone     # Чистый statically-linked ASM бинарник (no libc)
│   ├── forgelm_kernels.cubin  # Скомпилированный PTX кернел для GPU
│   ├── test_math              # Тест численной точности FP32 AVX2
│   ├── test_q4                # Тест численной точности Q4_0
│   └── test_gguf              # Тест валидации GGUF парсера
├── include/                   # Заголовочные файлы и определения структур
├── src/                       # Исходный код на чистом ассемблере
│   ├── forgelm_math_avx2.s    # RMSNorm и GEMV (AVX2 + FMA unrolled)
│   ├── forgelm_q4_0_avx2.s    # 4-bit квантованное скалярное произведение (AVX2 + F16C)
│   ├── forgelm_rope_softmax.s # RoPE позиционные эмбеддинги и устойчивый Softmax
│   ├── forgelm_gguf.s         # Парсер бинарных структур и заголовков GGUF
│   ├── forgelm_syscalls.s     # Прямые обертки Linux Syscalls (sys_mmap, sys_write, etc.)
│   ├── forgelm_standalone.s   # Точка входа _start автономного приложения
│   └── forgelm_kernels.ptx    # CUDA PTX ассемблер для GPU
├── tests/                     # Верификационный тестовый harness и бенчмарки
│   ├── test_math.c            # Сравнение с эталонными float32 вычислениями
│   ├── test_q4.c              # Сравнение с эталонной распаковкой Q4_0
│   ├── test_gguf.c            # Защита от поврежденных бинарных заголовков
│   └── benchmark_gemv.c       # Замер латентности и пропускной способности памяти
├── ARCHITECTURE.md            # Спецификация контрактов и арены памяти
└── Makefile                   # Конвейер сборки и тестирования
```

---

## 🚀 Быстрый старт

### Требования
- 64-битный Linux (x86_64)
- Процессор с поддержкой AVX2, FMA, F16C (Intel Core 4-го поколения+ / AMD Zen 1+)
- GNU Assembler (`as`), GNU Linker (`ld`), GCC (для тестового harness)
- *Опционально для GPU*: NVIDIA CUDA Toolkit (`ptxas`)

### Сборка и запуск тестов
Клонируйте репозиторий и выполните сборку:

```bash
git clone git@github.com:Homiakus/ForgeLM.git
cd ForgeLM
make clean
make test
```

### Запуск бенчмарка производительности GEMV
```bash
make benchmark
```

Пример вывода на Intel Core i5-9300H (матрица 4096 x 4096, 64 MB):
```text
=== [ForgeLM Benchmark] GEMV Kernel Performance ===
Matrix size: 4096 x 4096 (64.00 MB weights)
Iterations: 100
Avg latency: 4.397 ms
Compute Throughput: 7.63 GFLOPS
Memory Bandwidth: 15.26 GB/s
```

---

## 🔬 Результаты численного аудита

Все ассемблерные ядра прошли независимое тестирование против эталонных математических реализаций:

| Операция | ISA / Технология | Погрешность против Ref | Статус |
| :--- | :--- | :--- | :--- |
| **RMSNorm** | x86-64 AVX2 / FMA | `0.000000e+00` | ✅ PASS |
| **GEMV (FP32)** | x86-64 AVX2 8-way unroll | `0.000000e+00` | ✅ PASS |
| **Dot Product Q4_0** | x86-64 AVX2 + F16C | `0.000000e+00` | ✅ PASS |
| **GGUF v2/v3 Header**| x86-64 Binary Decoder | 100% Boundary Safety | ✅ PASS |
| **GPU RMSNorm** | CUDA PTX ISA (sm_61) | Binary `.cubin` verified | ✅ PASS |

---

## 📜 Лицензия
Проект распространяется под лицензией MIT. Подробности см. в файле [LICENSE](LICENSE).
