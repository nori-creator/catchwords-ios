"""Builds the Android launcher icons and the Play Store icon from the iOS app icon (same brand mark)."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "ios/CatchWords/Assets.xcassets/AppIcon.appiconset/icon.png"
RES = ROOT / "android/app/src/main/res"
STORE = ROOT / "docs/play-store"

src = Image.open(SRC).convert("RGBA")

# Legacy launcher icons (pre-Android 8): square with rounded corners, and round.
legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
for density, size in legacy.items():
    out = RES / f"mipmap-{density}"
    out.mkdir(parents=True, exist_ok=True)
    img = src.resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=size // 5, fill=255)
    sq = Image.new("RGBA", (size, size), (0, 0, 0, 0)); sq.paste(img, (0, 0), mask)
    sq.save(out / "ic_launcher.png")
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
    rd = Image.new("RGBA", (size, size), (0, 0, 0, 0)); rd.paste(img, (0, 0), mask)
    rd.save(out / "ic_launcher_round.png")

# Adaptive icon background layer: the full-bleed icon at 108dp (432px at xxxhdpi); the mark sits inside the safe zone.
fg = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
for density, size in fg.items():
    src.resize((size, size), Image.LANCZOS).save(RES / f"mipmap-{density}" / "ic_launcher_art.png")

STORE.mkdir(parents=True, exist_ok=True)
src.convert("RGB").resize((512, 512), Image.LANCZOS).save(STORE / "icon-512.png")
print("ok")
