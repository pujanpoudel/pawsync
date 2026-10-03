# Verification — 2026-09-29

Built and tested on this Apple Silicon Mac using Swift 6.4 and the macOS command-line SDK. The project targets macOS 14.0.

Verified:

- Dependency-free native app compiled for arm64 and x86_64.
- Service-enabled native app compiled for both architectures with Sparkle 2.10.0 and Sentry 8.58.4, resolved by Swift Package Manager and recorded in `Package.resolved`.
- `.app` bundle embeds both dynamic frameworks and has valid nested development signatures. The binary runs native self-checks with those frameworks loaded.
- `--check-assets` passes for startup preferences, both atlases, all five rig joints, parent relationships, alpha-aware hit testing, sleep transitions, valid Ed25519 licenses, modified-token rejection and wrong-public-key rejection.
- `--check-webhook` starts the actual loopback listener; an invalid bearer token receives 401 and a valid one receives 200.
- 20 Python tests pass against an isolated real PostgreSQL cluster. Tests cover eight-way competition for the last credit, four-way duplicate generation requests, atomic rollback, failed-generation refunds and retries, expired-lease recovery, duplicate payment fulfillment, refund-before-purchase ordering, post-refund token rejection, email-code restoration, accessory ownership, signatures/replay windows, photo validation and joint-offset export.
- Python source compilation and app icon decoding pass.

The test cluster was created solely for this project; test schemas are removed after each test. It can be stopped without affecting any existing databases. One upstream Starlette warning reports the future TestClient migration from httpx to httpx2; tests pass with the locked httpx dependency.

The app is **development signed**, not Developer ID signed or notarized. Ad-hoc signing does not provide a Team ID for hardened library validation, so the development package has no hardened-runtime flag. `notarize_release.py` applies hardened runtime to the complete app and its helpers using a single Developer ID Team ID before notarization. No disable-library-validation entitlement is added.

Launch regression fixed:

- The first normal launch crashed in `Preferences.init()` because `UserDefaults(suiteName:)` was called with the app's own bundle ID and force-unwrapped. The asset-only checks had missed that initialization path.
- Preferences now use `UserDefaults.standard`, which uses the same application domain without the invalid suite initializer. Native self-checks also instantiate Preferences to cover this regression.
- The rebuilt app was launched through native UI automation. Its onboarding accessibility tree and visible window were verified successfully. Input Monitoring and optional telemetry were left for the user to choose.

Not verified:

- Complete Settings acceptance and physical pet drag/right-click gestures. UI automation cannot send clicks to the nonactivating companion panel (`noWindowsAvailable`), although it can capture the panel and interact with Settings.
- Full-screen spaces, multiple physical monitors, notch/dock placement, drag gestures and TCC permission behavior on actual macOS 14/current systems.
- The strict 0.5% idle CPU / 60 MB RAM targets. Rendering pauses and Settings views are released on close, but hardware profiling is still required.
- Live Paddle/SMTP transactions, a production license environment, hosted Sparkle updates, Sentry delivery, Apple notarization and Gatekeeper acceptance of a public release. No payment or external release was performed.
- GPU/model inference or pet identity preservation. A trained part-segmentation model and GPU deployment remain required inputs. Atlas extraction is tested independently with synthetic segmentation masks.

Before distribution, complete the manual/service checks in `releasing.md` and measure representative idle, focus, screen-off, settings-open/closed, and multi-monitor cases. The local build is intended for development evaluation.

Input and control repair:

- Replaced the display-sized overlay with a 280×260 pet panel. Ordinary clicks no longer reorder the pet window during mouse-down. This earlier build passed all input through while Settings was active; the 28 September revision below restores pet clicks outside the Settings window.
- Added independent global mouse and local mouse/key monitors. Keyboard event tap callbacks return immediately and forward only event types. Permission changes are automatically rechecked; no Accessibility request is added.
- Native UI automation verified companion selection changes, Settings navigation, physical mouse-click delivery (the aggregate click counter increased), and local keyboard delivery (the keyboard counter increased). Input Monitoring remains disabled on this Mac, so cross-app typing is not yet verified.
- Added animation preview buttons and listener status in Companion Settings. A physical click selected Shibe in the final build; the Privacy counters then showed 2 mouse clicks and 3 keyboard triggers. Unconfigured checkout buttons now surface their status in that section rather than appearing to do nothing.
- Added native checks for alternating paw actions, click head reaction, and distinct petting/blink actions. The companion screenshot visibly shows the new keyboard prop.
- The final universal build passed those native checks, reopened successfully, and both Mach-O architectures declare macOS 14.0 as their minimum OS.

