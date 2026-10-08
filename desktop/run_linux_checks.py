"""Start an actual X11 session without relying on SIGUSR1 across emulation."""
import os,subprocess,sys,time
from pathlib import Path
os.environ.update(DISPLAY=':88',QT_QPA_PLATFORM='xcb',PAWSYNC_OFFLINE_PREVIEW='1',PAWSYNC_TEST_GLOBAL_INPUT='1')
xvfb=subprocess.Popen(['Xvfb',':88','-screen','0','1280x1024x24','-nolisten','tcp'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
wm=None
try:
    from Xlib import display
    for _ in range(100):
        try:d=display.Display();d.close();break
        except Exception:time.sleep(.1)
    else:raise RuntimeError('Xvfb did not become ready')
    wm=subprocess.Popen(['openbox'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    subprocess.run([sys.executable,'-m','pytest','desktop/tests','-q'],check=True)
    subprocess.run([sys.executable,'desktop/test_linux_runtime.py'],check=True)
    if '--source-only' not in sys.argv:subprocess.run(['desktop/dist/PawSync/PawSync','--smoke-test'],check=True,timeout=30)
finally:
    if wm:wm.terminate();wm.wait(timeout=5)
    xvfb.terminate();xvfb.wait(timeout=5)
