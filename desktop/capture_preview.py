"""Capture real Qt layouts for review, not a separate mockup."""
import os,sys
os.environ['QT_QPA_PLATFORM']='offscreen';os.environ['PAWSYNC_OFFLINE_PREVIEW']='1';os.environ['PAWSYNC_DATA_DIR']='/tmp/pawsync-preview'
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from PySide6.QtWidgets import QApplication
from pawsync.app import Controller
app=QApplication([]);app.setApplicationName('PawSync');c=Controller(app);c.input.stop();c.timer.stop();c.pet.heartbeat.stop();c.save_timer.stop();c.library.show();directory=Path(__file__).resolve().parents[1]/'build/desktop-preview';directory.mkdir(exist_ok=True)
for name in c.library.pages:
    c.library.open_page(name);app.processEvents();c.library.grab().save(str(directory/(name.lower().replace(' ','-')+'.png')))
c.state.prefs['companion']='knight-cat';c.pet.refresh();c.pet.react('Cuddle');c.pet.advance(c.pet.started+.3);c.pet.image.save(str(directory/'knight-cuddle.png'))
c.speech.say('One little step at a time. I’m right here with you ♡',chat=True);app.processEvents();c.speech.grab().save(str(directory/'chat.png'))
file=directory/'Friendly notes.txt';file.write_text('The pocket holds references, never copies.');c.pocket.add_files([str(file)]);app.processEvents();c.pocket.grab().save(str(directory/'file-pocket.png'))
c.quick.reveal();app.processEvents();c.quick.grab().save(str(directory/'quick-menu.png'));c.shutdown()
print(directory)
