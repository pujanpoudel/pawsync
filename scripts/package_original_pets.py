#!/usr/bin/env python3
"""Convert the one-time original-pet bake into bundled atlases and shareable packs."""
from pathlib import Path
import shutil
import subprocess
import zipfile


ROOT = Path(__file__).resolve().parents[1]
BAKE = ROOT / "build/original-pet-bake"
BUNDLED = ROOT / "macos/Resources/OpenPets/originals"
PACKS = ROOT / "build/original-pet-zips"
PETS = ("pixel-cat", "shibe", "fox", "bunny", "bear", "panda", "hamster", "otter", "capybara")
FILES = ("pet.json", "spritesheet.webp", "character-sheet.png", "pose-sheet.png")


def main() -> None:
    PACKS.mkdir(parents=True, exist_ok=True)
    for pet in PETS:
        source = BAKE / pet
        target = BUNDLED / pet
        target.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["cwebp", "-quiet", "-lossless", str(source / "spritesheet.png"), "-o", str(source / "spritesheet.webp")],
            check=True,
        )
        for name in ("pet.json", "spritesheet.webp"):
            shutil.copy2(source / name, target / name)
        with zipfile.ZipFile(PACKS / f"{pet}.zip", "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for name in FILES:
                archive.write(source / name, arcname=name)
        print(f"Packaged {pet}: {source.joinpath('spritesheet.webp').stat().st_size // 1024} KB WebP")
    with zipfile.ZipFile(ROOT / "build/PawSync-original-pets.zip", "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.write(ROOT / "docs/original-pet-packs.md", arcname="README.md")
        for pet in PETS:
            for name in FILES:
                archive.write(BAKE / pet / name, arcname=f"{pet}/{name}")


if __name__ == "__main__":
    main()
