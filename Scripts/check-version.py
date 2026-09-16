#!/usr/bin/env python3
"""Validate release versions without changing source files or the published cask."""

import argparse
from pathlib import Path
import plistlib
import re
import sys


def project_values(project, key):
    values = re.findall(r"\b" + key + r'\s*=\s*(?:"([^"]+)"|([^;\s]+))\s*;', project)
    if not values:
        raise ValueError(f"{key} is missing from project.pbxproj")
    return {quoted or plain for quoted, plain in values}


def check_version(root):
    version = (root / "VERSION").read_text().strip()
    if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", version):
        raise ValueError("VERSION must be a stable numeric major.minor.patch release version")
    source = (root / "Sources/AzCopyMacUICore/AppVersion.swift").read_text()
    core_versions = re.findall(r'\bstatic\s+let\s+current\s*=\s*"([^"]+)"', source)
    if core_versions != [version]:
        raise ValueError("VERSION does not match the AppVersion.current literal")
    with (root / "AzCopyMacUI/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundleShortVersionString") != version:
        raise ValueError("VERSION does not match Info.plist CFBundleShortVersionString")
    build = info.get("CFBundleVersion", "")
    if not isinstance(build, str) or not re.fullmatch(r"\d+(?:\.\d+){0,2}", build):
        raise ValueError("Info.plist CFBundleVersion must be a numeric build version")
    project = (root / "AzCopyMacUI.xcodeproj/project.pbxproj").read_text()
    if project_values(project, "MARKETING_VERSION") != {version}:
        raise ValueError("VERSION does not match every project MARKETING_VERSION")
    if project_values(project, "CURRENT_PROJECT_VERSION") != {build}:
        raise ValueError("CFBundleVersion does not match every project CURRENT_PROJECT_VERSION")
    return version, build


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    try:
        version, build = check_version(Path(__file__).resolve().parent.parent)
        print(f"version: {version} (build {build}) is consistent")
        return 0
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"version: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
