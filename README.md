# PawSync

Native macOS 14+ desktop companion. AppKit overlay, SwiftUI Settings, SpriteKit joint animation, a PostgreSQL-backed credit wallet, and a separate photo inference worker.

## Open the app

The built development app is at **`build/PawSync.app`**. Opening PawSync or clicking its Dock icon opens the native Library. Knight Cat is the main companion, with 47 bundled companions available in the gallery. The menu-bar utility remains available. Click reactions and typing inside PawSync work locally; grant Input Monitoring for typing in other apps. Library pages include companions, items, achievements and independent XP tracks. Companion, Progress, Reminders, Focus, Account, Privacy and About stay easy to find; detailed tools remain under Advanced.

The bundled configuration is an explicit development preview. It unlocks local companion features for development, uses placeholder cat/Shibe atlases, and does not pretend that payments or real-photo generation are configured. Production configuration requires a valid purchased license; unlicensed users receive a ten-minute static companion preview.

```sh
cd /Users/pujan/PawSync
python3 scripts/build_app.py --universal   # offline development build
python3 scripts/build_app.py --release     # universal build with Sparkle + Sentry
```

`--release` links the service SDKs; it does **not** publish or notarize the app. It remains a development app until you supply production configuration. The release signing script rejects development configuration.

The Swift package is in `macos/Package.swift`; resolved package versions are checked in. Full Xcode is recommended for shipping. A recent command-line SDK can build the supplied scripts.

## What works locally

- A pet-sized transparent panel follows application activation, space changes, display changes, and clicks on another display. Dock, active-window, notch and free-floating anchors are available. Option-drag moves the pet; ordinary drag pets it. Transparent pixels pass clicks through to other apps. Settings remains above the pet and always receives its own clicks.
- The same JSON/PNG rig loader handles both bundled and custom pets. Breathing, tail sway, typing, click reaction, petting/blink, sleep, celebration and build-failure box animations are implemented.
- Double-clicking a pet opens its nearby quick-action menu, with one-click reminder creation, hydration, focus, movement, and pet actions. Hovering opens the pet’s pocket for files it has caught.
- Drop regular files onto the pet to hold session-only references to their original URLs and filenames. The pocket supports drag-out, Open, Show in Finder, Remove and Clear All. Releasing or clearing a file never deletes the original; the app makes no new persistent copies.
- Global keyboard input is observed through a **listen-only CGEventTap**, with work dispatched off the tap callback. Mouse input has its own global/local NSEvent monitors and works even without keyboard permission. Local key events also work inside PawSync without that permission; granting permission is rechecked automatically. The listeners use event type only, never reading key codes, strings, or keyboard flags. Mouse position is read separately in AppKit screen coordinates. Only aggregate reaction counts appear in Privacy Settings; no event contents are retained.
- Each keyboard event alternates a short paw tap, without a keyboard prop. Clicks perk the head; dragging on the pet has a separate blink and head-tilt animation.
- Pomodoro uses absolute deadlines, puts the pet to sleep during focus, and celebrates breaks. Screen sleep pauses `SKView`; idle sleep pauses after its settling animation. Idle breathing renders short bursts rather than a permanent display loop.
- Developer hooks are off by default, bind only `127.0.0.1:9876`, require a random Keychain token, limit request sizes/connections/time, and cap requests at 10/sec. The token is shown once when created or regenerated.
- License and local webhook secrets use Keychain. Preferences use standard UserDefaults, which writes to the app's bundle-ID domain. Custom rigs and display-only wallet metadata use Application Support JSON.
- Custom-photo upload validates format, dimensions and size, strips image metadata on the server, uses a 30-second request timeout, retries transient errors twice with backoff, and reuses the generation request ID. A lost successful response can be retried even when the displayed balance is zero.

All 47 bundled companions use native frame playback, with joint-based rigs available for custom photo pets. The Library adds 228 original free wearable variants, 30 permanent achievements, seven secret pairings, three-choice gifts, favorites and chosen XP tracks with live 2× XP. Headwear follows each pet’s head silhouette and authored poses; glasses use facial landmarks. Adjustments persist separately per pet/item, and dragging an item onto a pet seats it automatically. See [Library features and deployment](docs/library-features.md) for optional progress sync, content delivery, paid collections and reset behavior.

## Run the backend

PostgreSQL and Redis are required. Redis rate limits are shared across workers and fail closed when Redis is unavailable.

```sh
cd /Users/pujan/PawSync
docker compose up -d
cd backend
uv sync --locked --group dev
cp .env.example .env
uv run python -m pawsync.manage keygen
```

Copy the printed **public** key into `macos/Resources/Config.local.json` as `licensePublicKey`; keep the private PEM only on the backend. Set `LICENSE_PRIVATE_KEY_PATH=data/license-private.pem` in the backend `.env`. Management commands need the environment loaded (for example `uv run --env-file .env …`).

```sh
uv run --env-file .env python -m pawsync.manage init-db
uv run --env-file .env uvicorn pawsync.api:app --host 127.0.0.1 --port 8000 --no-proxy-headers
```

`init-db` creates the initial schema and a PostgreSQL trigger that prohibits updating or deleting the credit ledger. Take schema changes through reviewed migrations after the initial deployment. Give the runtime DB role only the permissions it needs; keep migration ownership separate.

Configure the hosted checkout URLs in the client and actual Paddle price IDs in `PADDLE_PRICE_CATALOG`. Subscribe Paddle to `transaction.completed`, `adjustment.created`, and `adjustment.updated`. The receiver verifies the raw-body HMAC with a five-second replay tolerance, resolves email from Paddle's customer API, and applies each transaction once. Raw card details never reach PawSync.

