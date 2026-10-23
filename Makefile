CC = gcc
CFLAGS = -O3 -mavx2 -mf16c -mfma -Wall -Wextra -Iinclude
AS = as
LD = ld
PTXAS = ptxas
GPU_ARCH = sm_61

ASM_SRCS = src/forgelm_math_avx2.s src/forgelm_gguf.s src/forgelm_rope_softmax.s src/forgelm_q4_0_avx2.s src/forgelm_syscalls.s
PTX_SRCS = src/forgelm_kernels.ptx
BINS = bin/test_math bin/test_gguf bin/test_q4 bin/benchmark_gemv bin/forgelm_kernels.cubin bin/forgelm_standalone

all: $(BINS)

bin/test_math: tests/test_math.c src/forgelm_math_avx2.s
	@mkdir -p bin
	$(CC) $(CFLAGS) $^ -o $@ -lm

bin/test_gguf: tests/test_gguf.c src/forgelm_gguf.s
	@mkdir -p bin
	$(CC) $(CFLAGS) $^ -o $@

bin/test_q4: tests/test_q4.c src/forgelm_q4_0_avx2.s
	@mkdir -p bin
	$(CC) $(CFLAGS) $^ -o $@ -lm

bin/benchmark_gemv: tests/benchmark_gemv.c src/forgelm_math_avx2.s
	@mkdir -p bin
	$(CC) $(CFLAGS) $^ -o $@

bin/forgelm_kernels.cubin: $(PTX_SRCS)
	@mkdir -p bin
	$(PTXAS) -arch=$(GPU_ARCH) $< -o $@

bin/forgelm_standalone: src/forgelm_standalone.s
	@mkdir -p bin
	$(AS) $< -o bin/forgelm_standalone.o
	$(LD) bin/forgelm_standalone.o -o $@

test: all
	@echo "================ Running Test Suite ================"
	@./bin/test_math
	@./bin/test_gguf
	@./bin/test_q4
	@./bin/forgelm_standalone
	@echo "================ All tests passed successfully! ================"

benchmark: bin/benchmark_gemv
	@./bin/benchmark_gemv

clean:
	rm -rf bin/*

.PHONY: all test benchmark clean
