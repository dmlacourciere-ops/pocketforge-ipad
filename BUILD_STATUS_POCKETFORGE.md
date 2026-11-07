# PocketForge build status

Updated November 7, 2026. This records the Fa-based implementation, separate from the earlier Swift Playground prototype.

**Current delivery: a compiled unsigned iPad IPA, source, and a compiled browser build. Native checks passed on an iPad mini (A17 Pro) simulator. Signing, installation, and physical-iPad verification remain pending.**

## Verification completed

| Area | Result | Evidence boundary |
| --- | --- | --- |
| Product Dart/Flutter analysis | Passed scoped analysis | Covers the product entrypoint/runtime/UI and product tests; not every unrelated upstream module |
| Product UI behavior | 6 tests passed | Input/send, Stop, dirty-edit protection, preview focus, secure-key field behavior, and clean-file refresh after agent edits |
| Product visual snapshots | 5 passed on Windows; 5 comparisons differed on Mac | Full frames at desktop, phone, and iPad portrait sizes; real bundled fonts; every new snapshot visually inspected; Mac differences retained as diagnostics |
| Product golden coverage/localization guards | Passed | New widget files registered; English-only product copy uses the repository's explicit exemption |
| Session/storage and browser unit tests | 9 session/storage + 8 browser tests passed | A real disk restart test verifies persistence with the interpreter unavailable; with 6 UI and 5 golden tests, the scoped Flutter suite totals **28 passed, 1 skipped**. Windows lacks symlink-creation privileges; that check runs on macOS |
| JavaScript/game runtime checks | 6 passed | 3 actual desktop WebKit checks plus 3 simulation checks; neither runs iOS WebKit |
| iOS build-preparer checks | 5 passed | Includes quoted SDK-specific signing identities and explicit development preparation; does not compile or sign the iOS app |
| Native iPad integration test | Passed on iPad mini (A17 Pro) simulator | Production main, WASI stdout/stderr callbacks and pipeline output, actual WebKit game failure/repair, Stop/reload, PNG capture, and project/checkpoint metadata after session recreation; no model requests |
| Native output regressions | Passed on Mac | Three production Rust capture/replay tests and one focused Dart queued-output test |
| iOS release package | Compiled and packaged | Unsigned `com.pocketforge.ipad` IPA; device and simulator interpreter libraries source-built; required Wasm and native HTTP FFI exports retained |
| Browser release build | Compiled and booted | Actual Flutter web entrypoint loaded in a desktop browser |
| Compiled browser tool flow | Passed in Chrome and desktop WebKit | Seven controlled-provider requests per engine drove the compiled app through a failing game assertion, repair, and passing rerun; portrait layout, project persistence across reload, session-only key removal, and no browser errors were verified |

Golden previews use an explicit fake browser backend, so they validate the real Flutter shell and result/status widgets without claiming that a native WebKit engine ran. Browser unit tests, JavaScript runtime tests, and a compiled browser interaction run provide different evidence and must be reported separately.

The compiled browser run exposed two bridge problems: JavaScript structured-clone replies needed conversion into Dart values, and message-source checks needed the raw JavaScript Window identity. Both were corrected before the successful rerun. The end-to-end provider was controlled test input, **not a live DeepSeek model**, so this establishes tool/UI integration rather than model quality or account compatibility.

## Full upstream visual suite

The full inherited Fa golden suite was run on Windows with Flutter **3.47.9** and concurrency 2:

**18 passed, 9 skipped, 234 failed.** The failing assertions were golden pixel comparisons. Existing upstream snapshots were not regenerated.

The upstream helper documents canonical **macOS / Flutter 3.47.4** snapshots. An inspected unchanged baseline/render pair showed very similar layout with text/glyph placement differences, consistent with a host/SDK mismatch. That observation does not prove the cause of every failure. The full upstream suite remains red on this host; the scoped PocketForge comparison suite passes.

Full log in the development workspace: `test-results/pocketforge-full-goldens.log` outside this fork. Generated comparison images are under `flutter_app/test/golden/failures/`; they are diagnostics, not product assets.

