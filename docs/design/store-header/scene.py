"""
App Store の製品ページのヘッダー（21:9）の動画の 3D の骨格（案 A「撮れば、ことばになる」）。

机の上のマグカップと図鑑の本。カメラがゆっくり左右に揺れ（10 秒で 1 往復＝切れ目なくループ）、
マグカップから切り抜いたステッカーがはがれて本へ飛び、本が閉じる。光のペン・タグ・一言は、
この 3D の上に motion/header.html が重ねる（アプリの演出 v10 と同じ書き方）。

使い方（Blender 5.2 の Python モジュール。pip install "bpy==5.2.*"）:
  python scene.py mask   OUT_DIR W [first last]     マグカップだけ白の型（毎コマ。光のペンの輪郭に使う）
  python scene.py frame  OUT_DIR W N SAMPLES        1 コマだけ（ステッカーの元の絵）
  python scene.py main   OUT_DIR W SAMPLES [first last] [STICKER_PNG]   本番の絵
  python scene.py points OUT_DIR W                  毎コマの本の位置など（重ねる層が使う JSON）

素材の質感（机の木目・奥の壁）は今は Blender の中で作る。AI の画像に差し替える時は textures/ に
desk.png・backdrop.png を置く（あれば使う）。
"""

import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, "textures")
FPS, N = 30, 300                       # 10 秒でループ
ASPECT = 1646 / 3840                   # 21:9（3840×1646）

# 時刻（コマ）。重ねる層（motion/header.html）と同じ値。
F_PEEL = 120                           # ステッカーがはがれ始める
F_LIFT = 134
F_LAND = 166                           # 本の頁に着く
F_OPEN = (124, 150)                    # 表紙が開く
F_CLOSE = (176, 198)                   # 表紙が閉じる

# 表紙の内側でのステッカーの置き場（蝶番の座標）。ステッカーの上＝表紙の先（蝶番の +x）、表＝表紙の内側（蝶番の -z）
ON_COVER = Matrix(((0, 1, 0, 0.074), (1, 0, 0, 0.0), (0, 0, -1, -0.0024), (0, 0, 0, 1)))

CUP_AT = Vector((-0.072, 0.0, 0.0))
BOOK_AT = Vector((0.115, 0.085, 0.0))            # 背の真ん中（背は奥。表紙は奥へ起き上がる）
BOOK_ROT = math.radians(-90 - 10)


def srgb(h):
    def lin(c):
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin((h >> 16) & 255), lin((h >> 8) & 255), lin(h & 255), 1.0)


