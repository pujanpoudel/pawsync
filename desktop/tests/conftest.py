import os,sys
from pathlib import Path
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')
os.environ['PAWSYNC_OFFLINE_PREVIEW']='1'
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import json,pytest
from pawsync.assets import ASSETS,Catalog
from pawsync.state import State
@pytest.fixture
def content():return json.loads((ASSETS/'content.json').read_text())
@pytest.fixture
def state(content,tmp_path,qapp):return State(content,tmp_path)
@pytest.fixture
def catalog(state):return Catalog(state.root)
