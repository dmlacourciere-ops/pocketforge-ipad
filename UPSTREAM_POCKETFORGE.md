# PocketForge upstream record

PocketForge is an independent product entrypoint built on Flutter Agent Harness
(Fa), not an upstream Fa release or an OpenCode port.

- Source: https://github.com/IstiN/flutter_agent_harness
- Baseline commit: `cff76fc1d9248cace976db1fb6d6b8a5d9f6ad73`
- Baseline license: MIT, copyright (c) 2026 IstiN. See [LICENSE](LICENSE).
- Product entrypoint: `flutter_app/lib/main_pocketforge.dart`.
- Product runtime/UI: `flutter_app/lib/pocketforge/`.
- Agent instructions: `flutter_app/prompts/pocketforge_game.md`; generated Dart
  comes from `scripts/gen_prompts.dart`.
- Product assets: `flutter_app/assets/pocketforge/`.
- Original license headers and bundled dependency notices are retained.

The fork reuses Fa's provider adapter, agent loop, tool registry, filesystem
contracts, host wiring, WASI runtime integration and JSONL session repository.
PocketForge adds an isolated game project, a dedicated browser preview and test
tools, bounded runs, independent settings and an iPad-oriented interface.

The model API runs remotely. Project files, the agent tool loop and the game
preview run on the current device. The browser build uses the portable shell;
the native iOS build attempts the interpreter-backed WASI shell and reports its
actual fallback. Native iOS compilation, signing, WebKit behavior and installation
need an Apple build environment and physical-device validation.

No upstream signing credentials, deployment ownership, release automation or
published package identity is granted by this source checkout. Product build
instructions must use a separate signing identity and bundle identifier.

See [THIRD_PARTY_NOTICES_POCKETFORGE.md](THIRD_PARTY_NOTICES_POCKETFORGE.md) for
the source and bundled-artifact notice ledger.
