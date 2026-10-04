#!/usr/bin/env python3
"""Archive native resources, provenance, source poses and rendered contact sheets."""
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    output = ROOT / "build/PawSync-expressive-pets.zip"
    folders = ["macos/Resources/OpenPets", "macos/Resources/FileInteractions", "art/file-interactions", "art/pawpaw-reference", "art/pawpaw-fullbody", "art/knight-cat", "build/emotion-character-sheets"]
    files = ["docs/expressive-pet-packs.md", "docs/pet-expression-report.md", "docs/pet-expression-report.json", "art/file-interaction-sources.json", "art/pawpaw-fullbody-sources.json", "macos/Sources/PawSync/PetEmotion.swift", "macos/Sources/PawSync/FramePetNode.swift", "macos/Sources/PawSync/PetCompanionChrome.swift", "macos/Sources/PawSync/CompanionAnimating.swift", "scripts/bake_file_interactions.py", "scripts/bake_fullbody_companions.py", "scripts/import_pawpaw_previews.py"]
    files += ["scripts/bake_knight_cat.py","macos/Sources/PawSync/PetClickMotion.swift"]
    with zipfile.ZipFile(output,"w",zipfile.ZIP_DEFLATED) as archive:
        for folder in folders:
            for path in sorted((ROOT / folder).rglob("*")):
                if path.is_file(): archive.write(path,path.relative_to(ROOT))
        for file in files: archive.write(ROOT / file,file)
    print(f"Packaged expressive companions, actual catch/hold poses and native character sheets: {output}")


if __name__ == "__main__": main()
