// forgelm_simd128.wat - Референсный модуль WebAssembly SIMD128 для браузерного и Edge инференса
(module
  (memory (export "memory") 1)

  ;; forgelm_wasm_dot_f32(a_offset, b_offset, len) -> f32
  (func (export "forgelm_wasm_dot_f32") (param $a i32) (param $b i32) (param $len i32) (result f32)
    (local $acc v128)
    (local $i i32)
    (local $v1 v128)
    (local $v2 v128)

    (local.set $acc (f32x4.splat (f32.const 0)))
    (local.set $i (i32.const 0))

    (block $break
      (loop $top
        (br_if $break (i32.ge_s (local.get $i) (local.get $len)))
        
        ;; Загрузка 4 float через v128.load
        (local.set $v1 (v128.load (i32.add (local.get $a) (i32.shl (local.get $i) (i32.const 2)))))
        (local.set $v2 (v128.load (i32.add (local.get $b) (i32.shl (local.get $i) (i32.const 2)))))
        
        ;; acc += v1 * v2
        (local.set $acc (f32x4.add (local.get $acc) (f32x4.mul (local.get $v1) (local.get $v2))))

        (local.set $i (i32.add (local.get $i) (i32.const 4)))
        (br $top)
      )
    )

    ;; Горизонтальная сумма 4 float
    (f32.add
      (f32.add (f32x4.extract_lane 0 (local.get $acc)) (f32x4.extract_lane 1 (local.get $acc)))
      (f32.add (f32x4.extract_lane 2 (local.get $acc)) (f32x4.extract_lane 3 (local.get $acc)))
    )
  )
)
