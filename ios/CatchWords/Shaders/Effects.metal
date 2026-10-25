// SwiftUI shader effects (iOS 17+): used with .colorEffect / .layerEffect.
// Compiled into the app's default Metal library; called as ShaderLibrary.<name>.
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float a = hash21(i), b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1)), d = hash21(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// Background dissolve: the photo breaks into glowing dust from the top down.
/// progress 0 = untouched, 1 = gone. `size` is the view size in points.
[[ stitchable ]] half4 dissolve(float2 position, half4 color, float2 size, float progress) {
    float2 uv = position / max(size, float2(1));
    float n = valueNoise(uv * 16.0) * 0.65 + valueNoise(uv * 60.0) * 0.35;
    float front = progress * 1.35 - 0.2;
    float d = (n * 0.55 + uv.y * 0.45) - front;
    if (d < 0.0) { return half4(0.0); }
    float glow = smoothstep(0.07, 0.0, d);
    half3 ember = half3(0.62, 0.95, 1.0) * color.a;
    half3 rgb = mix(color.rgb, ember * 1.4h, half(glow));
    return half4(rgb, color.a);
}

/// Sticker outline traced around a cut-out subject (transparent background).
/// - progress: 0→1 how much of the outline is drawn, going round from the top (like scissors).
/// - width: outline width in points. - solid: 0 = glowing trace, 1 = plain white sticker edge.
[[ stitchable ]] half4 outline(float2 position, SwiftUI::Layer layer, float2 size, float progress, float width, float solid) {
    half4 here = layer.sample(position);
    float outside = 0.0;
    for (int i = 0; i < 16; i++) {
        float a = float(i) / 16.0 * 6.2831853;
        float2 o = float2(cos(a), sin(a)) * width;
        outside = max(outside, float(layer.sample(position + o).a));
    }
    float ring = saturate(outside - float(here.a));
    if (ring <= 0.001) { return here; }

    float2 c = size * 0.5;
    float2 v = position - c;
    // Angle measured clockwise from 12 o'clock, 0…1.
    float ang = fract((atan2(v.x, -v.y) / 6.2831853) + 1.0);
    float drawn = step(ang, progress);
    // Bright "blade" at the head of the trace.
    float head = exp(-pow((ang - progress) * 40.0, 2.0)) * (1.0 - solid);

    half3 trace = mix(half3(0.55, 0.93, 1.0), half3(1.0), half(solid));
    float alpha = ring * max(drawn, float(head));
    half3 rgb = trace * half(alpha) + half3(1.0) * half(head * ring);
    // Composite the ring under the subject (premultiplied).
    return half4(rgb, half(alpha)) * (1.0h - here.a) + here;
}

static float3 hueRGB(float h) {
    return saturate(abs(fract(h + float3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0);
}

/// Holographic foil for the trading-card style cards (`Holographic.swift`), drawn on a plain rectangle laid
/// over the card. Rainbow bands run diagonally and slide with the light; they glow brightest along a soft
/// "light line" that follows the tilt, with a thin sheen in its middle and fine glitter that winks on and
/// off as the card turns.
/// - size: view size in points. - tilt: -1…1 (x = left/right, y = toward/away). - strength: 0…1.
/// - pass: 0 = colour-dodge layer (rainbow + sheen; brightens the photo, leaves white paper white),
///         1 = normal layer (faint pastel wash so the white parts shimmer too, plus the glitter).
/// Output is premultiplied, so an unblended layer still reads as a light tint, never a dark film.
[[ stitchable ]] half4 holoFoil(float2 position, half4 color, float2 size, float2 tilt, float strength, float pass) {
    float2 s = max(size, float2(1.0));
    float2 uv = position / s;
    // Diagonal coordinate (top-left → bottom-right), corrected for the card's tall shape.
    float diag = (uv.x * s.x + uv.y * s.y) / (s.x + s.y);
    float across = (uv.x * s.x - uv.y * s.y) / (s.x + s.y);

    // Where the light hits, moved by the tilt.
    float light = 0.5 + tilt.x * 0.42 + tilt.y * 0.32;
    float dl = diag - light;
    float near = exp(-(dl * 2.6) * (dl * 2.6));
    float sheen = exp(-(dl * 11.0) * (dl * 11.0));

    // Rainbow bands: hue runs along the diagonal and shifts with the tilt; a little waviness across.
    float hue = diag * 1.7 + tilt.x * 0.55 - tilt.y * 0.35 + sin(across * 9.0 + tilt.y * 2.0) * 0.04;
    float3 rainbow = hueRGB(fract(hue));
    float st = saturate(strength);

    if (pass < 0.5) {
        // Colour-dodge layer: stronger near the light line, faint elsewhere.
        float a = st * (0.10 + 0.50 * near) + sheen * 0.35 * st;
        float3 c = mix(rainbow, float3(1.0), sheen * 0.6);
        return half4(half3(c * a), half(a)) * color.a;
    }

    // Normal layer: pastel wash + glitter.
    float wash = st * (0.04 + 0.10 * near);
    float3 pastel = mix(float3(1.0), rainbow, 0.55);

    // Glitter: one candidate glint per 6pt cell; about 1 in 14 cells holds one, and each winks as the
    // tilt sweeps through its own phase.
    float2 cellSize = float2(6.0);
    float2 cell = floor(position / cellSize);
    float h = hash21(cell);
    float h2 = hash21(cell + 17.0);
    float2 inCell = fract(position / cellSize) - 0.5 - (float2(h, h2) - 0.5) * 0.5;
    float spot = exp(-dot(inCell, inCell) * 60.0);
    float phase = fract(h2 * 7.0 + tilt.x * 1.3 + tilt.y * 1.7);
    float wink = smoothstep(0.35, 0.5, phase) * (1.0 - smoothstep(0.5, 0.65, phase));
    float glint = step(0.93, h) * spot * wink * st * (0.35 + 0.65 * near);

    float a = saturate(wash + glint * 0.9 + sheen * 0.10 * st);
    float3 c = pastel * wash + float3(1.0) * (glint * 0.9 + sheen * 0.10 * st);
    return half4(half3(c), half(a)) * color.a;
}

// Card catch: CSS `filter: brightness(amount)` — multiplies the colour (premultiplied, so it is clamped
// to the alpha), which SwiftUI's additive `.brightness` cannot do. formLight's piece goes to brightness(3).
[[ stitchable ]] half4 ccBrightness(float2 position, half4 color, float amount) {
    half3 rgb = min(color.rgb * half(amount), half3(color.a));
    return half4(rgb, color.a);
}

/// 「作り直す」 (owner 2026-10-16, after a reference video): the section's old content breaks into fine grains from left
/// to right, which drift right and a little up into a cloud while the right side is still whole; the cloud swirls
/// gently while the new content is being written, then the new content gathers back out of it from left to right.
/// The grains carry the content's own colours (each shows the bit of the content it flew from).
/// - size: the content's size in points. - out: 0…1 how far the old content has gone. - back: 0…1 how far the new
///   content has come back. - time: seconds, for the swirl.
/// Used with `.layerEffect(…, maxSampleOffset: RegenDust.reach)`.
[[ stitchable ]] half4 regenDust(float2 position, SwiftUI::Layer layer, float2 size, float out, float back, float time) {
    const float grain = 2.0;            // points: one grain
    const float spread = 0.35;          // how ragged the front is (share of the width)
    const float soft = 0.5;             // how long one grain takes to fly (share of the sweep)
    float2 cell = floor(position / grain);
    float r1 = hash21(cell), r2 = hash21(cell + 17.31), r3 = hash21(cell + 41.77), r4 = hash21(cell + 73.13);
    float x = position.x / max(size.x, 1.0);
    float start = x + r1 * spread;
    float gone = saturate((out * (1.0 + spread + soft) - start) / soft);
    float returned = saturate((back * (1.0 + spread + soft) - start) / soft);
    float flight = gone * (1.0 - returned);
    if (flight <= 0.0) { return layer.sample(position); }
    // Where this grain's bit of content came from: to its left and a little below (it drifts right and up), and a
    // slow swirl once it is in the cloud.
    float f = pow(flight, 1.4);
    float2 drift = float2(28.0 + 64.0 * r2, -(6.0 + 34.0 * r3)) * f;
    float2 swirl = float2(sin(time * 1.3 + r4 * 6.2832), cos(time * 1.1 + r2 * 6.2832)) * 5.0 * flight;
    float2 from = position - drift - swirl;
    // Fine grains, not blocks: a dot in each cell that shrinks a little as it flies; some grains fade on the way.
    float2 inCell = fract(position / grain) - 0.5;
    float radius = 0.5 - 0.08 * flight;
    if (length(inCell) > radius) { return half4(0.0); }
    if (r4 < flight * 0.3) { return half4(0.0); }
    return layer.sample(from);
}

// MARK: - The diary book on a wide screen (iPhone Duo, 2026-10-25)

/// Paper grain: a faint, fixed speckle on a page (`PaperSurface`), so a flat colour reads as paper. Each point gets its
/// own lighter or darker step (`strength` of 0.03 ≈ ±1.5 %), plus a slow, larger mottling; nothing moves.
[[ stitchable ]] half4 paperGrain(float2 position, half4 color, float strength) {
    float fine = hash21(floor(position * 1.0)) - 0.5;
    float coarse = valueNoise(position / 38.0) - 0.5;
    float g = fine * strength + coarse * strength * 0.9;
    return half4(color.rgb + half3(g) * color.a, color.a);
}

static bool curlInLeaf(float2 s, float2 size, float spine) {
    return s.x >= spine && s.x <= size.x && s.y >= 0.0 && s.y <= size.y;
}

static half4 curlSample(SwiftUI::Layer layer, float2 s, float2 size, float mirror) {
    float2 q = mirror > 0.5 ? float2(size.x - s.x, s.y) : s;
    return layer.sample(q);
}

/// A page turned like paper (`PageCurl`): the leaf leaves the page along a fold line and rolls round a cylinder of
/// `radius`, its back coming over on top and lying flat beyond. The layer is the whole spread: its right half is the
/// leaf's front (the page being turned), its left half the leaf's back (the page that will lie on the left once it has
/// landed), drawn at that final place — the back of the leaf at distance d from the spine is that page at distance d on
/// the other side. Everything else the layer holds is never shown; where the leaf is not, the spread under it shows
/// through, darkened by the leaf's shadow.
/// - size: the spread in points. - fold: a point of the fold line. - dir: unit vector across the fold, towards the
///   lifted edge. - spine: the spine's x. - mirror: 1 turns the other way (the left page back to the right): the same
///   geometry on the spread seen in a mirror.
/// Used with `.layerEffect(…, maxSampleOffset: .zero)`: the back is sampled up to a spread's width away, but always
/// inside the layer's own bounds.
[[ stitchable ]] half4 pageCurl(float2 position, SwiftUI::Layer layer, float2 size, float2 fold, float2 dir,
                                float radius, float spine, float mirror) {
    const float PI = 3.14159265;
    float2 p = mirror > 0.5 ? float2(size.x - position.x, position.y) : position;
    float r = max(radius, 0.0001);
    float x = dot(p - fold, dir);
    float2 base = p - dir * x;

    // Past the roll: the leaf has left this point. Its shadow falls on the page beneath, darkest by the roll.
    if (x > r) {
        float d = x - r;
        float a = 0.30 * exp(-d / (r * 1.4 + 10.0));
        return half4(0.0, 0.0, 0.0, half(a));
    }

    // The back, on top: on the upper half of the roll (0 ≤ x ≤ r) or lying flat beyond it (x < 0).
    float arcBack = x >= 0.0 ? PI * r - r * asin(clamp(x / r, -1.0, 1.0)) : PI * r - x;
    float2 sBack = base + dir * arcBack;
    if (curlInLeaf(sBack, size, spine)) {
        half4 c = curlSample(layer, float2(2.0 * spine - sBack.x, sBack.y), size, mirror);
        // Lit from above: the roll's crest is brightest, its sides fall away; the flat back is a touch darker
        // than the page it will become, the light of a sheet held up.
        float shade = 0.94;
        if (x >= 0.0) {
            float t = x / r;
            shade = 0.80 + 0.20 * sqrt(max(0.0, 1.0 - t * t));
        }
        c.rgb *= half(shade);
        // A thin bright line along the rolled edge.
        if (x >= 0.0 && x > r * 0.86) { c.rgb = min(half3(1.0), c.rgb + half3(0.05)); }
        return c;
    }

    // The front, on the lower half of the roll: it turns away from the light as it rises.
    if (x >= 0.0) {
        float arcFront = r * asin(clamp(x / r, -1.0, 1.0));
        float2 sFront = base + dir * arcFront;
        if (curlInLeaf(sFront, size, spine)) {
            half4 c = curlSample(layer, sFront, size, mirror);
            float t = x / r;
            c.rgb *= half(1.0 - 0.38 * t * t);
            return c;
        }
        return half4(0.0);
    }

    // The front, still flat: the page as it was, shaded a little where the roll hangs over it.
    if (curlInLeaf(p, size, spine)) {
        half4 c = curlSample(layer, p, size, mirror);
        c.rgb *= half(1.0 - 0.16 * exp(x / (r * 0.9 + 6.0)));
        return c;
    }
    return half4(0.0);
}
