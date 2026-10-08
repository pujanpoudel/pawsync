# PawSync for Windows and Linux

The existing native Swift macOS application stays in `macos/`. The Windows/Linux client lives in `desktop/` and uses native Qt widgets and shaped transparent desktop windows, not an embedded website. This is a development preview, not a signed public release.

## Run from source

Install Python 3.12 and uv, then from the repository root:

```sh
uv sync --project desktop --frozen --group dev
uv run --project desktop python desktop/run.py
```

On Linux, install the Qt/XCB libraries listed in `desktop/packaging/linux/Dockerfile`. Ubuntu 22.04 or newer is the binary baseline. Windows builds target Windows 10/11 x64. ARM builds are not yet packaged.

The app opens its Library; closing that window leaves the companion and tray utility running. Double-click the tray icon to reopen the Library. The tray offers mute, hide, focus, reminders, position reset, updates and quit. Linux desktops without a tray extension can reopen the Library by launching PawSync again.

## Shared art and behavior

All 47 bundled pets, including the six OpenPets imports and Knight Cat, use the existing sprite sheets. The same 230 item images, 30 achievements, seven secret pairings, authored face landmarks, catch/hold poses and per-frame head attachment coordinates come from the macOS resources. `PortableAssetExport.swift` renders the existing native item nodes into transparent PNGs; `desktop/export_previews.py` extracts unchanged first-frame thumbnails. Default art is not regenerated at runtime.

Six Library pages contain Pets, Items, Achievements, Make your own pet, Wellness and Settings. Clicking an unlocked card chooses/equips it. The info button opens details and pet renaming. Items support search, categories, favorites and placement preview/reset/cancel. Advanced controls stay in Settings. Earned progress uses the existing backend JSON contract; optional sync unions ownership and keeps higher XP, with local backups and reset epochs. Three-choice gifts can be kept for later, worn immediately or opened together.

Typing alternates paw frames; ambient mouse clicks use brief expressions; direct clicks use an affectionate hop and encouraging phrase. Ordinary dragging pets the friend; Alt-drag moves it. Walk, jump, roam, patrol, cursor-follow, size, mirroring, anchors and explicit opacity are available. Input interrupts travel at its current position rather than sending the pet back to the corner. There is no automatic idle opacity reduction or sleep. Focus, explicit sleep and system-sleep handling are separate.

Double-click opens the nearby action buttons; hover alone does not open that menu. A file drag shows the authored receive pose. Dropped files are session-only references to original paths: no copying, renaming or persistent file folder. Hovering a loaded pet reveals its pocket; files can be dragged back out, released or cleared. Quitting forgets the pocket, leaving originals intact.

Reminder presets and editing support intervals, times of day, one-off deadlines, optional text and high priority. Ordinary reminders queue during focus. The companion approaches the center-bottom for delivery, with a pet-shaped message and snooze. Hidden delivery uses the tray notification rather than unhiding the pet. Notification presentation depends on the desktop environment.

## Platform permissions and differences

Windows uses low-level keyboard/mouse hooks. The keyboard packet is never dereferenced: only the message type triggers a reaction. Secure desktops and higher-integrity applications may prevent observation. Linux X11 uses XRecord and reads only the event-type byte, never key/button detail.

Wayland restricts global input and arbitrary overlay positioning. On desktops with XWayland the client uses Qt's XCB backend. The `.deb` includes an optional fixed-path input helper and polkit policy; enable it explicitly in Advanced to observe binary input occurrences. Only this small helper receives administrator authorization, never the GUI. It skips the key-code field and emits `K`/`M` labels only. Authorization is not automatic or retained. This is not a claim of unrestricted Wayland support: stacking, full-screen surfaces, workspaces and window-edge traversal remain compositor-dependent. X11 is the fully testable Linux path.

