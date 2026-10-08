"""Secure credentials and the existing PawSync wallet/progress API."""
from __future__ import annotations
import base64, json, os, time, uuid
from urllib.parse import urlparse
import httpx, keyring
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from .assets import RESOURCES

class Vault:
    service='com.pawsync.desktop'
    def backend(self):
        backend=keyring.get_keyring()
        module=type(backend).__module__
        if 'chainer' in module:
            backend=next((b for b in backend.backends if any(k in type(b).__module__.lower() for k in ('windows','secretservice','kwallet','macos'))),None)
            module=type(backend).__module__ if backend else ''
        if not backend or not any(k in module.lower() for k in ('windows','secretservice','kwallet','macos')):
            raise ValueError('A secure credential store is unavailable. Enable Windows Credential Manager or Linux Secret Service/KWallet; no plaintext fallback is used.')
        return backend
    def get(self,name):
        try: return self.backend().get_password(self.service,name)
        except ValueError: raise
        except Exception: raise ValueError('Unlock your system credential store and try again.') from None
    def put(self,name,value):
        try:
            if value: self.backend().set_password(self.service,name,value)
            elif self.get(name): self.backend().delete_password(self.service,name)
        except ValueError: raise
        except Exception: raise ValueError('The system credential store could not save this secret.') from None

class Backend:
    def __init__(self,vault):
        self.vault=vault;self.config=json.loads((RESOURCES/'Config.json').read_text());self.base=self.config['apiBaseURL'].rstrip('/');self.credits=None;self.owned=[];self.licensed=self.config.get('environment')=='development'
        parsed=urlparse(self.base)
        if parsed.scheme!='https' and not (parsed.scheme=='http' and parsed.hostname in ('127.0.0.1','localhost','::1')): raise ValueError('The backend must use HTTPS.')
        if self.config.get('environment')=='development' and os.environ.get('PAWSYNC_OFFLINE_PREVIEW'): return
        try:
            token=self.vault.get('license')
            if token: self.validate_token(token);self.licensed=True
        except ValueError: pass
    def validate_token(self,token):
        try:
            def decode(v): return base64.urlsafe_b64decode(v+'='*((4-len(v)%4)%4))
            head,payload,signature=token.split('.');header=json.loads(decode(head));claims=json.loads(decode(payload))
            if header.get('alg')!='EdDSA' or claims.get('iss')!='pawsync' or claims.get('aud')!='pawsync-desktop' or claims.get('licensed') is not True or not isinstance(claims.get('sub'),str): raise ValueError()
            if claims.get('exp') is not None and claims['exp']<=time.time(): raise ValueError()
            Ed25519PublicKey.from_public_bytes(base64.b64decode(self.config['licensePublicKey'])).verify(decode(signature),(head+'.'+payload).encode())
            self.owned=claims.get('accessories',[]);return claims
        except Exception: raise ValueError('This license could not be verified.') from None
    def request(self,path,method='GET',authenticated=True,retry=False,**kwargs):
        headers=kwargs.pop('headers',{})
        if authenticated:
            token=self.vault.get('license')
            if not token: raise ValueError('Restore your purchase first.')
            headers['Authorization']='Bearer '+token
        for attempt in range(3 if retry else 1):
            try:
                with httpx.Client(timeout=30,follow_redirects=False) as client:
                    response=client.request(method,self.base+path,headers=headers,**kwargs)
                if response.status_code>=500 and retry and attempt<2: time.sleep(2**attempt);continue
                if response.status_code==401:
                    if authenticated:
                        self.licensed=False;self.owned=[]
                        self.vault.put('license','')
                    raise ValueError('Please restore your purchase again. The session may have been revoked.')
                if response.status_code==402: raise ValueError('No generation credits remain. Buy a top-up to make another pet.')
                if response.status_code==429: raise ValueError('Too many requests. Wait a moment and try again.')
                if response.status_code>=400: raise ValueError('The service could not complete this request. Please try again later.')
                if len(response.content)>40*1024*1024: raise ValueError('The service response was too large.')
                return response.json()
            except (httpx.TimeoutException,httpx.NetworkError):
                if retry and attempt<2: time.sleep(2**attempt);continue
                raise ValueError('Could not reach PawSync. Check your connection and try again; your local companion still works offline.') from None
            except (httpx.HTTPError,json.JSONDecodeError): raise ValueError('The service returned an invalid response.') from None
    def wallet(self):
        snapshot=self.request('/v1/wallet');self.credits=snapshot['credits'];self.owned=snapshot['accessories'];self.licensed=snapshot['licensed'];return snapshot
    def restore(self,email,code=None):
        if not code: return self.request('/v1/license/restore','POST',False,json={'email':email})
        result=self.request('/v1/license/restore/verify','POST',False,json={'email':email,'code':code});self.validate_token(result['token']);self.vault.put('license',result['token']);self.licensed=True;return self.wallet()
    def sync(self,progress): return self.request('/v1/library/progress','POST',json=progress)
    def generate(self,photo,request_id): return self.request('/v1/pet/vectorize','POST',retry=True,files={'photo':('pet.jpg',photo,'image/jpeg')},headers={'Idempotency-Key':request_id})
