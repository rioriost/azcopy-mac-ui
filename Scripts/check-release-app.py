#!/usr/bin/env python3
"""Verify archive/export metadata and every bundled Mach-O architecture before notarization."""

import argparse
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import sys


def check_app(app, version, build):
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundleShortVersionString") != version or info.get("CFBundleVersion") != build:
        raise ValueError(f"App metadata does not match VERSION/build: {app}")
    executable = info.get("CFBundleExecutable", "")
    if not executable or Path(executable).name != executable or executable in (".", ".."):
        raise ValueError(f"Invalid CFBundleExecutable: {app}")
    main = app / "Contents/MacOS" / executable
    if not main.is_file():
        raise ValueError(f"App executable is missing: {main}")
    magic_numbers = {
        b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
        b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
    }
    checked_main = False
    for path in sorted((app / "Contents").rglob("*")):
        if not path.is_file():
            continue
        with path.open("rb") as stream:
            if stream.read(4) not in magic_numbers:
                continue
        result = subprocess.run(["xcrun", "lipo", "-archs", str(path)], text=True, capture_output=True)
        if result.returncode or result.stdout.split() != ["arm64"]:
            raise ValueError(f"Expected arm64-only Mach-O: {path}: {result.stdout.strip()} {result.stderr.strip()}")
        checked_main |= path == main
    if not checked_main:
        raise ValueError(f"App executable is not Mach-O: {main}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    spec = importlib.util.spec_from_file_location("release_version", root / "Scripts/check-version.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    try:
        version, build = module.check_version(root)
        if args.archive:
            with (args.archive / "Info.plist").open("rb") as stream:
                properties = plistlib.load(stream).get("ApplicationProperties", {})
            if (
                properties.get("CFBundleShortVersionString") != version
                or properties.get("CFBundleVersion") != build
            ):
                raise ValueError("Archive metadata does not match VERSION/build")
        check_app(args.app, version, build)
        print(f"release-app: {version} (build {build}), arm64-only: {args.app}")
        return 0
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"release-app: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
