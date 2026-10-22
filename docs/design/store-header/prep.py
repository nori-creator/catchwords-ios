"""
3D の絵から、重ねる層とステッカーの材料を作る（OpenCV）。

  python prep.py sticker STILL.png MASK.png OUT.png    マグカップを白い縁つきで切り抜く（アプリのステッカー）。
                                                       OUT.json に画面での範囲（0〜1、左下が原点）を書く
  python prep.py outlines MASK_DIR OUT.json            毎コマのマグカップの輪郭（3840×1646 の座標。光のペンが描く）
"""

import json
import os
import sys

import cv2
import numpy as np

W_OUT = 3840


def sticker(still, mask, out):
    rgb = cv2.imread(still, cv2.IMREAD_COLOR)
    m = cv2.imread(mask, cv2.IMREAD_GRAYSCALE)
    m = np.where(m > 127, 255, 0).astype(np.uint8)              # 描画の細かいざらつき（値 1）を捨てる
    h, w = m.shape
    border = round(w * 0.0075)                                  # 1920 幅で 14px の白い縁
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * border + 1, 2 * border + 1))
    cut = cv2.GaussianBlur(m, (3, 3), 0)
    outer = cv2.GaussianBlur(cv2.dilate(m, k), (5, 5), 0)
    a = cut.astype(np.float32)[..., None] / 255
    img = (rgb.astype(np.float32) * a + 255 * (1 - a)).astype(np.uint8)   # 縁は白
    rgba = np.dstack([img, outer])
    ys, xs = np.where(outer > 0)
    pad = 4
    x0, x1, y0, y1 = max(0, xs.min() - pad), min(w, xs.max() + pad + 1), max(0, ys.min() - pad), min(h, ys.max() + pad + 1)
    cv2.imwrite(out, rgba[y0:y1, x0:x1])
    crop = [x0 / w, 1 - y1 / h, x1 / w, 1 - y0 / h]
    json.dump({"crop": crop}, open(out.replace(".png", ".json"), "w"))
    print("sticker", out, crop)


def outline(mask_path, n=260):
    m = cv2.imread(mask_path, cv2.IMREAD_GRAYSCALE)
    s = W_OUT / m.shape[1]
    _, b = cv2.threshold(m, 127, 255, cv2.THRESH_BINARY)
    cs, _ = cv2.findContours(b, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    if not cs:
        return None
    c = max(cs, key=cv2.contourArea)[:, 0, :].astype(np.float64)
    # なめらかに（輪のまま平均）
    k = 5
    c = np.stack([np.convolve(np.r_[c[-k:, i], c[:, i], c[:k, i]], np.ones(2 * k + 1) / (2 * k + 1), "valid") for i in (0, 1)], 1)
    # 時計回りにそろえ、一番上の点から始め、同じ間隔で n 点に
    area = 0.5 * np.sum(c[:, 0] * np.roll(c[:, 1], -1) - np.roll(c[:, 0], -1) * c[:, 1])
    if area < 0:
        c = c[::-1]
    top = np.argmin(c[:, 1] + 0.001 * c[:, 0])
    c = np.roll(c, -top, 0)
    seg = np.hypot(*np.diff(np.r_[c, c[:1]], axis=0).T)
    cum = np.r_[0, np.cumsum(seg)]
    t = np.linspace(0, cum[-1], n, endpoint=False)
    xs = np.interp(t, cum, np.r_[c[:, 0], c[0, 0]])
    ys = np.interp(t, cum, np.r_[c[:, 1], c[0, 1]])
    return [[round(x * s, 1), round(y * s, 1)] for x, y in zip(xs, ys)]


def outlines(d, out):
    files = sorted(f for f in os.listdir(d) if f.startswith("m") and f.endswith(".png"))
    json.dump([outline(os.path.join(d, f)) for f in files], open(out, "w"))
    print("outlines", len(files), "->", out)


if __name__ == "__main__":
    if sys.argv[1] == "sticker":
        sticker(*sys.argv[2:5])
    else:
        outlines(sys.argv[2], sys.argv[3])
