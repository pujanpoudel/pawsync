from __future__ import annotations
import json, math, os, re, shutil, sys, uuid, zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from PIL import Image
from PySide6.QtGui import QImage

ROOT=Path(__file__).resolve().parents[1]
ASSETS=Path(getattr(sys,'_MEIPASS',ROOT))/'assets' if getattr(sys,'frozen',False) else ROOT/'assets'
RESOURCES=Path(getattr(sys,'_MEIPASS',ROOT))/'resources' if getattr(sys,'frozen',False) else ROOT.parent/'macos/Resources'
RIGS=['pixel-cat','shibe','fox','bunny','bear','panda','hamster','otter','capybara']
Image.MAX_IMAGE_PIXELS=25_000_000

def checked_path(root,name):
    if not isinstance(name,str) or '\\' in name or ':' in name: raise ValueError('Invalid pet resource path')
    candidate=root/name
    if any(p.is_symlink() for p in [candidate,*candidate.parents] if p.is_relative_to(root)): raise ValueError('Symlinked pet resources are not accepted')
    path=candidate.resolve()
    if not path.is_relative_to(root.resolve()) or path.is_symlink(): raise ValueError('Invalid pet resource path')
    return path

@dataclass
class Pet:
    id:str; name:str; directory:Path; rows:int=9; group:str='Your creations & imports'; author:str='PawSync'; source:str=''; rig:dict|None=None
    @property
    def profile(self):
        file=self.directory/'interaction.json'
        if not file.exists(): return None
        return read_profile(file)
    def preview(self):
        baked=ASSETS/'previews'/(self.id+'.png')
        if baked.exists(): return QImage(str(baked))
        if self.rig:
            return QImage(str(self.directory/'preview.png'))
        image=QImage(str(self.directory/'spritesheet.webp'))
        if image.isNull(): raise ValueError('Could not decode the pet artwork')
        column=6 if self.rows==11 else 0
        return image.copy(column*image.width()//8,0,image.width()//8,image.height()//self.rows).scaled(136,148)

class Catalog:
    def __init__(self,root):
        self.root=Path(root); self.reload()
    def reload(self):
        self.pets=[]
        for id in RIGS:
            manifest=json.loads((RESOURCES/'Pets'/id/'atlas.json').read_text())
            self.pets.append(Pet(id,manifest['name'],RESOURCES/'OpenPets/originals'/id,group='PawSync originals'))
        for item in json.loads((RESOURCES/'OpenPets/catalog.json').read_text()):
            id=item['id']; group='OpenPets' if id.startswith('openpets-') else 'PawSync originals' if id=='knight-cat' else 'Animal friends'
            self.pets.append(Pet(id,item['name'],checked_path(RESOURCES/'OpenPets',item['folder']),item['rows'],group,item.get('author',''),item.get('source','')))
        for directory in (self.root/'Pets').glob('*'):
            if not directory.is_dir() or directory.is_symlink(): continue
            try:
                if (directory/'atlas.json').exists():
                    atlas=json.loads((directory/'atlas.json').read_text()); validate_rig(atlas,directory)
                    self.pets.append(Pet(atlas['id'],atlas['name'],directory,rig=atlas))
                elif (directory/'pet.json').exists():
                    meta=validate_frames(directory); self.pets.append(Pet(directory.name,meta['displayName'],directory,11 if meta.get('spriteVersionNumber')==2 else 9,author=meta.get('author','')))
            except (ValueError,OSError,KeyError): continue
        groups=['OpenPets','PawSync originals','Animal friends','Your creations & imports'];self.pets.sort(key=lambda p:groups.index(p.group))
        self.by_id={p.id:p for p in self.pets}
    def import_pet(self,source):
        source=Path(source); temporary=self.root/'Pets'/('.import-'+uuid.uuid4().hex); temporary.mkdir(parents=True)
        try:
            if source.is_dir():
                for file in ['pet.json','spritesheet.webp','interaction.json']:
                    path=source/file
                    if path.is_symlink(): raise ValueError('Symlinked pet resources are not accepted')
                    if path.exists(): shutil.copy2(path,temporary/file)
            else:
                if source.stat().st_size>50*1024*1024: raise ValueError('Pet ZIP must be below 50 MB')
                with zipfile.ZipFile(source) as archive:
                    entries=archive.infolist()
                    if len(entries)>256 or sum(i.file_size for i in entries)>64*1024*1024: raise ValueError('Pet ZIP is too large')
                    for entry in entries:
                        if entry.is_dir(): continue
                        if entry.external_attr>>16 & 0o170000==0o120000: raise ValueError('ZIP symlinks are not accepted')
                        checked_path(temporary,entry.filename)
                    candidates=[i for i in entries if PurePosixPath(i.filename).name=='pet.json']
                    if len(candidates)!=1: raise ValueError('Choose a package with one pet.json')
                    prefix=str(PurePosixPath(candidates[0].filename).parent)
                    prefix='' if prefix=='.' else prefix+'/'
                    for file in ['pet.json','spritesheet.webp','interaction.json']:
                        entry=next((i for i in entries if i.filename==prefix+file),None)
                        if entry: (temporary/file).write_bytes(archive.read(entry))
            meta=validate_frames(temporary)
            id='community-'+re.sub('[^a-zA-Z0-9_-]','-',meta.get('id','pet'))[:60]+'-'+uuid.uuid4().hex[:8]
            destination=self.root/'Pets'/id; temporary.rename(destination); self.reload(); return self.by_id[id]
        finally:
            if temporary.exists(): shutil.rmtree(temporary)

def validate_frames(directory):
    file=directory/'pet.json'
    if not file.exists() or file.stat().st_size>16384: raise ValueError('Missing or invalid pet.json')
    meta=json.loads(file.read_text('utf8')); rows=11 if meta.get('spriteVersionNumber')==2 else 9
    if meta.get('spriteVersionNumber',1) not in [1,2] or not isinstance(meta.get('displayName'),str) or not meta['displayName'].strip(): raise ValueError('Unsupported pet metadata')
    if meta.get('spritesheetPath','spritesheet.webp')!='spritesheet.webp': raise ValueError('Unsupported sprite path')
    if (directory/'spritesheet.webp').stat().st_size>50*1024*1024: raise ValueError('Sprite sheet too large')
    with Image.open(directory/'spritesheet.webp') as image:
        if image.width%8 or image.height%rows or image.width*image.height>25_000_000: raise ValueError('Use an 8-column OpenPets v1/v2 sprite sheet')
        image.verify()
    return meta

def validate_rig(atlas,directory):
    if not isinstance(atlas.get('name'),str) or set(atlas.get('parts',{}))!={'body','head','left_paw','right_paw','tail'}: raise ValueError('Invalid pet rig')
    for part in atlas['parts'].values():
        file=checked_path(directory,part['file'])
        if len(part['anchor'])!=2 or any(not 0<=v<=1 for v in part['anchor']): raise ValueError('Invalid anchor')
        with Image.open(file) as image:
            if image.width>4096 or image.height>4096: raise ValueError('Pet part too large')
            image.verify()


def read_profile(file):
    try:
        if file.is_symlink() or file.stat().st_size>32768:return None
        value=json.loads(file.read_text('utf8'))
        def vector(v,n):return isinstance(v,list) and len(v)==n and all(type(x) in (int,float) and math.isfinite(x) and 0<=x<=1 for x in v)
        if not vector(value.get('crown'),2) or not .2<=value.get('accessory_scale',1)<=2:return None
        eyes=value.get('eyes',[])
        if len(eyes)!=2 or any(not vector(e.get('point'),2) or not vector(e.get('fur'),3) or not .5<=e.get('radius',0)<=18 for e in eyes):return None
        return value
    except (OSError,ValueError,TypeError,AttributeError):return None
