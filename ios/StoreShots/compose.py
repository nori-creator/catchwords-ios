#!/usr/bin/env python3
"""Compose App Store marketing screenshots for the iPhone Duo.

Usage:
    python3 compose.py --screens DIR --out DIR [--lang ja|en|all]

Inputs (relative to this script): copy.json, fonts/.
--screens DIR must hold inner/<lang>_<screen>.png (2007x2853, Duo inner
display) and outer/<lang>_<screen>.png (1398x2034, Duo outer display).
Writes --out/inner/<lang>_NN.png (2007x2853) and --out/outer/<lang>_NN.png
(1398x2034), RGB PNG, NN = 01.. in copy.json order.
"""
import argparse
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = os.path.join(HERE, "fonts")

SIZES = {"inner": (2007, 2853), "outer": (1398, 2034)}

DARK = (11, 22, 48)       # #0B1630
BLUE = (22, 119, 242)     # #1677F2
SLATE = (74, 85, 104)     # #4A5568
PALETTES = {
    "light":  {"dark": DARK, "blue": BLUE, "sub": SLATE},
    "meadow": {"dark": DARK, "blue": BLUE, "sub": (52, 64, 84)},
    "navy":   {"dark": (255, 255, 255), "blue": (110, 182, 255), "sub": (201, 214, 238)},
}


def font_paths(lang):
    if lang == "ja":
        return (os.path.join(FONTS, "NotoSansJP-Black.ttf"),
                os.path.join(FONTS, "NotoSansJP-Medium.ttf"))
    return (os.path.join(FONTS, "Inter-ExtraBold.ttf"),
            os.path.join(FONTS, "Inter-Medium.ttf"))


# ---------------------------------------------------------------- background

def _lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def _vgradient(w, h, stops):
    """stops: list of (t, rgb). Returns RGB image w x h."""
    col = Image.new("RGB", (1, h))
    px = col.load()
    for y in range(h):
        t = y / max(1, h - 1)
        for i in range(len(stops) - 1):
            t0, c0 = stops[i]
            t1, c1 = stops[i + 1]
            if t0 <= t <= t1:
                px[0, y] = _lerp(c0, c1, (t - t0) / max(1e-6, t1 - t0))
                break
    return col.resize((w, h))


def _blobs(img, blobs, blur):
    """Paint soft circles. blobs: (cx, cy, r, rgba) in 0..1 of width/height.
    Each blob blurs only its alpha mask, so edges never go grey."""
    w, h = img.size
    out = img.convert("RGBA")
    for cx, cy, r, rgba in blobs:
        rr = r * w
        m = Image.new("L", (w, h), 0)
        ImageDraw.Draw(m).ellipse([cx * w - rr, cy * h - rr, cx * w + rr, cy * h + rr],
                                  fill=rgba[3])
        m = m.filter(ImageFilter.GaussianBlur(blur * w))
        out.paste(Image.new("RGBA", (w, h), rgba[:3] + (255,)), (0, 0), m)
    return out


