#!/usr/bin/env python3
"""Prepare a disposable checkout for PocketForge's unsigned iOS build.

This does not sign, upload, publish, install, or contact Apple. Invoke it
explicitly in the CI checkout; the upstream iOS files remain unchanged until then.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import plistlib
import re


_PBX_OBJECT = re.compile(
    r"(?m)^\t\t(?P<id>[A-F0-9]{24}) /\* (?P<label>[^\n]+?) \*/ = \{"
    r"(?P<body>[^\n]*\};\n|\n[\s\S]*?^\t\t\};\n)"
)


def _plist(data: dict) -> bytes:
    return plistlib.dumps(data, sort_keys=False)


def _project(text: str, bundle_id: str, team: str) -> str:
    """Remove the inactive upstream extension and telemetry build operations.

    Match complete top-level PBX objects; quoted shell-script braces never
    participate in this parse. Keep the Podfile and every linking flag intact.
    """
    text = text.replace("\r\n", "\n")
    objects = list(_PBX_OBJECT.finditer(text))
    extension_ids = {
        item["id"] for item in objects
        if item["label"] == "FaLiveActivity" and "isa = PBXNativeTarget;" in item["body"]
    }
    dropped = set(extension_ids)
    for item in objects:
        label, body = item["label"], item["body"]
        if label == "Embed App Extensions" or label.startswith("Crashlytics:"):
            dropped.add(item["id"])
        if "GoogleService-Info.plist" in label or "FaLiveActivity.appex" in label:
            dropped.add(item["id"])
        if "isa = PBXTargetDependency;" in body and any(
            re.search(rf"\btarget = {target}(?: /\*[^\n]*?\*/)?;", body) for target in extension_ids
        ):
            dropped.add(item["id"])
        if "isa = PBXContainerItemProxy;" in body and any(
            re.search(rf"\bremoteGlobalIDString = {target}(?: /\*[^\n]*?\*/)?;", body) for target in extension_ids
        ):
            dropped.add(item["id"])
    for item in reversed(objects):
        if item["id"] in dropped:
            text = text[:item.start()] + text[item.end():]
    if dropped:
        ids = "|".join(sorted(dropped))
        text = re.sub(rf"(?m)^\s*(?:{ids}) /\* [^\n]*?\*/,\s*\n", "", text)
    for target in extension_ids:
        text = re.sub(rf"(?m)^\t{{5}}{target} = \{{\n[\s\S]*?^\t{{5}}\}};\n", "", text)
    text = re.sub(r"\bdev\.fa1\.app\b", bundle_id, text)
    text = re.sub(r"(?m)(\bDEVELOPMENT_TEAM = )[^;]*;", lambda match: match[1] + f'"{team}";', text)
    text = re.sub(r"(?m)(\bCODE_SIGN_IDENTITY(?:\[[^\]]+\])? = )[^;]*;", r'\1"";', text)
    text = re.sub(r"(?m)(\bPROVISIONING_PROFILE(?:_SPECIFIER)? = )[^;]*;", r'\1"";', text)
    text = re.sub(r"(?m)(\bCODE_SIGN_STYLE = )[^;]*;", r"\1Automatic;", text)
    if "YP9HC3USZ3" in text or "Uladzimir Klyshevich" in text:
        raise ValueError("Unexpected author signing identity remains in the Xcode project.")
    return text


def _delegate(text: str, bundle_id: str) -> str:
    text = text.replace("\r\n", "\n")
    calls = re.compile(
        r"(?m)^\s*register(?P<name>\w+)Channel\(messenger: engineBridge\.applicationRegistrar\.messenger\(\)\)\s*\n"
    )
    text = calls.sub(lambda match: match[0] if match["name"] == "Keychain" else "", text)
    remaining = [match["name"] for match in calls.finditer(text)]
    if remaining != ["Keychain"] or "GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)" not in text:
        raise ValueError("AppDelegate registration shape changed; inspect it before preparing the build.")
    service = re.compile(r'(private let keychainService = ")[^"]+("\s*)')
    text, count = service.subn(lambda match: match[1] + bundle_id + ".keys" + match[2], text)
    if count != 1:
        raise ValueError("Expected exactly one native Keychain service declaration.")
    return text


def prepare_ios(repo: Path, *, bundle_id: str = "com.pocketforge.ipad", team: str = "", check: bool = False) -> list[str]:
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z][A-Za-z0-9-]*){2,}", bundle_id):
        raise ValueError("Use a reverse-DNS Apple bundle ID with at least three components.")
    if team and not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("An optional Apple team identifier must contain 10 uppercase letters/digits.")
    repo = repo.resolve(strict=True)
    ios = repo / "flutter_app/ios"
    paths = {
        "project": ios / "Runner.xcodeproj/project.pbxproj",
        "delegate": ios / "Runner/AppDelegate.swift",
        "info": ios / "Runner/Info.plist",
        "entitlements": ios / "Runner/Runner.entitlements",
    }
    for file in paths.values():
        if not file.resolve(strict=True).is_relative_to(repo) or file.is_symlink():
            raise ValueError(f"Refusing a path outside this checkout: {file}")
    original = {name: file.read_bytes() for name, file in paths.items()}
    info = plistlib.loads(original["info"])
    info["CFBundleDisplayName"] = "PocketForge"
    info["CFBundleName"] = "PocketForge"
    info["CFBundleURLTypes"] = [{
        "CFBundleURLName": bundle_id + ".oauth", "CFBundleURLSchemes": ["pocketforge"],
    }]
    for key in list(info):
        if (key.endswith("UsageDescription") or key.startswith("NSSupportsLiveActivities")
                or key == "UIBackgroundModes"):
            del info[key]
    # This product only calls HTTPS provider endpoints. It does not start the
    # upstream local-network/background/device-integration services.
    info.pop("NSAppTransportSecurity", None)
    updated = {
        "project": _project(original["project"].decode("utf-8"), bundle_id, team).encode("utf-8"),
        "delegate": _delegate(original["delegate"].decode("utf-8"), bundle_id).encode("utf-8"),
        "info": _plist(info),
        "entitlements": _plist({}),
    }
    # Keep an unused placeholder instead of distributing the author's Firebase
    # configuration; its project/resource and upload-phase references are gone.
    google = ios / "Runner/GoogleService-Info.plist"
    if google.exists():
        if google.is_symlink() or not google.resolve().is_relative_to(repo):
            raise ValueError("Refusing a linked Firebase configuration.")
        paths["google"] = google
        original["google"] = google.read_bytes()
        updated["google"] = _plist({})
    changed = [name for name in updated if original[name] != updated[name]]
    if check and changed:
        raise ValueError("Checkout is not prepared: " + ", ".join(changed))
    if not check:
        for name in changed:
            paths[name].write_bytes(updated[name])
    return [str(paths[name].relative_to(repo)).replace("\\", "/") for name in changed]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--bundle-id", default="com.pocketforge.ipad")
    parser.add_argument("--team", default="", help="Optional team for a later signing workflow; empty for unsigned CI.")
    parser.add_argument("--check", action="store_true", help="Read-only verification that preparation was already applied.")
    args = parser.parse_args()
    changed = prepare_ios(args.repo, bundle_id=args.bundle_id, team=args.team, check=args.check)
    print(json.dumps({"bundleId": args.bundle_id, "team": args.team or None,
        "codesigning": "not performed", "changed": changed}, indent=2))


if __name__ == "__main__":
    main()
