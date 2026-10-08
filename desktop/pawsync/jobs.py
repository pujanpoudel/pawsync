from PySide6.QtCore import QObject, Signal, QRunnable, QThreadPool

class Signals(QObject):
    result=Signal(object); failed=Signal(str); done=Signal()
class Job(QRunnable):
    def __init__(self,fn): super().__init__(); self.fn=fn; self.signals=Signals()
    def run(self):
        try: self.signals.result.emit(self.fn())
        except Exception as error:
            # External errors are deliberately wrapped by services before display.
            self.signals.failed.emit(str(error) if isinstance(error,ValueError) else 'This action could not finish. Please try again.')
        finally: self.signals.done.emit()

def launch(fn,success,failure,owner=None):
    job=Job(fn);job.signals.result.connect(success);job.signals.failed.connect(failure)
    if owner is not None:
        if not hasattr(owner,'jobs'): owner.jobs=set()
        owner.jobs.add(job);job.signals.done.connect(lambda:owner.jobs.discard(job))
    QThreadPool.globalInstance().start(job); return job
