"""Builds the app icon masters from the generated concept art.

Run from the repo root: uv run --with pillow python design/icons/make_icons.py
then: dart run flutter_launcher_icons
"""
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).parent
TEAL = (6, 67, 73)  # #064349, also adaptive_icon_background in pubspec.yaml
SIZE = 1024

src = Image.open(HERE / "photokeeper_icon_c_aperture_shield.jpg").convert("RGB")

# Key the glyph off the teal tile: alpha ramps with color distance, colour is un-mixed from the teal.
glyph = Image.new("RGBA", src.size)
cx, cy = src.width / 2, src.height / 2
px = []
for i, p in enumerate(src.get_flattened_data()):
    x, y = i % src.width, i // src.width
    if (x - cx) ** 2 + (y - cy) ** 2 > 430**2:  # outside the aperture: tile edge and white corners
        px.append((0, 0, 0, 0))
        continue
    d = sum((a - b) ** 2 for a, b in zip(p, TEAL)) ** 0.5
    a = min(max((d - 30) / 60, 0), 1)
    if a == 0:
        px.append((0, 0, 0, 0))
        continue
    c = tuple(min(max(round((v - (1 - a) * t) / a), 0), 255) for v, t in zip(p, TEAL))
    px.append((*c, round(a * 255)))
glyph.putdata(px)
glyph = glyph.crop(glyph.getbbox())


def place(canvas, box, fraction):
    """Pastes the glyph centred in box, its longer side `fraction` of the box width."""
    x0, y0, x1, y1 = box
    s = (x1 - x0) * fraction / max(glyph.size)
    g = glyph.resize((round(glyph.width * s), round(glyph.height * s)), Image.LANCZOS)
    canvas.alpha_composite(g, (x0 + (x1 - x0 - g.width) // 2, y0 + (y1 - y0 - g.height) // 2))
    return canvas


# iOS / store listings: full-bleed square, the OS applies its own mask.
place(Image.new("RGBA", (SIZE, SIZE), TEAL), (0, 0, SIZE, SIZE), 0.62).convert("RGB").save(HERE / "icon.png")

# Android adaptive foreground: glyph inside the 66% safe circle on a 108dp canvas.
place(Image.new("RGBA", (SIZE, SIZE)), (0, 0, SIZE, SIZE), 0.56).save(HERE / "icon_foreground.png")

# macOS / Windows / Linux: Apple's grid, an 824px rounded tile on a transparent 1024 canvas.
mask = Image.new("L", (SIZE * 4, SIZE * 4))
ImageDraw.Draw(mask).rounded_rectangle((400, 400, 3696, 3696), radius=740, fill=255)
rounded = Image.new("RGBA", (SIZE, SIZE), TEAL)
rounded.putalpha(mask.resize((SIZE, SIZE), Image.LANCZOS))
place(rounded, (100, 100, 924, 924), 0.62).save(HERE / "icon_rounded.png")
rounded.resize((256, 256), Image.LANCZOS).save(HERE.parent.parent / "linux/runner/resources/app_icon.png")
