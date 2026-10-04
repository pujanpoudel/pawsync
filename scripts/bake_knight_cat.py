#!/usr/bin/env python3
"""Bake Knight Cat's generated poses into the existing native pet contract."""
import argparse
import json
import zipfile
from bake_fullbody_companions import ROOT, OVERRIDES, bake

PET={
    'id':'knight-cat','name':'Knight Cat','folder':'knight-cat',
    'columns':8,'rows':9,'source':'PawSync','author':'PawSync',
    'origin':'PawSync original'
}
DESCRIPTION='A fluffy kitten knight with silver armor, a cream cape and pink ear bow. Four full-body poses, measured expressions and native file-catching paws.'
# The asymmetrical face is narrower than the generic detector's safe minimum.
# These are reviewed pixel coordinates in the fitted 192 × 208 neutral cell.
OVERRIDES[('knight-cat','neutral')]=[(78.5,84,4.2),(102.5,87.5,4.5)]


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--package-only',action='store_true')
    if parser.parse_args().package_only:
        package();return
    directory=ROOT/'macos/Resources/OpenPets/knight-cat'
    directory.mkdir(parents=True,exist_ok=True)
    manifest={'id':PET['id'],'displayName':PET['name'],'description':DESCRIPTION,
              'spritesheetPath':'spritesheet.webp','spriteVersionNumber':1,'author':'PawSync'}
    (directory/'pet.json').write_text(json.dumps(manifest,indent=2)+'\n')
    proof=bake(PET,source=ROOT/'art/knight-cat/character-sheet-source.png',description=DESCRIPTION)
    profile_path=directory/'interaction.json'
    profile=json.loads(profile_path.read_text())
    profile['paw_centers']=[[64/192,1-144/208],[124/192,1-145/208]]
    profile['foot_centers']=[[79/192,1-186/208],[115/192,1-188/208]]
    profile_path.write_text(json.dumps(profile,indent=2)+'\n')
    proof.save(ROOT/'build/knight-cat-eye-proof.png')
    provenance=json.loads((ROOT/'art/knight-cat/source.json').read_text())
    source=json.loads((directory/'fullbody-source.json').read_text())
    source['reference']=provenance['character_reference']
    source['prompt_manifest']='art/knight-cat/source.json'
    (directory/'fullbody-source.json').write_text(json.dumps(source,indent=2)+'\n')
    catalog_path=ROOT/'macos/Resources/OpenPets/catalog.json'
    catalog=json.loads(catalog_path.read_text())
    catalog=[pet for pet in catalog if pet['id']!=PET['id']]+[PET]
    catalog_path.write_text(json.dumps(catalog,indent=2)+'\n')
    package()
    print('Baked Knight Cat: four source poses, native atlas, measured expressions, receiving/holding and portable resource ZIP.')


def package():
    directory=ROOT/'macos/Resources/OpenPets/knight-cat'
    with zipfile.ZipFile(ROOT/'build/PawSync-knight-cat.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for folder in [directory,ROOT/'macos/Resources/FileInteractions/knight-cat',ROOT/'art/knight-cat']:
            for path in sorted(folder.rglob('*')):
                if path.is_file(): archive.write(path,path.relative_to(ROOT))
        for name in ['scripts/bake_knight_cat.py','scripts/bake_fullbody_companions.py','scripts/import_pawpaw_previews.py','macos/Sources/PawSync/PetClickMotion.swift']:
            archive.write(ROOT/name,name)
        for name in ['knight-cat-expressions.png','knight-cat-click-hop.png']:
            path=ROOT/'build/emotion-character-sheets'/name
            if path.exists(): archive.write(path,path.relative_to(ROOT))


if __name__=='__main__': main()
