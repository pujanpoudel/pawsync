#!/usr/bin/env python3
"""Build a real .app using the command-line SDK; --release links Sparkle and Sentry."""
import argparse
import os
import pathlib
import plistlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
LSREGISTER = pathlib.Path("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")


def run(*args, cwd=ROOT):
    subprocess.run([str(a) for a in args], cwd=cwd, check=True)


def retire_legacy_export():
    """An old asset-export app must never shadow the real app in LaunchServices."""
    duplicate = ROOT / "build/PawSync-export.app"
    info = duplicate / "Contents/Info.plist"
    if not info.exists():
        return
    bundle_id = plistlib.loads((ROOT / "macos/Info.plist").read_bytes())["CFBundleIdentifier"]
    if plistlib.loads(info.read_bytes()).get("CFBundleIdentifier") != bundle_id:
        return
    if LSREGISTER.exists():
        subprocess.run([str(LSREGISTER), "-u", str(duplicate)], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    archive = ROOT / "build/LegacyExports"
    archive.mkdir(exist_ok=True)
    destination = archive / "PawSync-export.bundle"
    suffix = 1
    while destination.exists():
        destination = archive / f"PawSync-export-{suffix}.bundle"
        suffix += 1
    shutil.move(str(duplicate), destination)
    print(f"Archived obsolete duplicate app to {destination}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--universal", action="store_true")
    parser.add_argument("--release", action="store_true")
    args = parser.parse_args()
    retire_legacy_export()
    app = ROOT / "build/PawSync.app"
    macos = app / "Contents/MacOS"
    macos.mkdir(parents=True, exist_ok=True)
    resources = app / "Contents/Resources"
    shutil.copytree(ROOT / "macos/Resources", resources, dirs_exist_ok=True)
    shutil.copy2(ROOT / "macos/Info.plist", app / "Contents/Info.plist")
    plist_path = app / "Contents/Info.plist"
    plist = plistlib.loads(plist_path.read_bytes())
    plist["PawSyncProductionDependencies"] = args.release
    if args.release and os.environ.get("PAWSYNC_FEED_URL"):
        plist["SUFeedURL"] = os.environ["PAWSYNC_FEED_URL"]
        plist["SUPublicEDKey"] = os.environ.get("PAWSYNC_SPARKLE_PUBLIC_KEY", "")
    plist_path.write_bytes(plistlib.dumps(plist))
    if args.release:
        command = ["swift", "build", "-c", "release", "--arch", "arm64", "--arch", "x86_64"]
        run(*command, cwd=ROOT / "macos")
        bin_path = pathlib.Path(subprocess.check_output(command + ["--show-bin-path"], cwd=ROOT / "macos", text=True).strip())
        shutil.copy2(bin_path / "PawSync", macos / "PawSync")
        frameworks = app / "Contents/Frameworks"
        frameworks.mkdir(exist_ok=True)
        linked = subprocess.check_output(["otool", "-L", str(macos / "PawSync")], text=True)
        for name in ["Sparkle", "Sentry"]:
            if f"{name}.framework/" not in linked: continue
            candidates = list((ROOT / "macos/.build/artifacts").rglob(f"{name}.framework"))
            candidates = [p for p in candidates if p.parent.name.startswith("macos-") and "dSYMs" not in p.parts]
            if name == "Sentry": candidates = [p for p in candidates if "Sentry-Dynamic" in p.parts]
            if candidates: run("ditto", candidates[0], frameworks / candidates[0].name)
        for bundle in bin_path.glob("*.bundle"):
            shutil.copytree(bundle, resources / bundle.name, dirs_exist_ok=True)
        run("install_name_tool", "-add_rpath", "@executable_path/../Frameworks", macos / "PawSync")
        sparkle = frameworks / "Sparkle.framework/Versions/B"
        for relative in ["XPCServices/Installer.xpc", "XPCServices/Downloader.xpc", "Autoupdate", "Updater.app"]:
            target = sparkle / relative
            if target.exists(): run("codesign", "--force", "--sign", "-", "--options", "0", target)
        for framework in frameworks.glob("*.framework"):
            run("codesign", "--force", "--sign", "-", "--options", "0", framework)
    else:
        sources = sorted((ROOT / "macos/Sources/PawSync").glob("*.swift"))
        sdk = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
        arches = ["arm64", "x86_64"] if args.universal else [subprocess.check_output(["uname", "-m"], text=True).strip()]
        binaries = []
        for arch in arches:
            output = ROOT / "build" / f"PawSync-{arch}"
            run("xcrun", "swiftc", "-swift-version", "5", "-O", "-sdk", sdk, "-target", f"{arch}-apple-macosx14.0", *sources, "-o", output)
            binaries.append(output)
        if len(binaries) == 2: run("lipo", "-create", *binaries, "-output", macos / "PawSync")
        else: shutil.copy2(binaries[0], macos / "PawSync")
    # An ad-hoc identity has no Team ID, so hardened library validation cannot
    # authorize its third-party frameworks. Developer ID release signing in
    # notarize_release.py enables runtime on every executable with one Team ID.
    run("codesign", "--force", "--sign", "-", "--options", "0", "--entitlements", ROOT / "macos/PawSync.entitlements", app)
    run("codesign", "--verify", "--strict", app)
    if LSREGISTER.exists():
        subprocess.run([str(LSREGISTER), "-f", str(app)], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"Built {app} ({'release dependencies' if args.release else 'offline development preview'})")


if __name__ == "__main__": main()
