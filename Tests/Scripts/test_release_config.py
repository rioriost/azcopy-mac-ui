import json
import subprocess

from script_fixture import ScriptFixture


class ReleaseConfigurationTests(ScriptFixture):
    def git_setting(self, key, value=None):
        args = ["git", "-C", str(self.root), "config", "--local", key]
        if value is not None:
            args.append(value)
        return subprocess.run(args, text=True, capture_output=True, check=value is not None)

    def clear_environment(self):
        for name in ("NOTARY_PROFILE", "NOTARY_KEYCHAIN", "DEVELOPER_ID_APPLICATION", "APPLE_TEAM_ID"):
            self.env.pop(name, None)

    def test_configure_persists_references_without_environment_or_passwords(self):
        result = self.run_script("release-config.py", "configure")
        self.assertEqual(result.returncode, 0, result.stderr)
        profile = self.env["NOTARY_PROFILE"]
        self.clear_environment()
        shown = self.run_script("release-config.py", "show")
        self.assertEqual(shown.returncode, 0, shown.stderr)
        settings = json.loads(shown.stdout)
        self.assertEqual(settings["NOTARY_PROFILE"], profile)
        self.assertEqual(settings["APPLE_TEAM_ID"], "A1B2C3D4E5")
        self.assertEqual(settings["NOTARY_KEYCHAIN"], "")
        config = (self.root / ".git/config").read_text()
        self.assertNotIn("password", config.lower())
        self.assertNotIn("--password", str(self.commands()))
        self.assertNotIn("store-credentials", str(self.commands()))

    def test_missing_reference_is_not_reported_as_missing_credentials(self):
        self.clear_environment()
        result = self.run_script("release-config.py", "check")
        self.assert_failed(result, "does NOT mean credentials are absent")
        self.assertFalse(any(c[:2] == ["xcrun", "notarytool"] for c in self.commands()))

    def test_environment_overrides_saved_profile(self):
        self.git_setting("azcopyRelease.notaryProfile", "saved-profile")
        shown = self.run_script("release-config.py", "show")
        self.assertEqual(json.loads(shown.stdout)["NOTARY_PROFILE"], self.env["NOTARY_PROFILE"])

    def test_configure_argument_overrides_environment(self):
        result = self.run_script("release-config.py", "configure", "--notary-profile", "selected profile")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git_setting("azcopyRelease.notaryProfile").stdout.strip(), "selected profile")

    def test_unique_signing_identity_and_team_are_resolved_without_exports(self):
        self.env.pop("DEVELOPER_ID_APPLICATION")
        self.env.pop("APPLE_TEAM_ID")
        shown = self.run_script("release-config.py", "show")
        self.assertEqual(shown.returncode, 0, shown.stderr)
        self.assertEqual(json.loads(shown.stdout)["APPLE_TEAM_ID"], "A1B2C3D4E5")

    def test_ambiguous_signing_identity_requires_selection(self):
        self.env.pop("DEVELOPER_ID_APPLICATION")
        self.env.pop("APPLE_TEAM_ID")
        self.state["identities"] = [
            "Developer ID Application: One (A1B2C3D4E5)",
            "Developer ID Application: Two (Z9Y8X7W6V5)",
        ]
        self.write_state()
        self.assert_failed(self.run_script("release-config.py", "show"), "ambiguous")

    def test_mismatching_team_fails_before_notarytool(self):
        self.env["APPLE_TEAM_ID"] = "Z9Y8X7W6V5"
        self.assert_failed(self.run_script("release-config.py", "check"), "does not match")
        self.assertFalse(any(c[:2] == ["xcrun", "notarytool"] for c in self.commands()))

    def test_custom_keychain_is_saved_and_can_be_cleared(self):
        keychain = self.write("credentials/custom keychain-db", "fixture")
        result = self.run_script("release-config.py", "configure", "--notary-keychain", str(keychain))
        self.assertEqual(result.returncode, 0, result.stderr)
        history = next(c for c in self.commands() if c[:3] == ["xcrun", "notarytool", "history"])
        self.assertEqual(history[history.index("--keychain") + 1], str(keychain))
        result = self.run_script("release-config.py", "configure", "--default-keychain")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git_setting("azcopyRelease.notaryKeychain").stdout, "\n")

    def test_invalid_keychain_file_is_an_explicit_selection_error(self):
        self.env["NOTARY_KEYCHAIN"] = str(self.root / "missing-keychain")
        self.assert_failed(self.run_script("release-config.py", "check"), "explicitly selected")

    def test_unreadable_profile_does_not_overwrite_good_saved_configuration(self):
        self.git_setting("azcopyRelease.notaryProfile", "keep-this-profile")
        self.state["notary_failure"] = "Error: No Keychain password item found for profile"
        self.write_state()
        result = self.run_script("release-config.py", "configure")
        self.assert_failed(result, "could not read the selected profile")
        self.assertEqual(self.git_setting("azcopyRelease.notaryProfile").stdout.strip(), "keep-this-profile")

    def test_credential_rejection_is_distinct_from_profile_lookup(self):
        self.state["notary_failure"] = "HTTP status code 401 Unauthorized"
        self.write_state()
        self.assert_failed(self.run_script("release-config.py", "check"), "Apple rejected")

    def test_locked_keychain_diagnostic(self):
        self.state["notary_failure"] = "User interaction is not allowed because keychain is locked"
        self.write_state()
        self.assert_failed(self.run_script("release-config.py", "check"), "locked or inaccessible")

    def test_control_characters_are_rejected_in_environment_and_saved_values(self):
        self.env["NOTARY_PROFILE"] = "profile\nanother-field"
        self.assert_failed(self.run_script("release-config.py", "show"), "control characters")
        self.env.pop("NOTARY_PROFILE")
        self.git_setting("azcopyRelease.notaryProfile", "profile\n")
        self.assert_failed(self.run_script("release-config.py", "show"), "control characters")
