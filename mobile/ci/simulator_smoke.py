#!/usr/bin/env python3
"""Launch the initial home screen and capture it; this is not an interaction test."""

import argparse
import json
import subprocess
import time
from pathlib import Path


def simctl(*arguments, timeout=60):
    return subprocess.check_output(["xcrun", "simctl", *arguments], text=True, timeout=timeout).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    inventory = json.loads(simctl("list", "--json"))
    runtimes = [runtime for runtime in inventory["runtimes"]
                if runtime.get("isAvailable") and ".iOS-" in runtime["identifier"]]
    runtimes.sort(key=lambda runtime: tuple(int(part) for part in runtime["version"].split(".")), reverse=True)
    preferred = ["iPhone SE (3rd generation)", "iPhone 16", "iPhone 17", "iPhone 16e", "iPhone 15"]
    candidates = []
    for runtime in runtimes:
        for device in inventory["devices"].get(runtime["identifier"], []):
            if device.get("isAvailable") and device["name"].startswith("iPhone"):
                rank = preferred.index(device["name"]) if device["name"] in preferred else len(preferred)
                candidates.append((rank, runtime, device))
    if not candidates:
        raise SystemExit("No available iPhone simulator/runtime is installed on this runner")
    # The stable sort prefers the newest runtime when the device type is equal.
    _, runtime, template = sorted(candidates, key=lambda candidate: candidate[0])[0]
    device_type = template.get("deviceTypeIdentifier") or next(
        item["identifier"] for item in inventory["devicetypes"] if item["name"] == template["name"]
    )
    device = simctl("create", "NIVQO CI home screen", device_type, runtime["identifier"])
    try:
        simctl("boot", device)
        simctl("bootstatus", device, "-b", timeout=240)
        simctl("status_bar", device, "override", "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100")
        simctl("install", device, str(args.app.resolve()))
        launch = simctl("launch", "--terminate-running-process", device, "dev.nivqo.iphone")
        # Allow the initial SwiftUI home page to render before checking survival.
        time.sleep(5)
        processes = simctl("spawn", device, "launchctl", "list")
        app_processes = [line.split() for line in processes.splitlines() if "dev.nivqo.iphone" in line]
        if not any(fields and fields[0].isdigit() and int(fields[0]) > 0 for fields in app_processes):
            raise SystemExit("The app exited before the simulator home-page capture")
        screenshot = args.output / "iphone-home.png"
        simctl("io", device, "screenshot", str(screenshot.resolve()))
        if not screenshot.is_file() or screenshot.stat().st_size == 0:
            raise SystemExit("Simulator screenshot was not created")
        report = (
            "Simulator home-page launch passed\n"
            f"Device: {template['name']}\n"
            f"Runtime: {runtime['name']}\n"
            f"Launch result: {launch}\n"
            "App remained running through the initial home-page screenshot.\n"
            "This check does not test taps, scrolling, keyboard layout, web\n"
            "content recovery, website challenges or any physical iPhone.\n"
        )
        (args.output / "SIMULATOR-SMOKE.txt").write_text(report, encoding="utf-8")
        print(report, end="")
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", device], check=False, timeout=60)
        subprocess.run(["xcrun", "simctl", "delete", device], check=False, timeout=60)


if __name__ == "__main__":
    main()
