"""Optional native companion tools. State is local and deadlines survive restart."""
import math,random,time
from datetime import datetime
from PySide6.QtCore import QObject,Signal

class Tools(QObject):
    said=Signal(str,str);changed=Signal()
    def __init__(self,state,content):
        super().__init__();self.state=state;self.content=content;self.practice=None;self.last_instruction=None;self.last_care=0
    def enabled(self,id):return self.state.value['features'].get(id,next((f['enabled'] for f in self.content['features'] if f['id']==id),False))
    def enable(self,id,value):self.state.value['features'][id]=value;self.state.save();self.changed.emit()
    @property
    def countdown(self):return self.state.value['tools'].setdefault('countdown',{'phase':'idle','label':'A little task','remaining':0,'deadline':0})
    def start_timer(self,minutes,title):
        self.countdown.update(phase='running',label=title.strip()[:120] or 'A little task',remaining=minutes*60,deadline=time.time()+minutes*60);self.state.save();self.changed.emit()
    def pause_timer(self):
        t=self.countdown
        if t['phase']=='running':t.update(phase='paused',remaining=max(0,t['deadline']-time.time()));self.state.save();self.changed.emit()
        elif t['phase']=='paused':t.update(phase='running',deadline=time.time()+t['remaining']);self.state.save();self.changed.emit()
    def add_five(self):
        t=self.countdown
        if t['phase']=='running':t['deadline']+=300
        elif t['phase']=='paused':t['remaining']+=300
        elif t['phase']=='expired':self.start_timer(5,t['label'])
        self.state.save();self.changed.emit()
    def cancel_timer(self):self.countdown['phase']='idle';self.state.save();self.changed.emit()
    def timer_text(self):
        t=self.countdown;seconds=max(0,int(t['deadline']-time.time())) if t['phase']=='running' else int(t['remaining']);return t['label']+' · '+t['phase']+(f' · {seconds//60:02d}:{seconds%60:02d}' if t['phase'] in ('running','paused') else '')
    def start_practice(self,kind,minutes=2):
        self.practice={'kind':kind,'duration':minutes*60,'deadline':time.time()+minutes*60,'remaining':minutes*60,'paused':False};self.last_instruction=None;self.changed.emit()
    def pause_practice(self):
        p=self.practice
        if not p:return
        if p['paused']:p['deadline']=time.time()+p['remaining'];p['paused']=False
        else:p['remaining']=max(0,p['deadline']-time.time());p['paused']=True
        self.changed.emit()
    def stop_practice(self):self.practice=None;self.changed.emit()
    def care(self,action):
        n=self.needs();now=time.time()
        if now-n.get('lastAction',0)<1:return
        n['lastAction']=now
        if action!='nap':n['asleepUntil']=0
        if action=='feed':n['food']=min(100,n['food']+20);n['affection']=min(100,n['affection']+3);reward=10;emotion='Happy'
        elif action=='play':n['happiness']=min(100,n['happiness']+20);n['energy']=max(0,n['energy']-5);reward=15;emotion='Playful'
        elif action=='pet':n['affection']=min(100,n['affection']+10);n['happiness']=min(100,n['happiness']+5);reward=5;emotion='Affectionate'
        else:n['asleepUntil']=now+1800;reward=5;emotion='Cozy'
        n['xp']+=reward
        while n['xp']>=n['level']*50:n['xp']-=n['level']*50;n['level']+=1
        self.state.record('care');self.state.save();self.said.emit({'feed':'A lovely little snack, thank you ♡','play':'Let’s play!','pet':'That feels so cozy ♡','nap':'A soft little rest…'}.get(action,'Thank you ♡'),emotion);self.changed.emit()
    def needs(self):
        saved=self.state.value['tools'].setdefault('care',{});id=self.state.prefs['companion'];now=time.time();n=saved.setdefault(id,{'food':80.,'energy':80.,'happiness':80.,'affection':50.,'xp':0,'level':1,'lastSeen':now,'asleepUntil':0})
        elapsed=max(0,min(30*86400,now-n['lastSeen']));sleep=max(0,min(elapsed,min(n['asleepUntil'],now)-n['lastSeen']));wake=elapsed-sleep
        n['food']=max(0,n['food']-elapsed/3600*2);n['energy']=max(0,min(100,n['energy']-wake/3600*3+sleep/3600*15));n['happiness']=max(0,n['happiness']-wake/3600*2-sleep/3600*.5);n['affection']=max(0,n['affection']-wake/3600);n['lastSeen']=now;return n
    def tick(self,focus=False):
        now=time.time();t=self.countdown
        if t['phase']=='running' and t['deadline']<=now:t.update(phase='expired',remaining=0,queued=True);self.state.dirty=True;self.changed.emit()
        if t.get('queued') and not focus:t.pop('queued');self.said.emit(t['label']+' is ready ♡','Success');self.state.record('timer')
        if self.practice and not self.practice['paused']:
            p=self.practice;p['remaining']=max(0,p['deadline']-now);elapsed=p['duration']-p['remaining'];kind=p['kind']
            if not p['remaining']:self.practice=None;self.state.record('practice');self.said.emit('A little calmer, one breath at a time ♡','Happy');self.changed.emit()
            else:
                stage=min(4,int(elapsed/max(1,p['duration']/5)))
                instruction=('Breathe in gently' if elapsed%12<5 else 'A soft pause' if elapsed%12<6 else 'Breathe out slowly') if kind=='Paced breathing' else ['Let your hands soften.','Lift, then relax your shoulders.','Unclench your jaw.','Let your feet rest comfortably.','Notice what feels a little looser.'][stage] if kind=='Unwind your muscles' else ['Notice five things you can see.','Notice four things you can feel.','Notice three sounds around you.','Notice two scents or colors.','One small thing you appreciate.'][stage] if kind=='Grounding' else 'Let thoughts pass by. Gently return to this moment.' if kind=='Quiet moment' else 'Picture a peaceful place, its colors, and a cozy spot to rest.'
                if instruction!=self.last_instruction:self.last_instruction=instruction;self.said.emit(instruction,'Cozy')
        if self.enabled('openpets.virtual-pet') and now-self.last_care>=60:self.needs();self.last_care=now;self.state.dirty=True;self.changed.emit()
