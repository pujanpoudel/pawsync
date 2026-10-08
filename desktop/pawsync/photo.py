"""Opt-in photo generation. Keys go only to the selected provider, never our backend."""
from __future__ import annotations
import base64, io, json, shutil, uuid
from collections import deque
from pathlib import Path
import httpx
from PIL import Image, ImageOps
import pillow_heif
from .assets import validate_rig
from .state import atomic_json
pillow_heif.register_heif_opener()
PROMPT='''Use the attached pet photo as the identity reference. Preserve its species, coat markings, fur colors and natural eye colors. Make a lovable rounded 2D cartoon desktop companion with soft brown outlines and natural friendly eyes. Return ONE 3:2 image containing exactly a 3-column by 2-row sprite PART atlas. Every cell is equal size. Do NOT draw a complete pet in any cell. Top-left: ONLY the torso with its two hind feet, no head, forearms or tail. Top-middle: ONLY the complete head including ears and face, neck at bottom. Top-right: ONLY the left forearm and paw, shoulder at top, paw at bottom. Bottom-left: ONLY the matching right forearm and paw, shoulder at top. Bottom-middle: ONLY the tail, base at left; for tailless pets use a tiny tuft. Bottom-right: completely empty. Each of the five pieces is centered in its cell, occupies about 70 percent of the cell, stays fully inside it with generous empty margins. Consistent art and perspective, ready to assemble as a front-facing standing pet. No labels, text, grid lines, shadows, props or accessories. Transparent background or perfectly flat magenta #FF00FF if unavailable; never checkerboard or gradient.'''

def validate_photo(file):
    path=Path(file)
    if path.suffix.lower() not in ('.jpg','.jpeg','.png','.heic','.heif'): raise ValueError('Choose a JPEG, PNG or HEIC photo.')
    if not 0<path.stat().st_size<=15*1024*1024: raise ValueError('Choose a photo smaller than 15 MB.')
    try:
        with Image.open(path) as source:
            if source.format not in ('JPEG','PNG','HEIF') or min(source.size)<128 or max(source.size)>8192 or source.width*source.height>25_000_000: raise ValueError('Use a photo between 128 and 8192 pixels, below 25 megapixels.')
            image=ImageOps.exif_transpose(source).convert('RGB');image.thumbnail((2048,2048));stream=io.BytesIO();image.save(stream,'JPEG',quality=92);return stream.getvalue()
    except ValueError: raise
    except Exception: raise ValueError('This photo could not be opened.') from None

def provider_image(provider,key,photo):
    image='data:image/jpeg;base64,'+base64.b64encode(photo).decode()
    if provider=='OpenAI':
        url='https://api.openai.com/v1/images/edits';headers={'Authorization':'Bearer '+key};body={'model':'gpt-image-2.5-sunburst','images':[{'image_url':image}],'prompt':PROMPT,'n':1,'size':'1536x1024','background':'transparent','output_format':'png','quality':'medium'}
    elif provider=='Gemini':
        url='https://generativelanguage.googleapis.com/v1/models/gemini-3.1-flash-image:generateContent';headers={'x-goog-api-key':key};body={'contents':[{'parts':[{'text':PROMPT},{'inline_data':{'mime_type':'image/jpeg','data':base64.b64encode(photo).decode()}}]}],'generationConfig':{'responseModalities':['TEXT','IMAGE'],'responseFormat':{'image':{'aspectRatio':'3:2','imageSize':'1K'}}}}
    else:
        url='https://api.x.ai/v1/images/edits';headers={'Authorization':'Bearer '+key};body={'model':'grok-imagine-image-2.0','prompt':PROMPT,'image':{'url':image,'type':'image_url'},'n':1,'aspect_ratio':'3:2','response_format':'b64_json'}
    # No automatic retries: direct-provider requests may be billable.
    try:
        with httpx.Client(timeout=120,follow_redirects=False) as client: response=client.post(url,headers=headers,json=body)
        if response.status_code in (401,403): raise ValueError('This provider rejected the API key. Check the key and account permissions.')
        if response.status_code==429: raise ValueError('The provider is busy or your quota is exhausted. Try later.')
        if response.status_code>=400: raise ValueError('The image provider could not generate this pet. Check billing/model access before retrying.')
        if len(response.content)>40*1024*1024: raise ValueError('The generated image was too large.')
        result=response.json();encoded=None
        if provider=='Gemini':
            for candidate in result.get('candidates',[]):
                for part in candidate.get('content',{}).get('parts',[]):
                    data=part.get('inlineData') or part.get('inline_data')
                    if data and not part.get('thought'): encoded=data.get('data');break
        else: encoded=result.get('data',[{}])[0].get('b64_json')
        if not encoded: raise ValueError('The provider did not return an image. No pet was installed.')
        return base64.b64decode(encoded,validate=True)
    except ValueError: raise
    except Exception: raise ValueError('Could not complete image generation. A provider timeout may still be billed; check before retrying.') from None

