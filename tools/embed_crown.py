"""Bake assets/unicrase-crown.png into the standalone Roblox Script (dev tool: Pillow)."""
import argparse
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "Enkaisy_Combined_UI_v4_2.lua"
ASSET = ROOT / "assets" / "unicrase-crown.png"
BEGIN, END = "-- BEGIN UNICRASE ICON DATA", "-- END UNICRASE ICON DATA"


def encode(values):
    # 64 printable symbols, none including '=' (safe in a Luau [=[long string]=]).
    return "".join(chr(63 + v) for v in values)


def band(samples, luminance):
    """Fit one half scanline to Roblox's limit of 20 ColorSequence keypoints."""
    points = list(range(len(samples)))
    while len(points) > 20:
        def error(k):
            a, x, b = points[k-1:k+2]
            va, vx, vb = (luminance[samples[i]] for i in (a, x, b))
            return abs((vx - va) * (b - a) - (vb - va) * (x - a))
        points.pop(min(range(1, len(points) - 1), key=error))
    return encode(v for x in points for v in (x, samples[x]))


def baked_data():
    with Image.open(ASSET) as source:
        if source.width != source.height:
            raise ValueError("The brand badge expects a square PNG (no implicit cropping)")
        rgb = source.convert("RGB")
        art = rgb.resize((144, 144), Image.Resampling.LANCZOS).quantize(colors=64, dither=Image.Dither.NONE)
        palette = bytes(art.getpalette()[:192])
        pixels = art.tobytes()
        rows = [encode(pixels[i:i+art.width]) for i in range(0, len(pixels), art.width)]
        # A filtered mip of the same art for clients without EditableImage permission/budget.
        mip = rgb.resize((64, 64), Image.Resampling.LANCZOS)
        samples = mip.quantize(palette=art, dither=Image.Dither.NONE).tobytes()
        assert max(samples) < 64
        luma = [sum(a*b for a, b in zip(palette[i:i+3], (.299, .587, .114))) for i in range(0, len(palette), 3)]
        strips = [band(samples[i:i+32], luma) for i in range(0, len(samples), 32)]
        return (f'{BEGIN}\nBrand.side = {art.width}\nBrand.rgb = "{palette.hex()}"\n'
                + 'Brand.pixels = [=[\n' + '\n'.join(rows) + '\n]=]\n'
                + 'Brand.bands = [=[\n' + '\n'.join(strips) + f'\n]=]\n{END}')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify the baked asset without editing")
    args = parser.parse_args()
    source = SCRIPT.read_text(encoding="utf-8")
    a, b = source.index(BEGIN), source.index(END) + len(END)
    updated = source[:a] + baked_data() + source[b:]
    if args.check:
        if updated != source:
            raise SystemExit("Embedded crown is stale; run tools/embed_crown.py")
    else:
        SCRIPT.write_text(updated, encoding="utf-8")
