#!/usr/bin/env python3
"""Builds the cut-out harness's photos and reference masks (scripts/cutout-harness/photos/).

Run from the repository root:  python3 scripts/cutout-harness/make_photos.py <dir with the source photos>

The sources and their licences are in cases.json ("photos"). Real photos get a reference mask drawn from a polygon a
little inside the thing's outline (so "covers 85% of the reference" means the cut-out holds the thing, whatever Vision
does at its very edge); the made-up scenes get the exact mask of each thing pasted in. Every photo is at most 1200 px.
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "photos")
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

# Polygons in 0–1000 of the upright photo, [x, y] — a little inside each thing.
POLYGONS = {
    "dorayaki.dorayaki": [[[225, 425], [300, 385], [450, 370], [600, 378], [710, 405], [770, 445], [765, 500], [750, 560],
                           [720, 610], [640, 640], [500, 652], [380, 648], [290, 628], [245, 600], [238, 540], [232, 480]]],
    "dorayaki.carton": [[[215, 65], [780, 62], [780, 340], [215, 340]]],
    "coffee.cup": [[[300, 150], [330, 90], [420, 55], [520, 50], [600, 80], [645, 150], [640, 250], [610, 370], [570, 470],
                    [500, 530], [420, 535], [350, 480], [320, 380], [300, 260]],
                   [[335, 590], [400, 580], [420, 640], [400, 740], [345, 750], [330, 680]]],
    "coffee.spoon": [[[560, 640], [620, 610], [665, 650], [670, 730], [630, 790], [575, 780], [552, 720]],
                     [[640, 590], [662, 592], [688, 200], [672, 190]]],
    "chelsea.cat": [[[60, 0], [800, 0], [800, 300], [760, 600], [700, 800], [600, 950], [400, 950], [250, 850], [130, 700],
                     [60, 500]]],
    "astronaut.helmet": [[[580, 780], [650, 700], [750, 680], [870, 690], [950, 760], [975, 850], [970, 1000], [570, 1000],
                          [555, 880]]],
    "astronaut.shuttle": [[[760, 40], [830, 5], [860, 60], [870, 250], [900, 380], [890, 480], [800, 480], [720, 420],
                           [740, 250], [770, 120]]],
    "cafe.cup": [[[420, 690], [500, 672], [640, 672], [700, 690], [690, 760], [640, 800], [520, 805], [450, 780], [425, 740]]],
    "cafe.vase": [[[800, 630], [900, 620], [950, 650], [945, 760], [800, 765], [785, 700]]],
    "cat.cat": [[[430, 170], [470, 90], [520, 170], [640, 180], [680, 165], [640, 290], [660, 420], [700, 560], [720, 700],
                 [750, 800], [740, 900], [700, 940], [680, 850], [600, 810], [470, 820], [400, 790], [370, 640], [360, 450],
                 [380, 300], [420, 230]]],
    "boba.cup": [[[250, 500], [480, 470], [740, 490], [720, 560], [690, 700], [650, 790], [400, 795], [340, 700], [300, 560]],
                 [[500, 310], [570, 305], [540, 470], [490, 470]]],
}


def fit(im, side=1200):
    im = im.convert("RGB")
    im.thumbnail((side, side), Image.LANCZOS)
    return im


def polygon_mask(size, polys):
    w, h = size
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    for p in polys:
        d.polygon([(x * w / 1000, y * h / 1000) for x, y in p], fill=255)
    return m


def save(im, name, **kw):
    path = os.path.join(OUT, name)
    if name.endswith(".jpg"):
        im.save(path, quality=88, **kw)
    else:
        im.save(path, optimize=True)
    print("wrote", os.path.relpath(path, REPO), im.size)


def table(size, seed=7):
    """A pale table top: smooth light grey-beige with a soft grain and a light fall-off."""
    w, h = size
    import random
    random.seed(seed)
    base = Image.new("RGB", size, (222, 216, 206))
    grain = Image.effect_noise(size, 18).convert("L").filter(ImageFilter.GaussianBlur(1.2))
    base = Image.blend(base, Image.merge("RGB", (grain, grain, grain)), 0.12)
    shade = Image.radial_gradient("L").resize(size).filter(ImageFilter.GaussianBlur(40))
    dark = Image.new("RGB", size, (150, 145, 138))
    return Image.composite(dark, base, ImageOps.autocontrast(shade).point(lambda v: int(v * 0.35)))


def shadow(canvas, alpha, offset=(14, 18), blur=16, strength=0.35):
    sh = Image.new("L", canvas.size, 0)
    sh.paste(alpha, offset)
    sh = sh.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * strength))
    canvas.paste((40, 36, 30), (0, 0), sh)


def glasses_layer(size, origin, scale=1.0):
    """Glasses drawn as dark frames: two rounded lenses, a bridge, two temples reaching to the right."""
    w, h = size
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ox, oy = origin
    s = scale
    t = int(13 * s)
    frame = (28, 26, 30, 255)
    for cx in (ox, ox + int(250 * s)):
        d.ellipse([cx - int(105 * s), oy - int(80 * s), cx + int(105 * s), oy + int(80 * s)], outline=frame, width=t)
    # the bridge
    d.arc([ox + int(85 * s), oy - int(60 * s), ox + int(165 * s), oy + int(10 * s)], 200, 340, fill=frame, width=t)
    # temples, folded back towards the right
    d.line([ox + int(352 * s), oy - int(30 * s), ox + int(520 * s), oy - int(60 * s)], fill=frame, width=int(10 * s))
    d.line([ox - int(102 * s), oy - int(30 * s), ox + int(40 * s), oy - int(105 * s), ox + int(470 * s), oy - int(112 * s)],
           fill=frame, width=int(10 * s), joint="curve")
    # lenses: a faint tint so they read as glass
    lens = Image.new("RGBA", size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(lens)
    for cx in (ox, ox + int(250 * s)):
        ld.ellipse([cx - int(96 * s), oy - int(71 * s), cx + int(96 * s), oy + int(71 * s)], fill=(200, 210, 220, 40))
    return Image.alpha_composite(lens, layer)


def sticker(name, height):
    im = Image.open(os.path.join(REPO, "docs/design/catch-concepts/film/assets/dex", name + ".png")).convert("RGBA")
    k = height / im.height
    return im.resize((int(im.width * k), int(im.height * k)), Image.LANCZOS)


def composite_glasses_bottle():
    size = (1200, 900)
    canvas = table(size)
    bottle = sticker("oolong", 640).rotate(0, expand=True)
    bx, by = 760, 120
    shadow(canvas, bottle.split()[3], (bx + 18, by + 22))
    canvas.paste(bottle, (bx, by), bottle)
    g = glasses_layer(size, (330, 640), 1.05)
    shadow(canvas, g.split()[3], (10, 14), blur=8, strength=0.3)
    canvas = Image.alpha_composite(canvas.convert("RGBA"), g).convert("RGB")
    save(canvas, "glasses-bottle.jpg")
    bm = Image.new("L", size, 0)
    bm.paste(bottle.split()[3].point(lambda v: 255 if v > 128 else 0), (bx, by))
    save(bm.filter(ImageFilter.MinFilter(9)), "glasses-bottle.bottle.png")
    gm = g.split()[3].point(lambda v: 255 if v > 128 else 0)
    # the frames only (not the faint lenses), a little thinned
    save(gm.filter(ImageFilter.MinFilter(3)), "glasses-bottle.glasses.png")


def composite_keys_remote():
    size = (1200, 900)
    canvas = table(size, seed=11)
    remote = sticker("remote", 620).rotate(-28, expand=True, resample=Image.BICUBIC)
    keys = sticker("keys", 360).rotate(12, expand=True, resample=Image.BICUBIC)
    rx, ry, kx, ky = 260, 130, 520, 380
    shadow(canvas, remote.split()[3], (rx + 16, ry + 20))
    canvas.paste(remote, (rx, ry), remote)
    shadow(canvas, keys.split()[3], (kx + 10, ky + 14), blur=10)
    canvas.paste(keys, (kx, ky), keys)
    save(canvas, "keys-remote.jpg")
    rm = Image.new("L", size, 0)
    rm.paste(remote.split()[3].point(lambda v: 255 if v > 128 else 0), (rx, ry))
    km = Image.new("L", size, 0)
    km.paste(keys.split()[3].point(lambda v: 255 if v > 128 else 0), (kx, ky))
    # the remote's reference is what shows of it (the keys lie on top)
    rm = Image.composite(Image.new("L", size, 0), rm, km)
    save(rm.filter(ImageFilter.MinFilter(9)), "keys-remote.remote.png")
    save(km.filter(ImageFilter.MinFilter(5)), "keys-remote.keys.png")


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(OUT, exist_ok=True)
    real = {
        "dorayaki": "dorayaki.png",
        "coffee": "coffee.png",
        "chelsea": "chelsea.png",
        "astronaut": "astronaut.png",
        "cafe": os.path.join(REPO, "ios/CatchWords/Resources/Onboarding/first_catch_cafe.webp"),
        "cat": os.path.join(REPO, "ios/CatchWords/Resources/Onboarding/first_catch_cat.webp"),
        "boba": os.path.join(REPO, "docs/design/catch-concepts/film/assets/photo_1080.jpg"),
    }
    for key, path in real.items():
        im = fit(Image.open(path if os.path.isabs(path) else os.path.join(src, path)))
        save(im, key + ".jpg")
        for ref, polys in POLYGONS.items():
            if ref.split(".")[0] == key:
                save(polygon_mask(im.size, polys), ref + ".png")
    # The dorayaki once more, stored on its side with EXIF orientation 6 ("turn 90° clockwise to show"), as an iPad
    # camera stores a photo: the harness must read it upright, like the app.
    up = Image.open(os.path.join(OUT, "dorayaki.jpg"))
    exif = Image.Exif()
    exif[0x0112] = 6
    up.rotate(90, expand=True).save(os.path.join(OUT, "dorayaki-exif6.jpg"), quality=88, exif=exif)
    print("wrote scripts/cutout-harness/photos/dorayaki-exif6.jpg (EXIF orientation 6)")
    composite_glasses_bottle()
    composite_keys_remote()


if __name__ == "__main__":
    main()
