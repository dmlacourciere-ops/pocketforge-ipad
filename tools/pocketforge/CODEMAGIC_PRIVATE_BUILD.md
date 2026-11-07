# Optional private Mac build with Codemagic

Prepared November 7, 2026. These files are a fallback configuration for review. No Codemagic account, GitHub integration, build, or Apple signing operation has been performed. Bash/YAML checks do not establish that the Apple build succeeds.

Codemagic advertises **500 free macOS M2 minutes per month for a personal account**, one parallel build, and 30-day artifact retention. Teams do not receive that allowance. Use the personal free account with billing disabled; this workflow selects `mac_mini_m2` and stops after 75 minutes. Check your account's remaining allowance before starting it. [Official pricing](https://codemagic.io/pricing/), [personal plan details](https://docs.codemagic.io/billing/pricing/).

## Connect this private repository

1. Sign up at [codemagic.io/signup](https://codemagic.io/signup) using GitHub or email. GitHub signup authenticates your identity; repository access is a separate installation. Select **Personal account**, rather than creating a Team. Leave billing disabled. Paid billing enrollment is a separate action that requests card details. [Signup](https://docs.codemagic.io/getting-started/signup/), [billing enrollment](https://docs.codemagic.io/billing/billing/).
2. Choose **Add application → GitHub → Authorize integration**, then **Install GitHub App**. This is the approval needed to share private source with another build provider. Install **Codemagic CI/CD** under the GitHub account that owns the repository, `dmlacourciere-ops`.
3. Choose **Only selected repositories** and select **pocketforge-ipad**. Review the displayed permission list and approve only if you want Codemagic to access that repository. The repository can remain private. A personal GitHub token, access to all repositories, Apple credentials, and provider API keys are not needed for this unsigned build. [Official GitHub/private-repository setup](https://docs.codemagic.io/getting-started/adding-apps/).
4. Select the repository and **Flutter** as the project type, then finish adding the application. Use the `codemagic.yaml` from the repository root. Its script handles the `flutter_app` subdirectory.
5. Select the source branch and manually start **PocketForge unsigned iOS and native iPad simulator checks** (`pocketforge-ios-unsigned`). This configuration has no push/PR/scheduled trigger or publishing section. Adding it to a repository alone does not start a build. [YAML configuration and manual build setup](https://docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/).

Do not add a DeepSeek/OpenAI key, Apple account, signing certificate, App Store Connect integration, or payment method for this workflow. A successful signup/free allowance is subject to Codemagic's actual account checks; the current documented free plan is not a guarantee that every account is admitted immediately.

## What the build attempts

The helper `tools/pocketforge/verify_ios_codemagic.sh` records its source and Xcode versions, runs the existing iOS-preparation checks, builds **wasmi/WASI from the vendored Rust source for device and ARM64 simulator**, runs scoped analysis/tests, and preserves golden-comparison diagnostics. It then runs `integration_test/pocketforge_native_test.dart` on an available iPad simulator with `--no-uninstall` so the native report and screenshot can be collected. Missing native prerequisites or failed native assertions stop the build.

Only after the native smoke check passes does it attempt an unsigned iOS release, check retained FFI exports and the independent bundle identity, and package `artifacts/PocketForge-unsigned.ipa` plus its checksum. The Rust helper uses the pinned compiler; if `rustup` is missing, the verification helper downloads its [official bootstrap](https://rust-lang.org/tools/install/) on the disposable build worker. It never falls back to a prebuilt Wasm engine.

Download the IPA, checksum, native report/screenshot, and logs from the build's **Artifacts** section. Inspect `artifacts/logs/golden-status.txt` separately: Windows-captured golden differences are retained without blocking the native result. An iPad simulator pass establishes only those simulator checks; physical iPad behavior remains unverified.

## Install on your iPad afterward

The unsigned IPA still needs signing. Follow [INSTALL_WINDOWS.md](INSTALL_WINDOWS.md) to sign and install it on your own iPad from Windows using your **own free Apple ID** in the local signing tool. Free-account signatures normally need renewal after seven days. Do not enter Apple credentials in Codemagic or chat for this route.

A green cloud build does not prove successful signing, installation, or operation on the physical iPad. Those are the final checks to perform on the downloaded artifact.
