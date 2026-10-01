#!/usr/bin/env python3
"""Bake the repository pet and its five sample packs without executing vendor code."""
import json, pathlib, shutil, zipfile
from PIL import Image
ROOT = pathlib.Path(__file__).resolve().parents[1]
out = ROOT / 'macos/Resources/OpenPets'
out.mkdir(parents=True, exist_ok=True)
shutil.copy2(ROOT / 'vendor/openpets/LICENSE', out / 'LICENSE')
catalog = []
def register(identifier, name, data, metadata, source):
    target = out / identifier
    target.mkdir(exist_ok=True)
    (target / 'spritesheet.webp').write_bytes(data)
    (target / 'pet.json').write_text(json.dumps(metadata, indent=2)+'\n')
    image = Image.open(target / 'spritesheet.webp') # Inspection only, original image is unchanged.
    cols, rows = 8, 11 if metadata.get('spriteVersionNumber') == 2 else 9
    assert image.width % cols == 0 and image.height % rows == 0, (identifier,image.size,rows)
    catalog.append(dict(id='openpets-'+identifier,name=name,folder=identifier,columns=cols,rows=rows,source=source,author=metadata.get('author','OpenPets')))
register('default', 'OpenPets Buddy', (ROOT/'vendor/openpets/apps/desktop/assets/default-pet-spritesheet.webp').read_bytes(), {'id':'default','displayName':'OpenPets Buddy','spriteVersionNumber':2}, 'https://github.com/OpenPetsHQ/openpets')
for entry in json.loads((ROOT/'vendor/openpets/apps/desktop/catalog.v2.fixture.json').read_text())['pets']:
    with zipfile.ZipFile(ROOT/('build/openpets-'+entry['id']+'.zip')) as archive:
        meta = next(n for n in archive.namelist() if pathlib.PurePosixPath(n).name == 'pet.json')
        image = next(n for n in archive.namelist() if pathlib.PurePosixPath(n).name == 'spritesheet.webp')
        assert archive.getinfo(image).file_size < 25*1024*1024
        metadata=json.loads(archive.read(meta))
        register(entry['id'],entry['displayName'],archive.read(image),metadata,entry['zip'])
(out/'catalog.json').write_text(json.dumps(catalog,indent=2)+'\n')
print('Baked',len(catalog),'OpenPets companions; original sprite sheets and attribution retained.')
