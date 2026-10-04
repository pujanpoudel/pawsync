#!/usr/bin/env python3
"""Bake authored full-body four-pose sheets into the native frame/face contract.

Only extracts and fits generated cells; originals and exact prompts are preserved.
Use --allow-partial during content production, then require all 31 for delivery.
"""
import argparse
import hashlib
import json
import math
import statistics
import zipfile
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageStat
from import_pawpaw_previews import measured_eyes

ROOT = Path(__file__).resolve().parents[1]
OVERRIDES = {
    ('wolf','neutral'): [(65,94.5,4),(114.5,98.5,4)],
    ('koala','neutral'): [(63,102,4),(123,105,4)],
    ('season2-sheep','neutral'): [(68,88.5,3),(103,90,3)],
    ('season2-penguin','neutral'): [(86,87.5,3.6),(126,87.5,3.6)],
    ('season2-shetland-sheepdog','neutral'): [(74,79,4),(106,80,4)],
    ('season2-squirrel','neutral'): [(61.5,106.5,4),(97,108.5,4)],
    ('season2-bat','neutral'): [(71,100,4),(103.5,102.5,4.3)],
    ('season2-hedgehog','neutral'): [(63.5,106.5,3.5),(104,106.5,3.5)],
    ('season2-skunk','neutral'): [(60,92,4),(99,96.5,4)],
    ('season2-chameleon','neutral'): [(45.5,104.5,3),(90.5,104.5,3.5)],
    ('season2-opossum','neutral'): [(62.5,79,3.5),(85.5,84.5,3.5)],
    ('season2-axolotl','neutral'): [(63.5,91.5,3.8),(111.5,93,4)],
    ('fox','receive'): [(55.5,81.5,4.5),(110.5,84.5,4.5)],
    ('pig','receive'): [(59,92.5,4.5),(118,95,4.5)],
    ('raccoon','receive'): [(55,90.5,4.5),(99,94,4.5)],
    ('seal','receive'): [(65,88,4),(106.5,89.5,4)],
    ('season2-bat','receive'): [(62,93.5,4),(94,95.5,4.5)],
    ('season2-chameleon','receive'): [(32,74,3),(77,74,3.5)],
    ('season2-axolotl','receive'): [(62.5,83.5,3.8),(110.5,85,4)],
}


def extract_character(frame):
    """Exclude disconnected strokes from neighbouring sheet cells, without
    moving/scaling the animal or changing any measured landmark coordinates."""
    pixels=frame.load();seen=set();largest=set()
    for y in range(208):
        for x in range(192):
            if (x,y) in seen or pixels[x,y][3]<=24: continue
            todo=[(x,y)];seen.add((x,y));component=set()
            while todo:
                px,py=todo.pop();component.add((px,py))
                for nx,ny in ((px-1,py),(px+1,py),(px,py-1),(px,py+1)):
                    if not 0<=nx<192 or not 0<=ny<208 or (nx,ny) in seen: continue
                    if pixels[nx,ny][3]>24:seen.add((nx,ny));todo.append((nx,ny))
            if len(component)>len(largest):largest=component
    keep=set(largest)
    for x,y in largest:
        for dx in (-1,0,1):
            for dy in (-1,0,1):keep.add((x+dx,y+dy))
    for y in range(208):
        for x in range(192):
            if (x,y) not in keep:pixels[x,y]=(0,0,0,0)
    return frame


def detect_eyes(image):
    p=image.load();seen=set();found=[]
    for y in range(30,116):
        for x in range(20,173):
            if (x,y) in seen or p[x,y][3]<160 or max(p[x,y][:3])>65: continue
            todo=[(x,y)];seen.add((x,y));component=[]
            while todo:
                px,py=todo.pop();component.append((px,py))
                for nx,ny in ((px-1,py),(px+1,py),(px,py-1),(px,py+1)):
                    if not 0<=nx<192 or not 0<=ny<208 or (nx,ny) in seen: continue
                    if p[nx,ny][3]>160 and max(p[nx,ny][:3])<=65:
                        seen.add((nx,ny));todo.append((nx,ny))
            xs,ys=zip(*component);box=min(xs),min(ys),max(xs)+1,max(ys)+1
            bw,bh=box[2]-box[0],box[3]-box[1]
            if 3<=bw<=26 and 3<=bh<=26 and .45<bw/bh<2.2 and len(component)/(bw*bh)>.35:
                found.append((box,len(component)))
    pairs=[]
    for left,area in found:
        for right,other in found:
            lx,ly=(left[0]+left[2])/2,(left[1]+left[3])/2
            rx,ry=(right[0]+right[2])/2,(right[1]+right[3])/2
            if not lx<96<rx or not 28<rx-lx<126 or abs(ly-ry)>12 or min(area,other)/max(area,other)<.35: continue
            score=abs(ly-ry)*3+abs((lx+rx)/2-96)+abs(ly-82)*.35-min(area,other)*.05-(rx-lx)*.07
            pairs.append((score,[(lx,ly,min(8.5,max(2.3,(left[2]-left[0])*.45))),
                                 (rx,ry,min(8.5,max(2.3,(right[2]-right[0])*.45)))]))
    if not pairs: raise ValueError("No reliable pair of eyes; measure landmarks before shipping")
    return min(pairs,key=lambda item:item[0])[1]


