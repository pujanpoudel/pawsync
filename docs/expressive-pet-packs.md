# Expressions, catching poses and companion varieties

The native development build contains 47 frame companions: ten PawSync originals (including Knight Cat), six existing OpenPets imports and 31 public Paw-Paw preview companions. The reference collection follows the [Season 2 release notes](https://paw-paw.pet/changelog#season-2): eleven Season 1 animals and twenty Season 2 animals. It excludes the separately sold Studio Spoon collection.

## Expressions and interactions

PawSync originals and the full-body reference adaptations have measured facial landmarks for happy, curious, surprised, affectionate, shy, sad, sleepy, excited, proud, focused, playful, delighted, cozy and grumpy expressions. The renderer preserves fur patterns and draws lids, pupils, blush and occasional hearts/sparkles over the real face. Existing OpenPets characters without measured facial landmarks keep their authored reaction frames, with limited accent overlays.

Surprise and file receiving use gently enlarged dark bead eyes with tiny warm highlights, without white sclera rings, to keep everyday reactions soft rather than startled.

Typing alternates left/right paws; rapid typing adds enthusiasm. Ordinary mouse clicks cycle through short boop, curiosity, happy, shy and proud reactions. Petting shows affection. These are finite reactions, independent of the double-tap quick-action menu.

Clicking the pet itself now triggers a finite cuddly dance: a crouch, two raised-paw kitten hops and soft landings inspired by the supplied Pinterest GIF, cycling delighted/playful/affectionate/cozy moods. Typing interrupts it immediately. This affection animation does not equip the system-audio dance headphones. Both Bear variants omit their desktop name/level caption while preserving names/progression in Settings.

All 31 Paw-Paw adaptations now use newly authored full-body four-pose sheets rather than the original peeking silhouettes. Each has complete feet/flippers/tail, alternating front-limb poses and authored file-receive/hold resources. Lower limbs move during walking. Their source sheets and precise prompts are preserved under `art/pawpaw-fullbody/` and `art/pawpaw-fullbody-sources.json`; the unchanged downloaded references remain under `art/pawpaw-reference/`. Pudding's neutral/receive/hold eyes are explicitly measured so its nostrils cannot be selected by the automatic detector.

The nine original pets have newly generated, transparent arms-open and cupped-hand poses. An incoming file drag shows the receive pose, cancellation restores the previous resting/holding pose, and a successful catch closes the arms around the small heart-sealed note. The small note disappears when empty. Other frame pets use their existing artwork with local paw motion; segmented custom pets move their actual arm joints.

File poses use their own transparency masks and face/accessory anchors, so extended paws remain clickable and the small heart-sealed note follows the held pose. Activity, sleep and roaming cannot interrupt an active file receive.

## Files are temporary

The pocket now keeps original file URLs in memory for the current app session. It never copies, renames, moves or deletes a dropped original. The exact filename, including Unicode and whitespace, remains unchanged. Successful outgoing drags release that entry; cancelled drags retain it. The visible Clear all button releases every reference without deleting any originals. The outgoing operation copies the original to the user's chosen destination rather than moving the source. Dismissal of a pocket removes its view; removing an entry only releases the reference. Quitting clears all references.

Earlier builds stored UUID-prefixed copies under Application Support/PawSync/PetInbox. Those earlier copies are preserved and excluded from the new temporary pocket. If present, Advanced → Companion tools offers “Show earlier copies in Finder” for recovery. No automatic deletion or renaming of those files occurs.

## Resources and archives

- `art/file-interactions/<id>.png`: unchanged two-pose generated source sheets.
- `art/file-interaction-sources.json`: exact prompts and built-in imagegen provenance.
- `macos/Resources/FileInteractions/<id>/`: fitted receive/hold PNGs and per-pose face/accessory landmarks.
- `macos/Resources/OpenPets/originals/<id>/`: existing OpenPets-compatible V1 atlases plus facial landmarks.
- `macos/Resources/OpenPets/pawpaw/<id>/`: four-pose character sheet, preview, native V1 playback atlas, manifest and facial landmarks.
- `art/pawpaw-reference/<id>/`: unchanged public preview sources and source URL/SHA-256 records.
- `build/emotion-character-sheets/`: native rendered contact sheets for all 47 pets, with 14 emotion requests, cuddle dance and receive/catch/hold states.
- `docs/pet-expression-report.md` and `.json`: complete companion inventory and precise expression/art coverage counts.
- `build/PawSync-expressive-pets.zip`: complete resource/reference archive, including the native code required for procedural expression playback.
- `build/PawSync-pawpaw-preview-pets.zip`: the 31 adapted public reference packs.

Chat and reminder bubbles use a pet-colored stitched plush cushion with matching paws. Primary buttons have a dark solid fill and light text; secondary actions have a full dark outline. The file pocket and small held note share the selected pet’s palette.

The original two-pose sheets and new full-body adaptations were created with built-in imagegen using the existing artwork as identity references. Baking only extracts/resizes cells and calculates landmarks; it does not generate artwork at runtime. Reference artwork remains attributed to Paw-Paw and is marked as development preview material. Public availability and a free app do not establish permission to redistribute another creator's illustrations commercially.

## Rebuild and verification

Run `uv run --with pillow python scripts/bake_file_interactions.py` to bake the original file poses and `uv run --with pillow python scripts/bake_fullbody_companions.py` for the full-body adaptations. `uv run --with pillow python scripts/import_pawpaw_previews.py` refreshes the cached reference catalog while preserving approved full-body adaptations. Run `python3 scripts/build_app.py --universal` to rebuild the native development app; `python3 scripts/build_pet_report.py` refreshes the inventory report.

The native `--check-emotions <directory>`, `--check-motion <directory>`, `--check-companion-ui <directory>`, `--check-file-pocket` and `--check-assets` commands cover render/state transitions, event dispatch, hit regions and disposable file fixtures. They do not establish physical cross-app input acceptance, operating-system drag-and-drop acceptance or the release CPU/RAM targets. Those require a live test of the final signed build.

## Knight Cat

The armored kitten joins the original companions as `knight-cat`, with four full-body poses, fourteen measured expression states, alternating hand taps, walking/jumping and native file catching. The sword stays sheathed to keep both hands free. Source art, the supplied references and exact built-in imagegen generation/edit prompts live in `art/knight-cat/`. Re-bake with `uv run --with pillow python scripts/bake_knight_cat.py`. The portable resources are in `build/PawSync-knight-cat.zip`.
