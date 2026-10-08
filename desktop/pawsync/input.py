"""Binary triggers only. Never dereference a Windows keyboard packet or decode X key detail."""
from __future__ import annotations
import os, sys, threading
from pathlib import Path
from PySide6.QtCore import QObject, Signal, QProcess

class InputMonitor(QObject):
    typing=Signal(); click=Signal(); status_changed=Signal(str)
    def __init__(self):
        super().__init__(); self.running=False; self.status='Reactions inside PawSync are available.'; self.thread=None
        self.context=None; self.display=None; self.process=None; self.thread_id=None;self.stop_event=threading.Event()
    def start(self):
        if self.running: return
        self.stop_event.clear()
        if sys.platform=='win32': self.thread=threading.Thread(target=self._windows,daemon=True)
        elif sys.platform.startswith('linux') and os.environ.get('XDG_SESSION_TYPE')!='wayland': self.thread=threading.Thread(target=self._x11,daemon=True)
        else:
            self._status('Wayland needs the optional system input helper for typing in other apps.' if sys.platform.startswith('linux') else 'Qt preview: only input inside PawSync is monitored.')
            return
        self.thread.start()
    def _status(self,message): self.status=message; self.status_changed.emit(message)
    def _x11(self):
        try:
            from Xlib import display
            from Xlib.ext import record
            control=display.Display(); stream=display.Display()
            if not control.has_extension('RECORD'): raise RuntimeError('XRecord unavailable')
            context=control.record_create_context(0,[record.AllClients],[dict(core_requests=(0,0),core_replies=(0,0),ext_requests=(0,0,0,0),ext_replies=(0,0,0,0),delivered_events=(0,0),device_events=(2,4),errors=(0,0),client_started=False,client_died=False)])
            control.sync()  # CreateContext must reach the server before the second connection enables it.
            self.display=control; self.context=context; self.running=True; self._status('Global typing and clicks are active (X11).')
            def binary(reply):
                if reply.category!=record.FromServer or reply.client_swapped: return
                # X event blocks are 32 bytes. Byte zero is the event TYPE;
                # byte one contains the key/button detail and is never read.
                for offset in range(0,len(reply.data),32):
                    kind=reply.data[offset]&0x7f
                    if kind==2: self.typing.emit()
                    elif kind==4: self.click.emit()
            stream.record_enable_context(context,binary)
            stream.close()
        except Exception as error:
            self._status('Global input is unavailable ('+type(error).__name__+'). Enable the optional input helper in Privacy.')
        finally:
            self.running=False
            if self.display:
                try: self.display.record_free_context(self.context); self.display.close()
                except Exception: pass
                self.display=None
    def _windows(self):
        import ctypes as c
        from ctypes import wintypes as w
        user=c.WinDLL('user32',use_last_error=True); kernel=c.WinDLL('kernel32',use_last_error=True)
        result=c.c_ssize_t; callback=c.WINFUNCTYPE(result,c.c_int,w.WPARAM,w.LPARAM)
        user.SetWindowsHookExW.argtypes=[c.c_int,callback,w.HINSTANCE,w.DWORD]; user.SetWindowsHookExW.restype=w.HANDLE
        user.CallNextHookEx.argtypes=[w.HANDLE,c.c_int,w.WPARAM,w.LPARAM]; user.CallNextHookEx.restype=result
        user.UnhookWindowsHookEx.argtypes=[w.HANDLE]; user.GetMessageW.argtypes=[c.POINTER(w.MSG),w.HWND,w.UINT,w.UINT]
        kernel.GetCurrentThreadId.restype=w.DWORD; kernel.GetModuleHandleW.argtypes=[w.LPCWSTR]; kernel.GetModuleHandleW.restype=w.HMODULE
        hooks=[]
        @callback
        def keyboard(code,message,packet):
            if code>=0 and message in (0x0100,0x0104): self.typing.emit()
            return user.CallNextHookEx(None,code,message,packet)
        @callback
        def mouse(code,message,packet):
            if code>=0 and message in (0x0201,0x0204,0x0207,0x020b): self.click.emit()
            return user.CallNextHookEx(None,code,message,packet)
        try:
            self.thread_id=kernel.GetCurrentThreadId()
            module=kernel.GetModuleHandleW(None)
            hooks=[user.SetWindowsHookExW(13,keyboard,module,0),user.SetWindowsHookExW(14,mouse,module,0)]
            if not all(hooks): raise RuntimeError('Input hook unavailable')
            if self.stop_event.is_set():return
            self.running=True; self._status('Global typing and clicks are active (Windows).')
            message=w.MSG()
            while user.GetMessageW(c.byref(message),None,0,0)>0:
                user.TranslateMessage(c.byref(message)); user.DispatchMessageW(c.byref(message))
        except Exception: self._status('Global input could not start. Reopen PawSync and try again.')
        finally:
            for hook in hooks:
                if hook: user.UnhookWindowsHookEx(hook)
            self.running=False
    def enable_helper(self):
        if self.process: return
        executable=Path('/usr/lib/pawsync/pawsync-input-helper')
        if not executable.exists():
            self._status('Install the PawSync .deb input helper to enable Wayland reactions. The main app never runs as root.'); return
        self.stop(); process=QProcess(self); self.process=process
        process.setProgram('pkexec'); process.setArguments([str(executable)])
        def receive():
            # Helper emits only single-byte event labels, not device packets.
            for line in bytes(process.readAllStandardOutput()).splitlines():
                if line==b'K': self.typing.emit()
                elif line==b'M': self.click.emit()
                elif line==b'READY': self.running=True; self._status('Input helper active. Only event occurrences are processed.')
        process.readyReadStandardOutput.connect(receive)
        process.finished.connect(lambda *_:self._helper_stopped())
        process.start()
    def _helper_stopped(self): self.process=None; self.running=False; self._status('Input helper stopped. Reactions inside PawSync still work.')
    def stop(self):
        self.stop_event.set()
        if self.process: self.process.terminate(); self.process.waitForFinished(1000); self.process=None
        if self.display and self.context:
            try: self.display.record_disable_context(self.context); self.display.flush()
            except Exception: pass
        if self.thread_id and sys.platform=='win32':
            import ctypes
            ctypes.windll.user32.PostThreadMessageW(self.thread_id,0x0012,0,0)
        if self.thread: self.thread.join(timeout=1)
        self.running=False
