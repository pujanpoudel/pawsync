"""Local names/preferences and server-compatible earned progress. Never stores secrets."""
from __future__ import annotations
import copy, json, math, os, random, re, time, uuid
from pathlib import Path
from datetime import datetime, timedelta
from PySide6.QtCore import QObject, Signal, QStandardPaths


def data_root() -> Path:
    return Path(os.environ.get('PAWSYNC_DATA_DIR') or QStandardPaths.writableLocation(QStandardPaths.AppDataLocation))


def atomic_json(file: Path, value):
    file.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = file.with_name(file.name + '.' + uuid.uuid4().hex + '.tmp')
    try:
        with temporary.open('x', encoding='utf8') as stream:
            os.chmod(temporary, 0o600)
            json.dump(value, stream, ensure_ascii=False, indent=2)
            stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, file)
    finally:
        temporary.unlink(missing_ok=True)


def fresh_progress():
    return dict(version=1, epoch=0, revision=0,
        tracks=[dict(id=i, name=n, xp=0) for i,n in [('season1','Season 1'),('season2','Season 2'),('originals','PawSync originals')]],
        activeTrack='originals', followsPet=False, pets=['knight-cat'], hats=['free.sprout'], favoritePets=[], favoriteHats=[],
        gifts=[], claimedGifts=[], achievements={}, discoveries=[], counters={}, automaticCheers=True, syncEnabled=False, placements={})


DEFAULT_PREFS = dict(companion='openpets-default', accessory='none', headAccessoriesVisible=True, scale=1., opacity=1.,
    mirror=False, muted=True, hidden=False, movement='Roam', anchor='Bottom Dock', clickThrough=False,
    integrations=False, music=False, telemetry=False, greet=True, userName='', login=False,
    walkSpeed=95, wanderInterval=25, edgeTraversal=False, liteMusic=False)


def track_for(pet):
    if pet.startswith('pawpaw-season2-'): return 'season2'
    if pet.startswith('pawpaw-'): return 'season1'
    if pet in ['knight-cat','pixel-cat','shibe','fox','bunny','bear','panda','hamster','otter','capybara']: return 'originals'
    return None


def next_time(times, now):
    values=[]
    date=datetime.fromtimestamp(now)
    for value in times:
        hour,minute=map(int,value.split(':'))
        if not (0<=hour<=23 and 0<=minute<=59): raise ValueError('Use a valid time such as 09:30.')
        candidate=date.replace(hour=hour,minute=minute,second=0,microsecond=0)
        if candidate.timestamp()<=now: candidate+=timedelta(days=1)
        values.append(candidate.timestamp())
    if not values: raise ValueError('Choose at least one time.')
    return min(values)


