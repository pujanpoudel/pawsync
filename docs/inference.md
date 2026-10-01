# Inference deployment contract

The public API performs authentication, rate limiting, file validation and transactional credit handling. The inference worker has no payment credentials and cannot change balances. Deploy it on a private network or behind mTLS; its additional bearer secret must match `PIPELINE_TOKEN` in both services.

Run from `inference/` with Python 3.12/3.13, CUDA PyTorch, and the dependencies in `pyproject.toml`. Export the variables from `.env.example`, then run `uvicorn worker:app --host 127.0.0.1 --port 8001`. If the API is on another machine, expose the worker through a private authenticated HTTPS reverse proxy rather than a public unrestricted socket. Configure the wallet API's `PIPELINE_URL` to the worker origin.

The worker accepts `POST /vectorize`, multipart `photo` (metadata-stripped PNG), `pet_id` (UUID), and `alpha_matting=true`. It returns `id`, `name`, and exactly five `parts`: body/head/left_paw/right_paw/tail. Each part has `png_base64`, `file`, normalized bottom-left `anchor`, and `parent_offset` relative to the body joint in SpriteKit coordinates. The API validates every PNG and anchor before committing a credit.

The part segmenter must accept float32 `[1,3,512,512]` ImageNet-normalized RGB and return logits `[1,6,512,512]`. Class order:

1. 0: background
2. 1: body
3. 2: head
4. 3: left paw
5. 4: right paw
6. 5: tail

Train and evaluate on cartoon-style pet images aligned with the selected diffusion model. Include diverse fur, eye colors, species, poses and occlusions. Missing anatomy is a generation failure, not a fabricated limb. The user should supply a front-facing full-body photo showing both front paws and the tail. Photos with an invisible tail or cropped body will fail this rig contract and return their credit.

Rig extraction scales the whole aligned output to at most 180 pixels, crops masks to their nontransparent bounds, adds one pixel of overlap to reduce joint seams, and computes parent offsets from image-space joint pivots. Transparent pixels are retained; no sprite-sheet animation is produced.

The public request has a 25-second pipeline deadline; provider HTTP requests have a 24-second timeout. Warm model weights before serving traffic. The worker serializes GPU jobs and returns 503 when busy. Scale separate warm replicas behind a queue-aware internal router to meet the budget; do not allow an unbounded inference queue inside the request timeout.

The integration code uses the documented [Diffusers ControlNet image-to-image API](https://huggingface.co/docs/diffusers/en/api/pipelines/controlnet) and [rembg session/removal API](https://github.com/danielgatis/rembg). Model weights, training, throughput, and output quality have not been verified in this environment.
