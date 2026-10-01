"""Private GPU worker. Model weights are deployment inputs, not fake runtime outputs."""
import asyncio
import hmac
import io
import logging
import os
import pathlib
import uuid
from contextlib import asynccontextmanager

from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from PIL import Image, ImageChops, ImageFilter, ImageOps

from rigging import build_atlas

log = logging.getLogger("pawsync.inference")


class PhotoPipeline:
    def __init__(self):
        import onnxruntime as ort
        import torch
        from diffusers import ControlNetModel, StableDiffusionControlNetImg2ImgPipeline
        from rembg import new_session

        model_path = os.environ.get("PART_SEGMENTATION_MODEL", "")
        if not model_path or not pathlib.Path(model_path).is_file():
            raise RuntimeError("Supply a trained six-class pet-part ONNX model via PART_SEGMENTATION_MODEL")
        self.segmenter = ort.InferenceSession(model_path, providers=["CUDAExecutionProvider", "CPUExecutionProvider"])
        self.background = new_session(os.environ.get("BACKGROUND_MODEL", "birefnet-general"))
        device = "cuda" if torch.cuda.is_available() else "cpu"
        if device != "cuda" and os.environ.get("ALLOW_CPU_INFERENCE") != "1":
            raise RuntimeError("A CUDA GPU is required to meet the client’s request timeout")
        dtype = torch.float16 if device == "cuda" else torch.float32
        controlnet = ControlNetModel.from_pretrained(os.environ.get("CONTROLNET_MODEL", "lllyasviel/control_v11p_sd15_lineart"), torch_dtype=dtype)
        self.stylizer = StableDiffusionControlNetImg2ImgPipeline.from_pretrained(
            os.environ.get("CARTOON_MODEL", "stable-diffusion-v1-5/stable-diffusion-v1-5"),
            controlnet=controlnet, torch_dtype=dtype).to(device)
        self.stylizer.set_progress_bar_config(disable=True)

    def generate(self, raw, pet_id):
        import numpy as np
        from rembg import remove

        with Image.open(io.BytesIO(raw)) as source:
            if source.width * source.height > 40_000_000: raise ValueError("Photo is too large")
            source = ImageOps.exif_transpose(source).convert("RGBA")
        masked = remove(source, session=self.background, alpha_matting=True)
        box = masked.getchannel("A").getbbox()
        if box is None: raise ValueError("No pet detected")
        foreground = masked.crop(box)
        foreground.thumbnail((448, 448))
        canvas = Image.new("RGBA", (512, 512))
        canvas.alpha_composite(foreground, ((512-foreground.width)//2, (512-foreground.height)//2))
        white = Image.new("RGBA", canvas.size, "white"); white.alpha_composite(canvas)
        reference = white.convert("RGB")
        edges = ImageOps.invert(reference.convert("L").filter(ImageFilter.FIND_EDGES)).convert("RGB")
        cartoon = self.stylizer(prompt=os.environ.get("CARTOON_PROMPT", "clean friendly 2D cartoon pet, flat colors, soft outline, preserve the reference pet's fur markings and eye colors, full body"),
            negative_prompt="extra limbs, missing limbs, altered markings, text, photograph, background scene",
            image=reference, control_image=edges, strength=0.38, num_inference_steps=20,
            guidance_scale=6, controlnet_conditioning_scale=0.85).images[0].convert("RGBA")
        cartoon.putalpha(canvas.getchannel("A"))
        # Segmentation contract: input float32 [1,3,512,512], ImageNet normalized;
        # output float32 logits [1,6,512,512] with labels listed in rigging.py.
        tensor = np.asarray(cartoon.convert("RGB"), dtype=np.float32) / 255
        tensor = (tensor - np.array([0.485, 0.456, 0.406], dtype=np.float32)) / np.array([0.229, 0.224, 0.225], dtype=np.float32)
        logits = self.segmenter.run(None, {self.segmenter.get_inputs()[0].name: tensor.transpose(2, 0, 1)[None]})[0]
        if logits.shape != (1, 6, 512, 512): raise ValueError("Segmentation model has the wrong output contract")
        classes = Image.fromarray(logits.argmax(axis=1)[0].astype(np.uint8), mode="L")
        return build_atlas(cartoon, classes, pet_id)


pipeline = None
gate = asyncio.Lock()


@asynccontextmanager
async def lifespan(app):
    global pipeline
    if len(os.environ.get("PIPELINE_TOKEN", "")) < 32: raise RuntimeError("Configure a private worker token of at least 32 characters")
    pipeline = await asyncio.to_thread(PhotoPipeline)
    yield


app = FastAPI(title="PawSync inference worker", lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)


@app.post("/vectorize")
async def vectorize(photo: UploadFile = File(...), pet_id: str = Form(...), alpha_matting: str = Form("true"), authorization: str = Header("")):
    if not hmac.compare_digest(authorization, "Bearer " + os.environ.get("PIPELINE_TOKEN", "")):
        raise HTTPException(401, "Unauthorized")
    try: pet_id = str(uuid.UUID(pet_id))
    except ValueError: raise HTTPException(422, "Invalid pet ID") from None
    raw = await photo.read(15 * 1024 * 1024 + 1)
    if len(raw) > 15 * 1024 * 1024: raise HTTPException(413, "Photo too large")
    if gate.locked(): raise HTTPException(503, "Worker is busy; retry later")
    async with gate:
        try:
            return await asyncio.to_thread(pipeline.generate, raw, pet_id)
        except Exception as error:
            log.error('{"event":"pipeline_failed","error_type":"%s"}', type(error).__name__)
            raise HTTPException(422, "Unable to segment this pet. Try a front-facing full-body photo.") from None