Latest development revision, 27 September 2026:

- Rebuilt the native app for arm64 and x86_64 after the new wardrobe and interaction changes. The keyboard prop has been removed from the current code.
- Native asset checks now cover all nine original rigs, alternating paws, click/petting/sleep/walking actions, head-attached free accessories, earned inventory persistence and duplicate-drop prevention. These checks pass, including paid-SKU rejection by the free-hat path.
- Direct click now uses a brief click reaction; drag uses the distinct petting gesture. Clicking a pet during a reminder dismisses that occurrence. Physical nonactivating-panel gestures remain unverified.
- The landing page's JavaScript passes syntax validation, all nine unchanged atlas images exist, and its localhost route returns HTTP 200. Chrome rendered the hero and all nine companion/hat controls. Full gesture, responsive layout and animation acceptance remains outstanding; UI automation became unavailable and was discontinued at the user's request.
- The OpenPets report is approximately 5,600 words. Its inventory matches all 18 checked-out plugin manifest IDs exactly and tracks 42 feature families across eight proposed phases. The interactive canvas passes TypeScript syntax transpilation; the IDE's runtime rendering was not independently verified.
- Input Monitoring was refreshed with user approval after the earlier checks described above. Physical cross-app typing on the newest rebuilt binary has **not** been verified, so the older disabled-permission note is historical rather than the current permission assertion.
- The standalone CuaDriver was stopped and moved out of Applications to Trash at the user's request. Neither that process nor the separate Codex UI helper was running at the final process check. PawSync has no CuaDriver dependency. No further GUI automation was used.

The wider OpenPets port was approved after this historical check. No production release, purchase, provider voice upload or new Accessibility/Screen Recording/Microphone grant was performed.


## Approved expansion — native source checks, 27 September 2026

The user approved the P1–P7 plan. The universal development artifact reports `x86_64 arm64`. `--check-assets` passes nine original rigs, imported V1/V2 neutral frames and mirrored gaze, reaction mapping and per-pet presentation persistence, corrupt-state quarantine, earned inventory and signed offline licensing. `python3 scripts/check_imports.py` passes stored/deflated/folder ZIPs and rejects 13 malformed packages, with identity/locking/crash-recovery checks. Native GUI interactions and real gallery HTTP downloads have not yet been exercised in this build. No CuaDriver reinstall or GUI automation was used.

