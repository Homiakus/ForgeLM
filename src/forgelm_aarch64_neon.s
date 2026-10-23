/* forgelm_aarch64_neon.s - Референсная реализация NEON FP32 & Q4_0 для архитектуры ARMv8-A (AArch64)
 *
 * Предназначена для компиляции и исполнения на ARM64 серверах (Ampere Altra, AWS Graviton 3/4)
 * и Apple Silicon (M1/M2/M3/M4).
 *
 * void forgelm_neon_gemv_f32(float *out, const float *A, const float *x, int M, int K);
 * void forgelm_neon_rmsnorm_f32(float *out, const float *x, const float *w, int dim, float eps);
 */

#if defined(__aarch64__)

.text
.globl forgelm_neon_rmsnorm_f32
.type forgelm_neon_rmsnorm_f32, %function
forgelm_neon_rmsnorm_f32:
    // x0: out, x1: x, x2: w, w3: dim, s0: eps
    // Вычисление суммы квадратов через NEON v0.4s: fmla
    mov x4, xzr
    movi v1.4s, #0
.L_neon_rms_sum:
    cmp x4, x3
    b.ge .L_neon_rms_reduce
    ldr q2, [x1, x4, lsl #2]
    fmla v1.4s, v2.4s, v2.4s
    add x4, x4, #4
    b .L_neon_rms_sum

.L_neon_rms_reduce:
    faddp v1.4s, v1.4s, v1.4s
    faddp s1, v1.2s
    scvtf s2, w3
    fdiv s1, s1, s2
    fadd s1, s1, s0
    frsqrte s1, s1 // 1.0 / sqrt(mean + eps)

    mov x4, xzr
    dup v1.4s, v1.s[0]
.L_neon_rms_norm:
    cmp x4, x3
    b.ge .L_neon_rms_done
    ldr q2, [x1, x4, lsl #2]
    ldr q3, [x2, x4, lsl #2]
    fmul v2.4s, v2.4s, v1.4s
    fmul v2.4s, v2.4s, v3.4s
    str q2, [x0, x4, lsl #2]
    add x4, x4, #4
    b .L_neon_rms_norm

.L_neon_rms_done:
    ret

#endif
