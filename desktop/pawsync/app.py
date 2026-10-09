from __future__ import annotations
import copy, json, os, random, sys, time
from pathlib import Path
# XWayland is needed for positioning/tray on compositors lacking desktop-pet protocols.
if sys.platform.startswith('linux') and os.environ.get('XDG_SESSION_TYPE')=='wayland' and os.environ.get('DISPLAY'):
    os.environ.setdefault('QT_QPA_PLATFORM','xcb')
from PySide6.QtCore import QObject, QTimer, Qt, QUrl, Signal, QEvent, QPoint
from PySide6.QtGui import QIcon, QPixmap, QDesktopServices, QCursor
from PySide6.QtWidgets import QApplication, QSystemTrayIcon, QMenu, QMessageBox
from PySide6.QtNetwork import QLocalServer, QLocalSocket
from . import __version__
from .assets import ASSETS, RESOURCES, Catalog
from .state import State, data_root
from .companion import Companion
from .input import InputMonitor
from .services import Vault, Backend
from .platform import SleepMonitor, login_enabled
from .integrations import Loopback, Music
from .popups import FilePocket, Speech, QuickActions
from .jobs import launch
from .ui import Library
from .tools import Tools

class Controller(QObject):
    def __init__(self,app):
        super().__init__();self.closed=False;self.app=app;self.content=json.loads((ASSETS/'content.json').read_text());self.state=State(self.content);self.catalog=Catalog(self.state.root);self.tools=Tools(self.state,self.content);self.vault=Vault();self.backend=Backend(self.vault);self.input=InputMonitor();self.hooks=Loopback(self.vault);self.music=Music();self.pet=Companion(self.state,self.catalog,self.content)
        self.pocket=FilePocket(self.pet);self.speech=Speech(self.pet);self.quick=QuickActions(self.pet,[('Chat ♡',self.chat),('Files',self.pocket.reveal),('Reminder',lambda:self.library.edit_reminder()),('Focus',self.start_focus),('Library',lambda:self.library.open_page('Pets'))]);self.library=Library(self);self.tools.said.connect(self.say)
        self.input.typing.connect(lambda:self.activity('Typing'));self.input.click.connect(lambda:self.activity('Click'))
        self.pet.double_tapped.connect(self.quick.reveal);self.pet.clicked.connect(self.cuddle);self.pet.petted.connect(lambda:self.state.record('pet'));self.pet.dropped.connect(self.catch);self.pet.pocket_requested.connect(self.pocket.reveal);self.pocket.count_changed.connect(self.holding)
        self.speech.snoozed.connect(self.state.snooze);self.speech.chat_sent.connect(self.respond);self.state.toast.connect(lambda title,detail:self.say(title+' ♡','Happy'))
        self.hooks.status.connect(lambda status:self.pet.react({'build_success':'Success','build_failed':'Failed','typing':'Typing','click':'Click','celebrate':'Success','wave':'Wave'}[status]));self.music.active.connect(self.dance);self.music.beat.connect(self.beat);self.music.error.connect(self.library.notify)
        self.sleep=SleepMonitor(self.pet);self.sleep.sleeping.connect(self.pause);self.last_cheer=time.monotonic();self.pending=[];self.current_reminder=None;self.focus_end=self.state.value['focus'].get('ends',0);self.break_end=0
        icon=QIcon(str(RESOURCES/'AppIcon.icns'))
        if icon.isNull():icon=QIcon(QPixmap.fromImage(self.catalog.by_id['knight-cat'].preview().scaled(32,32)))
        app.setWindowIcon(icon);self.tray=QSystemTrayIcon(icon,self);self.menu=QMenu();self.tray.setContextMenu(self.menu);self.tray.activated.connect(lambda reason:self.library.open_page('Pets') if reason==QSystemTrayIcon.DoubleClick else None);self.rebuild_menu();self.tray.show();self.state.changed.connect(self.rebuild_menu)
        self.timer=QTimer(self);self.timer.setInterval(1000);self.timer.timeout.connect(self.tick);self.timer.start();self.save_timer=QTimer(self);self.save_timer.setInterval(30000);self.save_timer.timeout.connect(self.flush);self.save_timer.start();self.app.installEventFilter(self)
        app.aboutToQuit.connect(self.shutdown);self.enforce_license();self.start_background();QTimer.singleShot(200,self.enable_input)
        if self.focus_end>time.time():self.pet.set_focus_sleep(True)
        if self.state.prefs['greet'] and not self.focus_end:QTimer.singleShot(1500,lambda:self.say('A little friend for your day. Let’s make it a kind one ♡','Happy'))
        self.reminder_to_show=None;self.pet.travel_finished.connect(self.reminder_arrived)
        self.pet.moved.connect(self.move_popups)
    def eventFilter(self,obj,event):
        # Only TYPE is inspected. Manual chat fields are ordinary explicitly typed UI.
        if event.type()==QEvent.KeyPress and not self.input.running:self.activity('Typing')
        elif event.type()==QEvent.MouseButtonPress and not self.input.running and obj is not self.pet:self.activity('Click')
        return False
    def rebuild_menu(self):
        self.menu.clear();self.menu.addAction('Open Library',lambda:self.library.open_page('Pets'));self.menu.addAction('Settings',lambda:self.library.open_page('Settings'));self.menu.addSeparator()
        mute=self.menu.addAction('Mute');mute.setCheckable(True);mute.setChecked(self.state.prefs['muted']);mute.triggered.connect(lambda value:self.state.set('muted',value));hidden=self.menu.addAction('Hide pet');hidden.setCheckable(True);hidden.setChecked(self.state.prefs['hidden']);hidden.triggered.connect(self.hide_pet)
        self.menu.addAction('Hide for 1 hour',self.hide_hour);self.menu.addAction('Start Pomodoro',self.start_focus);self.menu.addAction('Reminders',lambda:self.library.open_page('Wellness'));self.menu.addAction('Reset position',lambda:self.pet.reanchor(True));self.menu.addAction('Check for updates…',self.check_updates);self.menu.addSeparator();self.menu.addAction('Quit',self.quit)
    def enable_input(self):
        if not self.closed and self.backend.licensed:self.input.start()
    def activity(self,kind):
        if not self.backend.licensed:return
        self.state.input();self.pet.react(kind)
    def cuddle(self):
        if self.current_reminder:self.speech.hide();self.current_reminder=None;return
        self.state.record('hello');self.say(random.choice(self.content['lines']),'Cuddle')
    def say(self,message,emotion='Happy'):
        if self.closed:return
        if not self.state.prefs['hidden']:self.pet.react(emotion);self.speech.say(message)
    def chat(self):self.pet.stop_travel();self.speech.say('Hi, little friend! I’m listening ♡',chat=True)
    def respond(self,text):
        # Local companion conversation: no message is sent to a cloud service.
        self.state.record('chat');self.speech.say(random.choice(['I’m right here with you ♡ One little step at a time.','That sounds like a lot. A tiny break and a deep breath might help.','You’ve got this. I’ll keep you company while you take the next step.']),chat=True);self.pet.react('Affectionate')
    def catch(self,paths):self.pocket.add_files(paths);self.pet.react('Happy');self.state.record('files')
    def holding(self,count):self.pet.holding=count;self.pet.rest();self.pet.update_visual()
    def hide_pet(self,value):
        self.state.set('hidden',value);self.music.pause(value)
        if value:self.speech.hide();self.pocket.hide();self.quick.hide()
    def hide_hour(self):self.hide_pet(True);QTimer.singleShot(3600000,lambda:self.hide_pet(False))
    def start_focus(self,checked=False):
        if not self.backend.licensed:return
        self.focus_end=time.time()+25*60;self.break_end=0;self.pet.set_focus_sleep(True);self.state.value['focus']={'ends':self.focus_end};self.state.save();self.library.open_page('Wellness')
    def stop_focus(self):self.focus_end=0;self.break_end=0;self.pet.set_focus_sleep(False);self.state.value['focus']={};self.state.save()
    def tick(self):
        now=time.time();self.tools.tick(bool(self.focus_end))
        if hasattr(self.library,'timer_readout'):self.library.timer_readout.setText(self.tools.timer_text())
        if self.focus_end and now>=self.focus_end:
            self.focus_end=0;self.break_end=now+300;self.pet.sleeping=False;self.state.record('focus');self.state.value['focus']={};self.say('A lovely little focus session! Time for a gentle break ♡','Success');self.chime()
        if self.break_end and now>=self.break_end:self.break_end=0;self.say('Ready for another little step? ♡')
        self.library.focus_status.setText('Focus · '+self.countdown(self.focus_end-now) if self.focus_end else 'Break · '+self.countdown(self.break_end-now) if self.break_end else 'Ready when you are')
        self.pending+=self.state.due(now,bool(self.focus_end))
        if self.pending and not self.pet.screen_sleep and (not self.current_reminder or not self.speech.isVisible()):self.deliver(self.pending.pop(0))
        if self.state.progress['automaticCheers'] and time.monotonic()-self.last_cheer>1800 and not self.focus_end:
            self.last_cheer=time.monotonic();self.say(random.choice(self.content['lines']))
    @staticmethod
    def countdown(seconds):return f'{max(0,int(seconds))//60:02d}:{max(0,int(seconds))%60:02d}'
    def deliver(self,reminder):
        self.current_reminder=reminder['id'];kind=reminder['type'];message=reminder.get('message') or {'Hydration':'A little sip of water? Your body will thank you ♡','Stretch':'Time for a biiig gentle stretch ♡','Posture':'Let your shoulders soften and sit comfortably ♡','Eye Rest':'Look far away for 20 seconds. Rest those lovely eyes ♡'}.get(kind,reminder['title']);self.state.record('reminder');self.chime()
        if not self.state.prefs['hidden']:
            self.pet.sleeping=False;self.reminder_to_show=(message,reminder);screen=self.pet.active_screen().availableGeometry();self.pet.walk_to(QPoint(screen.center().x()-self.pet.width()//2,screen.bottom()-self.pet.height()+1))
        if self.state.prefs['hidden'] or not self.library.isVisible() or self.library.isMinimized():self.tray.showMessage('PawSync · '+reminder['title'],message,QSystemTrayIcon.Information,10000)
    def reminder_arrived(self):
        if not self.reminder_to_show:return
        message,reminder=self.reminder_to_show;self.reminder_to_show=None;self.pet.react('Cozy' if reminder['type']=='Stretch' else 'Wave');self.speech.say(message,reminder['id'])
        if self.focus_end:QTimer.singleShot(10000,self.resume_focus_pose)
    def resume_focus_pose(self):
        if self.focus_end:self.pet.sleeping=True;self.pet.frame_timer.stop();self.pet.rest();self.pet.update_visual()
    def move_popups(self):
        for popup in (self.speech,self.pocket):
            if popup.isVisible():popup.place()
    def chime(self):
        if not self.state.prefs['muted']:QApplication.beep()
    def dance(self,active):
        self.pet.dancing=active
        if active and self.pet.mode=='Idle' and not self.pet.sleeping:self.pet.react('Dance')
        elif not active and self.pet.mode=='Dance':self.pet.rest();self.pet.frame_timer.stop();self.pet.update_visual()
    def beat(self):
        if self.pet.dancing and self.pet.mode=='Idle' and not self.pet.sleeping:self.pet.react('Dance')
    def pause(self,value):self.pet.pause(value);self.music.pause(value or self.state.prefs['hidden'])
    def set_music(self,value):
        if value:self.music.start()
        else:self.music.stop();self.dance(False)
    def set_login(self,value):login_enabled(value)
    def set_integrations(self,value):
        if value:
            token=self.hooks.start()
            if token:self.show_token(token)
        else:self.hooks.stop()
    def regenerate_token(self):
        try:self.show_token(self.hooks.regenerate())
        except ValueError as error:self.library.notify(str(error))
    def show_token(self,token):
        QMessageBox.information(self.library,'Your local hook token','Copy and keep this token. It is stored securely and shown only now:\n\n'+token)
    def copy_template(self):
        QApplication.clipboard().setText('curl --fail http://127.0.0.1:9876/hook -H "Authorization: Bearer YOUR_TOKEN" -H "Content-Type: application/json" --data \'{"status":"build_success"}\'');self.library.notify('Template copied. Replace YOUR_TOKEN with your own local hook token.')
    def checkout(self,sku):
        url=self.backend.config.get('checkoutURLs',{}).get(sku)
        if url and QUrl(url).scheme()=='https':QDesktopServices.openUrl(QUrl(url))
        else:self.library.notify('Checkout has not been configured for this build.')
    def check_updates(self):QDesktopServices.openUrl(QUrl('https://github.com/pujanpoudel/pawsync/releases'))
    def sync(self):
        launch(lambda:self.backend.sync(copy.deepcopy(self.state.progress)),self.state.merge,self.library.notify,self)
    def sign_out(self):
        try:self.vault.put('license','');self.backend.licensed=self.backend.config.get('environment')=='development';self.backend.owned=[];self.backend.credits=None;self.enforce_license();self.library.wallet_status.setText('Signed out')
        except ValueError as error:self.library.notify(str(error))
    def enforce_license(self):
        self.pet.owned=self.backend.owned
        if not self.backend.licensed:self.pet.hide();self.input.stop();self.music.stop();self.hooks.stop();self.library.notify('Restore your purchase to unlock your companion.')
        else:self.pet.refresh()
    def start_background(self):
        try:
            if self.state.prefs['integrations'] and self.backend.licensed:self.set_integrations(True)
        except ValueError as error:self.library.notify(str(error))
        if self.state.prefs['music']:self.music.start()
        if self.backend.config.get('environment')=='development' and os.environ.get('PAWSYNC_OFFLINE_PREVIEW'):return
        try:token=self.vault.get('license')
        except ValueError:token=None
        if token:
            def validated(result):
                self.library.wallet_updated(result)
                if self.state.progress['syncEnabled']:self.sync()
            launch(self.backend.wallet,validated,lambda message:(self.enforce_license(),self.library.notify(message)),self)
    def flush(self):
        if self.state.dirty:self.state.save()
    def quit(self):
        self.shutdown();self.app.exit(0)
    def shutdown(self):
        if self.closed:return
        self.closed=True;self.timer.stop();self.save_timer.stop();self.pet.heartbeat.stop();self.pet.frame_timer.stop()
        self.input.stop();self.music.stop();self.hooks.stop();self.sleep.stop();self.state.save();self.tray.hide();self.pocket.clear()


def main():
    if '--version' in sys.argv:print('PawSync '+__version__);return 0
    app=QApplication(sys.argv);app.setOrganizationName('PawSync');app.setApplicationName('PawSync');app.setQuitOnLastWindowClosed(False)
    name='PawSync-'+str(os.getuid() if hasattr(os,'getuid') else os.environ.get('USERNAME','user'))
    socket=QLocalSocket();socket.connectToServer(name)
    if socket.waitForConnected(300):socket.write(b'library');socket.flush();socket.waitForBytesWritten(300);return 0
    QLocalServer.removeServer(name);server=QLocalServer();server.setSocketOptions(QLocalServer.UserAccessOption);server.listen(name)
    controller=Controller(app)
    def incoming():
        peer=server.nextPendingConnection();peer.disconnectFromServer();controller.library.open_page('Pets')
    server.newConnection.connect(incoming)
    if '--background' not in sys.argv:controller.library.show()
    if '--smoke-test' in sys.argv:QTimer.singleShot(1500,controller.quit)
    return app.exec()