def background(kind, size):
    w, h = size
    sw, sh = max(1, w // 4), max(1, h // 4)  # paint small, scale up (smooth anyway)
    if kind == "navy":
        img = _vgradient(sw, sh, [(0, (10, 28, 74)), (1, (6, 18, 46))])
        img = _blobs(img, [
            (0.5, 0.42, 0.55, (30, 90, 200, 90)),
            (0.05, 0.15, 0.30, (40, 110, 230, 60)),
            (0.95, 0.75, 0.32, (40, 110, 230, 55)),
        ], 0.12)
    elif kind == "meadow":
        img = _vgradient(sw, sh, [(0, (214, 234, 252)), (0.38, (236, 245, 252)),
                                  (0.62, (214, 238, 206)), (1, (150, 200, 120))])
        img = _blobs(img, [
            (0.15, 0.08, 0.30, (255, 255, 255, 170)),
            (0.85, 0.12, 0.28, (255, 255, 255, 150)),
            (0.10, 0.80, 0.30, (120, 190, 90, 120)),
            (0.90, 0.88, 0.32, (110, 180, 80, 120)),
            (0.55, 0.98, 0.35, (250, 250, 220, 110)),
            (0.80, 0.55, 0.22, (190, 225, 245, 90)),
        ], 0.07)
    else:
        img = _vgradient(sw, sh, [(0, (234, 243, 253)), (0.55, (244, 249, 254)),
                                  (1, (255, 255, 255))])
        img = _blobs(img, [
            (0.95, 0.03, 0.22, (190, 218, 248, 170)),
            (-0.02, 0.30, 0.20, (196, 222, 250, 150)),
            (1.02, 0.62, 0.20, (190, 218, 248, 140)),
            (0.0, 0.90, 0.22, (200, 225, 250, 140)),
            (0.5, 1.02, 0.30, (205, 228, 252, 120)),
        ], 0.06)
    return img.convert("RGB").resize((w, h), Image.BICUBIC)


# ---------------------------------------------------------------- text

def text_w(font, s):
    if not s:
        return 0
    l, _, r, _ = font.getbbox(s)
    return r - l


def wrap_sub(text, font, max_w, lang):
    """Return 1 or 2 lines; 2 lines are balanced. None if it can't fit in 2."""
    if text_w(font, text) <= max_w:
        return [text]
    if lang == "ja":
        cuts = list(range(1, len(text)))
        # prefer breaking after punctuation
        pref = [i for i in cuts if text[i - 1] in "、。・，,"]
    else:
        cuts = [i for i, c in enumerate(text) if c == " "]
        pref = []
    best = None
    for group in (pref, cuts):
        for i in group:
            a, b = text[:i].rstrip(), text[i:].lstrip()
            if lang == "ja" and b and b[0] in "、。・ー":
                continue
            m = max(text_w(font, a), text_w(font, b))
            if m <= max_w and (best is None or m < best[0]):
                best = (m, [a, b])
        if best:
            return best[1]
    return None


def layout_text(entry, lang, W, H, kind, type_w=None):
    head_path, sub_path = font_paths(lang)
    pal = PALETTES[kind]
    max_w = 0.90 * W
    tw = type_w or W
    base = (0.098 if lang == "ja" else 0.096) * tw
    hs = int(base)
    lines = entry["lines"]
    while hs > 10:
        f = ImageFont.truetype(head_path, hs)
        if max(text_w(f, t) for t, _ in lines) <= max_w:
            break
        hs -= 2
    hfont = ImageFont.truetype(head_path, hs)
    base_ss = int((0.046 if lang == "ja" else 0.043) * tw)
    ss = base_ss
    while ss > 10:
        sfont = ImageFont.truetype(sub_path, ss)
        sub_lines = wrap_sub(entry["sub"], sfont, 0.88 * W, lang)
        if sub_lines:
            break
        ss -= 2
    return {
        "hfont": hfont, "hs": hs, "head_shrink": hs / base,
        "sfont": sfont, "ss": ss, "sub_shrink": ss / base_ss,
        "lines": lines, "sub_lines": sub_lines, "pal": pal, "lang": lang,
    }


def draw_text(img, T, W, H):
    d = ImageDraw.Draw(img)
    y = int(0.055 * H)
    lh = int(T["hs"] * (1.22 if T["lang"] == "ja" else 1.12))
    for text, color in T["lines"]:
        d.text((W / 2, y), text, font=T["hfont"], fill=T["pal"][color], anchor="mt")
        y += lh
    y += int(T["hs"] * 0.20)
    slh = int(T["ss"] * 1.45)
    for s in T["sub_lines"]:
        d.text((W / 2, y), s, font=T["sfont"], fill=T["pal"]["sub"], anchor="mt")
        y += slh
    return y  # bottom of text block (approx; includes line gap)


# ---------------------------------------------------------------- device

# The iPhone Duo's frame as Simulator draws it: the device type's chrome (com.apple.dt.devicekit.chrome.phone15,
# PhoneComposite), copied out of Xcode by ios-store-shots.yml into chrome/ (not in git: Apple's artwork). It is the
# folded phone: the spine on the left, small corners on the spine's side and large ones on the other. The black inside
# is the screen. The owner asked for the real frame, never a drawn one (2026-10-30).
CHROME = os.path.join(HERE, "chrome", "PhoneComposite.png")
SCREEN_BOX = (97, 34, 2827, 3966)   # the black screen inside PhoneComposite (x0, y0, x1, y1)
TOP_MARKS = [(555, 589), (2328, 2363)]      # buttons on the top edge (columns)
BOTTOM_MARKS = [(1020, 1054), (1864, 1898)]  # and on the bottom edge


def _stretch(img, axis, at, by):
    """Nine-slice stretch as Simulator resizes its chrome: repeat the straight band at `at` by `by` pixels."""
    if by <= 0:
        return img
    w, h = img.size
    if axis == "x":
        band = img.crop((at, 0, at + 1, h)).resize((by, h))
        out = Image.new("RGBA", (w + by, h), (0, 0, 0, 0))
        out.paste(img.crop((0, 0, at, h)), (0, 0))
        out.paste(band, (at, 0))
        out.paste(img.crop((at, 0, w, h)), (at + by, 0))
    else:
        band = img.crop((0, at, w, at + 1)).resize((w, by))
        out = Image.new("RGBA", (w, h + by), (0, 0, 0, 0))
        out.paste(img.crop((0, 0, w, at)), (0, 0))
        out.paste(band, (0, at))
        out.paste(img.crop((0, at, w, h)), (0, at + by))
    return out


def _clear_marks(img, y0, y1, marks):
    """Paint over the button marks on an edge with the plain edge next to them."""
    for a, b in marks:
        plain = img.crop((a - 40, y0, a - 40 + (b - a), y1))
        img.paste(plain, (a, y0))
    return img


def _screen_mask(chrome, box):
    """The screen's shape: the black inside the frame (anti-aliased)."""
    flat = Image.new("RGBA", chrome.size, (255, 255, 255, 255))
    flat.alpha_composite(chrome)            # outside the frame is clear: not screen
    lum = flat.convert("L").crop(box)
    m = lum.point(lambda v: 255 if v <= 6 else (0 if v >= 40 else int(255 * (40 - v) / 34)))
    return m.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))


