import json
import os
import shutil
import subprocess
import unittest

from script_fixture import ScriptFixture


class CoverageTests(ScriptFixture):
    def test_7999_percent_fails_even_with_100_percent_regions_and_rounded_summary(self):
        self.coverage(covered=7999)
        self.assert_failed(self.run_script("check-coverage.sh"), "79.99%")

    def test_exactly_80_percent_passes(self):
        result = self.run_script("check-coverage.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("80.00% (8000/10000)", result.stdout)

    def test_subthreshold_value_rounding_to_80_still_fails(self):
        self.coverage(count=100000, covered=79999)
        self.assert_failed(self.run_script("check-coverage.sh"), "is below")

    def test_regions_are_not_used_when_line_metric_is_missing(self):
        file = self.coverage_file()
        del file["summary"]["lines"]
        self.coverage(files=[file])
        self.assert_failed(self.run_script("check-coverage.sh"), "line counts")

    def test_missing_core_coverage_does_not_use_global_totals(self):
        file = self.coverage_file()
        file["filename"] = str(self.root / "Sources/AzCopyMacUI/AppModel.swift")
        self.coverage(files=[file])
        self.assert_failed(self.run_script("check-coverage.sh"), "No executable core")

    def test_invalid_counts_fail(self):
        for count, covered in [(100, 101), (-1, 0), (100, -1), (100, 80.0), (True, 1)]:
            with self.subTest(count=count, covered=covered):
                self.coverage(count=count, covered=covered)
                self.assert_failed(self.run_script("check-coverage.sh"), "invalid line counts")

    def test_empty_coverage_fails(self):
        self.coverage(count=0, covered=0)
        self.assert_failed(self.run_script("check-coverage.sh"), "No executable core")

    def test_rejects_malformed_json(self):
        self.write("coverage.json", "{")
        self.assert_failed(self.run_script("check-coverage.sh"), "coverage:")

    def test_rejects_missing_export_schema_without_traceback(self):
        for document in (None, [], {}, {"type": "llvm.coverage.json.export", "data": [None]}):
            with self.subTest(document=document):
                self.write("coverage.json", json.dumps(document))
                result = self.run_script("check-coverage.sh")
                self.assert_failed(result, "coverage")
                self.assertNotIn("Traceback", result.stderr)

    def test_missing_profile_never_falls_back_to_stale_directory(self):
        self.profile.unlink()
        self.write(".build/older/debug/codecov/default.profdata", "stale")
        self.assert_failed(self.run_script("check-coverage.sh"), "profile missing")
        self.assertFalse(any(c[:2] == ["xcrun", "llvm-cov"] for c in self.commands()))

    def test_stale_binary_profile_pair_fails(self):
        os.utime(self.profile, (1, 1))
        self.assert_failed(self.run_script("check-coverage.sh"), "Stale/mismatched")

    def test_warning_for_wrong_profile_is_failure_even_if_export_returns_success(self):
        self.state["export_warning"] = "warning: 12 functions have mismatched data"
        self.write_state()
        self.assert_failed(self.run_script("check-coverage.sh"), "binary/profile mismatch")

    def test_export_failure_is_actionable(self):
        self.state.update(export_status=1, export_warning="error: malformed profile")
        self.write_state()
        self.assert_failed(self.run_script("check-coverage.sh"), "malformed profile")

    def test_ambiguous_package_and_split_products_fail(self):
        self.artifacts(["azcopy_mac_uiPackageTests"])
        self.assert_failed(self.run_script("check-coverage.sh"), "Ambiguous")

    def test_missing_one_current_test_product_fails(self):
        shutil.rmtree(self.bin / "AzCopyMacUIModelTests.xctest")
        self.assert_failed(self.run_script("check-coverage.sh"), "incomplete")

    def test_missing_all_test_binaries_fails(self):
        for bundle in self.bin.glob("*.xctest"):
            shutil.rmtree(bundle)
        self.assert_failed(self.run_script("check-coverage.sh"), "Test binaries missing")

    def test_older_native_package_layout_is_supported(self):
        self.bin = self.root / ".build/arm64-apple-macosx/debug"
        self.bin.mkdir(parents=True)
        self.state["bin_path"] = str(self.bin)
        self.write_state()
        self.artifacts(["azcopy_mac_uiPackageTests"])
        result = self.run_script("check-coverage.sh", "--build-system", "native")
        self.assertEqual(result.returncode, 0, result.stderr)
        export = next(c for c in self.commands() if c[:2] == ["xcrun", "llvm-cov"])
        self.assertIn("arm64-apple-macosx/debug", export[3])
        self.assertNotIn("-object", export)

    def test_all_current_products_export_together_and_only_core_counts_are_weighted(self):
        files = [self.coverage_file(count=90, covered=90),
                 self.coverage_file(name="Second.swift", count=10, covered=0)]
        excluded = self.coverage_file(count=10000, covered=0)
        excluded["filename"] = str(self.root / "Sources/AzCopyMacUI/AppModel.swift")
        files.append(excluded)
        self.coverage(files=files)
        result = self.run_script("check-coverage.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("90.00% (90/100)", result.stdout)
        export = next(c for c in self.commands() if c[:2] == ["xcrun", "llvm-cov"])
        self.assertEqual(export.count("-object"), 1)
        self.assertIn("AzCopyMacUICoreTests", export[3])
        self.assertIn("AzCopyMacUIModelTests", export[export.index("-object") + 1])

    def test_duplicate_file_records_are_not_double_counted(self):
        file = self.coverage_file(count=100, covered=80)
        self.coverage(files=[file, file])
        result = self.run_script("check-coverage.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("(80/100)", result.stdout)

    def test_differing_duplicate_file_records_must_be_merged_by_llvm_not_averaged(self):
        self.coverage(files=[self.coverage_file(count=100, covered=70),
                             self.coverage_file(count=100, covered=90)])
        self.assert_failed(self.run_script("check-coverage.sh"), "Conflicting duplicate")

    def test_release_minimum_cannot_be_lowered_or_invalid(self):
        for threshold in ("79", "NaN", "Infinity", "101", "garbage"):
            with self.subTest(threshold=threshold):
                self.env["COVERAGE_THRESHOLD"] = threshold
                self.assert_failed(self.run_script("check-coverage.sh"), "COVERAGE_THRESHOLD")

    def test_stricter_threshold_is_supported(self):
        self.env["COVERAGE_THRESHOLD"] = "90"
        self.assert_failed(self.run_script("check-coverage.sh"), "required 90.00%")

    def test_fresh_test_wrapper_uses_one_isolated_run_and_all_test_targets(self):
        result = self.run_script("test-with-coverage.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.commands()
        tests = [c for c in calls if c[:2] == ["swift", "test"]]
        self.assertEqual(len(tests), 1)
        self.assertNotIn("--filter", tests[0])
        self.assertIn("--enable-code-coverage", tests[0])
        scratch = tests[0][tests[0].index("--scratch-path") + 1]
        self.assertIn(".build/coverage-runs/", scratch)
        state = json.loads((self.root / "fixture.json").read_text())
        self.assertIn(scratch, state["bin_path"])

    @unittest.skipUnless(shutil.which("xcrun"), "Requires the macOS LLVM toolchain")
    def test_real_llvm_merges_shared_core_coverage_once_across_objects(self):
        tool_env = {**os.environ, "TMPDIR": str(self.root)}
        source = self.write("Sources/AzCopyMacUICore/Fixture.c",
                            "int left(void) {\n return 1;\n}\n"
                            "int right(void) {\n return 2;\n}\n")
        binaries, profiles = [], []
        for name, function, value in (("first", "left", 1), ("second", "right", 2)):
            main = self.write(f"{name}.c",
                              f"int {function}(void);\n"
                              f"int main(void) {{ return {function}() != {value}; }}\n")
            binary = self.root / name
            profile = self.root / f"{name}.profraw"
            subprocess.run(["xcrun", "clang", "-fprofile-instr-generate", "-fcoverage-mapping",
                            str(source), str(main), "-o", str(binary)],
                           check=True, capture_output=True, text=True, env=tool_env)
            subprocess.run([str(binary)], check=True, env={**tool_env, "LLVM_PROFILE_FILE": str(profile)})
            binaries.append(binary)
            profiles.append(profile)
        subprocess.run(["xcrun", "llvm-profdata", "merge", "-sparse", *map(str, profiles),
                        "-o", str(self.profile)], check=True, capture_output=True, text=True, env=tool_env)
        result = subprocess.run(["xcrun", "llvm-cov", "export", str(binaries[0]),
                                 "-object", str(binaries[1]), f"-instr-profile={self.profile}",
                                 str(source.parent)], check=True, capture_output=True, text=True, env=tool_env)
        document = json.loads(result.stdout)
        files = [file for entry in document["data"] for file in entry["files"]]
        self.assertEqual(len(files), 1)
        self.assertEqual(files[0]["summary"]["lines"]["covered"], files[0]["summary"]["lines"]["count"])
        self.write("coverage.json", result.stdout)
        gate = self.run_script("check-coverage.sh")
        self.assertEqual(gate.returncode, 0, gate.stderr)
        self.assertIn("100.00%", gate.stdout)
