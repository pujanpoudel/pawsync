#!/usr/bin/env python3
"""Bake the 31 public Paw-Paw website previews into local development frame packs.

Keeps the downloaded illustrations unchanged, attributes their creator, and emits
the same eight-column animation contract the native app already understands.
No runtime network requests are needed for this collection.
"""
import concurrent.futures
import hashlib
import io
import json
import math
from pathlib import Path
import re
import urllib.request
import zipfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art/pawpaw-reference"
BUNDLED = ROOT / "macos/Resources/OpenPets/pawpaw"
POSES = ("both-up", "both-down", "left-down", "right-down")
BASE = "https://paw-paw.pet/"
# Measured iris centers in the fitted 192×208 preview. Dark masks, noses and
# paw pads are intentionally excluded; automatic dark-component detection can
# otherwise mistake them for eyes. Coordinates keep the animal's real markings.
EYE_OVERRIDES = {
    "shiba": [(66,148,3.5),(106.5,153.5,4)],
    "bear": [(59.5,158.5,4),(113.5,163.5,4)],
    "raccoon": [(52,165,3),(100,168,3)],
    "season2-shetland-sheepdog": [(61,132,4.5),(100,134,4.5)],
    "season2-skunk": [(62,134,4),(102,139,4)],
    "season2-tanuki": [(71,130,4.5),(113,134,4.5)],
    "season2-giant-panda": [(65,129,4),(107,133,4)],
    "season2-sloth": [(70,104,3.5),(108,103,3.5)],
}
# Pudding's nostrils are a closer/squarer dark pair than its wide-set eyes.
# These landmarks refer to the neutral original frame, not the Paw-Paw pet.
ORIGINAL_EYE_OVERRIDES = {
    "capybara": [(54.5,78.5,6),(139.5,78,6)],
}


def measured_eyes(image, landmarks):
    info=[]
    for x,y,radius in landmarks:
        sample=image.getpixel((round(x),round(y-radius*1.8)))
        info.append({"point":[x/192,y/208],"radius":radius,"fur":[v/255 for v in sample[:3]]})
    return info


def fetch(url):
    with urllib.request.urlopen(url, timeout=30) as response:
        data = response.read(8_000_001)
    if len(data) > 8_000_000:
        raise ValueError("Reference asset is too large")
    return data


def eye_pair(image, crown, darkness=125):
    """Find the two isolated dark eye dots, avoiding outlines and the nose."""
    rgba = image.convert("RGBA")
    w, h = rgba.size
    pixels = rgba.load()
    seen = set()
    found = []
    for y in range(int(h * .25), int(h * .76)):
        for x in range(max(0, int(crown[0] - w*.23)), min(w, int(crown[0] + w*.23))):
            if (x, y) in seen:
                continue
            r, g, b, a = pixels[x, y]
            if a < 160 or max(r, g, b) > darkness:
                continue
            todo = [(x, y)]; seen.add((x, y)); component = []
            while todo:
                px, py = todo.pop(); component.append((px, py))
                for nx, ny in ((px-1,py),(px+1,py),(px,py-1),(px,py+1)):
                    if not 0 <= nx < w or not 0 <= ny < h or (nx,ny) in seen:
                        continue
                    r,g,b,a = pixels[nx,ny]
                    if a > 160 and max(r,g,b) <= darkness:
                        seen.add((nx,ny)); todo.append((nx,ny))
            xs, ys = zip(*component)
            box = (min(xs), min(ys), max(xs)+1, max(ys)+1)
            bw, bh = box[2]-box[0], box[3]-box[1]
            if 4 <= bw <= 45 and 4 <= bh <= 45 and .5 < bw/bh < 1.8 and len(component)/(bw*bh) > .35:
                found.append((box, len(component)))
    pairs = []
    for left, area in found:
        for right, other in found:
            lx,ly=(left[0]+left[2])/2,(left[1]+left[3])/2
            rx,ry=(right[0]+right[2])/2,(right[1]+right[3])/2
            if not lx < crown[0] < rx or not w*.045 < rx-lx < w*.50:
                continue
            if abs(ly-ry) > h*.08 or min(area,other)/max(area,other) < .4:
                continue
            score=abs(ly-ry)*3+abs((lx+rx)/2-crown[0])+abs(ly-h*.52)*.3
            pairs.append((score, (left,right)))
    if pairs:
        return min(pairs, key=lambda pair:pair[0])[1]
    # Eyes on unusual animals (e.g. a chameleon's) are tuned in metadata later.
    return [(int(crown[0]-w*.075-6),int(h*.51-6),int(crown[0]-w*.075+6),int(h*.51+6)),
            (int(crown[0]+w*.075-6),int(h*.51-6),int(crown[0]+w*.075+6),int(h*.51+6))]


