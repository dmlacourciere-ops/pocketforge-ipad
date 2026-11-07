"""Preparation tests use disposable copies, never this checkout's iOS files."""
import importlib.util
from pathlib import Path
import plistlib
import re
import shutil
import tempfile
import unittest


DIRECTORY = Path(__file__).resolve().parent
REPO = DIRECTORY.parents[1]
spec = importlib.util.spec_from_file_location("prepare_ios", DIRECTORY / "prepare_ios.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PrepareIOSTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="pocketforge-prepare-test-")
        self.repo = Path(self.temp.name)
        paths = [
            "flutter_app/ios/Runner.xcodeproj/project.pbxproj",
            "flutter_app/ios/Runner/AppDelegate.swift",
            "flutter_app/ios/Runner/Info.plist",
            "flutter_app/ios/Runner/Runner.entitlements",
            "flutter_app/ios/Podfile",
        ]
        for relative in paths:
            target = self.repo / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO / relative, target)
        google = self.repo / "flutter_app/ios/Runner/GoogleService-Info.plist"
        google.write_bytes(plistlib.dumps({"GOOGLE_APP_ID": "upstream-fixture", "API_KEY": "not-a-real-key"}))
        self.before = {relative: (self.repo / relative).read_bytes() for relative in paths}

    def tearDown(self):
        self.temp.cleanup()

    def test_identity_permissions_and_native_registration_are_product_scoped(self):
        changed = module.prepare_ios(self.repo)
        self.assertIn("flutter_app/ios/Runner/AppDelegate.swift", changed)
        info = plistlib.loads((self.repo / "flutter_app/ios/Runner/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleDisplayName"], "PocketForge")
        self.assertEqual(info["CFBundleURLTypes"][0]["CFBundleURLSchemes"], ["pocketforge"])
        self.assertFalse(any(key.endswith("UsageDescription") for key in info))
        self.assertNotIn("NSAppTransportSecurity", info)
        self.assertNotIn("NSSupportsLiveActivities", info)
        self.assertEqual(plistlib.loads((self.repo / "flutter_app/ios/Runner/Runner.entitlements").read_bytes()), {})
        delegate = (self.repo / "flutter_app/ios/Runner/AppDelegate.swift").read_text()
        self.assertIn("GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)", delegate)
        self.assertEqual(re.findall(r"^\s*register(\w+)Channel\(messenger: engineBridge", delegate, re.M), ["Keychain"])
        self.assertIn('private let keychainService = "com.pocketforge.ipad.keys"', delegate)
        self.assertIn('name: "fah/keychain"', delegate)
        self.assertIn("private func registerHomeChannel", delegate)  # dormant upstream implementation remains

    def test_project_drops_telemetry_extension_and_author_signing_metadata(self):
        module.prepare_ios(self.repo)
        project = (self.repo / "flutter_app/ios/Runner.xcodeproj/project.pbxproj").read_text()
        for marker in ["dev.fa1.app", "YP9HC3USZ3", "Uladzimir Klyshevich", "GoogleService-Info.plist", "Crashlytics: upload dSYMs", "Embed App Extensions", "FaLiveActivity.appex"]:
            self.assertNotIn(marker, project)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER = com.pocketforge.ipad;", project)
        self.assertIn('DEVELOPMENT_TEAM = "";', project)
        self.assertIn('PROVISIONING_PROFILE_SPECIFIER = "";', project)
        self.assertIn('CODE_SIGN_IDENTITY = "";', project)
        self.assertNotIn("target = FA51AC0300000000000000A1;", project)
        definitions = set(re.findall(r"(?m)^\s*([A-F0-9]{24})(?: /\*[^\n]*?\*/)? = ", project))
        references = set(re.findall(r"\b[A-F0-9]{24}\b", project))
        self.assertEqual(references - definitions, set(), "Prepared Xcode project contains dangling object IDs")
        self.assertEqual(plistlib.loads((self.repo / "flutter_app/ios/Runner/GoogleService-Info.plist").read_bytes()), {})
        self.assertEqual((self.repo / "flutter_app/ios/Podfile").read_bytes(), self.before["flutter_app/ios/Podfile"])
        self.assertIn("-Wl,-force_load", self.before["flutter_app/ios/Podfile"].decode())
        self.assertIn("-Wl,-exported_symbol", self.before["flutter_app/ios/Podfile"].decode())

    def test_preparation_is_idempotent_and_check_mode_never_mutates(self):
        with self.assertRaises(ValueError):
            module.prepare_ios(self.repo, check=True)
        self.assertEqual((self.repo / "flutter_app/ios/Runner/Info.plist").read_bytes(), self.before["flutter_app/ios/Runner/Info.plist"])
        self.assertTrue(module.prepare_ios(self.repo))
        self.assertEqual(module.prepare_ios(self.repo), [])
        self.assertEqual(module.prepare_ios(self.repo, check=True), [])

    def test_optional_team_is_explicit_and_invalid_identifiers_are_rejected_before_writes(self):
        for arguments in [{"team": "author-team"}, {"bundle_id": "bad; injected"}, {"bundle_id": "two.parts"}]:
            with self.assertRaises(ValueError):
                module.prepare_ios(self.repo, **arguments)
        self.assertEqual((self.repo / "flutter_app/ios/Runner/Info.plist").read_bytes(), self.before["flutter_app/ios/Runner/Info.plist"])
        module.prepare_ios(self.repo, team="ABCDEFGHIJ")
        text = (self.repo / "flutter_app/ios/Runner.xcodeproj/project.pbxproj").read_text()
        self.assertIn('DEVELOPMENT_TEAM = "ABCDEFGHIJ";', text)
        self.assertNotIn("YP9HC3USZ3", text)


if __name__ == "__main__":
    unittest.main()