def principled(name, color, rough=0.5, coat=0.0, spec=0.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = color
    b.inputs["Roughness"].default_value = rough
    b.inputs["Specular IOR Level"].default_value = spec
    if coat:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = 0.08
    return m


def assign(o, m):
    o.data.materials.clear()
    o.data.materials.append(m)


def smooth(o):
    for p in o.data.polygons:
        p.use_smooth = True


def lathe(name, profile, seg=96):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = [[bm.verts.new((r * math.cos(2 * math.pi * i / seg), r * math.sin(2 * math.pi * i / seg), z)) for i in range(seg)] for r, z in profile]
    for a, b in zip(rings, rings[1:]):
        for i in range(seg):
            j = (i + 1) % seg
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    smooth(o)
    return o


def box(name, size, loc):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    m = o.modifiers.new("Bevel", "BEVEL")
    m.width, m.segments = min(size) * 0.18, 3
    return o


# ---------------------------------------------------------------- the set


def image_or(name):
    p = os.path.join(TEX, name)
    return bpy.data.images.load(p) if os.path.exists(p) else None


def desk():
    bpy.ops.mesh.primitive_plane_add(size=4, location=(0, 0.8, 0))
    o = bpy.context.active_object
    o.name = "Desk"
    m = bpy.data.materials.new("DeskWood")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.55
    img = image_or("desk.png")
    if img:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = img
        tc = nt.nodes.new("ShaderNodeTexCoord")
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (3, 3, 1)
        nt.links.new(tc.outputs["UV"], mp.inputs["Vector"])
        nt.links.new(mp.outputs["Vector"], t.inputs["Vector"])
        nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    else:
        # 淡いアッシュ材: 細長く引き伸ばしたノイズを、クリームの濃淡に
        tc = nt.nodes.new("ShaderNodeTexCoord")
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (2.0, 60.0, 2.0)
        nz = nt.nodes.new("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = 6.0
        nz.inputs["Detail"].default_value = 8.0
        nz.inputs["Distortion"].default_value = 0.6
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = srgb(0xE6D6BC)
        ramp.color_ramp.elements[1].color = srgb(0xF4EADA)
        nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
        nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
        nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    assign(o, m)
    return o


def backdrop():
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 1.3, 0.5), rotation=(math.radians(90), 0, 0))
    o = bpy.context.active_object
    o.name = "Backdrop"
    o.scale = (4.5, 2.2, 1)
    m = bpy.data.materials.new("Backdrop")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 1.15
    img = image_or("backdrop.png")
    if img:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = img
        nt.links.new(t.outputs["Color"], em.inputs["Color"])
    else:
        # クリームの壁: 左上の窓の光から右下へ、ほんのり淡いネイビーへ
        tc = nt.nodes.new("ShaderNodeTexCoord")
        g = nt.nodes.new("ShaderNodeTexGradient")
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Rotation"].default_value = (0, 0, math.radians(-18))
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = srgb(0xFFF7EA)
        ramp.color_ramp.elements[1].color = srgb(0xDCE3EF)
        ramp.color_ramp.elements.new(0.6).color = srgb(0xF6ECDC)
        nt.links.new(tc.outputs["UV"], mp.inputs["Vector"])
        nt.links.new(mp.outputs["Vector"], g.inputs["Vector"])
        nt.links.new(g.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], nt.nodes["Material Output"].inputs["Surface"])
    assign(o, m)
    # ぼけて丸い光になる小さい玉（窓の光の反射）
    glow = bpy.data.materials.new("Bokeh")
    glow.use_nodes = True
    gn = glow.node_tree
    gn.nodes.remove(gn.nodes["Principled BSDF"])
    e2 = gn.nodes.new("ShaderNodeEmission")
    e2.inputs["Color"].default_value = srgb(0xFFF4DE)
    e2.inputs["Strength"].default_value = 2.2
    gn.links.new(e2.outputs["Emission"], gn.nodes["Material Output"].inputs["Surface"])
    for x, z, r, col in ((-0.62, 0.42, 0.018, 0xFFF4DE), (-0.48, 0.55, 0.012, 0xFFF4DE), (0.55, 0.38, 0.016, 0xBFD8FF),
                         (0.70, 0.52, 0.011, 0xFFF4DE), (-0.30, 0.62, 0.009, 0xBFD8FF), (0.38, 0.60, 0.010, 0xFFF4DE)):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(x, 1.25, z * 0.7))
        s = bpy.context.active_object
        mm = glow.copy()
        mm.node_tree.nodes["Emission"].inputs["Color"].default_value = srgb(col)
        assign(s, mm)
    return o


def props():
    """奥のぼけた小物: 左に本の束、右に植木鉢（形が分かるくらいでよい。ピントは手前）。"""
    for i, (w, d, h, col, rz) in enumerate(((0.24, 0.17, 0.028, 0x1F2F57, 4), (0.22, 0.16, 0.024, 0xEDE3D0, -3), (0.21, 0.15, 0.026, 0x9DB8E0, 6))):
        z = sum(x[2] for x in ((0.24, 0.17, 0.028), (0.22, 0.16, 0.024), (0.21, 0.15, 0.026))[:i]) + h / 2
        o = box(f"Stack{i}", (w, d, h), (-0.40, 0.62, z))
        o.rotation_euler[2] = math.radians(rz)
        assign(o, principled(f"Stack{i}", srgb(col), 0.7))
    pot = lathe("Pot", [(0.001, 0.0), (0.05, 0.0), (0.062, 0.11), (0.058, 0.115), (0.001, 0.112)], 64)
    pot.location = (0.40, 0.70, 0)
    assign(pot, principled("Pot", srgb(0xF2EBDF), 0.6))
    leaf = principled("Leaf", srgb(0x4E8F5A), 0.45)
    import random
    rnd = random.Random(7)
    for i in range(16):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(0.0, 0.07)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.035, location=(0.40 + r * math.cos(a), 0.70 + r * math.sin(a), 0.12 + rnd.uniform(0, 0.07)))
        l = bpy.context.active_object
        l.scale = (1.0, 0.45, 0.18)
        l.rotation_euler = (rnd.uniform(-0.6, 0.6), rnd.uniform(-0.6, 0.6), a)
        smooth(l)
        assign(l, leaf)


