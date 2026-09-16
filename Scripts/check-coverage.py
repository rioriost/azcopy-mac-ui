#!/usr/bin/env python3
"""Gate core line coverage from one current SwiftPM build, not report columns."""

import argparse
from decimal import Decimal, InvalidOperation
import json
import os
from pathlib import Path
import re
import subprocess
import sys


class CoverageError(Exception):
    pass


def run(command, root):
    result = subprocess.run(command, cwd=root, text=True, capture_output=True)
    if result.returncode:
        raise CoverageError(
            f"{' '.join(command[:2])} failed: {result.stderr.strip() or result.stdout.strip()}"
        )
    return result


def current_artifacts(root, build_path, configuration, build_system):
    command = [
        "swift", "build", "--package-path", str(root),
        "--scratch-path", str(build_path), "--configuration", configuration,
    ]
    if build_system:
        command += ["--build-system", build_system]
    output = run(command + ["--show-bin-path"], root).stdout.strip().splitlines()
    if len(output) != 1:
        raise CoverageError("SwiftPM did not return one unambiguous current binary directory")
    bin_path = Path(output[0]).resolve()
    if not bin_path.is_relative_to(build_path.resolve()):
        raise CoverageError(f"SwiftPM binary directory is outside the selected build path: {bin_path}")
    profile = bin_path / "codecov/default.profdata"
    if not profile.is_file():
        raise CoverageError(f"Coverage profile missing: {profile}. Run Scripts/test-with-coverage.sh")

    package = json.loads(run([
        "swift", "package", "--package-path", str(root), "describe", "--type", "json",
    ], root).stdout)
    targets = {target["name"] for target in package["targets"] if target["type"] == "test"}
    if not targets:
        raise CoverageError("SwiftPM describes no test targets")
    binaries = []
    for bundle in sorted(bin_path.glob("*.xctest")):
        binary = bundle / "Contents/MacOS" / bundle.stem if bundle.is_dir() else bundle
        if not binary.is_file():
            raise CoverageError(f"Test executable missing in bundle: {bundle}")
        binaries.append(binary)
    if not binaries:
        raise CoverageError(f"Test binaries missing from current SwiftPM directory: {bin_path}")
    names = {binary.stem for binary in binaries}
    package_names = {
        package["name"] + "PackageTests",
        re.sub(r"[^A-Za-z0-9_]", "_", package["name"]) + "PackageTests",
    }
    # swiftbuild produces one bundle per test target; older native SwiftPM links one bundle.
    if names != targets and not (len(binaries) == 1 and names <= package_names):
        raise CoverageError(
            "Ambiguous or incomplete test artifacts in current SwiftPM directory: "
            f"{', '.join(sorted(names))}; expected {', '.join(sorted(targets))} "
            "or one package test executable. Use a fresh scratch path."
        )
    inputs = binaries + [root / "Package.swift"]
    for directory in ("Sources", "Tests"):
        inputs.extend((root / directory).rglob("*.swift"))
    newer = [path for path in inputs if path.is_file() and path.stat().st_mtime_ns > profile.stat().st_mtime_ns]
    if newer:
        raise CoverageError(
            f"Stale/mismatched coverage profile: {profile} predates {newer[0]}. "
            "Run Scripts/test-with-coverage.sh"
        )
    return profile, binaries


def line_counts(document, root):
    if (
        not isinstance(document, dict)
        or document.get("type") != "llvm.coverage.json.export"
        or not isinstance(document.get("data"), list)
    ):
        raise CoverageError("Expected llvm-cov export JSON with file-level line coverage")
    core = (root / "Sources/AzCopyMacUICore").resolve()
    files = {}
    for entry in document["data"]:
        if not isinstance(entry, dict) or not isinstance(entry.get("files"), list):
            raise CoverageError("Coverage JSON is missing file-level coverage")
        for file in entry["files"]:
            if not isinstance(file, dict) or not isinstance(file.get("filename"), str):
                raise CoverageError("Coverage JSON contains an invalid file record")
            filename = Path(file["filename"])
            filename = (root / filename).resolve()
            if not filename.is_relative_to(core):
                continue
            summary = file.get("summary")
            lines = summary.get("lines") if isinstance(summary, dict) else None
            if not isinstance(lines, dict):
                raise CoverageError(f"Missing or invalid line counts for {filename}")
            count, covered = lines.get("count"), lines.get("covered")
            if (
                type(count) is not int or type(covered) is not int
                or count < 0 or covered < 0 or covered > count
            ):
                raise CoverageError(f"Missing or invalid line counts for {filename}")
            if filename in files:
                # llvm-cov merges objects before exporting. Never average per-product percentages.
                if files[filename] != file:
                    raise CoverageError(
                        f"Conflicting duplicate coverage for {filename}; export all test objects together"
                    )
                continue
            files[filename] = file
    total = sum(file["summary"]["lines"]["count"] for file in files.values())
    covered = sum(file["summary"]["lines"]["covered"] for file in files.values())
    if not total:
        raise CoverageError("No executable core source lines found; coverage binary/profile may not match")
    return covered, total


def threshold_value(value):
    try:
        threshold = Decimal(value)
    except InvalidOperation as error:
        raise CoverageError("COVERAGE_THRESHOLD must be a number between 80 and 100") from error
    if not threshold.is_finite() or not Decimal(80) <= threshold <= Decimal(100):
        raise CoverageError("COVERAGE_THRESHOLD must be between 80 and 100 (the release minimum is 80)")
    return threshold


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-path", default=".build", help="Scratch path used for the coverage test run")
    parser.add_argument("--configuration", choices=("debug", "release"), default="debug")
    parser.add_argument("--build-system", choices=("native", "swiftbuild", "xcode"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    build_path = (root / args.build_path).resolve()
    try:
        threshold = threshold_value(os.environ.get("COVERAGE_THRESHOLD", "80"))
        profile, binaries = current_artifacts(root, build_path, args.configuration, args.build_system)
        command = ["xcrun", "llvm-cov", "export", str(binaries[0])]
        for binary in binaries[1:]:
            command += ["-object", str(binary)]
        command += [f"-instr-profile={profile}", str(root / "Sources/AzCopyMacUICore")]
        result = run(command, root)
        if re.search(r"warning:|error:|mismatch|out of date|malformed", result.stderr, re.IGNORECASE):
            raise CoverageError(f"Coverage binary/profile mismatch or export warning: {result.stderr.strip()}")
        covered, total = line_counts(json.loads(result.stdout), root)
        coverage = Decimal(covered) * 100 / Decimal(total)
        numerator, denominator = threshold.as_integer_ratio()
        passed = covered * 100 * denominator >= numerator * total
        print(
            f"Core line coverage {coverage:.2f}% ({covered}/{total}) "
            f"{'meets' if passed else 'is below'} required {threshold:.2f}% "
            f"across {len(binaries)} test executable(s)"
        )
        return 0 if passed else 1
    except (CoverageError, OSError, ValueError, KeyError, TypeError) as error:
        print(f"coverage: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
