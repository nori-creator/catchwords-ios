#!/usr/bin/env python3
"""Builds the cut-out harness's made-up scenes (scripts/cutout-harness/scenes/ and scenes.json).

Run from the repository root:  python3 scripts/cutout-harness/make_scenes.py

Why (owner 2026-11-03, after a lint roller came out as its handle alone): the cut-out must hold up for everything people
photograph, not only the photos a bug was reported on, and however the AI's box falls on a given try. A real photo needs
a hand-drawn reference mask, so there are few; here each object's exact outline is known, so many scenes can be checked:

- The objects: the product photos in server/public/ai-test/photos (plain background) whose colour differs from the
  background — the outline is the pixels that differ (`object_mask`), a little inside; plus the owner's lint roller
  (its hand-drawn mask). White and silver things (a mug, a fan) cannot be told from the background and are left out.
- The backgrounds: a wooden floor (from the owner's lint-roller photo), a cafe table and a street (ai-test photos).
- Each object goes on each background at a size people photograph things at, with a soft shadow; some scenes put two
  objects side by side, touching (both named: they must still be told apart).

The harness (main.swift) runs every scene with several AI boxes per thing (`variants`: tight, loose, small, shifted),
so a scene passes only when every box gives the whole thing.
"""
import json
import os

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
AITEST = os.path.join(REPO, "server", "public", "ai-test", "photos")
OUT = os.path.join(HERE, "scenes")

# name in ai-test → the word the AI would give
OBJECTS = {
    "stool": "塑膠椅",
    "keys": "鑰匙",
    "umbrella": "雨傘",
    "slippers": "拖鞋",
    "lantern": "燈籠",
    "banana": "香蕉",
    "bubble-tea-cup": "珍珠奶茶",
    "succulent": "多肉植物",
    "cola": "可樂",
    "juice": "果汁",
    "oolong": "烏龍茶",
    "mango": "芒果",
    "pineapple-cake": "鳳梨酥",
    "xiaolongbao": "小籠包",
    "pomelo": "柚子",
}
W, H = 900, 1200


def object_mask(rgb: np.ndarray) -> np.ndarray:
    """The object on a plain background: pixels whose colour (not only brightness — shadows keep the colour) differs."""
    border = np.concatenate([rgb[:8].reshape(-1, 3), rgb[-8:].reshape(-1, 3), rgb[:, :8].reshape(-1, 3), rgb[:, -8:].reshape(-1, 3)])
    bg = np.median(border, 0)
    lum = rgb.mean(2)
    chroma = np.abs((rgb - rgb.mean(2, keepdims=True)) - (bg - bg.mean())).max(2)
    obj = (chroma > 14) | (lum < bg.mean() - 70) | (lum > bg.mean() + 12)
    m = Image.fromarray((obj * 255).astype("uint8"))
    m = m.filter(ImageFilter.MedianFilter(5)).filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
    return np.asarray(m) > 127


def load_objects():
    out = {}
    for name, word in OBJECTS.items():
        rgb = np.asarray(Image.open(os.path.join(AITEST, name + ".jpg")).convert("RGB")).astype(float)
        m = object_mask(rgb)
        ys, xs = np.where(m)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        out[name] = (word, rgb[y0:y1, x0:x1].astype("uint8"), m[y0:y1, x0:x1])
    # The owner's lint roller (photos/lint-roller.jpg and its hand-drawn mask).
    rgb = np.asarray(Image.open(os.path.join(HERE, "photos", "lint-roller.jpg")).convert("RGB"))
    m = np.asarray(Image.open(os.path.join(HERE, "photos", "lint-roller.roller.png")).convert("L")) > 127
    ys, xs = np.where(m)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    out["lint-roller"] = ("滾筒黏毛器", rgb[y0:y1, x0:x1], m[y0:y1, x0:x1])
    return out


def backgrounds():
    lint = Image.open(os.path.join(HERE, "photos", "lint-roller.jpg")).convert("RGB")
    floor = lint.crop((470, 560, 888, 1000)).resize((W, H), Image.LANCZOS)
    cafe = Image.open(os.path.join(AITEST, "cafe.jpg")).convert("RGB").resize((W, H), Image.LANCZOS)
    street = Image.open(os.path.join(AITEST, "bubble-tea-street.jpg")).convert("RGB")
    street = street.resize((W, int(street.height * W / street.width)), Image.LANCZOS).crop((0, 0, W, H))
    return {"floor": floor, "cafe": cafe, "street": street}


