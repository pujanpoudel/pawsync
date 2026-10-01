#!/usr/bin/env python3
"""Sign inside-out, notarize, staple, and produce a Sparkle-signed release zip.

Requires an already-built --release app and configured Apple/Sparkle signing identities.
It never uploads an appcast or publishes a release.
"""
import argparse
import base64
import json
import os
import pathlib
import plistlib
import subprocess
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--download-url", required=True)
    parser.add_argument("--notes-url", required=True)
    parser.add_argument("--sign-update-tool", required=True, type=pathlib.Path)
    parser.add_argument("--sparkle-key-file", type=pathlib.Path, help="Optional; omit to use Sparkle's signing key in Keychain")
    args = parser.parse_args()
    identity = os.environ.get("CODE_SIGN_IDENTITY", "")
    profile = os.environ.get("NOTARY_KEYCHAIN_PROFILE", "")
    if not identity.startswith("Developer ID Application:") or not profile:
        raise SystemExit("Set CODE_SIGN_IDENTITY to a Developer ID Application identity and NOTARY_KEYCHAIN_PROFILE to an existing notarytool profile")
    if not args.download_url.startswith("https://") or not args.notes_url.startswith("https://"):
        raise SystemExit("Distribution and release notes require HTTPS")
    app = ROOT / "build/PawSync.app"
    plist_path = app / "Contents/Info.plist"
    plist = plistlib.loads(plist_path.read_bytes())
    resources = app / "Contents/Resources"
    config_path = resources / "Config.local.json"
    if not config_path.exists(): config_path = resources / "Config.json"
    config = json.loads(config_path.read_text())
    if config["environment"] != "production" or not config["apiBaseURL"].startswith("https://"):
        raise SystemExit("Refusing to distribute a development client. Bundle production HTTPS configuration first.")
    if not plist.get("PawSyncProductionDependencies") or not plist.get("SUFeedURL", "").startswith("https://"):
        raise SystemExit("Build with --release and configure PAWSYNC_FEED_URL and PAWSYNC_SPARKLE_PUBLIC_KEY")
    try:
        if len(base64.b64decode(plist["SUPublicEDKey"], validate=True)) != 32 or len(base64.b64decode(config["licensePublicKey"], validate=True)) != 32:
            raise ValueError()
    except (KeyError, ValueError): raise SystemExit("Configure valid 32-byte Ed25519 update and license public keys")
    if not all(config["checkoutURLs"].get(sku, "").startswith("https://") for sku in ["base", "credits.5", "credits.15", "credits.40", "accessory.hat", "accessory.glasses"]):
        raise SystemExit("Configure all hosted checkout SKUs before distribution")
    architectures = subprocess.check_output(["lipo", "-archs", str(app / "Contents/MacOS/PawSync")], text=True).split()
    if set(architectures) != {"arm64", "x86_64"}: raise SystemExit("Release must be a Universal Binary")
    frameworks = app / "Contents/Frameworks"
    sparkle = frameworks / "Sparkle.framework/Versions/B"
    for relative in ["XPCServices/Installer.xpc", "XPCServices/Downloader.xpc", "Autoupdate", "Updater.app"]:
        target = sparkle / relative
        if target.exists(): run("codesign", "--force", "--sign", identity, "--timestamp", "--options", "runtime", target)
    for framework in frameworks.glob("*.framework"):
        run("codesign", "--force", "--sign", identity, "--timestamp", "--options", "runtime", framework)
    run("codesign", "--force", "--sign", identity, "--timestamp", "--options", "runtime", "--entitlements", ROOT / "macos/PawSync.entitlements", app)
    run("codesign", "--verify", "--deep", "--strict", app)  # --deep is verification only.
    release = ROOT / "build/release"
    release.mkdir(exist_ok=True)
    upload = release / "PawSync-notary.zip"
    run("ditto", "-c", "-k", "--keepParent", app, upload)
    run("xcrun", "notarytool", "submit", upload, "--keychain-profile", profile, "--wait")
    run("xcrun", "stapler", "staple", app)
    run("xcrun", "stapler", "validate", app)
    run("spctl", "--assess", "--type", "execute", "--verbose", app)
    archive = release / f"PawSync-{plist['CFBundleShortVersionString']}.zip"
    run("ditto", "-c", "-k", "--keepParent", app, archive)
    command = [str(args.sign_update_tool)]
    if args.sparkle_key_file: command += ["--ed-key-file", str(args.sparkle_key_file)]
    command += [str(archive)]
    signature = subprocess.check_output(command, text=True).strip()
    # Sparkle's sign_update prints enclosure attributes, rather than a raw signature.
    attributes = ET.fromstring(f"<enclosure xmlns:sparkle='http://www.andymatuschak.org/xml-namespaces/sparkle' {signature}/>").attrib
    namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    ET.register_namespace("sparkle", namespace)
    feed = ET.Element("rss", version="2.0")
    channel = ET.SubElement(feed, "channel")
    ET.SubElement(channel, "title").text = "PawSync updates"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"PawSync {plist['CFBundleShortVersionString']}"
    ET.SubElement(item, f"{{{namespace}}}releaseNotesLink").text = args.notes_url
    ET.SubElement(item, f"{{{namespace}}}minimumSystemVersion").text = "14.0"
    attributes.update({"url": args.download_url, "length": str(archive.stat().st_size), "type": "application/octet-stream",
                       f"{{{namespace}}}version": plist["CFBundleVersion"],
                       f"{{{namespace}}}shortVersionString": plist["CFBundleShortVersionString"]})
    ET.SubElement(item, "enclosure", attributes)
    ET.indent(feed)
    ET.ElementTree(feed).write(release / "appcast.xml", encoding="UTF-8", xml_declaration=True)
    print(f"Notarized and signed: {archive}. Appcast written beside it; publish both to your infrastructure.")


if __name__ == "__main__": main()
