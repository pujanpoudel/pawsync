# PawSync: OpenPets feature audit and implementation proposal

Prepared 27 September 2026. **The native macOS P1–P7 plan was approved on 27 September 2026.** This is a source audit and a proposed native port, not a claim that feature parity has been delivered.

## Recommendation and scope

Keep PawSync native: AppKit windows, SwiftUI controls, SpriteKit animation, macOS 14+, universal binaries, direct distribution, hardened runtime and notarization. Port OpenPets behavior and its public contracts into that architecture, preserving MIT notices when code is reused. OpenPets is an Electron/TypeScript application; copying its application files into Swift would not produce a working native app.

The requested expansion covers the desktop companion, pet catalog and imports, motion and multi-pet assignment, every maintained official/community plugin, the plugin SDK and author tools, agent integrations, AI chat and voice, remote control, experimental LAN features, Teams, and operational tooling. Windows/Linux packaging is recorded separately because it requires additional platforms beyond the macOS product you requested.

Paw-Paw supplies the visual and interaction direction. The approved commercial decision is **earned pets and free hats, with optional paid accessory packs**. Retain the one-time base license and custom-generation credits. Functional dancing headphones remain free and explicitly bypass accessory ownership.

A literal Electron fork is an alternative if running all existing JavaScript plugins unchanged matters more than native architecture. It changes the original stack and makes the 60 MB memory target especially uncertain. I recommend the native port, with compatibility tests rather than a promise of immediate drop-in plugin support.

## Evidence and limits

The audited checkout is `vendor/openpets`, pinned to commit **0145a86524cf8528701f44bbb6897fd9ce658612**, dated 25 September 2026. Both source submodules were initialized for inspection: System Resources at `091439770e2f0bb6b571bb50263514837928e911`, Usage Buddy at `962bc7ee6a19dc5d05c8c6c07cfeca75dd0c0035`. No upstream application or plugin was executed for this audit.

Primary evidence is the checked-out code, plugin manifests, package contracts and maintained documentation. Relevant pinned references:

