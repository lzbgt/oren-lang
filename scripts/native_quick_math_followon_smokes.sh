# Sourced by run_native_quick_integration.sh after base/runtime smoke coverage.

echo "== math cbrt smoke (native/C/bytecode) =="
math_cbrt_src="tests/modules/test_math_cbrt.oren"
math_cbrt_log="build/logs/${compiler_base}_math_cbrt.log"
rm -f "$math_cbrt_log" 2>/dev/null || true

run_step_checked "math cbrt smoke (native)" "$math_cbrt_log" \
  "$compiler" test "$math_cbrt_src" --backend native --platform "$platform" --no-cache
run_step_checked "math cbrt smoke (C)" "$math_cbrt_log" \
  "$compiler" test "$math_cbrt_src" --backend c --platform "$platform" --no-cache
run_step_checked "math cbrt smoke (bytecode)" "$math_cbrt_log" \
  "$compiler" test "$math_cbrt_src" --backend bytecode --platform "$platform" --no-cache
tail -n 8 "$math_cbrt_log"

echo "== math modf smoke (native/C/bytecode) =="
math_modf_src="tests/modules/test_math_modf.oren"
math_modf_log="build/logs/${compiler_base}_math_modf.log"
rm -f "$math_modf_log" 2>/dev/null || true

run_step_checked "math modf smoke (native)" "$math_modf_log" \
  "$compiler" test "$math_modf_src" --backend native --platform "$platform" --no-cache
run_step_checked "math modf smoke (C)" "$math_modf_log" \
  "$compiler" test "$math_modf_src" --backend c --platform "$platform" --no-cache
run_step_checked "math modf smoke (bytecode)" "$math_modf_log" \
  "$compiler" test "$math_modf_src" --backend bytecode --platform "$platform" --no-cache
tail -n 8 "$math_modf_log"

echo "== math remainder smoke (native/C/bytecode) =="
math_remainder_src="tests/modules/test_math_remainder.oren"
math_remainder_log="build/logs/${compiler_base}_math_remainder.log"
rm -f "$math_remainder_log" 2>/dev/null || true

run_step_checked "math remainder smoke (native)" "$math_remainder_log" \
  "$compiler" test "$math_remainder_src" --backend native --platform "$platform" --no-cache
run_step_checked "math remainder smoke (C)" "$math_remainder_log" \
  "$compiler" test "$math_remainder_src" --backend c --platform "$platform" --no-cache
run_step_checked "math remainder smoke (bytecode)" "$math_remainder_log" \
  "$compiler" test "$math_remainder_src" --backend bytecode --platform "$platform" --no-cache
tail -n 8 "$math_remainder_log"

echo "== math nextafter smoke (native/C/bytecode) =="
math_nextafter_src="tests/modules/test_math_nextafter.oren"
math_nextafter_log="build/logs/${compiler_base}_math_nextafter.log"
rm -f "$math_nextafter_log" 2>/dev/null || true

run_step_checked "math nextafter smoke (native)" "$math_nextafter_log" \
  "$compiler" test "$math_nextafter_src" --backend native --platform "$platform" --no-cache
run_step_checked "math nextafter smoke (C)" "$math_nextafter_log" \
  "$compiler" test "$math_nextafter_src" --backend c --platform "$platform" --no-cache
run_step_checked "math nextafter smoke (bytecode)" "$math_nextafter_log" \
  "$compiler" test "$math_nextafter_src" --backend bytecode --platform "$platform" --no-cache
tail -n 8 "$math_nextafter_log"

echo "== math logb/round_even smoke (native/C/bytecode) =="
math_logb_round_even_src="tests/modules/test_math_logb_round_even.oren"
math_logb_round_even_log="build/logs/${compiler_base}_math_logb_round_even.log"
rm -f "$math_logb_round_even_log" 2>/dev/null || true

run_step_checked "math logb/round_even smoke (native)" "$math_logb_round_even_log" \
  "$compiler" test "$math_logb_round_even_src" --backend native --platform "$platform" --no-cache
run_step_checked "math logb/round_even smoke (C)" "$math_logb_round_even_log" \
  "$compiler" test "$math_logb_round_even_src" --backend c --platform "$platform" --no-cache
run_step_checked "math logb/round_even smoke (bytecode)" "$math_logb_round_even_log" \
  "$compiler" test "$math_logb_round_even_src" --backend bytecode --platform "$platform" --no-cache
tail -n 8 "$math_logb_round_even_log"

echo "== math inverse trig smoke (native/C/bytecode) =="
math_inverse_trig_src="tests/modules/test_math_inverse_trig.oren"
math_inverse_trig_log="build/logs/${compiler_base}_math_inverse_trig.log"
rm -f "$math_inverse_trig_log" 2>/dev/null || true

run_step_checked "math inverse trig smoke (native)" "$math_inverse_trig_log" \
  "$compiler" test "$math_inverse_trig_src" --backend native --platform "$platform" --no-cache
run_step_checked "math inverse trig smoke (C)" "$math_inverse_trig_log" \
  "$compiler" test "$math_inverse_trig_src" --backend c --platform "$platform" --no-cache
