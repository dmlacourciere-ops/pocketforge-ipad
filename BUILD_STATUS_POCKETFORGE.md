# PocketForge build status

Updated November 7, 2026. This records the Fa-based implementation, separate from the earlier Swift Playground prototype.

**Current delivery: source plus a compiled browser build. No verified signed iPad installer or hardware-tested native build is available.**

## Verification completed

| Area | Result | Evidence boundary |
| --- | --- | --- |
| Product Dart/Flutter analysis | Passed scoped analysis | Covers the product entrypoint/runtime/UI and product tests; not every unrelated upstream module |
| Product UI behavior | 6 tests passed | Input/send, Stop, dirty-edit protection, preview focus, secure-key field behavior, and clean-file refresh after agent edits |
| Product visual snapshots | 5 passed on comparison | Full frames at desktop, phone, and iPad portrait sizes; real bundled fonts; every new snapshot visually inspected |
| Product golden coverage/localization guards | Passed | New widget files registered; English-only product copy uses the repository's explicit exemption |
| Session/storage and browser unit tests | Targeted tests passed | Fake provider/backend checks exercise local contracts; no paid model calls or iPad execution implied |
| Browser release build | Compiled and booted | Actual Flutter web entrypoint loaded in a desktop browser |
| Compiled browser tool flow | Retest pending | The interactive end-to-end run found a JavaScript structured-clone reply conversion bug. The bridge was corrected; the complete flow must pass the follow-up run before it is marked verified |

Golden previews use an explicit fake browser backend, so they validate the real Flutter shell and result/status widgets without claiming that a native WebKit engine ran. Browser unit tests, JavaScript runtime tests, and a compiled browser interaction run provide different evidence and must be reported separately.

## Full upstream visual suite

The full inherited Fa golden suite was run on Windows with Flutter **3.47.9** and concurrency 2:

**18 passed, 9 skipped, 234 failed.** The failing assertions were golden pixel comparisons. Existing upstream snapshots were not regenerated.

The upstream helper documents canonical **macOS / Flutter 3.47.4** snapshots. An inspected unchanged baseline/render pair showed very similar layout with text/glyph placement differences, consistent with a host/SDK mismatch. That observation does not prove the cause of every failure. The full upstream suite remains red on this host; the scoped PocketForge comparison suite passes.

Full log in the development workspace: `test-results/pocketforge-full-goldens.log` outside this fork. Generated comparison images are under `flutter_app/test/golden/failures/`; they are diagnostics, not product assets.

## Native iOS verification still required

[PocketForge unsigned iOS verification](.github/workflows/pocketforge-verify.yml) is prepared as a manual workflow. It has **not yet produced a successful iOS build**. Its planned unsigned IPA requires a separate signing step and is not directly installable.

The remaining checks include:

1. Compile the complete iOS app against Apple's SDK, including the statically linked interpreter and retained FFI exports.
2. Sign/install on an actual iPad, launch, rotate, edit files, and run the starter game.
3. Verify native Keychain save/reload/removal, local project/session persistence, and checkpoint restoration.
4. Verify the reported native WASI runtime or fallback, native WebKit input/tests/screenshots, cancellation, and recovery.
5. Test an actual DeepSeek request with an authorized account, including tool execution and provider errors. Development verification has used fake model responses rather than spending user API credits.

Successful compilation would establish a build result. It would not establish installation, runtime behavior, native screenshot operation, live model compatibility, or App Review acceptance.

## Product scope

The implemented route is an on-device game workspace with remote model inference. It does not supply arbitrary native Xcode builds, automatic native deployment, unrestricted desktop processes, outside-Safari control, or the complete OpenCode plugin ecosystem. Web screenshot capture explicitly reports unsupported; native screenshot support remains hardware-unverified.

For usage, source commands, and retained MIT attribution to IstiN, see [README_POCKETFORGE.md](README_POCKETFORGE.md).
