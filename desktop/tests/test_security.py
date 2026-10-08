import importlib.util,json,urllib.request,urllib.error,time
from pathlib import Path
import pytest
from pawsync.integrations import Loopback
from pawsync.services import Vault
from pawsync.assets import checked_path

class MemoryVault:
    def __init__(self):self.values={}
    def get(self,k):return self.values.get(k)
    def put(self,k,v):self.values[k]=v

def test_loopback_rejects_unauthenticated_and_limits(qtbot):
    vault=MemoryVault();hook=Loopback(vault);token=hook.start();assert hook.server.server_address==('127.0.0.1',9876)
    def request(token):
        req=urllib.request.Request('http://127.0.0.1:9876/hook',data=b'{"status":"build_success"}',headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
        try:return urllib.request.urlopen(req,timeout=3).status
        except urllib.error.HTTPError as e:return e.code
    try:
        assert request('wrong')==401
        for _ in range(5):assert request(token)==200
        assert request(token)==429
    finally:hook.stop()

def test_no_path_escape(tmp_path):
    with pytest.raises(ValueError):checked_path(tmp_path,'../escape.png')
    target=tmp_path/'inside';target.mkdir();(tmp_path/'symlink').symlink_to(target,target_is_directory=True)
    with pytest.raises(ValueError):checked_path(tmp_path,'symlink/file.png')

def test_global_listener_never_reads_key_content():
    source=(Path(__file__).parents[1]/'pawsync/input.py').read_text()
    assert 'from_address' not in source;assert 'vkCode' not in source;assert 'keyCode' not in source;assert 'reply.data[offset]&0x7f' in source
    helper=(Path(__file__).parents[1]/'packaging/linux/pawsync-input-helper').read_text();assert '@llH2xi' in helper
