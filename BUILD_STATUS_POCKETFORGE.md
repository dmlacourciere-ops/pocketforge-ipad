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
| Session/storage and browser unit tests | 8 session + 8 browser tests passed | Fake provider/backend checks exercise local contracts; with the 6 UI and 5 golden tests, the scoped Flutter suite totals **27 passed** |
| JavaScript/game runtime checks | 6 passed | 3 actual desktop WebKit checks plus 3 simulation checks; neither runs iOS WebKit |
| iOS build-preparer checks | 4 passed | Tests the source preparation script; does not compile the iOS app |
| Browser release build | Compiled and booted | Actual Flutter web entrypoint loaded in a desktop browser |
| Compiled browser tool flow | Passed in Chrome and desktop WebKit | Seven controlled-provider requests per engine drove the compiled app through a failing game assertion, repair, and passing rerun; portrait layout, project persistence across reload, session-only key removal, and no browser errors were verified |

Golden previews use an explicit fake browser backend, so they validate the real Flutter shell and result/status widgets without claiming that a native WebKit engine ran. Browser unit tests, JavaScript runtime tests, and a compiled browser interaction run provide different evidence and must be reported separately.

The compiled browser run exposed two bridge problems: JavaScript structured-clone replies needed conversion into Dart values, and message-source checks needed the raw JavaScript Window identity. Both were corrected before the successful rerun. The end-to-end provider was controlled test input, **not a live DeepSeek model**, so this establishes tool/UI integration rather than model quality or account compatibility.

## Full upstream visual suite

The full inherited Fa golden suite was run on Windows with Flutter **3.47.9** and concurrency 2:

**18 passed, 9 skipped, 234 failed.** The failing assertions were golden pixel comparisons. Existing upstream snapshots were not regenerated.

The upstream helper documents canonical **macOS / Flutter 3.47.4** snapshots. An inspected unchanged baseline/render pair showed very similar layout with text/glyph placement differences, consistent with a host/SDK mismatch. That observation does not prove the cause of every failure. The full upstream suite remains red on this host; the scoped PocketForge comparison suite passes.

Full log in the development workspace: `test-results/pocketforge-full-goldens.log` outside this fork. Generated comparison images are under `flutter_app/test/golden/failures/`; they are diagnostics, not product assets.

## Native iOS verification still required

[PocketForge unsigned iOS verification](.github/workflows/pocketforge-verify.yml) is prepared as a manual workflow. It has **not yet produced a successful iOS build**. Its planned unsigned IPA requires a separate signing step and is not directly installable.

The private development repository is [dmlacourciere-ops/pocketforge-ipad](https://github.com/dmlacourciere-ops/pocketforge-ipad). GitHub reported `startup_failure` before creating any jobs for the [native workflow](https://github.com/dmlacourciere-ops/pocketforge-ipad/actions/runs/42341866801). A separate [minimal Mac host diagnostic](https://github.com/dmlacourciere-ops/pocketforge-ipad/actions/runs/42342461554), with no checkout or third-party actions, also reported `startup_failure`. The REST API supplied no explanatory annotation or job log. Workflow validation with actionlint passed. The detailed GitHub page error is needed to diagnose this; no Apple compilation result is claimed.

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