def place(canvas: Image.Image, full: np.ndarray, obj, height_share: float, centre):
    """Pastes the object (with a soft shadow) so its height is `height_share` of the photo, centred at `centre`
    (0–1). Writes its mask into `full` (bool, H × W); returns its box in pixels."""
    _word, rgb, m = obj
    h = int(H * height_share)
    w = max(1, int(rgb.shape[1] * h / rgb.shape[0]))
    if w > W * 0.8:
        w = int(W * 0.8)
        h = max(1, int(rgb.shape[0] * w / rgb.shape[1]))
    img = Image.fromarray(rgb).resize((w, h), Image.LANCZOS)
    alpha = Image.fromarray((m * 255).astype("uint8")).resize((w, h), Image.LANCZOS)
    x = int(centre[0] * W - w / 2)
    y = int(centre[1] * H - h / 2)
    x = min(max(0, x), W - w)
    y = min(max(0, y), H - h)
    shadow = Image.new("L", canvas.size, 0)
    shadow.paste(alpha.point(lambda v: int(v * 0.45)), (x + int(w * 0.03), y + int(h * 0.03)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(max(4, w // 25)))
    canvas.paste(Image.new("RGB", canvas.size, (20, 15, 10)), (0, 0), shadow)
    canvas.paste(img, (x, y), alpha.filter(ImageFilter.GaussianBlur(0.8)))
    a = np.asarray(alpha) > 127
    full[y:y + h, x:x + w] |= a
    return (x, y, x + w, y + h)


def box_2d(b):
    x0, y0, x1, y1 = b
    return [round(y0 / H * 1000), round(x0 / W * 1000), round(y1 / H * 1000), round(x1 / W * 1000)]


def reference(mask: np.ndarray) -> Image.Image:
    """A little inside the outline (3 px), so the check measures the thing, not Vision's last pixel at its edge."""
    return Image.fromarray((mask * 255).astype("uint8")).filter(ImageFilter.MinFilter(7))


def main():
    os.makedirs(OUT, exist_ok=True)
    objs = load_objects()
    bgs = backgrounds()
    cases = []
    # Sizes and places people photograph a thing at: big and centred, smaller and off to one side.
    layouts = {"floor": (0.55, (0.5, 0.52)), "cafe": (0.42, (0.42, 0.62)), "street": (0.38, (0.58, 0.6))}
    for bg_name, bg in bgs.items():
        share, centre = layouts[bg_name]
        for name, obj in objs.items():
            canvas = bg.copy()
            full = np.zeros((H, W), bool)
            box = place(canvas, full, obj, share, centre)
            sid = f"{name}-on-{bg_name}"
            canvas.save(os.path.join(OUT, sid + ".jpg"), quality=90)
            reference(full).save(os.path.join(OUT, sid + "." + name + ".png"))
            cases.append({"id": sid, "photo": "../scenes/" + sid + ".jpg", "what": f"{name} on the {bg_name}.",
                          "variants": True,
                          "things": [{"name": obj[0], "box_2d": box_2d(box), "reference": "../scenes/" + sid + "." + name + ".png"}]})
    # Two things side by side, touching (both named): each must be whole and must not take the other.
    pairs = [("cola", "pineapple-cake"), ("banana", "mango"), ("keys", "slippers"), ("bubble-tea-cup", "xiaolongbao"),
             ("lint-roller", "keys"), ("umbrella", "lantern"), ("succulent", "juice"), ("stool", "pomelo")]
    for a, b in pairs:
        for bg_name in ("floor", "cafe"):
            canvas = bgs[bg_name].copy()
            fa = np.zeros((H, W), bool)
            fb = np.zeros((H, W), bool)
            ba = place(canvas, fa, objs[a], 0.42, (0.33, 0.55))
            # The second right next to the first, overlapping its edge a little (touching).
            wa = ba[2] - ba[0]
            bb = place(canvas, fb, objs[b], 0.36, ((ba[2] + wa * 0.35) / W, 0.6))
            fa &= ~fb   # the second is in front
            sid = f"{a}+{b}-on-{bg_name}"
            canvas.save(os.path.join(OUT, sid + ".jpg"), quality=90)
            reference(fa).save(os.path.join(OUT, sid + "." + a + ".png"))
            reference(fb).save(os.path.join(OUT, sid + "." + b + ".png"))
            cases.append({"id": sid, "photo": "../scenes/" + sid + ".jpg", "what": f"{a} and {b} touching, on the {bg_name}.",
                          "variants": True,
                          "things": [{"name": objs[a][0], "box_2d": box_2d(ba), "reference": "../scenes/" + sid + "." + a + ".png"},
                                     {"name": objs[b][0], "box_2d": box_2d(bb), "reference": "../scenes/" + sid + "." + b + ".png"}]})
    doc = {"photos": [
        {"file": "scenes/*", "licence": "Made for this test (make_scenes.py) from this repository's own pictures "
                 "(server/public/ai-test/photos, CatchWords' test photos) and the owner's lint-roller photo; CC0 for this test",
         "source": "this repository"}], "cases": cases}
    with open(os.path.join(HERE, "scenes.json"), "w") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(len(cases), "scenes")


if __name__ == "__main__":
    main()
