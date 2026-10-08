from __future__ import annotations
import math, random, time
from collections import OrderedDict
from pathlib import Path
from PySide6.QtCore import Qt, QTimer, QPoint, QPointF, QRectF, Signal
from PySide6.QtGui import QImage, QPainter, QColor, QPen, QPainterPath, QRegion, QBitmap, QCursor
from PySide6.QtWidgets import QWidget, QApplication
from .assets import ASSETS, RESOURCES, read_profile
from .platform import all_workspaces, foreground_rect

INK=QColor('#40312b'); PAPER=QColor('#fffaf5'); PURPLE=QColor('#7b57a6'); PINK=QColor('#c3428c')
EMOTIONS=['Happy','Curious','Surprised','Affectionate','Shy','Sad','Sleepy','Excited','Proud','Focused','Playful','Delighted','Cozy','Grumpy']

class Artwork:
    def __init__(self,pet,content):
        self.pet=pet; self.sheet=QImage(str(pet.directory/'spritesheet.webp')) if not pet.rig else None
        self.cache=OrderedDict(); self.profile=pet.profile; self.parts={}; self.item_cache={}
        self.fits=next((p['fits'] for p in content['pets'] if p['id']==pet.id),None)
        if pet.rig:
            for name,part in pet.rig['parts'].items(): self.parts[name]=QImage(str(pet.directory/part['file']))
    def frame(self,row,column,pose=None):
        key=(row,column,pose)
        if key in self.cache: self.cache.move_to_end(key); return self.cache[key]
        if pose:
            image=QImage(str(RESOURCES/'FileInteractions'/self.pet.id/(pose+'.png')))
        else:
            w=self.sheet.width()//8;h=self.sheet.height()//self.pet.rows; image=self.sheet.copy(column*w,row*h,w,h).scaled(192,208,Qt.IgnoreAspectRatio,Qt.SmoothTransformation)
        self.cache[key]=image
        while len(self.cache)>12: self.cache.popitem(last=False)
        return image
    def profile_for(self,row,column,pose=None):
        if pose: file=RESOURCES/'FileInteractions'/self.pet.id/pose/'interaction.json'
        elif row in (1,2,7): file=self.pet.directory/('typing-left' if column%2==0 else 'typing-right')/'interaction.json'
        else: return self.profile
        if file.exists():
            return read_profile(file) or self.profile
        return self.profile
    def paint(self,painter,row=0,column=0,pose=None,emotion=None,item=None,transform=None,blink=False,dance=False,tap=0):
        if self.pet.rig:
            self.paint_rig(painter,tap,emotion,blink,pose); profile=None
        else:
            painter.drawImage(QRectF(0,0,192,208),self.frame(row,column,pose))
            profile=self.profile_for(row,column,pose)
            # Side-view flight/running artwork retains its own natural eyes.
            if self.pet.id=='bunny' and row==4 or row in (1,2): profile=None
            self.face(painter,profile,'Cozy' if blink else emotion)
        crown=(96,38); sf=1.
        if self.pet.rig:
            head=self.pet.rig['parts']['head'];size=head.get('display_size',[150,125]);offset=head.get('parent_offset',[0,42]);crown=(96+offset[0],170-offset[1]-(1-head['anchor'][1])*size[1]+8);sf=size[0]/140
        if profile and (pose or profile.get('full_body')):
            crown=(profile['crown'][0]*192,profile['crown'][1]*208)
            sf=profile.get('accessory_scale',1)
        elif self.fits:
            fit=self.fits[min(row,len(self.fits)-1)][column]; crown=fit['crown'];sf=fit['scale']
        if item and item['id']!='none':
            image=self.item_cache.get(item['id'])
            if image is None: image=QImage(str(ASSETS/item['file']));self.item_cache[item['id']]=image
            adjustment=transform or {};scale=sf*adjustment.get('scale',1)
            x,y=crown
            if item['id']=='accessory.glasses' and profile:
                x=sum(e['point'][0]*192 for e in profile['eyes'])/2; y=sum(e['point'][1]*208 for e in profile['eyes'])/2+33*scale
                scale=(profile['eyes'][1]['point'][0]-profile['eyes'][0]['point'][0])*192/44*adjustment.get('scale',1)
                y=sum(e['point'][1]*208 for e in profile['eyes'])/2+33*scale
            elif item.get('kind') in ('beanie','cap') or item['id']=='free.beanie': y+=8*scale
            pivot=item.get('pivot',[80,112]);painter.save();painter.translate(x+adjustment.get('x',0),y-adjustment.get('y',0));painter.rotate(-adjustment.get('rotation',0));painter.scale(scale,scale)
            painter.drawImage(QPointF(-pivot[0],-pivot[1]),image);painter.restore()
        if dance:
            # Functional headphones intentionally bypass every ownership/SKU check.
            painter.save();painter.translate(*crown);painter.setPen(QPen(PURPLE,5,Qt.SolidLine,Qt.RoundCap));painter.setBrush(Qt.NoBrush)
            path=QPainterPath(QPointF(-27,24));path.cubicTo(-27,-11,27,-11,27,24);painter.drawPath(path)
            painter.setBrush(PURPLE);painter.setPen(QPen(INK,1.5));painter.drawRoundedRect(QRectF(-34,17,12,23),5,5);painter.drawRoundedRect(QRectF(22,17,12,23),5,5);painter.restore()
    def paint_rig(self,painter,tap,emotion,blink,pose=None):
        parts=self.pet.rig['parts']; origin=QPointF(96,170)
        body=parts['body']; body_pos=origin
        for key in ['tail','body','head','left_paw','right_paw']:
            part=parts[key];size=part.get('display_size',{'body':[120,96],'head':[150,125],'left_paw':[32,40],'right_paw':[32,40],'tail':[70,45]}[key]);offset=part.get('parent_offset',[0,0]);anchor=part['anchor']
            x=body_pos.x()+offset[0];y=body_pos.y()-offset[1]
            painter.save();painter.translate(x,y)
            if key in ('left_paw','right_paw'):
                if pose in ('receive','hold'):painter.rotate((-1 if key=='left_paw' else 1)*(55 if pose=='receive' else 28))
                elif tap:painter.rotate((1 if key=='left_paw' else -1)*tap*20)
            elif key=='head' and emotion in ('Cozy','Affectionate','Delighted'):painter.rotate(4*math.sin(time.monotonic()*3))
            elif key=='tail' and tap:painter.rotate(tap*12)
            image=self.parts[key];source=QRectF(*part['texture_rect']) if part.get('texture_rect') else QRectF(image.rect())
            painter.drawImage(QRectF(-anchor[0]*size[0],-(1-anchor[1])*size[1],*size),image,source);painter.restore()
    @staticmethod
    def face(painter,profile,emotion):
        if not profile or not emotion: return
        painter.save();painter.setRenderHint(QPainter.Antialiasing)
        for index,eye in enumerate(profile['eyes']):
            x,y=eye['point'][0]*192,eye['point'][1]*208;r=eye['radius'];painter.save();painter.translate(x,y)
            if emotion not in ('Focused','Surprised'):
                fur=eye['fur'];painter.setBrush(QColor.fromRgbF(*fur));painter.setPen(Qt.NoPen);painter.drawEllipse(QRectF(-r*1.38,-r*1.4,r*2.76,r*2.8))
            painter.setPen(QPen(INK,1.7,Qt.SolidLine,Qt.RoundCap));painter.setBrush(Qt.NoBrush);path=QPainterPath()
            if emotion=='Surprised': path.moveTo(-r*.7,-r*1.9);path.quadTo(0,-r*2.3,r*.7,-r*1.9)
            elif emotion=='Focused': path.moveTo(-r,-r*1.5);path.lineTo(r,-r*1.2)
            elif emotion=='Curious': painter.setBrush(INK);painter.drawEllipse(QRectF(-r*.9,-r,r*1.8,r*2))
            elif emotion=='Grumpy': path.moveTo(-r,-r*.35 if index==0 else r*.35);path.lineTo(r,r*.35 if index==0 else -r*.35)
            else:
                happy=emotion in ['Happy','Proud','Excited','Affectionate','Delighted','Playful'];path.moveTo(-r,0);path.quadTo(0,-r*1.3 if happy else r*.75,r,0)
            painter.drawPath(path)
            if emotion in ['Happy','Affectionate','Shy','Proud','Playful','Delighted','Cozy']:
                painter.setPen(Qt.NoPen);painter.setBrush(QColor('#f2aaab'));painter.drawEllipse(QRectF(-r,-r*.4+r*2.2,r*2,r*.8))
            painter.restore()
        if emotion in ['Affectionate','Excited','Proud','Delighted']:
            painter.setPen(QPen(INK,1));painter.setBrush(QColor('#ed9fa8'))
            for x in (28,164):
                p=QPainterPath(QPointF(x,65));p.cubicTo(x-14,55,x-7,45,x,53);p.cubicTo(x+7,45,x+14,55,x,65);painter.drawPath(p)
        painter.restore()

