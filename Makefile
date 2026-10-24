CC = gcc
CFLAGS = -O3 -mavx2 -mf16c -mfma -Wall -Wextra -Iinclude
AS = as
LD = ld
PTXAS = ptxas
GPU_ARCH = sm_61

ASM_SRCS = src/forgelm_math_avx2.s src/forgelm_gguf.s src/forgelm_rope_softmax.s src/forgelm_q4_0_avx2.s src/forgelm_syscalls.s src/forgelm_threads_avx2.s src/forgelm_flash_attn_avx2.s src/forgelm_tokenizer.s src/forgelm_server.s src/forgelm_speculative.s src/forgelm_paged_kv.s src/forgelm_q4_k_avx2.s src/forgelm_sampler.s src/forgelm_gguf_tensor.s src/forgelm_jit.s src/forgelm_radix_cache.s src/forgelm_tui.s
PTX_SRCS = src/forgelm_kernels.ptx
BINS = bin/test_math bin/test_gguf bin/test_q4 bin/benchmark_gemv bin/forgelm_kernels.cubin bin/forgelm_standalone bin/test_spin_pool_q4 bin/test_flash_attn bin/test_tokenizer bin/test_transformer_block bin/test_server bin/test_speculative bin/test_paged_kv bin/test_q4_k bin/test_sampler bin/test_gguf_tensor bin/test_jit bin/test_radix_cache bin/test_tui

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

bin/test_spin_pool_q4: tests/test_spin_pool_q4.c src/forgelm_q4_0_avx2.s
	@mkdir -p bin
	$(CC) $(CFLAGS) $^ -o $@ -lpthread -lm

bin/test_flash_attn: tests/test_flash_attn.c src/forgelm_flash_attn_avx2.s
	@mkdir -p bin
	$(CC) $(CFLAGS) $^ -o $@ -lm

bin/test_tokenizer: tests/test_tokenizer.c src/forgelm_tokenizer.s
	@mkdir -p bin
	$(CC) $(CFLAGS) $^ -o $@

bin/test_transformer_block: tests/test_transformer_block.c src/forgelm_math_avx2.s src/forgelm_rope_softmax.s src/forgelm_flash_attn_avx2.s src/forgelm_threads_avx2.s
	@mkdir -p bin
	$(CC) $(CFLAGS) $^ -o $@ -lm

bin/test_server: tests/test_server.c src/forgelm_server.s
	@mkdir -p bin
	$(CC) $(CFLAGS) $^ -o $@ -lpthread

bin/test_speculative: tests/test_speculative.c src/forgelm_speculative.s
	@mkdir -p bin
	$(CC) $(CFLAGS) $^ -o $@

bin/test_paged_kv: tests/test_paged_kv.c src/forgelm_paged_kv.s
	@mkdir -p bin
	$(CC) $(CFLAGS) $^ -o $@

bin/test_q4_k: tests/test_q4_k.c src/forgelm_q4_k_avx2.s
	@mkdir -p bin
	$(CC) $(CFLAGS) $^ -o $@ -lm

bin/test_sampler: tests/test_sampler.c src/forgelm_sampler.s
	@mkdir -p bin
	$(CC) $(CFLAGS) -mrdrnd $^ -o $@ -lm

bin/test_gguf_tensor: tests/test_gguf_tensor.c src/forgelm_gguf_tensor.s
	@mkdir -p bin
	$(CC) $(CFLAGS) $^ -o $@

bin/test_jit: tests/test_jit.c src/forgelm_jit.s
	@mkdir -p bin
	$(CC) $(CFLAGS) $^ -o $@ -lm

bin/test_radix_cache: tests/test_radix_cache.c src/forgelm_radix_cache.s
	@mkdir -p bin
	$(CC) $(CFLAGS) $^ -o $@

bin/test_tui: tests/test_tui.c src/forgelm_tui.s
	@mkdir -p bin
	$(CC) $(CFLAGS) $^ -o $@

bin/benchmark_gemv: tests/benchmark_gemv.c src/forgelm_math_avx2.s
	@mkdir -p bin
	$(CC) $(CFLAGS) $^ -o $@

bin/forgelm_kernels.cubin: $(PTX_SRCS)
	@mkdir -p bin
	$(PTXAS) -arch=$(GPU_ARCH) $< -o $@

bin/forgelm_standalone: src/forgelm_standalone.s src/forgelm_gguf.s src/forgelm_tui.s
	@mkdir -p bin
	$(AS) src/forgelm_standalone.s -o bin/forgelm_standalone.o
	$(AS) src/forgelm_gguf.s -o bin/forgelm_gguf.o
	$(AS) src/forgelm_tui.s -o bin/forgelm_tui.o
	$(LD) bin/forgelm_standalone.o bin/forgelm_gguf.o bin/forgelm_tui.o -o $@

test: all
	@echo "================ Running Test Suite ================"
	@./bin/test_math
	@./bin/test_gguf
	@./bin/test_q4
	@./bin/test_spin_pool_q4
	@./bin/test_flash_attn
	@./bin/test_tokenizer
	@./bin/test_transformer_block
	@./bin/test_server
	@./bin/test_speculative
	@./bin/test_paged_kv
	@./bin/test_q4_k
	@./bin/test_sampler
	@./bin/test_gguf_tensor
	@./bin/test_jit
	@./bin/test_radix_cache
	@./bin/test_tui
	@./bin/forgelm_standalone
	@echo "================ All tests passed successfully! ================"

benchmark: bin/benchmark_gemv
	@./bin/benchmark_gemv

clean:
	rm -rf bin/*

.PHONY: all test benchmark clean
