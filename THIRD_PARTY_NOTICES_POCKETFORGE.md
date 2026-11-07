# PocketForge third-party notice ledger

This ledger records identified notices in this source checkout. It supplements
the original license files and Flutter's generated package-license registry; it
does not replace their terms or establish that every transitive native binary
has been audited. Recheck the resolved lockfiles, downloaded native artifacts
and assets when preparing a distributable build.

## Fa source

Flutter Agent Harness (Fa), https://github.com/IstiN/flutter_agent_harness,
baseline `cff76fc1d9248cace976db1fb6d6b8a5d9f6ad73`, is MIT licensed,
copyright (c) 2026 IstiN. [LICENSE](LICENSE) is retained unchanged. Its copyright
and permission notice must accompany copies or substantial portions. Product
assets also include `flutter_app/assets/pocketforge/LICENSE.fa.txt`.

The local `packages/fa_ui`, `packages/fa_llm`, `packages/fa_llm_mock` and
`packages/dap_hub` retain their existing `LICENSE` files and source headers.

## Vendored source and native runtime

| Component | License/notice retained | Source |
| --- | --- | --- |
| wasm_run / wasm_run_flutter | MIT, copyright 2023 Juan Manuel Castillo; `vendor/wasm_run/LICENSE`, `vendor/wasm_run_flutter/LICENSE` | https://github.com/juancastillo0/wasm_run |
| quickjs_runtime | MIT; `vendor/quickjs_runtime/LICENSE` | Vendored package's upstream metadata |
| flutter_inappwebview_macos | Apache 2.0; `vendor/flutter_inappwebview_macos/LICENSE` | Vendored package's upstream metadata |
| dart_tui | MIT, including its stated Bubble Tea attribution; `vendor/dart_tui/LICENSE` | Vendored package's upstream metadata |
| xterm.dart | MIT, copyright 2020 xuty; `vendor/xterm/LICENSE` | https://github.com/TerminalStudio/xterm.dart/blob/master/LICENSE |

The xterm license was restored from its official upstream source because the
baseline vendor directory omitted that file. The iOS WasmRun.xcframework fetched
by build scripts is a separate compiled artifact: retain its included notices
and inspect its Rust/runtime dependency notices with the exact release used.
The interpreter backend does not grant unrestricted native code execution.

## Bundled WASI commands

`flutter_app/assets/wasm/ATTRIBUTION.md` identifies upstream sources, versions
and build notes. Retain that attribution and every adjacent `LICENSE.*` file
with distributed assets. These names refer to the actual bundled builds (for
example, coreutils is uutils), not similarly named system GNU binaries.

| Bundled component | Retained notice |
| --- | --- |
| uutils coreutils | MIT; `LICENSE.coreutils` |
| uutils findutils | MIT; `LICENSE.findutils` |
| ripgrep | MIT notice selected by the upstream attribution; `LICENSE.rg`, `LICENSE.rg.mit` |
| sed, awk | MIT; `LICENSE.sed`, `LICENSE.awk` |
| repository tar, gzip and zip helpers | MIT; `LICENSE.tar`, `LICENSE.gzip`, `LICENSE.zip` |
| CPython and packaged Python standard library | PSF/Python license history and included notices; `LICENSE.python` |
| QuickJS | MIT; `LICENSE.quickjs` |
| Lua | MIT; `LICENSE.lua` |

SQLite, WebAssembly toolchains, compression libraries and other linked
dependencies must be checked against their actual included build sources and
native artifact notices; the table above is not a binary dependency audit.

## Fonts and Flutter dependencies

- Inter: SIL Open Font License 1.1, retained at
  `flutter_app/assets/fonts/Inter-LICENSE.txt` and the test-font notice.
- JetBrains Mono: SIL Open Font License 1.1, retained at
  `flutter_app/assets/fonts/JetBrainsMono-LICENSE.txt`; restored from
  https://github.com/JetBrains/JetBrainsMono/blob/master/OFL.txt.
- Pub packages retain their individual licenses through resolved dependencies.
  Flutter generates the runtime license registry for bundled packages; the
  product About interface must expose these license notices in the shipped app.
  Keep `flutter_app/pubspec.lock` and root `pubspec.lock` as the resolution record.

PocketForge's new starter game is product code, rather than copied game artwork
or a third-party game. Any later imported sprites, music, fonts or generated
project templates need their own source/license record.
