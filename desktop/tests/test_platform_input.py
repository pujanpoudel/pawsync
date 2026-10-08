"""Real desktop event injection into an external client, separate from UI reactions."""
import os,sys,time
import pytest
from PySide6.QtTest import QSignalSpy
from pawsync.input import InputMonitor

@pytest.mark.skipif(not os.environ.get('PAWSYNC_TEST_GLOBAL_INPUT'),reason='Needs a real Windows/X11 desktop session')
def test_external_events_are_binary_triggers(qtbot):
    monitor=InputMonitor();keys=QSignalSpy(monitor.typing);clicks=QSignalSpy(monitor.click);monitor.start()
    try:
        qtbot.wait(1500)
        assert monitor.running,monitor.status
        if sys.platform.startswith('linux'):
            from Xlib import display,X
            from Xlib.ext import xtest
            sender=display.Display()
            # Production listener never receives or reads this test's key identity.
            xtest.fake_input(sender,X.KeyPress,38);xtest.fake_input(sender,X.KeyRelease,38);xtest.fake_input(sender,X.ButtonPress,1);xtest.fake_input(sender,X.ButtonRelease,1);sender.sync();sender.close()
        elif sys.platform=='win32':
            import ctypes
            user=ctypes.windll.user32
            user.keybd_event(0x41,0,0,0);user.keybd_event(0x41,0,2,0)
            user.mouse_event(2,0,0,0,0);user.mouse_event(4,0,0,0,0)
        else:pytest.skip('Global adapter is Windows/Linux only')
        qtbot.waitUntil(lambda:keys.count()>=1 and clicks.count()>=1,timeout=10000)
    finally:monitor.stop()
