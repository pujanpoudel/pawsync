#!/usr/bin/env python3
"""Build on the target OS: Windows EXE folder or Linux deb/tar. Never cross-compile Qt."""
from __future__ import annotations
import argparse,json,os,shutil,subprocess,sys,tarfile,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];DESKTOP=ROOT/'desktop';VERSION='0.3.0'
def run(*args,**kwargs):subprocess.run(list(map(str,args)),check=True,**kwargs)
def build():
    dist=DESKTOP/'dist';work=DESKTOP/'build';dist.mkdir(exist_ok=True)
    sep=';' if sys.platform=='win32' else ':'
    # Only live runtime art is included, not reference sheets or development resources.
    staging=work/'resources';shutil.rmtree(staging,ignore_errors=True);staging.mkdir(parents=True)
    for folder in ('OpenPets','Pets','FileInteractions','Library'):
        shutil.copytree(ROOT/'macos/Resources'/folder,staging/folder,ignore=shutil.ignore_patterns('*.zip','*.psd','*.xcf'))
    for file in ('Config.json','AppIcon.icns'):shutil.copy2(ROOT/'macos/Resources'/file,staging/file)
    # Release callers explicitly supply a signed-license config; never invent live credentials.
    if os.environ.get('PAWSYNC_RELEASE_CONFIG'):shutil.copy2(os.environ['PAWSYNC_RELEASE_CONFIG'],staging/'Config.json')
    args=[sys.executable,'-m','PyInstaller','--noconfirm','--clean','--name','PawSync','--onedir','--windowed','--paths',str(DESKTOP),'--distpath',str(dist),'--workpath',str(work/'pyinstaller'),'--specpath',str(work),'--add-data',str(DESKTOP/'assets')+sep+'assets','--add-data',str(staging)+sep+'resources','--collect-submodules','keyring.backends','--collect-data','keyring','--collect-all','soundcard','--hidden-import','numpy','--hidden-import','PySide6.QtDBus']
    if sys.platform.startswith('linux'):args+=['--hidden-import','Xlib.ext.record','--hidden-import','secretstorage','--hidden-import','jeepney']
    if sys.platform=='win32':args+=['--hidden-import','win32ctypes.core.ctypes','--icon',str(DESKTOP/'assets/pawsync.ico')]
    run(*args,str(DESKTOP/'run.py'))
    target=dist/'PawSync';licenses=target/'LICENSES';licenses.mkdir(exist_ok=True)
    shutil.copy2(ROOT/'macos/Resources/OpenPets/LICENSE',licenses/'OpenPets-MIT.txt')
    import importlib.metadata as metadata
    manifest=[]
    for package in ('PySide6','shiboken6','Pillow','pillow-heif','httpx','keyring','cryptography','numpy','soundcard','psutil','python-xlib'):
        try:
            d=metadata.distribution(package);manifest.append({'name':package,'version':d.version,'license':d.metadata.get('License-Expression') or d.metadata.get('License','See package license')})
            for file in d.files or []:
                if '.dist-info/' in str(file) and any(v in str(file).lower() for v in ('license','copying','notice')) and Path(d.locate_file(file)).is_file():
                    destination=licenses/package/Path(str(file).split('.dist-info/',1)[1]);destination.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(d.locate_file(file),destination)
        except metadata.PackageNotFoundError:pass
    (licenses/'dependencies.json').write_text(json.dumps(manifest,indent=2));shutil.copy2(DESKTOP/'packaging/NOTICE.md',licenses/'NOTICE.md')
    if sys.platform.startswith('linux'):
        archive=dist/f'PawSync-{VERSION}-linux-x86_64.tar.gz'
        with tarfile.open(archive,'w:gz') as tar:tar.add(target,arcname='PawSync')
        if shutil.which('dpkg-deb'):deb(target,dist)
    elif sys.platform=='win32':
        shutil.make_archive(str(dist/f'PawSync-{VERSION}-windows-x86_64'),'zip',dist,'PawSync')
    print('Built',target)
def deb(target,dist):
    with tempfile.TemporaryDirectory() as temporary:
        root=Path(temporary);shutil.copytree(target,root/'opt/pawsync');helper=root/'usr/lib/pawsync';helper.mkdir(parents=True);shutil.copy2(DESKTOP/'packaging/linux/pawsync-input-helper',helper/'pawsync-input-helper');(helper/'pawsync-input-helper').chmod(0o755)
        policy=root/'usr/share/polkit-1/actions';policy.mkdir(parents=True);shutil.copy2(DESKTOP/'packaging/linux/com.pawsync.input.policy',policy/'com.pawsync.input.policy')
        bin=root/'usr/bin';bin.mkdir(parents=True);(bin/'pawsync').write_text('#!/bin/sh\nexec /opt/pawsync/PawSync "$@"\n');(bin/'pawsync').chmod(0o755)
        apps=root/'usr/share/applications';apps.mkdir(parents=True);shutil.copy2(DESKTOP/'packaging/linux/pawsync.desktop',apps/'pawsync.desktop')
        icons=root/'usr/share/icons/hicolor/256x256/apps';icons.mkdir(parents=True);shutil.copy2(DESKTOP/'assets/pawsync.png',icons/'pawsync.png')
        control=root/'DEBIAN';control.mkdir();(control/'control').write_text(f'Package: pawsync\nVersion: {VERSION}\nArchitecture: amd64\nMaintainer: PawSync <support@pawsync.app>\nSection: utils\nPriority: optional\nDepends: libc6 (>= 2.35), libstdc++6, libglib2.0-0, libgl1, libegl1, libxkbcommon0, libxkbcommon-x11-0, libxcb-cursor0, libxcb-icccm4, libxcb-image0, libxcb-keysyms1, libxcb-render-util0, libxcb-shape0, libxcb-xinerama0, libxcb-randr0, libxcb-xfixes0, libxcb-sync1, libxcb-util1, libxcb-xkb1, libdbus-1-3, libfontconfig1, libpulse0, python3, policykit-1\nDescription: PawSync desktop companion\n Shared pets, reactions, reminders and accessories for Windows and Linux.\n')
        run('dpkg-deb','--root-owner-group','--build',root,dist/f'PawSync-{VERSION}-linux-amd64.deb')
if __name__=='__main__':build()