run_step_checked "math inverse trig smoke (bytecode)" "$math_inverse_trig_log" \
  "$compiler" test "$math_inverse_trig_src" --backend bytecode --platform "$platform" --no-cache
tail -n 8 "$math_inverse_trig_log"

echo "== math huge trig smoke (native/C/bytecode) =="
math_trig_huge_src="tests/modules/test_math_trig_huge.oren"
math_trig_huge_log="build/logs/${compiler_base}_math_trig_huge.log"
rm -f "$math_trig_huge_log" 2>/dev/null || true

run_step_checked "math huge trig smoke (native)" "$math_trig_huge_log" \
  "$compiler" test "$math_trig_huge_src" --backend native --platform "$platform" --no-cache
run_step_checked "math huge trig smoke (C)" "$math_trig_huge_log" \
  "$compiler" test "$math_trig_huge_src" --backend c --platform "$platform" --no-cache
run_step_checked "math huge trig smoke (bytecode)" "$math_trig_huge_log" \
  "$compiler" test "$math_trig_huge_src" --backend bytecode --platform "$platform" --no-cache
tail -n 8 "$math_trig_huge_log"

echo "== math hyperbolic smoke (native/C/bytecode) =="
math_hyperbolic_src="tests/modules/test_math_hyperbolic.oren"
math_hyperbolic_log="build/logs/${compiler_base}_math_hyperbolic.log"
rm -f "$math_hyperbolic_log" 2>/dev/null || true

run_step_checked "math hyperbolic smoke (native)" "$math_hyperbolic_log" \
  "$compiler" test "$math_hyperbolic_src" --backend native --platform "$platform" --no-cache
run_step_checked "math hyperbolic smoke (C)" "$math_hyperbolic_log" \
  "$compiler" test "$math_hyperbolic_src" --backend c --platform "$platform" --no-cache
run_step_checked "math hyperbolic smoke (bytecode)" "$math_hyperbolic_log" \
  "$compiler" test "$math_hyperbolic_src" --backend bytecode --platform "$platform" --no-cache
tail -n 8 "$math_hyperbolic_log"

echo "== math exp/log special smoke (native/C/bytecode) =="
math_exp_log_special_src="tests/modules/test_math_exp_log_special.oren"
math_exp_log_special_log="build/logs/${compiler_base}_math_exp_log_special.log"
rm -f "$math_exp_log_special_log" 2>/dev/null || true

run_step_checked "math exp/log special smoke (native)" "$math_exp_log_special_log" \
  "$compiler" test "$math_exp_log_special_src" --backend native --platform "$platform" --no-cache
run_step_checked "math exp/log special smoke (C)" "$math_exp_log_special_log" \
  "$compiler" test "$math_exp_log_special_src" --backend c --platform "$platform" --no-cache
run_step_checked "math exp/log special smoke (bytecode)" "$math_exp_log_special_log" \
  "$compiler" test "$math_exp_log_special_src" --backend bytecode --platform "$platform" --no-cache
tail -n 8 "$math_exp_log_special_log"

echo "== math erf smoke (native/C/bytecode) =="
math_erf_src="tests/modules/test_math_erf.oren"
math_erf_log="build/logs/${compiler_base}_math_erf.log"
rm -f "$math_erf_log" 2>/dev/null || true

run_step_checked "math erf smoke (native)" "$math_erf_log" \
  "$compiler" test "$math_erf_src" --backend native --platform "$platform" --no-cache
run_step_checked "math erf smoke (C)" "$math_erf_log" \
  "$compiler" test "$math_erf_src" --backend c --platform "$platform" --no-cache
run_step_checked "math erf smoke (bytecode)" "$math_erf_log" \
  "$compiler" test "$math_erf_src" --backend bytecode --platform "$platform" --no-cache
tail -n 8 "$math_erf_log"

echo "== math gamma smoke (native/C/bytecode) =="
math_gamma_src="tests/modules/test_math_gamma.oren"
math_gamma_log="build/logs/${compiler_base}_math_gamma.log"
rm -f "$math_gamma_log" 2>/dev/null || true

run_step_checked "math gamma smoke (native)" "$math_gamma_log" \
  "$compiler" test "$math_gamma_src" --backend native --platform "$platform" --no-cache
run_step_checked "math gamma smoke (C)" "$math_gamma_log" \
  "$compiler" test "$math_gamma_src" --backend c --platform "$platform" --no-cache
run_step_checked "math gamma smoke (bytecode)" "$math_gamma_log" \
  "$compiler" test "$math_gamma_src" --backend bytecode --platform "$platform" --no-cache
tail -n 8 "$math_gamma_log"

echo "== math quat smoke (native/C/bytecode) =="
math_quat_src="tests/modules/test_math_quat.oren"
math_quat_log="build/logs/${compiler_base}_math_quat.log"
rm -f "$math_quat_log" 2>/dev/null || true

run_step_checked "math quat smoke (native)" "$math_quat_log" \
  "$compiler" test "$math_quat_src" --backend native --platform "$platform" --no-cache
run_step_checked "math quat smoke (C)" "$math_quat_log" \
  "$compiler" test "$math_quat_src" --backend c --platform "$platform" --no-cache
