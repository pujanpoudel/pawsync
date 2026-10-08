"""Deterministic first-frame thumbnails; artwork remains unchanged."""
import json
from pathlib import Path
from PIL import Image
root=Path(__file__).resolve().parent;res=root.parent/'macos/Resources';output=root/'assets/previews';output.mkdir(exist_ok=True)
entries=[{'id':i,'folder':'originals/'+i,'rows':9} for i in ['pixel-cat','shibe','fox','bunny','bear','panda','hamster','otter','capybara']]+json.loads((res/'OpenPets/catalog.json').read_text())
for pet in entries:
    with Image.open(res/'OpenPets'/pet['folder']/'spritesheet.webp') as sheet:
        w,h=sheet.width//8,sheet.height//pet['rows'];col=6 if pet['rows']==11 else 0
        image=sheet.crop((w*col,0,w*(col+1),h));image.thumbnail((136,148),Image.Resampling.LANCZOS);image.save(output/(pet['id']+'.png'))
print('Exported',len(entries),'unchanged frame previews')
