#!/usr/bin/env python3
"""Bind this checkout to existing signing/notarization credentials, without exporting secrets."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
KEYS = {
    "DEVELOPER_ID_APPLICATION": "azcopyRelease.signingIdentity",
    "APPLE_TEAM_ID": "azcopyRelease.teamID",
    "NOTARY_PROFILE": "azcopyRelease.notaryProfile",
    "NOTARY_KEYCHAIN": "azcopyRelease.notaryKeychain",
}


def command(arguments, timeout=60):
    return subprocess.run(arguments, cwd=ROOT, text=True, capture_output=True, timeout=timeout)


def local_setting(key):
    result = command(["git", "config", "--local", "--null", "--get", key])
    if result.returncode == 1:
        return ""
    if result.returncode:
        raise ValueError(f"Cannot read local release configuration ({key}): {result.stderr.strip()}")
    return result.stdout.removesuffix("\0")


def identities():
    result = command(["security", "find-identity", "-v", "-p", "codesigning"])
    if result.returncode:
        raise ValueError("Cannot inspect signing identities. Check Keychain availability and unlock it if needed.")
    pattern = r'^\s*\d+\)\s+([A-Fa-f0-9]{40})\s+"(Developer ID Application: .+ \(([A-Z0-9]{10})\))"\s*$'
    return sorted(set(re.findall(pattern, result.stdout, re.MULTILINE)))


def resolve(overrides=None):
    overrides = overrides or {}
    settings = {}
    for variable, key in KEYS.items():
        value = overrides.get(variable)
        if value is None:
            value = os.environ[variable] if variable in os.environ else local_setting(key)
        if any(ord(character) < 32 or ord(character) == 127 for character in value):
            raise ValueError(f"{variable} must not contain control characters")
        settings[variable] = value

    profile = settings["NOTARY_PROFILE"]
    if not profile.strip():
        raise ValueError(
            "No notarization profile reference is configured for this checkout. "
            "This does NOT mean credentials are absent from Keychain. "
            "Bind an existing profile once with: python3 Scripts/release-config.py configure "
            "--notary-profile PROFILE [--notary-keychain PATH]. "
            "notarytool does not provide a profile-list command; protected/iCloud profiles "
            "may not appear in security dump-keychain."
        )
    keychain = settings["NOTARY_KEYCHAIN"]
    if keychain:
        keychain_path = Path(keychain).expanduser()
        if not keychain_path.is_file():
            raise ValueError(f"The explicitly selected notarization Keychain does not exist: {keychain_path}")
        settings["NOTARY_KEYCHAIN"] = str(keychain_path.resolve())

    identity = settings["DEVELOPER_ID_APPLICATION"]
    team = settings["APPLE_TEAM_ID"]
    if team and not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("APPLE_TEAM_ID must contain exactly 10 uppercase letters or digits")
    candidates = identities()
    if identity:
        candidates = [item for item in candidates if identity == item[1] or identity.upper() == item[0].upper()]
    if team:
        candidates = [item for item in candidates if item[2] == team]
    if len(candidates) != 1:
        raise ValueError(
            "Signing identity is unavailable, does not match APPLE_TEAM_ID, or is ambiguous. "
            "Select one valid Developer ID Application identity (name or SHA-1 fingerprint) "
            "using --signing-identity or DEVELOPER_ID_APPLICATION."
        )
    _, title, selected_team = candidates[0]
    settings["DEVELOPER_ID_APPLICATION"] = identity or title
    settings["APPLE_TEAM_ID"] = selected_team
    return settings


def validate_profile(settings):
    arguments = [
        "xcrun", "notarytool", "history",
        "--keychain-profile", settings["NOTARY_PROFILE"], "--output-format", "json",
    ]
    if settings["NOTARY_KEYCHAIN"]:
        arguments += ["--keychain", settings["NOTARY_KEYCHAIN"]]
    result = command(arguments)
    if result.returncode:
        error = (result.stderr + result.stdout).lower()
        if "401" in error or "unauthorized" in error or "invalid credentials" in error:
            reason = "Apple rejected the credentials; update the existing profile with notarytool store-credentials."
        elif "no keychain password item" in error:
            reason = (
                "notarytool could not read the selected profile. Check its exact name and Keychain selection; "
                "an unreadable profile is not proof that all saved credentials are missing."
            )
        elif "locked" in error or "interaction is not allowed" in error:
            reason = "The Keychain is locked or inaccessible. Unlock it in an interactive session."
        else:
            reason = "Credential validation failed. Check Apple service/network availability and Keychain access."
        raise ValueError(reason)
    try:
        document = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise ValueError("notarytool returned invalid credential-validation output") from error
    if not isinstance(document, dict) or not isinstance(document.get("history"), list):
        raise ValueError("notarytool did not return a valid submission history")


def save(settings):
    for variable, key in KEYS.items():
        result = command(["git", "config", "--local", "--replace-all", key, settings[variable]])
        if result.returncode:
            raise ValueError(f"Could not save local release configuration ({key}): {result.stderr.strip()}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="operation", required=True)
    configure = subcommands.add_parser("configure", help="Validate and persist references in .git/config")
    configure.add_argument("--notary-profile")
    configure.add_argument("--signing-identity")
    configure.add_argument("--team-id")
    keychain = configure.add_mutually_exclusive_group()
    keychain.add_argument("--notary-keychain")
    keychain.add_argument("--default-keychain", action="store_true",
                          help="Use notarytool's default/protected Keychain, not an explicit file")
    subcommands.add_parser("show", help="Show resolved nonsecret references without contacting Apple")
    subcommands.add_parser("check", help="Check signing identity and saved credentials without packaging")
    export = subcommands.add_parser("export", help=argparse.SUPPRESS)
    export.add_argument("--validate", action="store_true")
    args = parser.parse_args()
    try:
        overrides = {}
        if args.operation == "configure":
            overrides = {
                "NOTARY_PROFILE": args.notary_profile,
                "DEVELOPER_ID_APPLICATION": args.signing_identity,
                "APPLE_TEAM_ID": args.team_id,
                "NOTARY_KEYCHAIN": "" if args.default_keychain else args.notary_keychain,
            }
        settings = resolve(overrides)
        if args.operation in ("configure", "check") or getattr(args, "validate", False):
            validate_profile(settings)
        if args.operation == "configure":
            save(settings)
            print("Release references saved in this checkout's .git/config. Credentials remain in Keychain.")
        elif args.operation == "export":
            for variable in KEYS:
                print(settings[variable])
        else:
            print(json.dumps(settings, indent=2))
            if args.operation == "check":
                print("Release credential check passed.")
        return 0
    except subprocess.TimeoutExpired:
        print("release-config: Credential/configuration check timed out; check network and Keychain access.", file=sys.stderr)
        return 1
    except (OSError, ValueError) as error:
        print(f"release-config: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