def transparent_part(source):
    image=source.convert('RGBA');width,height=image.size;px=image.load()
    # Remove only connected flat border matte; preserve white within eyes/fur.
    corner=px[0,0];queue=deque([(x,0) for x in range(width)]+[(x,height-1) for x in range(width)]+[(0,y) for y in range(height)]+[(width-1,y) for y in range(height)]);seen=set()
    def matte(pixel): return pixel[3]<20 or (corner[3]>=20 and sum(abs(pixel[c]-corner[c]) for c in range(3))<70)
    while queue:
        x,y=queue.popleft()
        if (x,y) in seen: continue
        seen.add((x,y))
        if not matte(px[x,y]): continue
        px[x,y]=(0,0,0,0)
        for a,b in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
            if 0<=a<width and 0<=b<height and (a,b) not in seen: queue.append((a,b))
    box=image.getbbox()
    if not box or box[0]<=1 or box[1]<=1 or box[2]>=width-1 or box[3]>=height-1: raise ValueError('Generated parts overlap their cells. No pet was installed; try a new generation.')
    count=sum(image.getchannel('A').histogram()[21:])
    if not width*height/200<count<width*height*.9: raise ValueError('A generated pet part is missing or has an invalid background.')
    return image.crop(box)

def prepare_sheet(raw,name,root):
    with Image.open(io.BytesIO(raw)) as sheet:
        if not (600<=sheet.width<=3072 and 400<=sheet.height<=2048 and abs(sheet.width/sheet.height-1.5)<.05): raise ValueError('Expected a 3 × 2 part sheet. No pet was installed.')
        w,h=sheet.width//3,sheet.height//2;cells=[(0,0),(1,0),(2,0),(0,1),(1,1)];images=[transparent_part(sheet.crop((x*w,y*h,(x+1)*w,(y+1)*h))) for x,y in cells]
    id='custom-'+uuid.uuid4().hex;directory=Path(root)/'Drafts'/id;directory.mkdir(parents=True)
    keys=['body','head','left_paw','right_paw','tail'];sizes=[[92,96],[116,104],[38,54],[38,54],[58,74]];anchors=[[.5,.12],[.5,.1],[.5,.9],[.5,.9],[.1,.5]];offsets=[[0,0],[0,70],[-35,60],[35,60],[-38,25]]
    try:
        parts={}
        for key,image,size,anchor,offset in zip(keys,images,sizes,anchors,offsets):
            image.save(directory/(key+'.png'));parts[key]={'file':key+'.png','display_size':size,'anchor':anchor,'parent_offset':offset}
        atlas={'id':id,'name':name.strip()[:80] or 'My little friend','parts':parts};atomic_json(directory/'atlas.json',atlas);make_preview(directory,atlas);validate_rig(atlas,directory);return directory
    except Exception: shutil.rmtree(directory);raise

def prepare_backend(package,name,root):
    id='custom-'+uuid.uuid4().hex;directory=Path(root)/'Drafts'/id;directory.mkdir(parents=True)
    try:
        parts={}
        for key,part in package['parts'].items():
            raw=base64.b64decode(part['png_base64'],validate=True)
            if len(raw)>8*1024*1024: raise ValueError('Generated part too large.')
            (directory/(key+'.png')).write_bytes(raw);parts[key]={k:v for k,v in part.items() if k not in ('png_base64','url')};parts[key]['file']=key+'.png'
        atlas={'id':id,'name':name.strip()[:80] or 'My little friend','parts':parts};validate_rig(atlas,directory);atomic_json(directory/'atlas.json',atlas);make_preview(directory,atlas);return directory
    except Exception: shutil.rmtree(directory);raise ValueError('Could not prepare the generated pet. Please retry.') from None

def make_preview(directory,atlas):
    image=Image.new('RGBA',(192,208));origin=(96,170)
    for key in ('tail','body','head','left_paw','right_paw'):
        part=atlas['parts'][key];source=Image.open(directory/part['file']).convert('RGBA');size=part.get('display_size',{'body':[120,96],'head':[150,125],'left_paw':[32,40],'right_paw':[32,40],'tail':[70,45]}[key]);source=source.resize(tuple(map(int,size)),Image.Resampling.LANCZOS);anchor=part['anchor'];off=part.get('parent_offset',[0,0]);image.alpha_composite(source,(round(origin[0]+off[0]-anchor[0]*size[0]),round(origin[1]-off[1]-(1-anchor[1])*size[1])))
    image.save(directory/'preview.png')

def install_draft(directory,root):
    directory=Path(directory);destination=Path(root)/'Pets'/directory.name;destination.parent.mkdir(parents=True,exist_ok=True);directory.rename(destination);return destination
