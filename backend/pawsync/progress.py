"""Progress is independent of payment entitlements. Merge under the account lock."""
import copy
import math
import re

from pydantic import BaseModel, ConfigDict, Field, model_validator

TRACKS={'season1':'Season 1','season2':'Season 2','originals':'PawSync originals'}
ID=re.compile(r'^[a-zA-Z0-9._-]{1,100}$')


def fresh(epoch=0):
    return dict(version=1,epoch=epoch,revision=0,tracks=[dict(id=k,name=v,xp=0) for k,v in TRACKS.items()],activeTrack='originals',followsPet=False,pets=['knight-cat','pixel-cat','shibe'],hats=['free.sprout'],favoritePets=[],favoriteHats=[],gifts=[],claimedGifts=[],achievements={},discoveries=[],counters={},automaticCheers=True,syncEnabled=True,placements={})


class ProgressPayload(BaseModel):
    model_config=ConfigDict(extra='forbid')
    version:int=Field(ge=1,le=1)
    epoch:int=Field(ge=0,le=1_000_000)
    revision:int=Field(ge=0,le=1_000_000_000)
    tracks:list[dict]=Field(min_length=3,max_length=13)
    activeTrack:str
    followsPet:bool
    pets:list[str]=Field(max_length=2000)
    hats:list[str]=Field(max_length=1000)
    favoritePets:list[str]=Field(max_length=2000)
    favoriteHats:list[str]=Field(max_length=1000)
    gifts:list[dict]=Field(max_length=500)
    claimedGifts:list[str]=Field(max_length=10000)
    achievements:dict[str,float]=Field(max_length=100)
    discoveries:list[str]=Field(max_length=100)
    counters:dict[str,int]=Field(max_length=2100)
    automaticCheers:bool
    syncEnabled:bool
    placements:dict[str,dict]=Field(max_length=2000)

    @model_validator(mode='after')
    def validate(self):
        ids={t.get('id') for t in self.tracks}
        if not set(TRACKS)<=ids or len(ids)!=len(self.tracks) or self.activeTrack not in ids or any(not isinstance(k,str) or not ID.fullmatch(k) or k not in TRACKS and not k.startswith('collection.') for k in ids): raise ValueError('Invalid track')
        for t in self.tracks:
            if set(t)!={'id','name','xp'} or type(t['xp']) is not int or not 0<=t['xp']<=500_000_000: raise ValueError('Invalid XP')
            if not isinstance(t['name'],str) or not 1<=len(t['name'])<=80: raise ValueError('Invalid track name')
            t['name']=TRACKS.get(t['id'],t['name'])
        for values in [self.pets,self.hats,self.favoritePets,self.favoriteHats,self.claimedGifts,self.discoveries,list(self.achievements),list(self.counters)]:
            if any(not ID.fullmatch(v) for v in values): raise ValueError('Invalid identifier')
        if any(not h.startswith('free.') for h in self.hats+self.favoriteHats): raise ValueError('Paid items cannot be granted by progress')
        if any(not 0<=v<=1_000_000_000 for v in self.counters.values()): raise ValueError('Invalid counters')
        if any(not math.isfinite(t) or not 0<=t<=10_000_000_000 for t in self.achievements.values()): raise ValueError('Invalid achievement date')
        gift_ids=set()
        for g in self.gifts:
            if set(g)-{'id','track','level','choices','selected'} or not ID.fullmatch(g.get('id','')) or g.get('id') in gift_ids or g.get('track') not in ids or type(g.get('level')) is not int or not 1<=g['level']<=1_000_001: raise ValueError('Invalid gift')
            gift_ids.add(g['id'])
            choices=g.get('choices',[])
            if len(choices)!=3 or len(set(choices))!=3 or any(not isinstance(c,str) or not ID.fullmatch(c) or not c.startswith('free.') for c in choices) or g.get('selected') is not None and g['selected'] not in choices: raise ValueError('Invalid gift choices')
        for key in self.placements:
            parts=key.split('::')
            if not 1<=len(parts)<=2 or any(not ID.fullmatch(part) for part in parts): raise ValueError('Invalid placement identifier')
        for p in self.placements.values():
            if set(p)!={'x','y','scale','rotation'} or any(type(v) not in (int,float) or not math.isfinite(v) for v in p.values()) or abs(p['x'])>100 or abs(p['y'])>100 or not .4<=p['scale']<=2 or abs(p['rotation'])>90: raise ValueError('Invalid placement')
        return self


def merge(local,remote):
    """An old Mac cannot resurrect progress after an account reset."""
    if local is None:
        # Epoch is server-owned. A local-only reset does not advance account epoch.
        merged=copy.deepcopy(remote);merged['epoch']=0;return merged
    if remote['epoch']!=local['epoch']:
        return copy.deepcopy(local)
    result=copy.deepcopy(local)
    known_tracks={t['id'] for t in result['tracks']}
    result['tracks'] += [copy.deepcopy(t) for t in remote['tracks'] if t['id'] not in known_tracks]
    for track in result['tracks']:
        track['xp']=max(track['xp'],next((t['xp'] for t in remote['tracks'] if t['id']==track['id']),0))
    for key in ['pets','hats','favoritePets','favoriteHats','claimedGifts','discoveries']:
        result[key]=sorted(set(result[key]+remote[key]))
    for k,v in remote['achievements'].items(): result['achievements'].setdefault(k,v)
    for k,v in remote['counters'].items(): result['counters'][k]=max(result['counters'].get(k,0),v)
    known={g['id'] for g in result['gifts']}
    result['gifts'] += [g for g in remote['gifts'] if g['id'] not in known]
    result['gifts']=[g for g in result['gifts'] if g['id'] not in result['claimedGifts']]
    for k,v in remote['placements'].items(): result['placements'].setdefault(k,v)
    result['revision']=max(result['revision'],remote['revision'])+1
    # Bound merged unions as well as each request, preventing cumulative flooding.
    return ProgressPayload.model_validate(result).model_dump()