class Companion(QWidget):
    travel_finished=Signal(); double_tapped=Signal(); clicked=Signal(); petted=Signal(); dropped=Signal(list); pocket_requested=Signal(); moved=Signal()
    def __init__(self,state,catalog,content):
        flags=Qt.FramelessWindowHint|Qt.Tool|Qt.WindowStaysOnTopHint|Qt.WindowDoesNotAcceptFocus
        super().__init__(None,flags);self.setAttribute(Qt.WA_TranslucentBackground);self.setAttribute(Qt.WA_ShowWithoutActivating);self.setAcceptDrops(True)
        self.state=state;self.catalog=catalog;self.content=content;self.pet=None;self.art=None;self.mode='Idle';self.emotion=None;self.started=0.;self.duration=0.;self.row=0;self.column=0;self.pose=None
        self.travel=None;self.roaming_position=None;self.last_activity=time.monotonic();self.next_roam=time.monotonic()+20;self.taps=0;self.last_tap=0;self.screen_name=None;self.sleeping=False;self.screen_sleep=False;self.holding=0;self.owned=();self.receiving=False;self.dancing=False;self.cursor_near=None;self.next_cursor=0;self.next_blink=time.monotonic()+12;self.drag_start=None;self.last_mask=None;self.locked_mask_until=0.
        self.frame_timer=QTimer(self);self.frame_timer.setTimerType(Qt.PreciseTimer);self.frame_timer.setInterval(16);self.frame_timer.timeout.connect(self.advance)
        self.heartbeat=QTimer(self);self.heartbeat.setInterval(1000);self.heartbeat.timeout.connect(self.idle_tick);self.heartbeat.start()
        self.state.changed.connect(self.refresh);self.refresh()
    def refresh(self):
        prefs=self.state.prefs;id=prefs['companion']
        pet=self.catalog.by_id.get(id) or self.catalog.by_id['openpets-default']
        if not self.pet or self.pet.id!=pet.id: self.pet=pet;self.art=Artwork(pet,self.content);self.rest()
        self.resize(round(280*prefs['scale']),round(300*prefs['scale']));self.setWindowOpacity(prefs['opacity'])
        if prefs['hidden']: self.hide();self.frame_timer.stop()
        else: self.show()
        if self.roaming_position is None: self.reanchor()
        else: self.move(self.clamped(self.pos()))
        self.update_visual()
    def showEvent(self,event): super().showEvent(event);all_workspaces(self)
    def active_screen(self,point=None):
        if point is None:
            frame=foreground_rect();point=QPoint(frame[0]+frame[2]//2,frame[1]+frame[3]//2) if frame else QCursor.pos()
        return QApplication.screenAt(point) or QApplication.primaryScreen()
    def reanchor(self,reset=False,point=None):
        screen=self.active_screen(point)
        if not screen: return
        if screen.name()!=self.screen_name: self.stop_travel();self.roaming_position=None;self.screen_name=screen.name()
        if reset: self.stop_travel();self.roaming_position=None
        if self.roaming_position is not None: return
        visible=screen.availableGeometry();anchor=self.state.prefs['anchor']; x=visible.left()+20 if self.state.prefs['mirror'] else visible.right()-self.width()-20;y=visible.bottom()-self.height()+1
        if anchor=='Notch': x=visible.center().x()-self.width()//2;y=visible.top()
        elif anchor=='Active Window':
            frame=foreground_rect()
            if frame: x=frame[0]+frame[2]-self.width();y=frame[1]-self.height()+32
        elif anchor=='Free Floating': x=visible.center().x()-self.width()//2
        self.move(self.clamped(QPoint(x,y),screen));self.moved.emit()
    def clamped(self,point,screen=None):
        visible=(screen or self.screen() or self.active_screen()).availableGeometry()
        return QPoint(max(visible.left(),min(visible.right()-self.width()+1,point.x())),max(visible.top(),min(visible.bottom()-self.height()+1,point.y())))
    def stop_travel(self):
        if self.travel: self.travel=None;self.roaming_position=self.pos();self.rest()
    def react(self,kind):
        if self.sleeping or self.screen_sleep or self.state.prefs['hidden']: return
        self.stop_travel();self.last_activity=time.monotonic();self.next_roam=self.last_activity+self.state.prefs['wanderInterval'];self.started=self.last_activity;self.mode=kind;self.emotion=None;self.pose=None
        if kind=='Typing':
            self.taps+=1;self.row=7;self.column=(self.taps%2);self.duration=.5;self.emotion='Focused'
        elif kind=='Click': self.row=0;self.column=6 if self.pet.rows==11 else 0;self.duration=.55;self.emotion=EMOTIONS[(self.taps%4)+1];self.taps+=1
        elif kind=='Cuddle': self.row=3 if self.art.profile is None else 0;self.duration=1.5;self.emotion=random.choice(['Affectionate','Delighted','Cozy','Playful'])
        elif kind=='Success': self.row=4;self.duration=1.68;self.emotion='Excited'
        elif kind=='Failed': self.row=5;self.duration=1.2;self.emotion='Sad'
        elif kind in EMOTIONS: self.row=0;self.column=6 if self.pet.rows==11 else 0;self.duration=2;self.emotion=kind
        elif kind=='Dance': self.row=0;self.duration=10;self.dancing=True;self.emotion='Happy'
        elif kind=='Wave': self.row=3;self.duration=.9
        self.frame_timer.start();self.update_visual()
    def rest(self):
        self.mode='Idle';self.row=0;self.column=6 if self.pet and self.pet.rows==11 else 0;self.pose='hold' if self.holding and (self.native_pose('hold') or self.pet.rig) else None;self.emotion=None
    def native_pose(self,pose): return self.pet and (RESOURCES/'FileInteractions'/self.pet.id/(pose+'.png')).exists()
    def advance(self,now=None):
        now=time.monotonic() if now is None else now
        if self.screen_sleep or self.state.prefs['hidden']: self.frame_timer.stop();return
        elapsed=now-self.started
        if self.travel:
            start,target,began,duration,jump=self.travel;t=min(1,(now-began)/duration);e=(1-math.cos(t*math.pi))/2 if jump else t
            x=start.x()+(target.x()-start.x())*e;y=start.y()+(target.y()-start.y())*e-(math.sin(math.pi*e)*80 if jump else 0)
            self.move(round(x),round(y));self.roaming_position=self.pos();self.moved.emit()
            self.column=min(4,int(t*5)) if jump else int((now-began)*8)%6
            if t>=1: self.travel=None;self.rest();self.travel_finished.emit()
        elif self.mode=='Cuddle':
            cycle=elapsed%.61
            if self.pet.id=='bunny': self.row=4 if cycle<.52 else 0;self.column=0 if cycle<.14 or cycle>=.52 else 2;self.pose=None
            elif self.native_pose('receive') and self.art.profile:
                self.pose='receive' if .14<=cycle<.52 else 'hold' if self.holding else None
            elif self.art.profile is None: self.column=int(elapsed/.15)%4
        elif self.mode=='Typing':self.column=(self.taps%2)+2*min(2,int(elapsed/.14))
        elif self.mode in ('Wave','Success','Failed'): self.column=int(elapsed/.14)% (5 if self.mode=='Success' else 4 if self.mode=='Wave' else 6)
        if not self.travel and elapsed>=self.duration:
            if self.mode=='Dance' and self.dancing: self.started=now
            else: self.rest();self.frame_timer.stop()
        self.update_visual()
    def frame_image(self):
        image=QImage(self.size(),QImage.Format_ARGB32_Premultiplied);image.fill(Qt.transparent);painter=QPainter(image);painter.setRenderHint(QPainter.Antialiasing);painter.setRenderHint(QPainter.SmoothPixmapTransform)
        scale=self.state.prefs['scale'];painter.scale(scale,scale);painter.translate(44,60)
        elapsed=time.monotonic()-self.started
        if self.mode=='Cuddle':
            phase=min(elapsed,1.4)%.61; lift=22*max(0,math.sin((phase-.14)/.38*math.pi)) if .14<=phase<=.52 else 0
            painter.translate(0,-lift);painter.translate(96,208);painter.scale(1,.95 if phase<.14 else 1.03 if lift else 1);painter.translate(-96,-208)
        elif self.mode=='Typing': painter.translate(0,math.sin(min(elapsed,.25)/.25*math.pi)*2)
        elif self.mode=='Click':
            pulse=math.sin(min(1,elapsed/self.duration)*math.pi);direction=-1 if QCursor.pos().x()<self.x()+self.width()/2 else 1;painter.translate(96,175);painter.rotate(direction*pulse*3);painter.scale(1+pulse*.015,1+pulse*.025);painter.translate(-96,-175)
        elif self.mode=='IdleBlink':
            phase=min(1,elapsed/.85);painter.translate(96,208);painter.scale(1,1-.025*math.sin(phase*math.pi));painter.translate(-96,-208)
        elif self.mode=='Dance': painter.translate(0,-abs(math.sin(elapsed*math.pi*4))*9)
        elif self.mode=='Success':
            progress=min(1,elapsed/self.duration);painter.translate(96,104-math.sin(progress*math.pi)*30);painter.rotate(progress*360);painter.translate(-96,-104)
        if self.travel and self.mode=='Walk':
            direction=1 if self.travel[1].x()>self.travel[0].x() else -1; source=-1 if self.pet.id=='knight-cat' else 1
            if direction!=source: painter.translate(192,0);painter.scale(-1,1)
        elif self.state.prefs['mirror']: painter.translate(192,0);painter.scale(-1,1)
        item=next((i for i in self.content['items'] if i['id']==self.state.prefs['accessory']),None) if self.state.prefs['headAccessoriesVisible'] else None
        if item and not self.state.can_equip(item['id'],self.owned):item=None
        transform=self.state.progress['placements'].get(self.pet.id+'::'+self.state.prefs['accessory'])
        self.art.paint(painter,self.row,self.column,self.pose,'Sleepy' if self.sleeping else self.emotion,item,transform,dance=self.dancing and self.state.prefs['headAccessoriesVisible'],tap=math.sin(elapsed*(18 if self.mode=='Typing' else 8)) if self.mode in ('Typing','Walk','Dance') else 0)
        if self.mode=='Failed':
            painter.setPen(QPen(INK,2));painter.setBrush(QColor('#d8af80'));painter.drawRoundedRect(QRectF(34,145,124,58),8,8);painter.drawLine(96,146,96,160)
        if self.sleeping: painter.setPen(PURPLE);painter.drawText(QPointF(145,36),'z z')
        if self.holding:
            painter.setPen(QPen(INK,1.1));painter.setBrush(QColor('#c4a9dc'));painter.drawRoundedRect(QRectF(143,162,23,21),7,7);painter.drawArc(QRectF(148,157,13,15),0,180*16)
            painter.drawText(QRectF(143,163,23,19),Qt.AlignCenter,str(self.holding))
        painter.end();return image
    def update_visual(self):
        if not self.art: return
        self.image=self.frame_image();bitmap=QBitmap.fromImage(self.image.createAlphaMask());region=QRegion(bitmap)
        if self.state.prefs['clickThrough']: region=QRegion(0,0,1,1)
        if time.monotonic()<self.locked_mask_until and self.last_mask is not None:region=self.last_mask
        if region!=self.last_mask: self.setMask(region);self.last_mask=region
        self.update()
    def paintEvent(self,event):
        if hasattr(self,'image'):
            painter=QPainter(self);painter.drawImage(0,0,self.image);painter.end()
    def roam(self,jump=False):
        if self.sleeping or self.screen_sleep or self.state.prefs['hidden']: return
        self.stop_travel();visible=self.screen().availableGeometry();start=self.pos()
        if self.state.prefs['movement']=='Follow cursor': target=QPoint(QCursor.pos().x()-self.width()//2,visible.bottom()-self.height()+1)
        elif self.state.prefs['movement']=='Patrol': target=QPoint(visible.left()+10 if self.x()>visible.center().x() else visible.right()-self.width()-10,visible.bottom()-self.height()+1)
        else: target=start+QPoint(-180 if start.x()>visible.center().x() else 180,0)
        if self.state.prefs['edgeTraversal'] and self.state.prefs['anchor'] in ('Free Floating','Active Window'):
            front=foreground_rect()
            if front: target.setY(front[1]-self.height()+32 if abs(start.y()-(visible.bottom()-self.height()+1))<20 else visible.bottom()-self.height()+1);jump=True
        target=self.clamped(target);duration=1.68 if jump else max(1.2,abs(target.x()-start.x())/self.state.prefs['walkSpeed'])
        self.travel=(start,target,time.monotonic(),duration,jump);self.started=time.monotonic();self.duration=duration;self.mode='Jump' if jump else 'Walk';self.row=4 if jump else 1;self.pose=None;self.emotion=None;self.frame_timer.start();self.next_roam=time.monotonic()+self.state.prefs['wanderInterval']
    def walk_to(self,point):
        self.stop_travel();target=self.clamped(point);start=self.pos();duration=min(2.5,max(.4,(target-start).manhattanLength()/150))
        self.travel=(start,target,time.monotonic(),duration,False);self.started=time.monotonic();self.duration=duration;self.mode='Walk';self.row=1;self.pose=None;self.frame_timer.start()
    def idle_tick(self):
        if self.state.prefs['hidden'] or self.screen_sleep: return
        if self.sleeping: return
        self.reanchor()
        now=time.monotonic()
        if self.mode=='Idle' and not self.travel and self.state.prefs['movement']!='Stay' and now>=self.next_roam and now-self.last_activity>3: self.roam()
        if self.mode=='Idle' and not self.travel:
            if now>=self.next_blink:
                self.next_blink=now+random.uniform(12,18);self.started=now;self.duration=.85;self.mode='IdleBlink';self.emotion='Cozy';self.frame_timer.start()
            near=(QCursor.pos()-QPoint(self.x()+self.width()//2,self.y()+self.height()//2)).manhattanLength()<140
            if near:
                if self.cursor_near is None: self.cursor_near=now
                if now-self.cursor_near>.6 and now>self.next_cursor: self.react('Curious');self.next_cursor=now+5
            else: self.cursor_near=None
    def pause(self,value):
        self.screen_sleep=value
        if value: self.stop_travel();self.frame_timer.stop()
        else: self.rest();self.update_visual()
    def mousePressEvent(self,event): self.stop_travel();self.drag_start=event.globalPosition().toPoint();self.origin=self.pos();event.accept()
    def mouseMoveEvent(self,event):
        if self.drag_start is None: return
        delta=event.globalPosition().toPoint()-self.drag_start
        if event.modifiers()&Qt.AltModifier: self.move(self.clamped(self.origin+delta));self.roaming_position=self.pos();self.moved.emit()
        elif delta.manhattanLength()>4: self.react('Affectionate');self.petted.emit()
    def mouseReleaseEvent(self,event):
        if self.drag_start is not None and (event.globalPosition().toPoint()-self.drag_start).manhattanLength()<4:
            if event.button()==Qt.RightButton: self.double_tapped.emit()
            else:
                self.locked_mask_until=time.monotonic()+QApplication.doubleClickInterval()/1000
                self.react('Cuddle');self.clicked.emit()
        self.drag_start=None
    def mouseDoubleClickEvent(self,event): self.stop_travel();self.double_tapped.emit();self.drag_start=None;event.accept()
    def enterEvent(self,event):
        if self.holding: self.pocket_requested.emit()
        super().enterEvent(event)
    def dragEnterEvent(self,event):
        if event.mimeData().hasUrls() and all(u.isLocalFile() for u in event.mimeData().urls()):
            self.stop_travel();self.receiving=True;self.pose='receive' if self.native_pose('receive') or self.pet.rig else None;self.emotion='Happy';self.update_visual();event.acceptProposedAction()
    def dragLeaveEvent(self,event): self.receiving=False;self.rest();self.update_visual()
    def dropEvent(self,event):
        urls=[u.toLocalFile() for u in event.mimeData().urls() if u.isLocalFile()];self.receiving=False;self.dropped.emit(urls);self.rest();self.update_visual();event.acceptProposedAction()
