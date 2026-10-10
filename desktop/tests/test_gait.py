import math
from PySide6.QtCore import QPoint
from PySide6.QtGui import QImage
from pawsync.gait import GAITS, WalkingFrames, displacement
from pawsync.companion import Companion


def test_every_bundled_pet_has_a_gait(catalog):
    assert set(GAITS)=={pet.id for pet in catalog.pets}
    for id in ('pixel-cat','shibe','fox','panda','hamster','otter','capybara'):
        gait=GAITS[id]
        assert gait['kind']=='quadruped' and len(gait['limbs'])==4
        assert [l['phase'] for l in gait['limbs']]==[0,.5,.5,0]
    assert GAITS['bunny']['kind']=='hop'
    for id in ('openpets-default','openpets-snoopy','openpets-clippit','openpets-tux','openpets-wall-e','openpets-dobby'):
        assert GAITS[id]['kind']=='authored'


def test_gait_recovers_forward_and_keeps_face_fixed():
    for gait in GAITS.values():
        if not gait['limbs']:continue
        # No deformation reaches the eyes, ears or crown.
        for x in range(0,193,16):assert displacement(gait,x,85,.3)==(0,0)
        for limb in gait['limbs']:
            if limb['role']!='leg' or gait['kind'] not in ('biped','quadruped'):continue
            x,y=limb['tip'];phase=(.8-limb['phase'])%1
            # A recovering foot clears the floor.
            dx,dy=displacement(gait,x,y,phase)
            assert dy < -.2
        for phase in (0,.2,.5,.8):
            a=displacement(gait,96,180,phase);b=displacement(gait,96,180,phase+1)
            assert all(math.isclose(x,y,abs_tol=1e-9) for x,y in zip(a,b))


def test_each_procedural_pet_animates_actual_pixels_without_changing_eyes(catalog):
    for pet in catalog.pets:
        walker=WalkingFrames(pet)
        if not walker.procedural:continue
        gait=walker.gait;sheet=QImage(str(pet.directory/'spritesheet.webp'))
        base=sheet.copy(0,gait['row']*sheet.height()//pet.rows,sheet.width()//8,sheet.height()//pet.rows).scaled(192,208)
        first=walker.frame(base,.2);second=walker.frame(base,.8)
        assert first!=second,pet.id
        assert first.copy(0,0,192,85)==second.copy(0,0,192,85),pet.id
        assert walker.frame(base,.2).cacheKey()==first.cacheKey()
        assert len(walker.cache)==2


def test_walking_uses_neutral_pose_and_preserves_position_when_interrupted(qtbot,state,catalog,content):
    state.progress['pets'].append('pawpaw-shiba');state.choose(catalog.by_id['pawpaw-shiba'])
    pet=Companion(state,catalog,content);qtbot.addWidget(pet);pet.heartbeat.stop();pet.move(200,100)
    pet.walk_to(QPoint(450,100));pet.advance(pet.travel[2]+.2)
    assert pet.row==0 and pet.column==0 # never the waving row
    position=pet.pos();pet.react('Typing')
    assert pet.travel is None and pet.pos()==position
    assert len(pet.art.walking.cache)<=24