def mug():
    """白い磁器のマグカップ。口から少し下に、アプリの青の帯。"""
    body = lathe("Mug", [(0.001, 0.0), (0.036, 0.0), (0.0405, 0.004), (0.042, 0.090), (0.0412, 0.0925), (0.0385, 0.0905),
                         (0.0375, 0.012), (0.001, 0.011)])
    m = bpy.data.materials.new("Glaze")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.18
    b.inputs["Coat Weight"].default_value = 0.6
    b.inputs["Coat Roughness"].default_value = 0.05
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sx = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    els = ramp.color_ramp.elements
    els[0].color = srgb(0xFBF8F2)
    els[1].position, els[1].color = 0.80, srgb(0xFBF8F2)
    e = els.new(0.70)
    e.color = srgb(0x2F7FE0)
    mp = nt.nodes.new("ShaderNodeMath")
    mp.operation = "DIVIDE"
    mp.inputs[1].default_value = 0.095
    nt.links.new(tc.outputs["Object"], sx.inputs["Vector"])
    nt.links.new(sx.outputs["Z"], mp.inputs[0])
    r2 = nt.nodes.new("ShaderNodeVectorMath")
    r2.operation = "LENGTH"
    xy = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(sx.outputs["X"], xy.inputs["X"])
    nt.links.new(sx.outputs["Y"], xy.inputs["Y"])
    nt.links.new(xy.outputs["Vector"], r2.inputs[0])
    outside = nt.nodes.new("ShaderNodeMath")
    outside.operation = "GREATER_THAN"
    outside.inputs[1].default_value = 0.0398
    nt.links.new(r2.outputs["Value"], outside.inputs[0])
    only = nt.nodes.new("ShaderNodeMath")
    only.operation = "MULTIPLY"
    nt.links.new(mp.outputs[0], only.inputs[0])
    nt.links.new(outside.outputs[0], only.inputs[1])
    nt.links.new(only.outputs[0], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    assign(body, m)
    # 取っ手: 縦のトーラスの、胴の外に出る半分
    bpy.ops.mesh.primitive_torus_add(major_radius=0.026, minor_radius=0.0062, major_segments=64, minor_segments=24,
                                     location=(0.046, 0, 0.050), rotation=(math.radians(90), 0, 0))
    h = bpy.context.active_object
    h.name = "Handle"
    h.scale = (0.85, 1.0, 1.0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bm = bmesh.new()
    bm.from_mesh(h.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.x + 0.046 < 0.040], context="VERTS")
    bm.to_mesh(h.data)
    bm.free()
    smooth(h)
    assign(h, m)
    h.parent = body
    body.location = CUP_AT
    body.rotation_euler[2] = math.radians(-35)        # 取っ手は右手前
    return body, h


def book():
    """図鑑の本（アプリの DexBook と同じ青い布張り）。平らに置き、背は奥。表紙は背を軸に奥へ起き上がる。"""
    cloth = principled("Cloth", srgb(0x2F7FE0), 0.78)
    paper = principled("Page", srgb(0xFBF6EC), 0.95)
    label = principled("Label", srgb(0xFFFFFF), 0.8)
    w, d, t, board = 0.145, 0.20, 0.034, 0.0035
    root = bpy.data.objects.new("Book", None)
    bpy.context.collection.objects.link(root)
    back = box("BookBack", (w, d, board), (w / 2, 0, board / 2))
    assign(back, cloth)
    pages = box("BookPages", (w - 0.007, d - 0.008, t - 2 * board - 0.002), ((w - 0.007) / 2 + 0.002, 0, t / 2 - 0.001))
    assign(pages, paper)
    bpy.ops.mesh.primitive_cylinder_add(radius=t / 2, depth=d, vertices=48, location=(0, 0, t / 2), rotation=(math.radians(90), 0, 0))
    spine = bpy.context.active_object
    spine.name = "BookSpine"
    bm = bmesh.new()
    bm.from_mesh(spine.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.x > 0.0005], context="VERTS")
    bm.to_mesh(spine.data)
    bm.free()
    sol = spine.modifiers.new("S", "SOLIDIFY")
    sol.thickness = board
    smooth(spine)
    assign(spine, cloth)
    hinge = bpy.data.objects.new("Hinge", None)
    bpy.context.collection.objects.link(hinge)
    hinge.location = (0, 0, t - board / 2)
    cover = box("BookCover", (w, d, board), (w / 2, 0, 0))
    assign(cover, cloth)
    cover.parent = hinge
    lab = box("BookLabel", (0.085, 0.06, 0.0004), (w * 0.55, d * 0.12, board / 2 + 0.0002))
    lab.modifiers.clear()
    assign(lab, label)
    lab.parent = hinge
    for o in (back, pages, spine, hinge):
        o.parent = root
    root.location = BOOK_AT
    root.rotation_euler[2] = BOOK_ROT
    hinge.rotation_mode = "XYZ"
    ease = lambda u: u * u * (3 - 2 * u)
    for f in range(N):
        if f < F_OPEN[0] or f >= F_CLOSE[1]:
            a = 0.0
        elif f < F_OPEN[1]:
            a = ease((f - F_OPEN[0]) / (F_OPEN[1] - F_OPEN[0]))
        elif f < F_CLOSE[0]:
            a = 1.0
        else:
            a = 1 - ease((f - F_CLOSE[0]) / (F_CLOSE[1] - F_CLOSE[0]))
        hinge.rotation_euler = (0, -math.radians(112) * a, 0)
        hinge.keyframe_insert("rotation_euler", frame=f)
    page_top = Vector((w * 0.52, 0, t - board - 0.0008))
    return root, hinge, page_top


