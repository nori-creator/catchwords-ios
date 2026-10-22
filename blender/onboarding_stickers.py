"""
初回案内のステッカーに Blender で光を当てる（scripts/onboarding_stickers.py から呼ばれる）。

白いふち付きの平らなステッカー（PNG）を、ほんの少し反ったビニールの板として置き、上から撮る。
- 色は写真のまま（放射＝Emission で描き、表示の色変換は Standard）。光は「つや」だけに足す。
- 左上の大きな柔らかい光で、反りに沿ったつやの帯が出る。影は焼き込まない（画面で浮かせて動かすため、影は SwiftUI が描く）。
- 背景は透明（Film › Transparent）。

使い方: python blender/onboarding_stickers.py <平らなPNGのフォルダ> <書き出すフォルダ>
（Blender 4.5 LTS / 5.x の Python モジュール版 bpy。GPU は要らない: Cycles の CPU で描く）
"""

import glob
import math
import os
import sys

import bpy


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    scene.world = world
    return scene


def sticker_material(image):
    mat = bpy.data.materials.new("Sticker")
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    for n in list(nodes):
        nodes.remove(n)
    out = nodes.new("ShaderNodeOutputMaterial")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Cubic"
    tex.extension = "CLIP"
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.0
    links.new(tex.outputs["Color"], emit.inputs["Color"])
    # つや: ビニールのような、少しぼけた映り込み（色は足さない白）
    gloss = nodes.new("ShaderNodeBsdfGlossy")
    gloss.inputs["Roughness"].default_value = 0.32
    gloss.inputs["Color"].default_value = (1, 1, 1, 1)
    fres = nodes.new("ShaderNodeLayerWeight")
    fres.inputs["Blend"].default_value = 0.35
    scale = nodes.new("ShaderNodeMath")
    scale.operation = "MULTIPLY"
    scale.inputs[1].default_value = 0.8
    links.new(fres.outputs["Facing"], scale.inputs[0])
    mix_gloss = nodes.new("ShaderNodeMixShader")
    links.new(scale.outputs[0], mix_gloss.inputs["Fac"])
    links.new(emit.outputs[0], mix_gloss.inputs[1])
    add = nodes.new("ShaderNodeAddShader")
    links.new(emit.outputs[0], add.inputs[0])
    links.new(gloss.outputs[0], add.inputs[1])
    links.new(add.outputs[0], mix_gloss.inputs[2])
    # 透明な所は透明に
    transp = nodes.new("ShaderNodeBsdfTransparent")
    mix_alpha = nodes.new("ShaderNodeMixShader")
    links.new(tex.outputs["Alpha"], mix_alpha.inputs["Fac"])
    links.new(transp.outputs[0], mix_alpha.inputs[1])
    links.new(mix_gloss.outputs[0], mix_alpha.inputs[2])
    links.new(mix_alpha.outputs[0], out.inputs["Surface"])
    return mat


def render_one(src, dst):
    scene = reset()
    image = bpy.data.images.load(src)
    image.alpha_mode = "STRAIGHT"
    w, h = image.size
    aspect = w / h
    sx, sy = (1.0, 1.0 / aspect) if aspect >= 1 else (aspect, 1.0)

    bpy.ops.mesh.primitive_grid_add(x_subdivisions=64, y_subdivisions=64, size=2)
    plane = bpy.context.active_object
    plane.scale = (sx, sy, 1)
    bpy.ops.object.transform_apply(scale=True)
    plane.data.materials.append(sticker_material(image))
    # 少しだけ反らせる（横方向にゆるい弧、右下の角はほんの少し浮く: はがしかけの感じ）
    for v in plane.data.vertices:
        x, y = v.co.x, v.co.y
        v.co.z = 0.05 * (x * x) + 0.035 * max(0.0, x - 0.55 * sx) * max(0.0, -y - 0.45 * sy) / max(0.01, 0.45 * sx * 0.55 * sy)
    bpy.ops.object.shade_smooth()

    # 真上から、ゆがみの無いカメラ（正投影）で、絵と同じ縦横比のまま撮る
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.0 * max(sx, sy) * 1.08
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = (0, 0, 5)
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.resolution_x = round(w * 1.08)
    scene.render.resolution_y = round(h * 1.08)
    scene.render.resolution_percentage = 100

    # 左上の大きな柔らかい光（つやの帯）と、右下の弱い返し
    key = bpy.data.lights.new("Key", "AREA")
    key.energy = 1400
    key.size = 3.0
    key_obj = bpy.data.objects.new("Key", key)
    key_obj.location = (-2.6, 2.4, 3.2)
    key_obj.rotation_euler = (math.radians(-38), math.radians(-40), 0)
    scene.collection.objects.link(key_obj)
    rim = bpy.data.lights.new("Rim", "AREA")
    rim.energy = 160
    rim.size = 2.0
    rim_obj = bpy.data.objects.new("Rim", rim)
    rim_obj.location = (2.4, -2.2, 2.6)
    rim_obj.rotation_euler = (math.radians(40), math.radians(40), 0)
    scene.collection.objects.link(rim_obj)

    scene.render.filepath = dst
    bpy.ops.render.render(write_still=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    src_dir, out_dir = args[0], args[1]
    os.makedirs(out_dir, exist_ok=True)
    for src in sorted(glob.glob(os.path.join(src_dir, "*.png"))):
        name = os.path.basename(src)
        render_one(os.path.abspath(src), os.path.abspath(os.path.join(out_dir, name)))
        print("lit", name, flush=True)


if __name__ == "__main__":
    main()
