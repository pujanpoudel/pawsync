import importlib.util
import pathlib

import pytest
from PIL import Image, ImageDraw


path = pathlib.Path(__file__).resolve().parents[2] / "inference/rigging.py"
spec = importlib.util.spec_from_file_location("pawsync_rigging", path)
rigging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rigging)


def test_segmentation_atlas_preserves_parent_coordinates():
    cartoon = Image.new("RGBA", (180, 180), (220, 150, 80, 255))
    classes = Image.new("L", (180, 180), 0)
    draw = ImageDraw.Draw(classes)
    for box, value in [((55, 70, 125, 145), 1), ((55, 20, 125, 69), 2), ((45, 85, 54, 125), 3), ((126, 85, 136, 125), 4), ((15, 100, 44, 120), 5)]:
        draw.rectangle(box, fill=value)
    atlas = rigging.build_atlas(cartoon, classes, "c04d0ce4-9a3c-445c-a69b-d02b5dbb8fd1")
    assert set(atlas["parts"]) == set(rigging.CLASSES)
    assert atlas["parts"]["head"]["parent_offset"][1] > 0
    assert atlas["parts"]["left_paw"]["parent_offset"][0] < 0
    assert atlas["parts"]["right_paw"]["parent_offset"][0] > 0
    assert atlas["parts"]["body"]["parent_offset"] == [0, 0]


def test_missing_anatomy_is_rejected_instead_of_fabricated():
    with pytest.raises(ValueError, match="segmented body"):
        rigging.build_atlas(Image.new("RGBA", (180, 180)), Image.new("L", (180, 180)), "test")
