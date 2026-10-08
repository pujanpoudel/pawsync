"""Pet-anchored quick actions, thought bubbles and a temporary file pocket."""
from pathlib import Path
from PySide6.QtCore import Qt, QTimer, QMimeData, QUrl, QPoint, Signal
from PySide6.QtGui import QDrag, QPainter, QColor, QPen, QPainterPath, QCursor
from PySide6.QtWidgets import QWidget, QVBoxLayout, QHBoxLayout, QLabel, QPushButton, QListWidget, QListWidgetItem, QAbstractItemView, QLineEdit, QMenu, QApplication

class PetSurface(QWidget):
    def __init__(self,pet,parent=None):
        super().__init__(parent,Qt.Tool|Qt.FramelessWindowHint|Qt.WindowStaysOnTopHint);self.pet=pet
        self.setAttribute(Qt.WA_TranslucentBackground);self.setAttribute(Qt.WA_ShowWithoutActivating)
        self.setStyleSheet('QLabel{color:#40312b;background:transparent;} QPushButton{color:#40312b;background:#fffaf2;border:2px solid #d9b7a5;border-radius:14px;padding:8px 12px;font-weight:600;} QPushButton:hover{background:#f4dfeb;} QLineEdit{color:#40312b;background:white;border:2px solid #b18ab6;border-radius:15px;padding:9px;} QListWidget{color:#40312b;background:#fffaf2;border:0;border-radius:18px;} QListWidget::item{padding:9px;border-radius:10px;} QListWidget::item:selected{background:#e7d8f1;color:#40312b;}')
    def place(self):
        screen=self.pet.screen().availableGeometry();x=self.pet.x()+self.pet.width()//2-self.width()//2;y=self.pet.y()-self.height()+55
        self.move(max(screen.left()+8,min(screen.right()-self.width()-8,x)),max(screen.top()+8,min(screen.bottom()-self.height()-8,y)))
    def show_near(self): self.adjustSize();self.place();self.show();self.raise_()
    def paintEvent(self,event):
        painter=QPainter(self);painter.setRenderHint(QPainter.Antialiasing);painter.setPen(QPen(QColor('#b88d77'),2));painter.setBrush(QColor('#fff7eb'))
        # Rounded body, two soft ears and a scalloped base tie the surface to a pet.
        path=QPainterPath();path.setFillRule(Qt.WindingFill);path.addRoundedRect(5,20,self.width()-10,self.height()-27,26,26);path.addEllipse(20,5,35,36);path.addEllipse(self.width()-55,5,35,36);painter.drawPath(path.simplified());painter.end()

class DragList(QListWidget):
    def __init__(self): super().__init__();self.setSelectionMode(QAbstractItemView.ExtendedSelection);self.setDragEnabled(True);self.setDragDropMode(QAbstractItemView.DragOnly)
    def startDrag(self,actions):
        paths=[i.data(Qt.UserRole) for i in self.selectedItems() if Path(i.data(Qt.UserRole)).exists()]
        if not paths: return
        mime=QMimeData();mime.setUrls([QUrl.fromLocalFile(p) for p in paths]);drag=QDrag(self);drag.setMimeData(mime);drag.exec(Qt.CopyAction)

class FilePocket(PetSurface):
    count_changed=Signal(int)
    def __init__(self,pet):
        super().__init__(pet);self.paths=[];self.setMinimumSize(310,220);self.setMaximumWidth(380)
        layout=QVBoxLayout(self);layout.setContentsMargins(22,36,22,20);top=QHBoxLayout();top.addWidget(QLabel('Little file pocket'));clear=QPushButton('Clear all');clear.clicked.connect(self.clear);top.addWidget(clear);layout.addLayout(top)
        self.list=DragList();self.list.setMinimumHeight(120);layout.addWidget(self.list)
        row=QHBoxLayout();remove=QPushButton('Let go');remove.clicked.connect(self.remove_selected);close=QPushButton('Tuck away');close.clicked.connect(self.hide);row.addWidget(remove);row.addWidget(close);layout.addLayout(row)
        note=QLabel('Drag files out to share. Originals stay where they are.');note.setWordWrap(True);layout.addWidget(note)
        self.timeout=QTimer(self);self.timeout.setSingleShot(True);self.timeout.timeout.connect(self.hide)
    def add_files(self,paths):
        for value in paths:
            path=Path(value)
            if path.exists() and str(path.absolute()) not in self.paths: self.paths.append(str(path.absolute()))
        self.refresh();self.show_near();self.timeout.start(12000)
    def refresh(self):
        self.list.clear()
        for path in self.paths:
            item=QListWidgetItem(Path(path).name);item.setData(Qt.UserRole,path);item.setToolTip(path);self.list.addItem(item)
        self.count_changed.emit(len(self.paths))
        if not self.paths: self.hide()
    def remove_selected(self):
        for item in self.list.selectedItems(): self.paths.remove(item.data(Qt.UserRole))
        self.refresh()
    def clear(self): self.paths.clear();self.refresh()
    def enterEvent(self,event): self.timeout.stop()
    def leaveEvent(self,event): self.timeout.start(2500)
    def reveal(self):
        if self.paths: self.show_near();self.timeout.start(8000)

