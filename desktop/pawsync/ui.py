from __future__ import annotations
import copy, hashlib, json, random, shutil, time, uuid
from datetime import datetime
from pathlib import Path
from PySide6.QtCore import Qt, QSize, QUrl, Signal, QTimer
from PySide6.QtGui import QPixmap, QIcon, QDesktopServices
from PySide6.QtWidgets import (QMainWindow,QWidget,QVBoxLayout,QHBoxLayout,QGridLayout,QLabel,QPushButton,QLineEdit,QListWidget,QListWidgetItem,QStackedWidget,QScrollArea,QFrame,QComboBox,QCheckBox,QSlider,QSpinBox,QDialog,QFormLayout,QDialogButtonBox,QMessageBox,QFileDialog,QTabWidget,QProgressBar,QDateTimeEdit,QGroupBox)
from .assets import ASSETS, Pet
from .state import next_time, fresh_progress
from .photo import validate_photo,provider_image,prepare_sheet,prepare_backend,install_draft
from .jobs import launch

STYLE='''
QMainWindow,QDialog{background:#fff9f2;color:#40312b;} QWidget{font-size:14px;color:#40312b;}
QScrollArea,QScrollArea>QWidget>QWidget{background:transparent;border:0;} QLabel{background:transparent;}
QListWidget#sidebar{background:#f2eae2;border:0;padding:12px;} QListWidget#sidebar::item{padding:13px 12px;margin:3px 0;border-radius:12px;color:#66564e;} QListWidget#sidebar::item:selected{background:#e5d7ef;color:#5c3986;font-weight:600;}
QPushButton{background:#fffdf9;border:1px solid #dacdc4;border-radius:12px;padding:8px 13px;color:#40312b;} QPushButton:hover{background:#efe3f6;border-color:#9c7db8;} QPushButton:pressed{background:#ddcbe9;} QPushButton:disabled{color:#918780;background:#f0ece8;}
QPushButton[primary="true"]{background:#7b57a6;border-color:#7b57a6;color:white;font-weight:600;} QPushButton[primary="true"]:hover{background:#684592;}
QFrame#card,QGroupBox{background:#fffdfa;border:1px solid #e4d8ce;border-radius:18px;} QGroupBox{padding-top:23px;margin-top:9px;} QGroupBox::title{left:14px;top:3px;color:#71568f;}
QLineEdit,QSpinBox,QDateTimeEdit,QComboBox{background:#fffdf9;border:1px solid #cbb9ae;border-radius:10px;padding:8px;selection-background-color:#a17bbb;} QComboBox::drop-down{border:0;width:25px;} QTabWidget::pane{border:0;} QTabBar::tab{padding:10px 17px;border:0;border-radius:10px;background:#f1e9e1;margin:2px;} QTabBar::tab:selected{background:#e4d5ef;color:#633e8b;}
QCheckBox{spacing:8px;padding:5px;} QCheckBox::indicator{width:18px;height:18px;border:1px solid #b8a49c;border-radius:5px;background:white;} QCheckBox::indicator:checked{background:#7b57a6;border-color:#7b57a6;}
QSlider::groove:horizontal{height:5px;background:#e0d3e6;border-radius:2px;} QSlider::handle:horizontal{background:#7b57a6;width:16px;margin:-6px 0;border-radius:8px;} QProgressBar{background:#ebe3ed;border:0;border-radius:5px;text-align:center;} QProgressBar::chunk{background:#9a70b9;border-radius:5px;}
'''

def button(text,fn,primary=False):
    b=QPushButton(text);b.setProperty('primary',primary);b.clicked.connect(fn);return b

def label(text,size=14,bold=False):
    v=QLabel(text);v.setWordWrap(True);v.setStyleSheet(f'font-size:{size}px;'+('font-weight:600;' if bold else ''));return v

def card():
    frame=QFrame();frame.setObjectName('card');layout=QVBoxLayout(frame);layout.setContentsMargins(18,17,18,17);return frame,layout

def scroll(widget):
    area=QScrollArea();area.setWidgetResizable(True);area.setWidget(widget);return area

def info(parent,title,detail): QMessageBox.information(parent,title,detail)

class ClickCard(QFrame):
    activated=Signal()
    def __init__(self): super().__init__();self.setObjectName('card');self.setCursor(Qt.PointingHandCursor)
    def mouseReleaseEvent(self,event):
        if event.button()==Qt.LeftButton: self.activated.emit()
        super().mouseReleaseEvent(event)

