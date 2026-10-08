import json,time
from pathlib import Path
from PySide6.QtCore import Qt,QPoint,QMimeData,QUrl
from PySide6.QtGui import QDropEvent,QDragEnterEvent,QPixmap
from PySide6.QtTest import QSignalSpy,QTest
from pawsync.companion import Companion,Artwork
from pawsync.assets import ASSETS
from pawsync.popups import FilePocket,QuickActions,Speech

def test_shared_catalog_has_all_pets_and_native_items(catalog,content):
    assert len(catalog.pets)==47;assert len(content['items'])==230;assert len(content['achievements'])==30;assert len(content['secrets'])==7
    for pet in catalog.pets:
        assert not pet.preview().isNull();assert len(next(p['fits'] for p in content['pets'] if p['id']==pet.id))==pet.rows
    for item in content['items']:assert not QPixmap(str(ASSETS/item['file'])).isNull()

def test_typing_and_click_stop_roaming_at_current_location(qtbot,state,catalog,content):
    pet=Companion(state,catalog,content);qtbot.addWidget(pet);pet.heartbeat.stop();pet.roam();pet.advance(pet.travel[2]+.6);position=pet.pos()
    pet.react('Typing');assert pet.pos()==position;assert pet.travel is None;assert pet.mode=='Typing';pet.reanchor();assert pet.pos()==position
    pet.roam(True);pet.advance(pet.travel[2]+.6);position=pet.pos();pet.react('Click');assert pet.pos()==position;assert pet.mode=='Click'

def test_double_click_menu_not_hover(qtbot,state,catalog,content):
    pet=Companion(state,catalog,content);qtbot.addWidget(pet);pet.heartbeat.stop();menu=QuickActions(pet,[('Library',lambda:None)]);qtbot.addWidget(menu);pet.double_tapped.connect(menu.reveal)
    QTest.mouseMove(pet,QPoint(140,180));assert not menu.isVisible()
    QTest.mouseDClick(pet,Qt.LeftButton,pos=QPoint(140,180));assert menu.isVisible()

def test_click_cuddle_and_rabbit_no_catch_extra_arms(qtbot,state,catalog,content):
    state.progress['pets'].append('bunny');state.choose(catalog.by_id['bunny']);pet=Companion(state,catalog,content);qtbot.addWidget(pet);pet.heartbeat.stop()
    QTest.mouseClick(pet,Qt.LeftButton,pos=QPoint(140,180));assert pet.mode=='Cuddle'
    pet.advance(pet.started+.3);assert pet.row==4 and pet.column==2 and pet.pose is None

def test_file_pocket_original_name_no_copy_and_drag_urls(qtbot,state,catalog,content,tmp_path):
    pet=Companion(state,catalog,content);qtbot.addWidget(pet);pocket=FilePocket(pet);qtbot.addWidget(pocket);source=tmp_path/'notes final.txt';source.write_text('hello');pocket.add_files([str(source)])
    assert pocket.list.item(0).text()=='notes final.txt';assert pocket.list.item(0).data(Qt.UserRole)==str(source);assert source.read_text()=='hello';assert not (state.root/'Files').exists()
    pocket.clear();assert not pocket.isVisible();assert source.exists()

def test_pet_accepts_file_drag_and_drop(qtbot,state,catalog,content,tmp_path):
    pet=Companion(state,catalog,content);qtbot.addWidget(pet);source=tmp_path/'a.txt';source.write_text('a');mime=QMimeData();mime.setUrls([QUrl.fromLocalFile(str(source))]);spy=QSignalSpy(pet.dropped)
    enter=QDragEnterEvent(QPoint(140,180),Qt.CopyAction,mime,Qt.LeftButton,Qt.NoModifier);pet.dragEnterEvent(enter);assert enter.isAccepted() and pet.receiving
    drop=QDropEvent(QPoint(140,180),Qt.CopyAction,mime,Qt.LeftButton,Qt.NoModifier);pet.dropEvent(drop);assert spy.count()==1 and [Path(v) for v in spy.at(0)[0]]==[source]

def test_idle_never_sleeps_or_dims_and_hidden_pauses(qtbot,state,catalog,content):
    state.set('movement','Stay');pet=Companion(state,catalog,content);qtbot.addWidget(pet);pet.last_activity=0;pet.idle_tick()
    assert not pet.sleeping;assert pet.windowOpacity()==1.;assert not pet.frame_timer.isActive();pet.react('Typing');state.set('hidden',True);assert not pet.frame_timer.isActive()

def test_main_sidebar_cards_click_and_names(qtbot,monkeypatch,tmp_path):
    monkeypatch.setenv('PAWSYNC_DATA_DIR',str(tmp_path))
    from pawsync.app import Controller
    from PySide6.QtWidgets import QApplication
    c=Controller(QApplication.instance());qtbot.addWidget(c.library);c.input.stop();c.pet.heartbeat.stop();c.timer.stop();c.save_timer.stop();c.library.show()
    for page in c.library.pages:c.library.open_page(page);assert c.library.stack.currentIndex()==c.library.pages.index(page)
    c.library.choose_pet(c.catalog.by_id['knight-cat']);c.library.equip('free.sprout');assert c.state.prefs['accessory']=='free.sprout';assert c.state.prefs['companion']=='knight-cat'
    c.library.open_page('Settings');c.library.rename_field.setText('Sir Mochi');c.state.rename('knight-cat','Sir Mochi','Knight Cat');assert c.state.name(c.catalog.by_id['knight-cat'])=='Sir Mochi'
    c.shutdown();c.pet.close();c.quick.close();c.pocket.close();c.speech.close()

def test_library_close_hides_but_shutdown_accepts_close(qtbot,monkeypatch,tmp_path):
    from pawsync.app import Controller
    from PySide6.QtWidgets import QApplication
    from PySide6.QtGui import QCloseEvent
    monkeypatch.setenv('PAWSYNC_DATA_DIR',str(tmp_path));c=Controller(QApplication.instance());qtbot.addWidget(c.library)
    event=QCloseEvent();c.library.closeEvent(event);assert not event.isAccepted();c.shutdown();event=QCloseEvent();c.library.closeEvent(event);assert event.isAccepted()
    c.pet.close();c.quick.close();c.pocket.close();c.speech.close()
