"""Inference provider boundary. Demo mode returns placeholders, never pretends to stylize."""
import base64
import io
import json
import pathlib
import uuid
import warnings

import httpx
from PIL import Image, ImageOps
from pillow_heif import register_heif_opener

from .wallet import WalletError

register_heif_opener()
Image.MAX_IMAGE_PIXELS = 40_000_000
PARTS = {"body", "head", "left_paw", "right_paw", "tail"}
MAX_PHOTO = 15 * 1024 * 1024
MAX_PACKAGE = 10 * 1024 * 1024


def validate_photo(data):
    if not data or len(data) > MAX_PHOTO:
        raise WalletError("Photo must be smaller than 15 MB", 422)
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            image = Image.open(io.BytesIO(data))
            if image.format not in {"JPEG", "PNG", "HEIF", "HEIC"}:
                raise ValueError()
            width, height = image.size
            if min(width, height) < 64 or max(width, height) > 8192 or width * height > 40_000_000:
                raise ValueError()
            image.verify()
            image = ImageOps.exif_transpose(Image.open(io.BytesIO(data)))
            image.thumbnail((2048, 2048))
            output = io.BytesIO()
            image.convert("RGBA").save(output, "PNG")
            return output.getvalue()  # EXIF metadata is intentionally stripped.
    except (OSError, ValueError, Image.DecompressionBombError, Image.DecompressionBombWarning):
        raise WalletError("Use a valid JPEG, PNG or HEIC photo (64–8192 px, at most 40 MP)", 422) from None


def validate_package(package, pet_id):
    if not isinstance(package, dict) or set(package.get("parts", {})) != PARTS:
        raise WalletError("Inference returned an incomplete rig", 502)
    if str(uuid.UUID(pet_id)) != pet_id:
        raise WalletError("Invalid pet identifier", 502)
    result = {"id": pet_id, "name": "My companion", "parts": {}}
    for name in PARTS:
        part = package["parts"][name]
        anchor, offset = part.get("anchor"), part.get("parent_offset", [0, 0])
        if not isinstance(anchor, list) or len(anchor) != 2 or not all(isinstance(x, (int, float)) and 0 <= x <= 1 for x in anchor):
            raise WalletError("Inference returned invalid anchors", 502)
        if not isinstance(offset, list) or len(offset) != 2 or not all(isinstance(x, (int, float)) and abs(x) < 1024 for x in offset):
            raise WalletError("Inference returned invalid joint offsets", 502)
        try:
            encoded = part["png_base64"]
            if len(encoded) > 2_800_000:
                raise ValueError()
            png = base64.b64decode(encoded, validate=True)
            image = Image.open(io.BytesIO(png))
            if image.format != "PNG" or image.mode not in {"RGBA", "LA"} or max(image.size) > 512 or min(image.size) < 1:
                raise ValueError()
            image.verify()
        except (KeyError, ValueError, TypeError, OSError):
            raise WalletError("Inference returned an invalid transparent PNG", 502) from None
        result["parts"][name] = {"file": f"{name}.png", "anchor": anchor, "parent_offset": offset, "png_base64": encoded}
    if len(json.dumps(result)) > MAX_PACKAGE:
        raise WalletError("Inference package is too large", 502)
    return result


async def vectorize(settings, photo, pet_id):
    if settings.pipeline_mode == "demo":
        directory = pathlib.Path(__file__).resolve().parents[2] / "macos/Resources/Pets/pixel-cat"
        package = json.loads((directory / "atlas.json").read_text())
        for name, part in package["parts"].items():
            part["png_base64"] = base64.b64encode((directory / f"{name}.png").read_bytes()).decode()
        result = validate_package(package, pet_id)
        result["name"] = "Demo companion (placeholder)"
        return result
    if not settings.pipeline_url:
        raise WalletError("Photo generation is not configured yet. No credit has been spent.", 503)
    # The provider is an internal trusted model worker, not a URL supplied by the user.
    async with httpx.AsyncClient(timeout=24, follow_redirects=False) as client:
        async with client.stream("POST", settings.pipeline_url.rstrip("/") + "/vectorize",
                                 headers={"Authorization": f"Bearer {settings.pipeline_token}"},
                                 files={"photo": ("pet.png", photo, "image/png")},
                                 data={"pet_id": pet_id, "alpha_matting": "true"}) as response:
            if response.status_code != 200:
                raise WalletError("The image pipeline failed. Your credit will be returned.", 502)
            raw = bytearray()
            async for chunk in response.aiter_bytes():
                raw.extend(chunk)
                if len(raw) > MAX_PACKAGE:
                    raise WalletError("Inference package is too large", 502)
    try:
        package = json.loads(raw)
    except ValueError:
        raise WalletError("Invalid inference response", 502) from None
    return validate_package(package, pet_id)
