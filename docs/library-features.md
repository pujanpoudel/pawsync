# PawSync Library and progression

The native Library uses a warm paper/cream palette, rounded type and cards, a purple selected sidebar row, real pet previews and item artwork. Knight Cat remains the main companion. Companion tools and developer controls remain under Advanced.

## Available locally

- All 47 bundled companions, plus optional existing imports; search, favorites, preview sheets and companion selection. Existing pets stay unlocked on migration. New installs earn Season 1's 11 companions and Season 2's 20 companions on independent tracks (one companion every two levels, ending Season 2 at level 39). PawSync originals have their own track.
- A chosen XP track independent of pet selection, an opt-in “XP follows my companion” mode, an earning indicator in the sidebar, and 2× XP while a fast live-input rhythm is active. XP processing observes binary input occurrences only and batches UI/disk updates.
- 228 free wearable variants: 120 Season 1 items including six legacy hats, and 108 Season 2 items. Original vector silhouettes and palette variants are drawn natively; they are not a copy of Paw-Paw's item artwork. Items have category, rarity, track, favorites, search and collected filters. Desserts are under Food. Art remains visible before collection.
- Gifts persist through restarts. Pick one of three balls with a mouse or keys 1–3; Wear It or Add to Items collects it. Escape leaves it for later. Open All handles two or more waiting gifts. Claimed IDs prevent gifts returning through sync. Unopened gifts do not block achievement unlocks.
- 30 permanent achievements, seven hidden pet/item pairings and short native celebrations. Achievements grant no XP or gifts. Discoveries reveal their pairings only after the user finds them.
- Optional automatic cheers and a cheer on a direct pet click. Existing cuddles and double-tap quick actions remain. Existing reminder, focus, file-pocket and music behavior remains available.
- Small/Medium/Large, Mirror Mode with left docking, opacity and click-through, favorites and track selection in the pet/Dock menus, Hide for 1 Hour, Reset Position and Check for Updates. The Dock opens the Library; the menu-bar utility remains available too.
- A live item editor with per-pet/per-item saved adjustments, reset preview, cancel restoration, arrow-key nudging, Change Item and Done. Head-top items, soft caps, ear bows and glasses use distinct contact/scale rules. Full-body fitting samples the actual head silhouette rather than an arbitrary offset; glasses use facial landmarks. Existing authored pose offsets remain supported. Imported OpenPets eyewear has individually reviewed iris centers; original Fox facial anchors were corrected. Skeletal/custom rigs use their actual head-part dimensions.
- Opt-in launch at login uses Apple's public SMAppService API. Onboarding is three short steps: optional account explanation, privacy choices, then Input Monitoring. Accessibility and Screen Recording stay lazy for their existing feature paths.
- Reset Progress preserves purchases and settings and saves a backup. Reset Local Everything separately archives earned progress, local reminders/tools, aggregate counters and preferences, then relaunches for setup so in-memory state cannot restore them. Pet art, purchase cache and Keychain tokens remain. macOS TCC grants are not programmatically revoked.

## Connected behavior and deployment

Progress sync is off by default. Restore Purchase provides the existing signed Keychain session token. Authenticated `POST /v1/library/progress` merges inventories, achievements, discoveries and higher per-track XP under a PostgreSQL account-row lock. Both local and server backups preserve replaced copies. Server reset increments an authoritative epoch; an old/offline Mac cannot bring erased progress back. Reset with sync enabled applies to the account as well as this Mac. Purchase/credit state is never accepted from a progress payload. No app restart is needed for normal sync.

Optional content refresh obtains bounded, validated item metadata and cheers from the configured PawSync API. New pet packages use `GET /v1/library/pets/{id}`, an expected SHA-256 and the existing safe ZIP/image installer. Paid collection art is downloaded only after a signed account's server-side ownership check. Public catalogs contain metadata, not restricted art.

The existing Paddle flow now accepts configured `collection.<name>` and `accessory.pack.<name>` SKUs as separate one-time products. Optional artist collections can declare their own XP track, pet unlock levels, items and checkout SKU. The Library shows their page only when a collection is configured. It does not invent an Illustrain purchase, artist artwork, USD price or active checkout.

Deploy the existing backend with PostgreSQL/Redis, signing keys, SMTP and Paddle configuration. Run `python -m pawsync.manage init-db` for the new progress/backup tables. Set `LIBRARY_CONTENT_PATH` to the catalog JSON and `LIBRARY_ASSETS_DIR` to the bounded ZIP directory. Release signing/notarization and the signed Sparkle feed still require the existing production credentials. The bundled development configuration points to localhost and has no live merchant checkout or deployed sync service.

A collection manifest can extend the bundled catalog with `collections` and `pets`:

```json
{
  "version": 1,
  "items": [],
  "lines": ["A little cheer for your next small step."],
  "collections": [{"id":"collection.artist","name":"Artist Collection","sku":"collection.artist","priceLabel":"Configured checkout price"}],
  "pets": [{"id":"artist-kitten","sha256":"SHA256_OF_THE_SUPPLIED_ZIP","requiresSKU":"collection.artist","collection":"collection.artist","unlockLevel":1}]
}
```

Items use the bundled `Library/catalog.json` schema. Paid-track items specify their `season` as the collection ID and add `requiresSKU`. Their ownership remains independent of base licensing and generation credits. A package contains a validated `pet.json` and `spritesheet.webp`; its filename is `<id>.zip`.

## Validation and practical limits

`--check-library build/library-proof` exercises the progression, gifts, achievements, merge/reset and wearable catalog, and captures the actual native Library screens and six contact sheets covering all 47 bundled pets. Existing motion, asset, expression and control checks cover the rendering and interaction regressions. Backend tests run on isolated real PostgreSQL schemas, including paid-art authorization and reset replay protection.

Screenshots and native action checks do not establish physical Input Monitoring acceptance, notarized distribution, live payment fulfillment or the Instruments CPU/RAM budgets. The artist collection in the supplied reference needs its separately supplied licensed art and configured product; the mechanism is implemented, those inputs are not fabricated.

Verified on 6 October 2026: the universal arm64/x86_64 development build, ad-hoc signature verification, native Library/progression checks, asset/persistence checks, real-overlay Walk/Jump checks, 47-pet expression rendering, double-tap/bubble/pocket control checks, temporary-file lifecycle checks, and 33 backend tests using isolated real PostgreSQL schemas. Rendered fit sheets cover all 47 bundled pets. Physical cross-app input and production service/release acceptance remain separate from these checks.
