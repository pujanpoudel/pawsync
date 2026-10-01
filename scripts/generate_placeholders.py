#!/usr/bin/env python3
"""Build-time placeholder atlases. Replace these directories with the real pipeline bake."""
import json
import math
import pathlib
import random
import struct
import wave
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1] / "macos/Resources"


class Canvas:
    def __init__(self, width, height):
        self.width, self.height = width, height
        self.pixels = bytearray(width * height * 4)

    def shape(self, predicate, color):
        for y in range(self.height):
            for x in range(self.width):
                if predicate(x + 0.5, y + 0.5):
                    offset = (y * self.width + x) * 4
                    self.pixels[offset:offset + 4] = bytes(color)

    def ellipse(self, x, y, rx, ry, color):
        self.shape(lambda px, py: ((px-x)/rx)**2 + ((py-y)/ry)**2 <= 1, color)

    def polygon(self, points, color):
        def inside(x, y):
            result = False
            for a, b in zip(points, points[1:] + points[:1]):
                if (a[1] > y) != (b[1] > y) and x < (b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]:
                    result = not result
            return result
        self.shape(inside, color)

    def save(self, path):
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
        raw = b"".join(b"\x00" + self.pixels[y*self.width*4:(y+1)*self.width*4] for y in range(self.height))
        path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", self.width, self.height, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def generate(pet_id, name, shibe=False):
    directory = ROOT / "Pets" / pet_id
    directory.mkdir(parents=True, exist_ok=True)
    fur = (218, 156, 76, 255) if shibe else (153, 156, 183, 255)
    dark = (72, 57, 54, 255) if shibe else (66, 65, 87, 255)
    cream = (255, 237, 199, 255) if shibe else (230, 229, 241, 255)
    pink = (221, 154, 159, 255)
    body = Canvas(120, 100)
    body.ellipse(60, 51, 47, 49, dark); body.ellipse(60, 51, 44, 47, fur)
    body.ellipse(62, 64, 28, 32, cream); body.save(directory / "body.png")
    head = Canvas(110, 94)
    head.polygon([(8, 46), (12, 0), (43, 32)], dark)
    head.polygon([(67, 32), (98, 0), (103, 46)], dark)
    head.polygon([(13, 43), (16, 8), (40, 33)], fur)
    head.polygon([(70, 33), (94, 8), (98, 43)], fur)
    head.polygon([(19, 30), (19, 14), (34, 31)], pink)
    head.polygon([(77, 31), (92, 14), (90, 30)], pink)
    head.ellipse(55, 56, 51, 37, dark); head.ellipse(55, 55, 48, 35, fur)
    if shibe:
        head.ellipse(55, 72, 31, 19, cream)
        head.ellipse(35, 46, 10, 4, cream); head.ellipse(75, 46, 10, 4, cream)
    else:
        for x in [44, 55, 66]: head.polygon([(x-4, 21), (x+3, 21), (x, 38)], dark)
        head.ellipse(55, 75, 21, 13, cream)
    for x in [34, 76]:
        head.ellipse(x, 56, 6, 8, dark); head.ellipse(x-1, 53, 2, 2, (255,255,255,255))
    head.polygon([(49, 69), (61, 69), (55, 76)], dark)
    head.ellipse(48, 79, 7, 2, dark); head.ellipse(62, 79, 7, 2, dark)
    head.save(directory / "head.png")
    for key in ["left_paw", "right_paw"]:
        paw = Canvas(28, 48); paw.ellipse(14, 24, 13, 23, dark); paw.ellipse(14, 24, 10, 21, fur)
        paw.ellipse(14, 36, 10, 10, cream); paw.save(directory / f"{key}.png")
    tail = Canvas(83, 42)
    tail.ellipse(40, 24, 38, 15, dark); tail.ellipse(40, 23, 36, 12, fur)
    if shibe:
        tail.ellipse(61, 17, 20, 16, fur); tail.ellipse(64, 17, 9, 8, cream)
    tail.save(directory / "tail.png")
    parts = {
        "body": {"anchor": [0.5, 0.2]},
        "head": {"anchor": [0.5, 0.1], "parent_offset": [0, 61]},
        "left_paw": {"anchor": [0.5, 0.9], "parent_offset": [-33, 22]},
        "right_paw": {"anchor": [0.5, 0.9], "parent_offset": [33, 22]},
        "tail": {"anchor": [0.1, 0.5], "parent_offset": [-40, 31]}
    }
    for key, part in parts.items(): part["file"] = f"{key}.png"
    (directory / "atlas.json").write_text(json.dumps({"id": pet_id, "name": name, "parts": parts}, indent=2) + "\n")


def audio():
    random.seed(42)
    for name, seconds in [("tap", 0.045), ("meow", 0.24)]:
        with wave.open(str(ROOT / f"{name}.wav"), "wb") as output:
            output.setparams((1, 2, 22050, 0, "NONE", "not compressed"))
            samples = []
            for i in range(int(seconds * 22050)):
                t = i / 22050
                sample = random.uniform(-1, 1) * math.exp(-t*120) * 0.12 if name == "tap" else math.sin(2*math.pi*(520*t + 180*t*t)) * math.sin(math.pi*t/seconds)**2 * 0.11
                samples.append(struct.pack("<h", int(sample*32767)))
            output.writeframes(b"".join(samples))


def icon():
    iconset = ROOT.parents[1] / "build/AppIcon.iconset"
    iconset.mkdir(parents=True, exist_ok=True)
    for size in [16, 32, 128, 256, 512]:
        for multiplier in [1, 2]:
            length = size * multiplier
            image = Canvas(length, length)
            def rounded(x, y):
                margin, radius = length * 0.055, length * 0.21
                cx = max(margin + radius, min(length - margin - radius, x))
                cy = max(margin + radius, min(length - margin - radius, y))
                return (x-cx)**2 + (y-cy)**2 <= radius**2
            image.shape(rounded, (112, 91, 167, 255))
            cream = (255, 239, 219, 255)
            image.ellipse(length*.50, length*.61, length*.20, length*.17, cream)
            for x, y, radius in [(.25,.44,.075),(.41,.30,.085),(.61,.30,.085),(.77,.44,.075)]:
                image.ellipse(length*x, length*y, length*radius, length*radius*1.15, cream)
            suffix = "@2x" if multiplier == 2 else ""
            image.save(iconset / f"icon_{size}x{size}{suffix}.png")
    formats = {"icon_16x16.png": "icp4", "icon_32x32.png": "icp5", "icon_32x32@2x.png": "icp6", "icon_128x128.png": "ic07", "icon_256x256.png": "ic08", "icon_512x512.png": "ic09", "icon_512x512@2x.png": "ic10", "icon_16x16@2x.png": "ic11", "icon_128x128@2x.png": "ic13", "icon_256x256@2x.png": "ic14"}
    chunks = []
    for filename, kind in formats.items():
        png = (iconset / filename).read_bytes()
        chunks.append(kind.encode("ascii") + struct.pack(">I", len(png) + 8) + png)
    data = b"".join(chunks)
    (ROOT / "AppIcon.icns").write_bytes(b"icns" + struct.pack(">I", len(data) + 8) + data)


if __name__ == "__main__":
    generate("pixel-cat", "Pixel Cat")
    generate("shibe", "Shibe", shibe=True)
    audio()
    icon()
    print("Generated two static placeholder atlases and preview sounds.")
