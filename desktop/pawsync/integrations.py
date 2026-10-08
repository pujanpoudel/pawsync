from __future__ import annotations
import hmac, json, secrets, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from collections import deque
from PySide6.QtCore import QObject, Signal

class Loopback(QObject):
    status=Signal(str);error=Signal(str)
    def __init__(self,vault): super().__init__();self.vault=vault;self.server=None;self.lock=threading.Lock();self.hits=deque();self.slots=threading.BoundedSemaphore(8)
    def regenerate(self):
        token=secrets.token_urlsafe(32);self.vault.put('local-hook',token)
        if self.server: self.stop();self.start()
        return token
    def start(self):
        if self.server: return None
        token=self.vault.get('local-hook');created=None
        if not token: created=self.regenerate();token=created
        outer=self
        class Handler(BaseHTTPRequestHandler):
            def log_message(self,*args): pass  # Never log bearer headers or user payloads.
            def setup(self): super().setup();self.connection.settimeout(2)
            def do_POST(self):
                if not outer.slots.acquire(False): self.respond(429);return
                try:
                    if self.path not in ('/','/hook'): self.respond(404);return
                    if not hmac.compare_digest(self.headers.get('Authorization',''),'Bearer '+token): self.respond(401);return
                    with outer.lock:
                        now=time.monotonic()
                        while outer.hits and now-outer.hits[0]>1: outer.hits.popleft()
                        if len(outer.hits)>=5: self.respond(429);return
                        outer.hits.append(now)
                    try: length=int(self.headers.get('Content-Length','0'))
                    except ValueError: self.respond(400);return
                    if not 0<length<=8192: self.respond(413);return
                    try: payload=json.loads(self.rfile.read(length));status=payload.get('status')
                    except (ValueError,AttributeError): self.respond(400);return
                    if status not in ('build_success','build_failed','typing','click','celebrate','wave'): self.respond(422);return
                    outer.status.emit(status);self.respond(200)
                except (TimeoutError,OSError): pass
                finally: outer.slots.release()
            def respond(self,code):
                raw=json.dumps({'ok':code==200}).encode();self.send_response(code);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(raw)));self.send_header('Connection','close');self.end_headers();self.wfile.write(raw)
        try:
            self.server=ThreadingHTTPServer(('127.0.0.1',9876),Handler);self.server.daemon_threads=True;threading.Thread(target=self.server.serve_forever,daemon=True).start();return created
        except OSError: raise ValueError('Port 9876 is already in use. Stop the other listener and try again.') from None
    def stop(self):
        if self.server: self.server.shutdown();self.server.server_close();self.server=None

class Music(QObject):
    active=Signal(bool);beat=Signal();error=Signal(str)
    def __init__(self): super().__init__();self.running=False;self.enabled=False;self.paused=False;self.thread=None
    def start(self):
        self.enabled=True
        if self.running or self.paused: return
        self.running=True;self.thread=threading.Thread(target=self.run,daemon=True);self.thread.start()
    def run(self):
        listening=False;last_sound=0.;last_beat=0.;baseline=.0001
        try:
            import soundcard as sc
            import numpy as np
            speaker=sc.default_speaker();device=sc.get_microphone(id=speaker.id,include_loopback=True)
            if not device.isloopback: raise RuntimeError('Loopback unavailable')
            with device.recorder(samplerate=16000,channels=2,blocksize=2048) as recorder:
                while self.running:
                    data=recorder.record(numframes=2048);energy=float(np.mean(data*data));del data
                    now=time.monotonic()
                    if energy>.00003:
                        last_sound=now
                        if not listening: self.active.emit(True);listening=True
                        if energy>baseline*1.45 and now-last_beat>.25: self.beat.emit();last_beat=now
                    elif listening and now-last_sound>2.5: self.active.emit(False);listening=False
                    baseline=.85*baseline+.15*energy
        except Exception: self.error.emit('System audio is unavailable. Windows needs WASAPI loopback; Linux needs a PulseAudio/PipeWire monitor source. No audio was recorded or saved.')
        finally: self.running=False;self.active.emit(False)
    def stop(self):
        self.enabled=False;self.running=False
        if self.thread: self.thread.join(timeout=.5)
    def pause(self,value):
        enabled=self.enabled;self.paused=value
        if value: self.stop();self.enabled=enabled
        elif enabled: self.start()
