#!/bin/bash
# Source-build the vendored wasmi interpreter. Never download an unknown engine.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script needs macOS/Xcode to build Apple iOS archives." >&2
  exit 1
fi
task_root="$(cd "$(dirname "$0")/../.." && pwd)"
task_native="$task_root/vendor/wasm_run/native"
task_frameworks="$task_root/vendor/wasm_run_flutter/ios/Frameworks"
task_dest="$task_frameworks/WasmRun.xcframework"
task_stage="$(mktemp -d "${TMPDIR:-/tmp}/pocketforge-wasm-ios.XXXXXX")"
trap 'rm -rf "$task_stage"' EXIT

export IPHONEOS_DEPLOYMENT_TARGET=16.0
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$task_root/.build/pocketforge-rust-ios}"
task_rust="${POCKETFORGE_RUST_TOOLCHAIN:-1.91.1}"
task_features="wasmi,wasi"

rustup toolchain install "$task_rust" --profile minimal
# Exercise the production byte-capture/replay implementation on the Mac host
# before spending time on device and simulator cross-compilation.
rustc "+$task_rust" --edition=2021 --test "$task_native/src/stdio.rs" \
  -o "$task_stage/stdio-tests"
"$task_stage/stdio-tests"
rustup target add --toolchain "$task_rust" aarch64-apple-ios aarch64-apple-ios-sim
for task_target in aarch64-apple-ios aarch64-apple-ios-sim; do
  cargo "+$task_rust" build --manifest-path "$task_native/Cargo.toml" \
    --locked --release --no-default-features --features "$task_features" --target "$task_target"
done

task_device="$CARGO_TARGET_DIR/aarch64-apple-ios/release/libwasm_run_dart.a"
task_simulator="$CARGO_TARGET_DIR/aarch64-apple-ios-sim/release/libwasm_run_dart.a"
for task_archive in "$task_device" "$task_simulator"; do
  xcrun nm -gU "$task_archive" > "$task_stage/symbols.txt"
  if ! grep -Eq '[[:space:]]_wire_compile_wasm$' "$task_stage/symbols.txt"; then
    echo "Missing wasm_run FFI entry point in $task_archive" >&2
    exit 1
  fi
done
mkdir -p "$task_stage/headers"
cp "$task_root/vendor/wasm_run_flutter/ios/Classes/frb.h" "$task_stage/headers/frb.h"
xcodebuild -create-xcframework \
  -library "$task_device" -headers "$task_stage/headers" \
  -library "$task_simulator" -headers "$task_stage/headers" \
  -output "$task_stage/WasmRun.xcframework"

# Preserve the upstream Podfile verbatim. Its simulator force_load path uses a
# historical universal-slice name although x86_64 is explicitly excluded there.
# The canonical XCFramework metadata advertises ARM64 only; this alias supplies
# the compatible path without claiming an x86_64 simulator build.
ln -s ios-arm64-simulator "$task_stage/WasmRun.xcframework/ios-arm64_x86_64-simulator"
mkdir -p "$task_frameworks"
if [[ -e "$task_dest" || -L "$task_dest" ]]; then
  # Final target is fixed beneath the checkout; never delete a computed parent.
  python3 - "$task_root" "$task_dest" <<'PY'
import pathlib, shutil, sys
root = pathlib.Path(sys.argv[1]).resolve(strict=True)
target = pathlib.Path(sys.argv[2])
expected = root / "vendor/wasm_run_flutter/ios/Frameworks/WasmRun.xcframework"
if target.absolute() != expected or not target.parent.resolve().is_relative_to(root):
    raise SystemExit("Refusing an unexpected framework replacement target")
if target.is_symlink():
    target.unlink()
else:
    shutil.rmtree(target)
PY
fi
mv "$task_stage/WasmRun.xcframework" "$task_dest"
mkdir -p "$task_root/artifacts/logs"
cargo "+$task_rust" tree --manifest-path "$task_native/Cargo.toml" --locked \
  --no-default-features --features "$task_features" > "$task_root/artifacts/logs/wasm-cargo-tree.txt"
python3 - "$task_root" "$task_rust" <<'PY'
import hashlib, json, pathlib, subprocess, sys
root=pathlib.Path(sys.argv[1])
native=root/"vendor/wasm_run/native"
manifest={
  "engine":"wasmi interpreter built from vendored Rust source",
  "features":["wasmi","wasi"], "prebuiltFallback":False,
  "rustToolchain":sys.argv[2], "deviceTarget":"aarch64-apple-ios",
  "simulatorTarget":"aarch64-apple-ios-sim", "minimumIOS":"16.0",
  "sourceRevision":subprocess.check_output(["git","rev-parse","HEAD"],cwd=root,text=True).strip(),
  "cargoLockSHA256":hashlib.sha256((native/"Cargo.lock").read_bytes()).hexdigest(),
  "cargoManifestSHA256":hashlib.sha256((native/"Cargo.toml").read_bytes()).hexdigest(),
}
(root/"artifacts/wasm-ios-provenance.json").write_text(json.dumps(manifest,indent=2)+"\n")
print(json.dumps(manifest,indent=2))
PY