def bake(companion):
    remote_id=companion["id"]
    pet_id="pawpaw-"+remote_id
    folder=SOURCE / remote_id; folder.mkdir(parents=True,exist_ok=True)
    images={}; sources={}
    for pose in POSES:
        path=folder / f"{pose}.webp"
        url=f"{BASE}public/sprites/{remote_id}/{remote_id}-{pose}.{companion['ext']}"
        data=path.read_bytes() if path.exists() else fetch(url)
        image=Image.open(io.BytesIO(data)).convert("RGBA")
        if image.width > 1200 or image.height > 800 or image.getchannel("A").getextrema()[0] != 0:
            raise ValueError(f"Invalid transparent preview: {remote_id}")
        if not path.exists(): path.write_bytes(data)
        images[pose]=image
        sources[pose]={"url":url,"sha256":hashlib.sha256(data).hexdigest()}
    bounds=[image.getchannel("A").getbbox() for image in images.values()]
    crop=(min(b[0] for b in bounds),min(b[1] for b in bounds),max(b[2] for b in bounds),max(b[3] for b in bounds))
    scale=min(180/(crop[2]-crop[0]),182/(crop[3]-crop[1]))
    size=(round((crop[2]-crop[0])*scale),round((crop[3]-crop[1])*scale))
    fitted={key:value.crop(crop).resize(size,Image.Resampling.LANCZOS) for key,value in images.items()}
    atlas=Image.new("RGBA",(192*8,208*9))
    for row in range(9):
        for column in range(8):
            phase=column*math.pi/4
            if row == 0: pose="both-down" if column == 5 else "both-up"
            elif row in (1,2,7): pose="left-down" if column%2 == 0 else "right-down"
            elif row == 5: pose="both-down"
            elif row in (6,8): pose="both-down" if column in (3,4) else "both-up"
            else: pose="both-up"
            frame=fitted[pose]
            lift=[0,0,7,19,26,18,5,0][column] if row == 4 else round(abs(math.sin(phase))*2) if row in (1,2,7) else 0
            angle=math.sin(phase)*2 if row in (1,2,3) else 0
            if angle: frame=frame.rotate(angle,resample=Image.Resampling.BICUBIC,expand=False)
            x=column*192+(192-size[0])//2
            y=row*208+208-10-size[1]-lift
            atlas.alpha_composite(frame,(x,y))
    target=BUNDLED / remote_id; target.mkdir(parents=True,exist_ok=True)
    atlas.save(target / "spritesheet.webp",lossless=True,method=6)
    preview=Image.new("RGBA",(192,208));preview.alpha_composite(fitted["both-up"],((192-size[0])//2,208-10-size[1]));preview.save(target / "preview.png")
    original=images["both-up"]
    crown=(original.width*companion["head"][0],original.height*companion["head"][1])
    eyes=eye_pair(original,crown)
    offset_x=(192-size[0])/2; offset_y=208-10-size[1]
    def point(x,y): return [(offset_x+(x-crop[0])*scale)/192,(offset_y+(y-crop[1])*scale)/208]
    eye_info=[]
    for x0,y0,x1,y1 in eyes:
        x,y=(x0+x1)/2,(y0+y1)/2
        sample=original.getpixel((max(0,min(original.width-1,int(x))),max(0,min(original.height-1,int(y-max(8,(y1-y0)*.95))))))
        eye_info.append({"point":point(x,y),"radius":max(2.3,(x1-x0)*scale*.60),"fur":[v/255 for v in sample[:3]]})
    paw_centers=[]
    up,down=images["both-up"].load(),images["both-down"].load()
    for side in (-1,1):
        sx=sy=weight=0
        for y in range(int(original.height*.55),original.height):
            for x in range(original.width):
                if (x-crown[0])*side < original.width*.04: continue
                a,b=up[x,y],down[x,y]
                difference=sum(abs(i-j) for i,j in zip(a,b))
                if a[3]>160 and difference>90:
                    sx+=x;sy+=y;weight+=1
        value=point(sx/weight,sy/weight) if weight else [.30 if side<0 else .72,(offset_y+size[1]*.68)/208]
        paw_centers.append([value[0],1-value[1]])
    eye_span=abs(eye_info[1]["point"][0]-eye_info[0]["point"][0])*192
    profile={"eyes":eye_info,"crown":point(*crown),"accessory_scale":max(.4,min(1.25,eye_span/44)),
             "paw_centers":paw_centers,
             "source":BASE,"season":companion["season"],"unlock_level":companion["level"]}
    if remote_id in EYE_OVERRIDES:
        info=measured_eyes(preview,EYE_OVERRIDES[remote_id])
        profile["eyes"]=info
        profile["crown"]=[sum(e["point"][0] for e in info)/2,min(e["point"][1] for e in info)-24/208]
        profile["accessory_scale"]=max(.4,min(1.25,(info[1]["point"][0]-info[0]["point"][0])*192/44))
    (target / "interaction.json").write_text(json.dumps(profile,indent=2)+"\n")
    manifest={"id":pet_id,"displayName":companion["name"],"description":"Public Paw-Paw website preview, adapted for local PawSync development.","spritesheetPath":"spritesheet.webp","spriteVersionNumber":1,"author":"Paw-Paw"}
    (target / "pet.json").write_text(json.dumps(manifest,indent=2)+"\n")
    # A compact, readable contact sheet of the untouched four published poses.
    contact=Image.new("RGBA",(384,416))
    for index,pose in enumerate(POSES):
        frame=Image.new("RGBA",(192,208));frame.alpha_composite(fitted[pose],((192-size[0])//2,208-10-size[1]));contact.alpha_composite(frame,((index%2)*192,(index//2)*208))
    contact.save(target / "character-sheet.png")
    (folder / "sources.json").write_text(json.dumps(sources,indent=2)+"\n")
    return {"id":pet_id,"name":companion["name"],"folder":"pawpaw/"+remote_id,"columns":8,"rows":9,"source":BASE,"author":"Paw-Paw","origin":"Paw-Paw preview"}


def bake_original_profiles():
    for folder in sorted((ROOT / "macos/Resources/OpenPets/originals").iterdir()):
        path=folder / "spritesheet.webp"
        if not path.exists(): continue
        image=Image.open(path).convert("RGBA").crop((0,0,192,208))
        eyes=eye_pair(image,(96,36),darkness=45 if folder.name == "panda" else 125)
        info=[]
        for x0,y0,x1,y1 in eyes:
            x,y=(x0+x1)/2,(y0+y1)/2
            sample=image.getpixel((int(x),max(0,int(y-max(5,(y1-y0)*.95)))))
            info.append({"point":[x/192,y/208],"radius":max(2.3,(x1-x0)*.6),"fur":[v/255 for v in sample[:3]]})
        if folder.name in ORIGINAL_EYE_OVERRIDES:
            info=measured_eyes(image,ORIGINAL_EYE_OVERRIDES[folder.name])
        profile={"eyes":info,"crown":[.5,36/208],"accessory_scale":1,"paw_centers":[[.37,.32],[.63,.32]]}
        (folder / "interaction.json").write_text(json.dumps(profile,indent=2)+"\n")


def main():
    script=fetch(BASE+"public/companions.js").decode()
    companions=json.loads(re.search(r"window.PAWPAW_COMPANIONS = (\[.*?\]);",script,re.S).group(1))
    if len(companions) != 31: raise ValueError("Reference catalog changed; review before importing")
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        entries=list(pool.map(bake,companions))
    catalog_path=ROOT / "macos/Resources/OpenPets/catalog.json"
    catalog=json.loads(catalog_path.read_text())
    catalog=[entry for entry in catalog if entry.get("origin") != "Paw-Paw preview"]+entries
    catalog_path.write_text(json.dumps(catalog,indent=2)+"\n")
    bake_original_profiles()
    # Keep approved full-body adaptations when refreshing the reference catalog.
    # The unchanged website previews remain preserved under art/pawpaw-reference.
    from bake_fullbody_companions import bake as bake_fullbody
    for entry in entries:
        if (ROOT / "art/pawpaw-fullbody" / f"{entry['id'].removeprefix('pawpaw-')}.png").exists():
            bake_fullbody(entry)
    pack=ROOT / "build/PawSync-pawpaw-preview-pets.zip"
    with zipfile.ZipFile(pack,"w",zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(BUNDLED.rglob("*")):
            if path.is_file(): archive.write(path,path.relative_to(BUNDLED))
    print(f"Baked {len(entries)} public reference companions; character sheets and frame packs: {pack}")


if __name__ == "__main__": main()
