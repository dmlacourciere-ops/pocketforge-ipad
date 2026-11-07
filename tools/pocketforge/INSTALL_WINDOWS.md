# Install the native iPad build from Windows

Checked November 7, 2026. This is a documented signing/install route, **not a report that PocketForge has been signed or tested on your iPad**. The Mac CI build produces `PocketForge-unsigned.ipa`; tapping that file in Files does not install it.

You do not need to own a Mac for this route. CI performs the Apple build; your Windows PC signs the result for your own iPad. Sideloadly supports iPads and free Apple accounts. [Official Sideloadly site](https://sideloadly.io/).

## Direct route: Sideloadly

1. Download the successful CI run's artifact on Windows. Extract the artifact ZIP and locate **`PocketForge-unsigned.ipa`**. Keep the IPA intact.
2. Get Sideloadly from **[sideloadly.io](https://sideloadly.io/)**. Its current Windows instructions require Apple's **web/non-Microsoft-Store iTunes and iCloud**; use the prerequisite links on that official page. Review those instructions before changing an existing Apple software installation.
3. Connect the iPad by USB, unlock it, and accept **Trust This Computer**. Confirm the iPad appears in iTunes/Sideloadly. [Official device-detection guidance](https://sideloadly.io/faq).
4. Select the iPad in Sideloadly, load the IPA, and follow its Apple-account sign-in/installation flow. Enter your own credentials and any verification code **in the signing tool locally**, not in this chat. The official flow is download → load IPA → Apple ID → sideload. [Official installation outline](https://sideloadly.io/#how-it-works).
5. If requested, trust the developer under **Settings → General → VPN & Device Management**, and enable **Settings → Privacy & Security → Developer Mode**. Follow the iPad's confirmation/restart prompts. [Sideloadly device guidance](https://sideloadly.io/faq), [Apple Developer Mode documentation](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
6. Open PocketForge from its Home Screen icon. Test the included game first; then enter your DeepSeek key inside PocketForge's settings.

No software installation, Apple-account sign-in, certificate creation, or device pairing has been performed by this project on your behalf.

## Free-account renewal

With a free account, the signing normally lasts **7 days**, with **3 sideloaded apps installed at once**. Keep the same Apple account and bundle-ID choice when replacing/refreshing PocketForge; overwriting preserves local app data according to Sideloadly's guidance. Back up important projects before removing the app. Its optional auto-refresh daemon needs the Windows PC running and the iPad reachable by USB or configured Wi-Fi. These limits concern signing; the installed harness does not need a Windows agent server for normal use. [Official Sideloadly FAQ](https://sideloadly.io/faq).

Apple also limits free-account App IDs; avoid generating a different bundle ID for every update. AltStore documents **10 App IDs at a time**, each expiring after a week. [Official App ID explanation](https://faq.altstore.io/altstore-classic/app-ids).

## Alternative: AltStore Classic + AltServer

[AltStore's official Windows guide](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows) documents installing AltServer on Windows, pairing the iPad, signing in, and installing AltStore Classic. It also specifies non-Store Apple prerequisites and Developer Mode. Once installed, AltStore supports importing downloaded IPA files. [Official AltStore feature description](https://faq.altstore.io/about-us/press-kit).

AltStore's apps also expire after seven days; refresh them while AltServer is available over USB or the same Wi-Fi network. The Windows computer must remain available for renewal. [AltStore app management](https://faq.altstore.io/altstore-classic/your-altstore), [AltServer requirements](https://faq.altstore.io/altstore-classic/altserver).

## What installation does—and does not—change

The PocketForge preparation script removes the upstream HealthKit/HomeKit entitlements, Live Activity extension, author signing profiles, unrelated native-channel registration, and telemetry upload phase. It retains the app's own Keychain channel. The WASM engine is source-built with the **wasmi interpreter**; this build is intended to work without enabling an external JIT service. These are implementation choices, pending actual device validation.

Sideloading does not remove iPadOS's app sandbox or grant general process execution or control over other apps. [Apple runtime security](https://support.apple.com/guide/security/security-of-runtime-process-sec15bfe098e/web).

An install failure, a launch crash, or missing native FFI symbols still needs its exact diagnostic. Successful signing alone does not prove that the app runs correctly. No paid developer membership, TestFlight setup, or publishing workflow has been configured here.
