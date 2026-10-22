#!/usr/bin/env python3
"""Validate the distributable, not just Xcode's intermediate app directory."""

import argparse
import hashlib
import plistlib
import subprocess
import tempfile
import zipfile
from pathlib import Path, PurePosixPath


def require(condition, message):
    if not condition:
        raise SystemExit(f"IPA verification failed: {message}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="nivqo-ipa-") as temporary:
        with zipfile.ZipFile(args.ipa) as archive:
            require(archive.testzip() is None, "ZIP data is corrupt")
            for name in archive.namelist():
                path = PurePosixPath(name)
                require(not path.is_absolute() and ".." not in path.parts, "unsafe ZIP entry")
                require(path.parts and path.parts[0] == "Payload", "unexpected top-level entry")
            archive.extractall(temporary)

        apps = list((Path(temporary) / "Payload").glob("*.app"))
        require(len(apps) == 1 and apps[0].name == "NIVQO.app", "expected one NIVQO.app")
        app = apps[0]
        with (app / "Info.plist").open("rb") as source:
            info = plistlib.load(source)

        expected = {
            "CFBundleIdentifier": args.bundle_id,
            "CFBundleShortVersionString": args.version,
            "CFBundleVersion": args.build,
            "CFBundleExecutable": "NIVQO",
            "CFBundlePackageType": "APPL",
            "DTPlatformName": "iphoneos",
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
            "UIDeviceFamily": [1],
        }
        for key, value in expected.items():
            require(info.get(key) == value, f"{key}: expected {value!r}, got {info.get(key)!r}")

        executable = app / info["CFBundleExecutable"]
        require(executable.is_file() and executable.stat().st_size > 0, "missing executable")
        architectures = subprocess.check_output(["lipo", "-archs", str(executable)], text=True).strip()
        require("arm64" in architectures.split(), f"missing arm64: {architectures}")
        require(all(arch in {"arm64", "arm64e"} for arch in architectures.split()),
                f"unexpected device architectures: {architectures}")
        primary_icon = info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {})
        require(primary_icon.get("CFBundleIconName") == "AppIcon", "AppIcon not selected")
        require(bool(primary_icon.get("CFBundleIconFiles")), "missing compiled app icons")
        require((app / "Assets.car").is_file(), "missing compiled asset catalog")
        require(any(app.glob("AppIcon*.png")), "missing packaged app icon PNGs")
        require(not list(app.rglob("_CodeSignature")), "unexpected code signature")
        require(not list(app.rglob("embedded.mobileprovision")), "unexpected provisioning profile")
        signing = subprocess.run(["codesign", "-d", str(app)], capture_output=True, text=True)
        require(signing.returncode != 0 and "not signed at all" in signing.stderr,
                f"expected unsigned app: {signing.stderr.strip()}")

    digest = hashlib.sha256(args.ipa.read_bytes()).hexdigest()
    report = (
        "NIVQO iPhone IPA verification passed\n"
        f"Bundle identifier: {args.bundle_id}\n"
        f"Version / build: {args.version} / {args.build}\n"
        f"Platform / architectures: iPhoneOS / {architectures}\n"
        "App icon: AppIcon, compiled assets and icon PNGs present\n"
        "Signing: unsigned; no provisioning profile\n"
        f"SHA-256: {digest}\n"
        "Physical-device testing: not performed by this workflow\n"
    )
    args.report.write_text(report, encoding="utf-8")
    print(report, end="")


if __name__ == "__main__":
    main()