class Speech(PetSurface):
    snoozed=Signal(str);chat_sent=Signal(str)
    def __init__(self,pet):
        super().__init__(pet);self.setFixedWidth(320);self.reminder=None;self.layout=QVBoxLayout(self);self.layout.setContentsMargins(25,35,25,24)
        self.message=QLabel();self.message.setWordWrap(True);self.message.setAlignment(Qt.AlignCenter);self.message.setStyleSheet('font-size:16px;font-weight:600;color:#40312b;');self.layout.addWidget(self.message)
        self.entry=QLineEdit();self.entry.setPlaceholderText('Tell your little friend…');self.entry.returnPressed.connect(self.send);self.layout.addWidget(self.entry)
        self.buttons=QHBoxLayout();self.send_button=QPushButton('Say hello');self.send_button.clicked.connect(self.send);self.snooze=QPushButton('10 min later');self.snooze.clicked.connect(self.do_snooze);self.dismiss=QPushButton('Got it ♡');self.dismiss.clicked.connect(self.hide)
        for b in (self.send_button,self.snooze,self.dismiss): self.buttons.addWidget(b)
        self.layout.addLayout(self.buttons);self.timer=QTimer(self);self.timer.setSingleShot(True);self.timer.timeout.connect(self.hide)
    def say(self,text,reminder=None,chat=False):
        self.reminder=reminder;self.message.setText(text);self.entry.setVisible(chat);self.send_button.setVisible(chat);self.snooze.setVisible(reminder is not None);self.show_near()
        if chat: self.timer.stop();self.entry.setFocus()
        else: self.timer.start(10000 if reminder else 6000)
    def send(self):
        text=self.entry.text().strip()
        if text: self.entry.clear();self.chat_sent.emit(text)
    def do_snooze(self):
        if self.reminder: self.snoozed.emit(self.reminder);self.hide()
    def contextMenuEvent(self,event):
        if self.reminder:
            menu=QMenu(self);menu.addAction('Snooze 10 min',self.do_snooze);menu.exec(event.globalPos())

class QuickActions(QWidget):
    def __init__(self,pet,actions):
        super().__init__(None,Qt.Tool|Qt.FramelessWindowHint|Qt.WindowStaysOnTopHint);self.pet=pet;self.setAttribute(Qt.WA_TranslucentBackground);self.setAttribute(Qt.WA_ShowWithoutActivating);self.resize(390,150)
        self.setStyleSheet('QPushButton{color:#40312b;background:#fff4e6;border:2px solid #b991a2;border-radius:22px;padding:7px 12px;font-weight:600;} QPushButton:hover{background:#e7d7f2;}')
        positions=[(18,85),(48,30),(146,5),(247,30),(276,85)]
        for (name,callback),(x,y) in zip(actions,positions):
            button=QPushButton(name,self);button.setGeometry(x,y,100,44);button.clicked.connect(lambda checked=False,fn=callback:self.activate(fn))
        self.timer=QTimer(self);self.timer.setSingleShot(True);self.timer.timeout.connect(self.hide)
    def activate(self,fn): self.hide();fn()
    def reveal(self):
        screen=self.pet.screen().availableGeometry();self.move(max(screen.left()+5,min(screen.right()-self.width()-5,self.pet.x()+self.pet.width()//2-self.width()//2)),max(screen.top()+5,self.pet.y()-self.height()+75));self.show();self.raise_();self.timer.start(10000)
    def enterEvent(self,event): self.timer.stop()
    def leaveEvent(self,event): self.timer.start(1800)
