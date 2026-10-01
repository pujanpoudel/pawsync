# PawSync original pet animation packs

The nine original PawSync characters now use transparent 8-column × 9-row frame atlases (192 × 208 points per frame, 1536 × 1872 pixels total). They are baked at build time from original full-body pose art, so the running app only decodes the WebP atlas and advances frames. Original OpenPets imports continue to use their upstream sheets unchanged.

The nine individual ZIPs in `build/original-pet-zips/` are importable into PawSync. Each contains:

- `pet.json`: name, author, sprite version and atlas path.
- `spritesheet.webp`: transparent 8 × 9 playback atlas.
- `character-sheet.png`: original character reference sheet.
- `pose-sheet.png`: full-body source poses with walking legs, airborne and landing feet, waving paw, working paws, and happy expression.

`build/PawSync-original-pets.zip` collects all nine packs and this document. Import an individual ZIP into the gallery; the combined archive is for sharing or inspecting the complete character set. The app bundles the WebP and JSON for each pet under `Contents/Resources/OpenPets/originals/` and switches original PawSync pets to the same frame player as OpenPets pets. The previous rig remains a fallback if a baked atlas is absent.

The nine rows use the OpenPets V1 frame layout: idle, walk right, walk left, wave, jump, failed/rest, waiting, work, and review. Walking alternates leg poses; jumping shows crouch, airborne motion and landing. Clicking waves, petting plays the happy review expression, and lingering nearby triggers a wave. Frame timing, looping, collision alpha and head-accessory controls are handled by the existing PawSync frame player.

These are newly illustrated PawSync characters with an OpenPets-compatible animation format. They are not copies of OpenPets characters or exact reproductions of their art.
