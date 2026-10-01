"""Convert an aligned six-class mask into the same atlas used by bundled pets."""
import base64
import io

from PIL import Image, ImageChops, ImageFilter

CLASSES = {"body": 1, "head": 2, "left_paw": 3, "right_paw": 4, "tail": 5}
ANCHORS = {"body": [0.5, 0.2], "head": [0.5, 0.1], "left_paw": [0.5, 0.9], "right_paw": [0.5, 0.9], "tail": [0.1, 0.5]}


def build_atlas(cartoon, classes, pet_id):
    cartoon = cartoon.convert("RGBA")
    if cartoon.size != classes.size: raise ValueError("Segmentation must be aligned to the cartoon")
    classes = classes.convert("L")
    target = cartoon.copy(); target.thumbnail((180, 180), Image.Resampling.LANCZOS)
    classes = classes.resize(target.size, Image.Resampling.NEAREST)
    regions, pivots = {}, {}
    alpha = target.getchannel("A")
    for name, label in CLASSES.items():
        mask = classes.point([255 if value == label else 0 for value in range(256)])
        mask = ImageChops.multiply(mask, alpha)
        box = mask.getbbox()
        if not box or box[2] - box[0] < 3 or box[3] - box[1] < 3:
            raise ValueError(f"The photo does not contain a reliably segmented {name}; try a front-facing full-body photo")
        # A small overlap prevents seams opening as joints rotate.
        mask = ImageChops.multiply(mask.filter(ImageFilter.MaxFilter(3)), alpha)
        box = mask.getbbox()
        image = target.copy(); image.putalpha(mask); image = image.crop(box)
        ax, ay = ANCHORS[name]
        pivots[name] = (box[0] + image.width * ax, box[1] + image.height * (1 - ay))
        regions[name] = image
    body_x, body_y = pivots["body"]
    parts = {}
    for name, image in regions.items():
        output = io.BytesIO(); image.save(output, "PNG", optimize=True)
        x, y = pivots[name]
        parts[name] = {"file": f"{name}.png", "anchor": ANCHORS[name],
                       "parent_offset": [0, 0] if name == "body" else [round(x-body_x, 3), round(body_y-y, 3)],
                       "png_base64": base64.b64encode(output.getvalue()).decode()}
    return {"id": pet_id, "name": "My companion", "parts": parts}
