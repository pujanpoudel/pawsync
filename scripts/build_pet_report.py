#!/usr/bin/env python3
"""Create the inventory report from shipped manifests and the native emotion enum."""
import json
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
DESCRIPTIONS={
    'happy':'Smiling eye arcs and soft blush; ordinary positive reactions.',
    'curious':'Two attentive open eyes with gently raised brows; cursor interest.',
    'surprised':'Small dark bead eyes with warm highlights; brief boop/file receiving.',
    'affectionate':'Closed smiling eyes, blush and small hearts; petting and cuddles.',
    'shy':'Lowered lids, blush and a slight lean; gentle ambient reaction.',
    'sad':'Soft lowered eyes and a small tear; expression preview.',
    'sleepy':'Closed relaxed eye arcs; idle/focus sleep.',
    'excited':'Bright closed-eye smile and sparkles; rapid typing.',
    'proud':'Smiling eyes, blush and sparkles; a successful file catch.',
    'focused':'Retains the original eyes with subtle concentration brows; typing.',
    'playful':'A matching smile in both eyes; one of the direct-click cuddle responses.',
    'delighted':'Smiling closed eyes, blush and little sparkles; direct affection.',
    'cozy':'Relaxed closed eyes and blush; calm cuddling.',
    'grumpy':'Small slanted lids; a previewable expression, not a random punishment.',
}