class State(QObject):
    changed=Signal(); toast=Signal(str,str)
    def __init__(self, content, root=None):
        super().__init__(); self.root=Path(root or data_root()); self.file=self.root/'desktop.json'; self.content=content
        self.value=dict(version=1,prefs=DEFAULT_PREFS.copy(),names={},progress=fresh_progress(),reminders=[],focus={},tools={},features={},moods={})
        try:
            if self.file.exists():
                if self.file.is_symlink() or self.file.stat().st_size>4*1024*1024: raise ValueError('Invalid local state')
                saved=json.loads(self.file.read_text('utf8'))
                if saved.get('version')!=1 or not isinstance(saved.get('prefs'),dict) or not isinstance(saved.get('names',{}),dict): raise ValueError('Invalid local state')
                self.validate_progress(saved['progress'])
                if len(saved.get('reminders',[]))>2000: raise ValueError('Too many reminders')
                self.value.update(saved); self.value['prefs']=DEFAULT_PREFS | saved['prefs']
        except (ValueError,TypeError,KeyError,OSError,json.JSONDecodeError):
            if self.file.exists(): self.file.rename(self.file.with_suffix('.backup-'+uuid.uuid4().hex))
        self.dirty=False; self.last_input=0.; self.rhythm=0; self.hot_until=0.; self.update_unlocks()
    @property
    def prefs(self): return self.value['prefs']
    @property
    def progress(self): return self.value['progress']
    def save(self): atomic_json(self.file,self.value); self.dirty=False
    def set(self,key,value):
        self.prefs[key]=value; self.save(); self.changed.emit()
    def rename(self,pet,name,original):
        name=''.join(c for c in name if c.isprintable()).strip()[:40]
        if not name or name==original: self.value['names'].pop(pet,None)
        else: self.value['names'][pet]=name
        self.save(); self.changed.emit()
    def name(self,pet): return self.value['names'].get(pet.id,pet.name)
    def level(self,track=None): return next((p['xp']//500+1 for p in self.progress['tracks'] if p['id']==(track or self.progress['activeTrack'])),1)
    def can_select(self,pet): return track_for(pet.id) is None or pet.id in self.progress['pets']
    def can_equip(self,item,owned=()):
        if item=='none': return True
        if item in ('accessory.hat','accessory.glasses'): return item in owned
        spec=next((i for i in self.content['items'] if i['id']==item),{})
        return item in self.progress['hats'] and (not spec.get('requiresSKU') or spec['requiresSKU'] in owned)
    def choose(self,pet):
        if not self.can_select(pet): raise ValueError('Keep earning to unlock this friend.')
        self.prefs['companion']=pet.id
        if self.progress['followsPet'] and track_for(pet.id): self.progress['activeTrack']=track_for(pet.id)
        key='tried.'+pet.id
        if key not in self.progress['counters']: self.progress['counters'][key]=1; self.record('friends')
        self.save(); self.changed.emit()
    def record(self,key,count=1):
        counters=self.progress['counters']; counters[key]=min(1_000_000_000,counters.get(key,0)+count)
        for achievement in self.content['achievements']:
            if counters.get(achievement['key'],0)>=achievement['goal'] and achievement['id'] not in self.progress['achievements']:
                self.progress['achievements'][achievement['id']]=time.time()
                self.toast.emit(achievement['title'],'Achievement discovered')
        self.dirty=True
    def input(self,now=None):
        now=time.monotonic() if now is None else now
        self.rhythm=self.rhythm+1 if now-self.last_input<.28 else 1; self.last_input=now
        if self.rhythm>=8:
            if now>self.hot_until: self.record('fire')
            self.hot_until=now+3
        track=next(t for t in self.progress['tracks'] if t['id']==self.progress['activeTrack'])
        old=track['xp']//500+1; track['xp']+=2 if now<self.hot_until else 1
        self.record('input')
        if track['xp']//500+1>old:
            self.update_unlocks(); self.make_gift(track['id'],old+1); self.changed.emit()
    def make_gift(self,track,level):
        occupied=set(self.progress['hats']) | {c for g in self.progress['gifts'] for c in g['choices']}
        available=[i for i in self.content['items'] if i['id'] not in occupied and not i.get('requiresSKU') and (i.get('season','season1')==track or track=='originals')]
        choices=[]
        for _ in range(min(3,len(available))):
            item=random.choices(available,weights=[i['weight'] for i in available])[0]; choices.append(item['id']); available.remove(item)
        if len(choices)==3: self.progress['gifts'].append(dict(id=track+'-'+str(level),track=track,level=level,choices=choices,selected=None)); self.toast.emit('A little gift for you','Pick a gift ball in the Library.')
    def collect(self,gift_id,index):
        gift=next((g for g in self.progress['gifts'] if g['id']==gift_id),None)
        if not gift or not 0<=index<3: return None
        selected=gift.get('selected') or gift['choices'][index]; gift['selected']=selected
        self.progress['hats']=sorted(set(self.progress['hats'])|{selected}); self.progress['claimedGifts'].append(gift_id)
        self.progress['gifts'].remove(gift); self.record('gift'); self.save(); self.changed.emit(); return selected
    def favorite(self,id,pet=True):
        values=self.value.setdefault('paidFavoriteHats',[]) if not pet and not id.startswith('free.') else self.progress['favoritePets' if pet else 'favoriteHats']
        if id in values: values.remove(id)
        else: values.append(id); self.record('favorite')
        self.save(); self.changed.emit()
    def pairing(self,pet,hat):
        for pair in self.content['secrets']:
            if pair['pet']==pet and pair['hat']==hat and pair['id'] not in self.progress['discoveries']:
                self.progress['discoveries'].append(pair['id']); self.record('secret'); self.toast.emit(pair['title'],'A little secret discovered')
    def update_unlocks(self):
        # Values exported from the same macOS content/unlock definitions.
        for pet in self.content.get('pets',[]):
            track=track_for(pet['id'])
            if track and self.level(track)>=pet.get('unlock',1) and pet['id'] not in self.progress['pets']: self.progress['pets'].append(pet['id'])
    def due(self,now=None,focus=False):
        now=time.time() if now is None else now; due=[]
        for reminder in self.value['reminders']:
            if reminder.get('queued') and not focus:
                reminder.pop('queued'); due.append(copy.deepcopy(reminder)); self.dirty=True
                if not reminder.get('enabled',True): continue
            if not reminder.get('enabled',True) and not reminder.get('snooze'): continue
            snooze=reminder.get('snooze')
            regular=reminder.get('enabled',True) and reminder['nextDue']<=now
            if snooze is not None and snooze<=now or regular:
                if regular:
                    if reminder['schedule']=='Interval': reminder['nextDue']=now+reminder['minutes']*60
                    elif reminder['schedule']=='Times of day': reminder['nextDue']=next_time(reminder['times'],now)
                    else: reminder['enabled']=False
                if snooze is not None and snooze<=now: reminder.pop('snooze',None)
                if focus and not reminder.get('priority',False): reminder['queued']=True
                else: reminder.pop('queued',None); due.append(copy.deepcopy(reminder))
                self.dirty=True
            elif reminder.get('queued') and not focus:
                reminder.pop('queued'); due.append(copy.deepcopy(reminder)); self.dirty=True
        return due
    def snooze(self,id,now=None):
        reminder=next(r for r in self.value['reminders'] if r['id']==id)
        reminder['snooze']=(time.time() if now is None else now)+600; self.save()
    def backup(self):
        destination=self.root/'Backups'/('progress-'+uuid.uuid4().hex+'.json'); atomic_json(destination,self.progress)
    def merge(self,remote):
        self.validate_progress(remote); self.backup(); local=self.progress
        if remote['epoch']<local['epoch']: return
        if remote['epoch']>local['epoch']: self.value['progress']=copy.deepcopy(remote)
        else:
            for key in ['pets','hats','favoritePets','favoriteHats','claimedGifts','discoveries']: local[key]=sorted(set(local[key])|set(remote[key]))
            for track in local['tracks']:
                track['xp']=max(track['xp'],next((t['xp'] for t in remote['tracks'] if t['id']==track['id']),0))
            for key in ['counters','achievements']:
                for id,value in remote[key].items(): local[key][id]=max(local[key].get(id,0),value)
            merged={g['id']:g for g in remote['gifts']+local['gifts']}; local['gifts']=[g for id,g in merged.items() if id not in local['claimedGifts']]
            local['revision']=max(local['revision'],remote['revision'])+1
        self.update_unlocks(); self.save(); self.changed.emit()
    @staticmethod
    def validate_progress(value):
        if value.get('version')!=1 or not isinstance(value.get('epoch'),int) or value['epoch']<0: raise ValueError('Unsupported progress')
        if not 3<=len(value['tracks'])<=13 or any(not 0<=t['xp']<=500_000_000 for t in value['tracks']): raise ValueError('Invalid tracks')
        if len(value['gifts'])>500 or any(len(g['choices'])!=3 for g in value['gifts']): raise ValueError('Invalid gifts')
        for key,limit in [('pets',2000),('hats',1000),('favoritePets',2000),('favoriteHats',1000),('claimedGifts',10000),('discoveries',100),('achievements',100),('counters',2100)]:
            if len(value[key])>limit: raise ValueError('Invalid progress')
        if not all(t['id'] in ('season1','season2','originals') or t['id'].startswith('collection.') for t in value['tracks']): raise ValueError('Invalid track')
        ids=[t['id'] for t in value['tracks']]
        if len(set(ids))!=len(ids) or not {'season1','season2','originals'}<=set(ids) or value['activeTrack'] not in ids: raise ValueError('Invalid earning track')
        identifier=re.compile(r'^[a-zA-Z0-9._-]{1,100}$')
        for key in ('pets','hats','favoritePets','favoriteHats','claimedGifts','discoveries','achievements','counters'):
            if any(not isinstance(v,str) or not identifier.fullmatch(v) for v in value[key]):raise ValueError('Invalid identifier')
        if any(not v.startswith('free.') for v in value['hats']+value['favoriteHats']):raise ValueError('Progress cannot grant paid items')
        if any(type(v) is not int or not 0<=v<=1_000_000_000 for v in value['counters'].values()):raise ValueError('Invalid counters')
        if any(type(v) not in (int,float) or not math.isfinite(v) or not 0<=v<=10_000_000_000 for v in value['achievements'].values()):raise ValueError('Invalid achievement date')
        for gift in value['gifts']:
            if len(set(gift['choices']))!=3 or any(not c.startswith('free.') for c in gift['choices']) or gift.get('selected') is not None and gift['selected'] not in gift['choices']:raise ValueError('Invalid gift choices')
        if len(value.get('placements',{}))>2000:raise ValueError('Too many placements')
        for key,p in value.get('placements',{}).items():
            if any(not identifier.fullmatch(k) for k in key.split('::')) or set(p)!={'x','y','scale','rotation'} or any(type(v) not in (int,float) or not math.isfinite(v) for v in p.values()):raise ValueError('Invalid placement')
            if abs(p['x'])>100 or abs(p['y'])>100 or not .4<=p['scale']<=2 or abs(p['rotation'])>90:raise ValueError('Invalid placement')


