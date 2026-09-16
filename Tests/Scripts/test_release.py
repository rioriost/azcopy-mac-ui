import plistlib

from script_fixture import ScriptFixture


class VersionTests(ScriptFixture):
    def test_consistent_version_ignores_older_published_cask(self):
        self.write("Casks/azcopy-mac-ui.rb", 'version "0.1.1"\n')
        result = self.run_script("check-version.py")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_core_version_mismatch_fails(self):
        self.write("Sources/AzCopyMacUICore/AppVersion.swift", 'static let current = "0.2.0"')
        self.assert_failed(self.run_script("check-version.py"), "AppVersion")

    def test_info_short_version_mismatch_fails(self):
        with (self.root / "AzCopyMacUI/Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "3"}, stream)
        self.assert_failed(self.run_script("check-version.py"), "CFBundleShortVersionString")

    def test_any_marketing_configuration_mismatch_fails(self):
        self.write("AzCopyMacUI.xcodeproj/project.pbxproj",
                   "MARKETING_VERSION = 0.2.1;\nMARKETING_VERSION = 0.2.0;\nCURRENT_PROJECT_VERSION = 3;")
        self.assert_failed(self.run_script("check-version.py"), "MARKETING_VERSION")

    def test_bundle_build_mismatch_fails(self):
        with (self.root / "AzCopyMacUI/Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleShortVersionString": "0.2.1", "CFBundleVersion": "2"}, stream)
        self.assert_failed(self.run_script("check-version.py"), "CURRENT_PROJECT_VERSION")

    def test_missing_project_version_fails(self):
        self.write("AzCopyMacUI.xcodeproj/project.pbxproj", "CURRENT_PROJECT_VERSION = 3;")
        self.assert_failed(self.run_script("check-version.py"), "MARKETING_VERSION is missing")

    def test_unsafe_version_cannot_be_used_as_stage_path(self):
        self.write("VERSION", "../elsewhere\n")
        self.assert_failed(self.run_script("check-version.py"), "major.minor.patch")


