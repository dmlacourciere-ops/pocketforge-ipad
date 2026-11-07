#!/bin/bash
# Optional unsigned verification on a disposable ARM64 Mac CI worker.
# Provider-specific inputs are only CM_BUILD_DIR and PROJECT_BUILD_NUMBER.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo 'PocketForge iOS verification requires an Apple silicon Mac with Xcode.' >&2
  exit 1
fi

task_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
if [[ -n "${CM_BUILD_DIR:-}" && "$(cd "$CM_BUILD_DIR" && pwd -P)" != "$task_root" ]]; then
  echo 'CM_BUILD_DIR must identify this checkout.' >&2
  exit 1
fi
cd "$task_root"
task_build_number="${PROJECT_BUILD_NUMBER:-1}"
if [[ ! "$task_build_number" =~ ^[0-9]+$ ]]; then
  echo 'PROJECT_BUILD_NUMBER must be a nonnegative integer.' >&2
  exit 1
fi
# A project's CI counter can begin at zero; Apple's app build stays positive.
task_build_number=$(python3 -c 'import sys; print(int(sys.argv[1]) + 1)' "$task_build_number")
export IPHONEOS_DEPLOYMENT_TARGET=16.0
export POCKETFORGE_RUST_TOOLCHAIN="${POCKETFORGE_RUST_TOOLCHAIN:-1.91.1}"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}"
export CARGO_TARGET_DIR="$task_root/.build/pocketforge-rust-ios"
export PATH="$HOME/.cargo/bin:$PATH"
mkdir -p artifacts/logs

task_simulator_id=''
task_stage="$(mktemp -d "${TMPDIR:-/tmp}/pocketforge-ios-verify.XXXXXX")"
cleanup() {
  if [[ -n "$task_simulator_id" ]]; then
    xcrun simctl shutdown "$task_simulator_id" >/dev/null 2>&1 || true
  fi
  rm -rf "$task_stage"
}
trap cleanup EXIT

{
  git rev-parse HEAD
  uname -a
  xcodebuild -version
  xcrun --sdk iphoneos --show-sdk-version
  printf 'Project build number: %s\n' "$task_build_number"
} | tee artifacts/logs/build-host.txt

python3 -m unittest discover -s tools/pocketforge -p 'test_prepare_ios.py' -v 2>&1 | tee artifacts/logs/prepare-tests.txt
python3 tools/pocketforge/prepare_ios.py 2>&1 | tee artifacts/logs/prepare-ios.txt
python3 tools/pocketforge/prepare_ios.py --check
# No provider credential or inherited upstream .env value enters this bundle.
: > flutter_app/.env

flutter config --no-analytics
flutter config --no-enable-swift-package-manager
flutter --version --machine | tee artifacts/logs/flutter-version.json
python3 - <<'PY'
import json
from pathlib import Path
version = json.loads(Path('artifacts/logs/flutter-version.json').read_text())['frameworkVersion']
if version != '3.47.9':
    raise SystemExit(f'Expected Flutter 3.47.9, received {version}. Check codemagic.yaml.')
PY
(cd flutter_app && flutter pub get) 2>&1 | tee artifacts/logs/flutter-pub-get.txt

# Codemagic's image may not contain rustup. Install its official bootstrap only
# when absent; build_wasm_ios.sh then installs the pinned compiler and both targets.
if ! command -v rustup >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
    https://sh.rustup.rs --output "$task_stage/rustup-init.sh"
  sh "$task_stage/rustup-init.sh" -y --profile minimal --default-toolchain none --no-modify-path \
    2>&1 | tee artifacts/logs/rustup-bootstrap.txt
fi
bash tools/pocketforge/build_wasm_ios.sh 2>&1 | tee artifacts/logs/wasm-ios-build.txt

(cd flutter_app && flutter analyze --no-pub lib/main_pocketforge.dart lib/pocketforge test/pocketforge) \
  2>&1 | tee artifacts/logs/pocketforge-analyze.txt
(cd flutter_app && flutter test --no-pub test/pocketforge) 2>&1 | tee artifacts/logs/pocketforge-tests.txt
(cd flutter_app && flutter test --no-pub test/wasm_shell_pipeline_test.dart \
  --plain-name 'fast WASI exit keeps queued stdout and stderr in callbacks and result') \
  2>&1 | tee artifacts/logs/wasm-stdio-regression.txt