def registered_eyes(image, reference, eyes):
    landmarks=[]
    for eye in eyes:
        x,y=eye['point'][0]*192,eye['point'][1]*208;r=eye['radius'];pad=math.ceil(r*1.7)
        box=(round(x)-pad,round(y)-pad,round(x)+pad+1,round(y)+pad+1)
        template=reference.crop(box);matches=[]
        for dy in range(-32,33):
            for dx in range(-24,25):
                center=image.getpixel((max(0,min(191,round(x)+dx)),max(0,min(207,round(y)+dy))))
                if center[3]<220 or max(center[:3])>125: continue
                sample=image.crop((box[0]+dx,box[1]+dy,box[2]+dx,box[3]+dy))
                error=sum(ImageStat.Stat(ImageChops.difference(template,sample)).mean[:3])+(abs(dx)+abs(dy))*.12
                matches.append((error,dx,dy))
        _,dx,dy=min(matches);landmarks.append((x+dx,y+dy,r))
    return landmarks


def profile(image, remote, pose, reference=None, reference_eyes=None):
    landmarks=OVERRIDES.get((remote,pose)) or (registered_eyes(image,reference,reference_eyes) if reference is not None else detect_eyes(image))
    eyes=measured_eyes(image,landmarks)
    # A single pixel above an eye can hit antialiasing, an eyebrow or a mask
    # outline. Sample the surrounding fur instead of baking that dark speck
    # into a permanent circular eyelid patch.
    for eye,(x,y,radius) in zip(eyes,landmarks):
        samples=[]
        for angle in range(0,360,45):
            sx=round(x+math.cos(math.radians(angle))*radius*2.7)
            sy=round(y+math.sin(math.radians(angle))*radius*2.7)
            pixel=image.getpixel((max(0,min(191,sx)),max(0,min(207,sy))))
            if pixel[3]>220: samples.append(pixel[:3])
        if samples: eye['fur']=[statistics.median(p[channel] for p in samples)/255 for channel in range(3)]
    cx=sum(e['point'][0] for e in eyes)/2;eye_y=sum(e['point'][1] for e in eyes)/2
    return {'eyes':eyes,'crown':[cx,max(.06,eye_y-.18)],
            'accessory_scale':max(.4,min(1.3,(eyes[1]['point'][0]-eyes[0]['point'][0])*192/44)),
            'paw_centers':[[max(.1,cx-.17),.34],[min(.9,cx+.17),.34]],
            'foot_centers':[[max(.12,cx-.17),.115],[min(.88,cx+.17),.115]],
            'full_body':True}


