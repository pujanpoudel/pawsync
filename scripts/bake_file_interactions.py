#!/usr/bin/env python3
"""Normalize imagegen's two authored poses; preserve source artwork unchanged."""
import json
from pathlib import Path
import shutil
from PIL import Image
from import_pawpaw_previews import eye_pair, measured_eyes

ROOT = Path(__file__).resolve().parents[1]
FILE_EYE_OVERRIDES = {
    "capybara": {
        "receive": [(62,94.5,5.5),(133.5,94.5,5.5)],
        "hold": [(52.5,94,5.5),(124.5,94,5.5)],
    },
}


def main():
    sources = json.loads((ROOT / "art/file-interaction-sources.json").read_text())
    for source in sources:
        pet_id = source["id"]
        original = ROOT / f"art/file-interactions/{pet_id}.png"
        if not original.exists():
            shutil.copy2(source["path"], original)
        sheet = Image.open(original).convert("RGBA")
        assert 1.8 < sheet.width / sheet.height < 2.2, f"Expected two horizontal cells: {pet_id}"
        assert sheet.getchannel("A").getextrema() == (0, 255), f"Not transparent: {pet_id}"
        width = sheet.width // 2
        cells = [sheet.crop((n*width, 0, (n+1)*width, sheet.height)) for n in range(2)]
        bounds = [cell.getchannel("A").getbbox() for cell in cells]
        crop = (min(b[0] for b in bounds), min(b[1] for b in bounds), max(b[2] for b in bounds), max(b[3] for b in bounds))
        scale = min(180/(crop[2]-crop[0]), 188/(crop[3]-crop[1]))
        size = (round((crop[2]-crop[0])*scale), round((crop[3]-crop[1])*scale))
        destination = ROOT / f"macos/Resources/FileInteractions/{pet_id}"
        destination.mkdir(parents=True, exist_ok=True)
        for pose, cell in zip(("receive", "hold"), cells):
            frame = Image.new("RGBA", (192, 208))
            frame.alpha_composite(cell.crop(crop).resize(size, Image.Resampling.LANCZOS), ((192-size[0])//2, 198-size[1]))
            frame.save(destination / f"{pose}.png")
            eyes = eye_pair(frame, (96, 36), darkness=45 if pet_id == "panda" else 125)
            info = []
            for x0, y0, x1, y1 in eyes:
                x, y = (x0+x1)/2, (y0+y1)/2
                sample = frame.getpixel((int(x), max(0, int(y-max(5,(y1-y0)*.95)))))
                info.append({"point":[x/192,y/208], "radius":min(15,max(2.3,(x1-x0)*.6)), "fur":[v/255 for v in sample[:3]]})
            if pet_id in FILE_EYE_OVERRIDES:
                info = measured_eyes(frame,FILE_EYE_OVERRIDES[pet_id][pose])
            cx = sum(eye["point"][0] for eye in info)/2
            eye_y = sum(eye["point"][1] for eye in info)/2
            profile = {"eyes":info, "crown":[cx,max(.08,eye_y-.17)], "accessory_scale":max(.5,min(1.3,(info[1]["point"][0]-info[0]["point"][0])*192/44)), "paw_centers":[[cx-.15,.28],[cx+.15,.28]]}
            pose_dir = destination / pose
            pose_dir.mkdir(exist_ok=True)
            (pose_dir / "interaction.json").write_text(json.dumps(profile,indent=2)+"\n")
        print(f"Baked real open-arm and cupped-hand poses: {pet_id}")


if __name__ == "__main__":
    main()
