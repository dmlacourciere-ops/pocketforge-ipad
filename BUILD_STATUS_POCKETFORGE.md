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
| Session/storage and browser unit tests | 9 session/storage + 8 browser tests passed | A real disk restart test verifies persistence with the interpreter unavailable; with 6 UI and 5 golden tests, the scoped Flutter suite totals **28 passed, 1 skipped**. Windows lacks symlink-creation privileges; that check runs on macOS |
| JavaScript/game runtime checks | 6 passed | 3 actual desktop WebKit checks plus 3 simulation checks; neither runs iOS WebKit |
| iOS build-preparer checks | 5 passed | Includes quoted SDK-specific signing identities and explicit development preparation; does not compile or sign the iOS app |
| Native iPad integration test | Authored; analyzer passed; Apple execution pending | Boots production main, requires WASI and Keychain, runs rg.wasm, actual WebKit collision failure/repair, Stop/reload, PNG capture, and session recreation |
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

The private development repository is [dmlacourciere-ops/pocketforge-ipad](https://github.com/dmlacourciere-ops/pocketforge-ipad). Both Mac and Linux control jobs were rejected before starting. On November 7 the signed-in GitHub run page identified an account billing/admission block. This is independent of the app source and runner label; workflow validation with actionlint passed. Account resolution or an explicitly authorized source-publication decision is needed before cloud compilation can proceed. No Apple compilation result is claimed.

The native workflow now includes an actual iPad simulator test before packaging. Its preview PNG and JSON report become build artifacts only after successful native execution. Native source assets are bundled, and project/session storage uses the app's disk independently of the optional WASI interpreter. Normal native use needs no Windows server. The user selected free Apple account installation with weekly Windows signing renewal; no Apple credentials, certificate creation or installation have been performed.

An optional private Codemagic build configuration is prepared in `codemagic.yaml`, with a personal M2 runner and 75-minute limit. YAML, Bash and embedded Python syntax checks passed. No Codemagic account or repository grant exists yet; that requires the user's approval. See [the private build setup](tools/pocketforge/CODEMAGIC_PRIVATE_BUILD.md). It produces an unsigned IPA only after native verification; signing is still a separate Windows/Apple-account step.

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