def bake(pet):
    remote=pet['id'].removeprefix('pawpaw-')
    source=ROOT/'art/pawpaw-fullbody'/f'{remote}.png'
    sheet=Image.open(source).convert('RGBA')
    if abs(sheet.width-sheet.height)>16 or sheet.getchannel('A').getextrema() != (0,255):
        raise ValueError(f'Expected a transparent square four-cell sheet: {remote}')
    cw,ch=sheet.width//2,sheet.height//2
    cells=[sheet.crop((x*cw,y*ch,(x+1)*cw,(y+1)*ch)) for y in range(2) for x in range(2)]
    bounds=[cell.getchannel('A').getbbox() for cell in cells]
    if any(b is None for b in bounds): raise ValueError(f'Missing character cell: {remote}')
    crop=min(b[0] for b in bounds),min(b[1] for b in bounds),max(b[2] for b in bounds),max(b[3] for b in bounds)
    scale=min(180/(crop[2]-crop[0]),182/(crop[3]-crop[1]))
    size=round((crop[2]-crop[0])*scale),round((crop[3]-crop[1])*scale)
    fitted=[]
    for cell in cells:
        frame=Image.new('RGBA',(192,208))
        frame.alpha_composite(cell.crop(crop).resize(size,Image.Resampling.LANCZOS),((192-size[0])//2,198-size[1]))
        fitted.append(extract_character(frame))
    directory=ROOT/'macos/Resources/OpenPets'/pet['folder']
    atlas=Image.new('RGBA',(192*8,208*9))
    for row in range(9):
        for column in range(8):
            frame=fitted[(1 if column%2==0 else 2) if row in (1,2,7) else 3 if row==6 else 0]
            # Full bodies need their whole texture cell. SpriteKit moves the
            # sprite for jumps; baking a 26px lift would crop ears/bleed rows.
            lift=round(abs(math.sin(column*math.pi/4))*2) if row in (1,2,7) else 0
            atlas.alpha_composite(frame,(column*192,row*208-lift))
    atlas.save(directory/'spritesheet.webp',lossless=True,method=6)
    fitted[0].save(directory/'preview.png')
    neutral=profile(fitted[0],remote,'neutral')
    (directory/'interaction.json').write_text(json.dumps(neutral,indent=2)+'\n')
    for name,frame in [('typing-left',fitted[1]),('typing-right',fitted[2]),('receive',fitted[3])]:
        pose_directory=directory/name;pose_directory.mkdir(exist_ok=True)
        value=profile(frame,remote,name,fitted[0],neutral['eyes'])
        (pose_directory/'interaction.json').write_text(json.dumps(value,indent=2)+'\n')
    contact=Image.new('RGBA',(384,416))
    for i,frame in enumerate(fitted): contact.alpha_composite(frame,((i%2)*192,(i//2)*208))
    contact.save(directory/'character-sheet.png')
    manifest=json.loads((directory/'pet.json').read_text())
    manifest['description']='Full-body PawSync adaptation of the attributed Paw-Paw reference; authored four-pose sheet and native expressions.'
    (directory/'pet.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (directory/'fullbody-source.json').write_text(json.dumps({'file':str(source.relative_to(ROOT)),'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'tool':'built-in imagegen','reference':pet['source']},indent=2)+'\n')
    file_directory=ROOT/'macos/Resources/FileInteractions'/pet['id'];file_directory.mkdir(parents=True,exist_ok=True)
    for pose,frame in [('receive',fitted[3]),('hold',fitted[0])]:
        frame.save(file_directory/f'{pose}.png');pose_dir=file_directory/pose;pose_dir.mkdir(exist_ok=True)
        value=neutral if pose=='hold' else profile(frame,remote,pose,fitted[0],neutral['eyes'])
        (pose_dir/'interaction.json').write_text(json.dumps(value,indent=2)+'\n')
    proof=fitted[0].copy();draw=ImageDraw.Draw(proof)
    for eye in neutral['eyes']:
        x,y=eye['point'][0]*192,eye['point'][1]*208;r=eye['radius']
        draw.ellipse((x-r,y-r,x+r,y+r),outline=(255,0,120,255),width=1)
    return proof


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--allow-partial',action='store_true');args=parser.parse_args()
    pets=[p for p in json.loads((ROOT/'macos/Resources/OpenPets/catalog.json').read_text()) if p.get('origin')=='Paw-Paw preview']
    available=[p for p in pets if (ROOT/'art/pawpaw-fullbody'/f"{p['id'].removeprefix('pawpaw-')}.png").exists()]
    if not args.allow_partial and len(available)!=31: raise ValueError(f'Only {len(available)} of 31 full-body sheets are available')
    proof=Image.new('RGB',(192*8,232*4),'#f8f4ed');draw=ImageDraw.Draw(proof)
    for i,pet in enumerate(available):
        frame=bake(pet);x=(i%8)*192;y=(i//8)*232;proof.paste(frame,(x,y),frame);draw.text((x+8,y+211),pet['name'],fill='#302520')
    proof.save(ROOT/'build/fullbody-eye-proof.png')
    if len(available)==31:
        with zipfile.ZipFile(ROOT/'build/PawSync-pawpaw-preview-pets.zip','w',zipfile.ZIP_DEFLATED) as archive:
            for path in sorted((ROOT/'macos/Resources/OpenPets/pawpaw').rglob('*')):
                if path.is_file(): archive.write(path,path.relative_to(ROOT/'macos/Resources/OpenPets/pawpaw'))
    print(f'Baked {len(available)} full-body companions, four authored poses each, measured faces and native file-catching poses.')


if __name__=='__main__': main()