The X11 overlay requests all workspaces via EWMH. Windows workspace pinning is controlled by the OS; the client does not use undocumented virtual-desktop APIs. Active-window anchors use the available platform window geometry. macOS-only ScreenCaptureKit, Sparkle and Sentry wiring are not reused as if they existed on Windows/Linux.

Music detection is opt-in WASAPI loopback on Windows or a PulseAudio/PipeWire loopback monitor on Linux. Buffers are reduced to energy/onset signals in memory and discarded. Headphones are a free functional visual and bypass accessory ownership. No microphone fallback, audio file, transmission or private MediaRemote API is used. Hardware/desktop audio compatibility still needs testing on real Windows and Linux machines.

## Accounts and generation

License, provider and local hook tokens go only into Windows Credential Manager or Linux Secret Service/KWallet. Plaintext keyring backends are rejected. A valid signed license permits offline local features; an explicit rejection revokes the cached session. Transient network failures preserve offline access. Production requires a configured HTTPS backend, signing public key and checkout URLs; the bundled configuration is clearly marked development and does not invent purchases or credits.

The existing PostgreSQL/Paddle backend remains the source of truth for credits and entitlements. Cloud requests have 30-second timeouts, bounded retries and a stable generation request ID for retrying a lost response. Direct-provider image requests use Gemini, OpenAI or Grok keys sent only to that chosen provider, validate photos locally, strip EXIF metadata, stage five rig parts and require a preview/Keep step. They are not automatically retried because a timeout may still incur a provider charge. Live provider/payment transactions have not been exercised without credentials.

Developer hooks are opt-in and bind `127.0.0.1:9876` only. Bearer authentication, bounded bodies, connection timeouts and a five-request/second cap precede animation dispatch. Tokens are shown only at creation/regeneration. The copied curl template contains a placeholder, not a secret.

The update action opens GitHub Releases. It does not silently download or install an unsigned executable. Optional connected OpenPets Phase 5 modules remain disabled, as in the native app. This preview does not claim every future integration, auto-update mechanism, crash-reporting transport or macOS CPU/RAM target is already portable and verified.

## Build and checks

```sh
uv run --project desktop python -m pytest desktop/tests -q
uv run --project desktop python scripts/build_desktop.py
```

Build on the target OS. Linux produces `desktop/dist/PawSync-0.3.0-linux-amd64.deb` and a portable `.tar.gz`; Windows produces an `.exe` application folder and `.zip`, then `ISCC desktop/packaging/windows/installer.iss` produces a per-user installer. Dependency licenses and replaceable Qt shared libraries ship with each bundle. Release configuration can be supplied through `PAWSYNC_RELEASE_CONFIG`; neither signing credentials nor live API secrets belong in the repo.

The GitHub workflow builds/tests on Windows and Ubuntu independently and uploads preview installers. Tests cover progress persistence/merging, gifts collected once, queued one-off reminders, original file references, real drag/drop events, direct/double clicks, rabbit jump poses, stationary input reactions, asset completeness and authenticated loopback limits. `PAWSYNC_TEST_GLOBAL_INPUT=1` additionally exercises real Windows/X11 input occurrences. `desktop/test_linux_runtime.py` tests shaped-window routing and double-clicks with an external X11 client. Screenshots come from the actual Qt UI.

The Qt preview has not yet met the native macOS RAM target of 60 MB; do not transfer the Swift app's resource claims to this port. Idle rendering stops rather than running an unconditional 60-fps loop. Measure packaged idle/active usage on target hardware before a public performance claim.

### Interaction polish

Drag the companion normally to reposition it. Releasing a horizontal drag sends it walking a further bounded distance in that direction; typing still stops it in place. Click reactions keep the body upright, and open-eye emotions retain the original illustrated eyes. Knight Cat has a dedicated two-paw cheer pose. Active shared-client animation runs at 30 fps, facial landmarks are cached, and hidden Library pages do not rebuild on state changes. Performance budgets still need measurement on Windows and Linux hardware.
