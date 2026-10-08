"""Daemon workers deliver results through queued Qt signals, without blocking Quit."""
import threading
from PySide6.QtCore import QObject,Signal

class Signals(QObject):
    result=Signal(object);failed=Signal(str);done=Signal()
class Job:
    def __init__(self,fn):self.fn=fn;self.signals=Signals()
    def run(self):
        try:self.signals.result.emit(self.fn())
        except Exception as error:
            self.signals.failed.emit(str(error) if isinstance(error,ValueError) else 'This action could not finish. Please try again.')
        finally:self.signals.done.emit()

def launch(fn,success,failure,owner=None):
    job=Job(fn);job.signals.result.connect(success);job.signals.failed.connect(failure)
    if owner is not None:
        if not hasattr(owner,'jobs'):owner.jobs=set()
        owner.jobs.add(job);job.signals.done.connect(lambda:owner.jobs.discard(job))
    threading.Thread(target=job.run,daemon=True,name='PawSync service request').start();return job