class ReleaseTests(ScriptFixture):
    def assert_not_signed(self):
        self.assertFalse(any(c[0] in ("codesign", "xcodebuild") or c[:2] == ["xcrun", "notarytool"]
                             for c in self.commands()), self.commands())

    def test_version_failure_precedes_signing_credentials_and_leaves_artifacts(self):
        self.write("VERSION", "0.2.0\n")
        self.env.pop("DEVELOPER_ID_APPLICATION")
        sentinel = self.write("release/keep.zip", "user artifact")
        result = self.run_script("package-release.sh")
        self.assert_failed(result, "AppVersion")
        self.assertNotIn("Set DEVELOPER_ID_APPLICATION", result.stderr)
        self.assertEqual(sentinel.read_text(), "user artifact")
        self.assert_not_signed()
        self.assertFalse((self.root / "release/0.2.0").exists())

    def test_script_test_failure_prevents_packaging(self):
        self.state["script_test_failure"] = True
        self.write_state()
        self.assert_failed(self.run_script("package-release.sh"), "FAILED")
        self.assert_not_signed()
        self.assertFalse((self.root / "release").exists())

    def test_security_failure_prevents_packaging(self):
        self.write("Sources/AzCopyMacUICore/Unsafe.swift", 'let shell = "/bin/sh"\n')
        self.assert_failed(self.run_script("package-release.sh"), "shell execution")
        self.assert_not_signed()
        self.assertFalse((self.root / "release").exists())

    def test_swift_test_failure_prevents_packaging(self):
        self.state["test_status"] = 1
        self.write_state()
        result = self.run_script("package-release.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assert_not_signed()
        self.assertFalse((self.root / "release").exists())

    def test_coverage_failure_prevents_packaging(self):
        self.coverage(covered=7999)
        self.assert_failed(self.run_script("package-release.sh"), "79.99%")
        self.assert_not_signed()
        self.assertFalse((self.root / "release").exists())

    def test_existing_stage_is_preserved_and_rejected(self):
        sentinel = self.write("release/0.2.1/keep.zip", "user artifact")
        self.assert_failed(self.run_script("package-release.sh"), "existing release stage")
        self.assertEqual(sentinel.read_text(), "user artifact")
        self.assert_not_signed()

    def test_invalid_credentials_do_not_create_stage(self):
        self.state["notary_failure"] = "No Keychain password item found for profile"
        self.write_state()
        self.assert_failed(self.run_script("package-release.sh"), "could not read the selected profile")
        self.assertFalse((self.root / "release").exists())

    def test_configured_checkout_packages_without_environment_exports(self):
        result = self.run_script("release-config.py", "configure")
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in ("DEVELOPER_ID_APPLICATION", "APPLE_TEAM_ID", "NOTARY_PROFILE"):
            self.env.pop(name)
        result = self.run_script("package-release.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.root / "release/0.2.1/azcopy-mac-ui-0.2.1-macos-arm64.zip").is_file())

    def test_custom_notary_keychain_reaches_validation_and_submission(self):
        keychain = self.write("credentials/notary keychain-db", "fixture")
        self.env["NOTARY_KEYCHAIN"] = str(keychain)
        result = self.run_script("package-release.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for call in self.commands():
            if call[:2] == ["xcrun", "notarytool"]:
                self.assertEqual(call[call.index("--keychain") + 1], str(keychain))

    def test_retry_preserves_existing_stage_and_releases_lock(self):
        self.write("release/0.2.1/keep.zip", "user artifact")
        result = self.run_script("package-release.sh", "--retry")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        backups = list((self.root / "release").glob(".retry-0.2.1.*/artifacts/keep.zip"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "user artifact")
        self.assertFalse((self.root / "release/.0.2.1.lock").exists())

    def test_failed_retry_credentials_leave_existing_stage_untouched(self):
        sentinel = self.write("release/0.2.1/keep.zip", "user artifact")
        self.state["notary_failure"] = "HTTP status code 401 Unauthorized"
        self.write_state()
        self.assert_failed(self.run_script("package-release.sh", "--retry"), "Apple rejected")
        self.assertEqual(sentinel.read_text(), "user artifact")
        self.assertEqual(list((self.root / "release").glob(".retry-*")), [])

    def test_existing_release_lock_prevents_build_and_stage_changes(self):
        self.write("release/.0.2.1.lock/sentinel", "active release")
        result = self.run_script("package-release.sh")
        self.assert_failed(result, "Another release may be running")
        self.assertFalse(any(c[0] in ("codesign", "xcodebuild") for c in self.commands()))
        self.assertFalse((self.root / "release/0.2.1").exists())

    def test_release_root_symlink_is_rejected(self):
        target = self.root / "user-artifacts"
        target.mkdir()
        (self.root / "release").symlink_to(target, target_is_directory=True)
        self.assert_failed(self.run_script("package-release.sh"), "symlink")
        self.assertEqual(list(target.iterdir()), [])
        self.assert_not_signed()

    def test_success_uses_one_preflight_before_signing_and_preserves_previous_versions(self):
        sentinel = self.write("release/0.1.1/keep.zip", "published artifact")
        result = self.run_script("package-release.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(sentinel.read_text(), "published artifact")
        calls = self.commands()
        self.assertEqual(calls.count(["script-tests"]), 1)
        self.assertEqual(len([c for c in calls if c[:2] == ["swift", "test"]]), 1)
        export_index = next(i for i, c in enumerate(calls) if c[:2] == ["xcrun", "llvm-cov"])
        credential_index = next(i for i, c in enumerate(calls) if c[:2] == ["xcrun", "notarytool"])
        self.assertLess(export_index, credential_index)
        archive = next(c for c in calls if c[:2] == ["xcodebuild", "archive"])
        self.assertIn("ARCHS=arm64", archive)
        self.assertIn("OTHER_CODE_SIGN_FLAGS=--timestamp", archive)
        self.assertIn("CODE_SIGN_IDENTITY=" + self.env["DEVELOPER_ID_APPLICATION"], archive)
        with (self.root / "release/0.2.1/ExportOptions.plist").open("rb") as stream:
            options = plistlib.load(stream)
        self.assertEqual(options["signingCertificate"], self.env["DEVELOPER_ID_APPLICATION"])
        notary = next(c for c in calls if c[:3] == ["xcrun", "notarytool", "submit"])
        self.assertEqual(notary[notary.index("--keychain-profile") + 1], self.env["NOTARY_PROFILE"])
        self.assertTrue(any(c[:3] == ["xcrun", "stapler", "validate"] for c in calls))
        self.assertTrue(any(c[0] == "spctl" for c in calls))
        checksum = self.root / "release/0.2.1/azcopy-mac-ui-0.2.1-macos-arm64.zip.sha256"
        self.assertTrue(checksum.is_file())
        self.assertEqual(checksum.read_text().split()[1], "azcopy-mac-ui-0.2.1-macos-arm64.zip")

    def test_wrong_architecture_prevents_notarization(self):
        self.state["architectures"] = "arm64 x86_64"
        self.write_state()
        self.assert_failed(self.run_script("package-release.sh"), "arm64-only")
        self.assertFalse(any(c[:3] == ["xcrun", "notarytool", "submit"] for c in self.commands()))

    def test_non_arm64_nested_binary_prevents_notarization(self):
        self.state["nested_bad_arch"] = True
        self.write_state()
        self.assert_failed(self.run_script("package-release.sh"), "BadFramework")
        self.assertFalse(any(c[:3] == ["xcrun", "notarytool", "submit"] for c in self.commands()))

    def test_exported_app_version_is_checked_again_before_notarization(self):
        self.state["export_app_version"] = "0.2.0"
        self.write_state()
        self.assert_failed(self.run_script("package-release.sh"), "App metadata")
        self.assertTrue(any(c[:2] == ["xcodebuild", "-exportArchive"] for c in self.commands()))
        self.assertFalse(any(c[:3] == ["xcrun", "notarytool", "submit"] for c in self.commands()))

    def test_archive_metadata_mismatch_prevents_export_and_notarization(self):
        self.state["archive_version"] = "0.2.0"
        self.write_state()
        self.assert_failed(self.run_script("package-release.sh"), "Archive metadata")
        self.assertFalse(any(c[:2] == ["xcodebuild", "-exportArchive"] for c in self.commands()))

    def test_built_app_metadata_mismatch_prevents_export(self):
        self.state["app_build"] = "2"
        self.write_state()
        self.assert_failed(self.run_script("package-release.sh"), "App metadata")
        self.assertFalse(any(c[:2] == ["xcodebuild", "-exportArchive"] for c in self.commands()))


class SecurityGateTests(ScriptFixture):
    def test_known_credential_filter_and_negative_test_references_are_allowed(self):
        self.write("Sources/AzCopyMacUICore/AzCopyProcessRunner.swift",
                   'let blockedEnvironmentKeys = ["AZCOPY_ACCOUNT_KEY"]\n')
        self.write("Tests/AzCopyMacUICoreTests/CredentialRedactorTests.swift",
                   'let fixture = "AZCOPY_ACCOUNT_KEY=FAKE_SECRET"\n')
        result = self.run_script("security-review.sh")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_direct_account_key_use_in_ui_is_rejected(self):
        self.write("Sources/AzCopyMacUI/AppModel.swift", 'let environment = ["AZCOPY_ACCOUNT_KEY": "fixture"]\n')
        self.assert_failed(self.run_script("security-review.sh"), "direct account key")

    def test_allowlist_requires_exact_file_paths(self):
        self.write("Sources/AzCopyMacUICore/UnsafeSecurityPolicy.swift",
                   'let environment = ["AZCOPY_ACCOUNT_KEY": "fixture"]\n')
        self.assert_failed(self.run_script("security-review.sh"), "direct account key")
