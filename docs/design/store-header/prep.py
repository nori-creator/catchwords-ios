"""
App Store のヘッダー動画（v2: 実写）の材料を、オーナーが作った横長の写真から作る。

  python prep.py upscale SRC.png MODEL.pb       写真を AI（EDSR ×2）で 3840×1646 に拡大して assets/photo.jpg に（CPU で約 8 分）
  python prep.py objects                        カップ・バイク・黒板を切り抜き（rembg の isnet-general-use）、
                                                assets/objects.json（輪郭・範囲・タグの位置）と、カップの切り抜き
                                                assets/cup_cut.png・白い縁 assets/cup_border.png を書く

使う物: opencv-contrib-python-headless・rembg・onnxruntime（rembg は初回に学習済みモデルを GitHub から取る）。
植木鉢は葉が背景のぼけと混ざって切り抜けないので、アプリの v10 の動画と同じく、光のペンが描くのは 3 つ。
"""

import json
import os
import sys

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "assets")
W, H = 3840, 1646

# 物ごとの切り抜きの範囲（3840×1646 の写真の座標）。rembg は範囲の中のいちばん目立つ物を返す。
BOXES = {
    "cup": (1660, 760, 2080, 1530),
    "scooter": (1400, 500, 2100, 1310),
    "sign": (2380, 840, 2900, 1430),
}
# タグの付け根（物の範囲の中の割合）。アプリのタグと同じく、物の上の点から上へ出る
ANCHOR = {"cup": (0.5, 0.6), "scooter": (0.12, 0.5), "sign": (0.5, 0.42)}


def upscale(src, model):
    sr = cv2.dnn_superres.DnnSuperResImpl_create()
    sr.readModel(model)
    sr.setModel("edsr", 2)
    up = sr.upsample(cv2.imread(src))
    up = cv2.resize(up, (W, H), interpolation=cv2.INTER_LANCZOS4)
    os.makedirs(OUT, exist_ok=True)
    cv2.imwrite(os.path.join(OUT, "photo.jpg"), up, [cv2.IMWRITE_JPEG_QUALITY, 90])


def outline(mask, n=320):
    _, b = cv2.threshold(mask, 127, 255, cv2.THRESH_BINARY)
    cs, _ = cv2.findContours(b, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    c = max(cs, key=cv2.contourArea)[:, 0, :].astype(np.float64)
    k = 6
    c = np.stack([np.convolve(np.r_[c[-k:, i], c[:, i], c[:k, i]], np.ones(2 * k + 1) / (2 * k + 1), "valid") for i in (0, 1)], 1)
    area = 0.5 * np.sum(c[:, 0] * np.roll(c[:, 1], -1) - np.roll(c[:, 0], -1) * c[:, 1])
    if area < 0:
        c = c[::-1]
    c = np.roll(c, -int(np.argmin(c[:, 1] + 0.001 * c[:, 0])), 0)   # 一番上の点から時計回り
    seg = np.hypot(*np.diff(np.r_[c, c[:1]], axis=0).T)
    cum = np.r_[0, np.cumsum(seg)]
    t = np.linspace(0, cum[-1], n, endpoint=False)
    xs, ys = np.interp(t, cum, np.r_[c[:, 0], c[0, 0]]), np.interp(t, cum, np.r_[c[:, 1], c[0, 1]])
    # 曲がり具合（光のペンが曲がり角でゆっくりになる。アプリの v10 と同じ考え）
    pts = np.stack([xs, ys], 1)
    d1 = np.roll(pts, -1, 0) - pts
    d0 = pts - np.roll(pts, 1, 0)
    ang = np.abs(np.arctan2(d0[:, 0] * d1[:, 1] - d0[:, 1] * d1[:, 0], (d0 * d1).sum(1)))
    return [[round(x, 1), round(y, 1)] for x, y in pts], [round(a, 3) for a in ang]


def objects():
    from rembg import new_session, remove

    im = cv2.imread(os.path.join(OUT, "photo.jpg"))
    sess = new_session("isnet-general-use")
    masks = {}
    for k, (x0, y0, x1, y1) in BOXES.items():
        m = np.array(remove(cv2.cvtColor(im[y0:y1, x0:x1], cv2.COLOR_BGR2RGB), session=sess, only_mask=True))
        # 半分透けた所（後ろの物が薄く残る）を捨て、いちばん大きい塊だけ残す
        b = (m > 128).astype(np.uint8)
        n, lab, st, _ = cv2.connectedComponentsWithStats(b)
        b = (lab == 1 + int(np.argmax(st[1:, 4]))).astype(np.uint8) * 255
        full = np.zeros((H, W), np.uint8)
        full[y0:y1, x0:x1] = b
        masks[k] = full
    # バイクは手前のカップの後ろ: カップの分を引く
    masks["scooter"][cv2.dilate(masks["cup"], np.ones((9, 9), np.uint8)) > 100] = 0
    data = {}
    for k, m in masks.items():
        ys, xs = np.where(m > 127)
        box = [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]
        pts, turn = outline(m)
        ax, ay = ANCHOR[k]
        data[k] = {"box": box, "pts": pts, "turn": turn,
                   "anchor": [round(box[0] + ax * (box[2] - box[0])), round(box[1] + ay * (box[3] - box[1]))]}
    # カップの切り抜き（アプリの StickerCrop と同じく物の形）と白い縁（ステッカー）
    x0, y0, x1, y1 = data["cup"]["box"]
    pad = 40
    x0, y0, x1, y1 = x0 - pad, y0 - pad, x1 + pad, y1 + pad
    a = cv2.GaussianBlur(masks["cup"], (3, 3), 0)[y0:y1, x0:x1]
    cut = np.dstack([im[y0:y1, x0:x1], a])
    cv2.imwrite(os.path.join(OUT, "cup_cut.png"), cut)
    r = 22
    border = cv2.GaussianBlur(cv2.dilate(masks["cup"], cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))), (5, 5), 0)[y0:y1, x0:x1]
    cv2.imwrite(os.path.join(OUT, "cup_border.png"), np.dstack([np.full_like(a, 255)] * 3 + [border]))
    data["cup"]["tile"] = [x0, y0, x1 - x0, y1 - y0]
    with open(os.path.join(OUT, "objects.json"), "w") as f:
        json.dump(data, f)
    print({k: v["box"] for k, v in data.items()})


if __name__ == "__main__":
    if sys.argv[1] == "upscale":
        upscale(sys.argv[2], sys.argv[3])
    else:
        objects()