run_step_checked "math quat smoke (bytecode)" "$math_quat_log" \
  "$compiler" test "$math_quat_src" --backend bytecode --platform "$platform" --no-cache
tail -n 8 "$math_quat_log"

echo "== math mat4 smoke (native/C/bytecode) =="
math_mat4_src="tests/modules/test_math_mat4.oren"
math_mat4_log="build/logs/${compiler_base}_math_mat4.log"
rm -f "$math_mat4_log" 2>/dev/null || true

run_step_checked "math mat4 smoke (native)" "$math_mat4_log" \
  "$compiler" test "$math_mat4_src" --backend native --platform "$platform" --no-cache
run_step_checked "math mat4 smoke (C)" "$math_mat4_log" \
  "$compiler" test "$math_mat4_src" --backend c --platform "$platform" --no-cache
run_step_checked "math mat4 smoke (bytecode)" "$math_mat4_log" \
  "$compiler" test "$math_mat4_src" --backend bytecode --platform "$platform" --no-cache
tail -n 8 "$math_mat4_log"

echo "== math vec2 smoke (native/C/bytecode) =="
math_vec2_src="tests/modules/test_math_vec2.oren"
math_vec2_log="build/logs/${compiler_base}_math_vec2.log"
rm -f "$math_vec2_log" 2>/dev/null || true

run_step_checked "math vec2 smoke (native)" "$math_vec2_log" \
  "$compiler" test "$math_vec2_src" --backend native --platform "$platform" --no-cache
run_step_checked "math vec2 smoke (C)" "$math_vec2_log" \
  "$compiler" test "$math_vec2_src" --backend c --platform "$platform" --no-cache
run_step_checked "math vec2 smoke (bytecode)" "$math_vec2_log" \
  "$compiler" test "$math_vec2_src" --backend bytecode --platform "$platform" --no-cache
tail -n 8 "$math_vec2_log"

echo "== math vec3 smoke (native/C/bytecode) =="
math_vec3_src="tests/modules/test_math_vec3.oren"
math_vec3_log="build/logs/${compiler_base}_math_vec3.log"
rm -f "$math_vec3_log" 2>/dev/null || true

run_step_checked "math vec3 smoke (native)" "$math_vec3_log" \
  "$compiler" test "$math_vec3_src" --backend native --platform "$platform" --no-cache
run_step_checked "math vec3 smoke (C)" "$math_vec3_log" \
  "$compiler" test "$math_vec3_src" --backend c --platform "$platform" --no-cache
run_step_checked "math vec3 smoke (bytecode)" "$math_vec3_log" \
  "$compiler" test "$math_vec3_src" --backend bytecode --platform "$platform" --no-cache
tail -n 8 "$math_vec3_log"

echo "== math vec4 smoke (native/C/bytecode) =="
math_vec4_src="tests/modules/test_math_vec4.oren"
math_vec4_log="build/logs/${compiler_base}_math_vec4.log"
rm -f "$math_vec4_log" 2>/dev/null || true

run_step_checked "math vec4 smoke (native)" "$math_vec4_log" \
  "$compiler" test "$math_vec4_src" --backend native --platform "$platform" --no-cache
run_step_checked "math vec4 smoke (C)" "$math_vec4_log" \
  "$compiler" test "$math_vec4_src" --backend c --platform "$platform" --no-cache
run_step_checked "math vec4 smoke (bytecode)" "$math_vec4_log" \
  "$compiler" test "$math_vec4_src" --backend bytecode --platform "$platform" --no-cache
tail -n 8 "$math_vec4_log"

echo "== module integration suite (native + bytecode) =="
module_integration_src="tests/modules/test_integration_suite.oren"
module_integration_log="build/logs/${compiler_base}_module_integration_suite.log"
rm -f "$module_integration_log" 2>/dev/null || true

run_step_checked "module integration suite (native)" "$module_integration_log" \
  "$compiler" test "$module_integration_src" --backend native --platform "$platform"
run_step_checked "module integration suite (bytecode)" "$module_integration_log" \
  "$compiler" test "$module_integration_src" --backend bytecode --platform "$platform"
tail -n 8 "$module_integration_log"

echo "== codec smoke (YAML native comments) =="
yaml_comments_src="tests/modules/test_yaml_comments.oren"
yaml_comments_log="build/logs/${compiler_base}_yaml_comments_native.log"
rm -f "$yaml_comments_log" 2>/dev/null || true

run_step_checked "codec smoke (YAML native comments)" "$yaml_comments_log" \
  "$compiler" test "$yaml_comments_src" --backend native
tail -n 5 "$yaml_comments_log"

echo "== codec smoke (YAML native serde attrs) =="
yaml_serde_src="tests/modules/test_yaml_serde_attrs.oren"
yaml_serde_log="build/logs/${compiler_base}_yaml_serde_attrs_native.log"
rm -f "$yaml_serde_log" 2>/dev/null || true

run_step_checked "codec smoke (YAML native serde attrs)" "$yaml_serde_log" \
  "$compiler" test "$yaml_serde_src" --backend native
tail -n 5 "$yaml_serde_log"