Restoration sends a one-time code through STARTTLS SMTP. An email alone never returns a license. Codes expire after ten minutes, have an attempt cap, and are consumed once. License tokens use Ed25519 and a server-side hash/session record; refunds revoke the token epoch.

For an explicit backend smoke test, `PIPELINE_MODE=demo` returns a clearly named placeholder rig. It does **not** stylize the uploaded photo. Production configuration forbids demo mode. The `dev-license` management command is also development-only and writes a restricted token file rather than printing a bearer secret.

## Real photo generation

`inference/worker.py` implements background removal using rembg/BiRefNet with alpha matting, ControlNet image-to-image cartoon styling, an ONNX part segmenter, and transparent rig export. It is intended for a private CUDA GPU service, separate from the wallet API. See [the inference contract](docs/inference.md).

**You must supply trained six-class pet-part segmentation weights.** General background removal and diffusion models do not automatically provide reliable head/body/paw/tail masks. No such trained model, model-quality claim, or real-photo generation result is fabricated in this project. The worker refuses to start without weights; the API returns a clear failure and refunds the reservation when generation fails.

Replace `macos/Resources/Pets/pixel-cat` and `shibe` with the final one-time pipeline bakes when delivered. The current PNGs are build-time procedural placeholders, explicitly allowed by the specification. `scripts/generate_placeholders.py` is content tooling only; the running app never generates default artwork.

## Tests

```sh
cd backend
TEST_DATABASE_URL=postgresql+psycopg://pawsync:pawsync@127.0.0.1:15432/pawsync \
  uv run pytest -q
cd ..
build/PawSync.app/Contents/MacOS/PawSync --check-library build/library-proof
build/PawSync.app/Contents/MacOS/PawSync --check-assets
build/PawSync.app/Contents/MacOS/PawSync --check-motion build/motion-proofs
build/PawSync.app/Contents/MacOS/PawSync --check-input-status
build/PawSync.app/Contents/MacOS/PawSync --check-webhook
```

Each PostgreSQL test creates and cleans up a uniquely named test schema. Use an isolated test database. Without `TEST_DATABASE_URL`, DB tests are explicitly skipped; SQLite is not accepted as a substitute for row-lock/concurrency tests. Native checks do not request input permission or modify Keychain.

The motion check also moves the real transparent overlay panel through a Walk and Jump arc and verifies that opaque pet pixels accept hits while empty space passes through. It does not synthesize user input. Ad-hoc development signatures change across rebuilds, so a new build may need Input Monitoring re-enabled in System Settings; `--check-input-status` reports its current authorization without reading any keys.

See [verification notes](docs/verification.md) for the checks run on this machine and the outstanding visual, hardware, and service checks.

## Ship a release

Configure production HTTPS API and checkout URLs, the license public key, and optional Sentry DSN in bundled configuration. Configure `PAWSYNC_FEED_URL` and `PAWSYNC_SPARKLE_PUBLIC_KEY` before building with `--release`. Sparkle checks daily and exposes a manual check; automatic downloading/installing is disabled, so every update uses the confirmation UI, including major versions. See [release instructions](docs/releasing.md).

This is a non-sandboxed, hardened-runtime, direct-download app. App Sandbox is explicitly false. The app's only entitlement capabilities are network client/server. Every distributable release must be Developer ID signed, notarized and stapled; the development artifact is ad-hoc signed and is **not** a notarized public release.

## External setup still required

- Production API hosting, PostgreSQL/Redis, SMTP, Paddle account/products and webhook credentials.
- GPU worker hosting, trained part-segmentation weights, and validation that styling preserves pet identity.
- Production photo-pipeline pet bakes and finished sound design (the current default companions use bundled frame art, and chimes are synthesized).
- Developer ID/notary credentials, Sparkle signing key, HTTPS appcast/archive hosting, optional Sentry project.
- Visual and multi-monitor/full-screen checks on macOS 14 and current macOS; measured CPU/RAM acceptance on Apple Silicon.

The implementation pauses rendering to minimize idle work, but the **0.5% CPU / 60 MB RAM targets are not certified** by compilation or unit tests. Use `scripts/profile_idle.py --pid <PawSyncPID>` for an initial measurement, then Instruments for production acceptance, including screen-off and Settings-closed cases.

## Landing page and earned wardrobe

The clean local page lives in [website](website/README.md), with a bottom-right pet preview and a studio using all 15 bundled sprite sheets: nine PawSync originals and six OpenPets imports. Visitors can preview the wardrobe, pet size, backgrounds, and animations. Run `python3 scripts/serve_website.py` and open `http://127.0.0.1:8767/`. The page has not been published and does not claim the development app is notarized.

The native development build includes 228 original free wearable variants, weighted three-choice gifts, locally persisted inventory, and earned pet unlocks. Existing companions remain unlocked on migration. Optional paid accessories stay independent of earned hats and generation credits. Character-specific head landmarks make accessories follow original pets through walk and jump frames; imported OpenPets pets have separate fit profiles. Functional music headphones bypass cosmetic ownership entirely. Companion Settings includes the free wardrobe and a 40–180% size slider.

The [OpenPets feature report](docs/openpets-feature-report.md) audits every maintained official/community plugin, the SDK, gallery/imports, agent paths, assistant/voice and optional LAN/Teams. The native P1–P7 implementation plan was approved; its remaining phases are tracked in [implementation progress](docs/implementation-progress.md). See [the machine-readable inventory](docs/openpets-feature-inventory.json) for tracked feature families and phases.