class Library(QMainWindow):
    pages=['Pets','Items','Achievements','Make your own pet','Wellness','Settings']
    def __init__(self,controller):
        super().__init__();self.c=controller;self.state=controller.state;self.catalog=controller.catalog;self.setWindowTitle('PawSync · Your little companion');self.resize(1080,740);self.setMinimumSize(850,610);self.setStyleSheet(STYLE)
        center=QWidget();self.setCentralWidget(center);layout=QHBoxLayout(center);layout.setContentsMargins(0,0,0,0);layout.setSpacing(0)
        rail=QWidget();rail.setFixedWidth(205);rl=QVBoxLayout(rail);rl.setContentsMargins(12,22,12,18);rail.setStyleSheet('background:#f2eae2;');rl.addWidget(label('♧  PawSync',24,True))
        self.sidebar=QListWidget();self.sidebar.setObjectName('sidebar');self.sidebar.setFocusPolicy(Qt.NoFocus)
        for name in self.pages: self.sidebar.addItem(name)
        rl.addWidget(self.sidebar);self.mini=label('A little friend for your day',13);rl.addWidget(self.mini);layout.addWidget(rail)
        body=QWidget();body_layout=QVBoxLayout(body);body_layout.setContentsMargins(28,25,28,22);self.heading=label('Your pets',28,True);body_layout.addWidget(self.heading)
        self.stack=QStackedWidget();body_layout.addWidget(self.stack);self.notice=label('');self.notice.setStyleSheet('color:#704c83;');body_layout.addWidget(self.notice);layout.addWidget(body)
        self.page_widgets={};self.make_pets();self.make_items();self.make_achievements();self.make_creator();self.make_wellness();self.make_settings()
        self.sidebar.currentRowChanged.connect(self.page_changed);self.sidebar.setCurrentRow(0)
        self.refresh_timer=QTimer(self);self.refresh_timer.setSingleShot(True);self.refresh_timer.timeout.connect(self.refresh_visible);self.state.changed.connect(lambda:self.refresh_timer.start(80))
    def closeEvent(self,event): event.ignore();self.hide()
    def open_page(self,name): self.sidebar.setCurrentRow(self.pages.index(name));self.show();self.raise_();self.activateWindow()
    def page_changed(self,index):
        if index<0:return
        self.stack.setCurrentIndex(index);self.heading.setText(['Your pets','Little things to wear','Milestones & little secrets','Make your own pet','A kinder day','Settings'][index]);self.refresh_visible()
    def notify(self,message): self.notice.setText(message)
    def guarded(self,fn):
        try: return fn()
        except (ValueError,OSError) as error: self.notify(str(error));return None
    def job(self,fn,success):
        self.notify('Working…');return launch(fn,lambda value:(self.notify(''),success(value)),self.notify,self)
    def add_page(self,widget): self.stack.addWidget(widget)
    def make_pets(self):
        widget=QWidget();layout=QVBoxLayout(widget);row=QHBoxLayout();self.pet_search=QLineEdit();self.pet_search.setPlaceholderText('Find a friend');self.pet_group=QComboBox();self.pet_group.addItems(['All pets','OpenPets','PawSync originals','Animal friends','Your creations & imports']);self.pet_favorites=QCheckBox('Favorites');row.addWidget(self.pet_search);row.addWidget(self.pet_group);row.addWidget(self.pet_favorites);layout.addLayout(row)
        self.pet_grid_widget=QWidget();self.pet_grid=QGridLayout(self.pet_grid_widget);self.pet_grid.setSpacing(14);layout.addWidget(scroll(self.pet_grid_widget));imports=QHBoxLayout();imports.addWidget(button('Import ZIP',self.import_pet));imports.addWidget(button('Import folder',self.import_folder));imports.addWidget(button('From Codex',self.import_codex));layout.addLayout(imports);self.add_page(widget)
        for signal in (self.pet_search.textChanged,self.pet_group.currentTextChanged,self.pet_favorites.toggled): signal.connect(self.populate_pets)
        self.populate_pets()
    def clear_layout(self,layout):
        while layout.count():
            item=layout.takeAt(0)
            if item.widget(): item.widget().hide();item.widget().deleteLater()
    def populate_pets(self,*args):
        self.clear_layout(self.pet_grid);index=0;previous=None
        for pet in self.catalog.pets:
            if self.pet_search.text().lower() not in self.state.name(pet).lower(): continue
            if self.pet_group.currentText()!='All pets' and self.pet_group.currentText()!=pet.group: continue
            if self.pet_favorites.isChecked() and pet.id not in self.state.progress['favoritePets']:continue
            if pet.group!=previous:
                if index%4:index+=4-index%4
                self.pet_grid.addWidget(label(pet.group,17,True),index//4,0,1,4);index+=4;previous=pet.group
            frame=ClickCard();frame.setMinimumSize(140,195);v=QVBoxLayout(frame);v.setContentsMargins(10,12,10,10)
            image=QLabel();image.setAlignment(Qt.AlignCenter);image.setPixmap(QPixmap.fromImage(pet.preview()).scaled(120,130,Qt.KeepAspectRatio,Qt.SmoothTransformation));v.addWidget(image)
            title=label(self.state.name(pet),14,True);title.setAlignment(Qt.AlignCenter);v.addWidget(title)
            unlocked=self.state.can_select(pet);status='Your companion' if self.state.prefs['companion']==pet.id else 'Click to choose' if unlocked else f"Unlocks at level {next((p['unlock'] for p in self.c.content['pets'] if p['id']==pet.id),1)}";v.addWidget(label(status,11))
            controls=QHBoxLayout();fav=button('★' if pet.id in self.state.progress['favoritePets'] else '☆',lambda checked=False,p=pet:self.state.favorite(p.id));detail=button('ⓘ',lambda checked=False,p=pet:self.pet_info(p));controls.addWidget(fav);controls.addStretch();controls.addWidget(detail);v.addLayout(controls)
            frame.activated.connect(lambda p=pet:self.choose_pet(p));self.pet_grid.addWidget(frame,index//4,index%4);index+=1
        self.pet_grid.setRowStretch(index//4+1,1)
    def choose_pet(self,pet):
        def choose(): self.state.choose(pet);self.state.pairing(pet.id,self.state.prefs['accessory']);self.notify(f'{self.state.name(pet)} is here ♡')
        self.guarded(choose)
    def pet_info(self,pet):
        dialog=QDialog(self);dialog.setWindowTitle(self.state.name(pet));dialog.setStyleSheet(STYLE);v=QVBoxLayout(dialog);image=QLabel();image.setPixmap(QPixmap.fromImage(pet.preview()));image.setAlignment(Qt.AlignCenter);v.addWidget(image);v.addWidget(label(pet.group+' · '+pet.author));name=QLineEdit(self.state.name(pet));name.setMaxLength(40);v.addWidget(name);v.addWidget(button('Save name',lambda:(self.state.rename(pet.id,name.text(),pet.name),dialog.accept()),True));v.addWidget(label('Typing, clicks, affection, walking, jumping and file-catching use this friend’s available frames.'))
        if pet.source:v.addWidget(button('Artist / source',lambda:QDesktopServices.openUrl(QUrl(pet.source))))
        dialog.exec()
    def import_pet(self):
        file,_=QFileDialog.getOpenFileName(self,'Import a pet','','OpenPets ZIP (*.zip)')
        if file:
            pet=self.guarded(lambda:self.catalog.import_pet(file))
            if pet:self.state.choose(pet);self.populate_pets()
    def make_items(self):
        widget=QWidget();v=QVBoxLayout(widget);row=QHBoxLayout();self.item_search=QLineEdit();self.item_search.setPlaceholderText('Find an item');self.item_category=QComboBox();self.item_category.addItems(['All categories']+sorted({i.get('category','Other') for i in self.c.content['items']}));self.item_favorites=QCheckBox('Favorites');row.addWidget(self.item_search);row.addWidget(self.item_category);row.addWidget(self.item_favorites);v.addLayout(row)
        bar=QHBoxLayout();bar.addWidget(button('No item',lambda:self.equip('none')));bar.addWidget(button('Adjust current item',self.adjust_item));self.gift_button=button('Open gifts',self.open_gifts,True);bar.addWidget(self.gift_button);v.addLayout(bar)
        self.item_grid_widget=QWidget();self.item_grid=QGridLayout(self.item_grid_widget);self.item_grid.setSpacing(12);v.addWidget(scroll(self.item_grid_widget));self.add_page(widget)
        for signal in (self.item_search.textChanged,self.item_category.currentTextChanged,self.item_favorites.toggled):signal.connect(self.populate_items)
        self.populate_items()
    def populate_items(self,*args):
        self.clear_layout(self.item_grid);index=0
        for spec in self.c.content['items']:
            if self.item_search.text().lower() not in spec['name'].lower():continue
            if self.item_category.currentText()!='All categories' and self.item_category.currentText()!=spec.get('category','Other'):continue
            if self.item_favorites.isChecked() and spec['id'] not in self.state.progress['favoriteHats']:continue
            f=ClickCard();v=QVBoxLayout(f);v.setContentsMargins(9,10,9,9);image=QLabel();image.setAlignment(Qt.AlignCenter);image.setPixmap(QPixmap(str(ASSETS/spec['file'])).scaled(110,110,Qt.KeepAspectRatio,Qt.SmoothTransformation));v.addWidget(image);v.addWidget(label(spec['name'],13,True));owned=self.state.can_equip(spec['id'],self.c.backend.owned);v.addWidget(label('Wearing' if self.state.prefs['accessory']==spec['id'] else 'Click to wear' if owned else 'Paid pack' if spec.get('requiresSKU') else 'Earn in gifts',11))
            row=QHBoxLayout();row.addWidget(button('★' if spec['id'] in self.state.progress['favoriteHats'] else '☆',lambda checked=False,s=spec:self.state.favorite(s['id'],False)));row.addStretch();row.addWidget(button('ⓘ',lambda checked=False,s=spec:info(self,s['name'],s.get('category','Other')+' · '+s.get('season','PawSync')+'\n'+('Owned' if self.state.can_equip(s['id'],self.c.backend.owned) else 'Keep earning gifts to unlock this item.'))));v.addLayout(row);f.activated.connect(lambda s=spec:self.equip(s['id']));self.item_grid.addWidget(f,index//5,index%5);index+=1
        self.item_grid.setRowStretch(index//5+1,1);self.gift_button.setText(f"Open gifts ({len(self.state.progress['gifts'])})");self.gift_button.setEnabled(bool(self.state.progress['gifts']))
    def equip(self,id):
        if not self.state.can_equip(id,self.c.backend.owned):self.notify('This item has not been unlocked yet.');return
        self.state.set('accessory',id);self.state.set('headAccessoriesVisible',True)
        if id!='none':self.state.record('dress');self.state.pairing(self.state.prefs['companion'],id)
    def adjust_item(self):
        id=self.state.prefs['accessory']
        if id=='none':self.notify('Choose an item first.');return
        key=self.state.prefs['companion']+'::'+id;original=copy.deepcopy(self.state.progress['placements'].get(key,{}));dialog=QDialog(self);dialog.setWindowTitle('Make it fit');v=QVBoxLayout(dialog);v.addWidget(label('Preview changes on your desktop friend. Cancel restores its placement.'));form=QFormLayout();v.addLayout(form)
        current={'x':0,'y':0,'scale':1.,'rotation':0}|original;sliders={}
        for name,low,high,factor in [('x',-60,60,1),('y',-60,60,1),('scale',40,200,100),('rotation',-45,45,1)]:
            slider=QSlider(Qt.Horizontal);slider.setRange(low,high);slider.setValue(round(current[name]*factor));form.addRow(name.capitalize(),slider);sliders[name]=(slider,factor)
        def preview(*args):self.state.progress['placements'][key]={k:s.value()/factor for k,(s,factor) in sliders.items()};self.c.pet.update_visual()
        for s,_ in sliders.values():s.valueChanged.connect(preview)
        v.addWidget(button('Reset placement',lambda:[s.setValue(100 if k=='scale' else 0) for k,(s,_) in sliders.items()]));buttons=QDialogButtonBox(QDialogButtonBox.Save|QDialogButtonBox.Cancel);buttons.accepted.connect(dialog.accept);buttons.rejected.connect(dialog.reject);v.addWidget(buttons)
        if dialog.exec():self.state.save()
        else:
            if original:self.state.progress['placements'][key]=original
            else:self.state.progress['placements'].pop(key,None)
            self.c.pet.update_visual()
    def open_gifts(self):
        if not self.state.progress['gifts']:return
        gift=self.state.progress['gifts'][0];dialog=QDialog(self);dialog.setWindowTitle('A little gift for you');v=QVBoxLayout(dialog);v.addWidget(label('Pick a surprise ♡',23,True));row=QHBoxLayout();v.addLayout(row)
        def pick(index):
            id=self.state.collect(gift['id'],index);dialog.accept()
            if id:
                spec=next(s for s in self.c.content['items'] if s['id']==id);result=QDialog(self);result.setWindowTitle('Yours to keep');rv=QVBoxLayout(result);image=QLabel();image.setPixmap(QPixmap(str(ASSETS/spec['file'])));image.setAlignment(Qt.AlignCenter);rv.addWidget(image);rv.addWidget(label(spec['name'],21,True));rv.addWidget(button('Wear it',lambda:(self.equip(id),result.accept()),True));rv.addWidget(button('Add to items',result.accept));result.exec()
        for i in range(3):row.addWidget(button(f'✿  {i+1}',lambda checked=False,index=i:pick(index),True))
        v.addWidget(button('Save for later',dialog.reject))
        if len(self.state.progress['gifts'])>1:
            def all_gifts():
                for g in list(self.state.progress['gifts']):self.state.collect(g['id'],random.randrange(3))
                dialog.accept();self.notify('All gifts are waiting in your items ♡')
            v.addWidget(button('Open all',all_gifts))
        dialog.exec()
    def make_achievements(self):
        self.ach_widget=QWidget();self.ach_layout=QVBoxLayout(self.ach_widget);self.add_page(scroll(self.ach_widget));self.populate_achievements()
    def populate_achievements(self):
        self.clear_layout(self.ach_layout);self.ach_layout.addWidget(label(f"{len(self.state.progress['achievements'])} of {len(self.c.content['achievements'])} little milestones",17,True))
        for a in self.c.content['achievements']:
            f,v=card();v.addWidget(label(('✦  ' if a['id'] in self.state.progress['achievements'] else '○  ')+a['title'],16,True));v.addWidget(label(a['detail']));p=QProgressBar();p.setRange(0,a['goal']);p.setValue(min(a['goal'],self.state.progress['counters'].get(a['key'],0)));v.addWidget(p);self.ach_layout.addWidget(f)
        self.ach_layout.addWidget(label('Secret pairings',20,True))
        for s in self.c.content['secrets']:self.ach_layout.addWidget(label(s['title'] if s['id'] in self.state.progress['discoveries'] else 'A little secret waiting to be found…'))
    def make_creator(self):
        widget=QWidget();v=QVBoxLayout(widget);v.addWidget(label('Turn a real pet photo into a friend for your desktop.',18,True));v.addWidget(label('Your photo goes only to the provider you choose. Provider generation is billed by that provider; PawSync cloud generation uses your credits.'))
        f,form_v=card();form=QFormLayout();form_v.addLayout(form);self.photo_name=QLineEdit();self.photo_name.setPlaceholderText('Your pet’s name');self.provider=QComboBox();self.provider.addItems(['Gemini','OpenAI','Grok','PawSync credits']);self.api_key=QLineEdit();self.api_key.setEchoMode(QLineEdit.Password);self.api_key.setPlaceholderText('Saved only in your system credential store');form.addRow('Name',self.photo_name);form.addRow('Provider',self.provider);form.addRow('API key',self.api_key);form_v.addWidget(button('Save API key',self.save_key));v.addWidget(f)
        self.credit_note=label('Credit balance: restore or refresh your account to check.');self.credit_note.hide();v.addWidget(self.credit_note);credit_buy=button('Buy more credits',lambda:self.c.checkout('credits5'));credit_buy.hide();v.addWidget(credit_buy);self.provider.currentTextChanged.connect(lambda value:(self.credit_note.setVisible(value=='PawSync credits'),credit_buy.setVisible(value=='PawSync credits')))
        self.photo_file=None;self.draft=None;self.backend_request_id=None;self.backend_photo=None;self.photo_preview=QLabel('Choose JPEG, PNG or HEIC · up to 15 MB');self.photo_preview.setAlignment(Qt.AlignCenter);self.photo_preview.setMinimumHeight(150);v.addWidget(self.photo_preview);v.addWidget(button('Choose a photo',self.choose_photo));self.generate_button=button('Make my friend',self.generate,True);v.addWidget(self.generate_button);self.keep_button=button('Keep this pet',self.keep_pet,True);self.keep_button.hide();v.addWidget(self.keep_button);self.creator_status=label('');v.addWidget(self.creator_status);v.addStretch();self.add_page(scroll(widget));self.provider.currentTextChanged.connect(lambda text:self.api_key.setEnabled(text!='PawSync credits'))
    def save_key(self):
        if self.provider.currentText()!='PawSync credits':self.guarded(lambda:self.c.vault.put('provider-'+self.provider.currentText(),self.api_key.text().strip()));self.api_key.clear()
    def choose_photo(self):
        file,_=QFileDialog.getOpenFileName(self,'Your pet photo','','Pet photos (*.jpg *.jpeg *.png *.heic *.heif)')
        if file:
            data=self.guarded(lambda:validate_photo(file))
            if data:self.photo_file=file;pix=QPixmap();pix.loadFromData(data);self.photo_preview.setPixmap(pix.scaled(300,180,Qt.KeepAspectRatio,Qt.SmoothTransformation))
    def generate(self):
        if not self.photo_file:self.creator_status.setText('Choose a photo first.');return
        try:
            photo=validate_photo(self.photo_file);provider=self.provider.currentText();name=self.photo_name.text();key=None
            if provider!='PawSync credits':
                key=self.api_key.text().strip() or self.c.vault.get('provider-'+provider)
                if not key:raise ValueError('Enter your provider API key first.')
        except (ValueError,OSError) as error:self.creator_status.setText(str(error));return
        if self.draft:shutil.rmtree(self.draft,ignore_errors=True);self.draft=None
        self.keep_button.hide();self.generate_button.setEnabled(False);self.creator_status.setText('Making a lovable little friend… Keep this window open; generation can take up to two minutes.')
        if provider=='PawSync credits' and self.backend_photo!=photo:
            fingerprint=hashlib.sha256(photo).hexdigest();pending=self.state.value['tools'].get('cloudGeneration',{})
            self.backend_photo=photo;self.backend_request_id=pending.get('id') if pending.get('photoHash')==fingerprint else str(uuid.uuid4())
            self.state.value['tools']['cloudGeneration']={'photoHash':fingerprint,'id':self.backend_request_id};self.state.save()
        def work():
            if provider=='PawSync credits':return prepare_backend(self.c.backend.generate(photo,self.backend_request_id),name,self.state.root)
            return prepare_sheet(provider_image(provider,key,photo),name,self.state.root)
        def success(path):
            if self.c.closed:
                shutil.rmtree(path,ignore_errors=True);return
            self.state.value['tools'].pop('cloudGeneration',None);self.state.save();self.backend_photo=None;self.backend_request_id=None
            self.draft=path;self.photo_preview.setPixmap(QPixmap(str(path/'preview.png')).scaled(192,208));self.keep_button.show();self.generate_button.setEnabled(True);self.creator_status.setText('Preview your pet, then keep it or try another generation.')
        def failure(message):self.generate_button.setEnabled(True);self.creator_status.setText(message+' Use Make my friend to retry.')
        launch(work,success,failure,self)
    def keep_pet(self):
        if not self.draft:return
        destination=self.guarded(lambda:install_draft(self.draft,self.state.root))
        if destination:self.draft=None;self.keep_button.hide();self.catalog.reload();pet=self.catalog.by_id[destination.name];self.state.choose(pet);self.open_page('Pets')
    def make_wellness(self):
        widget=QWidget();v=QVBoxLayout(widget);f,fv=card();fv.addWidget(label('One gentle focus session',19,True));self.focus_status=label('Ready when you are');fv.addWidget(self.focus_status);r=QHBoxLayout();r.addWidget(button('Start 25 min',self.c.start_focus,True));r.addWidget(button('Stop',self.c.stop_focus));fv.addLayout(r);v.addWidget(f)
        presets=QHBoxLayout()
        for name in ['Hydration','Stretch','Posture','Eye Rest']:presets.addWidget(button(name,lambda checked=False,n=name:self.edit_reminder(preset=n)))
        v.addWidget(label('Reminders',20,True));v.addLayout(presets);v.addWidget(button('Add a reminder',self.edit_reminder));self.reminder_widget=QWidget();self.reminder_layout=QVBoxLayout(self.reminder_widget);v.addWidget(self.reminder_widget)
        tools,tv=card();tv.addWidget(label('Little ways to reset',18,True));row=QHBoxLayout()
        for title,fn in [('Breathe',lambda:self.c.say('Breathe in for 4… hold for 4… breathe out for 6. You’re doing okay ♡','Cozy')),('Fortune',lambda:self.c.say(random.choice(['A small step today becomes a lovely path tomorrow.','A kind pause can change the whole afternoon.']),'Happy')),('Magic 8 ball',lambda:self.c.say(random.choice(['All paws point to yes!','Take a little pause and ask again.','Trust your tiny next step.']),'Curious'))]:row.addWidget(button(title,fn))
        tv.addLayout(row);mood=QComboBox();mood.addItems(['How are you feeling?','Happy','Okay','Tired','Anxious']);mood.currentTextChanged.connect(lambda value:self.log_mood(value));tv.addWidget(mood);v.addWidget(tools);v.addStretch();self.add_page(scroll(widget));self.populate_reminders();self.make_extra_tools(v);self.c.tools.changed.connect(self.refresh_tools)
    def log_mood(self,value):
        if value=='How are you feeling?':return
        self.state.value['moods'][datetime.now().strftime('%Y-%m-%d')]=value;self.state.record('mood');self.state.save();self.c.say('I’m here with you. Let’s take this day one little step at a time ♡','Affectionate')
    def populate_reminders(self):
        self.clear_layout(self.reminder_layout)
        for reminder in self.state.value['reminders']:
            f,v=card();row=QHBoxLayout();enabled=QCheckBox(reminder['title']);enabled.setChecked(reminder.get('enabled',True));enabled.toggled.connect(lambda checked,r=reminder:self.toggle_reminder(r,checked));row.addWidget(enabled);row.addStretch();row.addWidget(button('Edit',lambda checked=False,r=reminder:self.edit_reminder(reminder=r)));row.addWidget(button('Remove',lambda checked=False,r=reminder:self.remove_reminder(r)));v.addLayout(row);v.addWidget(label('Every '+str(reminder['minutes'])+' min' if reminder['schedule']=='Interval' else ', '.join(reminder.get('times',[])) if reminder['schedule']=='Times of day' else 'One-off'));self.reminder_layout.addWidget(f)
    def toggle_reminder(self,reminder,value):reminder['enabled']=value;self.state.save()
    def remove_reminder(self,reminder):self.state.value['reminders'].remove(reminder);self.state.save();self.populate_reminders()
    def edit_reminder(self,checked=False,reminder=None,preset=None):
        dialog=QDialog(self);dialog.setWindowTitle('A gentle reminder');v=QVBoxLayout(dialog);form=QFormLayout();v.addLayout(form);title=QLineEdit((reminder or {}).get('title',preset or ''));type=QComboBox();type.addItems(['Hydration','Stretch','Posture','Eye Rest','Custom']);type.setCurrentText((reminder or {}).get('type',preset or 'Custom'));schedule=QComboBox();schedule.addItems(['Interval','Times of day','One-off']);schedule.setCurrentText((reminder or {}).get('schedule','Interval'));minutes=QSpinBox();minutes.setRange(1,1440);minutes.setValue((reminder or {}).get('minutes',45));times=QLineEdit(', '.join((reminder or {}).get('times',['09:00','15:00'])));when=QDateTimeEdit();when.setCalendarPopup(True);when.setDateTime(datetime.fromtimestamp((reminder or {}).get('nextDue',time.time()+3600)));message=QLineEdit((reminder or {}).get('message',''));priority=QCheckBox('Even during a focus session');priority.setChecked((reminder or {}).get('priority',False))
        for name,w in [('Title',title),('Kind',type),('Schedule',schedule),('Every (minutes)',minutes),('Times (09:00, 15:00)',times),('Date & time',when),('Your message',message)]:form.addRow(name,w)
        v.addWidget(priority);error=label('');v.addWidget(error);buttons=QDialogButtonBox(QDialogButtonBox.Save|QDialogButtonBox.Cancel);buttons.rejected.connect(dialog.reject);v.addWidget(buttons)
        def save():
            try:
                if not title.text().strip():raise ValueError('Give this reminder a name.')
                t=[s.strip() for s in times.text().split(',')];now=time.time();due=now+minutes.value()*60 if schedule.currentText()=='Interval' else next_time(t,now) if schedule.currentText()=='Times of day' else when.dateTime().toSecsSinceEpoch()
                if due<=now:raise ValueError('Choose a future date and time.')
                value={'id':reminder['id'] if reminder else uuid.uuid4().hex,'title':title.text().strip()[:120],'type':type.currentText(),'schedule':schedule.currentText(),'minutes':minutes.value(),'times':t,'nextDue':due,'enabled':True,'priority':priority.isChecked(),'message':message.text().strip()[:300]}
                if reminder:reminder.clear();reminder.update(value)
                else:self.state.value['reminders'].append(value)
                self.state.save();dialog.accept();self.populate_reminders()
            except ValueError as e:error.setText(str(e))
        buttons.accepted.connect(save);dialog.exec()
    def make_settings(self):
        tabs=QTabWidget();general=QWidget();g=QVBoxLayout(general);pet=self.catalog.by_id.get(self.state.prefs['companion'],self.catalog.pets[0]);self.rename_field=QLineEdit(self.state.name(pet));self.rename_field.setMaxLength(40);g.addWidget(label('Your companion’s name',17,True));g.addWidget(self.rename_field);g.addWidget(button('Save name',lambda:self.state.rename(self.c.pet.pet.id,self.rename_field.text(),self.c.pet.pet.name),True))
        self.setting_controls={}
        def check(layout,title,key,fn=None):
            control=QCheckBox(title);control.setChecked(self.state.prefs[key]);control.toggled.connect(lambda value:self.guarded(lambda:(fn(value) if fn else None,self.state.set(key,value))));layout.addWidget(control);self.setting_controls[key]=control;return control
        def combo(layout,title,key,values,reset=False):
            layout.addWidget(label(title));control=QComboBox();control.addItems(values);control.setCurrentText(self.state.prefs[key]);control.currentTextChanged.connect(lambda value:(self.state.set(key,value),self.c.pet.reanchor(True) if reset else None));layout.addWidget(control);self.setting_controls[key]=control
        def slider(layout,title,key,low,high,factor):
            layout.addWidget(label(title));control=QSlider(Qt.Horizontal);control.setRange(low,high);control.setValue(round(self.state.prefs[key]*factor));control.valueChanged.connect(lambda value:self.state.set(key,value/factor));layout.addWidget(control);self.setting_controls[key]=control
        slider(g,'Pet size', 'scale',55,180,100);check(g,'Mirror companion','mirror',lambda value:QTimer.singleShot(0,lambda:self.c.pet.reanchor(True)));check(g,'Show head accessories','headAccessoriesVisible');check(g,'Mute sound effects','muted');combo(g,'Movement','movement',['Stay','Roam','Patrol','Follow cursor']);combo(g,'Position','anchor',['Bottom Dock','Active Window','Notch','Free Floating'],True);check(g,'Open at login','login',self.c.set_login);g.addWidget(button('Reset position',lambda:self.c.pet.reanchor(True)));g.addStretch();tabs.addTab(scroll(general),'Companion')
        progress=QWidget();p=QVBoxLayout(progress);p.addWidget(label('Earn at your own pace',20,True));p.addWidget(label('Every input earns XP. A fast rhythm earns 2× XP; levels reveal new friends and gifts. Switching pets leaves your earning track unchanged.'));self.track_combo=QComboBox()
        for t in self.state.progress['tracks']:self.track_combo.addItem(t['name'],t['id'])
        self.track_combo.setCurrentIndex(self.track_combo.findData(self.state.progress['activeTrack']));self.track_combo.currentIndexChanged.connect(self.change_track);p.addWidget(self.track_combo);follows=QCheckBox('XP follows my companion');follows.setChecked(self.state.progress['followsPet']);follows.toggled.connect(lambda value:self.progress_flag('followsPet',value));p.addWidget(follows);cheers=QCheckBox('Occasional encouraging phrases');cheers.setChecked(self.state.progress['automaticCheers']);cheers.toggled.connect(lambda value:self.progress_flag('automaticCheers',value));p.addWidget(cheers);self.level_summary=label('');p.addWidget(self.level_summary);p.addWidget(button('Open gifts',self.open_gifts));p.addStretch();tabs.addTab(progress,'Progress')
        account=QWidget();a=QVBoxLayout(account);self.wallet_status=label('Development build · local features are available.');a.addWidget(self.wallet_status);self.email=QLineEdit();self.email.setPlaceholderText('Email used at checkout');self.code=QLineEdit();self.code.setPlaceholderText('One-time email code');a.addWidget(self.email);a.addWidget(button('Send restore code',lambda:self.job(lambda:self.c.backend.restore(self.email.text().strip()),lambda result:self.notify(result['message']))));a.addWidget(self.code);a.addWidget(button('Restore purchase',lambda:self.job(lambda:self.c.backend.restore(self.email.text().strip(),self.code.text().strip()),self.wallet_updated),True));a.addWidget(button('Refresh credits & license',lambda:self.job(self.c.backend.wallet,self.wallet_updated)));a.addWidget(button('Buy more credits',lambda:self.c.checkout('credits5')));a.addWidget(button('Buy PawSync',lambda:self.c.checkout('base')));sync=QCheckBox('Keep earned progress together across devices');sync.setChecked(self.state.progress['syncEnabled']);sync.toggled.connect(lambda value:self.progress_flag('syncEnabled',value));a.addWidget(sync);a.addWidget(button('Sync now',self.c.sync));a.addWidget(button('Sign out',self.c.sign_out));a.addWidget(label('Purchased credits never expire. Only the server decides the balance. Saved licenses allow the base app to work offline.'));a.addStretch();tabs.addTab(scroll(account),'Account')
        advanced=QWidget();ad=QVBoxLayout(advanced);ad.addWidget(label('Privacy & connections',20,True));self.input_status=label(self.c.input.status);ad.addWidget(self.input_status);self.c.input.status_changed.connect(self.input_status.setText);ad.addWidget(button('Enable global typing / clicks',self.c.enable_input));ad.addWidget(button('Stop global input',self.c.input.stop));ad.addWidget(button('Enable Linux input helper (Wayland)',self.c.input.enable_helper));ad.addWidget(label('Input monitors use event occurrences only. No key codes, typed text or audio are logged. Linux helper authorization is separate and optional.'))
        check(ad,'Dance to system audio (processed in memory only)','music',self.c.set_music);check(ad,'Traverse frontmost window edges','edgeTraversal');check(ad,'Local developer hooks · 127.0.0.1:9876','integrations',self.c.set_integrations);ad.addWidget(button('Regenerate hook token',self.c.regenerate_token));ad.addWidget(button('Copy integration template',self.c.copy_template));slider(ad,'Opacity (never changes automatically)','opacity',30,100,100);check(ad,'Click-through companion','clickThrough');tests=QHBoxLayout();tests.addWidget(button('Typing',lambda:self.c.pet.react('Typing')));tests.addWidget(button('Click',lambda:self.c.pet.react('Cuddle')));tests.addWidget(button('Walk',self.c.pet.roam));tests.addWidget(button('Jump',lambda:self.c.pet.roam(True)));ad.addLayout(tests)
        ad.addWidget(label('Available native integration modules',17,True))
        for feature in self.c.content.get('features',[]):
            if feature['phase']==2:
                control=QCheckBox(feature['name']);control.setChecked(self.c.tools.enabled(feature['id']));control.toggled.connect(lambda value,id=feature['id']:self.c.tools.enable(id,value));ad.addWidget(control)
            else:ad.addWidget(label(feature['name']+' · connected feature not enabled in this release',12))
        ad.addStretch();tabs.addTab(scroll(advanced),'Advanced')
        about=QWidget();av=QVBoxLayout(about);av.addWidget(label('PawSync 0.3.0',24,True));av.addWidget(label('Windows & Linux preview · shared pets and accessories with the native macOS app.'));av.addWidget(button('Check for updates…',self.c.check_updates));av.addWidget(button('Open data folder',lambda:QDesktopServices.openUrl(QUrl.fromLocalFile(str(self.state.root)))));av.addWidget(button('Reset earned progress…',self.reset_progress));av.addWidget(button('Licenses & artwork credits',lambda:info(self,'Credits','OpenPets artwork: MIT · OpenPets contributors.\nQt/PySide6: LGPLv3, dynamically linked.\nOther library licenses are included with the distribution.\nOriginal/imported asset attribution is retained with each pet.')));av.addStretch();tabs.addTab(about,'About');self.add_page(tabs)
    def change_track(self,index):
        self.state.progress['activeTrack']=self.track_combo.itemData(index);self.state.save();self.state.changed.emit()
    def progress_flag(self,key,value):self.state.progress[key]=value;self.state.save()
    def wallet_updated(self,result):
        self.credit_note.setText(f"{result['credits']} generation credits · never expire")
        self.wallet_status.setText(('Purchased' if result['licensed'] else 'Not purchased')+f" · {result['credits']} credits");self.c.enforce_license();self.populate_items()
    def reset_progress(self):
        if QMessageBox.question(self,'Start fresh?','Reset earned pets, items, gifts and achievements? Purchases, names and preferences are kept. Backups are saved.')!=QMessageBox.Yes:return
        def reset(epoch):
            self.state.backup();value=fresh_progress();value['epoch']=epoch;self.state.value['progress']=value;self.state.update_unlocks();self.state.save();self.state.changed.emit()
        if self.state.progress['syncEnabled']:self.job(lambda:self.c.backend.request('/v1/library/progress/reset','POST'),lambda result:reset(result['epoch']))
        else:reset(self.state.progress['epoch']+1)
    def refresh_visible(self):
        pet=self.catalog.by_id.get(self.state.prefs['companion'],self.catalog.pets[0]);self.mini.setText(self.state.name(pet)+'\n'+f"Level {self.state.level()} · earning XP")
        index=self.sidebar.currentRow()
        if index==0:self.populate_pets()
        elif index==1:self.populate_items()
        elif index==2:self.populate_achievements()
        elif index==4:self.populate_reminders()
        elif index==5:
            self.level_summary.setText('\n'.join(f"{t['name']} · Level {t['xp']//500+1} · {t['xp']%500}/500 XP" for t in self.state.progress['tracks']))
            if not self.rename_field.hasFocus():self.rename_field.setText(self.state.name(pet))

    def make_extra_tools(self,layout):
        self.extra_tool_cards={}
        countdown,cv=card();cv.addWidget(label('Simple timer',18,True));self.timer_readout=label(self.c.tools.timer_text());cv.addWidget(self.timer_readout);self.task_label=QLineEdit('A little task');cv.addWidget(self.task_label);minutes=QSpinBox();minutes.setRange(1,1440);minutes.setValue(15);cv.addWidget(minutes);row=QHBoxLayout()
        for title,fn in [('Start',lambda:self.c.tools.start_timer(minutes.value(),self.task_label.text())),('Pause / resume',self.c.tools.pause_timer),('+5 min',self.c.tools.add_five),('Cancel',self.c.tools.cancel_timer)]:row.addWidget(button(title,fn))
        cv.addLayout(row);layout.insertWidget(layout.count()-1,countdown);self.extra_tool_cards['openpets.simple-timer']=countdown
        practice,pv=card();pv.addWidget(label('A gentler moment',18,True));self.practice_kind=QComboBox();self.practice_kind.addItems(['Paced breathing','Unwind your muscles','Grounding','Quiet moment','Peaceful place']);pv.addWidget(self.practice_kind);row=QHBoxLayout();row.addWidget(button('Begin 2 min',lambda:self.c.tools.start_practice(self.practice_kind.currentText())));row.addWidget(button('Pause / resume',self.c.tools.pause_practice));row.addWidget(button('Stop',self.c.tools.stop_practice));pv.addLayout(row);layout.insertWidget(layout.count()-1,practice);self.extra_tool_cards['openpets.anxiety-aid-tools']=practice
        care,cav=card();cav.addWidget(label('Optional pet care',18,True));self.care_status=label('');cav.addWidget(self.care_status);row=QHBoxLayout()
        for action in ['feed','play','pet','nap']:row.addWidget(button(action.capitalize(),lambda checked=False,a=action:self.c.tools.care(a)))
        cav.addLayout(row);layout.insertWidget(layout.count()-1,care);self.extra_tool_cards['openpets.virtual-pet']=care
        resource,rv=card();rv.addWidget(label('System resources',18,True));self.resource_status=label('');rv.addWidget(self.resource_status);rv.addWidget(button('Check now',self.show_resources));layout.insertWidget(layout.count()-1,resource);self.extra_tool_cards['openpets.system-resources']=resource
        routine,r=card();r.addWidget(label('Morning & evening',18,True));r.addWidget(label('Use times-of-day reminders for a morning intention or a cozy evening reset.'));r.addWidget(button('Add a daily routine',lambda:self.edit_reminder(preset='Custom')));layout.insertWidget(layout.count()-1,routine);self.extra_tool_cards['openpets.day-routine']=routine
        self.refresh_tools()
    def refresh_tools(self):
        for id,w in self.extra_tool_cards.items():w.setVisible(self.c.tools.enabled(id))
        if self.c.tools.enabled('openpets.virtual-pet'):
            n=self.c.tools.needs();self.care_status.setText(f"Food {n['food']:.0f}% · Energy {n['energy']:.0f}% · Happiness {n['happiness']:.0f}% · Affection {n['affection']:.0f}% · Level {n['level']}")
    def show_resources(self):
        import psutil
        self.resource_status.setText(f'CPU {psutil.cpu_percent()}% · Memory {psutil.virtual_memory().percent}%')

    def import_folder(self):
        folder=QFileDialog.getExistingDirectory(self,'Choose an OpenPets folder')
        if folder:
            pet=self.guarded(lambda:self.catalog.import_pet(folder))
            if pet:self.state.choose(pet);self.populate_pets()
    def import_codex(self):
        root=Path.home()/'.codex/pets';imported=0;failed=0
        for directory in list(root.glob('*'))[:200]:
            if not directory.is_dir():continue
            try:self.catalog.import_pet(directory);imported+=1
            except (ValueError,OSError):failed+=1
        self.populate_pets();self.notify(f'Imported {imported} pets; skipped {failed} invalid packages. Originals are unchanged.')