# ---------------------------------------------------------------- camera & light


def camera():
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 58
    cam_data.sensor_fit = "HORIZONTAL"
    cam_data.sensor_width = 36
    cam_data.dof.use_dof = True
    cam_data.dof.aperture_fstop = 1.2
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    target = Vector((0.018, 0.0, 0.080))
    cam_data.dof.focus_distance = 1.80
    for f in range(N):
        p = 2 * math.pi * f / N
        loc = Vector((0.018 + 0.06 * math.sin(p), -1.75, 0.36 + 0.008 * math.sin(2 * p)))
        cam.location = loc
        cam.rotation_euler = (target + Vector((0.010 * math.sin(p), 0, 0)) - loc).to_track_quat("-Z", "Y").to_euler()
        cam.keyframe_insert("location", frame=f)
        cam.keyframe_insert("rotation_euler", frame=f)
    bpy.context.scene.camera = cam
    return cam


def lights():
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 4.6
    sun.angle = math.radians(6)
    sun.color = (1.0, 0.93, 0.82)
    so = bpy.data.objects.new("Sun", sun)
    bpy.context.collection.objects.link(so)
    so.rotation_euler = (math.radians(52), math.radians(-28), math.radians(-30))
    fill = bpy.data.lights.new("Fill", "AREA")
    fill.energy = 40
    fill.size = 1.2
    fill.color = (0.86, 0.91, 1.0)
    fo = bpy.data.objects.new("Fill", fill)
    bpy.context.collection.objects.link(fo)
    fo.location = (0.7, -0.9, 0.7)
    fo.rotation_euler = (Vector((0, 0, 0.05)) - fo.location).to_track_quat("-Z", "Y").to_euler()
    w = bpy.data.worlds.new("World")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = srgb(0xF3EADB)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.32
    bpy.context.scene.world = w