def real_frame(kind, screen_size):
    """(chrome RGBA, screen box, screen mask) at the screen's pixel size.

    outer: the folded Duo as Simulator draws it (PhoneComposite), its straight middle stretched to the outer screen's
    shape. inner: opened flat, the folded frame and its mirror side by side, joined where the screen continues across
    the fold; the mirrored half has no buttons."""
    base = Image.open(CHROME).convert("RGBA")
    x0, y0, x1, y1 = SCREEN_BOX
    sw, sh = screen_size
    if kind == "outer":
        bw, bh = x1 - x0, y1 - y0
        k = sw / bw
        extra = round(sh / k) - bh
        c = _stretch(base, "y", 2000, extra)
        box = (x0, y0, x1, y1 + extra)
    else:
        half = base.crop((x0, 0, base.size[0], base.size[1]))     # from the screen's spine-side edge
        # the screen runs on across the fold: no small corners where the halves meet
        straight = half.crop((300, 0, 301, half.size[1])).resize((140, half.size[1]))
        half.paste(straight, (0, 0))
        hx1 = x1 - x0
        bh = y1 - y0
        k = sh / bh
        need = round(sw / k / 2) - hx1                          # each half's screen is a bit wider than folded
        half = _stretch(half, "x", 1200, need)
        hx1 += max(0, need)
        left = half.transpose(Image.FLIP_LEFT_RIGHT)
        w = left.size[0]
        flipped = [(w - (b - x0 + (need if a - x0 > 1200 else 0)), w - (a - x0 + (need if a - x0 > 1200 else 0)))
                   for a, b in TOP_MARKS]
        left = _clear_marks(left, 0, y0, flipped)
        flipped = [(w - (b - x0 + (need if a - x0 > 1200 else 0)), w - (a - x0 + (need if a - x0 > 1200 else 0)))
                   for a, b in BOTTOM_MARKS]
        left = _clear_marks(left, y1, base.size[1], flipped)
        c = Image.new("RGBA", (2 * w, base.size[1]), (0, 0, 0, 0))
        c.paste(left, (0, 0))
        c.paste(half, (w, 0))
        box = (w - hx1, y0, w + hx1, y1)
        k = sh / bh
    mask = _screen_mask(c, box)
    # to screen pixels
    W, H = round(c.size[0] * k), round(c.size[1] * k)
    c = c.resize((W, H), Image.LANCZOS)
    box = tuple(round(v * k) for v in box)
    mask = mask.resize((box[2] - box[0], box[3] - box[1]), Image.LANCZOS)
    return c, box, mask


