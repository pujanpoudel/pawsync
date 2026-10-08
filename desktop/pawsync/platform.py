from __future__ import annotations
import ctypes, os, shlex, sys
from pathlib import Path
from PySide6.QtCore import QObject, Signal, QAbstractNativeEventFilter, SLOT
from PySide6.QtGui import QCursor
from PySide6.QtWidgets import QApplication


def command():
    return [sys.executable] if getattr(sys,'frozen',False) else [sys.executable,str(Path(__file__).parents[1]/'run.py')]


def login_enabled(enabled):
    args=command()+['--background']
    if sys.platform=='win32':
        import winreg, subprocess
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER,r'Software\Microsoft\Windows\CurrentVersion\Run') as key:
            if enabled: winreg.SetValueEx(key,'PawSync',0,winreg.REG_SZ,subprocess.list2cmdline(args))
            else:
                try: winreg.DeleteValue(key,'PawSync')
                except FileNotFoundError: pass
    elif sys.platform.startswith('linux'):
        file=Path(os.environ.get('XDG_CONFIG_HOME',str(Path.home()/'.config')))/'autostart/pawsync.desktop'
        if enabled:
            file.parent.mkdir(parents=True,exist_ok=True)
            quoted=' '.join('"'+a.replace('\\','\\\\').replace('"','\\"').replace('`','\\`').replace('$','\\$')+'"' for a in args)
            file.write_text('[Desktop Entry]\nType=Application\nName=PawSync\nExec='+quoted+'\nTerminal=false\nX-GNOME-Autostart-enabled=true\n')
        else: file.unlink(missing_ok=True)


def foreground_rect():
    if sys.platform=='win32':
        from ctypes import wintypes as w
        user=ctypes.windll.user32;user.GetForegroundWindow.restype=w.HWND
        user.GetWindowThreadProcessId.argtypes=[w.HWND,ctypes.POINTER(w.DWORD)];user.GetWindowRect.argtypes=[w.HWND,ctypes.POINTER(w.RECT)]
        window=user.GetForegroundWindow(); pid=w.DWORD(); user.GetWindowThreadProcessId(window,ctypes.byref(pid))
        if pid.value==os.getpid(): return None
        rect=w.RECT()
        if user.GetWindowRect(window,ctypes.byref(rect)): return (rect.left,rect.top,rect.right-rect.left,rect.bottom-rect.top)
    elif sys.platform.startswith('linux') and os.environ.get('DISPLAY'):
        try:
            from Xlib import display
            connection=display.Display(); root=connection.screen().root
            value=root.get_full_property(connection.intern_atom('_NET_ACTIVE_WINDOW'),0)
            if value and value.value[0]:
                window=connection.create_resource_object('window',int(value.value[0])); pid=window.get_full_property(connection.intern_atom('_NET_WM_PID'),0)
                if pid and pid.value[0]==os.getpid(): connection.close(); return None
                geometry=window.get_geometry(); offset=root.translate_coords(window,0,0)
                result=(offset.x,offset.y,geometry.width,geometry.height);connection.close();return result
            connection.close()
        except Exception: pass
    return None


def all_workspaces(widget):
    if not sys.platform.startswith('linux') or not os.environ.get('DISPLAY'): return
    try:
        from Xlib import display, X, Xatom, protocol
        connection=display.Display(); window=connection.create_resource_object('window',int(widget.winId()));root=connection.screen().root
        atom=connection.intern_atom('_NET_WM_DESKTOP');window.change_property(atom,Xatom.CARDINAL,32,[0xffffffff])
        message=protocol.event.ClientMessage(window=window,client_type=atom,data=(32,[0xffffffff,1,0,0,0]))
        root.send_event(message,event_mask=X.SubstructureRedirectMask|X.SubstructureNotifyMask);connection.flush();connection.close()
    except Exception: pass

class SleepMonitor(QObject,QAbstractNativeEventFilter):
    sleeping=Signal(bool)
    def __init__(self,widget):
        QObject.__init__(self);QAbstractNativeEventFilter.__init__(self); self.handle=None
        if sys.platform=='win32':
            from ctypes import wintypes as w
            class GUID(ctypes.Structure): _fields_=[('Data1',w.DWORD),('Data2',w.WORD),('Data3',w.WORD),('Data4',ctypes.c_ubyte*8)]
            guid=GUID(0x6fe69556,0x704a,0x47a0,(ctypes.c_ubyte*8)(0x8f,0x24,0xc2,0x8d,0x93,0x6f,0xda,0x47))
            fn=ctypes.windll.user32.RegisterPowerSettingNotification; fn.argtypes=[w.HANDLE,ctypes.POINTER(GUID),w.DWORD];fn.restype=w.HANDLE
            self.handle=fn(int(widget.winId()),ctypes.byref(guid),0);QApplication.instance().installNativeEventFilter(self)
        elif sys.platform.startswith('linux'):
            from PySide6.QtDBus import QDBusConnection
            bus=QDBusConnection.sessionBus()
            bus.connect('org.freedesktop.ScreenSaver','/org/freedesktop/ScreenSaver','org.freedesktop.ScreenSaver','ActiveChanged',self,SLOT('screenState(bool)'))
            bus.connect('org.gnome.ScreenSaver','/org/gnome/ScreenSaver','org.gnome.ScreenSaver','ActiveChanged',self,SLOT('screenState(bool)'))
            QDBusConnection.systemBus().connect('org.freedesktop.login1','/org/freedesktop/login1','org.freedesktop.login1.Manager','PrepareForSleep',self,SLOT('screenState(bool)'))
    from PySide6.QtCore import Slot
    @Slot(bool)
    def screenState(self,value): self.sleeping.emit(value)
    def nativeEventFilter(self,event_type,message):
        if sys.platform=='win32':
            from ctypes import wintypes as w
            msg=w.MSG.from_address(int(message))
            if msg.message==0x0218:
                if msg.wParam in (4,): self.sleeping.emit(True)
                elif msg.wParam in (7,18): self.sleeping.emit(False)
                elif msg.wParam==0x8013 and msg.lParam:
                    # POWERBROADCAST_SETTING: GUID (16), length (4), DWORD state.
                    if ctypes.c_uint32.from_address(msg.lParam+16).value==4: self.sleeping.emit(ctypes.c_uint32.from_address(msg.lParam+20).value==0)
        return False,0
    def stop(self):
        if self.handle:
            from ctypes import wintypes as w
            fn=ctypes.windll.user32.UnregisterPowerSettingNotification;fn.argtypes=[w.HANDLE];fn.restype=w.BOOL;fn(self.handle);QApplication.instance().removeNativeEventFilter(self)
