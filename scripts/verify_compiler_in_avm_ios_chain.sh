#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p build/logs build/tmp

COMPILER="${OREN_COMPILER:-./oren}"
if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not executable: $COMPILER" >&2
  exit 2
fi
if [[ ! -x ./avm ]]; then
  echo "ERROR: ./avm not executable; run make avm" >&2
  exit 2
fi

tag="${OREN_VERIFY_TAG:-$(date +%Y%m%d_%H%M%S)}"
plugins_log="build/logs/build_avm_plugins_compiler_obc_${tag}.log"
harness_build_log="build/logs/build_compiler_in_avm_vfs_stdlib_obc_harness_${tag}.log"
harness_run_log="build/logs/run_compiler_in_avm_vfs_stdlib_obc_harness_${tag}.log"
harness_obc="build/tmp/compiler_in_avm_vfs_stdlib_obc_harness_${tag}.obc"
compilerkit_src="build/tmp/compilerkit_smoke_${tag}.m"
compilerkit_bin="build/tmp/compilerkit_smoke_${tag}"
compilerkit_log="build/logs/run_compilerkit_smoke_${tag}.log"

echo "== build AVM stdlib/compiler OBC plugins =="
OREN_COMPILER="$COMPILER" OREN_BUILD_COMPILER_OBC=1 ./scripts/build_avm_plugins.sh >"$plugins_log" 2>&1 || {
  echo "FAIL: plugin OBC build failed" >&2
  tail -n 160 "$plugins_log" >&2 || true
  exit 3
}

cp build/plugins/oren.obc build/oren_compiler.obc
cp build/plugins/stdlib_bundle.obc build/stdlib_bundle.obc

echo "== build compiler-in-AVM harness =="
"$COMPILER" build tests/avm/fixtures/compiler_in_avm_vfs_stdlib_obc_harness.oren \
  --backend bytecode -o "$harness_obc" >"$harness_build_log" 2>&1 || {
  echo "FAIL: harness bytecode build failed" >&2
  tail -n 160 "$harness_build_log" >&2 || true
  exit 4
}

echo "== run compiler-in-AVM harness =="
./avm "$harness_obc" >"$harness_run_log" 2>&1 || {
  echo "FAIL: compiler-in-AVM harness failed" >&2
  tail -n 220 "$harness_run_log" >&2 || true
  exit 5
}

if ! grep -q "compiler in avm vfs stdlib obc OK" "$harness_run_log"; then
  echo "FAIL: harness success marker missing" >&2
  tail -n 220 "$harness_run_log" >&2 || true
  exit 6
fi

cat > "$compilerkit_src" <<'OBJC'
#import <Foundation/Foundation.h>
#import "OrenAVMKit.h"

int main(void) {
    @autoreleasepool {
        NSError* error = nil;
        OrenAVMCompilerKit* kit = [OrenAVMCompilerKit compilerKitWithCompilerOBCURL:[NSURL fileURLWithPath:@"build/plugins/oren.obc"]
                                                                       stdlibOBCURL:[NSURL fileURLWithPath:@"build/plugins/stdlib_bundle.obc"]
                                                                             error:&error];
        if (!kit) { fprintf(stderr, "CompilerKit load failed: %s\n", error.localizedDescription.UTF8String); return 10; }
        if (kit.compilerHeapLimitBytes < 384ull * 1024ull * 1024ull) {
            fprintf(stderr, "CompilerKit heap default too small: %llu\n", (unsigned long long)kit.compilerHeapLimitBytes);
            return 15;
        }
        NSString* source =
            @"import list \"std:list\"\n"
             "import time \"std:time\"\n"
             "fn main() {\n"
             "    var xs = []\n"
             "    list.push(xs, 7)\n"
             "    if time.sleep_ms(1) != 0 { oren_exit(2) }\n"
             "    if list.len(xs) == 1 && xs[0] == 7 { oren_exit(7) }\n"
             "    oren_exit(1)\n"
             "}\n"
             "main()\n";
        OrenAVMCompileResult* compiled = [kit compileSource:source platform:@"arm64-macos" error:&error];
        if (!compiled || compiled.obcData.length == 0 || compiled.compilerRunResult.exitCode != 0) {
            fprintf(stderr, "CompilerKit compile failed: %s\n", error.localizedDescription.UTF8String);
            return 11;
        }

        OrenAVMRuntimeConfig* cfg = [OrenAVMRuntimeConfig deterministicDefaults];
        cfg.allowedDomains = OrenAVMDomainCore | OrenAVMDomainTime | OrenAVMDomainExit;
        OrenAVMRuntime* runtime = [[OrenAVMRuntime alloc] initWithConfig:cfg];
        if (!runtime) { fprintf(stderr, "runtime init failed\n"); return 12; }
        OrenAVMRunResult* result = [runtime runOBCData:compiled.obcData error:&error];
        if (!result) { fprintf(stderr, "compiled OBC run failed: %s\n", error.localizedDescription.UTF8String); return 13; }
        if (result.exitCode != 7) {
            fprintf(stderr, "compiled OBC exit mismatch: %ld\n", (long)result.exitCode);
            return 14;
        }
        return 0;
    }
}
OBJC

HOST_SOURCES=()
while IFS= read -r src; do
  HOST_SOURCES+=("$src")
done < <(
  find lib/avm -maxdepth 1 -name '*.c' \
    ! -name 'main.c' \
    ! -name 'avm_cli_disasm.c' \
    ! -name 'avm_cli_dump.c' \
    ! -name 'avm_cli_fs.c' \
    ! -name 'avm_cli_policy.c' \
    ! -name 'avm_cli_util.c' \
    -print | sort
  printf '%s\n' third_party/tweetnacl/tweetnacl.c
)

echo "== run OrenAVMCompilerKit SDK smoke =="
clang -std=c11 -O3 -fno-fast-math -ffp-contract=off -DAVM_EMBED_NO_ABORT_ON_LEAK=1 \
  -Ilib/avm -Isdk/ios/OrenAVMKit -Ibuild \
  "$compilerkit_src" sdk/ios/OrenAVMKit/OrenAVMKit.m sdk/ios/OrenAVMKit/OrenAVMCompilerKit.m \
  sdk/ios/OrenAVMKit/OrenAVMRuntimeTypes.m \
  "${HOST_SOURCES[@]}" -fobjc-arc -framework Foundation -framework Security -o "$compilerkit_bin" >"$compilerkit_log" 2>&1 || {
  echo "FAIL: CompilerKit SDK smoke build failed" >&2
  tail -n 180 "$compilerkit_log" >&2 || true
  exit 7
}
"$compilerkit_bin" >>"$compilerkit_log" 2>&1 || {
  echo "FAIL: CompilerKit SDK smoke failed" >&2
  tail -n 220 "$compilerkit_log" >&2 || true
  exit 8
}

echo "OK: compiler-in-AVM iOS embedding chain passed"
echo "logs:"
echo "  $plugins_log"
echo "  $harness_build_log"
echo "  $harness_run_log"
echo "  $compilerkit_log"