def add_fold(screen):
    """A faint line down the middle, where the inner screen folds."""
    w, h = screen.size
    ov = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    cx = w // 2
    band = max(6, w // 160)
    for i in range(band, 0, -1):
        a = int(10 * (1 - i / band) ** 1.5)
        d.line([(cx - i - 1, 0), (cx - i - 1, h)], fill=(0, 0, 0, a))
        d.line([(cx + i, 0), (cx + i, h)], fill=(0, 0, 0, a))
    d.line([(cx, 0), (cx, h)], fill=(255, 255, 255, 40))
    return Image.alpha_composite(screen.convert("RGBA"), ov)


_FRAMES = {}


def device(raw, dev_w, kind):
    """The screenshot in the real Duo frame, `dev_w` wide."""
    key = (kind, raw.size)
    if key not in _FRAMES:
        _FRAMES[key] = real_frame(kind, raw.size)
    frame, box, mask = _FRAMES[key]
    screen = raw.convert("RGB").resize((box[2] - box[0], box[3] - box[1]), Image.LANCZOS)
    if kind == "inner":
        screen = add_fold(screen)
    body = frame.copy()
    body.paste(screen.convert("RGBA"), box[:2], mask)
    k = dev_w / body.size[0]
    return body.resize((dev_w, round(body.size[1] * k)), Image.LANCZOS)


def paste_device(canvas, dev, x, y, navy):
    w, h = dev.size
    pad = int(0.12 * w)
    sh = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    alpha = dev.split()[3].point(lambda a: int(a * (0.55 if navy else 0.28)))
    shadow_col = (0, 0, 0) if navy else (20, 60, 130)
    sh.paste(Image.new("RGBA", (w, h), shadow_col + (255,)), (pad, pad), alpha)
    sh = sh.filter(ImageFilter.GaussianBlur(0.045 * w))
    base = canvas.convert("RGBA")
    base.alpha_composite(sh, (x - pad, y - pad + int(0.025 * w)))
    base.alpha_composite(dev, (x, y))
    return base.convert("RGB")


# ---------------------------------------------------------------- compose

def out_size(kind, raw):
    """The Duo's inner display may be shot landscape (2853x2007): App Store Connect takes that size too."""
    w, h = SIZES[kind]
    return (h, w) if raw.size[0] > raw.size[1] and kind == "inner" else (w, h)


def compose(entry, lang, kind_size, raw):
    W, H = out_size(kind_size, raw)
    bg = entry.get("background", "light")
    img = background(bg, (W, H))
    # landscape: the headline over the device, its type sized as on a portrait canvas of the same height
    T = layout_text(entry, lang, W, H, bg, type_w=min(W, int(0.62 * H)))
    text_bottom = draw_text(img, T, W, H)
    top = text_bottom + int(0.025 * H)
    bottom = H - int(0.035 * H)
    avail_h = bottom - top
    probe = device(raw, 1000, kind_size)
    aspect = probe.size[1] / probe.size[0]
    dev_w = int(min(0.92 * W, avail_h / aspect))
    dev = device(raw, dev_w, kind_size)
    x = (W - dev.size[0]) // 2
    y = top + (avail_h - dev.size[1]) // 2
    out = paste_device(img, dev, x, y, bg == "navy")
    info = {"head_shrink": T["head_shrink"], "sub_shrink": T["sub_shrink"],
            "sub_lines": len(T["sub_lines"]), "device_w_pct": dev.size[0] / W}
    return out, info


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--screens", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--lang", default="all", choices=["ja", "en", "all"])
    ap.add_argument("--copy", default=os.path.join(HERE, "copy.json"))
    args = ap.parse_args()

    with open(args.copy, encoding="utf-8") as f:
        copy = json.load(f)
    langs = ["ja", "en"] if args.lang == "all" else [args.lang]
    missing = []
    for lang in langs:
        for n, entry in enumerate(copy[lang], 1):
            for kind in ("inner", "outer"):
                src = os.path.join(args.screens, kind, f"{lang}_{entry['screen']}.png")
                if not os.path.exists(src):
                    missing.append(src)
                    continue
                raw = Image.open(src)
                if raw.size not in (SIZES[kind], SIZES[kind][::-1]):
                    print(f"warning: {src} is {raw.size}, expected {SIZES[kind]}",
                          file=sys.stderr)
                out, info = compose(entry, lang, kind, raw)
                assert out.size == out_size(kind, raw) and out.mode == "RGB"
                dst_dir = os.path.join(args.out, kind)
                os.makedirs(dst_dir, exist_ok=True)
                dst = os.path.join(dst_dir, f"{lang}_{n:02d}.png")
                out.save(dst, "PNG", optimize=True)
                flag = ""
                if info["head_shrink"] < 0.85 or info["sub_shrink"] < 0.85:
                    flag = "  <- shrunk"
                print(f"{dst}  head x{info['head_shrink']:.2f}  sub x{info['sub_shrink']:.2f}"
                      f" ({info['sub_lines']} line)  device {info['device_w_pct']:.0%}{flag}")
    if missing:
        print("missing screens:\n  " + "\n  ".join(missing), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