def main():
    resources=ROOT/'macos/Resources/OpenPets'
    catalog=json.loads((resources/'catalog.json').read_text())
    source=(ROOT/'macos/Sources/PawSync/PetEmotion.swift').read_text()
    cases=re.search(r'case ([a-z,]+)\n',source).group(1).split(',')
    pets=[]
    for folder in sorted((resources/'originals').iterdir()):
        manifest=json.loads((folder/'pet.json').read_text())
        pets.append({'id':manifest['id'],'name':manifest['displayName'],'group':'PawSync originals','folder':'originals/'+folder.name,'rows':9,'columns':8})
    for pet in catalog:
        group='Full-body Paw-Paw adaptations' if pet.get('origin')=='Paw-Paw preview' else 'PawSync originals' if pet.get('origin')=='PawSync original' else 'OpenPets imports'
        pets.append({'id':pet['id'],'name':pet['name'],'group':group,'folder':pet['folder'],'rows':pet['rows'],'columns':pet['columns']})
    for pet in pets:
        directory=resources/pet['folder'];path=directory/'interaction.json'
        profile=json.loads(path.read_text()) if path.exists() else None
        pet['measured_face']=profile is not None
        pet['full_body_adaptation']=bool(pet['group']=='Full-body Paw-Paw adaptations' and profile and profile.get('full_body'))
        pet['emotion_states']=len(cases)
        pet['face_playback']='14 measured native expressions' if profile else 'Authored OpenPets faces and mapped reactions'
        pet['authored_file_poses']=(ROOT/'macos/Resources/FileInteractions'/pet['id']/'receive.png').exists()
        pet['desktop_caption']=pet['id'] not in ('bear','pawpaw-bear')
    expressions=[{'id':case,'name':case.capitalize(),'description':DESCRIPTIONS[case],'new':case in ('playful','delighted','cozy','grumpy')} for case in cases]
    totals={'bundled_companions':len(pets),'originals':sum(p['group']=='PawSync originals' for p in pets),'openpets_imports':sum(p['group']=='OpenPets imports' for p in pets),'full_body_adaptations':sum(p['full_body_adaptation'] for p in pets),'emotion_states':len(cases),'measured_faces':sum(p['measured_face'] for p in pets),'authored_file_pose_sets':sum(p['authored_file_poses'] for p in pets),'atlas_cells':sum(p['rows']*p['columns'] for p in pets)}
    assert totals['bundled_companions']==47 and totals['originals']==10 and totals['openpets_imports']==6 and totals['full_body_adaptations']==31 and totals['measured_faces']==41 and totals['emotion_states']==14 and totals['authored_file_pose_sets']==41,totals
    report={'date':'2026-10-04','source':'Local bundled manifests, measured face profiles and PetEmotion.swift; user-installed/custom pets excluded.','totals':totals,'pets':pets,'expressions':expressions}
    (ROOT/'docs/pet-expression-report.json').write_text(json.dumps(report,indent=2)+'\n')
    sections=['# PawSync pet and expression report','', 'Snapshot: 4 October 2026. Source: bundled manifests, face profiles, authored pose resources and the native animation code. User-installed and cloud-generated custom pets are additional and are excluded from these fixed counts.','', '## Inventory','', f"**{totals['bundled_companions']} selectable bundled companions**, comprising {totals['originals']} PawSync originals (including Knight Cat), six OpenPets imports and 31 full-body Paw-Paw adaptations. These are distinct companion/art variants, rather than a count of unique animal species.",'', f"**14 named expression states**, including Playful, Delighted, Cozy and Grumpy. {totals['measured_faces']} pets have measured facial profiles and procedural eyelids/pupils/blush. The six OpenPets imports preserve their authored face artwork and map the state requests to their existing reaction clips with limited accent overlays; they do not gain 14 newly drawn faces.",'', f"{totals['authored_file_pose_sets']} companions have authored receive/hold pose resources: ten originals and all 31 full-body adaptations. The adaptations contain 124 authored source poses (four per pet); Knight Cat adds four more source poses. The {totals['atlas_cells']:,} atlas cells include repeated poses and generated motion timing; they are not {totals['atlas_cells']:,} distinct hand-drawn pictures.",'', 'Knight Cat uses the user-provided armored kitten reference, with silver armor, a cream cape, a pink ear bow and a safely sheathed sword so both hands remain usable. Its exact generation/edit prompts and source references are preserved in `art/knight-cat/source.json`.','']
    for group in ['PawSync originals','OpenPets imports','Full-body Paw-Paw adaptations']:
        group_pets=[p for p in pets if p['group']==group]
        sections += [f'### {group} ({len(group_pets)})','']
        sections += [f"- {p['name']} (`{p['id']}`)" for p in group_pets]+['']
    sections += ['## Expressions','']
    sections += [f"- **{e['name']}**{' (new)' if e['new'] else ''}: {e['description']}" for e in expressions]
    sections += ['', '## What the pet does','', '- Direct single click: a finite crouch, two springy raised-paw kitten hops and soft landings inspired by the supplied Pinterest GIF; cycles delighted, playful, affectionate and cozy moods. Typing interrupts it immediately. It does not equip music headphones.', '- Double tap: opens the existing quick-action menu. Hover does not open that menu.', '- Click and drag: distinct stroking/petting animation. Option-drag repositions the companion.', '- Typing: alternating front-limb taps; fast bursts can show excitement. Ambient mouse clicks keep brief reactions rather than always dancing.', '- Walking: a bounded on-screen move, with an alternating lower-limb/flipper gait on the full-body adaptations. Jumping remains a finite arced move.', '- Music: separate audio-triggered dance with the free built-in headphones.', '- Files: arms-open receive pose, cancellation back to rest/hold, proud catch and a subtle held note. References stay temporary and original filenames/locations remain unchanged.', '- Sleep and reminders: existing idle/focus sleep, screen-sleep render suspension and in-character reminder delivery remain available.', '', '## Corrected presentation','', 'Pudding the Capybara uses measured wide-set eye landmarks in the neutral, receive and hold artwork. Its nostrils are no longer used as expression anchors. Full-body adaptations have reviewed eye landmarks, including masks, side-facing eyes and asymmetric heads; the receive pose registers its facial landmarks against the reviewed neutral face.', '', 'Both Cocoa the Bear and the Paw-Paw-derived Bear omit their desktop name/level caption. Pet names remain visible in Companion/Gallery, and level/XP remain in Settings → Advanced → Activity.', '', 'All 31 adaptations now show complete bodies with feet, flippers or tails appropriate to the animal, rather than the website’s original half-body peeking silhouette. The original downloaded website references remain unchanged under `art/pawpaw-reference/`. The new four-pose sheets and exact built-in imagegen prompts are under `art/pawpaw-fullbody/` and `art/pawpaw-fullbody-sources.json`.', '', '## Resources and checks','', '- `build/PawSync-knight-cat.zip`: Knight Cat atlas, source art, prompts, facial metadata and receiving/holding resources.', '- `build/PawSync-expressive-pets.zip`: all bundled resources, full-body source sheets, original catch/hold sheets, exact prompts, code and native emotion contact sheets.', '- `build/emotion-character-sheets/`: one native rendered sheet per bundled pet, including all 14 expressions, direct cuddle, receiving, catch and hold.', '- `docs/pet-expression-report.json`: machine-readable counts and per-pet coverage.', '- Native emotion, motion, asset, UI dispatch and temporary-file checks cover source/render behavior. Physical cross-app input, OS drag-out acceptance, Instruments budgets and notarized release acceptance are separate checks.', '', 'Reference attribution remains Paw-Paw/OpenPets where applicable. Generated adaptations do not establish commercial redistribution rights to another creator’s character designs.']
    (ROOT/'docs/pet-expression-report.md').write_text('\n'.join(sections)+'\n')
    print(json.dumps(report))


if __name__=='__main__': main()
