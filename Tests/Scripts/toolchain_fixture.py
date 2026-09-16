#!/usr/bin/env python3
"""Offline command stand-ins used only by script regression fixtures."""

import json
import os
from pathlib import Path
import plistlib
import shutil
import sys

root = Path(os.environ["SCRIPT_FIXTURE_ROOT"])
state_path = root / "fixture.json"
state = json.loads(state_path.read_text())
command = Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / "commands.jsonl").open("a") as stream:
    stream.write(json.dumps([command, *args]) + "\n")


def app_at(path):
    (path / "Contents/MacOS").mkdir(parents=True)
    with (path / "Contents/Info.plist").open("wb") as stream:
        plistlib.dump({
            "CFBundleShortVersionString": state.get("app_version", "0.2.1"),
            "CFBundleVersion": state.get("app_build", "3"),
            "CFBundleExecutable": "AzCopyMacUI",
        }, stream)
    (path / "Contents/MacOS/AzCopyMacUI").write_bytes(b"\xcf\xfa\xed\xfe" + b"fixture")
    if state.get("nested_bad_arch"):
        nested = path / "Contents/Frameworks/BadFramework"
        nested.parent.mkdir()
        nested.write_bytes(b"\xcf\xfa\xed\xfe" + b"fixture")


if command == "swift":
    if args[0] == "test":
        if state.get("test_status"):
            sys.exit(state["test_status"])
        build = root / args[args.index("--scratch-path") + 1]
        state["bin_path"] = str(build / "out/Products/Debug")
        directory = Path(state["bin_path"])
        for target in state["targets"]:
            binary = directory / f"{target}.xctest/Contents/MacOS" / target
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b"fixture")
        profile = directory / "codecov/default.profdata"
        profile.parent.mkdir()
        profile.write_bytes(b"fixture")
        state_path.write_text(json.dumps(state))
    elif args[0] == "build" and "--show-bin-path" in args:
        print(state["bin_path"])
    elif args[0] == "package" and "describe" in args:
        print(json.dumps({
            "name": "azcopy-mac-ui",
            "targets": [{"name": name, "type": "test"} for name in state["targets"]],
        }))
    else:
        sys.exit("Unexpected Swift invocation in fixture")
elif command == "xcrun":
    if args[:2] == ["llvm-cov", "export"]:
        if state.get("export_warning"):
            print(state["export_warning"], file=sys.stderr)
        print((root / "coverage.json").read_text())
        sys.exit(state.get("export_status", 0))
    elif args[:2] == ["lipo", "-archs"]:
        print("x86_64" if args[-1].endswith("/BadFramework") else state.get("architectures", "arm64"))
    elif args[:2] == ["notarytool", "history"]:
        if state.get("notary_failure"):
            print(state["notary_failure"], file=sys.stderr)
            sys.exit(69)
        print(json.dumps({"history": []}))
    elif args[0] not in ("notarytool", "stapler"):
        sys.exit("Unexpected xcrun invocation in fixture")
elif command == "xcodebuild":
    archive = root / args[args.index("-archivePath") + 1]
    if args[0] == "archive":
        app_at(archive / "Products/Applications/AzCopy Mac UI.app")
        with (archive / "Info.plist").open("wb") as stream:
            plistlib.dump({"ApplicationProperties": {
                "CFBundleShortVersionString": state.get("archive_version", "0.2.1"),
                "CFBundleVersion": "3",
            }}, stream)
    elif args[0] == "-exportArchive":
        export = root / args[args.index("-exportPath") + 1]
        shutil.copytree(archive / "Products/Applications", export)
        if state.get("export_app_version"):
            info = export / "AzCopy Mac UI.app/Contents/Info.plist"
            with info.open("rb") as stream:
                properties = plistlib.load(stream)
            properties["CFBundleShortVersionString"] = state["export_app_version"]
            with info.open("wb") as stream:
                plistlib.dump(properties, stream)
    else:
        sys.exit("Unexpected xcodebuild invocation in fixture")
elif command == "codesign":
    if "--display" in args:
        print("Runtime Version=26.0.0", file=sys.stderr)
elif command == "ditto":
    (root / args[-1]).write_bytes(b"offline release zip fixture")
elif command == "security":
    if args != ["find-identity", "-v", "-p", "codesigning"]:
        sys.exit("Fixture refuses secret-reading Keychain commands")
    default_identity = "Developer ID Application: Fixture 'quoted' \"double\" & <sample> (A1B2C3D4E5)"
    for index, identity in enumerate(state.get("identities", [default_identity]), 1):
        print(f'  {index}) {index:040X} "{identity}"')
elif command != "spctl":
    sys.exit("Unexpected command in fixture")
