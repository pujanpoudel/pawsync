#!/usr/bin/env python3
"""Create adversarial archive fixtures, then exercise the native installer."""
import io
import json
import pathlib
import struct
import subprocess
import tempfile
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]

def archive(entries, compression=zipfile.ZIP_STORED):
    buffer=io.BytesIO()
    with zipfile.ZipFile(buffer,"w",compression=compression) as output:
        for name,data in entries:
            output.writestr(name,data)
    return buffer.getvalue()

with tempfile.TemporaryDirectory(prefix="PawSync-import-tests-") as directory:
    fixture=pathlib.Path(directory)
    files=[(name,(ROOT/"macos/Resources/OpenPets/default"/name).read_bytes()) for name in ("pet.json","spritesheet.webp")]
    valid=archive(files)
    (fixture/"valid-store.zip").write_bytes(valid)
    (fixture/"valid-deflate.zip").write_bytes(archive(files,zipfile.ZIP_DEFLATED))
    (fixture/"valid-folder.zip").write_bytes(archive([("default/"+name,data) for name,data in files]))
    (fixture/"bad-traversal.zip").write_bytes(archive([("../pet.json",b"{}")]))
    (fixture/"bad-absolute.zip").write_bytes(archive([("/tmp/pet.json",b"{}")]))
    (fixture/"bad-case.zip").write_bytes(archive([("pet.json",b"{}"),("PET.JSON",b"{}")]))
    (fixture/"bad-truncated.zip").write_bytes(valid[:-6])
    (fixture/"bad-extra.zip").write_bytes(archive(files+[("executable.sh",b"echo nope")]))
    info=zipfile.ZipInfo("pet.json");info.create_system=3;info.external_attr=(0o120777<<16)
    (fixture/"bad-link.zip").write_bytes(archive([(info,b"/etc/passwd")]))
    central=valid.index(b"PK\x01\x02")
    encrypted=bytearray(valid);struct.pack_into("<H",encrypted,6,1);struct.pack_into("<H",encrypted,central+8,1)
    (fixture/"bad-encrypted.zip").write_bytes(encrypted)
    crc=bytearray(valid);crc[central+16]^=1;(fixture/"bad-crc.zip").write_bytes(crc)
    bomb=bytearray(valid);struct.pack_into("<I",bomb,central+24,101*1024*1024)
    (fixture/"bad-size.zip").write_bytes(bomb)
    second=valid.index(b"PK\x01\x02",central+4)
    overlap=bytearray(valid);struct.pack_into("<I",overlap,second+42,0)
    (fixture/"bad-overlap.zip").write_bytes(overlap)
    nested=archive([("a/b/"+name,data) for name,data in files])
    (fixture/"bad-nested.zip").write_bytes(nested)
    metadata=json.loads(files[0][1]);metadata["id"]="../escape"
    (fixture/"bad-id.zip").write_bytes(archive([("pet.json",json.dumps(metadata).encode()),files[1]]))
    metadata=json.loads(files[0][1]);metadata["spriteVersionNumber"]=3
    (fixture/"bad-version.zip").write_bytes(archive([("pet.json",json.dumps(metadata).encode()),files[1]]))
    subprocess.run([str(ROOT/"build/PawSync.app/Contents/MacOS/PawSync"),"--check-imports",str(fixture)],check=True)
