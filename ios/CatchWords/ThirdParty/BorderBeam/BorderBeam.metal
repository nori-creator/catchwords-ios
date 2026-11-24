//  Vendored from https://github.com/ismnoiet/border-beam-ios at a11d1b938b1cc8efad02e942f7590a0156bbd7da
//  (MIT, full text in BorderBeamLicense.swift). CatchWords changes: the shader is read from the app's own
//  Metal library (ShaderLibrary.default) and Reduce Motion follows the app's setting (\.appReduceMotion).
//
//
//  BorderBeam.metal
//  Author: ismnoiet
//
//  One GPU pass draws the whole beam (crisp edge + soft glow) for a rounded-rect / capsule / circle.
//  Used through SwiftUI's `colorEffect`, so there are no blur layers and no per-frame gradient rebuilds.
//
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Signed distance to a rounded box centred at the origin (negative inside).
static float sdRoundedBox(float2 p, float2 hs, float r) {
    float2 q = abs(p) - (hs - r);
    return length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

// Position along the border, measured clockwise from the right-edge midpoint, as 0...1.
// Using distance ALONG the edge (not the angle around the centre) keeps the beam's ends
// perpendicular to the border, so the glow never fans out toward the centre.
static float perimeterParam(float2 p, float2 hs, float r) {
    float2 ih = max(hs - r, float2(0.0));
    float q = M_PI_F * r * 0.5;                       // one corner arc
    float L = 4.0 * ih.x + 4.0 * ih.y + 4.0 * q;
    float baseBL = ih.y + q + 2.0 * ih.x;             // bottom-left corner start
    float baseL  = baseBL + q;                        // left edge start
    float baseTL = baseL + 2.0 * ih.y;                // top-left corner start
    float baseTR = baseTL + q + 2.0 * ih.x;           // top-right corner start
    float2 ap = abs(p);
    float s;
    if (ap.x > ih.x && ap.y > ih.y) {
        // corner: angle measured from the horizontal axis through the arc's centre
        float2 v = ap - ih;
        float ang = atan2(v.y, v.x);                  // 0 ... pi/2
        if (p.x >= 0.0 && p.y >= 0.0)      { s = ih.y + r * ang; }                    // bottom-right
        else if (p.x < 0.0 && p.y >= 0.0)  { s = baseBL + r * (M_PI_F * 0.5 - ang); } // bottom-left
        else if (p.x < 0.0)                { s = baseTL + r * ang; }                  // top-left
        else                               { s = baseTR + r * (M_PI_F * 0.5 - ang); } // top-right
    } else if ((hs.x - ap.x) < (hs.y - ap.y)) {
        // left / right edge
        if (p.x >= 0.0) { s = p.y >= 0.0 ? p.y : L + p.y; }
        else            { s = baseL + (ih.y - p.y); }
    } else {
        // top / bottom edge
        if (p.y >= 0.0) { s = ih.y + q + (ih.x - p.x); }
        else            { s = baseTL + q + (p.x + ih.x); }
    }
    return fract(s / max(L, 0.001));
}

// Linear blend across the packed RGBA palette. t in 0...1.
static float4 samplePalette(device const float *c, int floatCount, float t) {
    int n = floatCount / 4;                 // SwiftUI passes the number of floats (RGBA = 4 per color)
    if (n <= 0) { return float4(1.0); }
    if (n == 1) { return float4(c[0], c[1], c[2], c[3]); }
    float x = clamp(t, 0.0, 1.0) * float(n - 1);
    int i = min(int(floor(x)), n - 2);
    float f = x - float(i);
    float4 a = float4(c[i * 4], c[i * 4 + 1], c[i * 4 + 2], c[i * 4 + 3]);
    float4 b = float4(c[(i + 1) * 4], c[(i + 1) * 4 + 1], c[(i + 1) * 4 + 2], c[(i + 1) * 4 + 3]);
    return mix(a, b, f);
}

// Inverse of perimeterParam: the point on the border at distance `s` (points), clockwise from
// the right-edge midpoint.
static float2 boundaryPoint(float s, float2 hs, float r) {
    float2 ih = max(hs - r, float2(0.0));
    float q = M_PI_F * r * 0.5;
    float L = 4.0 * ih.x + 4.0 * ih.y + 4.0 * q;
    s = s - L * floor(s / max(L, 0.001));
    float l;
    l = ih.y;       if (s < l) { return float2(hs.x, s); }                                   s -= l;
    l = q;          if (s < l) { float a = s / r;                    return float2( ih.x,  ih.y) + r * float2(cos(a), sin(a)); } s -= l;
    l = 2.0 * ih.x; if (s < l) { return float2(ih.x - s, hs.y); }                            s -= l;
    l = q;          if (s < l) { float a = M_PI_F * 0.5 + s / r;     return float2(-ih.x,  ih.y) + r * float2(cos(a), sin(a)); } s -= l;
    l = 2.0 * ih.y; if (s < l) { return float2(-hs.x, ih.y - s); }                           s -= l;
    l = q;          if (s < l) { float a = M_PI_F + s / r;           return float2(-ih.x, -ih.y) + r * float2(cos(a), sin(a)); } s -= l;
    l = 2.0 * ih.x; if (s < l) { return float2(-ih.x + s, -hs.y); }                          s -= l;
    l = q;          if (s < l) { float a = M_PI_F * 1.5 + s / r;     return float2( ih.x, -ih.y) + r * float2(cos(a), sin(a)); } s -= l;
    return float2(hs.x, -ih.y + s);
}

// Soft glow of the orbiting beam = a chain of round Gaussian blobs laid along the beam's path on
// the border (like blurring a stroke). It never asks "which edge is nearest", so it cannot make
// seams, triangles or inset rectangles, and corners come out naturally round on any shape.
// Returns premultiplied rgb + brightness, with a peak of about 1 on the border.
static float4 orbitGlowBlobs(float2 p, float dist, float2 hs, float r, float phase, float direction,
                             float arc, float sigmaBase, device const float *colors, int count) {
    float2 ih = max(hs - r, float2(0.0));
    float q = M_PI_F * r * 0.5;
    float L = 4.0 * ih.x + 4.0 * ih.y + 4.0 * q;

    const int K = 24;
    float delta = arc * L / float(K);                 // spacing between blobs along the border
    float sigma = max(sigmaBase, 0.8 * delta);        // keep blobs overlapping so there is no beading
    if (dist > 3.0 * sigma) { return float4(0.0); }   // far from the border: nothing to draw
    float inv2s2 = 0.5 / (sigma * sigma);
    float norm = delta / (sigma * 2.50663);           // makes the summed peak ~1 along the beam

    float start = 1.0 - arc;
    float4 acc = float4(0.0);
    for (int k = 0; k < K; k++) {
        float t = (float(k) + 0.5) / float(K);        // 0 = tail ... 1 = head
        float sp = fract(start + t * arc + direction * phase);
        float2 pt = boundaryPoint(sp * L, hs, r);
        float2 dv = p - pt;
        float g = exp(-dot(dv, dv) * inv2s2);
        if (g < 0.003) { continue; }
        float bell = pow(sin(M_PI_F * t), 1.6);       // lighter toward both ends
        float4 c4 = samplePalette(colors, count, t);
        float v = g * norm * bell * clamp(c4.a, 0.0, 1.0);
        acc += float4(c4.rgb * v, v);
    }
    return acc;
}

[[ stitchable ]] half4 borderBeam(
    float2 position,
    half4 inColor,
    float2 size,          // view size in points
    float cornerRadius,   // clamped to half the shortest side (capsule / circle pass a huge value)
    float phase,          // 0...1, loops
    float direction,      // +1 clockwise (left to right on top), -1 counter-clockwise
    float mode,           // 0 = orbit the border, 1 = sweep along one edge
    float side,           // mode 1: 1 top, 2 bottom, 3 left, 4 right
    float arc,            // mode 0: length of the comet (fraction of the lap)
    float glow,           // soft inner glow reach in points
    float intensity,      // overall brightness 0...1
    device const float *colors,
    int count
) {
    float2 hs = size * 0.5;
    float r = min(cornerRadius, min(hs.x, hs.y));
    float2 p = position - hs;
    float dist = -sdRoundedBox(p, hs, r);        // points inside the shape, measured from the edge
    if (dist < 0.0) { return half4(0.0); }

    float4 acc = float4(0.0);                    // premultiplied rgb + weight, summed over layers

    if (mode < 0.5) {
        // --- crisp line + tight halo, hugging the edge (nearest-edge param is fine this close) ---
        float a = perimeterParam(p, hs, r);
        float tt = (fract(a - direction * phase) - (1.0 - arc)) / arc;
        if (tt >= 0.0) {
            // bell shape: brightest around the middle of the beam, lighter toward both ends
            float profile = pow(sin(M_PI_F * clamp(tt, 0.0, 1.0)), 1.2);
            float crisp = 1.0 - smoothstep(0.5, 2.25, dist);
            float halo = 0.6 * exp(-dist / max(glow * 0.1, 0.6));
            float4 c4 = samplePalette(colors, count, tt);
            float w = (crisp + halo) * profile * clamp(c4.a, 0.0, 1.0);
            acc += float4(c4.rgb * w, w);
        }
        // --- wide soft glow: chain of blobs along the beam ---
        acc += 0.55 * orbitGlowBlobs(p, dist, hs, r, phase, direction, arc,
                                     max(glow, 0.001) * 0.7, colors, count);
    } else {
        // --- edge sweep: ping-pong along one side with ease in/out ---
        float u;
        float edgeDist;
        int s = int(side + 0.5);
        if (s == 1)      { u = position.x / size.x; edgeDist = position.y; }
        else if (s == 2) { u = position.x / size.x; edgeDist = size.y - position.y; }
        else if (s == 3) { u = position.y / size.y; edgeDist = position.x; }
        else             { u = position.y / size.y; edgeDist = size.x - position.x; }

        float len = 0.28;
        float tri = phase < 0.5 ? phase * 2.0 : (1.0 - phase) * 2.0;
        float eased = tri * tri * (3.0 - 2.0 * tri);
        float c = len * 0.5 + (1.0 - len) * eased;
        float k = (u - (c - len * 0.5)) / len;
        if (k < 0.0 || k > 1.0) { return half4(0.0); }
        float tp = 1.0 - abs(2.0 * k - 1.0);
        float profile = tp * tp * (3.0 - 2.0 * tp);
        float4 c4 = samplePalette(colors, count, k);

        float crisp = 1.0 - smoothstep(0.5, 2.25, edgeDist);
        float halo = 0.8 * exp(-edgeDist / max(glow * 0.2, 0.5));
        float wide = 0.6 * exp(-pow(edgeDist / max(glow, 0.001), 1.4));
        float w = ((crisp + halo) * profile + wide * profile) * clamp(c4.a, 0.0, 1.0);
        acc += float4(c4.rgb * w, w);
    }

    float total = acc.a;
    if (total <= 0.0001) { return half4(0.0); }
    float3 rgb = acc.rgb / total;                // average color of everything contributing here
    float a = clamp(total * intensity, 0.0, 1.0);
    return half4(half3(rgb) * half(a), half(a)); // premultiplied
}
