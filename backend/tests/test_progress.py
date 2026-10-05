import copy

import pytest
from pydantic import ValidationError

from pawsync.progress import ProgressPayload, fresh, merge


def payload():
    return ProgressPayload.model_validate(fresh()).model_dump()


def test_merge_unions_inventory_and_uses_highest_track_xp():
    a,b=payload(),payload()
    a['tracks'][0]['xp']=1700;b['tracks'][0]['xp']=900;b['tracks'][1]['xp']=2500
    a['hats'].append('free.bow');b['hats'].append('free.star')
    a['achievements']['new-look']=1;b['achievements']['hello']=2
    a['counters']['input']=150;b['counters']['input']=200
    c=merge(a,b)
    assert [t['xp'] for t in c['tracks']]==[1700,2500,0]
    assert set(c['hats'])=={'free.sprout','free.bow','free.star'}
    assert set(c['achievements'])=={'new-look','hello'} and c['counters']['input']==200
    assert a['tracks'][1]['xp']==0  # Merge never modifies its inputs.


def test_reset_epoch_prevents_resurrection_and_is_server_owned():
    old=payload();old['tracks'][1]['xp']=15000;old['hats'].append('free.crown')
    clean=fresh(epoch=1)
    assert merge(clean,old)==clean
    future=copy.deepcopy(old);future['epoch']=999
    assert merge(clean,future)==clean
    assert merge(None,future)['epoch']==0


def test_claimed_gift_cannot_return_after_merge_or_be_claimed_twice():
    a,b=payload(),payload()
    b['gifts']=[dict(id='season1-2',track='season1',level=2,choices=['free.bow','free.star','free.crown'],selected='free.star')]
    a['claimedGifts']=['season1-2'];a['hats'].append('free.star')
    assert merge(a,b)['gifts']==[]
    a=payload();a['gifts']=copy.deepcopy(b['gifts']);a['gifts'][0].pop('selected')
    result=merge(a,b)
    assert len(result['gifts'])==1  # One level reward across Macs.


@pytest.mark.parametrize('change',[
    lambda p:p['hats'].append('accessory.hat'),
    lambda p:p['tracks'][0].update(xp=-1),
    lambda p:p['tracks'][0].update(xp=True),
    lambda p:p['counters'].update(input=-1),
    lambda p:p['achievements'].update(hello=float('nan')),
    lambda p:p['placements'].update(cat=dict(x=0,y=0,scale=100,rotation=0)),
    lambda p:p.update(gifts=[dict(id='season1-2',track='season1',level=2,choices=['free.bow']*3)]),
])
def test_untrusted_progress_cannot_grant_paid_items_or_invalid_state(change):
    p=payload();change(p)
    with pytest.raises(ValidationError):ProgressPayload.model_validate(p)


def test_placements_are_independent_per_pet_and_item_and_merge_safely():
    a,b=payload(),payload()
    a['placements']['knight-cat::free.crown']=dict(x=8,y=-4,scale=1.2,rotation=9)
    b['placements']['knight-cat::accessory.glasses']=dict(x=-3,y=2,scale=1,rotation=0)
    c=ProgressPayload.model_validate(merge(a,b)).model_dump()
    assert c['placements']['knight-cat::free.crown']['x']==8
    assert c['placements']['knight-cat::accessory.glasses']['x']==-3
    c['placements']['knight-cat::free.crown::bad']=dict(x=0,y=0,scale=1,rotation=0)
    with pytest.raises(ValidationError):ProgressPayload.model_validate(c)