# ---------------------------------------------------------------- the sticker


def sticker(cam, page_top, book_root, png, crop):
    """マグカップを切り抜いたステッカー。F_PEEL の時、画面の上でマグカップにぴったり重なる板として出て、
    持ち上がり、弧を描いて、起き上がった表紙の内側に貼り付く。crop: 切り抜きの範囲（画面の 0〜1、左下が原点）。"""
    sc = bpy.context.scene
    sc.frame_set(F_PEEL)
    img = bpy.data.images.load(png)
    u0, v0, u1, v1 = crop
    depth = 1.70                                       # マグカップより少し手前
    hw = depth * (cam.data.sensor_width / 2) / cam.data.lens
    hh = hw * ASPECT
    cx, cy = (u0 + u1) - 1, (v0 + v1) - 1              # -1..1
    sx, sy = (u1 - u0) * hw * 2, (v1 - v0) * hh * 2
    bpy.ops.mesh.primitive_plane_add(size=1)
    o = bpy.context.active_object
    o.name = "Sticker"
    o.scale = (sx, sy, 1)
    bpy.ops.object.transform_apply(scale=True)
    m = bpy.data.materials.new("Sticker")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    # 描いた絵をそのまま光らせ（元のマグカップと同じ色）、光沢の反射だけ足す。縁の外は透明
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = img
    t.extension = "CLIP"
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 2 ** 1.15          # 露出（-1.15）の分を戻す
    nt.links.new(t.outputs["Color"], em.inputs["Color"])
    gl = nt.nodes.new("ShaderNodeBsdfGlossy")
    gl.inputs["Roughness"].default_value = 0.25
    gl.inputs["Color"].default_value = (0.06, 0.06, 0.06, 1)
    add = nt.nodes.new("ShaderNodeAddShader")
    nt.links.new(em.outputs[0], add.inputs[0])
    nt.links.new(gl.outputs[0], add.inputs[1])
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(t.outputs["Alpha"], mix.inputs["Fac"])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(add.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    o.visible_shadow = True
    assign(o, m)
    o.rotation_mode = "QUATERNION"
    cm = cam.matrix_world.copy()
    start_loc = cm @ Vector((cx * hw, cy * hh, -depth))
    start_q = cm.to_quaternion()
    # 起き上がった表紙の内側に貼り付き、表紙と一緒に閉じる（頁に寝かせると、低い視点では線にしか見えない）
    hinge = bpy.data.objects["Hinge"]
    land_scale = 0.10 / sy
    keys = [
        (F_PEEL - 1, start_loc, start_q, 0.0),
        (F_PEEL, start_loc, start_q, 1.0),
        (F_PEEL + 4, start_loc + Vector((0, -0.01, 0.004)), start_q, 1.05),
    ]
    sc.frame_set(F_LAND)
    land_m = hinge.matrix_world @ ON_COVER
    land_loc, land_q = land_m.to_translation(), land_m.to_quaternion()
    # ピントの面（マグカップの距離）から離れないように、手前へは出さず、少し奥へ持ち上げる
    lift_loc = start_loc + Vector((0.0, 0.05, 0.075))
    mid_loc = (lift_loc + land_loc) / 2 + Vector((0, 0.0, 0.07))
    keys += [
        (F_LIFT, lift_loc, start_q.slerp(land_q, 0.15), 0.95),
        ((F_LIFT + F_LAND) // 2, mid_loc, start_q.slerp(land_q, 0.65), 0.95 * 0.5 + land_scale * 0.5),
    ]
    for f in range(F_LAND, F_CLOSE[1] + 3):
        sc.frame_set(f)
        m = hinge.matrix_world @ ON_COVER
        keys.append((f, m.to_translation(), m.to_quaternion(), land_scale))
    keys.append((F_CLOSE[1] + 3, keys[-1][1], keys[-1][2], 0.0))
    for f, loc, q, s in keys:
        o.location, o.rotation_quaternion, o.scale = loc, q, (s, s, s)
        for p in ("location", "rotation_quaternion", "scale"):
            o.keyframe_insert(p, frame=f)
    return o


# ---------------------------------------------------------------- build & modes


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.frame_start, sc.frame_end = 0, N - 1
    desk()
    backdrop()
    props()
    cup, handle = mug()
    root, hinge, page_top = book()
    cam = camera()
    lights()
    # Standard: ステッカー（描いた絵をそのまま光らせる板）が元のマグカップと同じ色に見えるように
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = -1.15
    return cam, cup, handle, root, page_top


def setup_render(width, samples, transparent=False):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = samples > 1
    sc.cycles.max_bounces = 6
    sc.render.resolution_x = width
    sc.render.resolution_y = round(width * ASPECT)
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = transparent
    sc.render.image_settings.file_format = "PNG"


def mask_mode(cup, handle):
    """マグカップだけを白、他は黒（光のペンの輪郭と、ステッカーの切り抜きに使う）。"""
    white = bpy.data.materials.new("MaskWhite")
    white.use_nodes = True
    nt = white.node_tree
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs["Color"].default_value = (1, 1, 1, 1)
    nt.links.new(e.outputs["Emission"], nt.nodes["Material Output"].inputs["Surface"])
    for o in bpy.data.objects:
        if o.type == "MESH":
            if o in (cup, handle):
                assign(o, white)
            else:
                o.is_holdout = True
    for o in bpy.data.objects:
        if o.type == "LIGHT":
            o.hide_render = True
    bpy.context.scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    bpy.context.scene.camera.data.dof.use_dof = False   # 輪郭はくっきり（マグカップにピントが合っている）
    bpy.context.scene.view_settings.view_transform = "Standard"
    bpy.context.scene.view_settings.look = "None"


def render_frames(out, first, last, pattern="f%04d.png"):
    sc = bpy.context.scene
    os.makedirs(out, exist_ok=True)
    for f in range(first, last + 1):
        path = os.path.join(out, pattern % f)
        if os.path.exists(path):
            continue
        sc.frame_set(f)
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("frame", f, flush=True)


def main():
    mode, out, width = sys.argv[1], sys.argv[2], int(sys.argv[3])
    rest = sys.argv[4:]
    cam, cup, handle, root, page_top = build()
    if mode == "mask":
        setup_render(width, 1)
        mask_mode(cup, handle)
        first, last = (int(rest[0]), int(rest[1])) if len(rest) >= 2 else (0, N - 1)
        render_frames(out, first, last, "m%04d.png")
    elif mode == "frame":
        f, samples = int(rest[0]), int(rest[1])
        setup_render(width, samples)
        render_frames(out, f, f, "still%04d.png")
    elif mode == "main":
        samples = int(rest[0])
        first, last = (int(rest[1]), int(rest[2])) if len(rest) >= 3 else (0, N - 1)
        if len(rest) >= 4:
            meta = json.load(open(rest[3].replace(".png", ".json")))
            sticker(cam, page_top, root, rest[3], meta["crop"])
        setup_render(width, samples)
        render_frames(out, first, last)
    elif mode == "points":
        sc = bpy.context.scene
        from bpy_extras.object_utils import world_to_camera_view
        pts = []
        for f in range(N):
            sc.frame_set(f)
            on = (bpy.data.objects["Hinge"].matrix_world @ ON_COVER).to_translation()
            p = world_to_camera_view(sc, cam, on)
            pts.append({"cover": [p.x, 1 - p.y]})
        with open(os.path.join(out, "points.json"), "w") as fh:
            json.dump(pts, fh)
    else:
        raise SystemExit("mode?")


if __name__ == "__main__":
    main()
