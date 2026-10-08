import base64,io,json,time
from pathlib import Path
import httpx,pytest
from PIL import Image
from pawsync.photo import validate_photo,transparent_part,prepare_sheet
from pawsync.services import Backend,Vault
from pawsync.tools import Tools

def test_photo_validation_strips_metadata_and_rejects_bad_files(tmp_path):
    image=Image.new('RGB',(256,256),'white');file=tmp_path/'pet.jpg';exif=Image.Exif();exif[0x010e]='private description';image.save(file,exif=exif)
    raw=validate_photo(file)
    with Image.open(io.BytesIO(raw)) as clean:assert len(clean.getexif())==0
    bad=tmp_path/'bad.png';bad.write_text('not a png')
    with pytest.raises(ValueError):validate_photo(bad)

def test_transparent_border_does_not_erase_black_fur():
    image=Image.new('RGBA',(60,60));pixels=image.load()
    for y in range(15,45):
        for x in range(15,45):pixels[x,y]=(0,0,0,255)
    part=transparent_part(image);assert part.size==(30,30);assert part.getpixel((0,0))==(0,0,0,255)

def test_flat_matte_keeps_internal_white_eyes():
    image=Image.new('RGBA',(60,60),(255,0,255,255));pixels=image.load()
    for y in range(15,45):
        for x in range(15,45):pixels[x,y]=(120,80,60,255)
    pixels[25,25]=(255,255,255,255);part=transparent_part(image);assert part.getpixel((10,10))==(255,255,255,255)

def test_backend_retries_same_credit_request_id(monkeypatch):
    class Memory:
        def get(self,k):return 'signed-session'
        def put(self,*args):pass
    backend=Backend.__new__(Backend);backend.vault=Memory();backend.base='https://pawsync.test';backend.licensed=True;calls=[]
    original=httpx.Client
    def handle(request):
        calls.append(request.headers['Idempotency-Key']);assert request.headers['Authorization']=='Bearer signed-session'
        return httpx.Response(503 if len(calls)<3 else 200,json={'parts':{}},request=request)
    monkeypatch.setattr(httpx,'Client',lambda **kwargs:original(transport=httpx.MockTransport(handle),**kwargs));monkeypatch.setattr('pawsync.services.time.sleep',lambda _:None)
    assert backend.generate(b'photo','request-123')=={'parts':{}};assert calls==['request-123']*3

def test_revocation_clears_saved_session(monkeypatch):
    class Memory:
        value='license'
        def get(self,k):return self.value
        def put(self,k,v):self.value=v
    b=Backend.__new__(Backend);b.vault=Memory();b.base='https://pawsync.test';b.licensed=True;b.owned=['accessory.hat'];original=httpx.Client
    monkeypatch.setattr(httpx,'Client',lambda **kwargs:original(transport=httpx.MockTransport(lambda r:httpx.Response(401,request=r)),**kwargs))
    with pytest.raises(ValueError):b.request('/v1/wallet')
    assert not b.licensed and not b.owned and b.vault.value==''

def test_plaintext_vault_rejected(monkeypatch):
    class Unsafe:pass
    monkeypatch.setattr('pawsync.services.keyring.get_keyring',lambda:Unsafe())
    with pytest.raises(ValueError,match='secure credential'):Vault().get('license')

def test_countdown_persists_and_defers_focus_alert(state,content):
    tools=Tools(state,content);tools.start_timer(1,'Tea');tools.countdown['deadline']=time.time()-1;tools.tick(focus=True)
    assert tools.countdown['phase']=='expired' and tools.countdown['queued'];tools.tick(focus=False);assert 'queued' not in tools.countdown;assert state.progress['counters']['timer']==1
    tools.start_timer(15,'Work');tools.pause_timer();assert tools.countdown['phase']=='paused';remaining=tools.countdown['remaining'];tools.add_five();assert tools.countdown['remaining']==remaining+300
