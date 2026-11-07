# Install the native iPad build from Windows

Checked November 7, 2026. This is a documented signing/install route, **not a report that PocketForge has been signed or tested on your iPad**. A successful Mac CI build will produce `PocketForge-unsigned.ipa`; tapping that file in Files does not install it.

You do not need to own a Mac for this route. CI performs the Apple build; your Windows PC signs the result for your own iPad. Sideloadly supports iPads and free Apple accounts. [Official Sideloadly site](https://sideloadly.io/).

## Direct route: Sideloadly

1. Download the successful CI run's artifact on Windows. Extract the artifact ZIP and locate **`PocketForge-unsigned.ipa`**. Keep the IPA intact.
2. Get the current **[official Sideloadly installer for 64-bit Windows](https://sideloadly.io/SideloadlySetup64.exe)**, linked from [sideloadly.io](https://sideloadly.io/). If **Apple Devices** is already installed, keep that setup and try device detection before adding more Apple software. This is a minimal first attempt; Sideloadly does not explicitly document Apple Devices as a supported substitute for its listed prerequisites.
3. Connect the iPad by USB, unlock it, and accept **Trust This Computer**. If Apple Devices is present, confirm it can see the iPad, then check Sideloadly's device list. Pairing does not require enabling media or cloud synchronization. [Apple's trust/pairing guidance](https://support.apple.com/en-us/109054), [Sideloadly device-detection guidance](https://sideloadly.io/faq).
4. Select the iPad in Sideloadly, load the IPA, and follow its Apple-account sign-in/installation flow. Enter your own credentials and any verification code **in the signing tool locally**, not in this chat. For a free account, follow its normal Apple login and two-factor verification; the FAQ's app-specific-password option applies only to particular paid-account configurations. [Official installation outline](https://sideloadly.io/#how-it-works), [sign-in FAQ](https://sideloadly.io/faq).
5. If requested, trust the developer under **Settings → General → VPN & Device Management**, and enable **Settings → Privacy & Security → Developer Mode**. Follow the iPad's confirmation/restart prompts. [Sideloadly device guidance](https://sideloadly.io/faq), [Apple Developer Mode documentation](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
6. Open PocketForge from its Home Screen icon. Test the included game first; then enter your DeepSeek key inside PocketForge's settings.

No software installation, Apple-account sign-in, certificate creation, or device pairing has been performed by this project on your behalf.

## If Sideloadly reports missing Apple components

The official documentation currently has a mismatch: the homepage's **Before you install** section still lists web/non-Microsoft-Store **iTunes and iCloud**, while its newer changelog says **v0.71.0 adds Fake Anisette on Windows**, with iTunes Anisette taking priority, and **v0.60.0 supports two-factor authentication without iTunes on Windows**. Authentication support alone does not prove that an existing Apple Devices installation supplies every library Sideloadly needs. [Official prerequisite notice](https://sideloadly.io/), [official changelog](https://sideloadly.io/changelog).

Try the current version's available authentication setup first. If it reports a missing Apple component or cannot detect the paired iPad, use the prerequisite links on the official homepage and the exact diagnostic to choose the next step. The links checked for this guide are [web iTunes 64-bit](https://www.apple.com/itunes/download/win64) and [Apple's web iCloud installer](https://updates.cdn-apple.com/2020/windows/001-39935-20200911-1A70AA56-F448-11EA-8CC0-99D41950005E/iCloudSetup.exe). These are fallback components, not a claim that both are necessary on every Windows 11 setup.

Do not remove a working Apple Devices installation merely to follow older iTunes instructions. The reviewed Sideloadly instructions do not require turning on iCloud Photos, Drive, Passwords, cloud backups, or library syncing. No such settings changes are part of this installation route.

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
