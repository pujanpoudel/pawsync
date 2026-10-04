# PawSync pet and expression report

Snapshot: 4 October 2026. Source: bundled manifests, face profiles, authored pose resources and the native animation code. User-installed and cloud-generated custom pets are additional and are excluded from these fixed counts.

## Inventory

**47 selectable bundled companions**, comprising 10 PawSync originals (including Knight Cat), six OpenPets imports and 31 full-body Paw-Paw adaptations. These are distinct companion/art variants, rather than a count of unique animal species.

**14 named expression states**, including Playful, Delighted, Cozy and Grumpy. 41 pets have measured facial profiles and procedural eyelids/pupils/blush. The six OpenPets imports preserve their authored face artwork and map the state requests to their existing reaction clips with limited accent overlays; they do not gain 14 newly drawn faces.

41 companions have authored receive/hold pose resources: ten originals and all 31 full-body adaptations. The adaptations contain 124 authored source poses (four per pet); Knight Cat adds four more source poses. The 3,400 atlas cells include repeated poses and generated motion timing; they are not 3,400 distinct hand-drawn pictures.

Knight Cat uses the user-provided armored kitten reference, with silver armor, a cream cape, a pink ear bow and a safely sheathed sword so both hands remain usable. Its exact generation/edit prompts and source references are preserved in `art/knight-cat/source.json`.

### PawSync originals (10)

- Cocoa the Bear (`bear`)
- Clover the Bunny (`bunny`)
- Pudding the Capybara (`capybara`)
- Ember the Fox (`fox`)
- Peaches the Hamster (`hamster`)
- Pebble the Otter (`otter`)
- Bao the Panda (`panda`)
- Maple the Cat (`pixel-cat`)
- Mochi the Shibe (`shibe`)
- Knight Cat (`knight-cat`)

### OpenPets imports (6)

- OpenPets Buddy (`openpets-default`)
- Snoopy (`openpets-snoopy`)
- Clippy (`openpets-clippit`)
- Tux (`openpets-tux`)
- Wall-E (`openpets-wall-e`)
- Dobby (`openpets-dobby`)

### Full-body Paw-Paw adaptations (31)

- Shiba Inu (`pawpaw-shiba`)
- Fox (`pawpaw-fox`)
- Bear (`pawpaw-bear`)
- Hamster (`pawpaw-hamster`)
- Koala (`pawpaw-koala`)
- Pig (`pawpaw-pig`)
- Corgi (`pawpaw-corgi`)
- Wolf (`pawpaw-wolf`)
- Capybara (`pawpaw-capybara`)
- Raccoon (`pawpaw-raccoon`)
- Seal (`pawpaw-seal`)
- Sheep (`pawpaw-season2-sheep`)
- Dolphin (`pawpaw-season2-dolphin`)
- Squirrel (`pawpaw-season2-squirrel`)
- Bat (`pawpaw-season2-bat`)
- Penguin (`pawpaw-season2-penguin`)
- Giant Panda (`pawpaw-season2-giant-panda`)
- Frog (`pawpaw-season2-frog`)
- Shetland Sheepdog (`pawpaw-season2-shetland-sheepdog`)
- Chameleon (`pawpaw-season2-chameleon`)
- Otter (`pawpaw-season2-otter`)
- Hedgehog (`pawpaw-season2-hedgehog`)
- Beluga (`pawpaw-season2-beluga`)
- Sloth (`pawpaw-season2-sloth`)
- Skunk (`pawpaw-season2-skunk`)
- Axolotl (`pawpaw-season2-axolotl`)
- Tanuki (`pawpaw-season2-tanuki`)
- Manatee (`pawpaw-season2-manatee`)
- Armadillo (`pawpaw-season2-armadillo`)
- Platypus (`pawpaw-season2-platypus`)
- Opossum (`pawpaw-season2-opossum`)

## Expressions

