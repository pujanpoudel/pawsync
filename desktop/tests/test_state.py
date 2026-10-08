import copy,json
from pawsync.state import State

def test_names_persist_without_changing_identity(state,catalog):
    pet=catalog.by_id['openpets-default'];state.rename(pet.id,'Mochi',pet.name);state.save()
    restored=State(state.content,state.root);assert restored.name(pet)=='Mochi';assert pet.id=='openpets-default'
    restored.rename(pet.id,'',pet.name);assert restored.name(pet)==pet.name

def test_rhythm_levels_gifts_once(state):
    state.progress['tracks'][2]['xp']=490
    for i in range(10):state.input(now=100+i*.1)
    assert state.level()==2;assert state.hot_until>100.9;assert len(state.progress['gifts'])==1
    gift=copy.deepcopy(state.progress['gifts'][0]);selected=state.collect(gift['id'],2)
    assert selected in state.progress['hats'];assert state.collect(gift['id'],0) is None
    assert state.progress['counters']['gift']==1

def test_focus_queues_one_off_and_snooze_does_not_shift_schedule(state):
    r=dict(id='r',title='Water',type='Hydration',schedule='One-off',nextDue=10,enabled=True,priority=False,minutes=45,times=[])
    state.value['reminders']=[r];assert state.due(now=11,focus=True)==[];assert not r['enabled']
    assert [v['id'] for v in state.due(now=12,focus=False)]==['r'];assert state.due(now=13)==[]
    r.update(schedule='Interval',enabled=True,nextDue=1000);state.snooze('r',now=10)
    assert state.due(now=611)[0]['id']=='r';assert r['nextDue']==1000

def test_merge_unions_higher_levels_and_reset_epoch(state):
    other=copy.deepcopy(state.progress);other['tracks'][0]['xp']=1300;other['hats'].append('free.beanie');state.merge(other)
    assert state.level('season1')==3;assert 'free.beanie' in state.progress['hats'];assert list((state.root/'Backups').glob('*.json'))
    reset=copy.deepcopy(other);reset['epoch']=2;reset['tracks'][0]['xp']=0;reset['hats']=[];state.merge(reset)
    assert state.level('season1')==1;state.merge(other);assert state.progress['epoch']==2;assert 'free.beanie' not in state.progress['hats']

def test_no_credential_fields_persisted(state):
    state.save();assert not any(k in state.file.read_text() for k in ('api_key','bearer','licenseToken','local-hook'))
