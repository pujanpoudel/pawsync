# Release procedure

Use an Apple Developer account with Developer ID Application signing and notarytool credentials stored under a Keychain profile. Keep license-signing and Sparkle-update-signing private keys separate. The license key belongs to the backend; Sparkle's update private key belongs to protected release infrastructure.

1. Replace placeholder pet bakes and accessory/sound art. Confirm the five-part atlas contract.
2. Configure bundled `Config.json` or ignored `Config.local.json`: environment `production`, HTTPS API, 32-byte raw Ed25519 license public key in base64, all six hosted checkout URLs, optional Sentry DSN. No backend secrets go in this file.
3. Increment `CFBundleVersion` and `CFBundleShortVersionString` in `macos/Info.plist`.
4. Set `PAWSYNC_FEED_URL` to your HTTPS appcast and `PAWSYNC_SPARKLE_PUBLIC_KEY` to your Sparkle Ed25519 public key. Run `python3 scripts/build_app.py --release`.
5. Set `CODE_SIGN_IDENTITY` to your `Developer ID Application: …` identity and `NOTARY_KEYCHAIN_PROFILE` to your existing notarytool profile. Run:

```sh
python3 scripts/notarize_release.py \
  --download-url https://your-update-host/PawSync-0.1.0.zip \
  --notes-url https://your-update-host/releases/0.1.0.html \
  --sign-update-tool /path/to/Sparkle/bin/sign_update
```

The script validates production configuration and Universal architectures, signs nested Sparkle helpers/frameworks inside-out, signs the app with hardened runtime and minimum app entitlements, verifies signatures, submits to Apple, staples the ticket, assesses Gatekeeper, and finally creates an EdDSA-signed update archive and `appcast.xml`. It stops on every failure. It does not publish files. Upload the final archive and feed only after manual release acceptance.

Automatic downloads/installations are disabled for all versions. Sparkle checks on a daily schedule and uses its standard confirmation UI. The Sentry integration starts only after explicit opt-in; disable diagnostics on revocation of consent. Consider Sentry's retained crash files in your privacy/retention policy.

Network destinations are configured, never derived from a downloaded atlas: wallet/photo API, hosted checkouts opened in the default browser, Sparkle feed/archive host, and optional opt-in Sentry host. The localhost listener binds strictly to IPv4 loopback. Update delivery and optional telemetry necessarily add the network destinations required by Module G; they are exceptions to Section 3's narrower network list.

The window uses alpha-aware view hit testing **and** dynamically toggles `NSWindow.ignoresMouseEvents` outside the pet. A view returning nil alone cannot route an already-targeted window event into another application. A small SKView renders inside the display-sized transparent panel. Full-screen visibility, window-server memory and interaction must be tested on actual display configurations.

Relevant primary references: [Sparkle setup](https://sparkle-project.org/documentation/programmatic-setup/), [Sparkle signing helpers](https://sparkle-project.org/documentation/sandboxing/), [Paddle signature verification](https://developer.paddle.com/webhooks/about/signature-verification/), [Paddle adjustment events](https://developer.paddle.com/webhooks/adjustments/adjustment-created/), and [Apple Input Monitoring preflight](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess()).
