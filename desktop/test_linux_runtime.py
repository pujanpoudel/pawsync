"""Run under Xvfb/Openbox. Checks actual shaped-window routing and desktop reactions."""
import os,sys,time
from pathlib import Path
os.environ['PAWSYNC_OFFLINE_PREVIEW']='1';os.environ['PAWSYNC_DATA_DIR']='/tmp/pawsync-linux-runtime';os.environ['QT_QPA_PLATFORM']='xcb'
from PySide6.QtWidgets import QApplication,QPushButton
from PySide6.QtCore import QPoint,QTimer,Qt
from PySide6.QtTest import QTest
from pawsync.app import Controller
from Xlib import display,X
from Xlib.ext import xtest
app=QApplication([]);app.setApplicationName('PawSync');c=Controller(app);c.library.hide();c.pet.heartbeat.stop();c.timer.stop();c.save_timer.stop();c.enable_input()
def wait(seconds):
    end=time.monotonic()+seconds
    while time.monotonic()<end:app.processEvents();time.sleep(.005)
wait(1)
assert c.input.running,c.input.status
sender=display.Display();visible=c.pet.screen().availableGeometry();outside=QPushButton('Background control');outside.setGeometry(visible.left()+60,visible.top()+80,240,100);outside.show();hits=[];outside.clicked.connect(lambda:hits.append(1));wait(.2)
point=outside.mapToGlobal(outside.rect().center());xtest.fake_input(sender,X.MotionNotify,x=point.x(),y=point.y());xtest.fake_input(sender,X.ButtonPress,1);xtest.fake_input(sender,X.ButtonRelease,1);sender.sync();wait(.3);assert hits,'Background click blocked'
c.pet.roam();wait(.4);position=c.pet.pos();xtest.fake_input(sender,X.KeyPress,38);xtest.fake_input(sender,X.KeyRelease,38);sender.sync();wait(.1);assert c.pet.travel is None;assert c.pet.pos()==position;assert c.pet.mode=='Typing'
wait(.6);c.pet.roam(True);wait(.4);position=c.pet.pos();xtest.fake_input(sender,X.ButtonPress,1);xtest.fake_input(sender,X.ButtonRelease,1);sender.sync();wait(.1);assert c.pet.travel is None;assert c.pet.pos()==position
# Find an actually opaque pixel, then double click using a separate X client.
wait(.7);image=c.pet.image;point=None
for y in range(image.height()//2,image.height()):
    for x in range(image.width()//3,image.width()*2//3):
        if image.pixelColor(x,y).alpha()>250:point=c.pet.mapToGlobal(QPoint(x,y));break
    if point:break
xtest.fake_input(sender,X.MotionNotify,x=point.x(),y=point.y());sender.sync();wait(.1)
for _ in range(2):
    xtest.fake_input(sender,X.ButtonPress,1);xtest.fake_input(sender,X.ButtonRelease,1);sender.sync();wait(.07)
wait(.15);assert c.quick.isVisible(),'Real desktop double-click did not open quick actions'
# All six screens render with the same resources.
c.library.show();wait(.2);out=Path('/workspace/build/linux-desktop-preview');out.mkdir(parents=True,exist_ok=True)
for page in c.library.pages:c.library.open_page(page);wait(.15);c.library.grab().save(str(out/(page.replace(' ','-')+'.png')))
print('PASS: external X11 keys/clicks, roaming freeze, shaped-window routing, double-click menu, six Library screens')
sender.close();c.shutdown();outside.close();c.pet.close()
