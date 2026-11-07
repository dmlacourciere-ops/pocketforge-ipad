# PocketForge

PocketForge is an experimental game-building app based on [Flutter Agent Harness (Fa)](https://github.com/IstiN/flutter_agent_harness). The agent loop, project files, sandbox tools, and game preview run on the current device. **DeepSeek supplies the model through its remote API.**

This is a separate product entrypoint, not an OpenCode port or an upstream Fa release. The upstream README is retained in the build distribution. Current verification and unfinished work are recorded in [BUILD_STATUS_POCKETFORGE.md](BUILD_STATUS_POCKETFORGE.md). The development repository is [pocketforge-ipad](https://github.com/dmlacourciere-ops/pocketforge-ipad) (private).

## What it does

- Edits a local HTML/CSS/JavaScript game project using Fa's agent and tool infrastructure.
- Provides a file editor, streamed conversation, actual tool activity, Stop, saved sessions, and project checkpoints.
- Runs the project in an isolated preview. The agent can inspect the DOM and console, dispatch synthetic clicks/keys/pointers, evaluate game state, and run explicit JavaScript assertions.
- Shows the checks returned by a real `game_test` call. It does not display a successful test badge before a test has run.
- Includes a playable starter game, **Neon Drift**.
- Supports an editable DeepSeek model ID and request limit. This product entrypoint currently wires DeepSeek; it does not expose Fa's full provider/settings catalog.

On native iOS, the intended shell is the interpreter-backed WASI sandbox. If initialization falls back to the portable Dart sandbox, the interface reports the runtime actually selected. The browser build uses the portable sandbox. Neither is an unrestricted desktop terminal.

## Use the app

1. Open **Preview** or press the top Run button to try the starter game without a model key.
2. Open **Model settings**, enter a DeepSeek API key, choose a compatible model ID, and save. The default ID is `deepseek-flash`.
3. Describe the change in **Agent**. The agent can edit files and use the preview tools to check its work. Tool activity and error messages report actual results.
4. Use **Stop** in the header or composer to cancel the run. Review files before continuing an interrupted task.
5. Open **Files** to inspect or edit source. Save edits before changing panels or starting an agent run; the UI asks before discarding unsaved changes.
6. Use the project menu to save/restore a checkpoint or start a new conversation. A new conversation keeps the project files. Checkpoint restoration changes files separately from conversation history.

Each run has request, tool, context, and time limits. The default request limit is 20; Settings permits 1–40. A run can make several billable provider requests. Keep the native app foregrounded while it works.

## Data and credentials

Prompts, selected file contents, and tool results go to DeepSeek. Model inference is not on-device or offline. No provider key is bundled.

Where native Keychain is available, the key is stored there. Where secure storage is unavailable, the key remains in session memory; the settings screen says so. Keys are not saved to browser local storage, generated game source, or plaintext settings. Generated preview code has no credential or general filesystem bridge.

Projects, sessions, and checkpoints use Fa's platform storage. The browser's project state uses IndexedDB; its API key does not. File limits are 500 files, 512 KiB per file, and 20 MiB per project. Eight checkpoints are retained.

## Run from source

The checked development toolchain is Flutter **3.47.9**. From this checkout:

```sh
cd flutter_app
flutter pub get
flutter run -d chrome --target lib/main_pocketforge.dart
```

For a browser release build:

```sh
flutter build web --release --target lib/main_pocketforge.dart
```

Use an empty `flutter_app/.env` when the upstream asset declaration requires that file; enter credentials in Settings. Do not put a real API key in a bundled `.env`. The PocketForge entrypoint does not require the upstream Fa onboarding, Firebase account, remote relay, or published Fa identity.

## iPad builds and installation

The native Flutter app is a conventional iOS project. Its build route does not require Swift Playground. Building it still requires an Apple SDK/Mac build environment, and installation on a physical iPad requires a separate authorized signing/provisioning or sideloading workflow.

[The manual verification workflow](.github/workflows/pocketforge-verify.yml) prepares an independent bundle ID, builds the Wasm interpreter from vendored Rust source, runs scoped checks, and attempts an **unsigned** iOS release build. GitHub rejected startup before any job ran, including a minimal Mac host diagnostic; the detailed page error is still needed. It does not publish, sign, install, or upload to TestFlight. Any resulting unsigned IPA is a build artifact, not a tap-to-install app. See the [Windows signing route](tools/pocketforge/INSTALL_WINDOWS.md) and the separate [browser test route](tools/pocketforge/TRY_BROWSER_WINDOWS.md).

## Limits of this version

- The product focuses on local browser games and apps. It cannot build/sign arbitrary Xcode projects or automatically install generated native iOS apps.
- Preview tools operate on the embedded local game. They do not control Safari, other apps, or an unrestricted external browser.
- The preview bundles local assets and restricts remote resources, forms, and popups. Use browser-ready source without an npm build step; not every browser API works in the isolated preview.
- Screenshot capture is implemented for the native preview and remains unverified on iPad hardware. The web build explicitly reports screenshots as unsupported. A model must accept image input before screenshot capture can support visual reasoning.
- Live DeepSeek/account behavior, native Keychain persistence, native WASI startup, iOS WebKit, signing, and device behavior still require their own verification. A passing mock-provider test is not a live API test.

## Checks and source map

```sh
cd flutter_app
flutter analyze --no-pub lib/main_pocketforge.dart lib/pocketforge test/pocketforge
flutter test --no-pub test/pocketforge
flutter test --no-pub test/golden/pocketforge_golden_test.dart
```

The product entrypoint is `flutter_app/lib/main_pocketforge.dart`; runtime, storage, browser tools, and UI are under `flutter_app/lib/pocketforge/`. Agent instructions live in `flutter_app/prompts/pocketforge_game.md` and are generated through the repository's prompt generator.

Independent JavaScript checks are under `tools/pocketforge`: run `npm ci`, `npx playwright install webkit`, then `npm test`. For the complete controlled-provider UI check, serve the compiled web bundle on `127.0.0.1:8768`, then run `npm run test:web`; set `POCKETFORGE_BROWSER=webkit` for portrait WebKit. Chrome is the default and requires installed Google Chrome. These checks use fixture model replies and do not spend API credits.

Current scoped checks pass: **27 Flutter tests**, **6 JavaScript/WebKit tests**, and **4 iOS-preparer tests**. A compiled Chrome end-to-end run completed seven controlled-provider requests, exercised a failing game assertion followed by a passing repair, and reported no browser errors. Those provider responses were deterministic test input, not live AI output. Native iOS and physical-iPad verification remain pending.

## License and attribution

The Fa baseline is **MIT licensed, copyright (c) 2026 IstiN**. The original [LICENSE](LICENSE), source headers, and dependency notices are retained. See [UPSTREAM_POCKETFORGE.md](UPSTREAM_POCKETFORGE.md) for the pinned source revision and [THIRD_PARTY_NOTICES_POCKETFORGE.md](THIRD_PARTY_NOTICES_POCKETFORGE.md) for bundled components and font notices. Settings → **Open source notices** exposes the app's license registry.

Open-source permission does not grant the upstream project's signing identities, store accounts, or release ownership.