- **Happy**: Smiling eye arcs and soft blush; ordinary positive reactions.
- **Curious**: Two attentive open eyes with gently raised brows; cursor interest.
- **Surprised**: Small dark bead eyes with warm highlights; brief boop/file receiving.
- **Affectionate**: Closed smiling eyes, blush and small hearts; petting and cuddles.
- **Shy**: Lowered lids, blush and a slight lean; gentle ambient reaction.
- **Sad**: Soft lowered eyes and a small tear; expression preview.
- **Sleepy**: Closed relaxed eye arcs; idle/focus sleep.
- **Excited**: Bright closed-eye smile and sparkles; rapid typing.
- **Proud**: Smiling eyes, blush and sparkles; a successful file catch.
- **Focused**: Retains the original eyes with subtle concentration brows; typing.
- **Playful** (new): A matching smile in both eyes; one of the direct-click cuddle responses.
- **Delighted** (new): Smiling closed eyes, blush and little sparkles; direct affection.
- **Cozy** (new): Relaxed closed eyes and blush; calm cuddling.
- **Grumpy** (new): Small slanted lids; a previewable expression, not a random punishment.

## What the pet does

- Direct single click: a finite crouch, two springy raised-paw kitten hops and soft landings inspired by the supplied Pinterest GIF; cycles delighted, playful, affectionate and cozy moods. Typing interrupts it immediately. It does not equip music headphones.
- Double tap: opens the existing quick-action menu. Hover does not open that menu.
- Click and drag: distinct stroking/petting animation. Option-drag repositions the companion.
- Typing: alternating front-limb taps; fast bursts can show excitement. Ambient mouse clicks keep brief reactions rather than always dancing.
- Walking: a bounded on-screen move, with an alternating lower-limb/flipper gait on the full-body adaptations. Jumping remains a finite arced move.
- Music: separate audio-triggered dance with the free built-in headphones.
- Files: arms-open receive pose, cancellation back to rest/hold, proud catch and a subtle held note. References stay temporary and original filenames/locations remain unchanged.
- Sleep and reminders: existing idle/focus sleep, screen-sleep render suspension and in-character reminder delivery remain available.

## Corrected presentation

Pudding the Capybara uses measured wide-set eye landmarks in the neutral, receive and hold artwork. Its nostrils are no longer used as expression anchors. Full-body adaptations have reviewed eye landmarks, including masks, side-facing eyes and asymmetric heads; the receive pose registers its facial landmarks against the reviewed neutral face.

Both Cocoa the Bear and the Paw-Paw-derived Bear omit their desktop name/level caption. Pet names remain visible in Companion/Gallery, and level/XP remain in Settings → Advanced → Activity.

All 31 adaptations now show complete bodies with feet, flippers or tails appropriate to the animal, rather than the website’s original half-body peeking silhouette. The original downloaded website references remain unchanged under `art/pawpaw-reference/`. The new four-pose sheets and exact built-in imagegen prompts are under `art/pawpaw-fullbody/` and `art/pawpaw-fullbody-sources.json`.

## Resources and checks

- `build/PawSync-knight-cat.zip`: Knight Cat atlas, source art, prompts, facial metadata and receiving/holding resources.
- `build/PawSync-expressive-pets.zip`: all bundled resources, full-body source sheets, original catch/hold sheets, exact prompts, code and native emotion contact sheets.
- `build/emotion-character-sheets/`: one native rendered sheet per bundled pet, including all 14 expressions, direct cuddle, receiving, catch and hold.
- `docs/pet-expression-report.json`: machine-readable counts and per-pet coverage.
- Native emotion, motion, asset, UI dispatch and temporary-file checks cover source/render behavior. Physical cross-app input, OS drag-out acceptance, Instruments budgets and notarized release acceptance are separate checks.

Reference attribution remains Paw-Paw/OpenPets where applicable. Generated adaptations do not establish commercial redistribution rights to another creator’s character designs.
