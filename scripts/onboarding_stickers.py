#!/usr/bin/env python3
"""
初回案内（OnboardingView）の写真を、アプリと同じ「切り抜きステッカー」に作り直す。

1. 切り抜く: 物が写っている写真は、物の形で切り抜く（rembg の BiRefNet。iPhone の Vision の代わり）。
   景色の写真は物の形が無いので、アプリの最後の手段と同じく「角の丸い形」で切り抜く（`StickerCrop.shaped`）。
2. 白いふち: 切り抜いた形の外側に、白いダイカットのふちを付ける（アプリのステッカーと同じ見た目）。
3. 光: blender/onboarding_stickers.py が Blender で、ほんの少し反ったビニールのステッカーとして光を当てる。
4. 書き出す: ios/CatchWords/Resources/Onboarding/onboarding_sticker_<名前>.webp

使い方（Python 3.11 以上）:
  pip install rembg pillow numpy scipy "bpy>=4.5"
  python scripts/onboarding_stickers.py          # 1〜4 をまとめて（初回は切り抜きのモデル 約 1GB を落とす）
  python scripts/onboarding_stickers.py --flat   # Blender を使わない（白いふちまで）
  python scripts/onboarding_stickers.py --cuts DIR  # 切り抜き済みの <元の写真>.png を DIR から使う（速い）

単語の札（咖啡 など）は絵に焼き込まない。画面の WordTag が、設定の読み（注音・ピンイン）付きで描く。
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "ios", "CatchWords", "Resources", "Onboarding")
SOURCES = os.path.join(ROOT, "blender", "onboarding", "sources")
OUT = SRC

# 名前 → (元の写真, 切り方)。"cut" は物の形、"shaped" は角の丸い形（景色）。
# 元の写真は blender/onboarding/sources/ に置いてある（アプリには入れない）。
# gen_*: 2026-10-22〜 ElevenLabs（Seedream 5 Pro）で作った、白い背景の商品写真（切り抜きやすい）。最初の画面の絵。
# first_catch_*: Web 時代の写真。興味の9枚はこれを使う（オーナー 2026-10-23「興味関心は元の画像を使って進めて」）。
STICKERS = {
    "cafe": ("gen_cafe", "cut"),
    "flower": ("first_catch_flower", "cut"),
    "cat": ("first_catch_cat", "cut"),
    "bubbletea": ("gen_bubbletea", "cut"),
    "food": ("first_catch_interest_food", "cut"),
    "travel": ("first_catch_interest_travel", "shaped"),
    "animals": ("first_catch_interest_animals", "cut"),
    "nature": ("first_catch_interest_nature", "shaped"),
    "city": ("first_catch_interest_city", "shaped"),
    "fashion": ("first_catch_interest_fashion", "cut"),
    "business": ("first_catch_interest_business", "cut"),
    "music": ("first_catch_interest_music", "cut"),
    "sports": ("first_catch_interest_sports", "cut"),
}

# 興味の9枚: 同じ大きさの正方形に、見た目の面積（白いふちを含む不透明な所）をそろえて置く
# （オーナー 2026-10-23「画像のサイズや縮尺が変だから、自然になるようにして」: 細長い靴が枠いっぱい、景色の四角が大きすぎた）。
INTERESTS = {"food", "travel", "animals", "nature", "city", "fashion", "business", "music", "sports"}
TILE = 640
# 正方形に対する不透明な所の割合と、はみ出さないための余白
TILE_AREA = 0.36
TILE_MARGIN = 0.06

# 書き出しの長い辺（px）。画面では最大で約 200pt なので 3x でも足りる大きさ。
LONG_SIDE = 700
# 白いふちの太さ（長い辺に対して）。アプリの切り抜きのふち（`CatchStickerArt` の 4%）に合わせる。
BORDER = 0.04


def cutout(photo, session):
    from rembg import remove

    return remove(photo.convert("RGB"), session=session)


def clean_alpha(rgba):
    """薄いもや（背景の残り）を消し、いちばん大きな形とそれに近い形だけ残す。"""
    a = np.asarray(rgba.getchannel("A")).astype(np.float32) / 255
    a[a < 0.12] = 0
    mask = a > 0.5
    labels, n = ndimage.label(mask)
    if n > 1:
        sizes = ndimage.sum(mask, labels, range(1, n + 1))
        keep = [i + 1 for i, s in enumerate(sizes) if s >= sizes.max() * 0.08]
        a[~np.isin(labels, keep) & (a > 0)] = 0
    out = rgba.copy()
    out.putalpha(Image.fromarray((a * 255).astype(np.uint8)))
    return out


def shaped(photo):
    """景色: 写真の真ん中の 9 割を、角の丸い形で切り抜く（`StickerCrop.shaped` の角 = 短い辺の 20%）。"""
    w, h = photo.size
    box = (int(w * 0.05), int(h * 0.05), int(w * 0.95), int(h * 0.95))
    crop = photo.convert("RGBA").crop(box)
    cw, ch = crop.size
    k = 4  # なめらかな角のため、大きく描いてから縮める
    m = Image.new("L", (cw * k, ch * k), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, cw * k - 1, ch * k - 1), radius=int(min(cw, ch) * 0.2 * k), fill=255)
    crop.putalpha(m.resize((cw, ch), Image.LANCZOS))
    return crop


def trim(rgba):
    bbox = rgba.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    return rgba.crop(bbox) if bbox else rgba


def scale_to(rgba, long_side):
    w, h = rgba.size
    k = long_side / max(w, h)
    img = rgba.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)
    if k > 1.2:
        # 小さな写真（250px）を大きくした時のぼやけを少し戻す
        rgb = img.convert("RGB").filter(ImageFilter.UnsharpMask(radius=1.6, percent=60, threshold=2))
        rgb.putalpha(img.getchannel("A"))
        img = rgb
    return img


def die_cut(rgba):
    """白いダイカットのふち: 形を丸く太らせ、なめらかにして、白で下に敷く。"""
    w, h = rgba.size
    r = max(4, round(max(w, h) * BORDER))
    pad = r + 6
    canvas = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    canvas.alpha_composite(rgba, (pad, pad))
    inside = np.asarray(canvas.getchannel("A")) > 90
    # 形からの距離が r 以内を白にする（丸い筆で太らせたのと同じ）
    grown = Image.fromarray(((ndimage.distance_transform_edt(~inside) <= r) * 255).astype(np.uint8))
    # 角を丸め、ふちをなめらかに
    grown = grown.filter(ImageFilter.GaussianBlur(r * 0.35)).point(lambda v: 255 if v > 110 else 0)
    grown = grown.filter(ImageFilter.GaussianBlur(1.1))
    white = Image.new("RGBA", canvas.size, (255, 255, 255, 0))
    white.putalpha(grown)
    white.alpha_composite(canvas)
    return trim(white)


def on_tile(rgba):
    """正方形のキャンバスの真ん中に、見た目の面積が TILE_AREA になる大きさで置く（枠からははみ出さない）。"""
    area = (np.asarray(rgba.getchannel("A")) > 128).sum()
    k = (TILE_AREA * TILE * TILE / max(1, area)) ** 0.5
    inner = TILE * (1 - 2 * TILE_MARGIN)
    k = min(k, inner / max(rgba.size))
    w, h = max(1, round(rgba.width * k)), max(1, round(rgba.height * k))
    piece = rgba.resize((w, h), Image.LANCZOS)
    tile = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    tile.alpha_composite(piece, ((TILE - w) // 2, (TILE - h) // 2))
    return tile


def main():
    flat = "--flat" in sys.argv
    cuts = sys.argv[sys.argv.index("--cuts") + 1] if "--cuts" in sys.argv else None
    session = None
    work = tempfile.mkdtemp(prefix="onboarding-stickers-")
    for name, (src, kind) in STICKERS.items():
        path = os.path.join(SOURCES, src + ".webp")
        photo = Image.open(path)
        cached = os.path.join(cuts, src + ".png") if cuts else None
        if kind == "cut" and cached and os.path.exists(cached):
            piece = clean_alpha(Image.open(cached).convert("RGBA"))
        elif kind == "cut":
            if session is None:
                from rembg import new_session

                session = new_session("birefnet-general")
            piece = clean_alpha(cutout(photo, session))
        else:
            piece = shaped(photo)
        piece = scale_to(trim(piece), LONG_SIDE)
        sticker = die_cut(piece)
        sticker.save(os.path.join(work, name + ".png"))
        print("cut", name, sticker.size, flush=True)

    if not flat:
        lit = os.path.join(work, "lit")
        os.makedirs(lit, exist_ok=True)
        subprocess.run([sys.executable, os.path.join(ROOT, "blender", "onboarding_stickers.py"), work, lit], check=True)
        work = lit

    for name in STICKERS:
        img = trim(Image.open(os.path.join(work, name + ".png")).convert("RGBA"))
        if name in INTERESTS:
            img = on_tile(img)
        img.save(os.path.join(OUT, f"onboarding_sticker_{name}.webp"), "WEBP", quality=88, method=6)
        print("wrote", f"onboarding_sticker_{name}.webp", img.size)


if __name__ == "__main__":
    main()