# The committed goldens were captured on Windows. Preserve Mac differences as
# diagnostics without using font drift to hide the native runtime/build result.
if (cd flutter_app && flutter test --no-pub test/golden/pocketforge_golden_test.dart) \
  2>&1 | tee artifacts/logs/pocketforge-goldens.txt; then
  printf 'passed\n' > artifacts/logs/golden-status.txt
else
  printf 'failed; inspect the retained comparison diagnostics\n' > artifacts/logs/golden-status.txt
  echo 'Golden comparison differs on this Mac; continuing to the native checks.'
fi

xcrun simctl list devices available --json > artifacts/logs/simulator-devices.json
task_simulator_selection=$(python3 - <<'PY'
import json
from pathlib import Path
data = json.loads(Path('artifacts/logs/simulator-devices.json').read_text())
devices = [device for group in data['devices'].values() for device in group
           if device.get('isAvailable') and 'iPad' in device.get('name', '')]
devices.sort(key=lambda device: ('A17 Pro' not in device['name'], device['name']))
if not devices:
    raise SystemExit('No available iPad simulator runtime on this Mac worker.')
selected = devices[0]
Path('artifacts/logs/selected-simulator.json').write_text(json.dumps(selected, indent=2) + '\n')
print(selected['udid'], selected.get('state', 'Shutdown'))
PY
)
read -r task_simulator_id task_simulator_state <<< "$task_simulator_selection"
if [[ "$task_simulator_state" != 'Booted' ]]; then
  xcrun simctl boot "$task_simulator_id"
fi
xcrun simctl bootstatus "$task_simulator_id" -b
(cd flutter_app && flutter test --no-pub --no-uninstall integration_test/pocketforge_native_test.dart \
  --device-id "$task_simulator_id" --timeout 15m) 2>&1 | tee artifacts/logs/native-ipad-smoke.txt
task_app_data=$(xcrun simctl get_app_container "$task_simulator_id" com.pocketforge.ipad data)
cp "$task_app_data/Documents/fah_sandbox/pocketforge-state/native-smoke-report.json" artifacts/
cp "$task_app_data/Documents/fah_sandbox/pocketforge-state/native-smoke-preview.png" artifacts/
xcrun simctl shutdown "$task_simulator_id"
task_simulator_id=''

(cd flutter_app && flutter build ios --release --no-codesign --no-pub \
  --target lib/main_pocketforge.dart --build-name 0.1.0 --build-number "$task_build_number") \
  2>&1 | tee artifacts/logs/ios-release-build.txt

task_app="$task_root/flutter_app/build/ios/iphoneos/Runner.app"
task_executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$task_app/Info.plist")
xcrun dyld_info -exports "$task_app/$task_executable" > artifacts/logs/runner-exports.txt
for task_symbol in _wire_compile_wasm _store_dart_post_cobject _init_frb_dart_api_dl; do
  if ! grep -Eq "[[:space:]]${task_symbol}$" artifacts/logs/runner-exports.txt; then
    echo "Required wasm_run dlsym export missing: $task_symbol" >&2
    exit 1
  fi
done
if ! grep -q '_NativeCupertinoHttp_' artifacts/logs/runner-exports.txt; then
  echo 'Native HTTP FFI trampolines were stripped.' >&2
  exit 1
fi
test ! -e "$task_app/embedded.mobileprovision"
test ! -d "$task_app/PlugIns/FaLiveActivity.appex"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$task_app/Info.plist" | grep -Fx 'com.pocketforge.ipad'

mkdir -p "$task_stage/Payload"
ditto "$task_app" "$task_stage/Payload/Runner.app"
ditto -c -k --keepParent "$task_stage/Payload" "$task_root/artifacts/PocketForge-unsigned.ipa"
shasum -a 256 artifacts/PocketForge-unsigned.ipa > artifacts/PocketForge-unsigned.ipa.sha256
cat > artifacts/UNSIGNED-READ-ME.txt <<'TEXT'
PocketForge unsigned source build.
This artifact has no Apple provisioning profile and is NOT installable by tapping it.
Use the separate authorized signing/install instructions in tools/pocketforge/INSTALL_WINDOWS.md.
This verification does not sign, publish, deploy, submit to App Review, or upload to TestFlight.
The native smoke report is an ARM64 iPad SIMULATOR result, not a physical-iPad test.
Review its recorded checks and screenshot, alongside build logs and FFI export checks.
TEXT
printf '\nUnsigned artifact ready: artifacts/PocketForge-unsigned.ipa\n'