## Native iOS build and remaining verification

[PocketForge unsigned iOS verification](.github/workflows/pocketforge-verify.yml) is prepared as a manual workflow. **Codemagic build 2 produced `PocketForge-unsigned.ipa` after passing the native simulator test.** This unsigned IPA requires a separate signing step and is not directly installable by tapping it.

The development repository is [dmlacourciere-ops/pocketforge-ipad](https://github.com/dmlacourciere-ops/pocketforge-ipad). The owner explicitly authorized making only this repository public. GitHub still rejected the public control job with an account-wide billing lock. Workflow validation with actionlint passed; compilation now uses the separately authorized Codemagic route.

The native workflow runs an actual iPad simulator test before packaging. Build 2 includes its preview PNG and JSON report as artifacts. Native source assets are bundled, and project/session storage uses the app's disk independently of the optional WASI interpreter. Normal native use needs no Windows server. The selected installation route uses a free Apple account with weekly Windows signing renewal; CI does not receive Apple credentials or perform signing.

The owner authorized Codemagic's free personal builder. `codemagic.yaml` uses a personal M2 runner and 75-minute limit, with no publishing or paid billing enabled. Codemagic reads the public repository through its URL; no GitHub App or private-repository token was granted. See [the build setup](tools/pocketforge/CODEMAGIC_PRIVATE_BUILD.md).

[Codemagic build 2](https://codemagic.io/app/6aef36b344beb3179939831d/build/6aef43da24e1ec237557344e) used source `0125d16231b6be9d206379c05d34994c6820b228`, Flutter 3.47.9, Xcode 26.6, and Rust 1.91.1. It passed the scoped analyzer, 24 app tests, 5 preparer tests, 3 Rust output tests, the focused Dart output regression, and the native integration test. Both ARM64 Apple interpreter targets compiled from source. Release compilation and the FFI-export checks passed before packaging. The app build number is 3.

The native report records matching stdout/stderr callbacks, successful pipeline output, passing baseline collision checks, detection of an injected shield-consumption bug, and passing checks after restoring the source. It also records cancellation/reload recovery, project persistence and checkpoint metadata after reopening, Keychain availability, and a **282,427-byte WebKit PNG**. These are simulator observations. They do not establish a live model's ability to find the repair: the native test writes the deliberate fault and repair directly, and makes **zero model requests**.

The IPA's build checksum is `e60c0058c447931833abbb9e3ff84de98b8ac6cd5027e9c012609e9018cd7d5f`. The build artifacts include `PocketForge-unsigned.ipa.sha256`, `native-smoke-report.json`, `native-smoke-preview.png`, source provenance, and verification logs. Five Windows-captured golden comparisons differed on Mac and remain retained diagnostics, not a claimed pass.

[Build 1](https://codemagic.io/app/6aef36b344beb3179939831d/build/6aef36da24e1ec2375573076) had caught a native command-output bug before game tests or packaging. Build 2 includes the buffered/live stream repair and verifies native stdout, stderr, and pipeline delivery.

The remaining checks include:

1. Sign/install on an actual iPad, launch, rotate, edit files, and run the starter game.
2. Verify Keychain save/reload/removal, local project/session persistence, and checkpoint restoration on that physical device.
3. Repeat native WASI, WebKit input/tests/screenshots, cancellation, and recovery checks on physical hardware.
4. Test an actual DeepSeek request with an authorized account, including tool execution and provider errors. Development verification has used controlled model responses rather than spending user API credits.

The successful build and simulator run establish the recorded compilation and runtime checks. They do not establish physical installation, hardware behavior, live model compatibility, or App Review acceptance.

## Product scope

The implemented route is an on-device game workspace with remote model inference. It does not supply arbitrary native Xcode builds, automatic native deployment, unrestricted desktop processes, outside-Safari control, or the complete OpenCode plugin ecosystem. Web screenshot capture explicitly reports unsupported; native screenshot support remains hardware-unverified.

For usage, source commands, and retained MIT attribution to IstiN, see [README_POCKETFORGE.md](README_POCKETFORGE.md).