- [Architecture](https://github.com/OpenPetsHQ/openpets/blob/0145a86524cf8528701f44bbb6897fd9ce658612/docs/architecture.md), [Desktop](https://github.com/OpenPetsHQ/openpets/blob/0145a86524cf8528701f44bbb6897fd9ce658612/docs/desktop.md), [IPC](https://github.com/OpenPetsHQ/openpets/blob/0145a86524cf8528701f44bbb6897fd9ce658612/docs/ipc.md).
- [Pets and import contracts](https://github.com/OpenPetsHQ/openpets/blob/0145a86524cf8528701f44bbb6897fd9ce658612/docs/pets.md), [Catalog](https://github.com/OpenPetsHQ/openpets/blob/0145a86524cf8528701f44bbb6897fd9ce658612/docs/catalog.md).
- [Plugin platform](https://github.com/OpenPetsHQ/openpets/blob/0145a86524cf8528701f44bbb6897fd9ce658612/docs/plugins.md), [SDK](https://github.com/OpenPetsHQ/openpets/blob/0145a86524cf8528701f44bbb6897fd9ce658612/docs/sdk.md), [Official and community lineup](https://github.com/OpenPetsHQ/openpets/blob/0145a86524cf8528701f44bbb6897fd9ce658612/docs/official-plugins.md).
- [Agent integrations](https://github.com/OpenPetsHQ/openpets/blob/0145a86524cf8528701f44bbb6897fd9ce658612/docs/agent-integrations.md), [LAN](https://github.com/OpenPetsHQ/openpets/blob/0145a86524cf8528701f44bbb6897fd9ce658612/docs/lan-mode.md), [Localization](https://github.com/OpenPetsHQ/openpets/blob/0145a86524cf8528701f44bbb6897fd9ce658612/docs/i18n.md).
- [Actual bundled plugin defaults](https://github.com/OpenPetsHQ/openpets/blob/0145a86524cf8528701f44bbb6897fd9ce658612/apps/desktop/src/bundled-plugins.ts), [Actual app preferences](https://github.com/OpenPetsHQ/openpets/blob/0145a86524cf8528701f44bbb6897fd9ce658612/apps/desktop/src/app-state.ts), [MIT license](https://github.com/OpenPetsHQ/openpets/blob/0145a86524cf8528701f44bbb6897fd9ce658612/LICENSE).

The public pet-catalog snapshot already downloaded into `build/openpets-catalog.json` contains 1,304 entries across 14 pages. This is a dated snapshot, not a guaranteed permanent count or proof every pet is redistributable. The repository's default companion is Hoodie Cat V2; the entire online gallery is not baked into its source repository. A `web/` tree mentioned by documentation is absent from this pinned checkout. Public gallery infrastructure and the complete organization backend cannot be treated as inspected, available source.

Documentation has drift: the README's plugin list is shorter than the maintained 13-official/5-community lineup; Launch Buddy is implemented as greetings, not an application launcher. Agent docs describe a disabled pool default in one place, while `app-state.ts` initializes `petPoolEnabled: true`. For PawSync I propose an opt-in multi-agent pool to preserve the light default companion.

Current PawSync status below means code exists, partial code exists, or work is new. It does not substitute for runtime verification. The newest movement/audio changes have compiled previously but physical movement, cross-app keys and multi-monitor behavior remain acceptance checks. Production payments, inference hosting, notarization and update delivery need external setup.

## Current PawSync baseline

- AppKit transparent companion panel and SwiftUI Settings; SpriteKit skeletal rigs and a frame-sheet adapter. Settings click routing, local typing, and aggregate mouse reactions were verified in earlier UI work.
- Nine original illustrated companions: Maple, Mochi, Ember, Clover, Cocoa, Bao, Peaches, Pebble and Pudding. Six previously imported OpenPets sample companions are bundled; this is not the full gallery. Six original character sheets exist; sheets for the newest three are still outstanding.
- Binary global input event observation; input types and separate cursor coordinates only. Input Monitoring was refreshed with your authorization; a final test of cross-app keyboard reactions on the newest binary remains pending.
- Idle, typing, click, petting, sleep, celebration and failure reactions; no keyboard prop in the latest code. Pet size, locomotion, deliberate jump, cursor look, music state and free headphone code exist but need the manual tests described below.
- Friendly speech bubbles, greetings, local reminders and chore creation, recurring schedules, snooze, focus suppression, high priority and optional system notifications. Focus and screen sleep are separate render-pause paths.
- A token-authenticated loopback build-status listener. This is not OpenPets MCP, its richer IPC protocol or a general plugin runtime.
- Local aggregate activity and XP. Following your newest approval, a native earned wardrobe was added and passes code checks: six original vector hats, weighted drops without duplicates, local JSON inventory, pet unlock levels and preservation of existing pets. Paid accessories remain a separate server-authorized path.
- API/upload validation, retry and timeout code; PostgreSQL wallet ledger and credit reservation recovery; signed offline license validation and Keychain secrets. The recorded earlier verification includes 20 real PostgreSQL tests. No live purchase or production photo generation is claimed.
- Sparkle/Sentry integration and release scripts exist. The local development artifact is ad-hoc signed; public release signing, notarization, hosted feed and measured CPU/RAM acceptance remain outstanding.

The latest Paw-Paw-inspired website is separate from the native app. Its playable demo reacts only inside the browser; it cannot establish that global native input or desktop locomotion works.

## 1. Desktop shell and companion behavior

Port the tray-first utility, single-instance handling and one Control Center window. A second launch should focus the existing control window instead of creating a duplicate app. Supply Dashboard, Pets, Settings, Plugins, Integrations and optional Teams routes. Preserve PawSync's Reminders, Focus, Wallet and Privacy sections.

Add durable show/hide and pause behavior, default-pet-on-launch preference, all-pet controls and consistent restoration after sleep, spaces, full-screen transitions and monitor changes. Differentiate a user's manual hide from a temporary close caused by display/window changes. Keep the pet nonactivating and transparent; the pet and bubbles may receive direct gestures, while transparent areas must pass through. Recheck routing after dragging and window lifecycle changes.

Provide a live pet context menu with state-sensitive root controls and plugin submenus. Commands should appear only when applicable: pause/resume, current timer actions, snooze/done, feed/play, movement controls and settings. Implement horizontal flip per pet; no invented vertical-flip option. Upstream scale presets span 0.35–1.25 and independently scale HUDs. PawSync's continuous 40–180% slider can stay, with compatible presets and HUD scale added.

Implement configurable reaction-to-animation mappings. Upstream categories include thinking, working, editing, running, testing, waiting, review, success, error, celebration and idle. Distinguish looping busy states from bounded one-shot success/error actions. The waiting cycle has normal and relaxed timing. Let users preview mappings and restore defaults. A status badge should remain truthful after its short explanatory bubble disappears.

Use one presentation coordinator for transient bubbles, pinned status, actionable alerts, images, plugin HUDs, voice indicators and deliveries. The pinned HUD supports up to four metrics with priority handling rather than stacking competing panels. Opening chat should suppress duplicate chat bubbles. Calendar couriers come from declared, trusted sprite descriptors, with bounded queues per display and reduced-motion support.

Add on-pet Chat/Talk buttons as optional controls, independently configurable size/corner; keep them off by default. Add show/hide and Talk shortcuts with collision detection and safe rollback when replacement registration fails. System/light/dark themes, accessible labels and keyboard navigation belong to the Control Center; they must not steal global typing from other applications.

Add versioned, atomic state files, bounded local activity summaries and dashboard health: installed pets, active plugins, errors, integrations and update status. Quarantine corrupt files instead of silently overwriting valuable state. Introduce rotating, redacted diagnostic logs and an Open Logs action, never keystrokes, audio buffers, prompts, provider credentials or bearer tokens.

**PawSync gap:** the panel, settings, aggregate activity and basic bubbles already exist. Multi-pet shell, richer reaction maps, presentation arbitration, dashboard, shortcuts and plugin-aware context menus are new. Reliability fixes precede these additions.

## 2. Pet catalog, installation and formats

Provide searchable gallery pages, categories/subcategories, original/featured filters and installed status. Support catalog v3 first, v2 fallback and a small offline fixture when networking fails. Allow explicit valid pet IDs even when they are not currently featured. Download on demand rather than loading 1,304 atlases into RAM or blindly baking them into the app.

Support install, remove, set default, animation preview and provenance details. Broken pets should fall back to a known companion with a clear message. Gallery assets, user imports, Codex-imported pets and organization pets require separate source labels and ownership rules. Import from `~/.codex/pets` without modifying that directory.

Upstream sprite formats are distinct from PawSync's five-part JSON rig:

- V1: unmarked 8-column, 9-row sheets, with minimum frame dimensions of 192×208.
- V2: marker `spriteVersionNumber: 2`, exact 1536×2288 transparent WebP, 8 columns and 11 rows. Neutral idle uses row 0, column 6; the additional rows hold 16 cursor-gaze directions.
- Reject unknown versions, unsafe IDs, bad transparency/dimensions or incompatible metadata. Keep native skeletal pets and frame pets behind one animation contract.

Port ZIP and folder imports with validation before committing assets. The current package contract is `pet.json` plus `spritesheet.webp`, at the root or one enclosing directory. Reject traversal, symlinks, encryption, case collisions and decompression bombs. Retain limits for download/extracted bytes, file count and individual files. Use staging, atomic rename, backups and a crash-recovery journal; do not claim power-loss durability from rename alone. Fence ambiguous per-pet recoveries rather than merging damaged installations.

The standalone install CLI should prefer the running app's private IPC. A direct installer needs an interprocess lock, bounded stale-lock recovery and the same validators. Organization artifacts must never overwrite an unrelated personal pet. Native asset loading must use controlled roots and bounded decoding instead of copying Electron asset protocols literally.

**Art/content boundary:** preserve OpenPets MIT notices for its code and licensed bundled material. Inspect individual catalog provenance before redistribution; some recognizable third-party characters need a separate rights review. “All pets supported for user installation” is different from “all art owned and shipped by PawSync.” Paw-Paw's artwork and app internals are not provided as reusable source.

## 3. Motion, cursor reactions and multiple companions

OpenPets centralizes window position changes through one motion owner and a shared ticker. Port that ownership discipline, fractional-coordinate handling, gravity, bounce, display clamping and cancellation. Do not let active-window tracking, drag, roam and jump independently fight over the same window origin.

Walkabout supplies wander, cursor following and patrol, with speed/interval controls and pause-while-busy. PawSync has bottom-edge roaming and explicit arced jumps; keep those deliberate jumps as the native behavior requirement. Upstream gravity/bounce does not prove window-edge climbing works. Cursor gaze should be short-lived, throttled and suppressed during busy actions, drag, movement overrides or sleep.

Store positions by display, clamp after unplug/resolution changes and avoid crossing gaps between nonadjacent screens. Cross-display roaming is off by default upstream and should remain optional. Follow the active display for the primary pet as originally specified.

Multi-agent pets need a deterministic ordered pool, healthy installed pet selection, session leases, short heartbeats, terminal PID binding and liveness cleanup. First lease opens its pet; final release closes it. Explicit targets take priority. Confinement to the owning terminal/window takes priority over cross-display roaming. This needs Accessibility only for window geometry, requested lazily; denial should leave a functional screen-edge fallback. Handle hidden, disconnected and terminated owners without orphan pets.

Screen sleep suspends render and audio work. Hidden pets should unload or throttle expensive work. Preserve the idle CPU/RAM targets as measured acceptance criteria, not an assumption. Benchmarks must include one idle companion separately from multiple animated pets, settings, plugins, voice and active music.

## 4. Every maintained plugin

The maintained catalog contains **13 official and 5 community plugins**. Eight official plugins are bundled; six are initially enabled. Saved enablement wins on upgrade. Community plugins are never silently installed or enabled. Native equivalents should share PawSync's existing reminder/focus engines, avoiding duplicate timers and duplicate nudges.

### Official plugins

1. **Quick Reminders — `openpets.reminders`** (bundled, enabled). Custom and quick 15/30/60-minute reminders; pending list/cancel/clear; due and missed alerts; snooze/done, optional sound/system notification, restart reconciliation. Assistant operations create/list/complete/snooze/remove. Absolute assistant dates need explicit timezone handling. PawSync has a useful baseline, but missed-event reconciliation and typed assistant capabilities need parity work.
2. **Simple Timer — `openpets.simple-timer`** (bundled, enabled). Preset and custom countdowns, pinned HUD, pause/resume, +5 minutes, cancel and show; expiry snooze/dismiss, persisted deadline, sound and notification. This is distinct from Pomodoro and recurring reminders. New native domain.
3. **Anxiety Aid Tools — `openpets.anxiety-aid-tools`** (bundled, enabled). Guided paced breathing, muscle relaxation, grounding, meditation, peaceful visualization and layered relaxing sounds, with practice controls. Narration/media downloads are on demand from its declared host. Reusing text/media needs attribution/provenance checks; present as optional wellness practices, without importing unsupported treatment claims. New native practice-session UI and media cache.
4. **Focus Buddy — `openpets.focus-buddy`** (bundled, enabled). Focus/break durations, break style, progress HUD, pause/resume/end/skip break, persistent state and sounds. Six typed assistant operations. PawSync Pomodoro needs pause/resume, richer HUD and command parity.
5. **Launch Buddy — `openpets.launch-buddy`** (bundled, enabled). Time-aware, custom or random greetings; every launch/once daily/after-away policies, delay, reaction and sound settings; greet/reset. Assistant `launch.greet`. Current source is a greeter, not an arbitrary app/folder launcher. PawSync greetings need these policies.
6. **Daily Fortune Cookie — `openpets.fortune-cookie`** (bundled, enabled). Scheduled daily fortune, deterministic fortune of the day and manual another-fortune action, with local persistence. New native feature.
7. **Virtual Pet — `openpets.virtual-pet`** (bundled, disabled). Hunger, affection, energy and bond state, elapsed-time decay, feed/play/pet/nap, pinned status HUD and persistent needs. Typed assistant status/feed/play/pet/nap. New; activity XP is not an implementation of these needs.
8. **System Resources — `openpets.system-resources`** (bundled, disabled; separate MIT submodule). Aggregate CPU/RAM and optional GPU/system-volume usage; four-item HUD, optional battery/network rates, threshold alerts, cooldowns and fresh-sample checks. Metrics do not expose process/app/device identities. Assistant get/show/hide. Yield pinned presentation to higher-priority interactions. New native probes; availability must be honest on each Mac.
9. **Calendar Airmail — `openpets.calendar-airmail`** (installable). Google OAuth PKCE, read-only primary-calendar sync, connect/disconnect/test, upcoming-event reminders and a selected animated courier. Requires user OAuth setup and declared Google endpoints. New connected feature; no access to calendar until enabled and authorized.
10. **Morning & Evening Routine — `openpets.day-routine`** (installable). Configured times/day toggles, once-daily greetings, manual morning/evening delivery and pause today. Partial overlap with greetings/reminders; new routine policy.
11. **Magic 8-Ball — `openpets.magic-8-ball`** (installable). Optional locally entered question, random answer, quick answer and last-answer state. It is a local toy, not a paid AI call. New native feature.
12. **Mood Check-in — `openpets.mood-check-in`** (installable). Scheduled interactive four-feeling check-in, local history/summary and pause today. Personal mood data remains local; it must not automatically flow to Teams. New native feature.
13. **Water Reminder — `openpets.water-reminder`** (installable). Configurable cadence, drank-water action, pause today, preview and sound. PawSync hydration reminders exist; acknowledgment and day-pause behavior need parity.

### Community plugins

14. **Walkabout — `openpets.walkabout`**. Wander/follow/patrol with speed, interval, busy-pause, multi-pet/display events and power handling. PawSync motion exists in development; patrol and full host contracts are new.
15. **Spotify Buddy — `openpets.spotify-buddy`**. Spotify OAuth/client configuration, playback polling/control, track announcements, mood reactions, lyric display with timing offset and pause policy. Declares Spotify and lyric-service hosts. This is separate from generic system-audio dancing. External provider configuration and network-write approval are needed; no automatic reuse of private account credentials.
16. **Vocabulary Drag & Drop — `openpets.drag-vocab`**. Explicitly dropped text produces definitions/translations in a scrollable HUD; language/provider settings and optional Anki deck integration. Dictionary/translation hosts and optional loopback `127.0.0.1:8765` writes require distinct consent. This does not authorize reading ambient keystrokes or continuous clipboard monitoring.
17. **Higgsfield Watch — `openpets.higgsfield-watch`**. API-token-backed job/progress polling, start/finish announcements and completion celebrations. Requires configured provider service; secrets in Keychain. New connected feature.
18. **Usage Buddy — `regis.usage-buddy`** (separate MIT submodule). Claude/Codex utilization from a separate local usage-monitor endpoint, default `127.0.0.1:45455/usage`; provider filters, status, greeting, configurable polling and persisted upward threshold warnings at 50/75/90/100. It does not itself read provider credential files, chat histories or prompts. New plugin plus documented optional external monitor dependency.

The plugin inventories above describe behavior, not an instruction to enable them all. Initially keep expensive/resource-sensitive features off. Use explicit per-plugin network and local-write approvals rather than automatically accepting upstream bundled permissions.

## 5. Plugin SDK, host and author tooling

Full plugin parity is a platform project. Implement manifest/SDK v3 validation and a host bridge covering **23 namespaces**: `pet`, `pets`, `ui`, `schedule`, `storage`, `config`, `events`, `bus`, `audio`, `voice`, `notify`, `ai`, `secrets`, `auth`, `net`, `files`, `system`, `assets`, `commands`, `status`, `assistant`, `t`, and `log`. Do not call a few Swift built-ins a compatible runtime.

Port typed config fields, localization keys, declarative host-rendered bubbles/HUDs/alerts/sessions/courier deliveries, sound choices and commands. Plugins should not inject arbitrary HTML or gain unrestricted Swift/Node access. The legacy HTTP helper is a compatibility surface, not permission to bypass the newer network controls.

Schedules need once/every/daily/cron/absolute-time semantics, persistence, cancellation and missed-event reconciliation. Storage needs per-plugin quotas and atomic updates. Events expose curated pet clicks/drops, idle/display/power changes; keyboard content stays unavailable. Add a scoped cross-plugin bus, explicitly chosen file capabilities, imported opaque audio handles, aggregate system metrics and permission-gated clipboard operations.

Separate plugin-declared permissions from user-approved permissions and enforce the intersection on every call. Host permissions, network methods, payload/time quotas and approved hosts must remain effective even when a plugin misbehaves. Distinguish internet access, loopback access and network writes. Reject private-network/DNS-rebinding paths unless the appropriate local capability is granted. Secrets/OAuth tokens belong in Keychain; use OAuth PKCE and bounded redirects, never embed credentials into logs or user-editable JSON.

Upstream uses isolated Electron plugin renderers with no Node integration. A native port needs an independently reviewed isolated host, such as a restricted XPC process with a JS engine and a capability bridge. **JavaScriptCore alone is not a security boundary.** Hardened-runtime entitlements must be reassessed if a chosen runtime needs additional capabilities; do not add broad entitlements merely to make third-party code execute.

Implement catalog v2 installs with semantic minimum-app versions, hashes, package/source consistency, enable/disable/update/uninstall, health state and quota errors. Legacy catalog v1 is an empty compatibility response, not the maintained plugin source. Record official/community/local-dev origin. Team plugins have separate roots and artifact-specific approval; an organization's update must not silently replace a personal install.

Assistant capabilities are registered explicitly, independently of pet-menu commands. Validate bounded object-rooted schemas and arguments; enforce names, payload sizes, deadlines and current plugin generation. Cancel stale tools after unload/reload. An LLM cannot make an undeclared command authorized. Preserve deterministic results for rejected/unavailable/indeterminate operations.

Add local folder loading with safe snapshots, symlink/path limits and bounded hot reload. Ship author CLI scaffolding for blank, reminder, ambient, AI-chat, Tamagotchi and calendar templates; validator, package/hash tooling and a deterministic fake-clock harness. The harness checks plugin behavior, while real host tests prove isolation/permissions. Release/catalog validation and versioned compatibility fixtures are separate required checks.

## 6. AI chat, personality, providers and voice

Port the compact pet composer and expandable attached chat panel with message/tool cards, draft preservation, close/cancel behavior, context-aware placement and response status. Keep the bubbly PawSync visual style. One bounded host conversation coordinates typed and voice modalities so concurrent lanes cannot conflict.

Expose pet name, owner address, tone, style and response length. Personality changes apply next turn and should not override security policies or tool permissions. Inject current local date/time/timezone for relative reminder requests. Validate complete tool batches before effects; report authoritative actual tool results rather than model-generated claims of success.

Implement a provider library with separate Text, STT and TTS roles, plus a derived realtime mode when both required OpenAI models/configuration exist. Text includes native Anthropic and OpenAI-compatible endpoints, including local Ollama/LM Studio/vLLM and cloud gateways. STT includes compatible transcription providers and ElevenLabs Scribe. TTS includes macOS voices, compatible speech endpoints, ElevenLabs and MiniMax. Do not assume a text-only local endpoint can transcribe audio. Setup tests need minimal bounded probes, cancellation and clear errors; credentials are never rendered back into settings.

Maintain bounded local chat history with list/delete/clear controls, corrupt-file quarantine and explicit retention limits. Upstream documents 200 messages/30 days/512 KB archive limits and a smaller recent context budget. This is not cloud memory, semantic retrieval or continuous observation of user activity. Chat text intentionally entered by the user is distinct from global input content, which remains unavailable.

Voice requires a **fourth lazy TCC permission: Microphone**. This is separate from Screen Recording for system-audio dance. Provide one-shot push-to-talk with bounded acquisition/recording/transcription deadlines, an unmistakable active-mic indicator, tray stop/cancel and cleanup after errors, hide, sleep, disable or shutdown. No wake word or ambient listening is established upstream.

Optional OpenAI Realtime uses an exclusive voice lane, bounded session setup, interruption/mute/end/retry controls and host-validated tool calls. Provider/model configuration remains pinned during the session. Session completion must not silently reopen the mic. Device choices use opaque identifiers and refreshed availability; if system TTS uses OS routing, say so instead of falsely claiming a selected speaker.

For network STT, the user's deliberately recorded voice may be sent only to the configured provider after consent. System-music buffers are used for energy/onset detection only and must never be reused, stored or transmitted. Private MediaRemote is a narrow, fragile optional fallback, not a universal replacement for public ScreenCaptureKit audio detection.

## 7. Agent integrations and private IPC

Support the shared OpenPets client contract alongside PawSync's existing authenticated build webhook. Add private macOS Unix-socket discovery, owner-only permissions, authenticated requests, bounded NDJSON v1 messages, connect/response timeouts, errors and status. Never expose that full local API on a public listener. Methods cover health/status, pet lists and install operations, reaction/speech/media, and lease acquire/heartbeat/release.

Bundle a pinned Node client/MCP executable if compatibility requires it, instead of downloading `@latest` at runtime. MCP exposes exactly the three public tools `openpets_status`, `openpets_react`, `openpets_say`; lease management and heartbeat are host/client lifecycle operations. Leases carry session identity, TTL, idempotent release and PID/window confinement. Media allows only bounded supported local image formats, safe dimensions and restricted click-through schemes, not arbitrary executable/file URLs.

All eight integration paths need their own configuration and acceptance checks:

1. **Generic MCP:** stdio schema validation, sanitized failures, heartbeat, orderly SIGINT/disconnect cleanup and explicit-pet targeting.
2. **Claude Code:** scoped global/project hooks for prompt/tool/permission/notification/stop/failure categories, MCP configuration and managed instruction blocks. Respect existing configuration, local precedence and cooldowns; do not consume raw prompts/output for reactions.
3. **OpenCode:** safe JSONC configuration for plugin and MCP entries plus managed instructions; runtime lifecycle events and excluded-reaction settings.
4. **Cursor:** managed `.cursor/mcp.json` and marked rule blocks, strict size/path validation, preview, backups and pinned client. MCP is not native lifecycle-hook telemetry.
5. **Zed:** global JSONC `context_servers`, comment-preserving edits, conflict/error states, atomic backup/journal recovery and bounded source revision checks. No invented lifecycle hooks.
6. **Pi:** native extension lifecycle handling and `/openpets` status/test/react/say commands, default nonblocking behavior; do not confuse commands with callable model tools.
7. **OpenClaw:** managed native plugin installation/update/removal, supported-version checks and safe config. Current lifecycle coverage is thinking/working, not imaginary successful-completion hooks. Separate inventory success from proof a Gateway loaded the plugin; restarting another service is a distinct action.
8. **DSH/Cordis:** local bundle/status stream, categorized running/idle/error/approval reactions, error suppression windows and sanitized tool-action labels. Remote environments stand down unless explicitly configured.

Configuration installation needs a reviewable diff before modifying an existing user's integration files, safe backups and targeted rollback. Remote agents must not discover local sockets, install pets, read files or join a local pet lease simply because credentials are present elsewhere.

## 8. Remote control, LAN and Teams

These are opt-in expansions, not requirements for an offline desk companion.

**Remote control:** upstream permits concrete local/private/link-local/CGNAT IPv4 binds, never wildcard/public/hostname/IPv6 binds, with small payloads, rate/concurrency limits and scoped status/react/say operations. Tokens are shown once and stored as hashes with rotate/revoke controls. Upstream transport is unencrypted TCP with an acknowledgment warning. I propose encrypted native transport or an explicit experimental compatibility mode; silently widening PawSync's loopback listener would violate the original security scope. No remote install, file media, prompts or leases.

**LAN mode:** experimental pet edge handoff between configured neighboring hosts, topology, authenticated small JSON polling, per-owner visitor windows and backoff/cleanup. Visitor assets must already exist; missing assets skip delivery instead of trusting arbitrary remote files. Coarse work-return signals carry owner/work state, not prompts, tool payloads, speech or media. Session freshness/sequence checks prevent stale returns. The upstream documented validation used two profiles on one physical host, so cross-machine reliability is not proven. A true multi-machine test is required before claiming parity. Store native credentials in Keychain rather than copying upstream plaintext environment/config patterns.

**Teams enrollment:** organization preview, expiring deep-link intent, bounded/idempotent finish, safe credential storage and atomic membership metadata. Requires an organization backend that is not fully present in this checkout. Own deployment, schemas, administration and service credentials are external work; do not use the OpenPets production service as an assumed PawSync backend.

**Team Packs:** versioned immutable pet/plugin releases, required/optional assets, pending state until artifact-specific approval, serialized/jittered synchronization, hash validation, rollback and source isolation. Permission changes need fresh approval. Offline leave/uninstall should be shown as pending until completed; no overwrite of personal state.

**Manager Check-ins:** host-owned schedules for daily/every-N-days/weekly/monthly/quarterly forms, correct missing-date handling, local matching day, interactive five-feeling reply plus optional bounded note and explicit Share. Skip/close does not submit. No inference of employee productivity or missed responses from ambient inputs. Bound synchronized history/receipts and idempotent cycle IDs; device-private pause is not shared with the organization. Keep this distinct from private personal Mood Check-in.

## 9. Distribution, diagnostics and ecosystem tooling

Retain PawSync's Keychain, signed licensing, PostgreSQL ledger and transactional reserve/commit/refund/chargeback behavior. OpenPets is not a substitute payment service. Keep free hats separate from server-tracked paid accessory pack ownership and nonexpiring custom-generation credits.

Use Sparkle for signed macOS appcasts, visible major-version approval and manual update checks. Upstream GitHub release notices can inform release discovery but should not replace the required signed update chain. Public builds need universal binaries, Developer ID signing, hardened runtime, notarization, staple/Gatekeeper checks and minimal entitlements. Development builds must remain clearly labeled.

Add seven upstream UI locales—English, Latin American Spanish, Brazilian Portuguese, Japanese, Korean, Simplified Chinese and Traditional Chinese—with localized plugin messages and fallback behavior. Some plugins have additional translations; preserve their available locales rather than claiming every plugin shares exactly the same set.

Retain opt-in diagnostics, redact structured backend errors and bound local logs. Add permission-denial, corrupted-state, sleep/wake, failed install, stale lease, update, plugin reload and migration regressions. Enforce request ceilings on public APIs, local hooks, plugin hosts, remote listeners and inference.

Record the separate website/catalog publishing lane: asset indexes, plugin packages, hashes, provenance, compatibility metadata and release validation need owned hosting. No borrowing upstream domains, private keys, OAuth clients or payment credentials.

Windows signed installers, Linux AppImage/DEB/RPM/tar/AUR support, X11 bootstrap and experimental Wayland behavior are ecosystem features. They are **out of the native macOS implementation target** unless you explicitly approve a separate cross-platform program. Keep a list of these differences rather than calling macOS-specific substitutes literal code parity.

## 10. Paw-Paw direction and additional native polish

The public [Paw-Paw landing page](https://paw-paw.pet/) presents a playful Mac companion, input reactions, character selection, progression and collectible hats, with a playable website mascot, drag-to-equip preview, community/contact sections and FAQs. It reports 11 animals and 73 cosmetics in version 0.1.10. These are its catalog counts, not PawSync's. The matching landing-page structure now uses PawSync branding and nine original pets; no claim is made that its proprietary art/code was copied.

Its [changelog](https://paw-paw.pet/changelog) also describes inventory persistence, rarity/drop tuning, hat positioning, alpha click-through, dragging, per-app hiding, sleep, typing effects, Sparkle updates, accessibility improvements and a confirmed reset/relaunch flow. Remote catalog sync is described as disabled in its production build, so it is not an existing behavior to imitate as enabled.

PawSync should emphasize visible alternating short paw taps without a keyboard prop, curious cursor look, distinct click versus petting, a bubbly greeting/reminder, a responsive small hop, and a stroll with grounded gait. The public site does not specify exact proprietary physics/animation timings; those need our own native implementation and visual acceptance rather than a claim of exact internal matching.

Your approved earned/free/paid model is implemented independently: local aggregate XP, six original free hats and early pet unlocks; future optional paid packs have separate entitlements. Expand original free content toward a larger wardrobe without copying the reference's 73 artworks. Add hat positioning/scale controls, drag-to-equip, per-app hiding and opt-in typing effects. Reset local companion data needs a concrete confirmation showing what is cleared; it must never erase the server credit ledger or silently delete a license token.

The local landing page includes the hero, interactive companion, feature overview, pet picker, wardrobe preview, roadmap/status labels, FAQs, local app instructions and a feedback-note download. A live download, contact backend, public hostname and merchant checkout require release/service setup; placeholders do not submit fake messages or claim a public signed release.

## 11. Proposed dependency-ordered implementation

**P0 — Confirm the core experience.** Finish the authorized Paw-Paw-directed work: native paws/no keyboard, bubble style, size, click/petting/global keys, walk/jump cancellation, earned inventory, sleep and permission state. Test all nine rigs and six sample frame pets. Produce missing character sheets. Verify rendering stops on sleep and obtain idle CPU/RAM measurements. Fix failures before building more features. This phase continues existing authorized fixes; it is not permission to implement the OpenPets platform.

**P1 — Pet content and native shell.** Add gallery/import validators, provenance, offline cache, V2 gaze, reaction maps, live menus, horizontal flip, HUD scaling, dashboard and state migrations. Add local wardrobe transform/drop/equip and per-app hiding. Relatively large because archive recovery and asset validation need adversarial tests.

**P2 — Offline companion features.** Complete reminder/focus parity, Simple Timer, greeting policies, routines, fortunes, Magic 8-Ball, local mood history, virtual needs and resource HUD. One scheduler/domain store per feature; one presentation coordinator. Add practice sessions with downloadable media only after its host/content approval. Medium to large, with independently testable domains.

**P3 — Agent compatibility.** Implement private IPC/client/MCP, leases, multi-pet pool/confinement, configuration previews/backups and all eight agent adapters. Large. Validate real event behavior on supported installed tools rather than only emitting synthetic events.

**P4 — Plugin platform.** Build the isolated host, capability bridge, all 23 namespaces, permissions/quotas/catalog lifecycle, local development and author CLI/harness. Then run every official/community package against it and close compatibility differences. Very large; a thin bridge is not completion. Native domain features should be exposed through these APIs without duplication.

**P5 — Connected plugins and assistant.** Implement provider roles/personality/history/tool validation, optional mic/STT/TTS/realtime, Google Calendar, Spotify/lyrics, Higgsfield, vocabulary/Anki and Usage Buddy. Very large; credentials and host permissions are user-configured, features default off. Each connection gets independent error/offline/cancel tests.

**P6 — Optional remote/LAN/Teams.** Add protected remote control, experimental edge handoff, owned team backend/enrollment/packs/check-ins and explicit sharing. Very large and separate from core launch. Cross-machine and organization-service tests are required. Do not enable LAN/network servers merely by installing the app.

**P7 — Release acceptance.** Localize, verify migration/isolation/privacy, measure idle and active resources, run the real sandbox payment lifecycle, exercise update rollback, sign/notarize and publish appcast/downloads and the landing page. Finalize owned service endpoints and content rights. Windows/Linux are a separate approved extension, not hidden inside P7.

These are relative effort descriptions, not calendar promises. The critical path is working interaction → safe content/state → presentation/domain services → IPC/isolated capabilities → connected features → release acceptance. Optional services should not block the offline companion from working.

## 12. Acceptance criteria before calling this complete

- Physical typing in a separate app alternates paws; mouse clicks in another app react; petting is visually distinct. Review source for any `keyCode`, characters or input logging. Permission denial is useful and reversible.
- Every displayed pet loads with correct orientation/pivot/alpha hit-test; wardrobe follows head motion; no keyboard prop. Size changes hit bounds, panel clamping and bubble placement together. Walking/jump visibly move the native panel and cancel cleanly on input/drag/sleep.
- Reminder/focus/timer schedules survive restart, clock changes and sleep; suppression/high priority/missed events behave correctly; snooze affects one occurrence. Alerts do not compete with chat or pinned HUDs.
- Inventory reload preserves XP/unlocks/owned hats; repeat reconciliation does not grant duplicate drops. Free hats never consult paid ownership; paid packs never unlock from a forged local balance; headphones never require a SKU.
- ZIPs with traversal/symlinks/bombs/bad manifests fail before installation. Interrupted installs recover without touching unrelated pets. V1/V2 boundaries, cache quotas, corrupt state and unavailable catalog have fixtures.
- All 18 plugin behaviors run through real host permissions, with denied hosts/local writes/oversized payloads/expired tools/reloads tested. The isolated host cannot read arbitrary files, Node APIs or key events. SDK compatibility has a versioned checklist.
- All eight integrations preserve unrelated config, expose preview/diff, recover from rollback and exercise truthful lifecycle reactions; leases clean up crashed owners, no cross-session stealing or orphan pets.
- Chat tools report actual outcomes, history is bounded/deletable, secrets are Keychain-only. Mic capture is lazy, visible, stoppable and canceled on every exit path. Music buffers never reach a file/network/provider.
- Remote/LAN/Teams are off by default, authentication/limits hold, no prompts/media leak through work-return signals, visitor assets are trusted, check-in sharing is explicit and pending/offline states are accurate.
- Real Apple Silicon Instruments measurements certify idle under 0.5% CPU and under 60 MB RAM with Settings closed and optional workers inactive. Report active-feature budgets separately. Public builds pass signing/notarization/Gatekeeper and signed update delivery; no development artifact is represented as a public release.

## 13. Approved scope

The user approved **the native macOS OpenPets feature port described in P1–P7** on 27 September 2026, covering all maintained plugins and agent paths, with chat/voice/cloud/remote/LAN/Teams opt-in and on-demand. Existing PawSync licensing/credits remain; earned pets/free hats and optional paid packs follow your confirmed choice. This approval authorizes local implementation, not purchases, granting new TCC permissions, transmitting personal data to providers, or publishing a public release without the necessary setup.

The resulting network scope will be wider than the original narrow backend/loopback allowlist, because gallery downloads, plugin hosts, optional AI/OAuth and Teams need declared endpoints. Each optional connection must be disabled until configured and explicitly enabled. Microphone is an additional lazy permission; no Accessibility or Screen Recording grant is implied by report approval.

Cross-platform packaging and redistribution of every third-party character asset remain separate decisions. The recommended interpretation of “all pets” is complete catalog/import support with provenance checks and on-demand installation, rather than shipping an unreviewed bulk art archive.

**The user approved this native macOS plan. Implementation proceeds in dependency order; the acceptance criteria remain release gates.**
