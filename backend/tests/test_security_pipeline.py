import base64
import hashlib
import hmac
import io
import json
import pathlib

import pytest
from PIL import Image

from pawsync.pipeline import validate_package, validate_photo
from pawsync.security import verify_paddle
from pawsync.wallet import WalletError


def test_paddle_raw_body_signature_and_replay_window():
    raw, secret, timestamp = b'{"hello":"world"}', "test-secret", "100"
    signature = hmac.new(secret.encode(), b"100:" + raw, hashlib.sha256).hexdigest()
    header = f"ts={timestamp};h1={signature}"
    verify_paddle(raw, header, secret, current_time=103)
    for body, time in [(raw + b" ", 103), (raw, 106)]:
        with pytest.raises(WalletError): verify_paddle(body, header, secret, current_time=time)
    with pytest.raises(WalletError): verify_paddle(raw, "malformed", secret, current_time=100)


def test_photo_validation_strips_metadata_and_rejects_small_images():
    output = io.BytesIO(); Image.new("RGB", (128, 128)).save(output, "JPEG")
    normalized = validate_photo(output.getvalue())
    assert Image.open(io.BytesIO(normalized)).format == "PNG"
    small = io.BytesIO(); Image.new("RGB", (12, 12)).save(small, "PNG")
    for invalid in [small.getvalue(), b"not an image"]:
        with pytest.raises(WalletError): validate_photo(invalid)


def test_rig_validation_rejects_unsafe_anchors_and_nontransparent_parts():
    directory = pathlib.Path(__file__).resolve().parents[2] / "macos/Resources/Pets/pixel-cat"
    package = json.loads((directory / "atlas.json").read_text())
    for key, part in package["parts"].items(): part["png_base64"] = base64.b64encode((directory / f"{key}.png").read_bytes()).decode()
    pet_id = "c04d0ce4-9a3c-445c-a69b-d02b5dbb8fd1"
    assert validate_package(package, pet_id)["id"] == pet_id
    package["parts"]["head"]["anchor"] = [float("nan"), 0.5]
    with pytest.raises(WalletError): validate_package(package, pet_id)