Resource implementation references Apple’s public [Mach statistics API](https://developer.apple.com/documentation/kernel/1502863-host_statistics64) and [IOPowerSources ownership rules](https://developer.apple.com/documentation/iokit/iopowersources_h), alongside the installed macOS SDK headers. Aggregate metrics do not establish PawSync’s own performance budget; Instruments acceptance remains pending.

## Current approved expansion — 28 September 2026

- All nine original pet character sheets are in both `art/character-sheets/` and the app resource bundle, including the newly generated Hamster, Otter and Capybara sheets. These are expressive references, not a claim that every pose is implemented as a rig animation.
- The latest universal development build passed `--check-assets`, `--check-companion-tools`, `scripts/check_imports.py`, `codesign --verify --deep --strict`, and `lipo -archs` reported `x86_64 arm64`. The import check rejected 13 adversarial packages.
- A read-only live gallery check fetched the OpenPets v3 index (1,304 entries), a catalog page and an original pet ZIP, then validated its atlas and package ID. It did not install a pet.
- Installed-pet enumeration now reads bounded manifest/image metadata rather than every full sprite sheet. Pet hit testing remains enabled while Settings is visible outside that window and while the pet walks; a direct click can wake virtual-care sleep.
- The binary has **not** been reopened for the newest physical cross-app typing, direct pet click/drag, Walk or Jump check. The user explicitly said they had not reopened it yet. Idle CPU and resident RAM remain unmeasured with Instruments.
- The 18-plugin inventory is accurate; basic P2 native equivalents are present, while the isolated plugin SDK, eight agent integrations, connected features, LAN/Teams and release acceptance in P3–P7 remain unfinished and disabled.

## Gallery and Settings repair — 28 September 2026

- Sidebar button labels now fill a rectangular hit area across each row. Visual click acceptance in the running app is still pending.
- Installed and catalog pets show asynchronously loaded thumbnails. Catalog entries have a preview sheet before installation; gallery image requests stay opt-in, bounded and restricted to the validated catalog host. V2 installed sprites use their neutral frame, column 6, instead of the first frame.
- The universal development app rebuilt successfully. `--check-assets` covers the local sprite-sheet preview decoder; `--check-catalog` fetched and decoded a real thumbnail before validating a pet ZIP. Both pass. Development signature verification and the `x86_64 arm64` architecture check pass.

## Animation and Settings verification — 29 September 2026

- The arm64 build ran `--check-assets`, `--check-companion-tools`, and `--check-motion`. The motion check rendered all nine original companions in resting, petting, walking, jumping and sleeping poses, and all six bundled OpenPets companions in neutral, waving, work, jump and failure frames. The proof sheets are `build/motion-proofs/original-motions.png` and `build/motion-proofs/openpets-motions.png`.
- The motion check tests exact authored frame durations and finite-cycle completion, render suspension, static V2 neutral behavior, interrupted joint action settling, and aggregate activity persistence after 700 input triggers. An image review exposed wrong Clover eyelid color and Pudding eye positions; those are corrected in the final source. The latest source also adjusts Peaches' eyelid color.
- `scripts/check_imports.py` again passed, including 13 rejected malformed archives. The final universal binary reports `x86_64 arm64`, passes `codesign --verify --deep --strict`, `--check-assets`, and `--check-motion`; the rendered Peaches expression was reviewed after the last color correction.
- These checks render SpriteKit through Metal offscreen. They do not establish on-screen click/drag behavior, cross-app Input Monitoring, window placement across monitors, or the strict idle CPU/RAM targets. No CuaDriver or UI automation was installed.
- The rebuilt app was opened normally and remained running for over a minute; the system recorded a normal termination, with no new PawSync crash report. A 20-second sample with Settings open reached 71.77 MB RSS, above the 60 MB goal. The old profiler's CPU figure was a smoothed launch history, so it is not a valid idle reading; `scripts/profile_idle.py` now measures CPU-time change over the actual interval. A representative Settings-closed/screen-sleep Instruments profile and any resulting optimization are still required.
- A further universal build replaced full original-pet atlas textures with copies of the five small rendered parts. Its `--check-assets` and `--check-motion` commands pass and the resulting proof sheet was reviewed for all nine rigs. The bundle again verifies with `codesign --verify --deep --strict` and reports `x86_64 arm64`.
- A follow-up Settings-open sample after the texture change measured 48.88 MB peak RSS over 20 seconds, down from 71.77 MB in the previous build. CPU-time delta was 7.404% in that period while companion motion and Settings were active; this is not an idle-budget pass. The system sampler reported a 50.2 MB physical footprint at the sample point and a 61.8 MB peak since launch. A true quiet-idle and screen-off profile is still needed.
- The user physically tried direct click/drag, cross-app typing, Walk and Jump on that build and reported all four failing. Native diagnostics then found Input Monitoring authorization missing for the newly ad-hoc-signed build. The next code pass changes panel key eligibility, deterministic manual Walk targeting, alternate global keyboard registration, and OpenPets Buddy as the default. The offscreen real-panel test passes; physical retesting must use that newly rebuilt binary and refresh Input Monitoring if macOS reports it missing. [Apple explains](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/) that privacy grants follow code-signing requirements, and [nonactivating panels](https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded) can receive clicks without taking keyboard focus.

## Accessory and landing-page pass — 30 September 2026

- Native hats and glasses now use per-character head/eye landmarks. Original frame pets adjust those landmarks while walking and jumping; the six bundled OpenPets pets have separate profiles. The accessory slot is repositioned on each displayed frame. The free headphone indicator is drawn as vector artwork, and selecting a different accessory clears stale manual offsets. Settings offers “Recenter on my pet.”
- Offscreen Metal proof sheets at `build/motion-checks/accessory-fit.png` and `build/motion-checks/openpets-accessory-fit.png` show the wardrobe on all 15 bundled pets. Motion checks assert that walking and jumping actually move original pets' headwear. These image reviews are visual development checks, not physical click acceptance.
- The landing page has a new soft responsive visual theme, a three-scene pet feature showcase, and the same nine WebP frame sheets used by the native app. `node scripts/check_website.mjs` uses Chrome DevTools emulation to verify 1440 px desktop and 390 px phone layouts, nine gallery pets, three showcase cards, no horizontal overflow, single-column mobile hero/playground, and pet selection, dress-up/removal, and jump controls. Screenshots are saved under `build/landing-*-verified.png`.
- The app remains an ad-hoc-signed development preview. Global typing, physical click/drag, multi-monitor behavior, and the strict CPU/RAM acceptance targets still require a live test on this final build. No CuaDriver was installed or run.

## Companion controls and input repair — 3 October 2026

- Companion controls now use per-pet fur colors: paw-shaped quick actions, a stitched file pocket with native outgoing file drags, a scalloped thought cloud, and a held mini satchel. The pocket is absent when empty except during an incoming file drag.
- Double-click or double-tap opens the quick actions. Hover and a single click do not open them. A second double-click toggles them closed; choosing an action or clicking away dismisses them. Hovering over a held file pocket remains a separate action. All six menu labels use native text fields on opaque tags so desktop wallpaper cannot obscure them.
- `--check-companion-ui build/companion-ui-previews` passes double-tap dispatch, hover/single-tap exclusion, whole-button and caption hit testing, readable/unclipped labels, first-click acceptance, transparent-center pass-through, thought-bubble action dispatch, and empty held-pocket hit testing. Fifteen native previews include light and dark menu backgrounds. `--check-motion` passes the nine originals and nine fallback rigs, authored frame timing, motion interruption/settling, and render suspension. Original frame pets alternate local paw motion on typing; ordinary clicks use a brief perk/look rather than a greeting wave.
- An obsolete `build/PawSync-export.app` shared the production bundle identifier. macOS's permission “Quit & Reopen” launched that older exporter instead of the current build. It was unregistered and reversibly archived as `build/LegacyExports/PawSync-export.bundle`; the build script now retires that duplicate and registers the current `build/PawSync.app`.
- The current arm64 development build compiles and passes signature verification. It is open at the expected executable path, with Input Monitoring visibly enabled after refreshing the existing authorized grant. The final automated cross-app text test did not increment its counters, so it is not evidence of physical global-input acceptance. The computer-use tool cannot click the nonactivating overlay (`noWindowsAvailable`); physical double-tap, click/drag and cross-app typing acceptance remain manual checks. CPU/RAM and notarized release acceptance remain pending.

## Expressions and temporary file pocket — 4 October 2026

- All 31 public Paw-Paw Season 1/2 preview varieties are present locally, alongside six existing OpenPets imports and nine PawSync originals. Public previews remain attributed to Paw-Paw, with unchanged sources and per-file URL/hash provenance. The paid Studio Spoon collection is excluded. These are reference/development assets, not an assertion of commercial redistribution rights.
- `--check-emotions build/emotion-character-sheets` passed for 46 companions × ten states, receive/catch/hold/cancel, held/empty hit targets and nine custom/fallback rigs. The nine originals use newly generated two-pose arms-open/cupped-hand art. An image review corrected facial landmarks for masked animals and the sheltie, where dark masks/paw pads had been mistaken for eyes.
- `--check-motion build/motion-proof`, `--check-companion-ui build/companion-ui-proof`, and `--check-assets` passed on the current source. This includes alternating typing paws, varied finite mouse reactions, original walking/jumping, interruption settling, frame suspension, double-tap-only menu activation, readable full-menu hit targets and thought-bubble actions.
- `--check-file-pocket` passed using disposable fixtures: exact filenames/URLs, no persistent copies, same-name files in different folders, duplicate/self-drop rejection, cancelled versus completed drag-out, originals surviving release/clear, preservation of earlier copied files, empty restart, and large/missing originals. The pocket now holds only session-local original URLs; it does not copy, rename, move or delete source files. Earlier UUID-prefixed copies remain recoverable under Advanced → Companion tools.
- The contact-sheet/resource bundle is `build/PawSync-expressive-pets.zip`. Generated sources, precise prompts, baked PNGs, landmarks, native procedural renderer and asset provenance are documented in `docs/expressive-pet-packs.md`.
- These checks are native offscreen render/dispatch and file-lifecycle checks. They do not prove operating-system drag-out acceptance, physical cross-app input or Instruments CPU/RAM acceptance; those remain separate live checks.
- The final universal development build reports `x86_64 arm64` and passes strict signature verification. The updated `--check-companion-ui` passes Clear all hit testing/dispatch and renders 36 previews, including the stitched chat cushion on dark backgrounds and pet-specific palettes. The former large satchel indicator is replaced by a small heart-sealed note; Clear all releases session references and never deletes originals.

## Softer eye expressions — 4 October 2026

- Removed the oversized white sclera rings from the shared surprise/file-receive expression. Dark bead eyes with small warm highlights now retain the companion's soft appearance during clicks and catching files.
- Rebuilt the universal app and reran `--check-emotions build/emotion-character-sheets`: all 46 pets × ten expressions and file interaction transitions pass. Visually reviewed the refreshed Capybara and Hamster sheets, including surprise and arms-open states. Regenerated the complete character-sheet/resource ZIP.
- Input Monitoring refresh remains unfinished at the second macOS authentication prompt; native expression checks do not establish physical global-input acceptance.
