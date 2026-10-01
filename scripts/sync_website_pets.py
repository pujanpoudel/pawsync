"""Copy the same bundled sprite sheets used by the macOS app into the site."""

import json
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "macos/Resources/OpenPets"
FRAMES = ROOT / "website/assets/frames"
THUMBS = ROOT / "website/assets/thumbs"
CATALOG = ROOT / "website/assets/catalog.json"

ORIGINALS = [
    "pixel-cat", "shibe", "fox", "bunny", "bear", "panda",
    "hamster", "otter", "capybara",
]
IMPORTED = ["default", "snoopy", "clippit", "tux", "wall-e", "dobby"]


def entry(folder: Path, site_id: str, group: str) -> dict:
    manifest = json.loads((folder / "pet.json").read_text())
    rows = 11 if manifest.get("spriteVersionNumber") == 2 else 9
    source = folder / "spritesheet.webp"
    if not source.is_file():
        raise FileNotFoundError(source)
    shutil.copy2(source, FRAMES / f"{site_id}.webp")
    subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-y", "-i", str(source),
         "-vf", f"crop=192:208:{(6 if rows == 11 else 0) * 192}:0,scale=96:104",
         "-frames:v", "1", str(THUMBS / f"{site_id}.png")],
        check=True,
    )
    return {
        "id": site_id,
        "name": manifest["displayName"],
        "group": group,
        "sheet": f"assets/frames/{site_id}.webp",
        "thumbnail": f"assets/thumbs/{site_id}.png",
        "rows": rows,
        "idleColumn": 6 if rows == 11 else 0,
    }


def main() -> None:
    FRAMES.mkdir(parents=True, exist_ok=True)
    THUMBS.mkdir(parents=True, exist_ok=True)
    pets = [entry(SOURCE / "originals" / pet, pet, "PawSync") for pet in ORIGINALS]
    pets += [entry(SOURCE / pet, f"openpets-{pet}", "OpenPets") for pet in IMPORTED]
    CATALOG.write_text(json.dumps(pets, indent=2) + "\n")
    print(f"Synced {len(pets)} bundled pets to {FRAMES}")


if __name__ == "__main__":
    main()
